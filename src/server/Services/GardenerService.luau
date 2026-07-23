--!strict
-- GardenerService: the deposit stand. Players fill their carry bag by mowing, then
-- walk onto the Gardener's glowing pad to BANK everything -- clippings convert to
-- gold (and, rarely, diamonds) and the bag empties. The stand is built entirely in
-- code (no asset dependency): a wooden platform, a produce barrel, a sign, and a
-- pulsing amber zone disc named "GardenerZone" that the client watches to trigger a
-- deposit. All deposit math lives in PlayerDataService.Deposit; this service builds
-- the stand and validates the request (the player must actually be on the pad).

local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local GardenerService = {}

local PlayerDataService: any

local WOOD = Color3.fromRGB(120, 84, 52)
local WOOD_DARK = Color3.fromRGB(92, 62, 38)
local ZONE_FILL = Color3.fromRGB(240, 196, 90)
local ZONE_EDGE = Color3.fromRGB(214, 158, 54)

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

local function buildStand(): BasePart?
	local existing = Workspace:FindFirstChild("Gardener")
	if existing then
		existing:Destroy()
	end

	local base = GameConfig.GARDENER_POSITION
	local model = Instance.new("Model")
	model.Name = "Gardener"

	-- Wooden platform the player steps onto.
	local deck = part({
		Name = "Deck",
		Size = Vector3.new(10, 1, 10),
		CFrame = CFrame.new(base + Vector3.new(0, 0.5, 0)),
		Color = WOOD,
		Material = Enum.Material.WoodPlanks,
		CanCollide = true,
	}, model)

	-- A produce barrel to deposit into (Cylinder faces are on local X, so rotate it
	-- 90 degrees about Z to stand it upright).
	part({
		Name = "Barrel",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(3.2, 3.4, 3.4),
		CFrame = CFrame.new(base + Vector3.new(0, 2.7, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = WOOD_DARK,
		Material = Enum.Material.WoodPlanks,
		CanCollide = true,
	}, model)

	-- Sign post + board.
	part({
		Name = "Post",
		Size = Vector3.new(0.5, 6, 0.5),
		CFrame = CFrame.new(base + Vector3.new(-4, 3, -4)),
		Color = WOOD_DARK,
		Material = Enum.Material.Wood,
		CanCollide = true,
	}, model)
	local board = part({
		Name = "Board",
		Size = Vector3.new(6, 2.2, 0.4),
		CFrame = CFrame.new(base + Vector3.new(-2.6, 6, -4)),
		Color = WOOD,
		Material = Enum.Material.WoodPlanks,
		CanCollide = true,
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
	print("[GardenerService] Deposit stand ready.")
end

return GardenerService
