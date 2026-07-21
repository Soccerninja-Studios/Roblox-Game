--!strict
-- MapService: procedurally builds the world, one village at a time.
--
-- WORLD PLAN (Medieval Dynasty-style): five villages ring a central castle.
-- Each village is a "zone" the player cleans of overgrown grass; clearing one
-- unlocks the next. Village 1 ("Greenhollow") is the starting area -- it holds
-- the shop + gardener. Only Village 1 is built so far; its gates already point at
-- where Villages 2 & 5 and the Castle will connect.
--
-- OVERGROWTH + DISTRICTS: the whole village starts buried under grass. Every
-- district's ground AND rooftops are carpeted in grass tiles (tagged with a
-- "District" attribute), so GrassService grows grass on them automatically.
-- Mowing uncovers the village bit by bit. When a district is fully mowed,
-- DistrictService reveals that district's villagers & animals -- built hidden in
-- ServerStorage.DistrictLife -- to bring the place to life.
--
-- Everything is generated in code so the world stays reproducible and tweakable:
-- adjust the layout constants / district builders below to reshape the village.

local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

local MapService = {}

----------------------------------------------------------------------
-- Constants / palette
----------------------------------------------------------------------

local GY = 0 -- ground top height; everything builds up from here
local ZONE_KEY = "Village1"
local P = 130 -- half-size of the village (palisade sits at +/-P)
local GROUND_THICKNESS = 4

-- Districts: each has a display key, the grass type covering it, and (for the two
-- big carpets) is filled by its own builder below. Only Meadow/Wild are used for
-- required carpets so the starting Rusty Shears can always clear them.
local DISTRICT = {
	Square = "Square",
	Residential = "Residential",
	Craftsmen = "Craftsmen",
	Farmstead = "Farmstead",
}

local function rgb(r, g, b): Color3
	return Color3.fromRGB(r, g, b)
end

local PAL = {
	GROUND = rgb(96, 150, 74),
	GROUND_DRY = rgb(120, 150, 86),
	DIRT = rgb(122, 96, 64),
	PATH = rgb(158, 132, 96),
	FIELD = rgb(104, 74, 48),
	WOOD_DARK = rgb(84, 58, 36),
	WOOD = rgb(120, 84, 50),
	WOOD_LIGHT = rgb(156, 120, 78),
	WALL = rgb(226, 214, 188),
	WALL2 = rgb(208, 192, 162),
	WALL3 = rgb(196, 176, 150),
	BARN_RED = rgb(150, 66, 54),
	ROOF_THATCH = rgb(176, 138, 78),
	ROOF_WOOD = rgb(104, 72, 46),
	ROOF_TILE = rgb(150, 82, 62),
	ROOF_SLATE = rgb(96, 96, 104),
	STONE = rgb(150, 146, 138),
	STONE_DARK = rgb(108, 104, 98),
	WATER = rgb(70, 122, 150),
	LEAF = rgb(74, 128, 60),
	LEAF2 = rgb(94, 152, 72),
	LEAF3 = rgb(120, 168, 82),
	ROCK = rgb(122, 120, 116),
	HAY = rgb(214, 182, 96),
	WINDOW = rgb(126, 172, 192),
	CLOTH_RED = rgb(170, 74, 62),
	CLOTH_BLUE = rgb(74, 104, 150),
	SKIN = rgb(232, 196, 158),
}

----------------------------------------------------------------------
-- Roots (assigned in Init)
----------------------------------------------------------------------

local mapRoot: Model
local terrainF: Folder
local structF: Folder
local propsF: Folder
local grassF: Folder
local lifeFolder: Folder
local lifeModels: { [string]: Model } = {}

local function lifeModel(key: string): Model
	local m = lifeModels[key]
	if not m then
		m = Instance.new("Model")
		m.Name = key
		m.Parent = lifeFolder
		lifeModels[key] = m
	end
	return m
end

----------------------------------------------------------------------
-- Primitives
----------------------------------------------------------------------

local function make(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material
	if shape then
		p.Shape = shape
	end
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- Vertical cylinder: a Cylinder part's length runs along local X, so rotate it
-- 90 degrees about Z to stand it upright. centerPos is the world center.
local function pillar(parent: Instance, name: string, diameter: number, height: number, centerPos: Vector3, color: Color3, material: Enum.Material): Part
	local cf = CFrame.new(centerPos) * CFrame.Angles(0, 0, math.rad(90))
	return make(parent, name, Vector3.new(height, diameter, diameter), cf, color, material, Enum.PartType.Cylinder)
end

local function ball(parent: Instance, name: string, diameter: number, centerPos: Vector3, color: Color3, material: Enum.Material): Part
	return make(parent, name, Vector3.new(diameter, diameter, diameter), CFrame.new(centerPos), color, material, Enum.PartType.Ball)
end

-- world position from a base CFrame + local offset
local function wp(base: CFrame, x: number, y: number, z: number): Vector3
	return (base * CFrame.new(x, y, z)).Position
end

-- A ground-level base CFrame at (x, z) with a yaw (degrees).
local function at(x: number, z: number, yaw: number?): CFrame
	return CFrame.new(x, GY, z) * CFrame.Angles(0, math.rad(yaw or 0), 0)
end

local function tagGrass(part: BasePart, grassType: string, district: string?)
	part:SetAttribute("GrassType", grassType)
	part:SetAttribute("ZoneKey", ZONE_KEY)
	if district then
		part:SetAttribute("District", district)
	end
	CollectionService:AddTag(part, GameConfig.GRASS_SURFACE_TAG)
end

-- A thin ground pad that GrassService carpets with grass, tagged to a district.
local function groundCarpet(district: string, grassType: string, x: number, z: number, w: number, d: number)
	local p = make(grassF, "Carpet_" .. district, Vector3.new(w, 0.6, d), CFrame.new(x, GY + 0.3, z), PAL.GROUND, Enum.Material.Ground)
	tagGrass(p, grassType, district)
	return p
end

----------------------------------------------------------------------
-- Signs
----------------------------------------------------------------------

local function billboardSign(adornee: BasePart, title: string, subtitle: string?, offsetY: number?)
	local b = Instance.new("BillboardGui")
	b.Name = "Sign"
	b.Size = UDim2.fromOffset(210, 74)
	b.StudsOffset = Vector3.new(0, offsetY or 3.5, 0)
	b.MaxDistance = 260
	b.Adornee = adornee
	b.Parent = adornee

	local f = Instance.new("Frame")
	f.Size = UDim2.fromScale(1, 1)
	f.BackgroundColor3 = rgb(48, 34, 20)
	f.BackgroundTransparency = 0.1
	f.BorderSizePixel = 0
	f.Parent = b
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 8)
	c.Parent = f

	local t = Instance.new("TextLabel")
	t.Size = UDim2.new(1, -10, subtitle and 0.6 or 1, 0)
	t.Position = UDim2.fromOffset(5, 3)
	t.BackgroundTransparency = 1
	t.Font = Enum.Font.FredokaOne
	t.TextScaled = true
	t.TextColor3 = rgb(244, 232, 210)
	t.Text = title
	t.Parent = f

	if subtitle then
		local s = Instance.new("TextLabel")
		s.Size = UDim2.new(1, -10, 0.36, 0)
		s.Position = UDim2.new(0, 5, 0.6, 0)
		s.BackgroundTransparency = 1
		s.Font = Enum.Font.Gotham
		s.TextScaled = true
		s.TextColor3 = rgb(206, 188, 150)
		s.Text = subtitle
		s.Parent = f
	end
end

----------------------------------------------------------------------
-- Terrain + props
----------------------------------------------------------------------

local function road(a: Vector3, b: Vector3, width: number, color: Color3?, material: Enum.Material?)
	local ay = Vector3.new(a.X, GY + 0.35, a.Z)
	local by = Vector3.new(b.X, GY + 0.35, b.Z)
	local mid = (ay + by) / 2
	local len = (by - ay).Magnitude
	if len < 0.1 then
		return
	end
	local cf = CFrame.lookAt(mid, by)
	make(terrainF, "Road", Vector3.new(width, 0.6, len), cf, color or PAL.PATH, material or Enum.Material.Ground)
end

local function tree(pos: Vector3, scale: number?)
	local s = scale or 1
	local h = 10 * s
	pillar(propsF, "Trunk", 1.6 * s, h, Vector3.new(pos.X, GY + h / 2, pos.Z), PAL.WOOD, Enum.Material.Wood)
	local topY = GY + h
	ball(propsF, "Leaves", 9 * s, Vector3.new(pos.X, topY, pos.Z), PAL.LEAF, Enum.Material.LeafyGrass)
	ball(propsF, "Leaves", 7 * s, Vector3.new(pos.X - 2.6 * s, topY - 1 * s, pos.Z + 1.4 * s), PAL.LEAF2, Enum.Material.LeafyGrass)
	ball(propsF, "Leaves", 6.4 * s, Vector3.new(pos.X + 2.4 * s, topY - 0.6 * s, pos.Z - 1.6 * s), PAL.LEAF3, Enum.Material.LeafyGrass)
	ball(propsF, "Leaves", 6 * s, Vector3.new(pos.X + 0.4 * s, topY + 2.2 * s, pos.Z + 0.2 * s), PAL.LEAF2, Enum.Material.LeafyGrass)
end

local function bush(pos: Vector3, scale: number?)
	local s = scale or 1
	ball(propsF, "Bush", 4 * s, Vector3.new(pos.X, GY + 1.4 * s, pos.Z), PAL.LEAF2, Enum.Material.LeafyGrass)
	ball(propsF, "Bush", 3.2 * s, Vector3.new(pos.X + 1.6 * s, GY + 1.1 * s, pos.Z + 0.8 * s), PAL.LEAF, Enum.Material.LeafyGrass)
end

local function rock(pos: Vector3, scale: number?)
	local s = scale or 1
	local cf = CFrame.new(Vector3.new(pos.X, GY + 1.2 * s, pos.Z)) * CFrame.Angles(math.rad(math.random(-20, 20)), math.rad(math.random(0, 360)), math.rad(math.random(-20, 20)))
	make(propsF, "Rock", Vector3.new(4 * s, 3 * s, 3.4 * s), cf, PAL.ROCK, Enum.Material.Slate)
end

local function hayBale(pos: Vector3)
	make(propsF, "HayBale", Vector3.new(3.6, 3, 3), CFrame.new(Vector3.new(pos.X, GY + 1.5, pos.Z)), PAL.HAY, Enum.Material.Grass, Enum.PartType.Cylinder)
end

local function barrel(pos: Vector3)
	pillar(propsF, "Barrel", 2, 2.6, Vector3.new(pos.X, GY + 1.3, pos.Z), PAL.WOOD, Enum.Material.Wood)
end

local function crate(pos: Vector3)
	make(propsF, "Crate", Vector3.new(2.4, 2.4, 2.4), CFrame.new(Vector3.new(pos.X, GY + 1.2, pos.Z)) * CFrame.Angles(0, math.rad(math.random(0, 40)), 0), PAL.WOOD_LIGHT, Enum.Material.WoodPlanks)
end

local function cart(pos: Vector3, yaw: number)
	local base = at(pos.X, pos.Z, yaw)
	make(propsF, "CartBed", Vector3.new(4.5, 1, 8), base * CFrame.new(0, 2.4, 0), PAL.WOOD, Enum.Material.WoodPlanks)
	make(propsF, "CartRail", Vector3.new(4.5, 1.4, 0.4), base * CFrame.new(0, 3.4, -3.8), PAL.WOOD_DARK, Enum.Material.Wood)
	for _, sx in { -1, 1 } do
		make(propsF, "Wheel", Vector3.new(0.5, 3, 3), base * CFrame.new(sx * 2.4, 1.5, 2.6) * CFrame.Angles(0, 0, math.rad(90)), PAL.WOOD_DARK, Enum.Material.Wood, Enum.PartType.Cylinder)
		make(propsF, "Wheel", Vector3.new(0.5, 3, 3), base * CFrame.new(sx * 2.4, 1.5, -2.6) * CFrame.Angles(0, 0, math.rad(90)), PAL.WOOD_DARK, Enum.Material.Wood, Enum.PartType.Cylinder)
	end
end

local function torch(pos: Vector3)
	pillar(propsF, "TorchPost", 0.5, 6, Vector3.new(pos.X, GY + 3, pos.Z), PAL.WOOD_DARK, Enum.Material.Wood)
	local head = ball(propsF, "Flame", 1.2, Vector3.new(pos.X, GY + 6.3, pos.Z), rgb(255, 160, 70), Enum.Material.Neon)
	local fire = Instance.new("Fire")
	fire.Size = 6
	fire.Heat = 6
	fire.Color = rgb(255, 150, 60)
	fire.SecondaryColor = rgb(220, 90, 40)
	fire.Parent = head
	local light = Instance.new("PointLight")
	light.Range = 20
	light.Brightness = 2.2
	light.Color = rgb(255, 175, 95)
	light.Parent = head
end

local function fenceLine(a: Vector3, b: Vector3, height: number?)
	local h = height or 3.5
	local ay = Vector3.new(a.X, GY, a.Z)
	local by = Vector3.new(b.X, GY, b.Z)
	local dir = by - ay
	local len = dir.Magnitude
	if len < 0.1 then
		return
	end
	local unit = dir.Unit
	local n = math.max(1, math.floor(len / 6))
	for i = 0, n do
		local p = ay + unit * (len * (i / n))
		make(propsF, "FencePost", Vector3.new(0.6, h, 0.6), CFrame.new(p + Vector3.new(0, h / 2, 0)), PAL.WOOD_DARK, Enum.Material.Wood)
	end
	local mid = (ay + by) / 2
	for _, ry in { h * 0.42, h * 0.8 } do
		local cf = CFrame.lookAt(mid + Vector3.new(0, ry, 0), by + Vector3.new(0, ry, 0))
		make(propsF, "Rail", Vector3.new(0.3, 0.4, len), cf, PAL.WOOD, Enum.Material.Wood)
	end
end

local function water(pos: Vector3, w: number, d: number)
	make(terrainF, "PondBank", Vector3.new(w + 10, 0.9, d + 10), CFrame.new(pos.X, GY + 0.1, pos.Z), rgb(150, 132, 96), Enum.Material.Sand)
	local p = make(terrainF, "Pond", Vector3.new(w, 1.2, d), CFrame.new(pos.X, GY + 0.25, pos.Z), PAL.WATER, Enum.Material.Glass)
	p.Transparency = 0.35
	p.Reflectance = 0.15
	p.CanCollide = false
end

local function farmPlot(pos: Vector3, w: number, d: number)
	make(terrainF, "Field", Vector3.new(w, 0.6, d), CFrame.new(pos.X, GY + 0.32, pos.Z), PAL.FIELD, Enum.Material.Ground)
	local rows = math.max(1, math.floor(w / 3))
	for i = 0, rows - 1 do
		local x = pos.X - w / 2 + 1.5 + i * 3
		make(propsF, "Crop", Vector3.new(1, 1.4, d - 2), CFrame.new(x, GY + 1, pos.Z), rgb(120, 160, 70), Enum.Material.Grass)
	end
end

local function scarecrow(pos: Vector3)
	local base = CFrame.new(Vector3.new(pos.X, GY, pos.Z))
	pillar(propsF, "Pole", 0.5, 7, wp(base, 0, 3.5, 0), PAL.WOOD_DARK, Enum.Material.Wood)
	make(propsF, "Arms", Vector3.new(6, 0.5, 0.5), base * CFrame.new(0, 5.4, 0), PAL.WOOD_DARK, Enum.Material.Wood)
	ball(propsF, "Head", 1.8, wp(base, 0, 7.2, 0), PAL.HAY, Enum.Material.Grass)
	make(propsF, "Shirt", Vector3.new(3, 3, 1.4), base * CFrame.new(0, 5, 0), PAL.CLOTH_RED, Enum.Material.Fabric)
end

----------------------------------------------------------------------
-- Living things (built into a given parent so they can start hidden)
----------------------------------------------------------------------

local function villager(parent: Instance, pos: Vector3, yaw: number, shirt: Color3)
	local m = Instance.new("Model")
	m.Name = "Villager"
	m.Parent = parent
	local base = at(pos.X, pos.Z, yaw)
	local function pp(name, size, x, y, z, color, mat, shape)
		return make(m, name, size, base * CFrame.new(x, y, z), color, mat, shape)
	end
	pp("Leg", Vector3.new(1.1, 3, 1.1), -0.7, 1.5, 0, rgb(74, 62, 50), Enum.Material.Fabric)
	pp("Leg", Vector3.new(1.1, 3, 1.1), 0.7, 1.5, 0, rgb(74, 62, 50), Enum.Material.Fabric)
	pp("Torso", Vector3.new(3, 3.4, 1.6), 0, 4.7, 0, shirt, Enum.Material.Fabric)
	pp("Arm", Vector3.new(1, 3, 1), -2, 4.6, 0, shirt, Enum.Material.Fabric)
	pp("Arm", Vector3.new(1, 3, 1), 2, 4.6, 0, shirt, Enum.Material.Fabric)
	pp("Head", Vector3.new(1.8, 1.8, 1.8), 0, 7.2, 0, PAL.SKIN, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
end

local function cow(parent: Instance, pos: Vector3, yaw: number)
	local m = Instance.new("Model")
	m.Name = "Cow"
	m.Parent = parent
	local base = at(pos.X, pos.Z, yaw)
	local function pp(name, size, x, y, z, color, mat, shape)
		return make(m, name, size, base * CFrame.new(x, y, z), color, mat, shape)
	end
	local white, dark = rgb(238, 236, 230), rgb(56, 50, 46)
	pp("Body", Vector3.new(3, 3, 6), 0, 4, 0, white, Enum.Material.SmoothPlastic)
	pp("Spot", Vector3.new(3.1, 1.7, 2), 0, 4.5, -1, dark, Enum.Material.SmoothPlastic)
	pp("Spot", Vector3.new(3.1, 1.4, 1.5), 0, 3.6, 1.4, dark, Enum.Material.SmoothPlastic)
	pp("Head", Vector3.new(2, 2, 2.2), 0, 4.6, 3.6, white, Enum.Material.SmoothPlastic)
	pp("Snout", Vector3.new(1.5, 1.2, 0.8), 0, 4.1, 4.7, rgb(226, 176, 176), Enum.Material.SmoothPlastic)
	pp("Horn", Vector3.new(0.4, 0.4, 1), -0.7, 5.6, 3.9, rgb(210, 205, 190), Enum.Material.SmoothPlastic)
	pp("Horn", Vector3.new(0.4, 0.4, 1), 0.7, 5.6, 3.9, rgb(210, 205, 190), Enum.Material.SmoothPlastic)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			pp("Leg", Vector3.new(0.8, 3, 0.8), sx * 1, 1.5, sz * 2, dark, Enum.Material.SmoothPlastic)
		end
	end
end

local function sheep(parent: Instance, pos: Vector3, yaw: number)
	local m = Instance.new("Model")
	m.Name = "Sheep"
	m.Parent = parent
	local base = at(pos.X, pos.Z, yaw)
	local function pp(name, size, x, y, z, color, mat, shape)
		return make(m, name, size, base * CFrame.new(x, y, z), color, mat, shape)
	end
	local wool, face = rgb(238, 234, 226), rgb(60, 56, 54)
	pp("Wool", Vector3.new(3.2, 3.2, 4.4), 0, 3.6, 0, wool, Enum.Material.SmoothPlastic)
	pp("Wool2", Vector3.new(3.7, 2.6, 3.4), 0, 4.3, 0, wool, Enum.Material.SmoothPlastic)
	pp("Head", Vector3.new(1.6, 1.8, 1.6), 0, 3.9, 2.9, face, Enum.Material.SmoothPlastic)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			pp("Leg", Vector3.new(0.7, 2.4, 0.7), sx * 0.9, 1.2, sz * 1.5, face, Enum.Material.SmoothPlastic)
		end
	end
end

local function pig(parent: Instance, pos: Vector3, yaw: number)
	local m = Instance.new("Model")
	m.Name = "Pig"
	m.Parent = parent
	local base = at(pos.X, pos.Z, yaw)
	local function pp(name, size, x, y, z, color, mat, shape)
		return make(m, name, size, base * CFrame.new(x, y, z), color, mat, shape)
	end
	local pink, dark = rgb(226, 152, 152), rgb(198, 120, 120)
	pp("Body", Vector3.new(2.6, 2.6, 4.4), 0, 2.9, 0, pink, Enum.Material.SmoothPlastic)
	pp("Head", Vector3.new(1.9, 1.9, 1.6), 0, 3, 2.6, pink, Enum.Material.SmoothPlastic)
	pp("Snout", Vector3.new(1.1, 1, 0.6), 0, 2.8, 3.5, dark, Enum.Material.SmoothPlastic)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			pp("Leg", Vector3.new(0.7, 1.8, 0.7), sx * 0.8, 0.9, sz * 1.4, dark, Enum.Material.SmoothPlastic)
		end
	end
end

local function chicken(parent: Instance, pos: Vector3, yaw: number)
	local m = Instance.new("Model")
	m.Name = "Chicken"
	m.Parent = parent
	local base = at(pos.X, pos.Z, yaw)
	local function pp(name, size, x, y, z, color, mat, shape)
		return make(m, name, size, base * CFrame.new(x, y, z), color, mat, shape)
	end
	local white = rgb(244, 242, 236)
	pp("Body", Vector3.new(1.3, 1.5, 1.8), 0, 1.9, 0, white, Enum.Material.SmoothPlastic)
	pp("Head", Vector3.new(0.9, 1, 0.9), 0, 3, 0.7, white, Enum.Material.SmoothPlastic)
	pp("Beak", Vector3.new(0.4, 0.3, 0.5), 0, 2.9, 1.3, rgb(240, 180, 60), Enum.Material.SmoothPlastic)
	pp("Comb", Vector3.new(0.3, 0.5, 0.6), 0, 3.6, 0.7, rgb(210, 70, 60), Enum.Material.SmoothPlastic)
	pp("Leg", Vector3.new(0.25, 1, 0.25), -0.35, 0.9, 0, rgb(240, 180, 60), Enum.Material.SmoothPlastic)
	pp("Leg", Vector3.new(0.25, 1, 0.25), 0.35, 0.9, 0, rgb(240, 180, 60), Enum.Material.SmoothPlastic)
end

----------------------------------------------------------------------
-- Buildings
----------------------------------------------------------------------

-- A gabled building built around baseCF (ground at local y=0, front faces +Z).
-- The roof is two tilted slabs, and the triangular gable ends are CLOSED with a
-- stack of tapered filler panels that hug the roofline (no WedgeParts, no open
-- shells). Corner beams + a solid door + windows finish the timber-framed look.
local function basicBuilding(baseCF: CFrame, opts)
	opts = opts or {}
	local W = opts.width or 15
	local D = opts.depth or 18
	local H = opts.height or 8
	local wt = opts.wallThickness or 0.7
	local wallColor = opts.wallColor or PAL.WALL
	local wallMat = opts.wallMaterial or Enum.Material.Brick
	local roofColor = opts.roofColor or PAL.ROOF_TILE
	local roofMat = opts.roofMaterial or Enum.Material.Slate
	local roofH = opts.roofHeight or (W * 0.34)
	local overhang = opts.overhang or 0.7
	local doorW = opts.doorWidth or 3.6
	local doorH = opts.doorHeight or 5.4
	local parent = opts.parent or structF
	local m = Instance.new("Model")
	m.Name = opts.name or "Building"
	m.Parent = parent

	local function put(name, size, x, y, z, color, mat, shape, rot)
		return make(m, name, size, baseCF * CFrame.new(x, y, z) * (rot or CFrame.new()), color, mat, shape)
	end

	local ft = 1.0 -- floor top (local y)
	local wallCenter = ft + H / 2
	local wallTop = ft + H

	-- Floor slab (slightly oversized so it reads as a foundation).
	put("Floor", Vector3.new(W + 0.6, 1, D + 0.6), 0, ft - 0.5, 0, PAL.WOOD_DARK, Enum.Material.WoodPlanks)

	-- Walls (back + sides solid; front has a door gap).
	put("WallBack", Vector3.new(W, H, wt), 0, wallCenter, -D / 2, wallColor, wallMat)
	put("WallLeft", Vector3.new(wt, H, D), -W / 2, wallCenter, 0, wallColor, wallMat)
	put("WallRight", Vector3.new(wt, H, D), W / 2, wallCenter, 0, wallColor, wallMat)

	local sideW = (W - doorW) / 2
	if not opts.noDoor then
		put("WallFrontL", Vector3.new(sideW, H, wt), -(doorW / 2 + sideW / 2), wallCenter, D / 2, wallColor, wallMat)
		put("WallFrontR", Vector3.new(sideW, H, wt), doorW / 2 + sideW / 2, wallCenter, D / 2, wallColor, wallMat)
		local lintelH = H - doorH
		if lintelH > 0.2 then
			put("Lintel", Vector3.new(doorW, lintelH, wt), 0, ft + doorH + lintelH / 2, D / 2, wallColor, wallMat)
		end
		put("Door", Vector3.new(doorW - 0.3, doorH - 0.2, 0.3), 0, ft + (doorH - 0.2) / 2, D / 2 + 0.15, PAL.WOOD_DARK, Enum.Material.WoodPlanks)
	else
		put("WallFront", Vector3.new(W, H, wt), 0, wallCenter, D / 2, wallColor, wallMat)
	end

	-- Corner beams (timber frame).
	if opts.timber ~= false then
		for _, cx in { -1, 1 } do
			for _, cz in { -1, 1 } do
				put("Beam", Vector3.new(0.9, H, 0.9), cx * (W / 2), wallCenter, cz * (D / 2), PAL.WOOD_DARK, Enum.Material.Wood)
			end
		end
	end

	-- Windows on the side walls.
	if opts.windows ~= false then
		local wy = ft + H * 0.55
		for _, zz in { -D * 0.26, D * 0.26 } do
			put("Window", Vector3.new(wt + 0.3, 2.4, 2.6), -W / 2, wy, zz, PAL.WINDOW, Enum.Material.Glass)
			put("Window", Vector3.new(wt + 0.3, 2.4, 2.6), W / 2, wy, zz, PAL.WINDOW, Enum.Material.Glass)
		end
	end

	-- Roof: two tilted slabs meeting at the ridge (x = 0).
	local halfW = W / 2 + overhang
	local slope = math.sqrt(halfW * halfW + roofH * roofH)
	local alpha = math.atan(roofH / halfW)
	local rd = D + overhang * 1.8
	local roofL = put("RoofL", Vector3.new(slope, 0.5, rd), -halfW / 2, wallTop + roofH / 2, 0, roofColor, roofMat, nil, CFrame.Angles(0, 0, alpha))
	local roofR = put("RoofR", Vector3.new(slope, 0.5, rd), halfW / 2, wallTop + roofH / 2, 0, roofColor, roofMat, nil, CFrame.Angles(0, 0, -alpha))
	put("Ridge", Vector3.new(0.9, 0.7, rd), 0, wallTop + roofH, 0, PAL.WOOD_DARK, Enum.Material.Wood)

	-- Closed, tapered gable ends (front + back) hugging the roofline.
	local steps = 6
	for k = 0, steps - 1 do
		local f = (k + 0.5) / steps
		local hw = halfW * (1 - f) * 0.98
		if hw > 0.4 then
			local gw = hw * 2
			local gy = wallTop + f * roofH
			local gh = (roofH / steps) * 1.06
			put("GableF", Vector3.new(gw, gh, wt), 0, gy, D / 2, wallColor, wallMat)
			put("GableB", Vector3.new(gw, gh, wt), 0, gy, -D / 2, wallColor, wallMat)
		end
	end

	-- Optional chimney with a wisp of smoke.
	if opts.chimney then
		local cxp = W / 2 - 2
		local chim = put("Chimney", Vector3.new(2.4, roofH + 4, 2.4), cxp, wallTop + (roofH + 4) / 2 - 1, -D / 4, PAL.STONE_DARK, Enum.Material.Slate)
		local smoke = Instance.new("Smoke")
		smoke.Size = 2
		smoke.RiseVelocity = 4
		smoke.Opacity = 0.25
		smoke.Color = rgb(210, 210, 210)
		smoke.Parent = chim
	end

	-- Rooftops are overgrown too: grass grows on the tilted slabs. This is COSMETIC
	-- overgrowth only (no District tag) -- roofs need climbing to reach, so requiring
	-- them would soft-lock a district. Ground carpets drive district completion.
	if opts.roofGrass ~= false then
		tagGrass(roofL, opts.roofGrassType or "Wild")
		tagGrass(roofR, opts.roofGrassType or "Wild")
	end

	return m, wallTop + roofH
end

-- Building presets (each just configures basicBuilding + a few extra props).
local function cottage(x, z, yaw, district)
	return basicBuilding(at(x, z, yaw), { width = 13, depth = 15, height = 7, wallColor = PAL.WALL2, roofColor = PAL.ROOF_THATCH, roofMaterial = Enum.Material.Grass, roofGrassType = "Meadow", name = "Cottage", district = district, chimney = true })
end

local function familyHouse(x, z, yaw, district)
	return basicBuilding(at(x, z, yaw), { width = 17, depth = 21, height = 9, wallColor = PAL.WALL, roofColor = PAL.ROOF_TILE, roofMaterial = Enum.Material.Slate, roofGrassType = "Wild", name = "FamilyHouse", district = district, chimney = true })
end

local function shed(x, z, yaw, district)
	return basicBuilding(at(x, z, yaw), { width = 11, depth = 13, height = 5.5, wallColor = PAL.WOOD, wallMaterial = Enum.Material.WoodPlanks, roofColor = PAL.ROOF_WOOD, roofMaterial = Enum.Material.WoodPlanks, roofGrassType = "Wild", name = "Shed", district = district, windows = false })
end

local function storehouse(x, z, yaw, district)
	return basicBuilding(at(x, z, yaw), { width = 15, depth = 18, height = 10, wallColor = PAL.WOOD_LIGHT, wallMaterial = Enum.Material.WoodPlanks, roofColor = PAL.ROOF_WOOD, roofMaterial = Enum.Material.WoodPlanks, roofGrassType = "Wild", name = "Storehouse", district = district })
end

local function barn(x, z, yaw, district)
	local m = basicBuilding(at(x, z, yaw), { width = 24, depth = 30, height = 12, roofHeight = 9, wallColor = PAL.BARN_RED, wallMaterial = Enum.Material.WoodPlanks, roofColor = PAL.ROOF_WOOD, roofMaterial = Enum.Material.WoodPlanks, roofGrassType = "Wild", name = "Barn", district = district, windows = false, doorWidth = 8, doorHeight = 9 })
	return m
end

local function tavern(x, z, yaw, district)
	local m = basicBuilding(at(x, z, yaw), { width = 22, depth = 26, height = 11, wallColor = PAL.WALL2, roofColor = PAL.ROOF_THATCH, roofMaterial = Enum.Material.Grass, roofGrassType = "Wild", name = "Tavern", district = district, chimney = true })
	local sign = make(structF, "TavernSign", Vector3.new(0.4, 3, 5), at(x, z, yaw) * CFrame.new(0, 8, 13.4), PAL.WOOD_DARK, Enum.Material.Wood)
	billboardSign(sign, "The Rusty Tankard", "Tavern", 2)
	return m
end

local function townHall(x, z, yaw, district)
	return basicBuilding(at(x, z, yaw), { width = 26, depth = 22, height = 12, wallColor = PAL.WALL, roofColor = PAL.ROOF_TILE, roofMaterial = Enum.Material.Slate, roofGrassType = "Wild", name = "TownHall", district = district, doorWidth = 5, doorHeight = 7 })
end

local function blacksmith(x, z, yaw, district)
	local base = at(x, z, yaw)
	local m = basicBuilding(base, { width = 18, depth = 20, height = 9, wallColor = PAL.STONE, wallMaterial = Enum.Material.Slate, roofColor = PAL.ROOF_SLATE, roofMaterial = Enum.Material.Slate, roofGrassType = "Wild", name = "Blacksmith", district = district, doorWidth = 6, doorHeight = 7 })
	-- Forge outside the door with fire + light + anvil.
	local forge = make(structF, "Forge", Vector3.new(4, 3, 4), base * CFrame.new(6, 1.5, 13), PAL.STONE_DARK, Enum.Material.Slate)
	local coals = make(structF, "Coals", Vector3.new(3, 1, 3), base * CFrame.new(6, 3.2, 13), rgb(255, 130, 50), Enum.Material.Neon)
	local fire = Instance.new("Fire")
	fire.Size = 5
	fire.Heat = 8
	fire.Parent = coals
	local pl = Instance.new("PointLight")
	pl.Range = 16
	pl.Brightness = 2
	pl.Color = rgb(255, 150, 80)
	pl.Parent = coals
	make(structF, "Anvil", Vector3.new(1.4, 1.6, 3), base * CFrame.new(-6, 1.8, 12), PAL.STONE_DARK, Enum.Material.Metal)
	return m
end

local function chapel(x, z, yaw, district)
	local base = at(x, z, yaw)
	local m = basicBuilding(base, { width = 16, depth = 26, height = 11, wallColor = PAL.WALL, wallMaterial = Enum.Material.Marble, roofColor = PAL.ROOF_SLATE, roofMaterial = Enum.Material.Slate, roofGrassType = "Wild", name = "Chapel", district = district, doorWidth = 4, doorHeight = 7 })
	-- Steeple with a cross.
	make(structF, "Steeple", Vector3.new(6, 16, 6), base * CFrame.new(0, 8, -11), PAL.STONE, Enum.Material.Marble)
	make(structF, "Spire", Vector3.new(4.2, 8, 4.2), base * CFrame.new(0, 19, -11) * CFrame.Angles(0, math.rad(45), 0), PAL.ROOF_SLATE, Enum.Material.Slate)
	make(structF, "CrossV", Vector3.new(0.5, 3, 0.5), base * CFrame.new(0, 25, -11), rgb(232, 210, 150), Enum.Material.Metal)
	make(structF, "CrossH", Vector3.new(2, 0.5, 0.5), base * CFrame.new(0, 25.4, -11), rgb(232, 210, 150), Enum.Material.Metal)
	return m
end

local function windmill(x, z, yaw, district)
	local base = at(x, z, yaw)
	pillar(structF, "MillTower", 14, 22, wp(base, 0, 11, 0), PAL.WALL2, Enum.Material.Brick)
	make(structF, "MillCap", Vector3.new(15, 6, 15), base * CFrame.new(0, 23, 0), PAL.ROOF_WOOD, Enum.Material.WoodPlanks)
	-- A tagged, tilted grass band could go here later; keep the cap clean for now.
	local hub = make(structF, "MillHub", Vector3.new(2, 2, 2), base * CFrame.new(0, 20, 8), PAL.WOOD_DARK, Enum.Material.Wood)
	for i = 0, 3 do
		local blade = make(structF, "Blade", Vector3.new(2.4, 16, 0.6), hub.CFrame * CFrame.Angles(0, 0, math.rad(i * 90)) * CFrame.new(0, 8, 0.4), PAL.WOOD_LIGHT, Enum.Material.WoodPlanks)
		blade.Color = PAL.WOOD_LIGHT
	end
	return nil
end

local function well(x, z)
	local base = at(x, z, 0)
	pillar(structF, "WellRing", 8, 3, wp(base, 0, 1.5, 0), PAL.STONE, Enum.Material.Cobblestone)
	pillar(structF, "WellInner", 6, 3.2, wp(base, 0, 1.6, 0), PAL.STONE_DARK, Enum.Material.Slate)
	local w = make(structF, "WellWater", Vector3.new(5.4, 0.4, 5.4), base * CFrame.new(0, 2.6, 0), PAL.WATER, Enum.Material.Glass)
	w.Transparency = 0.3
	for _, sx in { -1, 1 } do
		make(structF, "WellPost", Vector3.new(0.7, 6, 0.7), base * CFrame.new(sx * 3, 5, 0), PAL.WOOD_DARK, Enum.Material.Wood)
	end
	make(structF, "WellBeam", Vector3.new(7, 0.7, 0.7), base * CFrame.new(0, 8, 0), PAL.WOOD_DARK, Enum.Material.Wood)
	make(structF, "WellRoofL", Vector3.new(0.4, 4, 5), base * CFrame.new(-1.4, 9.6, 0) * CFrame.Angles(0, 0, math.rad(38)), PAL.ROOF_WOOD, Enum.Material.WoodPlanks)
	make(structF, "WellRoofR", Vector3.new(0.4, 4, 5), base * CFrame.new(1.4, 9.6, 0) * CFrame.Angles(0, 0, math.rad(-38)), PAL.ROOF_WOOD, Enum.Material.WoodPlanks)
	make(structF, "WellBucket", Vector3.new(1.4, 1.4, 1.4), base * CFrame.new(0, 6, 0), PAL.WOOD, Enum.Material.Wood, Enum.PartType.Cylinder)
end

local function marketStall(x, z, yaw, cloth)
	local base = at(x, z, yaw)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			make(structF, "StallPost", Vector3.new(0.5, 7, 0.5), base * CFrame.new(sx * 3, 3.5, sz * 2), PAL.WOOD_DARK, Enum.Material.Wood)
		end
	end
	make(structF, "StallCounter", Vector3.new(6.6, 1, 2), base * CFrame.new(0, 3.4, 2), PAL.WOOD, Enum.Material.WoodPlanks)
	-- striped awning (two colored slabs)
	make(structF, "AwningL", Vector3.new(3.6, 0.3, 5), base * CFrame.new(-1.7, 7.6, 0) * CFrame.Angles(math.rad(18), 0, 0), cloth, Enum.Material.Fabric)
	make(structF, "AwningR", Vector3.new(3.6, 0.3, 5), base * CFrame.new(1.7, 7.6, 0) * CFrame.Angles(math.rad(18), 0, 0), rgb(238, 232, 220), Enum.Material.Fabric)
	crate(wp(base, -2, 0, 2))
	barrel(wp(base, 2.4, 0, 2.4))
end

local function gardenerHut(x, z, yaw)
	local base = at(x, z, yaw)
	basicBuilding(base, { width = 12, depth = 12, height = 6, wallColor = PAL.WOOD_LIGHT, wallMaterial = Enum.Material.WoodPlanks, roofColor = PAL.ROOF_THATCH, roofMaterial = Enum.Material.Grass, roofGrassType = "Meadow", name = "GardenerHut", district = DISTRICT.Square })
	-- Garden beds out front.
	for i = -1, 1 do
		make(structF, "GardenBed", Vector3.new(3, 1, 6), base * CFrame.new(i * 4, 0.5, 10), PAL.DIRT, Enum.Material.Ground)
		make(propsF, "Sprouts", Vector3.new(2.6, 1.2, 5.4), base * CFrame.new(i * 4, 1.4, 10), rgb(120, 170, 80), Enum.Material.Grass)
	end
	-- Deposit anchor for the future Gardener (Phase 1) -- tagged for pickup by hand.
	local anchor = make(structF, "GardenerAnchor", Vector3.new(6, 0.4, 6), base * CFrame.new(0, 0.4, 6), PAL.PATH, Enum.Material.WoodPlanks)
	anchor:SetAttribute("ZoneKey", ZONE_KEY)
	CollectionService:AddTag(anchor, "GardenerSpot")
	local sign = make(structF, "GardenerSign", Vector3.new(0.4, 2.4, 4), base * CFrame.new(0, 6, 6.5), PAL.WOOD_DARK, Enum.Material.Wood)
	billboardSign(sign, "Gardener", "Deposit clippings", 1.5)
end

----------------------------------------------------------------------
-- Perimeter: palisade wall + four signed gates
----------------------------------------------------------------------

local function gate(cx, cz, yaw, title, subtitle)
	local base = at(cx, cz, yaw)
	for _, sx in { -1, 1 } do
		make(structF, "GatePost", Vector3.new(3, 16, 3), base * CFrame.new(sx * 8, 8, 0), PAL.STONE, Enum.Material.Cobblestone)
		torch(wp(base, sx * 8, 0, 4))
	end
	local lintel = make(structF, "GateLintel", Vector3.new(22, 3, 3), base * CFrame.new(0, 16.5, 0), PAL.WOOD_DARK, Enum.Material.Wood)
	billboardSign(lintel, title, subtitle, 3)
end

local function palisadeRun(x1, z1, x2, z2, gapCenter, gapHalf, along)
	-- along = "x" (wall runs along X) or "z" (runs along Z). Skips a gate gap.
	local step = 3
	if along == "x" then
		local z = z1
		local x = math.min(x1, x2)
		while x <= math.max(x1, x2) do
			if math.abs(x - gapCenter) > gapHalf then
				pillar(structF, "Palisade", 2.4, 10, Vector3.new(x, GY + 5, z), PAL.WOOD, Enum.Material.Wood)
				make(structF, "PaliTip", Vector3.new(2.2, 2, 2.2), CFrame.new(x, GY + 10.4, z) * CFrame.Angles(0, math.rad(45), 0), PAL.WOOD_DARK, Enum.Material.Wood)
			end
			x += step
		end
	else
		local x = x1
		local z = math.min(z1, z2)
		while z <= math.max(z1, z2) do
			if math.abs(z - gapCenter) > gapHalf then
				pillar(structF, "Palisade", 2.4, 10, Vector3.new(x, GY + 5, z), PAL.WOOD, Enum.Material.Wood)
				make(structF, "PaliTip", Vector3.new(2.2, 2, 2.2), CFrame.new(x, GY + 10.4, z) * CFrame.Angles(0, math.rad(45), 0), PAL.WOOD_DARK, Enum.Material.Wood)
			end
			z += step
		end
	end
end

local function buildPerimeter()
	local gap = 10
	palisadeRun(-P, -P, P, -P, 0, gap, "x") -- north (-Z)
	palisadeRun(-P, P, P, P, 0, gap, "x") -- south (+Z)
	palisadeRun(P, -P, P, P, 0, gap, "z") -- east (+X)
	palisadeRun(-P, -P, -P, P, 0, gap, "z") -- west (-X)
	gate(0, -P, 0, "To the Castle", "Locked")
	gate(0, P, 180, "Greenhollow", "Village 1")
	gate(P, 0, 90, "To Village 2", "Locked")
	gate(-P, 0, 270, "To Village 5", "Locked")
end

----------------------------------------------------------------------
-- World shell + roads
----------------------------------------------------------------------

local function buildWorld()
	make(terrainF, "Ground", Vector3.new(300, GROUND_THICKNESS, 300), CFrame.new(0, GY - GROUND_THICKNESS / 2, 0), PAL.GROUND, Enum.Material.Grass)
	make(terrainF, "Plains", Vector3.new(1700, 8, 1700), CFrame.new(0, GY - 0.6 - 4, 0), PAL.GROUND_DRY, Enum.Material.Grass)
end

local function buildRoads()
	road(Vector3.new(0, 0, 0), Vector3.new(0, 0, P), 9)
	road(Vector3.new(0, 0, 0), Vector3.new(0, 0, -P), 9)
	road(Vector3.new(0, 0, 0), Vector3.new(P, 0, 0), 9)
	road(Vector3.new(0, 0, 0), Vector3.new(-P, 0, 0), 9)
	road(Vector3.new(-112, 0, 78), Vector3.new(112, 0, 78), 8)
end

local function buildOutskirts()
	local placed = 0
	while placed < 140 do
		local ang = math.random() * math.pi * 2
		local dist = 155 + math.random() * 470
		local x = math.cos(ang) * dist
		local z = math.sin(ang) * dist
		local r = math.random()
		if r < 0.7 then
			tree(Vector3.new(x, 0, z), 0.8 + math.random() * 0.7)
		elseif r < 0.85 then
			rock(Vector3.new(x, 0, z), 0.8 + math.random())
		else
			bush(Vector3.new(x, 0, z), 0.8 + math.random())
		end
		placed += 1
	end
	water(Vector3.new(-260, 0, 240), 90, 60)
	for _, h in { Vector3.new(360, 0, -120), Vector3.new(-330, 0, -260), Vector3.new(300, 0, 320) } do
		make(terrainF, "Hill", Vector3.new(150, 36, 150), CFrame.new(h.X, GY - 13, h.Z), PAL.GROUND, Enum.Material.Grass, Enum.PartType.Ball)
	end
end

local function buildSpawn()
	local sp = Instance.new("SpawnLocation")
	sp.Name = "VillageSpawn"
	sp.Anchored = true
	sp.Size = Vector3.new(12, 1, 12)
	sp.CFrame = CFrame.new(0, GY + 0.6, 40) * CFrame.Angles(0, math.rad(180), 0)
	sp.Neutral = true
	sp.Duration = 0
	sp.Color = PAL.PATH
	sp.Material = Enum.Material.WoodPlanks
	sp.TopSurface = Enum.SurfaceType.Smooth
	sp.Parent = mapRoot
end

----------------------------------------------------------------------
-- Districts
----------------------------------------------------------------------

local function buildSquare()
	groundCarpet(DISTRICT.Square, "Meadow", 0, 0, 80, 80)
	well(0, 0)
	gardenerHut(20, 18, 200) -- mirrors the Shop (placed by ShopService at -20, 18)
	townHall(0, -33, 0)
	marketStall(-24, -8, 90, PAL.CLOTH_RED)
	marketStall(24, -8, 270, PAL.CLOTH_BLUE)
	for _, p in { Vector3.new(15, 0, 15), Vector3.new(-15, 0, 15), Vector3.new(15, 0, -15), Vector3.new(-15, 0, -15) } do
		torch(p)
	end
	cart(Vector3.new(28, 0, 22), 40)
	barrel(Vector3.new(-28, 0, 20))
	crate(Vector3.new(-26, 0, 25))
	local L = lifeModel(DISTRICT.Square)
	villager(L, Vector3.new(-24, 0, -3), 90, PAL.CLOTH_RED)
	villager(L, Vector3.new(24, 0, -3), 270, PAL.CLOTH_BLUE)
	villager(L, Vector3.new(6, 0, 8), 220, rgb(120, 150, 90))
	villager(L, Vector3.new(-8, 0, -10), 40, rgb(150, 120, 170))
end

local function buildResidential()
	groundCarpet(DISTRICT.Residential, "Wild", 0, 76, 224, 72)
	familyHouse(-82, 58, 0, DISTRICT.Residential)
	cottage(-40, 58, 0, DISTRICT.Residential)
	familyHouse(28, 58, 0, DISTRICT.Residential)
	cottage(72, 58, 0, DISTRICT.Residential)
	cottage(-70, 100, 180, DISTRICT.Residential)
	familyHouse(-20, 100, 180, DISTRICT.Residential)
	cottage(40, 100, 180, DISTRICT.Residential)
	familyHouse(90, 100, 180, DISTRICT.Residential)
	well(0, 78)
	torch(Vector3.new(-56, 0, 78))
	torch(Vector3.new(56, 0, 78))
	fenceLine(Vector3.new(-100, 0, 46), Vector3.new(-64, 0, 46))
	fenceLine(Vector3.new(-4, 0, 46), Vector3.new(48, 0, 46))
	for _, gx in { -82, -40, 28, 72 } do
		make(propsF, "Garden", Vector3.new(6, 1, 6), CFrame.new(gx, GY + 0.6, 72), rgb(120, 170, 80), Enum.Material.Grass)
	end
	local L = lifeModel(DISTRICT.Residential)
	villager(L, Vector3.new(-82, 0, 72), 180, rgb(150, 120, 90))
	villager(L, Vector3.new(-40, 0, 72), 180, PAL.CLOTH_BLUE)
	villager(L, Vector3.new(30, 0, 72), 160, rgb(120, 150, 110))
	villager(L, Vector3.new(-20, 0, 86), 0, PAL.CLOTH_RED)
	villager(L, Vector3.new(88, 0, 86), 20, rgb(170, 150, 90))
end

local function buildCraftsmen()
	groundCarpet(DISTRICT.Craftsmen, "Wild", 76, -36, 72, 152)
	blacksmith(74, -4, 270, DISTRICT.Craftsmen)
	tavern(78, -48, 270, DISTRICT.Craftsmen)
	storehouse(74, -92, 270, DISTRICT.Craftsmen)
	shed(60, 26, 270, DISTRICT.Craftsmen)
	windmill(100, -104, 0, DISTRICT.Craftsmen)
	marketStall(50, -28, 90, PAL.CLOTH_BLUE)
	barrel(Vector3.new(60, 0, -14))
	crate(Vector3.new(58, 0, -60))
	hayBale(Vector3.new(92, 0, -108))
	torch(Vector3.new(52, 0, -4))
	torch(Vector3.new(52, 0, -70))
	local L = lifeModel(DISTRICT.Craftsmen)
	villager(L, Vector3.new(80, 0, 10), 250, rgb(120, 120, 120))
	villager(L, Vector3.new(62, 0, -34), 90, PAL.CLOTH_RED)
	villager(L, Vector3.new(60, 0, -50), 110, rgb(150, 130, 90))
	villager(L, Vector3.new(62, 0, -92), 90, rgb(120, 150, 90))
end

local function buildFarmstead()
	groundCarpet(DISTRICT.Farmstead, "Wild", -76, 0, 72, 80)
	groundCarpet(DISTRICT.Farmstead, "Wild", -36, -76, 152, 72)
	barn(-86, -74, 90, DISTRICT.Farmstead)
	familyHouse(-32, -86, 0, DISTRICT.Farmstead)
	shed(-98, -28, 90, DISTRICT.Farmstead)
	shed(-98, 20, 90, DISTRICT.Farmstead)
	storehouse(-102, -92, 0, DISTRICT.Farmstead)
	farmPlot(Vector3.new(2, 0, -98), 46, 24)
	farmPlot(Vector3.new(-44, 0, -104), 40, 22)
	scarecrow(Vector3.new(2, 0, -98))
	scarecrow(Vector3.new(-44, 0, -104))
	hayBale(Vector3.new(-70, 0, -52))
	hayBale(Vector3.new(-64, 0, -52))
	-- pasture fence
	fenceLine(Vector3.new(-72, 0, -50), Vector3.new(-40, 0, -50))
	fenceLine(Vector3.new(-72, 0, -20), Vector3.new(-40, 0, -20))
	fenceLine(Vector3.new(-72, 0, -50), Vector3.new(-72, 0, -20))
	fenceLine(Vector3.new(-40, 0, -50), Vector3.new(-40, 0, -20))
	local L = lifeModel(DISTRICT.Farmstead)
	villager(L, Vector3.new(-84, 0, -58), 90, rgb(150, 120, 90))
	villager(L, Vector3.new(-34, 0, -72), 0, rgb(120, 150, 110))
	cow(L, Vector3.new(-60, 0, -30), 20)
	cow(L, Vector3.new(-52, 0, -40), -50)
	sheep(L, Vector3.new(-64, 0, -42), 120)
	sheep(L, Vector3.new(-46, 0, -32), 200)
	pig(L, Vector3.new(-96, 0, -60), 0)
	pig(L, Vector3.new(-90, 0, -66), 40)
	for _, c in { Vector3.new(-78, 0, -58), Vector3.new(-74, 0, -62), Vector3.new(-80, 0, -64), Vector3.new(-72, 0, -56) } do
		chicken(L, c, math.random(0, 360))
	end
end

local function buildVillage()
	buildWorld()
	buildPerimeter()
	buildRoads()
	buildSquare()
	buildResidential()
	buildCraftsmen()
	buildFarmstead()
	buildOutskirts()
	buildSpawn()
end

----------------------------------------------------------------------
-- Init
----------------------------------------------------------------------

function MapService.Init()
	-- Clear the default baseplate + any stray spawns so the world isn't an island.
	local bp = Workspace:FindFirstChild("Baseplate")
	if bp then
		bp:Destroy()
	end
	for _, c in Workspace:GetChildren() do
		if c:IsA("SpawnLocation") then
			c:Destroy()
		end
	end
	local existing = Workspace:FindFirstChild("Map")
	if existing then
		existing:Destroy()
	end

	mapRoot = Instance.new("Model")
	mapRoot.Name = "Map"
	mapRoot.Parent = Workspace
	terrainF = Instance.new("Folder")
	terrainF.Name = "Terrain"
	terrainF.Parent = mapRoot
	structF = Instance.new("Folder")
	structF.Name = "Structures"
	structF.Parent = mapRoot
	propsF = Instance.new("Folder")
	propsF.Name = "Props"
	propsF.Parent = mapRoot
	grassF = Instance.new("Folder")
	grassF.Name = "GrassSurfaces"
	grassF.Parent = mapRoot

	-- District life waits hidden in ServerStorage until its district is mowed.
	local oldLife = ServerStorage:FindFirstChild("DistrictLife")
	if oldLife then
		oldLife:Destroy()
	end
	lifeFolder = Instance.new("Folder")
	lifeFolder.Name = "DistrictLife"
	lifeFolder.Parent = ServerStorage
	lifeModels = {}

	math.randomseed(20260720)
	buildVillage()

	print("[MapService] Village 1 (Greenhollow) built.")
end

return MapService