--!strict
-- ShopService: spawns the hand-authored market stall model (built in Studio and
-- synced in via Rojo at ReplicatedStorage.Assets.Shop), then turns its ShopZone
-- part into a visible, glowing circular area so the player can see exactly where
-- to stand to open the shop. The client watches ShopZone.Position to auto-open,
-- so the visible disc and the interaction radius line up exactly. We also rename
-- the baked-in sign to "SHOP" and give the shopkeeper NPC a looping idle anim.

local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

local ShopService = {}

-- The shop's walk-in circle is YELLOW.
local ZONE_FILL = Color3.fromRGB(255, 224, 92)
local ZONE_EDGE = Color3.fromRGB(240, 190, 55)

-- Classic looping R6 idle from the catalog (the shopkeeper is an R6 rig).
local IDLE_ANIMATION_ID = "rbxassetid://180435571"

local function getTemplate(): Model?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local template = assets and assets:FindFirstChild("Shop")
	if template and template:IsA("Model") then
		return template
	end
	return nil
end

-- Rename the baked-in sign from "MARKET" to "SHOP" (kept the cart emoji).
local function setSignText(model: Model)
	local gui = model:FindFirstChild("SignGui", true)
	if not gui then
		return
	end
	local label = gui:FindFirstChildWhichIsA("TextLabel", true)
	if label then
		(label :: TextLabel).Text = "\u{1F6D2} SHOP"
	end
end

-- Give the shopkeeper NPC a gentle looping idle so the stall feels alive.
local function animateShopkeeper(model: Model)
	local humanoid: Humanoid? = nil
	for _, d in model:GetDescendants() do
		if d:IsA("Humanoid") then
			humanoid = d
			break
		end
	end
	if not humanoid then
		warn("[ShopService] No shopkeeper Humanoid found; skipping idle animation.")
		return
	end

	-- Keep them planted behind the counter.
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	pcall(function()
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
	end)

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	local anim = Instance.new("Animation")
	anim.AnimationId = IDLE_ANIMATION_ID

	local ok, track = pcall(function()
		return (animator :: Animator):LoadAnimation(anim)
	end)
	if ok and track then
		local t = track :: AnimationTrack
		t.Looped = true
		t.Priority = Enum.AnimationPriority.Idle
		t:Play()
	else
		warn("[ShopService] Could not load the shopkeeper idle animation.")
	end
end

-- Turn ShopZone into a flat, translucent, pulsing disc whose radius matches the
-- interaction radius exactly.
local function styleZone(zone: BasePart)
	local radius = GameConfig.SHOP_ZONE_RADIUS
	local groundY = GameConfig.SHOP_POSITION.Y + 0.15
	local center = Vector3.new(zone.Position.X, groundY, zone.Position.Z)

	-- Drop any joints so re-anchoring + moving the trigger can't drag the stall.
	for _, d in zone:GetChildren() do
		if d:IsA("JointInstance") or d:IsA("WeldConstraint") then
			d:Destroy()
		end
	end

	-- A Cylinder part's flat circular faces are on its local X ends, so rotate it
	-- 90 degrees about Z to lay the disc flat with its axis pointing straight up.
	local flat = CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90))

	zone.Shape = Enum.PartType.Cylinder
	zone.Size = Vector3.new(0.4, radius * 2, radius * 2)
	zone.CFrame = flat
	zone.Anchored = true
	zone.CanCollide = false
	zone.CanQuery = false
	zone.CanTouch = false
	zone.Material = Enum.Material.Neon
	zone.Color = ZONE_FILL
	zone.Transparency = 0.5
	zone.CastShadow = false

	-- A brighter ring just outside the fill for a crisp edge.
	local ring = Instance.new("Part")
	ring.Name = "ShopZoneRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.3, radius * 2 + 1.4, radius * 2 + 1.4)
	ring.CFrame = flat * CFrame.new(-0.05, 0, 0)
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.Material = Enum.Material.Neon
	ring.Color = ZONE_EDGE
	ring.Transparency = 0.2
	ring.CastShadow = false
	ring.Parent = zone

	-- Gentle pulse so the area reads as interactive.
	task.spawn(function()
		while zone.Parent do
			TweenService:Create(zone, TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { Transparency = 0.72 }):Play()
			task.wait(1.1)
			TweenService:Create(zone, TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { Transparency = 0.42 }):Play()
			task.wait(1.1)
		end
	end)
end

local function spawnShop()
	local template = getTemplate()
	if not template then
		warn("[ShopService] No ReplicatedStorage.Assets.Shop model found; skipping shop spawn.")
		return
	end

	local existing = Workspace:FindFirstChild("Shop")
	if existing then
		existing:Destroy()
	end

	local model = template:Clone()
	model.Name = "Shop"

	-- Rest the stall on the ground, centered on SHOP_POSITION (pure translation, so
	-- the builder's authored rotation is preserved).
	local cf, size = model:GetBoundingBox()
	local desiredCenter = Vector3.new(
		GameConfig.SHOP_POSITION.X,
		GameConfig.SHOP_POSITION.Y + size.Y / 2,
		GameConfig.SHOP_POSITION.Z
	)
	model:PivotTo(model:GetPivot() + (desiredCenter - cf.Position))
	model.Parent = Workspace

	setSignText(model)
	animateShopkeeper(model)

	local zone = model:FindFirstChild("ShopZone", true)
	if zone and zone:IsA("BasePart") then
		styleZone(zone)
	else
		warn("[ShopService] Shop model has no ShopZone part; the walk-in area won't be visible.")
	end
end

function ShopService.Init() end

function ShopService.Start()
	spawnShop()
	print("[ShopService] Shop ready.")
end

return ShopService
