--!strict
-- DistrictService: makes "mow the grass to bring the village back to life" real.
--
-- MapService buries each district's ground under grass tiles tagged with a
-- "District" attribute, and hides that district's villagers + animals in
-- ServerStorage.DistrictLife.<District>. This service counts the grass in each
-- district, and once a district's last ground tile is mowed it reveals that
-- district's life (moving it into the world) and announces it to everyone. When
-- all districts are clear, Greenhollow is declared fully restored.
--
-- Only GROUND grass counts toward completion. Rooftop grass is cosmetic (it has
-- no District tag) because roofs need climbing to reach -- see MapService.

local Workspace = game:GetService("Workspace")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)

local DistrictService = {}

local DISPLAY_NAMES: { [string]: string } = {
	Square = "The Village Square",
	Residential = "Residential Row",
	Craftsmen = "Craftsmen's Quarter",
	Farmstead = "The Farmstead",
}

local grassRoot: Instance?
local lifeFolder: Instance?
local mapRoot: Instance?

local remaining: { [string]: number } = {}
local cleared: { [string]: boolean } = {}
local clearedCount = 0
local totalDistricts = 0
local doneAll = false

-- Count every standing ground grass tile, bucketed by its District attribute.
local function snapshot(): ({ [string]: number }, number)
	local counts: { [string]: number } = {}
	local total = 0
	if not grassRoot then
		return counts, total
	end
	for _, d in grassRoot:GetDescendants() do
		if d:IsA("BasePart") and d.Name == "GrassTile" then
			local key = d:GetAttribute("District")
			if typeof(key) == "string" then
				counts[key] = (counts[key] or 0) + 1
				total += 1
			end
		end
	end
	return counts, total
end

local function reveal(key: string)
	if cleared[key] then
		return
	end
	cleared[key] = true
	clearedCount += 1

	-- Move this district's hidden life into the world so it comes alive.
	if lifeFolder and mapRoot then
		local model = lifeFolder:FindFirstChild(key)
		if model then
			model.Parent = mapRoot
		end
	end

	local display = DISPLAY_NAMES[key] or key
	Remotes.Get("DistrictCleared"):FireAllClients(display, "restored \u{2014} its people return!")
	print("[DistrictService] District restored: " .. key)

	if not doneAll and totalDistricts > 0 and clearedCount >= totalDistricts then
		doneAll = true
		Workspace:SetAttribute("Village1Cleared", true)
		task.wait(2.5)
		Remotes.Get("DistrictCleared"):FireAllClients("Greenhollow Restored!", "Every district is thriving again.")
		print("[DistrictService] Greenhollow fully restored.")
	end
end

function DistrictService.Init()
	-- Grass tiles live under Workspace.Kingdom (created by GrassService); life waits
	-- in ServerStorage.DistrictLife (created by MapService). They may not exist yet
	-- at Init time, so Start() resolves them defensively.
	mapRoot = Workspace:FindFirstChild("Map")
	lifeFolder = ServerStorage:FindFirstChild("DistrictLife")
end

function DistrictService.Start()
	grassRoot = Workspace:WaitForChild("Kingdom", 30)
	mapRoot = mapRoot or Workspace:WaitForChild("Map", 30)
	lifeFolder = lifeFolder or ServerStorage:FindFirstChild("DistrictLife")

	if not grassRoot then
		warn("[DistrictService] No grass root (Workspace.Kingdom); districts disabled.")
		return
	end

	-- Wait for GrassService to finish coating: poll until the tile total holds steady
	-- across a few checks, so we snapshot the FULL overgrowth as our clear target.
	local lastTotal = -1
	local stableFor = 0
	while stableFor < 3 do
		task.wait(0.5)
		local _, total = snapshot()
		if total == lastTotal and total > 0 then
			stableFor += 1
		else
			stableFor = 0
		end
		lastTotal = total
	end

	remaining = (snapshot())
	totalDistricts = 0
	for key, count in remaining do
		totalDistricts += 1
		if count <= 0 then
			reveal(key)
		end
	end

	-- Decrement as tiles are cleared; reveal a district when its last tile is gone.
	grassRoot.DescendantRemoving:Connect(function(inst)
		if not inst:IsA("BasePart") or inst.Name ~= "GrassTile" then
			return
		end
		local key = inst:GetAttribute("District")
		if typeof(key) ~= "string" or cleared[key] then
			return
		end
		remaining[key] = (remaining[key] or 1) - 1
		if remaining[key] <= 0 then
			reveal(key)
		end
	end)

	print("[DistrictService] Watching districts.")
end

return DistrictService
