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
	bagTier: number, -- LEGACY (pre-v4 bag ladder); superseded by `backpacks`
	backpacks: {
		owned: { [string]: boolean }, -- pack key -> purchased
		level: { [string]: number }, -- pack key -> capacity level (1-based)
		autoDeposit: { [string]: boolean }, -- pack key -> banks itself when full
		equipped: string, -- pack key currently worn; decides carry capacity
	},
	totalBladesCut: number,
	toolTier: number,
	skills: { [string]: number },
	zones: { [string]: { tilesCut: number, restored: boolean } },
	prestige: number,
	swords: {
		owned: { [string]: boolean },
		level: { [string]: number },
		equipped: string?,
	},
	essence: { [string]: number },
	bosses: {
		kills: { [string]: number }, -- boss key -> lifetime defeats
		trophies: { [string]: boolean }, -- zone -> first-kill quest trophy claimed
		crowns: { [string]: boolean }, -- zone -> champion quest crown claimed
	},
	quests: {
		progress: { [string]: number }, -- questId (as string) -> current progress
		claimed: { [string]: boolean }, -- questId (as string) -> reward claimed
		reached: { [string]: boolean }, -- grass type -> has the player mown it (zone unlock)
	},
	autoMowers: {
		owned: { [string]: boolean }, -- mower key -> purchased
		deployed: { [string]: boolean }, -- mower key -> currently out working
	},
	pets: {
		owned: { [string]: { level: number, xp: number, golden: boolean, shards: number, rank: number } },
		equipped: { string }, -- ordered, unique pet keys; maximum comes from GameConfig
	},
	petRewards: {
		lastFreeSpin: number,
		wheelPity: number,
		cratePity: number,
		totalSpins: number,
		totalCrates: number,
	},
	villagers: {
		rescued: { [string]: boolean },
		features: { [string]: boolean },
	},
}

-- What we actually store: the profile plus a lightweight session lock.
type StoredData = {
	data: Profile?,
	lockJobId: string?,
	lockTime: number?,
}

local PROFILE_VERSION = 10
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

-- The first pack in config is the one everybody starts with, so this never drifts
-- out of step with GameConfig.
local function startingPackKey(): string
	local first = GameConfig.BACKPACKS and GameConfig.BACKPACKS[1]
	return if first then first.key else "basket"
end

local function defaultProfile(): Profile
	return {
		version = PROFILE_VERSION,
		clippings = 0,
		gold = 0,
		diamonds = 0,
		bagTier = 1,
		backpacks = {
			owned = { [startingPackKey()] = true },
			level = { [startingPackKey()] = 1 },
			autoDeposit = {},
			equipped = startingPackKey(),
		},
		totalBladesCut = 0,
		toolTier = 1,
		skills = {},
		zones = {},
		prestige = 0,
		quests = { progress = {}, claimed = {}, reached = {} },
		autoMowers = { owned = {}, deployed = {} },
		swords = { owned = {}, level = {}, equipped = nil },
		essence = {},
		bosses = { kills = {}, trophies = {}, crowns = {} },
		pets = { owned = {}, equipped = {} },
		petRewards = { lastFreeSpin = 0, wheelPity = 0, cratePity = 0, totalSpins = 0, totalCrates = 0 },
		villagers = { rescued = {}, features = {} },
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
	-- v2 -> v3: added the autoMowers block. No data conversion is needed -- the
	-- field-fill loop above already grafts the empty default onto older saves.
	--
	-- v3 -> v4: the single upgradeable bag became five per-zone backpacks. An old
	-- save carries a bagTier of 1-5, which we honour by granting that many packs at
	-- level 1 and equipping the best of them. That is generous -- the packs cost far
	-- more gold than the old tiers did -- but the alternative is cutting a tier-5
	-- player from 1,000 capacity down to 25, and silently shrinking someone's bag is
	-- much worse than handing out a head start. bagTier itself is left untouched.
	if incoming < 4 then
		local packs = GameConfig.BACKPACKS or {}
		local b = profile.backpacks
		local earned = math.clamp(profile.bagTier or 1, 1, #packs)
		for i = 1, earned do
			local def = packs[i]
			if def then
				b.owned[def.key] = true
				b.level[def.key] = b.level[def.key] or 1
				b.equipped = def.key
			end
		end
	end
	-- v4 -> v5: the ring 3/4 zone keys were renamed to end the long-standing split
	-- between the code and the design docs:
	--     "Moss"  -> "Mossmire"  (ring 3)
	--     "Thick" -> "Thicket"   (ring 4)
	-- `quests.reached` is keyed by grass/zone key and IS persisted, so without this
	-- remap every existing player would silently lose their ring 3 and ring 4
	-- unlocks -- which also re-locks those zones' quests, backpacks and auto-mowers,
	-- since all three gate on quests.reached. `zones` is remapped for the same
	-- reason. Old keys are copied, not moved, only if the new key is absent, so
	-- running this twice is harmless.
	if incoming < 5 then
		local RENAMES = { Moss = "Mossmire", Thick = "Thicket" }
		local reached = profile.quests and profile.quests.reached
		for oldKey, newKey in RENAMES do
			if reached and reached[oldKey] ~= nil then
				if reached[newKey] == nil then
					reached[newKey] = reached[oldKey]
				end
				reached[oldKey] = nil
			end
			local zones = profile.zones
			if zones and zones[oldKey] ~= nil then
				if zones[newKey] == nil then
					zones[newKey] = zones[oldKey]
				end
				zones[oldKey] = nil
			end
		end
	end
	-- v6 -> v7: persistent boss kills and claimed boss collectibles. Keep this
	-- nested reconciliation unconditional so partially written/future profiles heal.
	profile.bosses = profile.bosses or { kills = {}, trophies = {}, crowns = {} }
	profile.bosses.kills = profile.bosses.kills or {}
	profile.bosses.trophies = profile.bosses.trophies or {}
	profile.bosses.crowns = profile.bosses.crowns or {}
	-- v7 -> v8: complete pet ownership/loadout/level data. Keep the nested repair
	-- unconditional so partial Studio saves and future wheel/shard fields self-heal.
	profile.pets = profile.pets or { owned = {}, equipped = {} }
	profile.pets.owned = profile.pets.owned or {}
	profile.pets.equipped = profile.pets.equipped or {}
	for key, data in profile.pets.owned do
		if type(data) ~= "table" then
			profile.pets.owned[key] = { level = 1, xp = 0, golden = false, shards = 0, rank = 1 }
		else
			data.level = math.max(1, tonumber(data.level) or 1)
			data.xp = math.max(0, tonumber(data.xp) or 0)
			data.golden = data.golden == true
			data.shards = math.max(0, tonumber(data.shards) or 0)
			data.rank = math.clamp(math.floor(tonumber(data.rank) or 1), 1, (GameConfig.PET_SYSTEM and GameConfig.PET_SYSTEM.maxRank) or 5)
		end
	end
	-- v8 -> v9: persistent daily wheel, both pity counters, lifetime opens,
	-- and shard ranks. Nested repair is unconditional for partial Studio saves.
	profile.petRewards = profile.petRewards or {}
	profile.petRewards.lastFreeSpin = math.max(0, tonumber(profile.petRewards.lastFreeSpin) or 0)
	profile.petRewards.wheelPity = math.max(0, math.floor(tonumber(profile.petRewards.wheelPity) or 0))
	profile.petRewards.cratePity = math.max(0, math.floor(tonumber(profile.petRewards.cratePity) or 0))
	profile.petRewards.totalSpins = math.max(0, math.floor(tonumber(profile.petRewards.totalSpins) or 0))
	profile.petRewards.totalCrates = math.max(0, math.floor(tonumber(profile.petRewards.totalCrates) or 0))
	-- v9 -> v10: rescued neighbors and unlocked permanent side features.
	profile.villagers = profile.villagers or { rescued = {}, features = {} }
	profile.villagers.rescued = profile.villagers.rescued or {}
	profile.villagers.features = profile.villagers.features or {}
	for _, def in ipairs(GameConfig.VILLAGERS or {}) do
		if profile.villagers.rescued[def.key] then
			profile.villagers.features[def.feature] = true
		end
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

local function petDef(key: string): any?
	for _, def in ipairs(GameConfig.PETS or {}) do
		if def.key == key then
			return def
		end
	end
	return nil
end

-- Aggregate only equipped, owned, unique pets. All consumers call this on the
-- server, so clients can never forge a level or stat multiplier.
function PlayerDataService.GetPetBonuses(profile: Profile): { [string]: number }
	local totals: { [string]: number } = {}
	local pets = profile.pets
	if not pets then
		return totals
	end
	local seen: { [string]: boolean } = {}
	local maxEquipped = (GameConfig.PET_SYSTEM and GameConfig.PET_SYSTEM.maxEquipped) or 3
	for index, key in ipairs(pets.equipped or {}) do
		if index > maxEquipped then
			break
		end
		local data = pets.owned[key]
		local def = not seen[key] and data and petDef(key) or nil
		if def then
			seen[key] = true
			local growth = (GameConfig.PET_SYSTEM and GameConfig.PET_SYSTEM.levelBonusGrowth) or 0.04
			local levelScale = 1 + math.max(0, (data.level or 1) - 1) * growth
			local goldenScale = if data.golden then ((GameConfig.PET_SYSTEM and GameConfig.PET_SYSTEM.goldenBonusMultiplier) or 1.5) else 1
			local rankScale = 1 + math.max(0, (data.rank or 1) - 1) * ((GameConfig.PET_SYSTEM and GameConfig.PET_SYSTEM.rankBonusGrowth) or 0.15)
			for stat, amount in def.bonuses or {} do
				totals[stat] = (totals[stat] or 0) + amount * levelScale * goldenScale * rankScale
			end
		end
	end
	return totals
end

function PlayerDataService.GetPetBonus(profile: Profile, stat: string): number
	return PlayerDataService.GetPetBonuses(profile)[stat] or 0
end

function PlayerDataService.GetVillagerBonuses(profile: Profile): { [string]: number }
	local totals: { [string]: number } = {}
	local rescued = profile.villagers and profile.villagers.rescued
	if not rescued then
		return totals
	end
	for _, def in ipairs(GameConfig.VILLAGERS or {}) do
		if rescued[def.key] then
			for stat, amount in def.bonus or {} do
				totals[stat] = (totals[stat] or 0) + amount
			end
		end
	end
	return totals
end

function PlayerDataService.GetVillagerBonus(profile: Profile, stat: string): number
	return PlayerDataService.GetVillagerBonuses(profile)[stat] or 0
end

-- Send the client a fresh snapshot of everything it needs to render UI/stats.
function PlayerDataService.PushState(player: Player)
	local profile = profiles[player]
	if not profile then
		return
	end
	local packDef, packLevel = PlayerDataService.GetEquippedBackpack(profile)
	Remotes.Get("StateChanged"):FireClient(player, {
		clippings = profile.clippings,
		gold = profile.gold,
		diamonds = profile.diamonds,
		bagTier = profile.bagTier,
		bagCapacity = PlayerDataService.GetBagCapacity(profile),
		packKey = profile.backpacks.equipped,
		packName = if packDef then packDef.name else "Backpack",
		packLevel = packLevel,
		packMaxLevel = if packDef then #packDef.levels else 1,
		packAutoDeposit = PlayerDataService.HasAutoDeposit(profile),
		totalBladesCut = profile.totalBladesCut,
		toolTier = profile.toolTier,
		skills = profile.skills,
		essence = table.clone(profile.essence or {}),
		petBonuses = PlayerDataService.GetPetBonuses(profile),
		villagerBonuses = PlayerDataService.GetVillagerBonuses(profile),
		bosses = {
			kills = table.clone(profile.bosses.kills or {}),
			trophies = table.clone(profile.bosses.trophies or {}),
			crowns = table.clone(profile.bosses.crowns or {}),
			allDefeated = PlayerDataService.HasDefeatedAllBosses(profile),
		},
	})
end

-- The definition of the pack a player is wearing, plus its clamped level.
function PlayerDataService.GetEquippedBackpack(profile: Profile): (any?, number)
	local packs = GameConfig.BACKPACKS
	local b = profile.backpacks
	if not packs or not b then
		return nil, 1
	end
	for _, def in ipairs(packs) do
		if def.key == b.equipped then
			local level = math.clamp(b.level[def.key] or 1, 1, #def.levels)
			return def, level
		end
	end
	return nil, 1
end

-- Clipping capacity of the equipped pack at its current level.
function PlayerDataService.GetBagCapacity(profile: Profile): number
	local def, level = PlayerDataService.GetEquippedBackpack(profile)
	if def then
		local baseCapacity = def.levels[level].capacity
		return math.max(1, math.floor(baseCapacity * (1 + PlayerDataService.GetPetBonus(profile, "bagCapacity") + PlayerDataService.GetVillagerBonus(profile, "bagCapacity")) + 0.5))
	end
	-- Pre-v4 fallback, only reachable if the equipped key is missing from config.
	local tier = GameConfig.BAG_TIERS[profile.bagTier] or GameConfig.BAG_TIERS[1]
	return tier.capacity
end

-- Does the worn pack bank a full bag by itself?
function PlayerDataService.HasAutoDeposit(profile: Profile): boolean
	local def = PlayerDataService.GetEquippedBackpack(profile)
	if not def then
		return false
	end
	return profile.backpacks.autoDeposit[def.key] == true
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
	local valueBonus = PlayerDataService.GetPetBonus(profile, "clippingValue") + PlayerDataService.GetVillagerBonus(profile, "clippingValue")
	local goldGained = math.floor(carried * GameConfig.CLIPPING_TO_GOLD * (1 + valueBonus))
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

-- Grant currency directly (quest/boss rewards). Negative values are ignored.
function PlayerDataService.GrantCurrency(player: Player, gold: number, diamonds: number)
	local profile = profiles[player]
	if not profile then
		return
	end
	if gold and gold > 0 then
		profile.gold += gold
	end
	if diamonds and diamonds > 0 then
		profile.diamonds += diamonds
	end
	PlayerDataService.PushState(player)
end

-- Grant a combat essence currency (dropped by monsters). Non-positive ignored.
function PlayerDataService.GrantEssence(player: Player, key: string, amount: number)
	local profile = profiles[player]
	if not profile or not key or not amount or amount <= 0 then
		return
	end
	profile.essence = profile.essence or {}
	profile.essence[key] = (profile.essence[key] or 0) + amount
	PlayerDataService.PushState(player)
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

-- Atomically spend gold, diamonds, and (optionally) one essence currency.
-- Existing two-currency callers can omit the final arguments. No balance changes
-- occur unless the player can afford every component, preventing partial charges.
function PlayerDataService.SpendCurrency(
	player: Player,
	gold: number,
	diamonds: number,
	essenceKey: string?,
	essenceAmount: number?
): boolean
	local profile = profiles[player]
	if not profile then
		return false
	end
	gold = math.max(0, gold or 0)
	diamonds = math.max(0, diamonds or 0)
	essenceAmount = math.max(0, essenceAmount or 0)
	profile.essence = profile.essence or {}
	local essenceBalance = if essenceKey then (profile.essence[essenceKey] or 0) else 0
	if profile.gold < gold
		or profile.diamonds < diamonds
		or (essenceAmount > 0 and (not essenceKey or essenceBalance < essenceAmount))
	then
		return false
	end
	profile.gold -= gold
	profile.diamonds -= diamonds
	if essenceKey and essenceAmount > 0 then
		profile.essence[essenceKey] = essenceBalance - essenceAmount
	end
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


-- Record one authoritative boss defeat. Returns the new lifetime count and whether
-- this was the player's first victory over that boss.
function PlayerDataService.RecordBossDefeat(player: Player, bossKey: string): (number, boolean)
	local profile = profiles[player]
	if not profile then
		return 0, false
	end
	profile.bosses = profile.bosses or { kills = {}, trophies = {}, crowns = {} }
	profile.bosses.kills = profile.bosses.kills or {}
	local previous = profile.bosses.kills[bossKey] or 0
	local count = previous + 1
	profile.bosses.kills[bossKey] = count
	PlayerDataService.PushState(player)
	return count, previous == 0
end

function PlayerDataService.GrantBossCollectible(player: Player, zone: string, kind: string)
	local profile = profiles[player]
	if not profile then
		return
	end
	profile.bosses = profile.bosses or { kills = {}, trophies = {}, crowns = {} }
	profile.bosses.trophies = profile.bosses.trophies or {}
	profile.bosses.crowns = profile.bosses.crowns or {}
	if kind == "trophy" then
		profile.bosses.trophies[zone] = true
	elseif kind == "crown" then
		profile.bosses.crowns[zone] = true
	else
		return
	end
	PlayerDataService.PushState(player)
end

function PlayerDataService.HasDefeatedAllBosses(profile: Profile): boolean
	local kills = profile.bosses and profile.bosses.kills
	if not kills then
		return false
	end
	local total = 0
	for _, def in ipairs(GameConfig.BOSSES or {}) do
		total += 1
		if (kills[def.key] or 0) < 1 then
			return false
		end
	end
	return total > 0
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
