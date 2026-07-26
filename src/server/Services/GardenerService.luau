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
--
-- THE SAGGING TORSO: the Farmer's torso used to droop out of the stall. The old
-- code pinned the NPC by anchoring its HumanoidRootPart and unanchoring everything
-- else, which left a live Humanoid state machine attached to a body hanging in mid
-- air -- it fell into Freefall/Ragdoll and dragged the torso down. Shared/NpcRig now
-- handles that properly (rebuilds a missing RootJoint, disables the state machine,
-- pins only the root), so the Farmer holds his pose while still playing his idle.
--
-- INTRO CUTSCENE: while the intro is playing the stall is parked in ServerStorage
-- so no client can see it, and CutsceneService calls Reveal() during the fade to
-- black -- so it's simply already standing there when the picture returns.

local Workspace = game:GetService("Workspace")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local NpcRig = require(ReplicatedStorage.Shared.NpcRig)

local GardenerService = {}

local PlayerDataService: any
local QuestService: any

-- The Gardener's walk-in circle is LIGHT GREEN.
local ZONE_FILL = Color3.fromRGB(150, 235, 130)
local ZONE_EDGE = Color3.fromRGB(96, 200, 110)

-- The built stall, and whether it's allowed on screen yet.
local gardenerModel: Model? = nil
local revealed = false

local function getTemplate(): Model?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local template = assets and assets:FindFirstChild("Gardener")
	if template and template:IsA("Model") then
		return template :: Model
	end
	return nil
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

-- Anchor the stall geometry so walking into it can't knock it out of place. The
-- Farmer is handled separately by NpcRig.Stabilize, which pins the root and frees
-- the limbs so the idle animation still plays.
local function anchorModel(model: Model)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
		end
	end
end

-- A floating green "GARDENER" sign hovering above the stand, mirroring the shop's
-- "SHOP" label so players can spot the deposit point from a distance.
local function floatLabel(model: Model)
	local anchor = Instance.new("Part")
	anchor.Name = "GardenerLabelAnchor"
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CastShadow = false
	anchor.CFrame = CFrame.new(GameConfig.GARDENER_POSITION + Vector3.new(0, 8, 0))
	anchor.Parent = model

	local gui = Instance.new("BillboardGui")
	gui.Name = "GardenerSign"
	gui.Adornee = anchor
	gui.Size = UDim2.new(9, 0, 2.4, 0)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 0, 0)
	gui.MaxDistance = 300
	gui.AlwaysOnTop = false
	gui.Parent = anchor

	local label = Instance.new("TextLabel")
	label.Name = "TextLabel"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.Text = "GARDENER"
	label.TextColor3 = Color3.fromRGB(238, 255, 226)
	label.TextScaled = true
	label.TextStrokeColor3 = Color3.fromRGB(24, 54, 22)
	label.TextStrokeTransparency = 0.35
	label.Parent = gui

	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new(Color3.fromRGB(150, 240, 120), Color3.fromRGB(64, 168, 72))
	grad.Rotation = 90
	grad.Parent = label
end

-- Everything that should only start running once the stall is actually on screen.
local function activate(model: Model)
	NpcRig.Stabilize(model)
	NpcRig.PlayIdle(model)
	styleZone(model)
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
	-- Anchor before it goes live so it can't be shoved around.
	anchorModel(model)
	floatLabel(model)
	gardenerModel = model

	if revealed then
		model.Parent = Workspace
		activate(model)
	else
		-- Held off-screen until the intro fades to black. ServerStorage never
		-- replicates, so the stall is genuinely invisible rather than just transparent.
		model.Parent = ServerStorage
	end
end

-- Called by CutsceneService behind the fade to black (and harmlessly again on the
-- skip / error path). Safe to call before Start(): the flag makes the eventual
-- spawn go straight into the Workspace.
function GardenerService.Reveal()
	if revealed then
		return
	end
	revealed = true

	local model = gardenerModel
	if model and model.Parent ~= Workspace then
		model.Parent = Workspace
		activate(model)
	end
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
		-- Quests: credit banked gold and any diamonds earned this deposit.
		if QuestService then
			QuestService.ReportDeposit(player, summary.gold or 0, summary.diamonds or 0)
		end
	end
end

function GardenerService.Init(services: any)
	PlayerDataService = services.PlayerDataService
	QuestService = services.QuestService
	Remotes.Get("RequestDeposit").OnServerEvent:Connect(onRequestDeposit)
end

function GardenerService.Start()
	-- No intro means nothing to hide behind, so the stall is live immediately.
	if not GameConfig.INTRO_CUTSCENE then
		revealed = true
	end
	spawnGardener()
	print("[GardenerService] Deposit stall ready." .. (if revealed then "" else " (hidden until the intro fades out)"))
end

return GardenerService
