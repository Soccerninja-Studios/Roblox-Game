--!strict
-- GrassService: generates the grass, validates cut requests, awards Clippings.
-- The server is the source of truth: it checks distance, swing rate, and tile state.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local StatCalculator = require(ReplicatedStorage.Shared.StatCalculator)

local GrassService = {}

local PlayerDataService: any
local lastSwing: { [Player]: number } = {}

local function onRequestCut(player: Player, tile: unknown)
	local profile = PlayerDataService.Get(player)
	if not profile then
		return
	end

	-- Validate the target is a real, uncut grass tile
	if typeof(tile) ~= "Instance" or not tile:IsA("BasePart") or tile.Name ~= "GrassTile" then
		return
	end
	local blades = tile:GetAttribute("BladesRemaining")
	if type(blades) ~= "number" or blades <= 0 then
		return
	end

	-- Distance check (small buffer for latency)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root or (root.Position - tile.Position).Magnitude > GameConfig.CUT_RANGE + 8 then
		return
	end

	-- Swing rate limit (10% tolerance for network jitter)
	local cooldown = StatCalculator.GetSwingCooldown(profile.skills) * 0.9
	local now = os.clock()
	if lastSwing[player] and now - lastSwing[player] < cooldown then
		return
	end
	lastSwing[player] = now

	-- Compute the cut
	local bladesPerSwing = StatCalculator.GetBladesPerSwing(profile.toolTier, profile.skills)
	local cut = math.min(blades, bladesPerSwing)
	local isCrit = math.random() < GameConfig.CRIT_BASE_CHANCE
	local earned = cut * GameConfig.CLIPPINGS_PER_BLADE * (isCrit and GameConfig.CRIT_BASE_MULTIPLIER or 1)

	tile:SetAttribute("BladesRemaining", blades - cut)
	if blades - cut <= 0 then
		-- Mowed look: short, lighter tile
		tile.Size = Vector3.new(GameConfig.TILE_SIZE_STUDS, 0.2, GameConfig.TILE_SIZE_STUDS)
		tile.Position = Vector3.new(tile.Position.X, 0.1, tile.Position.Z)
		tile.Color = Color3.fromRGB(164, 198, 106)
	end

	profile.totalBladesCut += cut
	PlayerDataService.AddClippings(player, earned)
	Remotes.Get("TileCut"):FireClient(player, tile.Position, earned, isCrit)
end

local function generateMeadow()
	local kingdom = Instance.new("Folder")
	kingdom.Name = "Kingdom"

	local meadow = Instance.new("Folder")
	meadow.Name = "TestMeadow"
	meadow.Parent = kingdom

	local size = GameConfig.TILE_SIZE_STUDS
	for x = 1, GameConfig.MEADOW_GRID do
		for z = 1, GameConfig.MEADOW_GRID do
			local height = 1 + math.random() * 0.4 -- slight height variation looks natural
			local tile = Instance.new("Part")
			tile.Name = "GrassTile"
			tile.Anchored = true
			tile.CanCollide = false -- players walk through tall grass
			tile.Material = Enum.Material.Grass
			tile.Size = Vector3.new(size, height, size)
			tile.Position = Vector3.new(16 + x * size, height / 2, 16 + z * size)
			tile.Color = Color3.fromRGB(70 + math.random(0, 30), 130 + math.random(0, 40), 50 + math.random(0, 20))
			tile:SetAttribute("BladesRemaining", GameConfig.BLADES_PER_TILE)
			tile.Parent = meadow
		end
	end

	kingdom.Parent = Workspace
end

function GrassService.Init(services: any)
	PlayerDataService = services.PlayerDataService
	Remotes.Get("RequestCut").OnServerEvent:Connect(onRequestCut)
	Players.PlayerRemoving:Connect(function(player)
		lastSwing[player] = nil
	end)
end

function GrassService.Start()
	generateMeadow()
	print("[GrassService] Test meadow generated")
end

return GrassService
