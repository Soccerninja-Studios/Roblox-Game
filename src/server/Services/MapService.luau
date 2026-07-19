--!strict
-- MapService: procedurally builds the Kingdom world from GameConfig.ZONES.
--
-- The whole map is data-driven: a central stone spawn plaza (which also holds the
-- spawn point and the shop) followed by a contiguous strip of grass "zones", laid
-- end-to-end in progression order. Each zone pad is tagged with the GrassSurface
-- tag and given a GrassType attribute, so GrassService grows the right grass on it
-- exactly like a hand-tagged part -- no special casing.
--
-- Adding, reordering, reskinning, or resizing zones is a one-line change in
-- GameConfig.ZONES / GameConfig.WORLD; there is nothing to edit in here.

local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

local MapService = {}

local mapRoot: Model

local function color3(rgb: { number }): Color3
	return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

local function newPart(name: string, size: Vector3, position: Vector3, color: Color3, material: Enum.Material): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.Position = position
	part.Color = color
	part.Material = material
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = mapRoot
	return part
end

-- A floating label on a short post, marking a zone entrance.
local function makeSign(title: string, subtitle: string, position: Vector3)
	local post = newPart(
		"SignPost",
		Vector3.new(0.6, 7, 0.6),
		position,
		color3(GameConfig.WORLD.SIGN_POST_COLOR),
		Enum.Material.Wood
	)

	local board = Instance.new("BillboardGui")
	board.Name = "ZoneSign"
	board.Size = UDim2.fromOffset(220, 86)
	board.StudsOffset = Vector3.new(0, 4.4, 0)
	board.MaxDistance = 240
	board.Adornee = post
	board.Parent = post

	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.fromRGB(28, 40, 26)
	bg.BackgroundTransparency = 0.15
	bg.BorderSizePixel = 0
	bg.Parent = board

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = bg

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Size = UDim2.new(1, -12, 0.55, 0)
	titleLabel.Position = UDim2.fromOffset(6, 4)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Font = Enum.Font.FredokaOne
	titleLabel.TextScaled = true
	titleLabel.TextColor3 = Color3.fromRGB(235, 245, 230)
	titleLabel.Text = title
	titleLabel.Parent = bg

	local subLabel = Instance.new("TextLabel")
	subLabel.Size = UDim2.new(1, -12, 0.4, 0)
	subLabel.Position = UDim2.new(0, 6, 0.56, 0)
	subLabel.BackgroundTransparency = 1
	subLabel.Font = Enum.Font.GothamMedium
	subLabel.TextScaled = true
	subLabel.TextColor3 = Color3.fromRGB(180, 214, 170)
	subLabel.Text = subtitle
	subLabel.Parent = bg
end

local function buildSpawn(topY: number)
	-- Clear any pre-existing spawns (e.g. the Baseplate's default) so players always
	-- start on the Kingdom plaza.
	for _, inst in Workspace:GetDescendants() do
		if inst:IsA("SpawnLocation") then
			inst:Destroy()
		end
	end

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "KingdomSpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(8, 1, 8)
	spawn.Position = Vector3.new(10, topY + 0.5, 10)
	spawn.Color = Color3.fromRGB(120, 180, 120)
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Parent = mapRoot
end

local function buildWorld()
	local world = GameConfig.WORLD
	local thickness = world.GROUND_THICKNESS
	local depth = world.STRIP_DEPTH
	local centerY = thickness / 2
	local topY = thickness -- bottom sits at y=0, so the walkable top is at y=thickness

	-- Spawn plaza (stone, no grass) centered on the origin.
	local plazaSize = world.PLAZA_SIZE
	newPart(
		"Plaza",
		Vector3.new(plazaSize, thickness, depth),
		Vector3.new(0, centerY, 0),
		color3(world.PLAZA_COLOR),
		Enum.Material.Slate
	)

	-- Lay each zone contiguously along +X, starting at the plaza's near edge.
	local cursorX = plazaSize / 2
	for _, zone in GameConfig.ZONES do
		local length = zone.length
		local zoneCenterX = cursorX + length / 2

		local pad = newPart(
			"Zone_" .. zone.key,
			Vector3.new(length, thickness, depth),
			Vector3.new(zoneCenterX, centerY, 0),
			color3(zone.groundColor),
			Enum.Material.Ground
		)
		pad:SetAttribute("GrassType", zone.grassType)
		pad:SetAttribute("ZoneKey", zone.key)
		CollectionService:AddTag(pad, GameConfig.GRASS_SURFACE_TAG)

		-- Entrance sign at the near-south corner of the zone.
		local def = GameConfig.GRASS_TYPES[zone.grassType]
		local grassName = (def and def.displayName) or zone.grassType
		local reward = (def and def.clipReward) or 0
		makeSign(
			zone.displayName,
			`{grassName} \u{2022} needs {zone.requiredTool} \u{2022} {reward}c`,
			Vector3.new(cursorX + 3, topY + 3.5, -depth / 2 + 3)
		)

		cursorX += length
	end

	-- Enclose the strip so players can't wander off the edges into the void.
	local startX = -plazaSize / 2
	local endX = cursorX
	local spanX = endX - startX
	local midX = (startX + endX) / 2
	local wallH = 4
	local wallY = thickness + wallH / 2
	local border = color3(world.BORDER_COLOR)
	newPart("Border_North", Vector3.new(spanX, wallH, 1), Vector3.new(midX, wallY, depth / 2), border, Enum.Material.Slate)
	newPart("Border_South", Vector3.new(spanX, wallH, 1), Vector3.new(midX, wallY, -depth / 2), border, Enum.Material.Slate)
	newPart("Border_Back", Vector3.new(1, wallH, depth), Vector3.new(startX, wallY, 0), border, Enum.Material.Slate)
	newPart("Border_End", Vector3.new(1, wallH, depth), Vector3.new(endX, wallY, 0), border, Enum.Material.Slate)

	buildSpawn(topY)
end

function MapService.Init()
	local existing = Workspace:FindFirstChild("Map")
	if existing then
		existing:Destroy()
	end

	mapRoot = Instance.new("Model")
	mapRoot.Name = "Map"
	mapRoot.Parent = Workspace

	buildWorld()
	print(`[MapService] Kingdom map built ({#GameConfig.ZONES} zones).`)
end

return MapService
