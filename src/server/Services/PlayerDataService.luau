--!strict
-- PlayerDataService: loads, caches, and (in M2) saves each player's profile.
-- Also replicates state snapshots to the owning client via the StateChanged remote.
-- M1: in-memory only. M2: replaced with DataStore-backed persistence.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)

local PlayerDataService = {}

export type Profile = {
	version: number,
	clippings: number,
	totalBladesCut: number,
	toolTier: number,
	skills: { [string]: number },
	zones: { [string]: { tilesCut: number, restored: boolean } },
	prestige: number,
}

local profiles: { [Player]: Profile } = {}

local function defaultProfile(): Profile
	return {
		version = 1,
		clippings = 0,
		totalBladesCut = 0,
		toolTier = 1,
		skills = {},
		zones = {},
		prestige = 0,
	}
end

function PlayerDataService.Get(player: Player): Profile?
	return profiles[player]
end

-- Send the client a fresh snapshot of everything it needs to render UI/stats
function PlayerDataService.PushState(player: Player)
	local profile = profiles[player]
	if not profile then
		return
	end
	Remotes.Get("StateChanged"):FireClient(player, {
		clippings = profile.clippings,
		totalBladesCut = profile.totalBladesCut,
		toolTier = profile.toolTier,
		skills = profile.skills,
	})
end

function PlayerDataService.AddClippings(player: Player, amount: number)
	local profile = profiles[player]
	if not profile then
		return
	end
	profile.clippings += amount
	PlayerDataService.PushState(player)
end

-- Returns true and deducts if the player can afford it; false otherwise
function PlayerDataService.Spend(player: Player, amount: number): boolean
	local profile = profiles[player]
	if not profile or profile.clippings < amount then
		return false
	end
	profile.clippings -= amount
	return true
end

local function onPlayerAdded(player: Player)
	-- TODO(M2): load from DataStore with session locking
	if not profiles[player] then
		profiles[player] = defaultProfile()
		print(`[PlayerDataService] Profile ready for {player.Name}`)
	end
end

function PlayerDataService.Init()
	-- Handle any players who joined before this connected (e.g. Studio playtest)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end

	Players.PlayerAdded:Connect(onPlayerAdded)

	Players.PlayerRemoving:Connect(function(player: Player)
		-- TODO(M2): save to DataStore
		profiles[player] = nil
	end)

	-- Client asks for a snapshot once its UI is ready
	Remotes.Get("RequestState").OnServerEvent:Connect(function(player: Player)
		PlayerDataService.PushState(player)
	end)
end

return PlayerDataService
