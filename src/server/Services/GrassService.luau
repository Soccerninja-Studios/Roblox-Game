--!strict
-- GrassService: grows grass over the map and handles cutting it down.
--
-- The map is built by hand. Any Part tagged with GameConfig.GRASS_SURFACE_TAG
-- ("GrassSurface") gets a grid of grass tiles grown out of its TOP face, oriented
-- to that part -- so grass covers flat ground, tilted roofs, and (via a rotated
-- pad) walls. Cutting a tile shrinks it; clearing it removes the tile to reveal
-- whatever is underneath. Each grass type has its own defense (armor + health),
-- so tougher grass needs better tools and power upgrades.

local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.GameConfig)
local StatCalculator = require(Shared.StatCalculator)
local Remotes = require(Shared.Remotes)

local GrassService = {}

local PlayerDataService
local ClippingsService
local grassRoot: Model -- workspace.Kingdom, holds every grass tile

local function color3(rgb: { number }): Color3
	return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

local function grassDef(name: string)
	return GameConfig.GRASS_TYPES[name] or GameConfig.GRASS_TYPES[GameConfig.DEFAULT_GRASS_TYPE]
end

-- Build one grass tile standing on a surface point.
-- baseCF: a CFrame sitting ON the surface, its up-vector pointing along the surface normal.
local function makeTile(baseCF: CFrame, typeName: string, def: any, parent: Instance)
	local height = def.height
	local footprint = GameConfig.TILE_SIZE_STUDS * GameConfig.TILE_FILL

	local tile = Instance.new("Part")
	tile.Name = "GrassTile"
	tile.Anchored = true
	tile.CanCollide = false
	tile.CanQuery = true -- must stay true so the mouse can target it
	tile.CanTouch = false
	tile.Material = Enum.Material.Grass
	-- small per-tile color jitter so the field doesn't look flat
	local base = color3(def.color)
	local jitter = (math.random() - 0.5) * 0.08
	tile.Color = Color3.new(
		math.clamp(base.R + jitter, 0, 1),
		math.clamp(base.G + jitter, 0, 1),
		math.clamp(base.B + jitter * 0.5, 0, 1)
	)
	tile.Size = Vector3.new(footprint, height, footprint)
	tile.CFrame = baseCF * CFrame.new(0, height / 2, 0)

	tile:SetAttribute("GrassType", typeName)
	tile:SetAttribute("MaxHealth", def.health)
	tile:SetAttribute("Health", def.health)
	tile:SetAttribute("FullHeight", height)
	tile:SetAttribute("BaseCFrame", baseCF)
	tile.Parent = parent
	return tile
end

-- Cover the top face of a tagged surface part with a grid of grass tiles.
local function coatSurface(surface: BasePart)
	if surface:GetAttribute("GrassCoated") then
		return
	end
	surface:SetAttribute("GrassCoated", true)

	local typeName = surface:GetAttribute("GrassType") or GameConfig.DEFAULT_GRASS_TYPE
	local def = grassDef(typeName)
	if surface:GetAttribute("GrassHeight") then
		def = table.clone(def)
		def.height = surface:GetAttribute("GrassHeight")
	end

	local size = surface.Size
	local cf = surface.CFrame
	local step = GameConfig.TILE_SIZE_STUDS
	local nx = math.max(1, math.floor(size.X / step))
	local nz = math.max(1, math.floor(size.Z / step))

	if nx * nz > GameConfig.MAX_TILES_PER_SURFACE then
		warn(string.format("[GrassService] '%s' is huge (%d tiles); capping.", surface.Name, nx * nz))
		local scale = math.sqrt(GameConfig.MAX_TILES_PER_SURFACE / (nx * nz))
		nx = math.max(1, math.floor(nx * scale))
		nz = math.max(1, math.floor(nz * scale))
	end

	local startX = -(nx - 1) * step / 2
	local startZ = -(nz - 1) * step / 2
	local topY = size.Y / 2

	local folder = Instance.new("Folder")
	folder.Name = "Grass_" .. surface.Name
	folder.Parent = grassRoot

	for i = 0, nx - 1 do
		for j = 0, nz - 1 do
			local baseCF = cf * CFrame.new(startX + i * step, topY, startZ + j * step)
			makeTile(baseCF, typeName, def, folder)
		end
	end
end

-- Apply the shrink animation for a tile at its current health.
local function refreshTileHeight(tile: BasePart)
	local maxHealth = tile:GetAttribute("MaxHealth") or 1
	local health = tile:GetAttribute("Health") or 0
	local fullHeight = tile:GetAttribute("FullHeight") or tile.Size.Y
	local baseCF = tile:GetAttribute("BaseCFrame") :: CFrame
	local footprint = tile.Size.X

	local fraction = math.clamp(health / maxHealth, 0, 1)
	local newHeight = math.max(GameConfig.GRASS_MIN_STUB, fullHeight * fraction)

	local tween = TweenService:Create(
		tile,
		TweenInfo.new(GameConfig.GRASS_SHRINK_TWEEN, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.new(footprint, newHeight, footprint), CFrame = baseCF * CFrame.new(0, newHeight / 2, 0) }
	)
	tween:Play()
end

local function onRequestCut(player: Player, tile: Instance?)
	if not tile or not tile:IsA("BasePart") or tile.Name ~= "GrassTile" then
		return
	end
	if (tile:GetAttribute("Health") or 0) <= 0 then
		return
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	if (root.Position - tile.Position).Magnitude > GameConfig.CUT_RANGE + tile.Size.Y then
		return
	end

	local profile = PlayerDataService.Get(player)
	if not profile then
		return
	end

	local typeName = tile:GetAttribute("GrassType") or GameConfig.DEFAULT_GRASS_TYPE
	local def = grassDef(typeName)

	local power = StatCalculator.GetCutPower(profile.toolTier, profile.skills)
	local damage = power - def.armor
	if damage < GameConfig.MIN_CUT_DAMAGE then
		-- Tool isn't strong enough for this grass type yet.
		Remotes.Get("GrassTooTough"):FireClient(player, tile.Position, typeName)
		return
	end

	local health = tile:GetAttribute("Health") or 0
	local applied = math.min(health, damage)
	local newHealth = health - applied
	tile:SetAttribute("Health", newHealth)

	-- Clipping value for this swing (dropped on the ground, not auto-banked).
	local isCrit = math.random() < GameConfig.CRIT_BASE_CHANCE
	local critMul = isCrit and GameConfig.CRIT_BASE_MULTIPLIER or 1
	local valueMul = StatCalculator.GetClippingMultiplier(profile.skills)
	local earned =
		math.max(1, math.floor(applied * GameConfig.CLIPPINGS_PER_BLADE * def.value * valueMul * critMul + 0.5))

	profile.totalBladesCut = (profile.totalBladesCut or 0) + applied

	refreshTileHeight(tile)
	Remotes.Get("TileCut"):FireClient(player, tile.Position, typeName)

	-- Drop the clippings physically near the top of the tile.
	local dropFrom = tile.Position + Vector3.new(0, tile.Size.Y / 2 + 1, 0)
	if ClippingsService then
		ClippingsService.Drop(player, dropFrom, earned, isCrit)
	end

	if newHealth <= 0 then
		-- Fully cut: reveal whatever is underneath.
		tile.CanQuery = false
		Debris:AddItem(tile, GameConfig.GRASS_SHRINK_TWEEN + 0.05)
	end
end

-- Demo: only runs if the builder hasn't tagged anything yet, so there's always
-- something to test. Delete/ignore once you've tagged your own map.
local function buildDemo()
	local center = GameConfig.DEMO_CENTER

	local function coatedPad(sizeXZ: number, height: number, offset: Vector3, dirt: Color3, grassType: string)
		local pad = Instance.new("Part")
		pad.Anchored = true
		pad.Size = Vector3.new(sizeXZ, height, sizeXZ)
		pad.Position = center + offset
		pad.Color = dirt
		pad.Material = Enum.Material.Ground
		pad.Name = "DemoGround"
		pad.Parent = grassRoot
		pad:SetAttribute("GrassType", grassType)
		coatSurface(pad)
	end

	coatedPad(100, 2, Vector3.new(0, 1, 0), Color3.fromRGB(96, 72, 52), "Wild")
	coatedPad(24, 1, Vector3.new(34, 2, 20), Color3.fromRGB(80, 62, 46), "Thick")
	coatedPad(20, 1, Vector3.new(-32, 2, -18), Color3.fromRGB(66, 54, 44), "Ironweed")

	-- A little stone hut with a mossy roof, to show "cut grass -> reveal building".
	local hut = Instance.new("Part")
	hut.Anchored = true
	hut.Size = Vector3.new(18, 12, 16)
	hut.Position = center + Vector3.new(0, 8, -42)
	hut.Color = Color3.fromRGB(150, 146, 138)
	hut.Material = Enum.Material.Slate
	hut.Name = "DemoHut"
	hut.Parent = grassRoot
	hut:SetAttribute("GrassType", "Moss")
	coatSurface(hut)
end

function GrassService.Init(services)
	PlayerDataService = services.PlayerDataService
	ClippingsService = services.ClippingsService

	grassRoot = Workspace:FindFirstChild("Kingdom") :: Model
	if not grassRoot then
		grassRoot = Instance.new("Model")
		grassRoot.Name = "Kingdom"
		grassRoot.Parent = Workspace
	end
end

function GrassService.Start()
	-- Coat everything the builder tagged.
	local tagged = CollectionService:GetTagged(GameConfig.GRASS_SURFACE_TAG)
	for _, inst in tagged do
		if inst:IsA("BasePart") then
			coatSurface(inst)
		end
	end

	-- Support tagging parts live while play-testing.
	CollectionService:GetInstanceAddedSignal(GameConfig.GRASS_SURFACE_TAG):Connect(function(inst)
		if inst:IsA("BasePart") then
			task.defer(coatSurface, inst)
		end
	end)

	if #tagged == 0 and GameConfig.DEMO_ENABLED then
		print("[GrassService] No GrassSurface tags found - building demo map.")
		buildDemo()
	end

	Remotes.Get("RequestCut").OnServerEvent:Connect(onRequestCut)
	print("[GrassService] Grass ready.")
end

return GrassService
