--!strict
-- TargetingController: press the mouse SCROLL WHEEL (middle button) to toggle a
-- lock-on mode. While locked on:
--   * the camera frames the targeted enemy over your shoulder (same offset as
--     shift-lock, so your own avatar never blocks the enemy), and
--   * your character keeps facing that enemy while you walk/strafe freely,
-- exactly like the lock-on in most action games. A red reticle hovers over the
-- target: HOLLOW when it is out of sword range, FILLED when it is close enough to
-- hit. Scroll-wheel again (or the on-screen buttons) toggles it off; SwapTarget
-- cycles to the next nearby enemy so you are not stuck on one.
--
-- Lock-on only turns on when there is an enemy nearby, and turns ITSELF off the
-- moment no enemy remains in range -- so you are never stuck in a locked camera
-- staring at nothing.
--
-- Coordinates with ShiftLockController through the player attribute "LockOn":
-- while a lock is held, shift-lock steps aside so they do not fight the camera.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local StatCalculator = require(Shared:WaitForChild("StatCalculator"))

local TargetingController = {}

local player = Players.LocalPlayer

local BIND_NAME = "LockOnFace"
local MAX_LOCK_RANGE = 120 -- studs; drop a target (and lock-on) once nothing is this close
local ACQUIRE_RANGE = 90 -- studs; how far to look when acquiring / what counts as "nearby"
local CAM_BACK = 12 -- studs the camera sits behind the player
local CAM_HEIGHT = 3 -- studs the camera sits above the player before the shoulder offset
local IN_RANGE_PAD = 3 -- fudge added to sword reach for the "filled" ring
-- Same over-the-shoulder framing as ShiftLockController (X = right, Y = up, camera
-- space) so the avatar sits low-left and never blocks the locked-on enemy.
local SHOULDER_OFFSET = Vector3.new(4, 2, 0)

local active = false
local target: Model? = nil
local reticleGui: BillboardGui? = nil
local reticleCircle: Frame? = nil

-- ---------------------------------------------------------------------------
-- Character / world helpers
-- ---------------------------------------------------------------------------

local function character(): Model?
	return player.Character
end

local function currentRoot(): BasePart?
	local char = character()
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function currentHumanoid(): Humanoid?
	local char = character()
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum and hum:IsA("Humanoid") then
		return hum
	end
	return nil
end

local function monsterFolder(): Folder?
	local f = Workspace:FindFirstChild("Monsters")
	if f and f:IsA("Folder") then
		return f
	end
	return nil
end

local function isAliveMonster(model: Instance): boolean
	if not model:IsA("Model") then
		return false
	end
	if model:GetAttribute("Dead") then
		return false
	end
	if (model:GetAttribute("Health") or 0) <= 0 then
		return false
	end
	return model.PrimaryPart ~= nil
end

-- Studs the equipped sword reaches. Returns 0 when no sword is held so the ring
-- never fills without a weapon.
local function swordRange(): number
	local char = character()
	if not char then
		return 0
	end
	local held: Tool? = nil
	for _, ch in char:GetChildren() do
		if ch:IsA("Tool") and ch:GetAttribute("Sword") then
			held = ch
			break
		end
	end
	if not held then
		return 0
	end
	local key = held:GetAttribute("SwordKey")
	return StatCalculator.GetSwordReach(key) + IN_RANGE_PAD
end

-- ---------------------------------------------------------------------------
-- Target selection
-- ---------------------------------------------------------------------------

-- Pick the enemy most directly in FRONT of the camera (highest look dot) within
-- range. Preferred when first locking on.
local function acquireTarget(): Model?
	local folder = monsterFolder()
	local root = currentRoot()
	if not folder or not root then
		return nil
	end
	local camera = Workspace.CurrentCamera
	local look = if camera then camera.CFrame.LookVector else root.CFrame.LookVector
	look = Vector3.new(look.X, 0, look.Z)
	if look.Magnitude < 0.001 then
		look = root.CFrame.LookVector
	end
	look = look.Unit
	local origin = root.Position

	local best: Model? = nil
	local bestScore = -math.huge
	for _, model in folder:GetChildren() do
		if isAliveMonster(model) then
			local mroot = (model :: Model).PrimaryPart :: BasePart
			local to = mroot.Position - origin
			local dist = to.Magnitude
			if dist <= ACQUIRE_RANGE and dist > 0.1 then
				local flat = Vector3.new(to.X, 0, to.Z)
				if flat.Magnitude > 0.001 then
					local dot = flat.Unit:Dot(look)
					-- Favor enemies in front (higher dot), then closer ones.
					local score = dot - (dist / ACQUIRE_RANGE) * 0.35
					if dot > -0.15 and score > bestScore then
						bestScore = score
						best = model :: Model
					end
				end
			end
		end
	end
	return best
end

-- Alive monsters within MAX_LOCK_RANGE, nearest first. Used for swapping and as a
-- fallback when nothing is directly in front.
local function monstersByDistance(): { Model }
	local list: { Model } = {}
	local folder = monsterFolder()
	local root = currentRoot()
	if not folder or not root then
		return list
	end
	local origin = root.Position
	for _, model in folder:GetChildren() do
		if isAliveMonster(model) then
			local mroot = (model :: Model).PrimaryPart :: BasePart
			if (mroot.Position - origin).Magnitude <= MAX_LOCK_RANGE then
				table.insert(list, model :: Model)
			end
		end
	end
	table.sort(list, function(a, b)
		local ra = (a.PrimaryPart :: BasePart).Position
		local rb = (b.PrimaryPart :: BasePart).Position
		return (ra - origin).Magnitude < (rb - origin).Magnitude
	end)
	return list
end

-- The target to lock when turning lock-on on (or re-acquiring): prefer whatever is
-- in front, else the nearest enemy inside ACQUIRE_RANGE. Returns nil when there is
-- simply no enemy nearby -- which is what gates activation and drives auto-off.
local function pickTarget(): Model?
	local t = acquireTarget()
	if t then
		return t
	end
	local root = currentRoot()
	if not root then
		return nil
	end
	local list = monstersByDistance()
	if #list > 0 then
		local nearest = list[1]
		if ((nearest.PrimaryPart :: BasePart).Position - root.Position).Magnitude <= ACQUIRE_RANGE then
			return nearest
		end
	end
	return nil
end

-- ---------------------------------------------------------------------------
-- Reticle (red circle over the target)
-- ---------------------------------------------------------------------------

local function ensureReticle()
	if reticleGui then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "LockOnReticle"
	gui.Size = UDim2.fromOffset(60, 60)
	gui.StudsOffset = Vector3.new(0, 3, 0)
	gui.AlwaysOnTop = true
	gui.ResetOnSpawn = false
	gui.Enabled = false

	local circle = Instance.new("Frame")
	circle.Name = "Circle"
	circle.AnchorPoint = Vector2.new(0.5, 0.5)
	circle.Position = UDim2.fromScale(0.5, 0.5)
	circle.Size = UDim2.fromScale(1, 1)
	circle.BackgroundColor3 = Color3.fromRGB(220, 40, 40)
	circle.BackgroundTransparency = 1 -- hollow by default
	circle.BorderSizePixel = 0
	circle.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = circle

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(220, 40, 40)
	stroke.Thickness = 3
	stroke.Parent = circle

	gui.Parent = player:WaitForChild("PlayerGui")
	reticleGui = gui
	reticleCircle = circle
end

local function hideReticle()
	if reticleGui then
		reticleGui.Enabled = false
		reticleGui.Adornee = nil
	end
end

local function updateReticle(inRange: boolean)
	if not reticleGui or not reticleCircle or not target then
		return
	end
	local adornee = target:FindFirstChild("Head") or target.PrimaryPart
	reticleGui.Adornee = adornee :: any
	reticleGui.Enabled = true
	-- Filled when the enemy is within sword range, hollow otherwise.
	reticleCircle.BackgroundTransparency = if inRange then 0.35 else 1
end

-- ---------------------------------------------------------------------------
-- Enable / disable
-- ---------------------------------------------------------------------------

local function restoreCamera()
	local camera = Workspace.CurrentCamera
	if camera and camera.CameraType ~= Enum.CameraType.Custom then
		camera.CameraType = Enum.CameraType.Custom
	end
end

function TargetingController.IsActive(): boolean
	return active
end

local function enable()
	if active then
		return
	end
	-- Only lock on if there is actually an enemy nearby.
	local t = pickTarget()
	if not t then
		return
	end
	active = true
	target = t
	player:SetAttribute("LockOn", true) -- lets ShiftLockController step aside
end

local function disable()
	if not active then
		return
	end
	active = false
	target = nil
	player:SetAttribute("LockOn", false)
	restoreCamera()
	local hum = currentHumanoid()
	if hum then
		hum.AutoRotate = true
	end
	hideReticle()
end

-- ---------------------------------------------------------------------------
-- Per-frame lock-on update
-- ---------------------------------------------------------------------------

local function onStep()
	if not active then
		return
	end
	local root = currentRoot()
	if not root then
		return
	end

	-- Drop the current target if it died, despawned, or drifted out of range.
	if target then
		local mroot = target.PrimaryPart
		if not target.Parent or not isAliveMonster(target) or not mroot then
			target = nil
		elseif (mroot.Position - root.Position).Magnitude > MAX_LOCK_RANGE then
			target = nil
		end
	end
	-- Try to re-acquire; if nothing is nearby, lock-on turns ITSELF off.
	if not target then
		target = pickTarget()
	end
	if not target then
		disable()
		return
	end

	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end

	local troot = target.PrimaryPart :: BasePart
	local ppos = root.Position
	local tpos = troot.Position

	-- Face the character at the enemy (flat) so you always face it while moving.
	local flatTarget = Vector3.new(tpos.X, ppos.Y, tpos.Z)
	if (flatTarget - ppos).Magnitude > 0.05 then
		root.CFrame = CFrame.lookAt(ppos, flatTarget)
	end
	local hum = currentHumanoid()
	if hum then
		hum.AutoRotate = false
	end

	-- Frame the camera behind the player, looking toward the enemy, then shove it
	-- over the shoulder by the SAME offset shift-lock uses so the avatar never blocks
	-- the enemy. Multiplying on the right keeps the view direction and just slides the
	-- camera right + up in its own space.
	local dir = Vector3.new(tpos.X - ppos.X, 0, tpos.Z - ppos.Z)
	if dir.Magnitude < 0.01 then
		local look = root.CFrame.LookVector
		dir = Vector3.new(look.X, 0, look.Z)
	end
	dir = dir.Unit
	camera.CameraType = Enum.CameraType.Scriptable
	local camPos = ppos - dir * CAM_BACK + Vector3.new(0, CAM_HEIGHT, 0)
	local aim = ppos:Lerp(tpos, 0.6) + Vector3.new(0, 2.5, 0)
	camera.CFrame = CFrame.lookAt(camPos, aim) * CFrame.new(SHOULDER_OFFSET.X, SHOULDER_OFFSET.Y, 0)

	-- Fill the reticle when the enemy is within sword range.
	local inRange = (tpos - ppos).Magnitude <= swordRange()
	updateReticle(inRange)
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

function TargetingController.Toggle()
	if active then
		disable()
	else
		enable()
	end
end

-- Cycle to the next-nearest enemy. Turns lock-on on first if it was off (and only
-- if an enemy is nearby, via enable()).
function TargetingController.SwapTarget()
	if not active then
		enable()
		return
	end
	local list = monstersByDistance()
	if #list == 0 then
		target = nil
		return
	end
	local idx = 1
	if target then
		for i, m in ipairs(list) do
			if m == target then
				idx = i + 1
				break
			end
		end
		if idx > #list then
			idx = 1
		end
	end
	target = list[idx]
end

function TargetingController.Init()
	ensureReticle()
	player:SetAttribute("LockOn", false)

	-- Runs after ShiftLockController's bind (Character + 2 vs + 1); shift-lock yields
	-- to us via the LockOn attribute, so there is no camera/facing tug-of-war.
	RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Character.Value + 2, onStep)

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton3 then
			TargetingController.Toggle()
		end
	end)

	-- A fresh character means a new rig and camera; drop any stale lock cleanly.
	player.CharacterAdded:Connect(function()
		if active then
			disable()
		end
	end)
end

function TargetingController.Start() end

return TargetingController
