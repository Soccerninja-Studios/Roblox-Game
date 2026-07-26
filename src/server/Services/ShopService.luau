--!strict
-- ShopService: spawns the hand-authored market stall (synced in via Rojo at
-- ReplicatedStorage.Assets.Shop), drops it exactly where the designer asked, tints
-- its walk-in ShopZone disc YELLOW, and gives the shopkeeper NPC a looping idle so
-- the stall feels alive. The model already ships with a "SHOP" sign, a ShopZone +
-- ShopZoneRing pad, and an R6 shopkeeper, so this service is mostly placement +
-- polish. The client watches the ShopZone position to auto-open the shop menu.
--
-- INTRO CUTSCENE: the stall must not be standing in the plains while the intro is
-- still playing. When GameConfig.INTRO_CUTSCENE is on we build the model but park it
-- in ServerStorage, where no client can see it, and only move it into the Workspace
-- when CutsceneService calls Reveal() -- which it does while the screen is faded to
-- black, so the stall is simply "already there" when the picture comes back.

local Workspace = game:GetService("Workspace")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local NpcRig = require(ReplicatedStorage.Shared.NpcRig)

local ShopService = {}

-- The shop's walk-in circle is YELLOW.
local ZONE_FILL = Color3.fromRGB(255, 224, 92)
local ZONE_EDGE = Color3.fromRGB(240, 190, 55)

-- The built stall, and whether it's allowed on screen yet.
local shopModel: Model? = nil
local revealed = false

local function getTemplate(): Model?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local template = assets and assets:FindFirstChild("Shop")
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

-- Anchor the stall geometry so walking into it can't knock it out of place. The
-- shopkeeper is handled separately by NpcRig.Stabilize, which pins the root and
-- frees the limbs so the idle animation still plays.
local function anchorModel(model: Model)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
		end
	end
end

-- Everything that should only start running once the stall is actually on screen.
local function activate(model: Model)
	NpcRig.Stabilize(model)
	NpcRig.PlayIdle(model)
	styleZone(model)
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
	-- Anchor before it goes live so it can't be shoved around.
	anchorModel(model)
	shopModel = model

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
function ShopService.Reveal()
	if revealed then
		return
	end
	revealed = true

	local model = shopModel
	if model and model.Parent ~= Workspace then
		model.Parent = Workspace
		activate(model)
	end
end

function ShopService.Init() end

function ShopService.Start()
	-- No intro means nothing to hide behind, so the stall is live immediately.
	if not GameConfig.INTRO_CUTSCENE then
		revealed = true
	end
	spawnShop()
	print("[ShopService] Shop ready." .. (if revealed then "" else " (hidden until the intro fades out)"))
end

return ShopService
