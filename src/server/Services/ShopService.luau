--!strict
-- ShopService: spawns the hand-authored market stall (synced in via Rojo at
-- ReplicatedStorage.Assets.Shop), drops it exactly where the designer asked, tints
-- its walk-in ShopZone disc YELLOW, and gives the shopkeeper NPC a looping idle so
-- the stall feels alive. The model already ships with a "SHOP" sign, a ShopZone +
-- ShopZoneRing pad, and an R6 shopkeeper, so this service is mostly placement +
-- polish. The client watches the ShopZone position to auto-open the shop menu.

local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

local ShopService = {}

-- The shop's walk-in circle is YELLOW.
local ZONE_FILL = Color3.fromRGB(255, 224, 92)
local ZONE_EDGE = Color3.fromRGB(240, 190, 55)

-- Looping catalog idles, picked to match the NPC's rig.
local IDLE_R6 = "rbxassetid://180435571"
local IDLE_R15 = "rbxassetid://507766388"

local function getTemplate(): Model?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local template = assets and assets:FindFirstChild("Shop")
	if template and template:IsA("Model") then
		return template :: Model
	end
	return nil
end

-- Plant the NPC behind the counter and loop a gentle idle animation.
local function animateNPC(model: Model)
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
	anim.AnimationId = if humanoid.RigType == Enum.HumanoidRigType.R15 then IDLE_R15 else IDLE_R6

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

-- Slow transparency pulse so the walk-in pad reads as interactive.
local function pulse(zone: BasePart)
	task.spawn(function()
		while zone.Parent do
			TweenService:Create(zone, TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { Transparency = 0.72 }):Play()
			task.wait(1.1)
			TweenService:Create(zone, TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { Transparency = 0.42 }):Play()
			task.wait(1.1)
		end
	end)
end

-- Recolor the authored ShopZone / ShopZoneRing into a glowing yellow disc. We keep
-- the builder's geometry + position and only restyle it, so the disc lines up with
-- however the stall was authored.
local function styleZone(model: Model)
	local zone = model:FindFirstChild("ShopZone", true)
	if zone and zone:IsA("BasePart") then
		zone.Anchored = true
		zone.CanCollide = false
		zone.CanQuery = false
		zone.CanTouch = false
		zone.CastShadow = false
		zone.Material = Enum.Material.Neon
		zone.Color = ZONE_FILL
		zone.Transparency = 0.5
		pulse(zone)
	else
		warn("[ShopService] Shop model has no ShopZone part; walk-in area won't glow.")
	end

	local ring = model:FindFirstChild("ShopZoneRing", true)
	if ring and ring:IsA("BasePart") then
		ring.Anchored = true
		ring.CanCollide = false
		ring.CanQuery = false
		ring.CanTouch = false
		ring.CastShadow = false
		ring.Material = Enum.Material.Neon
		ring.Color = ZONE_EDGE
		ring.Transparency = 0.2
	end
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

	-- Place exactly at the designer-specified pivot with zero orientation.
	model:PivotTo(CFrame.new(GameConfig.SHOP_POSITION))
	model.Parent = Workspace

	animateNPC(model)
	styleZone(model)
end

function ShopService.Init() end

function ShopService.Start()
	spawnShop()
	print("[ShopService] Shop ready.")
end

return ShopService
