--!strict
-- WheelWorldService: constructs the full-size shared Golden Pet Wheel beside the
-- Shop/Gardener and mirrors successful server wheel results on its physical rotor.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local WheelWorldService = {}

local rotor: Model? = nil
local rotorBase = CFrame.identity
local angleDegrees = 0
local spinSerial = 0
local spinningUntil = 0

local COLORS = {
	Color3.fromRGB(236, 72, 92), Color3.fromRGB(255, 173, 54),
	Color3.fromRGB(78, 180, 121), Color3.fromRGB(75, 155, 221),
	Color3.fromRGB(143, 99, 202), Color3.fromRGB(246, 197, 63),
	Color3.fromRGB(232, 100, 154), Color3.fromRGB(94, 194, 189),
	Color3.fromRGB(102, 137, 211), Color3.fromRGB(180, 111, 201),
	Color3.fromRGB(241, 132, 63), Color3.fromRGB(255, 215, 76),
}

local function part(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material): Part
	local value = Instance.new("Part")
	value.Name = name
	value.Size = size
	value.CFrame = cframe
	value.Color = color
	value.Material = material
	value.Anchored = true
	value.CanCollide = true
	value.CanQuery = true
	value.CanTouch = false
	value.CastShadow = true
	value.TopSurface = Enum.SurfaceType.Smooth
	value.BottomSurface = Enum.SurfaceType.Smooth
	value.Parent = parent
	return value
end

local function grounded(position: Vector3): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {}
	params.IgnoreWater = false
	local hit = Workspace:Raycast(position + Vector3.new(0, 100, 0), Vector3.new(0, -300, 0), params)
	if hit then
		return Vector3.new(position.X, hit.Position.Y, position.Z)
	end
	return position
end

local function buildWheel()
	local previous = Workspace:FindFirstChild("GoldenPetWheel")
	if previous then
		previous:Destroy()
	end
	local world = Instance.new("Model")
	world.Name = "GoldenPetWheel"
	world:SetAttribute("InteractionRadius", GameConfig.PET_WHEEL_INTERACTION_RADIUS or 16)
	world.Parent = Workspace

	local ground = grounded(GameConfig.PET_WHEEL_POSITION)
	local diameter = GameConfig.PET_WHEEL_DIAMETER or 15
	local center = ground + Vector3.new(0, diameter * 0.56 + 2.2, 0)
	local shop = GameConfig.SHOP_POSITION
	local target = Vector3.new(shop.X, center.Y, shop.Z)
	if (target - center).Magnitude < 1 then
		target = center + Vector3.new(0, 0, -1)
	end
	local face = CFrame.lookAt(center, target)

	local platform = part(world, "InteractionPad", Vector3.new(1, diameter + 7, diameter + 7), CFrame.new(ground + Vector3.new(0, 0.45, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(253, 188, 47), Enum.Material.Neon)
	platform.Shape = Enum.PartType.Cylinder
	platform.Transparency = 0.58
	platform.CanCollide = false
	platform.CanTouch = true

	local base = part(world, "StoneBase", Vector3.new(diameter + 5, 1.5, 6), CFrame.new(ground + Vector3.new(0, 0.75, 0)), Color3.fromRGB(67, 72, 91), Enum.Material.Slate)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "OpenGoldenWheel"
	prompt.ActionText = "Open Wheel"
	prompt.ObjectText = "Golden Pet Wheel"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = GameConfig.PET_WHEEL_INTERACTION_RADIUS or 16
	prompt.RequiresLineOfSight = false
	prompt.Exclusivity = Enum.ProximityPromptExclusivity.OneGlobally
	prompt.Parent = base
	prompt.Triggered:Connect(function(player: Player)
		if player.Parent == Players then
			Remotes.Get("OpenPhysicalPetWheel"):FireClient(player)
		end
	end)

	for _, x in { -diameter * 0.52, diameter * 0.52 } do
		part(world, "WheelPost", Vector3.new(1.2, center.Y - ground.Y + 1.2, 1.2), face * CFrame.new(x, -(center.Y - ground.Y) * 0.46, 1.3), Color3.fromRGB(104, 72, 48), Enum.Material.Wood)
	end
	part(world, "TopBeam", Vector3.new(diameter + 3, 1.1, 1.1), face * CFrame.new(0, diameter * 0.58, 1.3), Color3.fromRGB(104, 72, 48), Enum.Material.Wood)

	local wheel = Instance.new("Model")
	wheel.Name = "Rotor"
	wheel.Parent = world
	local pivot = part(wheel, "Pivot", Vector3.new(0.2, 0.2, 0.2), face, Color3.new(), Enum.Material.SmoothPlastic)
	pivot.Transparency = 1
	pivot.CanCollide = false
	pivot.CanQuery = false
	wheel.PrimaryPart = pivot
	local disc = part(wheel, "WheelDisc", Vector3.new(1.1, diameter, diameter), face * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(34, 39, 68), Enum.Material.SmoothPlastic)
	disc.Shape = Enum.PartType.Cylinder
	disc.CanCollide = false
	local radius = diameter * 0.385
	for index = 1, 12 do
		local radians = math.rad((index - 1) * 30)
		local x = math.sin(radians) * radius
		local y = math.cos(radians) * radius
		local tile = part(wheel, "RewardSlot" .. tostring(index), Vector3.new(2.65, 3.45, 0.72), face * CFrame.new(x, y, -0.72) * CFrame.Angles(0, 0, -radians), COLORS[index], Enum.Material.Neon)
		tile.CanCollide = false
		tile:SetAttribute("WheelSlot", index)
	end
	local hub = part(wheel, "GoldenHub", Vector3.new(1.8, 2.65, 2.65), face * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(255, 213, 69), Enum.Material.Metal)
	hub.Shape = Enum.PartType.Cylinder
	hub.CanCollide = false

	local arrow = Instance.new("WedgePart")
	arrow.Name = "WinningArrow"
	arrow.Size = Vector3.new(1.5, 2.1, 1)
	arrow.CFrame = face * CFrame.new(0, diameter * 0.58, -1.4) * CFrame.Angles(0, math.rad(90), math.rad(180))
	arrow.Color = Color3.fromRGB(244, 73, 83)
	arrow.Material = Enum.Material.Neon
	arrow.Anchored = true
	arrow.CanCollide = false
	arrow.Parent = world

	local sign = Instance.new("BillboardGui")
	sign.Name = "WheelSign"
	sign.Adornee = base
	sign.AlwaysOnTop = false
	sign.MaxDistance = 100
	sign.Size = UDim2.fromOffset(330, 65)
	sign.StudsOffsetWorldSpace = Vector3.new(0, center.Y - ground.Y + diameter * 0.63, 0)
	sign.Parent = base
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(28, 34, 63)
	label.BackgroundTransparency = 0.1
	label.Font = Enum.Font.FredokaOne
	label.Text = "GOLDEN PET WHEEL"
	label.TextColor3 = Color3.fromRGB(255, 224, 98)
	label.TextScaled = true
	label.TextStrokeTransparency = 0.45
	label.Parent = sign
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = label

	rotor = wheel
	rotorBase = face
	angleDegrees = 0
	print("[WheelWorldService] Physical Golden Pet Wheel built beside the hub services.")
end

function WheelWorldService.SpinForResult(slotIndex: number)
	local wheel = rotor
	if not wheel or not wheel.Parent or os.clock() < spinningUntil then
		return
	end
	spinningUntil = os.clock() + (GameConfig.PET_REWARDS.wheelLockSeconds or 2.6)
	spinSerial += 1
	local serial = spinSerial
	local startAngle = angleDegrees
	local desired = ((slotIndex - 1) % 12) * 30
	local delta = 4 * 360 + ((desired - (startAngle % 360)) % 360)
	local targetAngle = startAngle + delta
	local started = os.clock()
	local duration = 2.4
	task.spawn(function()
		while serial == spinSerial and wheel.Parent do
			local t = math.clamp((os.clock() - started) / duration, 0, 1)
			local eased = 1 - ((1 - t) ^ 4)
			local current = startAngle + delta * eased
			wheel:PivotTo(rotorBase * CFrame.Angles(0, 0, math.rad(-current)))
			if t >= 1 then
				angleDegrees = targetAngle
				break
			end
			RunService.Heartbeat:Wait()
		end
	end)
end

function WheelWorldService.Init(_services: any)
end

function WheelWorldService.Start()
	task.delay(2, buildWheel)
end

return WheelWorldService
