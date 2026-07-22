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
-- ground -- than the one inside it. Outer rings use chunkier grass tiles so a
-- huge field stays a sane number of parts; each pad = 2 x its tile size, so
-- GrassService always subdivides it cleanly.
--
-- On top of the grass we scatter scenery (trees, rocks, bushes, flowers and
-- decorative grass) from ReplicatedStorage.Assets.PlainsAssets. Placement uses a
-- jittered grid whose fill chance is driven by low-frequency noise, so the map
-- has plentiful pockets and scarce clearings while staying evenly spread overall.

local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
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
local decorF: Folder

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
-- Scenery scatter (trees, rocks, bushes, flowers, grass tufts)
----------------------------------------------------------------------

local SCATTER_SEED = 20260722 -- change this to reshuffle the whole layout

-- Assets are grouped so big things (trees, boulders) sit on a coarse grid and
-- keep their distance, while small things (bushes, flowers, tufts) fill in on a
-- finer grid. Weights bias which asset gets picked; assets missing from the
-- shipped folder are simply skipped, so it's safe if names change later.
local LARGE_WEIGHTS: { [string]: number } = {
	["Tree 1"] = 3, ["Tree 2"] = 3, ["Tree 3"] = 3, ["Tree 4"] = 2,
	["Rock 1"] = 1, ["Rock 5"] = 1, ["Grass 6"] = 0.4,
}
local SMALL_WEIGHTS: { [string]: number } = {
	["Bush 1"] = 2, ["Bush 2"] = 2, ["Bush 3"] = 2,
	["Flower Bush 1"] = 1.5, ["Flower Bush 2"] = 1.5,
	["Flowers 1"] = 1.5, ["Flowers 2"] = 1.5, ["Flowers 3"] = 1.5, ["Flowers 4"] = 1.5,
	["Grass 1"] = 2, ["Grass 2"] = 2, ["Grass 3"] = 2, ["Grass 4"] = 2, ["Grass 5"] = 2,
	["Rock 2"] = 1, ["Rock 3"] = 1, ["Rock 4"] = 1,
}

-- Grid + density knobs. Raise CELL or lower MID to thin things out (fewer parts,
-- better performance); lower CELL or raise MID for a denser, lusher map. MID is
-- the average fill chance; SPAN is how far low-frequency noise pushes it up in
-- "plentiful" pockets and down in "scarce" ones.
local LARGE_CELL = 80
local LARGE_MID = 0.30
local LARGE_SPAN = 0.55
local LARGE_FREQ = 0.006
local SMALL_CELL = 42
local SMALL_MID = 0.42
local SMALL_SPAN = 0.62
local SMALL_FREQ = 0.011

local SCATTER_MAX_R = 1150 -- keep scenery inside the plate
local SCATTER_MIN_R = CLEAR_RADIUS + 12 -- keep the house yard clear

-- The scenery folder lives in ReplicatedStorage.Assets ideally, but we also look
-- in ServerStorage and Workspace so it works if you keep it in Workspace.
local function findAssetsFolder(): Instance?
	local candidates: { Instance? } = {
		ReplicatedStorage:FindFirstChild("Assets"),
		ServerStorage:FindFirstChild("Assets"),
		ServerStorage,
		ReplicatedStorage,
		Workspace,
	}
	local folder: Instance? = nil
	for _, c in candidates do
		if c then
			folder = c:FindFirstChild("PlainsAssets") or c:FindFirstChild("Plains Assets")
			if folder then
				break
			end
		end
	end
	if folder and #folder:GetChildren() == 1 then
		local only = folder:GetChildren()[1]
		if only:IsA("Folder") then
			folder = only
		end
	end
	return folder
end

local function clamp01(n: number): number
	if n < 0 then
		return 0
	elseif n > 1 then
		return 1
	end
	return n
end

-- Flatten a weight table into a pick list, keeping only assets that shipped.
local function buildPool(folder: Instance, weights: { [string]: number }): { Instance }
	local pool: { Instance } = {}
	for name, weight in weights do
		local template = folder:FindFirstChild(name)
		if template then
			local copies = math.max(1, math.floor(weight * 2 + 0.5))
			for _ = 1, copies do
				table.insert(pool, template)
			end
		end
	end
	return pool
end

-- Clone `template`, make it static, and seat it so its base rests on the ground
-- at (x, z) with a random yaw -- works no matter where the model's pivot is.
local function placeDecor(template: Instance, x: number, z: number, gy: number, yaw: number)
	local clone = template:Clone()
	if clone:IsA("BasePart") then
		clone.Anchored = true
	end
	local trash: { Instance } = {}
	for _, d in clone:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
		elseif d:IsA("LuaSourceContainer") or d:IsA("Camera") then
			-- strip packaged Scripts/LocalScripts/ModuleScripts so unowned-asset
			-- loaders (e.g. a bush's "Constant" module) can't error or run
			table.insert(trash, d)
		end
	end
	for _, d in trash do
		d:Destroy()
	end
	clone.Parent = decorF

	if clone:IsA("Model") then
		clone:PivotTo(CFrame.new(x, gy, z) * CFrame.Angles(0, yaw, 0))
		local bcf, size = clone:GetBoundingBox()
		local bottom = bcf.Position.Y - size.Y / 2
		clone:PivotTo(clone:GetPivot() + Vector3.new(0, gy - bottom, 0))
	elseif clone:IsA("BasePart") then
		clone.CFrame = CFrame.new(x, gy + clone.Size.Y / 2, z) * CFrame.Angles(0, yaw, 0)
	end
end

local function scatterPass(cx: number, cz: number, gy: number, folder: Instance, weights: { [string]: number }, cell: number, mid: number, span: number, freq: number, rng: Random, noiseZ: number)
	local pool = buildPool(folder, weights)
	if #pool == 0 then
		return
	end
	local steps = math.ceil(SCATTER_MAX_R / cell)
	local placed = 0
	for i = -steps, steps do
		for j = -steps, steps do
			-- jitter inside the cell so the underlying grid never shows
			local x = i * cell + rng:NextNumber(-cell * 0.42, cell * 0.42)
			local z = j * cell + rng:NextNumber(-cell * 0.42, cell * 0.42)
			local r = math.sqrt(x * x + z * z)
			if r >= SCATTER_MIN_R and r <= SCATTER_MAX_R then
				local n = math.noise(x * freq, z * freq, noiseZ) -- ~[-0.5, 0.5]
				local density = clamp01(mid + span * n)
				if rng:NextNumber() < density then
					local template = pool[rng:NextInteger(1, #pool)]
					placeDecor(template, cx + x, cz + z, gy, rng:NextNumber(0, math.pi * 2))
					placed += 1
					if placed % 50 == 0 then
						task.wait() -- spread the build over frames so it never hard-freezes
					end
				end
			end
		end
	end
end

local function buildScatter(cx: number, cz: number, gy: number)
	local folder = findAssetsFolder()
	if not folder then
		warn("[MapService] PlainsAssets folder not found - skipping scenery scatter.")
		return
	end
	local rng = Random.new(SCATTER_SEED)
	-- Big features first (their clusters shape the landscape), then fill in details.
	scatterPass(cx, cz, gy, folder, LARGE_WEIGHTS, LARGE_CELL, LARGE_MID, LARGE_SPAN, LARGE_FREQ, rng, 0.5)
	scatterPass(cx, cz, gy, folder, SMALL_WEIGHTS, SMALL_CELL, SMALL_MID, SMALL_SPAN, SMALL_FREQ, rng, 12.5)
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
		decorF = Instance.new("Folder")
		decorF.Name = "Decorations"
		decorF.Parent = mapRoot
	end
	buildBase(c.X, c.Z, c.Y)
	buildRings(c.X, c.Z, c.Y)
	buildSpawn(c.X, c.Z, c.Y)
	local ok, err = pcall(buildScatter, c.X, c.Z, c.Y)
	if not ok then
		warn("[MapService] scenery scatter failed: " .. tostring(err))
	end
	print("[MapService] Plains map built (5x5 baseplate, 5 concentric grass rings, scattered scenery).")
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
