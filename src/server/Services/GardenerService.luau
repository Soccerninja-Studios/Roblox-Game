--!strict
-- GardenerService: the deposit stall. Players fill their carry bag by mowing, then
-- walk onto the Gardener's glowing pad to BANK everything -- clippings convert to
-- gold (and, rarely, diamonds) and the bag empties. This spawns the hand-authored
-- gardener stall (synced in via Rojo at ReplicatedStorage.Assets.Gardener), drops it
-- exactly where the designer asked, tints its GardenerZone disc LIGHT GREEN, and
-- loops an idle on the Farmer NPC. The model already ships with a "DEPOSIT CLIPPINGS"
-- sign, a GardenerZone + GardenerZoneRing pad, and an R6 farmer. All deposit math
-- lives in PlayerDataService.Deposit; this service validates that the player is
-- actually standing on the pad before banking.

local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local GardenerService = {}

local PlayerDataService: any

-- The Gardener's walk-in circle is LIGHT GREEN.
local ZONE_FILL = Color3.fromRGB(150, 235, 130)
local ZONE_EDGE = Color3.fromRGB(96, 200, 110)

-- Looping catalog idles, picked to match the NPC's rig.
local IDLE_R6 = "rbxassetid://180435571"
local IDLE_R15 = "rbxassetid://507766388"

local function getTemplate(): Model?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local template = assets and assets:FindFirstChild("Gardener")
	if template and template:IsA("Model") then
		return template :: Model
	end
	return nil
end

-- Plant the Farmer NPC and loop a gentle idle animation.
local function animateNPC(model: Model)
	local humanoid: Humanoid? = nil
	for _, d in model:GetDescendants() do
		if d:IsA("Humanoid") then
			humanoid = d
			break
		end
	end
	if not humanoid then
		warn("[GardenerService] No Farmer Humanoid found; skipping idle animation.")
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
		warn("[GardenerService] Could not load the Farmer idle animation.")
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

-- Recolor the authored GardenerZone / GardenerZoneRing into a glowing light-green
-- disc, keeping the builder's geometry + position.
local function styleZone(model: Model)
	local zone = model:FindFirstChild("GardenerZone", true)
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
		warn("[GardenerService] Gardener model has no GardenerZone part; walk-in area won't glow.")
	end

	local ring = model:FindFirstChild("GardenerZoneRing", true)
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

local function spawnGardener()
	local template = getTemplate()
	if not template then
		warn("[GardenerService] No ReplicatedStorage.Assets.Gardener model found; skipping gardener spawn.")
		return
	end

	local existing = Workspace:FindFirstChild("Gardener")
	if existing then
		existing:Destroy()
	end

	local model = template:Clone()
	model.Name = "Gardener"

	-- Place exactly at the designer-specified pivot with zero orientation.
	model:PivotTo(CFrame.new(GameConfig.GARDENER_POSITION))
	model.Parent = Workspace

	animateNPC(model)
	styleZone(model)
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
	spawnGardener()
	print("[GardenerService] Deposit stall ready.")
end

return GardenerService
