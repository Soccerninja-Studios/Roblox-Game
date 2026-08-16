--!strict
-- Remotes: single place that owns all client<->server RemoteEvents.
-- The server creates the folder on first require; clients wait for it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local REMOTE_NAMES = {
	"RequestCut", -- client -> server: player wants to cut a grass tile
	"PurchaseUpgrade", -- client -> server: buy a tool tier or skill level
	"RequestState", -- client -> server: ask for a fresh state snapshot
	"StateChanged", -- server -> client: full state snapshot (clippings, upgrades)
	"TileCut", -- server -> client: a cut landed (grass burst effect)
	"ClippingCollected", -- server -> client: a dropped clipping was picked up (+N popup)
	"GrassTooTough", -- server -> client: swing bounced off grass too tough for the tool
	"DistrictCleared", -- server -> client: a district was fully mowed (reveal banner)
	-- Economy
	"RequestDeposit", -- client -> server: I stepped onto the Gardener pad; bank my bag
	"Deposited", -- server -> client: deposit summary (clippings, gold, diamonds) for the banner
	"BagFull", -- server -> client: your carry bag is full; go deposit
	-- Quests
	"RequestQuests", -- client -> server: send me my full quest board
	"QuestState", -- server -> client: full quest list with progress + claimed flags
	"ClaimQuest", -- client -> server: claim the reward for a completed quest (id)
	"QuestToast", -- server -> client: a quest was completed/claimed (name, reward) popup
	-- Auto-Mowers
	"RequestAutoMowers", -- client -> server: send me my auto-mower panel state
	"AutoMowerState", -- server -> client: full mower list (owned/deployed/storage) + currency
	"PurchaseAutoMower", -- client -> server: buy the mower with this key
	"ToggleAutoMower", -- client -> server: deploy/recall the mower with this key
	"AutoMowerBanked", -- server -> client: a deployed mower auto-banked gold (toast)
	-- Backpacks (one per zone)
	"RequestBackpacks", -- client -> server: send me my backpack list
	"BackpackState", -- server -> client: all packs (owned/level/autoDeposit) + currency
	"PurchaseBackpack", -- client -> server: buy the pack with this key
	"UpgradeBackpack", -- client -> server: buy the next capacity level, or ("key", "autoDeposit")
	"EquipBackpack", -- client -> server: wear the pack with this key
	-- Admin panel (testers only)
	"AdminGrantCurrency", -- client -> server: grant the caller gold/diamonds (whitelist enforced server-side)
	-- Intro cutscene (client<->server).
	"CutsceneReady", -- client -> server: my camera/UI is ready, start the intro
	"CutsceneSkip", -- client -> server: player pressed Skip
	"CutsceneCamera", -- server -> client: cut the camera to a named shot
	"CutsceneFade", -- server -> client: fade the screen ("out"/"in", seconds)
	"CutscenePose", -- server -> client: play an animation on MY character (poseId, animId)
	"CutscenePoseDone", -- client -> server: that pose finished (poseId)
	-- Combat: swords + monsters
	"RequestSwords",
	"SwordState",
	"PurchaseSword",
	"UpgradeSword",
	"EquipSword",
	"SwordSwing",
	"MonsterHit",
	"MonsterDefeated",
	"PlayerHurt",
	"ClippingsScattered",
	"ClippingsRecovered",
	-- Five-ring bosses
	"RequestBossState", -- client -> server: request every active boss snapshot
	"BossState", -- server -> client: boss spawned/updated/defeated
	"BossDefeated", -- server -> contributing client: authoritative reward summary
	"SwordSpecial", -- server -> client: confirmed special-sword visual
	-- Studio-only boss testing. The server rejects this outside Studio.
	"DebugSpawnBoss", -- client -> server: request a focused Studio boss spawn
	"BossDebugResult", -- server -> client: success/error feedback for that request
}

local Remotes = {}
local known: { [string]: boolean } = {}
for _, name in REMOTE_NAMES do
	known[name] = true
end

-- Do not only create events when the folder is absent. Studio can preserve an
-- older/partial Remotes folder during syncs, which previously made every new
-- Remotes.Get call wait forever. The server now reconciles every event on boot.
if RunService:IsServer() then
	local existing = ReplicatedStorage:FindFirstChild("Remotes")
	local folder: Folder
	if existing and existing:IsA("Folder") then
		folder = existing
	else
		if existing then
			existing:Destroy()
		end
		folder = Instance.new("Folder")
		folder.Name = "Remotes"
		folder.Parent = ReplicatedStorage
	end
	for _, name in REMOTE_NAMES do
		local child = folder:FindFirstChild(name)
		if child and not child:IsA("RemoteEvent") then
			child:Destroy()
			child = nil
		end
		if not child then
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
	end
end

function Remotes.Get(name: string): RemoteEvent
	assert(known[name], string.format("[Remotes] Unknown remote requested: %s", tostring(name)))
	local folder = ReplicatedStorage:WaitForChild("Remotes")
	local remote = folder:WaitForChild(name)
	assert(remote:IsA("RemoteEvent"), string.format("[Remotes] %s is not a RemoteEvent", name))
	return remote
end

return Remotes
