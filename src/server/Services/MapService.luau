--!strict
-- MapService: procedurally builds the world, one village at a time.
--
-- WORLD PLAN (Medieval Dynasty-style): five villages ring a central castle.
-- Each village is a "zone" the player cleans of overgrown grass; clearing one
-- unlocks the next. Village 1 is the starting area (it holds the shop + gardener).
-- Only Village 1 is built so far; its gates already point at where Villages 2 & 5
-- and the Castle will connect.
--
-- Everything is generated in code so the world stays reproducible and tweakable:
-- adjust the layout tables / constants below to reshape the village. Any part we
-- want the player to mow is tagged GameConfig.GRASS_SURFACE_TAG with a GrassType
-- attribute, so GrassService grows grass on it automatically -- including on the
-- tilted roof slabs (its top face aims along the slope), which sets up the future
-- roof-climbing gameplay.

local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

local MapService = {}

----------------------------------------------------------------------
-- Constants / palette
----------------------------------------------------------------------

local GY = 0 -- ground top height; everything builds up from here
local ZONE_KEY = "Village1"
local P = 130 -- half-size of the village (palisade sits at +/-P)

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
	ROOF_THATCH = rgb(176, 138, 78),
	ROOF_WOOD = rgb(104, 72, 46),
	ROOF_TILE = rgb(138, 78, 60),
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

local function tagGrass(part: BasePart, grassType: string)
	part:SetAttribute("GrassType", grassType)
	part:SetAttribute("ZoneKey", ZONE_KEY)
	CollectionService:AddTag(part, GameConfig.GRASS_SURFACE_TAG)
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
	local ay = Vector3.new(a.X, GY + 0.3, a.Z)
	local by = Vector3.new(b.X, GY + 0.3, b.Z)
	local mid = (ay + by) / 2
	local len = (by - ay).Magnitude
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

local function flowers(pos: Vector3)
	local cols = { rgb(230, 96, 110), rgb(240, 214, 90), rgb(150, 120, 220), rgb(240, 240, 240) }
	for _ = 1, math.random(3, 6) do
		local ox = (math.random() - 0.5) * 4
		local oz = (math.random() - 0.5) * 4
		make(propsF, "Stem", Vector3.new(0.2, 1.2, 0.2), CFrame.new(pos.X + ox, GY + 0.6, pos.Z + oz), PAL.LEAF, Enum.Material.Grass)
		ball(propsF, "Bloom", 0.7, Vector3.new(pos.X + ox, GY + 1.3, pos.Z + oz), cols[math.random(#cols)], Enum.Material.SmoothPlastic)
	end
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
	local base = CFrame.new(Vector3.new(pos.X, GY, pos.Z)) * CFrame.Angles(0, math.rad(yaw), 0)
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

local function grassPatch(x: number, z: number, w: number, d: number, grassType: string)
	local p = make(grassF, "GrassPatch", Vector3.new(w, 0.6, d), CFrame.new(x, GY + 0.3, z), PAL.DIRT, Enum.Material.Ground)
	tagGrass(p, grassType)
	return p
end

local function water(pos: Vector3, w: number, d: number)
	make(terrainF, "PondBank", Vector3.new(w + 10, 0.9, d + 10), CFrame.new(pos.X, GY + 0.1, pos.Z), rgb(150, 132, 96), Enum.Material.Sand)
	local p = make(terrainF, "Pond", Vector3.new(w, 1.2, d), CFrame.new(pos.X, GY + 0.25, pos.Z), PAL.WATER, Enum.Material.Glass)
	p.Transparency = 0.35
	p.Reflectance = 0.15
	p.CanCollide = false
end

local function farmPlot(pos: Vector3, w: number, d: number)
	make(terrainF, "Field", Vector3.new(w, 0.6, d), CFrame.new(pos.X, GY + 0.3, pos.Z), PAL.FIELD, Enum.Material.Ground)
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

local function villager(pos: Vector3, yaw: number, shirt: Color3)
	local m = Instance.new("Model")
	m.Name = "Villager"
	m.Parent = propsF
	local base = CFrame.new(Vector3.new(pos.X, GY, pos.Z)) * CFrame.Angles(0, math.rad(yaw), 0)
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

----------------------------------------------------------------------
-- Buildings
----------------------------------------------------------------------

-- A generic gabled building, built around baseCF (ground at local y=0, front
-- faces +Z). Two tilted slabs form the roof so no WedgeParts are needed. Returns
-- the model and the ridge height.
local function basicBuilding(baseCF: CFrame, opts)
	opts = opts or {}
	local W = opts.width or 16
	local D = opts.depth or 20
	local H = opts.height or 9
	local wallColor = opts.wallColor or PAL.WALL
	local wallMat = opts.wallMaterial or Enum.Material.Brick
	local roofColor = opts.roofColor or PAL.ROOF_WOOD
	local roofMat = opts.roofMaterial or Enum.Material.WoodPlanks
	local roofH = opts.roofHeight or (W * 0.42)
	local doorW = opts.doorWidth or 4
	local doorH = opts.doorHeight or 6
	local parent = opts.parent or structF
	local m = Instance.new("Model")
	m.Name = opts.name or "Building"
	m.Parent = parent

	local function put(name, size, x, y, z, color, mat, shape, rot)
		return make(m, name, size, baseCF * CFrame.new(x, y, z) * (rot or CFrame.new()), color, mat, shape)
	end

	local floorTop = 1
	local wt = 0.7
	local wy = floorTop + H / 2
	put("Floor", Vector3.new(W, 1, D), 0, 0.5, 0, PAL.WOOD_DARK, Enum.Material.WoodPlanks)
	put("WallBack", Vector3.new(W, H, wt), 0, wy, -D / 2, wallColor, wallMat)
	put("WallLeft", Vector3.new(wt, H, D), -W / 2, wy, 0, wallColor, wallMat)
	put("WallRight", Vector3.new(wt, H, D), W / 2, wy, 0, wallColor, wallMat)
	local segW = (W - doorW) / 2
	put("WallFrontL", Vector3.new(segW, H, wt), -(doorW / 2 + segW / 2), wy, D / 2, wallColor, wallMat)
	put("WallFrontR", Vector3.new(segW, H, wt), (doorW / 2 + segW / 2), wy, D / 2, wallColor, wallMat)
	put("WallFrontTop", Vector3.new(doorW, H - doorH, wt), 0, floorTop + doorH + (H - doorH) / 2, D / 2, wallColor, wallMat)
	if not opts.noDoor then
		put("Door", Vector3.new(doorW - 0.3, doorH - 0.2, 0.35), 0, floorTop + (doorH - 0.2) / 2, D / 2 + 0.05, PAL.WOOD_DARK, Enum.Material.WoodPlanks)
	end
	if opts.timber ~= false then
		for _, sx in { -1, 1 } do
			for _, sz in { -1, 1 } do
				put("Post", Vector3.new(1, H, 1), sx * (W / 2 - 0.2), wy, sz * (D / 2 - 0.2), PAL.WOOD_DARK, Enum.Material.Wood)
			end
		end
	end
	if opts.windows ~= false then
		local wyw = floorTop + H * 0.55
		put("Window", Vector3.new(0.3, 2.6, 2.8), -W / 2, wyw, D * 0.22, PAL.WINDOW, Enum.Material.Glass)
		put("Window", Vector3.new(0.3, 2.6, 2.8), -W / 2, wyw, -D * 0.22, PAL.WINDOW, Enum.Material.Glass)
		put("Window", Vector3.new(0.3, 2.6, 2.8), W / 2, wyw, D * 0.22, PAL.WINDOW, Enum.Material.Glass)
		put("Window", Vector3.new(0.3, 2.6, 2.8), W / 2, wyw, -D * 0.22, PAL.WINDOW, Enum.Material.Glass)
		put("Window", Vector3.new(2.8, 2.6, 0.3), 0, wyw, -D / 2, PAL.WINDOW, Enum.Material.Glass)
	end

	local wallTopLocalY = floorTop + H
	local overhang = opts.overhang or 1.4
	local halfW = W / 2 + overhang
	local slopeLen = math.sqrt(halfW * halfW + roofH * roofH)
	local alpha = math.atan(roofH, halfW)
	local rd = D + overhang * 1.6
	local roofL = put("RoofL", Vector3.new(slopeLen, 0.6, rd), -halfW / 2, wallTopLocalY + roofH / 2, 0, roofColor, roofMat, nil, CFrame.Angles(0, 0, alpha))
	local roofR = put("RoofR", Vector3.new(slopeLen, 0.6, rd), halfW / 2, wallTopLocalY + roofH / 2, 0, roofColor, roofMat, nil, CFrame.Angles(0, 0, -alpha))
	put("Ridge", Vector3.new(1.2, 0.7, rd), 0, wallTopLocalY + roofH, 0, roofColor, roofMat)
	local ridgeH = wallTopLocalY + roofH

	if opts.roofGrass then
		tagGrass(roofL, opts.roofGrassType or "Meadow")
		tagGrass(roofR, opts.roofGrassType or "Meadow")
	end

	if opts.chimney then
		local chTop = ridgeH + 3
		local chH = chTop - floorTop
		put("Chimney", Vector3.new(2.2, chH, 2.2), W / 2 - 2.4, floorTop + chH / 2, -D / 2 + 2.6, PAL.STONE_DARK, Enum.Material.Cobblestone)
		if opts.smoke then
			local emit = ball(m, "Ember", 0.6, wp(baseCF, W / 2 - 2.4, chTop + 0.4, -D / 2 + 2.6), rgb(90, 80, 74), Enum.Material.SmoothPlastic)
			local sm = Instance.new("ParticleEmitter")
			sm.Rate = 5
			sm.Lifetime = NumberRange.new(2.4, 3.4)
			sm.Speed = NumberRange.new(2, 3)
			sm.Size = NumberSequence.new(2.6)
			sm.Transparency = NumberSequence.new(0.5)
			sm.Color = ColorSequence.new(rgb(120, 112, 104))
			sm.Rotation = NumberRange.new(0, 360)
			sm.Parent = emit
		end
	end

	return m, ridgeH
end

local function cottage(baseCF: CFrame, o)
	o = o or {}
	o.name = o.name or "Cottage"
	o.width = o.width or 13
	o.depth = o.depth or 15
	o.height = o.height or 7
	o.wallColor = o.wallColor or PAL.WALL2
	o.roofColor = o.roofColor or PAL.ROOF_THATCH
	o.roofMaterial = o.roofMaterial or Enum.Material.Fabric
	if o.chimney == nil then
		o.chimney = true
	end
	return basicBuilding(baseCF, o)
end

local function familyHouse(baseCF: CFrame, o)
	o = o or {}
	o.name = o.name or "House"
	o.width = o.width or 17
	o.depth = o.depth or 21
	o.height = o.height or 9
	o.roofColor = o.roofColor or PAL.ROOF_TILE
	o.roofMaterial = o.roofMaterial or Enum.Material.Slate
	if o.chimney == nil then
		o.chimney = true
	end
	return basicBuilding(baseCF, o)
end

local function shed(baseCF: CFrame, o)
	o = o or {}
	o.name = o.name or "Farmer's Shed"
	o.width = o.width or 11
	o.depth = o.depth or 9
	o.height = o.height or 6
	o.wallColor = o.wallColor or PAL.WOOD_LIGHT
	o.wallMaterial = Enum.Material.WoodPlanks
	o.roofColor = PAL.ROOF_WOOD
	o.windows = false
	local m = basicBuilding(baseCF, o)
	crate(wp(baseCF, o.width / 2 + 2, 0, 2))
	barrel(wp(baseCF, o.width / 2 + 2, 0, -2))
	return m
end

local function storehouse(baseCF: CFrame, o)
	o = o or {}
	o.name = o.name or "Storehouse"
	o.width = o.width or 16
	o.depth = o.depth or 18
	o.height = o.height or 8
	o.wallColor = PAL.WOOD_LIGHT
	o.wallMaterial = Enum.Material.WoodPlanks
	o.roofColor = PAL.ROOF_WOOD
	o.windows = false
	return basicBuilding(baseCF, o)
end

local function barn(baseCF: CFrame, o)
	o = o or {}
	o.name = o.name or "Barn"
	o.width = o.width or 22
	o.depth = o.depth or 30
	o.height = o.height or 12
	o.wallColor = o.wallColor or rgb(150, 80, 66)
	o.wallMaterial = Enum.Material.WoodPlanks
	o.roofColor = PAL.ROOF_WOOD
	o.roofHeight = 11
	o.doorWidth = 8
	o.doorHeight = 9
	o.windows = false
	local m = basicBuilding(baseCF, o)
	hayBale(wp(baseCF, o.width / 2 + 3, 0, 6))
	hayBale(wp(baseCF, o.width / 2 + 3, 0, 2.4))
	hayBale(wp(baseCF, -o.width / 2 - 3, 0, -6))
	cart(wp(baseCF, 0, 0, o.depth / 2 + 6), 0)
	return m
end

local function tavern(baseCF: CFrame)
	local o = { name = "Tavern", width = 22, depth = 26, height = 12, wallColor = rgb(212, 198, 166), roofColor = PAL.ROOF_SLATE, roofMaterial = Enum.Material.Slate, chimney = true, smoke = true, doorWidth = 5, doorHeight = 7 }
	local m = basicBuilding(baseCF, o)
	local board = make(m, "SignBoard", Vector3.new(4.5, 3, 0.4), baseCF * CFrame.new(o.width / 2 + 0.3, 6.6, o.depth / 2 - 3), rgb(84, 54, 30), Enum.Material.WoodPlanks)
	make(m, "SignArm", Vector3.new(3.4, 0.5, 0.5), baseCF * CFrame.new(o.width / 2 - 1.2, 8.4, o.depth / 2 - 3), PAL.WOOD_DARK, Enum.Material.Wood)
	make(m, "SignPost", Vector3.new(0.6, 9, 0.6), baseCF * CFrame.new(o.width / 2 + 2, 4.5, o.depth / 2 - 3), PAL.WOOD_DARK, Enum.Material.Wood)
	billboardSign(board, "The Rusty Tankard", "Tavern", 1.8)
	barrel(wp(baseCF, o.width / 2 + 3, 0, o.depth / 2 - 8))
	barrel(wp(baseCF, o.width / 2 + 5, 0, o.depth / 2 - 8))
	torch(wp(baseCF, -o.width / 2 - 1, 0, o.depth / 2 + 1))
	return m
end

local function blacksmith(baseCF: CFrame)
	local o = { name = "Blacksmith", width = 16, depth = 18, height = 9, wallColor = rgb(120, 112, 104), wallMaterial = Enum.Material.Cobblestone, roofColor = PAL.ROOF_WOOD, chimney = true, smoke = true }
	local m = basicBuilding(baseCF, o)
	make(m, "Forge", Vector3.new(4, 3, 4), baseCF * CFrame.new(-(o.width / 2) - 3, 2.5, 2), PAL.STONE_DARK, Enum.Material.Cobblestone)
	local ember = make(m, "Ember", Vector3.new(2, 1, 2), baseCF * CFrame.new(-(o.width / 2) - 3, 4.2, 2), rgb(255, 120, 40), Enum.Material.Neon)
	local fire = Instance.new("Fire")
	fire.Size = 5
	fire.Heat = 6
	fire.Color = rgb(255, 140, 50)
	fire.Parent = ember
	local light = Instance.new("PointLight")
	light.Range = 16
	light.Brightness = 2
	light.Color = rgb(255, 150, 70)
	light.Parent = ember
	make(m, "Anvil", Vector3.new(1.4, 1.6, 3), baseCF * CFrame.new(-(o.width / 2) - 6, 1.8, -2), rgb(60, 60, 64), Enum.Material.Metal)
	return m
end

local function chapel(baseCF: CFrame)
	local o = { name = "Chapel", width = 16, depth = 28, height = 11, wallColor = PAL.STONE, wallMaterial = Enum.Material.Cobblestone, roofColor = PAL.ROOF_SLATE, roofMaterial = Enum.Material.Slate, doorHeight = 7 }
	local m = basicBuilding(baseCF, o)
	make(m, "Steeple", Vector3.new(7, 26, 7), baseCF * CFrame.new(0, 13, o.depth / 2 + 3.5), PAL.STONE, Enum.Material.Cobblestone)
	make(m, "SteepleCap", Vector3.new(7.4, 1, 7.4), baseCF * CFrame.new(0, 26.5, o.depth / 2 + 3.5), PAL.ROOF_SLATE, Enum.Material.Slate)
	make(m, "SteepleRoof", Vector3.new(5.5, 5, 5.5), baseCF * CFrame.new(0, 29, o.depth / 2 + 3.5), PAL.ROOF_SLATE, Enum.Material.Slate)
	make(m, "CrossV", Vector3.new(0.5, 4, 0.5), baseCF * CFrame.new(0, 33, o.depth / 2 + 3.5), rgb(232, 216, 160), Enum.Material.Metal)
	make(m, "CrossH", Vector3.new(2.4, 0.5, 0.5), baseCF * CFrame.new(0, 33.6, o.depth / 2 + 3.5), rgb(232, 216, 160), Enum.Material.Metal)
	return m
end

local function well(pos: Vector3)
	local base = CFrame.new(Vector3.new(pos.X, GY, pos.Z))
	pillar(structF, "WellRing", 8, 3, wp(base, 0, 1.5, 0), PAL.STONE, Enum.Material.Cobblestone)
	local w = pillar(structF, "WellWater", 6, 0.4, wp(base, 0, 2.9, 0), PAL.WATER, Enum.Material.Glass)
	w.Transparency = 0.3
	w.Reflectance = 0.2
	make(structF, "WellPostA", Vector3.new(0.7, 7, 0.7), base * CFrame.new(-3.2, 4.5, 0), PAL.WOOD_DARK, Enum.Material.Wood)
	make(structF, "WellPostB", Vector3.new(0.7, 7, 0.7), base * CFrame.new(3.2, 4.5, 0), PAL.WOOD_DARK, Enum.Material.Wood)
	make(structF, "WellBeam", Vector3.new(7, 0.7, 0.7), base * CFrame.new(0, 8, 0), PAL.WOOD_DARK, Enum.Material.Wood)
	make(structF, "WellRoofL", Vector3.new(6, 0.5, 8), base * CFrame.new(-1.6, 9.2, 0) * CFrame.Angles(0, 0, math.rad(38)), PAL.ROOF_WOOD, Enum.Material.WoodPlanks)
	make(structF, "WellRoofR", Vector3.new(6, 0.5, 8), base * CFrame.new(1.6, 9.2, 0) * CFrame.Angles(0, 0, math.rad(-38)), PAL.ROOF_WOOD, Enum.Material.WoodPlanks)
end

local function marketStall(pos: Vector3, yaw: number, cloth: Color3)
	local base = CFrame.new(Vector3.new(pos.X, GY, pos.Z)) * CFrame.Angles(0, math.rad(yaw), 0)
	make(structF, "StallCounter", Vector3.new(8, 2.4, 3), base * CFrame.new(0, 1.4, 1.6), PAL.WOOD, Enum.Material.WoodPlanks)
	for _, sx in { -1, 1 } do
		make(structF, "StallPost", Vector3.new(0.5, 7, 0.5), base * CFrame.new(sx * 3.6, 3.5, 0), PAL.WOOD_DARK, Enum.Material.Wood)
		make(structF, "StallPost", Vector3.new(0.5, 7, 0.5), base * CFrame.new(sx * 3.6, 3.5, 3), PAL.WOOD_DARK, Enum.Material.Wood)
	end
	make(structF, "StallAwning", Vector3.new(9, 0.4, 5), base * CFrame.new(0, 7.2, 1.4) * CFrame.Angles(math.rad(-16), 0, 0), cloth, Enum.Material.Fabric)
	crate(wp(base, -2, 0, 1.6))
	barrel(wp(base, 2.6, 0, 1.6))
end

local function windmill(pos: Vector3)
	local base = CFrame.new(Vector3.new(pos.X, GY, pos.Z))
	pillar(structF, "MillTower", 12, 22, wp(base, 0, 11, 0), rgb(200, 186, 158), Enum.Material.Brick)
	pillar(structF, "MillCap", 13, 4, wp(base, 0, 23, 0), PAL.ROOF_WOOD, Enum.Material.WoodPlanks)
	make(structF, "MillHub", Vector3.new(2, 2, 2), base * CFrame.new(0, 18, 6.5), PAL.WOOD_DARK, Enum.Material.Wood)
	for i = 0, 3 do
		make(structF, "Blade", Vector3.new(2.4, 16, 0.6), base * CFrame.new(0, 18, 6.9) * CFrame.Angles(0, 0, math.rad(i * 90)), PAL.WOOD_LIGHT, Enum.Material.WoodPlanks)
	end
	make(structF, "MillDoor", Vector3.new(4, 6, 0.4), base * CFrame.new(0, 4, 6.05), PAL.WOOD_DARK, Enum.Material.WoodPlanks)
end

local function watchtower(pos: Vector3, o)
	o = o or {}
	local base = CFrame.new(Vector3.new(pos.X, GY, pos.Z))
	local h = o.height or 20
	make(structF, "TowerBody", Vector3.new(9, h, 9), base * CFrame.new(0, h / 2, 0), PAL.STONE, Enum.Material.Cobblestone)
	make(structF, "TowerPlat", Vector3.new(12, 1, 12), base * CFrame.new(0, h + 0.5, 0), PAL.STONE_DARK, Enum.Material.Cobblestone)
	make(structF, "MerlonN", Vector3.new(12, 2, 1), base * CFrame.new(0, h + 2, 6), PAL.STONE, Enum.Material.Cobblestone)
	make(structF, "MerlonS", Vector3.new(12, 2, 1), base * CFrame.new(0, h + 2, -6), PAL.STONE, Enum.Material.Cobblestone)
	make(structF, "MerlonE", Vector3.new(1, 2, 12), base * CFrame.new(6, h + 2, 0), PAL.STONE, Enum.Material.Cobblestone)
	make(structF, "MerlonW", Vector3.new(1, 2, 12), base * CFrame.new(-6, h + 2, 0), PAL.STONE, Enum.Material.Cobblestone)
	make(structF, "TowerDoor", Vector3.new(3.4, 6, 0.4), base * CFrame.new(0, 4, 4.55), PAL.WOOD_DARK, Enum.Material.WoodPlanks)
	torch(wp(base, 6, 0, 6))
	torch(wp(base, -6, 0, 6))
end

local function gardenerHut(pos: Vector3, yaw: number)
	local base = CFrame.new(Vector3.new(pos.X, GY, pos.Z)) * CFrame.Angles(0, math.rad(yaw), 0)
	local m = cottage(base, { name = "Gardener's Hut", width = 14, depth = 16, height = 8, wallColor = rgb(206, 198, 170), roofColor = PAL.ROOF_THATCH })
	for i = -1, 1 do
		local bed = make(m, "GardenBed", Vector3.new(4, 0.8, 8), base * CFrame.new(i * 5, 0.4, 12), PAL.FIELD, Enum.Material.Ground)
		bed.CanCollide = false
		for j = -2, 2 do
			make(m, "Sprout", Vector3.new(0.8, 1.6, 0.8), base * CFrame.new(i * 5, 1.2, 12 + j * 1.6), rgb(120, 170, 80), Enum.Material.Grass)
		end
	end
	local anchor = make(m, "GardenerAnchor", Vector3.new(6, 0.3, 6), base * CFrame.new(0, 0.2, 8), rgb(196, 170, 120), Enum.Material.Sand)
	anchor:SetAttribute("ZoneKey", ZONE_KEY)
	CollectionService:AddTag(anchor, "GardenerSpot")
	billboardSign(anchor, "Gardener", "Deposit clippings here", 4)
	villager(wp(base, 0, 0, 6), yaw + 180, PAL.CLOTH_BLUE)
	return m
end

local function gate(pos: Vector3, axis: string, title: string, subtitle: string)
	local half = 8
	local off = (axis == "x") and Vector3.new(half, 0, 0) or Vector3.new(0, 0, half)
	pillar(structF, "GatePillar", 2.6, 13, Vector3.new(pos.X, GY + 6.5, pos.Z) - off, PAL.STONE, Enum.Material.Cobblestone)
	pillar(structF, "GatePillar", 2.6, 13, Vector3.new(pos.X, GY + 6.5, pos.Z) + off, PAL.STONE, Enum.Material.Cobblestone)
	local beamSize = (axis == "x") and Vector3.new(half * 2 + 3, 2, 3) or Vector3.new(3, 2, half * 2 + 3)
	local beam = make(structF, "GateBeam", beamSize, CFrame.new(pos.X, GY + 13, pos.Z), PAL.WOOD_DARK, Enum.Material.Wood)
	billboardSign(beam, title, subtitle, 2.4)
	torch(Vector3.new(pos.X, GY, pos.Z) - off * 1.3)
	torch(Vector3.new(pos.X, GY, pos.Z) + off * 1.3)
end

local function buildSpawn(pos: Vector3)
	for _, inst in Workspace:GetDescendants() do
		if inst:IsA("SpawnLocation") then
			inst:Destroy()
		end
	end
	local s = Instance.new("SpawnLocation")
	s.Name = "VillageSpawn"
	s.Anchored = true
	s.Size = Vector3.new(12, 1, 12)
	s.CFrame = CFrame.new(Vector3.new(pos.X, GY + 0.5, pos.Z))
	s.Color = rgb(150, 150, 150)
	s.Material = Enum.Material.Cobblestone
	s.Neutral = true
	s.Duration = 0
	s.TopSurface = Enum.SurfaceType.Smooth
	s.Parent = mapRoot
end

----------------------------------------------------------------------
-- Village 1 -- "Greenhollow"
----------------------------------------------------------------------

local function buildVillage()
	math.randomseed(20260720)

	-- Base ground (visual only -- NOT tagged, so it grows no cuttable grass).
	make(terrainF, "Ground", Vector3.new(440, 4, 440), CFrame.new(0, GY - 2, 0), PAL.GROUND, Enum.Material.Grass)
	-- Packed-dirt village square at the origin.
	make(terrainF, "Square", Vector3.new(70, 0.5, 70), CFrame.new(0, GY + 0.25, 0), rgb(150, 132, 100), Enum.Material.Ground)

	-- Main roads through the four gates (N=castle, S=entrance, E=Village 2, W=Village 5).
	road(Vector3.new(0, 0, P + 60), Vector3.new(0, 0, -(P + 60)), 12)
	road(Vector3.new(-(P + 60), 0, 0), Vector3.new(P + 60, 0, 0), 12)

	-- Square centerpiece + dressing.
	well(Vector3.new(0, 0, 0))
	torch(Vector3.new(-26, 0, 26))
	torch(Vector3.new(26, 0, 26))
	torch(Vector3.new(-26, 0, -26))
	torch(Vector3.new(26, 0, -26))
	marketStall(Vector3.new(-20, 0, -14), 20, PAL.CLOTH_RED)
	marketStall(Vector3.new(20, 0, -16), -20, PAL.CLOTH_BLUE)
	marketStall(Vector3.new(0, 0, -26), 0, PAL.CLOTH_BLUE)
	cart(Vector3.new(14, 0, 6), 40)
	villager(Vector3.new(-8, 0, 10), 200, PAL.CLOTH_RED)
	villager(Vector3.new(10, 0, -6), 20, PAL.CLOTH_BLUE)
	villager(Vector3.new(4, 0, 20), 120, rgb(150, 140, 90))

	-- Gardener's hut beside the shop (shop is spawned by ShopService at SHOP_POSITION).
	gardenerHut(Vector3.new(20, 0, 18), 180)

	local function at(x, z, yaw)
		return CFrame.new(Vector3.new(x, GY, z)) * CFrame.Angles(0, math.rad(yaw), 0)
	end

	-- Northwest quarter (toward the castle)
	tavern(at(-42, -30, 130))
	familyHouse(at(-66, -20, 90), { roofGrass = true, roofGrassType = "Meadow" })
	cottage(at(-72, -46, 90))
	blacksmith(at(-38, -60, 180))
	storehouse(at(-60, -74, 160))
	chapel(at(-18, -86, 180))

	-- Northeast quarter
	barn(at(48, -40, 225))
	familyHouse(at(68, -24, 270), { roofGrass = true, roofGrassType = "Wild" })
	cottage(at(74, -52, 270), { roofGrass = true })
	familyHouse(at(40, -64, 175), { name = "Bakery", smoke = true, roofColor = PAL.ROOF_TILE })
	windmill(Vector3.new(88, 0, -74))
	watchtower(Vector3.new(20, 0, -104), { height = 22 })

	-- Southwest quarter
	familyHouse(at(-46, 30, 45), { roofGrass = true })
	cottage(at(-68, 22, 90))
	shed(at(-40, 58, 0))
	barn(at(-66, 66, 20))
	familyHouse(at(-24, 84, 0), { roofGrass = true, roofGrassType = "Meadow" })

	-- Animal pen
	do
		local c = Vector3.new(-52, 0, 88)
		fenceLine(c + Vector3.new(-12, 0, -10), c + Vector3.new(12, 0, -10))
		fenceLine(c + Vector3.new(12, 0, -10), c + Vector3.new(12, 0, 10))
		fenceLine(c + Vector3.new(12, 0, 10), c + Vector3.new(-12, 0, 10))
		fenceLine(c + Vector3.new(-12, 0, 10), c + Vector3.new(-12, 0, -10))
		make(propsF, "Trough", Vector3.new(6, 1.4, 2), CFrame.new(c + Vector3.new(0, GY + 0.7, 0)), PAL.WOOD, Enum.Material.WoodPlanks)
		hayBale(c + Vector3.new(-6, 0, -4))
	end

	-- Southeast quarter
	familyHouse(at(46, 30, 315))
	cottage(at(68, 24, 270), { roofGrass = true, roofGrassType = "Wild" })
	storehouse(at(40, 58, 0))
	shed(at(64, 64, 340))
	familyHouse(at(24, 84, 0))
	watchtower(Vector3.new(18, 0, 108), { height = 18 })

	-- Yard fences + fields for texture.
	fenceLine(Vector3.new(-58, 0, -8), Vector3.new(-58, 0, 12))
	fenceLine(Vector3.new(56, 0, 12), Vector3.new(56, 0, 40))
	farmPlot(Vector3.new(-90, 0, 44), 26, 34)
	scarecrow(Vector3.new(-90, 0, 44))
	farmPlot(Vector3.new(92, 0, 44), 24, 30)
	scarecrow(Vector3.new(92, 0, 44))

	-- Trees dotted through the village.
	local villageTrees = {
		Vector3.new(-30, 0, 40), Vector3.new(30, 0, 44), Vector3.new(-14, 0, -40),
		Vector3.new(14, 0, -46), Vector3.new(-84, 0, -8), Vector3.new(84, 0, -8),
		Vector3.new(-30, 0, 100), Vector3.new(34, 0, 100), Vector3.new(0, 0, 58),
		Vector3.new(-50, 0, -100), Vector3.new(52, 0, -92),
	}
	for _, tp in villageTrees do
		tree(tp, 0.9 + math.random() * 0.5)
	end

	-- OVERGROWN GRASS the player mows (ZoneKey = Village1). Mostly Meadow/Wild for a
	-- gentle start, with a few tougher patches nearer the castle road.
	local patches = {
		{ -30, 30, 16, 16, "Meadow" }, { 32, 34, 16, 12, "Meadow" }, { -12, 44, 12, 12, "Wild" },
		{ 14, 46, 12, 12, "Meadow" }, { -50, 8, 16, 16, "Wild" }, { 52, 10, 16, 16, "Meadow" },
		{ -78, 34, 16, 16, "Wild" }, { 78, 34, 16, 12, "Meadow" }, { -30, 70, 20, 16, "Wild" },
		{ 30, 72, 16, 16, "Meadow" }, { 0, 96, 20, 12, "Wild" }, { -60, 96, 16, 12, "Meadow" },
		{ 60, 92, 16, 12, "Wild" }, { -20, -50, 16, 16, "Meadow" }, { 24, -52, 16, 12, "Wild" },
		{ -80, -30, 16, 16, "Wild" }, { 80, -28, 16, 16, "Meadow" }, { -40, -96, 16, 12, "Moss" },
		{ 40, -96, 16, 12, "Moss" }, { 0, -70, 20, 16, "Thick" }, { -14, 22, 12, 12, "Meadow" },
		{ 16, 24, 12, 12, "Meadow" }, { -96, 62, 16, 16, "Wild" }, { 96, 62, 16, 16, "Wild" },
		{ -110, 10, 16, 16, "Meadow" }, { 110, 12, 16, 16, "Meadow" }, { -8, 112, 16, 12, "Wild" },
		{ 8, -114, 16, 12, "Thick" },
	}
	for _, gp in patches do
		grassPatch(gp[1], gp[2], gp[3], gp[4], gp[5])
	end

	-- Palisade + four gates (16-stud gate gaps).
	local g = 9
	fenceLine(Vector3.new(-P, 0, -P), Vector3.new(-g, 0, -P))
	fenceLine(Vector3.new(g, 0, -P), Vector3.new(P, 0, -P))
	fenceLine(Vector3.new(-P, 0, P), Vector3.new(-g, 0, P))
	fenceLine(Vector3.new(g, 0, P), Vector3.new(P, 0, P))
	fenceLine(Vector3.new(P, 0, -P), Vector3.new(P, 0, -g))
	fenceLine(Vector3.new(P, 0, g), Vector3.new(P, 0, P))
	fenceLine(Vector3.new(-P, 0, -P), Vector3.new(-P, 0, -g))
	fenceLine(Vector3.new(-P, 0, g), Vector3.new(-P, 0, P))

	gate(Vector3.new(0, 0, -P), "x", "To the Castle", "Locked")
	gate(Vector3.new(0, 0, P), "x", "Greenhollow", "Village 1")
	gate(Vector3.new(P, 0, 0), "z", "To Village 2", "Locked")
	gate(Vector3.new(-P, 0, 0), "z", "To Village 5", "Locked")

	-- Outer world detail: pond, hills, forest, rocks.
	water(Vector3.new(-175, 0, 150), 60, 44)
	make(propsF, "Dock", Vector3.new(4, 0.6, 16), CFrame.new(-150, GY + 0.6, 150), PAL.WOOD, Enum.Material.WoodPlanks)

	for _, hp in { Vector3.new(170, 0, -150), Vector3.new(-160, 0, -170), Vector3.new(180, 0, 120), Vector3.new(150, 0, 185) } do
		make(terrainF, "Hill", Vector3.new(90, 30, 90), CFrame.new(hp.X, GY - 8, hp.Z), PAL.GROUND, Enum.Material.Grass, Enum.PartType.Ball)
	end

	local placed = 0
	while placed < 150 do
		placed += 1
		local x = (math.random() - 0.5) * 420
		local z = (math.random() - 0.5) * 420
		if math.abs(x) <= P + 12 and math.abs(z) <= P + 12 then
			continue
		end
		if (math.abs(x) < 16 and math.abs(z) > P) or (math.abs(z) < 16 and math.abs(x) > P) then
			continue
		end
		local r = math.random()
		if r < 0.72 then
			tree(Vector3.new(x, 0, z), 0.8 + math.random() * 0.8)
		elseif r < 0.85 then
			rock(Vector3.new(x, 0, z), 0.8 + math.random() * 1.4)
		else
			bush(Vector3.new(x, 0, z), 0.9 + math.random() * 0.7)
		end
	end

	for _, fp in { Vector3.new(-18, 0, 30), Vector3.new(22, 0, 28), Vector3.new(-34, 0, -18), Vector3.new(36, 0, 12), Vector3.new(-6, 0, -30) } do
		flowers(fp)
	end
	bush(Vector3.new(-28, 0, 20))
	bush(Vector3.new(30, 0, -18))

	buildSpawn(Vector3.new(0, 0, 100))
end

function MapService.Init()
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
	grassF.Name = "GrassPatches"
	grassF.Parent = mapRoot

	buildVillage()
	print("[MapService] Village 1 (Greenhollow) built.")
end

return MapService