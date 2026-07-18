--!strict
-- ShopService: builds a detailed medieval market stall the player can walk into,
-- plus an invisible zone the client watches to auto-open the shop menu.

local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

local ShopService = {}

local WOOD = Color3.fromRGB(104, 68, 41)
local WOOD_DARK = Color3.fromRGB(78, 50, 30)
local CANVAS_A = Color3.fromRGB(196, 64, 58)
local CANVAS_B = Color3.fromRGB(238, 231, 214)
local GOLD = Color3.fromRGB(226, 176, 62)

type PartArgs = {
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material?,
	shape: Enum.PartType?,
	transparency: number?,
	reflectance: number?,
	parent: Instance,
}

local function block(a: PartArgs): BasePart
	local p = Instance.new("Part")
	p.Name = a.name
	p.Anchored = true
	p.CanCollide = true
	p.Size = a.size
	p.CFrame = a.cframe
	p.Color = a.color
	p.Material = a.material or Enum.Material.SmoothPlastic
	p.Transparency = a.transparency or 0
	p.Reflectance = a.reflectance or 0
	if a.shape then
		p.Shape = a.shape
	end
	p.Parent = a.parent
	return p
end

local function buildShopkeeper(model: Model, base: CFrame)
	local skin = Color3.fromRGB(226, 190, 150)
	local apron = Color3.fromRGB(66, 122, 74)
	block({ name = "NPC_Torso", size = Vector3.new(2, 2, 1), cframe = base * CFrame.new(0, 3, 0), color = apron, material = Enum.Material.Fabric, parent = model })
	block({ name = "NPC_Head", size = Vector3.new(1.2, 1.2, 1.2), cframe = base * CFrame.new(0, 4.7, 0), color = skin, material = Enum.Material.SmoothPlastic, parent = model })
	block({ name = "NPC_Hat", size = Vector3.new(1.8, 0.3, 1.8), cframe = base * CFrame.new(0, 5.35, 0), color = GOLD, material = Enum.Material.Fabric, parent = model })
	block({ name = "NPC_HatTop", size = Vector3.new(1.1, 0.7, 1.1), cframe = base * CFrame.new(0, 5.65, 0), color = GOLD, material = Enum.Material.Fabric, parent = model })
	for _, side in { -1, 1 } do
		block({ name = "NPC_Arm", size = Vector3.new(0.7, 2, 0.7), cframe = base * CFrame.new(side * 1.35, 3, 0), color = skin, material = Enum.Material.SmoothPlastic, parent = model })
	end
end

local function buildStall(): Model
	local model = Instance.new("Model")
	model.Name = "Shop"

	local origin = CFrame.new(GameConfig.SHOP_POSITION)

	-- Floor platform + trim
	local floor = block({ name = "Floor", size = Vector3.new(16, 1, 12), cframe = origin * CFrame.new(0, 0.5, 0), color = Color3.fromRGB(120, 88, 58), material = Enum.Material.WoodPlanks, parent = model })
	block({ name = "Rug", size = Vector3.new(10, 0.15, 8), cframe = origin * CFrame.new(0, 1.05, 1), color = Color3.fromRGB(150, 52, 52), material = Enum.Material.Fabric, parent = model })

	-- Four posts
	for _, x in { -7, 7 } do
		for _, z in { -5, 5 } do
			block({ name = "Post", size = Vector3.new(0.7, 10, 0.7), cframe = origin * CFrame.new(x, 6, z), color = WOOD_DARK, material = Enum.Material.Wood, parent = model })
		end
	end

	-- Top beams
	block({ name = "BeamFront", size = Vector3.new(15.5, 0.7, 0.7), cframe = origin * CFrame.new(0, 11, -5), color = WOOD, material = Enum.Material.Wood, parent = model })
	block({ name = "BeamBack", size = Vector3.new(15.5, 0.7, 0.7), cframe = origin * CFrame.new(0, 11, 5), color = WOOD, material = Enum.Material.Wood, parent = model })

	-- Striped awning (angled), alternating canvas colors
	local stripes = 8
	local awning = Instance.new("Model")
	awning.Name = "Awning"
	awning.Parent = model
	for i = 0, stripes - 1 do
		local x = -7 + (i + 0.5) * (14 / stripes)
		block({
			name = "Stripe",
			size = Vector3.new(14 / stripes, 0.3, 8.5),
			cframe = origin * CFrame.new(x, 11.9, 0.2) * CFrame.Angles(math.rad(-22), 0, 0),
			color = (i % 2 == 0) and CANVAS_A or CANVAS_B,
			material = Enum.Material.Fabric,
			parent = awning,
		})
	end
	-- Scalloped front trim of the awning
	for i = 0, stripes - 1 do
		local x = -7 + (i + 0.5) * (14 / stripes)
		block({
			name = "Scallop",
			size = Vector3.new(14 / stripes - 0.1, 0.8, 0.3),
			cframe = origin * CFrame.new(x, 10.4, -4.1),
			color = (i % 2 == 0) and CANVAS_A or CANVAS_B,
			material = Enum.Material.Fabric,
			parent = awning,
		})
	end

	-- Back wall + shelves
	block({ name = "BackWall", size = Vector3.new(15.5, 9, 0.4), cframe = origin * CFrame.new(0, 6, 5.3), color = WOOD, material = Enum.Material.WoodPlanks, parent = model })
	for _, y in { 5, 8 } do
		block({ name = "Shelf", size = Vector3.new(13, 0.4, 1.2), cframe = origin * CFrame.new(0, y, 4.7), color = WOOD_DARK, material = Enum.Material.Wood, parent = model })
	end
	-- little colored "wares" on the shelves
	for i = 0, 5 do
		local x = -6 + i * 2.4
		block({ name = "Ware", size = Vector3.new(0.9, 1.1, 0.9), cframe = origin * CFrame.new(x, 5.75, 4.7), color = Color3.fromHSV((i / 6), 0.6, 0.9), material = Enum.Material.SmoothPlastic, parent = model })
		block({ name = "Ware", size = Vector3.new(0.8, 0.9, 0.8), cframe = origin * CFrame.new(x, 8.75, 4.7), color = Color3.fromHSV(((i + 3) / 6) % 1, 0.6, 0.9), material = Enum.Material.SmoothPlastic, parent = model })
	end

	-- Counter
	block({ name = "Counter", size = Vector3.new(13, 3, 1.6), cframe = origin * CFrame.new(0, 2.5, -3.4), color = WOOD, material = Enum.Material.WoodPlanks, parent = model })
	block({ name = "CounterTop", size = Vector3.new(13.4, 0.4, 2.2), cframe = origin * CFrame.new(0, 4.1, -3.4), color = WOOD_DARK, material = Enum.Material.Wood, parent = model })

	-- Lanterns with light
	for _, x in { -6.6, 6.6 } do
		local lantern = block({ name = "Lantern", size = Vector3.new(0.8, 1.2, 0.8), cframe = origin * CFrame.new(x, 9.6, -5), color = GOLD, material = Enum.Material.Neon, parent = model })
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 214, 140)
		light.Brightness = 2
		light.Range = 14
		light.Parent = lantern
	end

	-- Banner flags on the front posts
	for _, x in { -7, 7 } do
		block({ name = "Banner", size = Vector3.new(0.15, 3, 1.6), cframe = origin * CFrame.new(x, 8, -5.3), color = CANVAS_A, material = Enum.Material.Fabric, parent = model })
	end

	-- Decorations: barrels + crates + a potted plant
	block({ name = "Barrel", size = Vector3.new(1.8, 2.4, 1.8), cframe = origin * CFrame.new(-6, 2.2, -2) * CFrame.Angles(0, 0, math.rad(90)), color = WOOD_DARK, material = Enum.Material.Wood, shape = Enum.PartType.Cylinder, parent = model })
	block({ name = "Crate", size = Vector3.new(2, 2, 2), cframe = origin * CFrame.new(6, 2, -1.5), color = Color3.fromRGB(150, 110, 66), material = Enum.Material.WoodPlanks, parent = model })
	block({ name = "Crate", size = Vector3.new(1.5, 1.5, 1.5), cframe = origin * CFrame.new(6.5, 3.6, -1.8) * CFrame.Angles(0, math.rad(20), 0), color = Color3.fromRGB(150, 110, 66), material = Enum.Material.WoodPlanks, parent = model })
	block({ name = "Pot", size = Vector3.new(1.4, 1.2, 1.4), cframe = origin * CFrame.new(-6, 1.6, 2.5), color = Color3.fromRGB(150, 90, 60), material = Enum.Material.Slate, parent = model })
	block({ name = "Bush", size = Vector3.new(2, 2, 2), cframe = origin * CFrame.new(-6, 2.9, 2.5), color = Color3.fromRGB(86, 158, 66), material = Enum.Material.Grass, shape = Enum.PartType.Ball, parent = model })

	-- Shopkeeper NPC behind the counter
	buildShopkeeper(model, origin * CFrame.new(0, 1, 3))

	-- Glowing overhead sign with a BillboardGui
	local sign = block({ name = "Sign", size = Vector3.new(7, 1.8, 0.3), cframe = origin * CFrame.new(0, 13.2, -4.6), color = WOOD_DARK, material = Enum.Material.Wood, parent = model })
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "SignGui"
	billboard.Size = UDim2.fromScale(9, 2.4)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 0, -0.3)
	billboard.AlwaysOnTop = false
	billboard.MaxDistance = 300
	billboard.Parent = sign
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = "\u{1F6D2} MARKET"
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 244, 214)
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new(Color3.fromRGB(255, 236, 170), Color3.fromRGB(240, 170, 60))
	grad.Rotation = 90
	grad.Parent = label
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = Color3.fromRGB(70, 40, 20)
	stroke.Parent = label
	label.Parent = billboard

	-- Invisible walk-in zone (client watches this to open the menu)
	local zone = block({
		name = "ShopZone",
		size = Vector3.new(GameConfig.SHOP_ZONE_RADIUS * 2, 14, GameConfig.SHOP_ZONE_RADIUS * 2),
		cframe = origin * CFrame.new(0, 7, 0),
		color = Color3.fromRGB(120, 200, 255),
		transparency = 1,
		parent = model,
	})
	zone.CanCollide = false
	zone.CanQuery = false
	model.PrimaryPart = zone

	return model, sign
end

function ShopService.Start()
	local existing = Workspace:FindFirstChild("Shop")
	if existing then
		existing:Destroy()
	end

	local model, sign = buildStall()
	model.Parent = Workspace

	-- Gentle bobbing sign for a bit of life.
	local baseCF = sign.CFrame
	task.spawn(function()
		while sign.Parent do
			TweenService:Create(sign, TweenInfo.new(2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { CFrame = baseCF * CFrame.new(0, 0.35, 0) }):Play()
			task.wait(2)
			TweenService:Create(sign, TweenInfo.new(2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { CFrame = baseCF }):Play()
			task.wait(2)
		end
	end)

	print("[ShopService] Shop built.")
end

return ShopService
