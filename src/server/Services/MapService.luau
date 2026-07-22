--!strict
-- MapService: builds the "plains" gameplay map.
--
-- A giant flat green square base -- a 5 x 5 grid of 512-stud baseplates
-- (2560 x 2560 studs total). The player's house sits dead-center on a bare dirt
-- yard, and FIVE concentric rings of grass surround it, ordered from the easiest
-- grass nearest the house to the toughest farthest out
-- (Meadow -> Wild -> Moss -> Thick -> Ironweed, matching the tool progression in
-- GameConfig). Every grass ring is built from small pads tagged with
-- GameConfig.GRASS_SURFACE_TAG, so GrassService grows cuttable grass on them.
--
-- This replaces the old village map. During the intro cutscene the plains will
-- be swapped in to replace the neighborhood; for now it builds on server start
-- so it can be walked and tested directly.

local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

local MapService = {}

----------------------------------------------------------------------
-- Layout
----------------------------------------------------------------------

local GY = 0 -- ground top height; everything builds up from here
local BASEPLATE = 512 -- one Roblox baseplate is 512 studs square
local PLATE_TILES = 5 -- 5 x 5 baseplates
local GROUND_THICKNESS = 4

-- House clearing + concentric grass rings (studs, measured from the center).
local CLEAR_RADIUS = 50 -- bare yard kept clear so House 2 fits centered
local RING_WIDTH = 20 -- radial thickness of each grass ring
local RING_GAP = 6 -- bare gap between rings (reads as a walking path)
local PAD = 16 -- grid granularity of the grass pads

-- Rings from the house outward: easiest grass first.
local RINGS = { "Meadow", "Wild", "Moss", "Thick", "Ironweed" }

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local PAL = {
	PLATE = rgb(96, 168, 78), -- the giant green base
	SOIL = rgb(88, 140, 70), -- grass-pad base (peeks between the blades)
	YARD = rgb(150, 130, 96), -- dirt yard under the house
}

----------------------------------------------------------------------
-- Roots (assigned in Init)
----------------------------------------------------------------------

local mapRoot: Model
local groundF: Folder
local grassF: Folder

----------------------------------------------------------------------
-- Primitives
----------------------------------------------------------------------

local function make(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function tagGrass(part: BasePart, grassType: string)
	part:SetAttribute("GrassType", grassType)
	CollectionService:AddTag(part, GameConfig.GRASS_SURFACE_TAG)
end

-- A thin pad that GrassService carpets with grass of the given type.
local function grassPad(grassType: string, x: number, z: number, size: number)
	local p = make(grassF, "Grass_" .. grassType, Vector3.new(size, 0.6, size), CFrame.new(x, GY + 0.3, z), PAL.SOIL, Enum.Material.Ground)
	tagGrass(p, grassType)
	return p
end

----------------------------------------------------------------------
-- Build
----------------------------------------------------------------------

-- Which grass type (if any) a given radius from the center belongs to.
local function ringTypeAt(r: number): string?
	if r < CLEAR_RADIUS then
		return nil
	end
	for i = 1, #RINGS do
		local inner = CLEAR_RADIUS + (i - 1) * (RING_WIDTH + RING_GAP)
		local outer = inner + RING_WIDTH
		if r >= inner and r < outer then
			return RINGS[i]
		end
	end
	return nil
end

local function buildBase()
	-- 5 x 5 grid of 512-stud baseplates. A single 2560-wide part would exceed
	-- Roblox's 2048-stud part limit, so the plate is tiled.
	local half = (PLATE_TILES - 1) / 2
	for i = 0, PLATE_TILES - 1 do
		for j = 0, PLATE_TILES - 1 do
			local x = (i - half) * BASEPLATE
			local z = (j - half) * BASEPLATE
			make(groundF, "Plate", Vector3.new(BASEPLATE, GROUND_THICKNESS, BASEPLATE), CFrame.new(x, GY - GROUND_THICKNESS / 2, z), PAL.PLATE, Enum.Material.Grass)
		end
	end
	-- bare dirt yard under where House 2 sits (kept clear of grass)
	local yard = CLEAR_RADIUS * 2 + 8
	make(groundF, "Yard", Vector3.new(yard, 0.4, yard), CFrame.new(0, GY + 0.2, 0), PAL.YARD, Enum.Material.Ground)
end

local function buildRings()
	local outerR = CLEAR_RADIUS + #RINGS * (RING_WIDTH + RING_GAP)
	local steps = math.ceil(outerR / PAD) + 1
	for i = -steps, steps do
		for j = -steps, steps do
			local x = i * PAD
			local z = j * PAD
			local grassType = ringTypeAt(math.sqrt(x * x + z * z))
			if grassType then
				grassPad(grassType, x, z, PAD)
			end
		end
	end
end

local function buildSpawn()
	-- Placeholder spawn in the front yard so the map is walkable now. The intro
	-- cutscene will set the real "spawn in front of the house" position later.
	local sp = Instance.new("SpawnLocation")
	sp.Name = "PlayerSpawn"
	sp.Anchored = true
	sp.Neutral = true
	sp.Duration = 0
	sp.Size = Vector3.new(12, 1, 12)
	sp.CFrame = CFrame.new(0, GY + 0.5, CLEAR_RADIUS - 16)
	sp.Color = PAL.YARD
	sp.Material = Enum.Material.Ground
	sp.TopSurface = Enum.SurfaceType.Smooth
	sp.Parent = mapRoot
end

----------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------

function MapService.Init(_services: any)
	local baseplate = Workspace:FindFirstChild("Baseplate")
	if baseplate then
		baseplate:Destroy()
	end

	mapRoot = Instance.new("Model")
	mapRoot.Name = "Map"
	mapRoot.Parent = Workspace

	groundF = Instance.new("Folder")
	groundF.Name = "Ground"
	groundF.Parent = mapRoot

	grassF = Instance.new("Folder")
	grassF.Name = "GrassSurfaces"
	grassF.Parent = mapRoot

	buildBase()
	buildRings()
	buildSpawn()

	print("[MapService] Plains map built (5x5 baseplate, concentric grass rings).")
end

function MapService.Start() end

return MapService
