--!strict
-- PlayerDataService: loads, caches, saves, and replicates each player's profile.
--
-- M2: DataStore-backed persistence with:
--   * pcall + retries around every DataStore call (network can fail),
--   * a session lock so two servers never edit the same player at once
--     (that's what causes progress rollbacks and item duplication),
--   * periodic autosave, plus a save on player-leave and on server-shutdown,
--   * a "never overwrite good data with a fallback" guard when a load fails.
--
-- The public API (Get / PushState / AddClippings / Spend) is unchanged, so the
-- rest of the game keeps working exactly as before.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

local PlayerDataService = {}

export type Profile = {
	version: number,
	clippings: number, -- what's currently in the carry BAG (unbanked)
	gold: number, -- banked, spendable currency
	diamonds: number, -- rare premium currency
	bagTier: number, -- index into GameConfig.BAG_TIERS
	totalBladesCut: number,
	toolTier: number,
	skills: { [string]: number },
	zones: { [string]: { tilesCut: number, restored: boolean } },
	prestige: number,
}

-- What we actually store: the profile plus a lightweight session lock.
type StoredData = {
	data: Profile?,
	lockJobId: string?,
	lockTime: number?,
}

local PROFILE_VERSION = 2
local STORE_NAME = "PlayerData_v1" -- bump this name if you ever need a clean wipe
local KEY_PREFIX = "player_"
local AUTOSAVE_INTERVAL = 120 -- seconds between background autosaves
local LOAD_RETRIES = 5
local LOCK_RETRY_DELAY = 4 -- wait between attempts when another session holds the lock
local SAVE_RETRIES = 4
local SAVE_RETRY_DELAY = 3
local STALE_LOCK_SECONDS = 1200 -- a lock older than this is treated as abandoned

local store: DataStore? = nil
local dataStoreReady = false
local jobId = game.JobId ~= "" and game.JobId or "studio"

local profiles: { [Player]: Profile } = {}
local canSave: { [Player]: boolean } = {} -- false if the load failed (protects real data)
local loading: { [Player]: boolean } = {}

local function defaultProfile(): Profile
	return {
		version = PROFILE_VERSION,
		clippings = 0,
		gold = 0,
		diamonds = 0,
		bagTier = 1,
		totalBladesCut = 0,
		toolTier = 1,
		skills = {},
		zones = {},
		prestige = 0,
	}
end

-- Fill in any fields missing from an older save so the schema can grow safely.
local function reconcile(profile: Profile): Profile
	local incoming = (profile :: any).version or 1
	local base = defaultProfile()
	for key, value in base :: any do
		if (profile :: any)[key] == nil then
			(profile :: any)[key] = value
		end
	end
	-- v1 -> v2: clippings USED to be the spendable currency. Under the new economy
	-- clippings are just what's in your carry bag, and GOLD is what you bank/spend.
	-- Preserve old progress by moving banked clippings into gold and starting the
	-- (new) carry bag empty.
	if incoming < 2 then
		profile.gold = (profile.gold or 0) + (profile.clippings or 0)
		profile.clippings = 0
	end
	profile.version = PROFILE_VERSION
	return profile
end

local function keyFor(player: Player): string
	return KEY_PREFIX .. player.UserId
end

-- Read the stored profile and take the session lock in one atomic UpdateAsync.
-- Returns (ok, profile?, lockedByOther).
local function tryAcquire(player: Player): (boolean, Profile?, boolean)
	local ds = store
	if not ds then
		return false, nil, false
	end
	local lockedByOther = false
	local stored: StoredData? = nil
	local ok, err = pcall(function()
		ds:UpdateAsync(keyFor(player), function(raw: StoredData?): StoredData?
			local current: StoredData = raw or {}
			local now = os.time()
			-- Another live session holds a fresh lock -> leave it alone.
			if current.lockJobId
				and current.lockJobId ~= jobId
				and current.lockTime
				and (now - current.lockTime) < STALE_LOCK_SECONDS
			then
				lockedByOther = true
				stored = current
				return nil -- cancel the write; keep their lock
			end
			-- Acquire (or refresh) the lock for this server.
			current.lockJobId = jobId
			current.lockTime = now
			stored = current
			return current
		end)
	end)
	if not ok then
		warn(`[PlayerDataService] Load error for {player.Name}: {err}`)
		return false, nil, false
	end
	if lockedByOther then
		return false, nil, true
	end
	return true, stored and stored.data, false
end

-- Returns (profile, loadedCleanly). When loadedCleanly is false we must NOT save,
-- so a temporary fallback profile can never clobber the player's real data.
local function loadProfile(player: Player): (Profile, boolean)
	if not dataStoreReady then
		return defaultProfile(), false
	end
	for attempt = 1, LOAD_RETRIES do
		local ok, profile, lockedByOther = tryAcquire(player)
		if ok then
			if profile then
				return reconcile(profile), true
			end
			return defaultProfile(), true -- brand-new player
		end
		if lockedByOther then
			warn(`[PlayerDataService] {player.Name} locked by another session; retry {attempt}/{LOAD_RETRIES}`)
			task.wait(LOCK_RETRY_DELAY)
		else
			-- Hard error (network, or Studio API access disabled). Try once more
			-- quickly, then give up so testing isn't blocked for 20+ seconds.
			if attempt >= 2 then
				break
			end
			task.wait(1)
		end
	end
	warn(`[PlayerDataService] Could not load {player.Name}; using a TEMPORARY profile (will not save).`)
	return defaultProfile(), false
end

-- Writes the cached profile back. If releaseLock is true, also frees the session
-- lock (used on leave / shutdown). Returns true on success.
local function saveProfile(player: Player, releaseLock: boolean): boolean
	local ds = store
	local profile = profiles[player]
	if not profile or canSave[player] == false or not ds then
		return false
	end
	for attempt = 1, SAVE_RETRIES do
		local ok, err = pcall(function()
			ds:UpdateAsync(keyFor(player), function(raw: StoredData?): StoredData?
				local current: StoredData = raw or {}
				-- If another server has taken over this player, don't overwrite.
				if current.lockJobId and current.lockJobId ~= jobId then
					return nil
				end
				current.data = profile
				if releaseLock then
					current.lockJobId = nil
					current.lockTime = nil
				else
					current.lockJobId = jobId
					current.lockTime = os.time()
				end
				return current
			end)
		end)
		if ok then
			return true
		end
		warn(`[PlayerDataService] Save error for {player.Name} (attempt {attempt}/{SAVE_RETRIES}): {err}`)
		task.wait(SAVE_RETRY_DELAY)
	end
	warn(`[PlayerDataService] FAILED to save {player.Name} after {SAVE_RETRIES} attempts.`)
	return false
end

-- ---------------------------------------------------------------------------
-- Public API (unchanged signatures)
-- ---------------------------------------------------------------------------

function PlayerDataService.Get(player: Player): Profile?
	return profiles[player]
end

-- Send the client a fresh snapshot of everything it needs to render UI/stats.
function PlayerDataService.PushState(player: Player)
	local profile = profiles[player]
	if not profile then
		return
	end
	Remotes.Get("StateChanged"):FireClient(player, {
		clippings = profile.clippings,
		gold = profile.gold,
		diamonds = profile.diamonds,
		bagTier = profile.bagTier,
		bagCapacity = PlayerDataService.GetBagCapacity(profile),
		totalBladesCut = profile.totalBladesCut,
		toolTier = profile.toolTier,
		skills = profile.skills,
	})
end

-- Clipping bag capacity for the player's current bag tier.
function PlayerDataService.GetBagCapacity(profile: Profile): number
	local tier = GameConfig.BAG_TIERS[profile.bagTier] or GameConfig.BAG_TIERS[1]
	return tier.capacity
end

function PlayerDataService.IsBagFull(player: Player): boolean
	local profile = profiles[player]
	if not profile then
		return false
	end
	return profile.clippings >= PlayerDataService.GetBagCapacity(profile)
end

-- Add mown clippings to the carry bag, never exceeding its capacity. Returns how
-- many were actually stored (0 if the bag was already full).
function PlayerDataService.AddClippings(player: Player, amount: number): number
	local profile = profiles[player]
	if not profile then
		return 0
	end
	local capacity = PlayerDataService.GetBagCapacity(profile)
	local space = math.max(0, capacity - profile.clippings)
	local added = math.min(space, amount)
	if added > 0 then
		profile.clippings += added
		PlayerDataService.PushState(player)
	end
	return added
end

-- Bank the whole bag: clippings -> gold (plus a rare diamond roll), bag emptied.
-- Returns a summary for the deposit banner.
function PlayerDataService.Deposit(player: Player): { clippings: number, gold: number, diamonds: number }
	local profile = profiles[player]
	if not profile or profile.clippings <= 0 then
		return { clippings = 0, gold = 0, diamonds = 0 }
	end
	local carried = profile.clippings
	local goldGained = math.floor(carried * GameConfig.CLIPPING_TO_GOLD)
	local diamondsGained = 0
	local rolls = math.floor(carried / GameConfig.DIAMOND_ROLL_PER_CLIPPINGS)
	for _ = 1, rolls do
		if math.random() < GameConfig.DIAMOND_CHANCE then
			diamondsGained += 1
		end
	end
	profile.clippings = 0
	profile.gold += goldGained
	profile.diamonds += diamondsGained
	PlayerDataService.PushState(player)
	return { clippings = carried, gold = goldGained, diamonds = diamondsGained }
end

-- Returns true and deducts GOLD if the player can afford it; false otherwise.
function PlayerDataService.SpendGold(player: Player, amount: number): boolean
	local profile = profiles[player]
	if not profile or profile.gold < amount then
		return false
	end
	profile.gold -= amount
	return true
end

-- Legacy clipping spend (kept for compatibility; upgrades now use SpendGold).
function PlayerDataService.Spend(player: Player, amount: number): boolean
	local profile = profiles[player]
	if not profile or profile.clippings < amount then
		return false
	end
	profile.clippings -= amount
	return true
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

local function onPlayerRemoving(player: Player)
	if profiles[player] then
		saveProfile(player, true) -- final save + release the lock
	end
	profiles[player] = nil
	canSave[player] = nil
	loading[player] = nil
end

local function onPlayerAdded(player: Player)
	if profiles[player] or loading[player] then
		return
	end
	loading[player] = true

	local profile, loadedCleanly = loadProfile(player)
	loading[player] = nil

	profiles[player] = profile
	canSave[player] = loadedCleanly

	-- If they left mid-load, finalize immediately and clean up.
	if not player.Parent then
		onPlayerRemoving(player)
		return
	end

	print(`[PlayerDataService] Profile ready for {player.Name} (loaded={loadedCleanly})`)
	PlayerDataService.PushState(player)
end

function PlayerDataService.Init()
	-- Acquire the DataStore safely. In an unpublished place (or with Studio API
	-- access turned off) GetDataStore THROWS, which previously crashed this whole
	-- module and took every service that depends on it down with it. Guard it so the
	-- game still runs; progress just won't persist until the place is published and
	-- Studio Access to API Services is enabled.
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		store = result
		dataStoreReady = true
	else
		warn(`[PlayerDataService] DataStore unavailable - progress will NOT save this session.`)
		warn(`[PlayerDataService] Publish the place and enable Studio Access to API Services to turn saving on. ({result})`)
	end

	-- Handle any players who joined before this connected (e.g. Studio playtest).
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	-- Client asks for a snapshot once its UI is ready.
	Remotes.Get("RequestState").OnServerEvent:Connect(function(player: Player)
		PlayerDataService.PushState(player)
	end)

	-- Final safety net: save everyone still in-game when the server shuts down.
	game:BindToClose(function()
		local remaining = 0
		for _, player in Players:GetPlayers() do
			if profiles[player] then
				remaining += 1
				task.spawn(function()
					saveProfile(player, true)
					remaining -= 1
				end)
			end
		end
		local deadline = os.clock() + 25
		while remaining > 0 and os.clock() < deadline do
			task.wait(0.2)
		end
	end)
end

function PlayerDataService.Start()
	-- Background autosave loop. Spread saves out to respect DataStore budgets.
	while true do
		task.wait(AUTOSAVE_INTERVAL)
		for _, player in Players:GetPlayers() do
			if profiles[player] then
				saveProfile(player, false)
				task.wait(1)
			end
		end
	end
end

return PlayerDataService
