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
}

local Remotes = {}

if RunService:IsServer() and not ReplicatedStorage:FindFirstChild("Remotes") then
	local folder = Instance.new("Folder")
	folder.Name = "Remotes"
	for _, name in REMOTE_NAMES do
		local remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = folder
	end
	folder.Parent = ReplicatedStorage
end

function Remotes.Get(name: string): RemoteEvent
	local folder = ReplicatedStorage:WaitForChild("Remotes")
	return folder:WaitForChild(name) :: RemoteEvent
end

return Remotes
