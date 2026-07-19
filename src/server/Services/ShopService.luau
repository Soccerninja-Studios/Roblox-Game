--!strict
-- ShopService: spawns the hand-authored market stall model (built in Studio and
-- synced in via Rojo at ReplicatedStorage.Assets.Shop), then turns its ShopZone
-- part into a visible, glowing circular area so the player can see exactly where
-- to stand to open the shop. The client watches ShopZone.Position to auto-open,
-- so the visible disc and the interaction radius line up exactly.

local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

local ShopService = {}

local ZONE_FILL = Color3.fromRGB(120, 210, 120)
local ZONE_EDGE = Color3.fromRGB(64, 156, 74)

local function getTemplate(): Model?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local template = assets and assets:FindFirstChild("Shop")
	if template and template:IsA("Model") then
		return template
	end
	return nil
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
