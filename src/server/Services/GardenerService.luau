--!strict
-- GardenerService: the deposit stall. Players fill their carry bag by mowing, then
-- walk onto the Gardener's glowing pad to BANK everything -- clippings convert to
-- gold (and, rarely, diamonds) and the bag empties. Like the Shop it's a little
-- market stall, but garden/nature themed: a striped green-and-cream awning on
-- wooden posts, flower planters, potted bushes, and a produce barrel to tip your
-- clippings into. A pulsing LIGHT-GREEN disc named "GardenerZone" (radius == the
-- interaction radius) is what the client watches to trigger a deposit. All deposit
-- math lives in PlayerDataService.Deposit; this service builds the stall and
-- validates the request (the player must actually be on the pad).

local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local GardenerService = {}

local PlayerDataService: any

local WOOD = Color3.fromRGB(120, 84, 52)
local WOOD_DARK = Color3.fromRGB(92, 62, 38)
local LEAF = Color3.fromRGB(78, 168, 78)
local LEAF_DARK = Color3.fromRGB(54, 130, 60)
local CREAM = Color3.fromRGB(245, 240, 214)
local SOIL = Color3.fromRGB(74, 54, 38)

-- The Gardener's walk-in circle is LIGHT GREEN.
local ZONE_FILL = Color3.fromRGB(150, 235, 130)
local ZONE_EDGE = Color3.fromRGB(96, 200, 110)

local FLOWER_COLORS = {
	Color3.fromRGB(240, 130, 170),
	Color3.fromRGB(250, 214, 90),
	Color3.fromRGB(224, 96, 96),
	Color3.fromRGB(170, 120, 210),
	Color3.fromRGB(245, 160, 90),
}

local function part(props: { [string]: any }, parent: Instance): BasePart
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	for k, v in props do
		(p :: any)[k] = v
	end
	p.Parent = parent
	return p
end

-- One flower: a thin green stem topped with a colored bloom.
local function plantFlower(pos: Vector3, color: Color3, parent: Instance)
	part({
		Name = "Stem",
		Size = Vector3.new(0.18, 1.1, 0.18),
		CFrame = CFrame.new(pos + Vector3.new(0, 0.55, 0)),
		Color = LEAF_DARK,
		Material = Enum.Material.Grass,
	}, parent)
	part({
		Name = "Bloom",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(0.7, 0.7, 0.7),
		CFrame = CFrame.new(pos + Vector3.new(0, 1.2, 0)),
		Color = color,
		Material = Enum.Material.SmoothPlastic,
	}, parent)
end

-- A wooden planter box full of soil with a few flowers poking out.
local function buildPlanter(center: Vector3, parent: Instance)
	part({
		Name = "Planter",
		Size = Vector3.new(4, 1.4, 1.6),
		CFrame = CFrame.new(center),
		Color = WOOD,
		Material = Enum.Material.WoodPlanks,
		CanCollide = true,
	}, parent)
	part({
		Name = "Soil",
		Size = Vector3.new(3.6, 0.4, 1.2),
		CFrame = CFrame.new(center + Vector3.new(0, 0.7, 0)),
		Color = SOIL,
		Material = Enum.Material.Ground,
	}, parent)
	local top = center + Vector3.new(0, 0.9, 0)
	for i = -1, 1 do
		local color = FLOWER_COLORS[((i + 1) % #FLOWER_COLORS) + 1]
		plantFlower(top + Vector3.new(i * 1.2, 0, 0), color, parent)
	end
end

local function buildStand(): BasePart?
	local existing = Workspace:FindFirstChild("Gardener")
	if existing then
		existing:Destroy()
	end

	local base = GameConfig.GARDENER_POSITION
	local model = Instance.new("Model")
	model.Name = "Gardener"

	-- Standable wooden deck.
	local deck = part({
		Name = "Deck",
		Size = Vector3.new(12, 1, 12),
		CFrame = CFrame.new(base + Vector3.new(0, 0.5, 0)),
		Color = WOOD,
		Material = Enum.Material.WoodPlanks,
		CanCollide = true,
	}, model)

	-- Four corner posts holding up the awning.
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			part({
				Name = "Post",
				Size = Vector3.new(0.6, 7, 0.6),
				CFrame = CFrame.new(base + Vector3.new(sx * 5, 4, sz * 5)),
				Color = WOOD_DARK,
				Material = Enum.Material.Wood,
				CanCollide = true,
			}, model)
		end
	end

	-- Striped awning roof (alternating leaf-green and cream), gently pitched.
	local stripeCount = 8
	local stripeW = 1.6
	local roofY = 7.7
	local totalW = stripeCount * stripeW
	for i = 0, stripeCount - 1 do
		local x = -totalW / 2 + stripeW / 2 + i * stripeW
		part({
			Name = "Awning",
			Size = Vector3.new(stripeW, 0.4, 13),
			CFrame = CFrame.new(base + Vector3.new(x, roofY, 0)) * CFrame.Angles(math.rad(-6), 0, 0),
			Color = (i % 2 == 0) and LEAF or CREAM,
			Material = Enum.Material.SmoothPlastic,
		}, model)
	end
	-- Ridge beam capping the stripes.
	part({
		Name = "Ridge",
		Size = Vector3.new(totalW + 0.6, 0.5, 0.8),
		CFrame = CFrame.new(base + Vector3.new(0, roofY + 0.5, 0)),
		Color = WOOD_DARK,
		Material = Enum.Material.Wood,
	}, model)

	-- Front counter to hand produce across.
	part({
		Name = "Counter",
		Size = Vector3.new(10, 2, 1.4),
		CFrame = CFrame.new(base + Vector3.new(0, 2, 5)),
		Color = WOOD,
		Material = Enum.Material.WoodPlanks,
		CanCollide = true,
	}, model)

	-- Deposit barrel (Cylinder faces are on local X, so rotate upright).
	part({
		Name = "Barrel",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(3.0, 3.2, 3.2),
		CFrame = CFrame.new(base + Vector3.new(3.4, 2.6, -3.2)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = WOOD_DARK,
		Material = Enum.Material.WoodPlanks,
		CanCollide = true,
	}, model)
	-- A heap of fresh clippings piled on top of the barrel.
	part({
		Name = "ClippingHeap",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(3.0, 1.6, 3.0),
		CFrame = CFrame.new(base + Vector3.new(3.4, 4.2, -3.2)),
		Color = Color3.fromRGB(120, 200, 92),
		Material = Enum.Material.Grass,
	}, model)

	-- Flower planters flanking the front of the stall.
	buildPlanter(base + Vector3.new(-4.2, 1.7, 4.4), model)
	buildPlanter(base + Vector3.new(4.2, 1.7, 4.4), model)

	-- Potted bushes on the back deck corners.
	for _, sx in { -1, 1 } do
		part({
			Name = "Pot",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(1.4, 1.5, 1.5),
			CFrame = CFrame.new(base + Vector3.new(sx * 4.4, 1.7, -4.2)) * CFrame.Angles(0, 0, math.rad(90)),
			Color = Color3.fromRGB(196, 108, 74),
			Material = Enum.Material.Slate,
		}, model)
		part({
			Name = "Bush",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(2.4, 2.2, 2.4),
			CFrame = CFrame.new(base + Vector3.new(sx * 4.4, 3.1, -4.2)),
			Color = LEAF,
			Material = Enum.Material.Grass,
		}, model)
	end

	-- Sign post + board out front (board turned to face the plaza).
	part({
		Name = "SignPost",
		Size = Vector3.new(0.5, 6, 0.5),
		CFrame = CFrame.new(base + Vector3.new(-5.4, 3, 6.4)),
		Color = WOOD_DARK,
		Material = Enum.Material.Wood,
		CanCollide = true,
	}, model)
	local board = part({
		Name = "Board",
		Size = Vector3.new(6, 2.2, 0.4),
		CFrame = CFrame.new(base + Vector3.new(-3.8, 6, 6.4)) * CFrame.Angles(0, math.rad(180), 0),
		Color = LEAF_DARK,
		Material = Enum.Material.WoodPlanks,
	}, model)

	local sign = Instance.new("SurfaceGui")
	sign.Face = Enum.NormalId.Front
	sign.CanvasSize = Vector2.new(300, 110)
	sign.Parent = board
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.FredokaOne
	text.Text = "\u{1FA99} DEPOSIT"
	text.TextColor3 = Color3.fromRGB(255, 248, 224)
	text.TextScaled = true
	text.Parent = sign

	-- Glowing walk-in pad; its radius matches the interaction radius exactly.
	local radius = GameConfig.GARDENER_ZONE_RADIUS
	local center = Vector3.new(base.X, base.Y + 0.15, base.Z)
	local flat = CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90))
	local zone = part({
		Name = "GardenerZone",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.4, radius * 2, radius * 2),
		CFrame = flat,
		Material = Enum.Material.Neon,
		Color = ZONE_FILL,
		Transparency = 0.5,
		CastShadow = false,
	}, model)
	part({
		Name = "GardenerZoneRing",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.3, radius * 2 + 1.4, radius * 2 + 1.4),
		CFrame = flat * CFrame.new(-0.05, 0, 0),
		Material = Enum.Material.Neon,
		Color = ZONE_EDGE,
		Transparency = 0.2,
		CastShadow = false,
	}, model)

	model.PrimaryPart = deck
	model.Parent = Workspace

	-- Gentle pulse so the pad reads as interactive.
	task.spawn(function()
		while zone.Parent do
			TweenService:Create(zone, TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { Transparency = 0.72 }):Play()
			task.wait(1.1)
			TweenService:Create(zone, TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { Transparency = 0.42 }):Play()
			task.wait(1.1)
		end
	end)

	return zone
end

local function onRequestDeposit(player: Player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	-- Server-side proximity check so a deposit can't be spoofed from anywhere.
	local base = GameConfig.GARDENER_POSITION
	local delta = root.Position - base
	local horizontal = math.sqrt(delta.X * delta.X + delta.Z * delta.Z)
	if horizontal > GameConfig.GARDENER_ZONE_RADIUS + 6 then
		return
	end

	local summary = PlayerDataService.Deposit(player)
	if summary and summary.clippings > 0 then
		Remotes.Get("Deposited"):FireClient(player, summary)
	end
end

function GardenerService.Init(services: any)
	PlayerDataService = services.PlayerDataService
	Remotes.Get("RequestDeposit").OnServerEvent:Connect(onRequestDeposit)
end

function GardenerService.Start()
	buildStand()
	print("[GardenerService] Deposit stall ready.")
end

return GardenerService
