--!strict
-- GrassService: generates the grass, validates cut requests, awards Clippings.
-- The server is the source of truth: it checks distance, swing rate, and tile state.
--
-- Grass tiles now start TALL and shrink vertically a little on every cut (the amount
-- scales with the player's clipping power), then disappear once fully mowed. The
-- shrink is done with a server-side tween so it looks smooth and replicates to
-- every client while remaining fully authoritative.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
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

	-- Compute the cut. "Clipping power" (blades per swing) determines how much a tile
	-- shrinks, so stronger tools clear tall grass in fewer swings.
	local bladesPerSwing = StatCalculator.GetBladesPerSwing(profile.toolTier, profile.skills)
	local cut = math.min(blades, bladesPerSwing)
	local remaining = blades - cut
	local isCrit = math.random() < GameConfig.CRIT_BASE_CHANCE
	local earned = cut * GameConfig.CLIPPINGS_PER_BLADE * (isCrit and GameConfig.CRIT_BASE_MULTIPLIER or 1)

	tile:SetAttribute("BladesRemaining", remaining)

	-- Work out the new height and shrink toward it (keeping the tile's base on the ground)
	local fullHeight = (tile:GetAttribute("FullHeight") :: number?) or GameConfig.TALL_GRASS_HEIGHT
	local bladesInitial = (tile:GetAttribute("BladesInitial") :: number?) or GameConfig.BLADES_PER_TILE
	local size = GameConfig.TILE_SIZE_STUDS

	local depleted = remaining <= 0
	local newHeight: number
	if depleted then
		newHeight = GameConfig.GRASS_MIN_STUB
	else
		newHeight = math.max(GameConfig.GRASS_MIN_STUB, fullHeight * (remaining / bladesInitial))
	end

	local goalSize = Vector3.new(size, newHeight, size)
	local goalPos = Vector3.new(tile.Position.X, newHeight / 2, tile.Position.Z)
	local tween = TweenService:Create(
		tile,
		TweenInfo.new(GameConfig.GRASS_SHRINK_TWEEN, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = goalSize, Position = goalPos }
	)
	tween:Play()

	if depleted then
		-- Once mowed down, remove the tile so the ground beneath is revealed.
		tile.CanQuery = false
		Debris:AddItem(tile, GameConfig.GRASS_SHRINK_TWEEN + 0.02)
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
	local origin = GameConfig.MEADOW_ORIGIN
	for x = 1, GameConfig.MEADOW_GRID do
		for z = 1, GameConfig.MEADOW_GRID do
			local height = GameConfig.TALL_GRASS_HEIGHT + math.random() * GameConfig.GRASS_HEIGHT_VARIATION
			local tile = Instance.new("Part")
			tile.Name = "GrassTile"
			tile.Anchored = true
			tile.CanCollide = false -- players walk through tall grass
			tile.Material = Enum.Material.Grass
			tile.Size = Vector3.new(size, height, size)
			tile.Position = Vector3.new(origin.X + x * size, height / 2, origin.Z + z * size)
			tile.Color = Color3.fromRGB(70 + math.random(0, 30), 130 + math.random(0, 40), 50 + math.random(0, 20))
			tile:SetAttribute("BladesRemaining", GameConfig.BLADES_PER_TILE)
			tile:SetAttribute("BladesInitial", GameConfig.BLADES_PER_TILE)
			tile:SetAttribute("FullHeight", height)
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
