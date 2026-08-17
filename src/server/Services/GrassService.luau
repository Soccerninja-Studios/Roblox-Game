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
local QuestService
local MonsterService
local BossService
local grassRoot: Model -- workspace.Kingdom, holds every grass tile
local remainingByZone: { [string]: number } = {}

local function color3(rgb: { number }): Color3
	return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

local function grassDef(name: string)
	return GameConfig.GRASS_TYPES[name] or GameConfig.GRASS_TYPES[GameConfig.DEFAULT_GRASS_TYPE]
end

-- Build one grass tile standing on a surface point.
-- baseCF: a CFrame sitting ON the surface, its up-vector pointing along the surface normal.
local function makeTile(baseCF: CFrame, typeName: string, def: any, parent: Instance, tileSize: number?)
	local height = def.height
	local footprint = (tileSize or GameConfig.TILE_SIZE_STUDS) * GameConfig.TILE_FILL

	local tile = Instance.new("Part")
	tile.Name = "GrassTile"
	tile.Anchored = true
	-- The visible grass blade itself never collides (back to how it was). A separate
	-- invisible barrier part (built below) is what blocks the player until the tile is
	-- fully cut down.
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
	remainingByZone[typeName] = (remainingByZone[typeName] or 0) + 1

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

	-- Which district this surface belongs to (set by MapService). Every tile grown
	-- from it inherits the tag so DistrictService can tell when a district is clear.
	local district = surface:GetAttribute("District")

	local size = surface.Size
	local cf = surface.CFrame
	-- A surface may override the tile footprint via a "TileSize" attribute (used by
	-- the big plains rings so a huge grass field stays a sane number of parts).
	local step = (surface:GetAttribute("TileSize") :: number?) or GameConfig.TILE_SIZE_STUDS
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
			local tile = makeTile(baseCF, typeName, def, folder, step)
			if district then
				tile:SetAttribute("District", district)
			end
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


-- One authoritative completion hook shared by hand tools and auto-mowers. It
-- guarantees exactly one monster/boss roll per tile, attributes mower rolls to
-- their owner, and reserves the final tile in a ring for that ring's boss.
local function reportTileCleared(player: Player, tile: BasePart, typeName: string)
	if tile:GetAttribute("ClearCounted") then
		return
	end
	tile:SetAttribute("ClearCounted", true)
	local remaining = math.max(0, (remainingByZone[typeName] or 1) - 1)
	remainingByZone[typeName] = remaining
	local zoneIndex = GrassService.GetGrassZoneIndex(typeName)
	-- A grass tile's Position is the center of its blade, several studs above the
	-- actual ring floor. Use the stored surface CFrame so combat spawns begin from
	-- the real ground even before the cleared blade has disappeared.
	local spawnPosition = tile.Position - tile.CFrame.UpVector * (tile.Size.Y * 0.5)
	local baseCFrame = tile:GetAttribute("BaseCFrame")
	if typeof(baseCFrame) == "CFrame" then
		spawnPosition = (baseCFrame :: CFrame).Position
	end
	if remaining <= 0 and BossService then
		BossService.OnZoneCleared(player, spawnPosition, zoneIndex)
	elseif MonsterService then
		MonsterService.OnTileCleared(player, spawnPosition, zoneIndex)
	end
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

	-- Zone gating: your current tool must be rated for this grass's zone. A tool
	-- can cut its own zone and every earlier one, but tougher zones are locked
	-- until you upgrade -- this keeps players moving through zones in order.
	if not StatCalculator.CanCutGrass(profile.toolTier, typeName) then
		Remotes.Get("GrassTooTough"):FireClient(player, tile.Position, typeName)
		return
	end

	local power = StatCalculator.GetCutPowerForGrass(profile.toolTier, typeName, profile.skills)
	power *= (1 + PlayerDataService.GetPetBonus(profile, "cutPower"))
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
	profile.totalBladesCut = (profile.totalBladesCut or 0) + applied

	refreshTileHeight(tile)
	Remotes.Get("TileCut"):FireClient(player, tile.Position, typeName)

	if newHealth > 0 then
		-- Still standing: no clippings are awarded until the tile is fully cleared.
		return
	end

	-- Fully cut down. Each grass type pays out a SET number of clippings
	-- (def.clipReward) regardless of how many swings clearing it actually took, so a
	-- strong tool that fells it in one hit still yields the full reward. That base is
	-- the guaranteed minimum; upgrades (Greener Thumb) and gamepasses multiply it up.
	local baseReward = def.clipReward or 1
	local valueMul = StatCalculator.GetClippingMultiplier(profile.skills) -- Greener Thumb
	local gamepassMul = player:GetAttribute("ClipMultiplier") or 1 -- hook for gamepasses / global boosts
	local isCrit = math.random() < GameConfig.CRIT_BASE_CHANCE
	local critMul = isCrit and GameConfig.CRIT_BASE_MULTIPLIER or 1
	-- max() guarantees the payout never drops below this type's base amount.
	local reward = math.max(baseReward, math.floor(baseReward * valueMul * gamepassMul + 0.5)) * critMul

	local dropFrom = tile.Position + Vector3.new(0, tile.Size.Y / 2 + 1, 0)
	if ClippingsService then
		ClippingsService.Drop(player, dropFrom, reward, isCrit)
	end

	-- Quests: one tuft of this grass type was fully cleared.
	if QuestService then
		QuestService.ReportMow(player, typeName)
	end

	-- Combat: every source uses the same one-roll completion pipeline.
	reportTileCleared(player, tile, typeName)

	-- Reveal whatever is underneath and let the player walk through now.
	tile.CanQuery = false
	tile.CanCollide = false
	Debris:AddItem(tile, GameConfig.GRASS_SHRINK_TWEEN + 0.05)
end

-- Mower-facing API -----------------------------------------------------------
-- Auto-mowers cut the same tiles players do, so they reuse the exact shrink and
-- clear behaviour here instead of reimplementing it. The difference is where the
-- payout goes: a mower banks clippings into its own storage, so these functions
-- return the reward rather than dropping pickups for a player.

local GRASS_ZONE_INDEX: { [string]: number } = {
	Meadow = 1,
	Wild = 2,
	Mossmire = 3,
	Thicket = 4,
	Ironweed = 5,
}

-- Zone index of a grass type (1 = easiest). Unknown types read as the easiest.
function GrassService.GetGrassZoneIndex(typeName: string): number
	return GRASS_ZONE_INDEX[typeName] or 1
end

-- Is this instance a grass tile that still has health left to cut?
function GrassService.IsCuttableTile(inst: Instance?): boolean
	if not inst or not inst:IsA("BasePart") or inst.Name ~= "GrassTile" then
		return false
	end
	return (inst:GetAttribute("Health") or 0) > 0
end

-- Find the closest cuttable tile to `origin` belonging to EXACTLY `zoneIndex`.
--
-- Note this is deliberately stricter than the player's tool rule: a tool can cut
-- its own zone and every easier one, but each mower is dedicated to a single zone
-- so mowers don't pile onto the Meadow and trivialise the early game. Sweeps
-- outward in steps so a mower in a cleared patch still finds work further afield
-- without scanning the whole map every tick.
function GrassService.FindNearestCuttableTile(origin: Vector3, zoneIndex: number): BasePart?
	local step = GameConfig.AUTO_MOWER_SEARCH_STEP or 60
	local maxRadius = GameConfig.AUTO_MOWER_SEARCH_MAX or 420
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { grassRoot }
	params.MaxParts = 0

	local radius = step
	while radius <= maxRadius do
		local parts = Workspace:GetPartBoundsInRadius(origin, radius, params)
		local best: BasePart? = nil
		local bestDist = math.huge
		for _, part in parts do
			if GrassService.IsCuttableTile(part) then
				local typeName = part:GetAttribute("GrassType") or GameConfig.DEFAULT_GRASS_TYPE
				if GrassService.GetGrassZoneIndex(typeName) == zoneIndex then
					local d = (part.Position - origin).Magnitude
					if d < bestDist then
						bestDist = d
						best = part
					end
				end
			end
		end
		if best then
			return best
		end
		radius += step
	end
	return nil
end

-- Apply one mower swing to a tile.
-- Returns (cleared, reward): `cleared` is true when this swing felled the tile,
-- and `reward` is the clippings it yielded (0 unless it was cleared).
function GrassService.MowerCut(player: Player, tile: BasePart, cutPower: number): (boolean, number)
	if not GrassService.IsCuttableTile(tile) then
		return false, 0
	end

	local typeName = tile:GetAttribute("GrassType") or GameConfig.DEFAULT_GRASS_TYPE
	local def = grassDef(typeName)

	local damage = cutPower - def.armor
	if damage < GameConfig.MIN_CUT_DAMAGE then
		-- This mower is not strong enough to dent this grass type.
		return false, 0
	end

	local health = tile:GetAttribute("Health") or 0
	local applied = math.min(health, damage)
	local newHealth = health - applied
	tile:SetAttribute("Health", newHealth)
	refreshTileHeight(tile)

	if newHealth > 0 then
		return false, 0
	end

	-- Fully cut down. Mowers get the grass type's flat base reward with no player
	-- skill multipliers or crits -- those belong to hand-cutting, which keeps manual
	-- mowing worth doing even once the field is automated.
	local reward = def.clipReward or 1
	reportTileCleared(player, tile, typeName)

	tile.CanQuery = false
	tile.CanCollide = false
	Debris:AddItem(tile, GameConfig.GRASS_SHRINK_TWEEN + 0.05)

	return true, reward
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
	coatedPad(24, 1, Vector3.new(34, 2, 20), Color3.fromRGB(80, 62, 46), "Thicket")
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
	hut:SetAttribute("GrassType", "Mossmire")
	coatSurface(hut)
end

function GrassService.Init(services)
	PlayerDataService = services.PlayerDataService
	ClippingsService = services.ClippingsService
	QuestService = services.QuestService
	MonsterService = services.MonsterService
	BossService = services.BossService

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
