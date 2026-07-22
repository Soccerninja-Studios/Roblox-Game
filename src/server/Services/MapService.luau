--!strict
-- MapService: builds the "plains" gameplay map.
--
-- A giant flat green base -- a 5 x 5 grid of 512-stud baseplates (2560 x 2560
-- studs total, tiled because a single 2560-wide part exceeds Roblox's 2048-stud
-- limit). The house sits dead-center on a bare dirt yard, and FIVE big concentric
-- grass rings surround it, ordered easiest-nearest to toughest-outermost
-- (Meadow -> Wild -> Moss -> Thick -> Ironweed, matching the tool progression).
--
-- Each ring is a true circular BAND (membership is a pure radius test, so the
-- edges are round, not square) and each ring is wider -- and covers far more
-- ground -- than the one inside it. The rings now stretch across most of the map
-- instead of a small patch in the middle. Outer rings use chunkier grass tiles so
-- a huge field stays a sane number of parts; each pad = 2 x its tile size, so
-- GrassService always subdivides it cleanly.
--
-- (Trees, lakes, rocks and decorative grass get scattered on top later, once
-- those models arrive.)

local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

local MapService = {}

----------------------------------------------------------------------
-- Layout
----------------------------------------------------------------------

local BASEPLATE = 512 -- one Roblox baseplate is 512 studs square
local PLATE_TILES = 5 -- 5 x 5 baseplates
local GROUND_THICKNESS = 4
local CLEAR_RADIUS = 120 -- bare yard kept clear so the house fits centered

-- Concentric grass rings, house -> outward.
--   grass       = which GrassType (see GameConfig.GRASS_TYPES)
--   inner/outer = radius band in studs (gaps between bands read as walking paths)
--   pad         = build-grid step; always 2 x tile so tiles subdivide cleanly
--   tile        = grass tile footprint GrassService grows on this ring
type RingDef = { grass: string, inner: number, outer: number, pad: number, tile: number }
local RINGS: { RingDef } = {
	{ grass = "Meadow", inner = 120, outer = 255, pad = 20, tile = 10 },
	{ grass = "Wild", inner = 290, outer = 480, pad = 28, tile = 14 },
	{ grass = "Moss", inner = 515, outer = 725, pad = 36, tile = 18 },
	{ grass = "Thick", inner = 765, outer = 965, pad = 48, tile = 24 },
	{ grass = "Ironweed", inner = 1005, outer = 1145, pad = 60, tile = 30 },
}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local PAL = {
	PLATE = rgb(96, 168, 78), -- the giant green base
	SOIL = rgb(88, 140, 70), -- grass-pad base (peeks between the blades)
	YARD = rgb(150, 130, 96), -- dirt yard under the house
}

----------------------------------------------------------------------
-- Roots (created on first build)
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

-- A thin pad that GrassService carpets with grass of the given type.
local function grassPad(grassType: string, x: number, y: number, z: number, size: number, tile: number)
	local p = make(grassF, "Grass_" .. grassType, Vector3.new(size, 0.6, size), CFrame.new(x, y + 0.3, z), PAL.SOIL, Enum.Material.Ground)
	p:SetAttribute("GrassType", grassType)
	p:SetAttribute("TileSize", tile)
	CollectionService:AddTag(p, GameConfig.GRASS_SURFACE_TAG)
	return p
end

----------------------------------------------------------------------
-- Build steps (all take the map center so the cutscene can rebuild the plains
-- centered on the house instead of the origin)
----------------------------------------------------------------------

local function buildBase(cx: number, cz: number, gy: number)
	local half = (PLATE_TILES - 1) / 2
	for i = 0, PLATE_TILES - 1 do
		for j = 0, PLATE_TILES - 1 do
			local x = cx + (i - half) * BASEPLATE
			local z = cz + (j - half) * BASEPLATE
			make(groundF, "Plate", Vector3.new(BASEPLATE, GROUND_THICKNESS, BASEPLATE), CFrame.new(x, gy - GROUND_THICKNESS / 2, z), PAL.PLATE, Enum.Material.Grass)
		end
	end
	-- bare dirt yard under where the house sits (kept clear of grass)
	local yard = CLEAR_RADIUS * 2 + 8
	make(groundF, "Yard", Vector3.new(yard, 0.4, yard), CFrame.new(cx, gy + 0.2, cz), PAL.YARD, Enum.Material.Ground)
end

local function buildRings(cx: number, cz: number, gy: number)
	-- Each ring is built on its own grid so inner rings stay finely rounded while
	-- outer rings use bigger steps. A cell is filled only if its distance from the
	-- center lands inside the band -- a pure radial test, so the bands are circles.
	for _, ring in RINGS do
		local steps = math.ceil(ring.outer / ring.pad)
		for i = -steps, steps do
			for j = -steps, steps do
				local dx = i * ring.pad
				local dz = j * ring.pad
				local r = math.sqrt(dx * dx + dz * dz)
				if r >= ring.inner and r < ring.outer then
					grassPad(ring.grass, cx + dx, gy, cz + dz, ring.pad, ring.tile)
				end
			end
		end
	end
end

local function buildSpawn(cx: number, cz: number, gy: number)
	local sp = Instance.new("SpawnLocation")
	sp.Name = "PlayerSpawn"
	sp.Anchored = true
	sp.Neutral = true
	sp.Duration = 0
	sp.Size = Vector3.new(12, 1, 12)
	sp.CFrame = CFrame.new(cx, gy + 0.5, cz + (CLEAR_RADIUS - 20))
	sp.Color = PAL.YARD
	sp.Material = Enum.Material.Ground
	sp.TopSurface = Enum.SurfaceType.Smooth
	sp.Parent = mapRoot
end

----------------------------------------------------------------------
-- Public build
----------------------------------------------------------------------

-- Build the plains centered on `center` (defaults to the origin). The cutscene
-- rebuilds it centered on the house when it swaps the neighborhood away.
function MapService.BuildPlains(center: Vector3?)
	local c = center or Vector3.new(0, 0, 0)
	if not mapRoot then
		mapRoot = Instance.new("Model")
		mapRoot.Name = "Map"
		mapRoot.Parent = Workspace
		groundF = Instance.new("Folder")
		groundF.Name = "Ground"
		groundF.Parent = mapRoot
		grassF = Instance.new("Folder")
		grassF.Name = "GrassSurfaces"
		grassF.Parent = mapRoot
	end
	buildBase(c.X, c.Z, c.Y)
	buildRings(c.X, c.Z, c.Y)
	buildSpawn(c.X, c.Z, c.Y)
	print("[MapService] Plains map built (5x5 baseplate, 5 big concentric grass rings).")
end

----------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------

function MapService.Init(_services: any)
	local baseplate = Workspace:FindFirstChild("Baseplate")
	if baseplate then
		baseplate:Destroy()
	end

	-- When the intro cutscene is on, CutsceneService builds the plains (centered on
	-- the house) at the moment it swaps the neighborhood out. Otherwise build it now
	-- at the origin so the map is walkable straight away -- handy for testing.
	if not GameConfig.INTRO_CUTSCENE then
		MapService.BuildPlains(Vector3.new(0, 0, 0))
	end
end

function MapService.Start() end

return MapService
