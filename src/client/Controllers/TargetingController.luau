--!strict
-- TargetingController: press the mouse SCROLL WHEEL (middle button) to toggle a
-- lock-on mode; press E to swap to the next nearby enemy. While locked on:
--   * the camera frames the targeted enemy over your shoulder (same offset as
--     shift-lock, so your own avatar never blocks the enemy),
--   * your character keeps facing that enemy while you walk/strafe freely, and
--   * the mouse cursor is hidden and pinned to center, just like shift-lock.
--
-- You can still ZOOM in/out with the scroll wheel while locked on -- the camera
-- distance follows your zoom, but the over-the-shoulder proportions (4 studs
-- right and 2 studs up) stay fixed regardless of zoom.
--
-- The reticle is the shared shift-lock crosshair: it shows WHITE while the target
-- is out of sword range and turns RED when the target is close enough to hit.
--
-- Lock-on only turns on when there is an enemy nearby, and turns ITSELF off the
-- moment no enemy remains in range.
--
-- Coordinates with ShiftLockController through the player attribute "LockOn":
-- while a lock is held, shift-lock steps aside so they do not fight the camera.
-- On disable, AutoRotate and the cursor are only restored if shift-lock isn't
-- still on -- otherwise shift-lock keeps owning facing/cursor, which avoids the
-- Humanoid-vs-shift-lock facing tug-of-war that caused jittery movement.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CombatRange = require(Shared:WaitForChild("CombatRange"))
local ShiftLockController = require(script.Parent:WaitForChild("ShiftLockController"))

local TargetingController = {}

local player = Players.LocalPlayer

local BIND_NAME = "LockOnFace"
local MAX_LOCK_RANGE = 120 -- studs; drop a target (and lock-on) once nothing is this close
local ACQUIRE_RANGE = 90 -- studs; how far to look when acquiring / what counts as "nearby"
-- Keep the lock camera near the player's shoulder/head height instead of raising
-- it from the full player-to-target distance. This avoids the steep overhead view.
local CAMERA_HEIGHT = 2.25 -- studs above the player's HumanoidRootPart
local TARGET_AIM_HEIGHT = 1.25 -- aim around the monster's upper body, not above it
local ZOOM_STEP = 3 -- studs of zoom per scroll-wheel notch while locked on
-- Same over-the-shoulder framing as ShiftLockController (X = right, Y = up, camera
-- space). Kept fixed in studs so the proportions stay the same at any zoom.
local SHOULDER_OFFSET = Vector3.new(4, 2, 0)
local WHITE = Color3.new(1, 1, 1)
local RED = Color3.fromRGB(220, 40, 40)

local active = false
local target: Model? = nil
local restoreOnNextCharacter = false
local zoomDistance = 14 -- current camera pull-back; seeded from real zoom on enable

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
	return CombatRange.IsAliveMonster(model)
end

-- Sane zoom clamp: respect the player's own zoom settings but keep a small floor
-- so the shoulder framing never collapses into first-person.
local function zoomBounds(): (number, number)
	local lo = math.max(player.CameraMinZoomDistance, 5)
	local hi = math.min(player.CameraMaxZoomDistance, 80)
	if hi < lo then
		hi = lo
	end
	return lo, hi
end

-- Seed the pull-back from the camera's real distance so toggling lock-on does not
-- snap the zoom the player had set.
local function seedZoom()
	local lo, hi = zoomBounds()
	local camera = Workspace.CurrentCamera
	local root = currentRoot()
	if camera and root then
		zoomDistance = math.clamp((camera.CFrame.Position - root.Position).Magnitude, lo, hi)
	else
		zoomDistance = math.clamp(zoomDistance, lo, hi)
	end
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
-- Enable / disable
-- ---------------------------------------------------------------------------

local function restoreCamera(subject: Humanoid?)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	-- CameraType alone is not enough after a Scriptable-camera death: Roblox can
	-- retain the dead humanoid as CameraSubject and leave the view at the death site.
	-- Explicitly bind the current/new humanoid before returning control to Roblox.
	local hum = subject or currentHumanoid()
	if hum then
		camera.CameraSubject = hum
	end
	camera.CameraType = Enum.CameraType.Custom
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
	restoreOnNextCharacter = false -- a living rig has taken ownership again
	seedZoom()
	player:SetAttribute("LockOn", true) -- lets ShiftLockController step aside
	-- Hide + center the cursor, just like shift-lock.
	UserInputService.MouseIconEnabled = false
	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	-- Reuse the shift-lock crosshair as the reticle (white until in range).
	ShiftLockController.SetCrosshairColor(WHITE)
	ShiftLockController.SetCrosshairVisible(true)
end

local function disable()
	-- Always perform the full reset, even if active was already cleared elsewhere.
	-- Respawning can otherwise leave a Scriptable camera or stale CameraSubject.
	active = false
	target = nil
	player:SetAttribute("LockOn", false)
	restoreCamera()
	local hum = currentHumanoid()
	if hum then
		-- If shift-lock is still on it owns facing; turning AutoRotate back on here is
		-- what caused the jitter (Humanoid auto-turn vs shift-lock's manual facing).
		hum.AutoRotate = not ShiftLockController.IsEnabled()
	end
	-- Restore the cursor unless shift-lock still wants it hidden.
	if not ShiftLockController.IsEnabled() then
		UserInputService.MouseIconEnabled = true
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	end
	-- Hand the crosshair back to shift-lock: reset to white, keep it visible only if
	-- shift-lock itself is still on.
	ShiftLockController.SetCrosshairColor(WHITE)
	ShiftLockController.SetCrosshairVisible(ShiftLockController.IsEnabled())
end

-- ---------------------------------------------------------------------------
-- Per-frame lock-on update
-- ---------------------------------------------------------------------------

local function onStep()
	if not active then
		return
	end
	local root = currentRoot()
	local hum = currentHumanoid()
	if not root or not hum or hum.Health <= 0 then
		restoreOnNextCharacter = true
		disable()
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

	-- Keep the cursor hidden/centered every frame (robust even if shift-lock was
	-- toggled off underneath us).
	UserInputService.MouseIconEnabled = false
	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter

	-- Face the character at the enemy (flat) so you always face it while moving.
	local flatTarget = Vector3.new(tpos.X, ppos.Y, tpos.Z)
	if (flatTarget - ppos).Magnitude > 0.05 then
		root.CFrame = CFrame.lookAt(ppos, flatTarget)
	end
	hum.AutoRotate = false

	-- Frame the camera behind the player at the player's current zoom distance,
	-- looking toward the enemy, then move it over the shoulder by the same fixed
	-- offset shift-lock uses. Its Y position stays near the player's head instead of
	-- scaling upward with target distance, preventing an overhead lock-on view.
	local dir = Vector3.new(tpos.X - ppos.X, 0, tpos.Z - ppos.Z)
	if dir.Magnitude < 0.01 then
		local look = root.CFrame.LookVector
		dir = Vector3.new(look.X, 0, look.Z)
	end
	dir = dir.Unit
	camera.CameraType = Enum.CameraType.Scriptable
	local aim = tpos + Vector3.new(0, TARGET_AIM_HEIGHT, 0)
	local backXZ = ppos - dir * zoomDistance
	local camPos = Vector3.new(backXZ.X, ppos.Y + CAMERA_HEIGHT, backXZ.Z)
	camera.CFrame = CFrame.lookAt(camPos, aim) * CFrame.new(SHOULDER_OFFSET.X, SHOULDER_OFFSET.Y, 0)

	-- Crosshair is the range indicator: red when the enemy is within sword range,
	-- white otherwise. Keep it shown while locked on.
	local inRange = CombatRange.IsInSwingBox(character(), tpos)
	ShiftLockController.SetCrosshairColor(if inRange then RED else WHITE)
	ShiftLockController.SetCrosshairVisible(true)
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
		elseif input.KeyCode == Enum.KeyCode.E then
			TargetingController.SwapTarget()
		end
	end)

	-- Scroll wheel zooms while locked on. Because the lock-on camera is Scriptable
	-- (which disables the default zoom), we track the distance ourselves and clamp
	-- it to the player's zoom limits.
	UserInputService.InputChanged:Connect(function(input, gameProcessed)
		if not active then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseWheel then
			local lo, hi = zoomBounds()
			zoomDistance = math.clamp(zoomDistance - input.Position.Z * ZOOM_STEP, lo, hi)
		end
	end)

	-- Death must release Scriptable mode immediately. On the next CharacterAdded we
	-- also bind CameraSubject to the NEW humanoid after it exists; this is what makes
	-- the camera snap back to the respawn instead of watching the old target.
	local function bindCharacter(char: Model)
		-- If CharacterAdded beat the death/removal callbacks, preserve the fact that
		-- this lock-on camera still needs to be rebound to the new rig.
		if active then
			restoreOnNextCharacter = true
			disable()
		end
		task.spawn(function()
			local hum = char:WaitForChild("Humanoid", 10)
			if not hum or not hum:IsA("Humanoid") or player.Character ~= char then
				return
			end
			hum.Died:Connect(function()
				if player.Character == char and active then
					restoreOnNextCharacter = true
					disable()
				end
			end)
			if restoreOnNextCharacter then
				-- Let Roblox finish assigning the new character, then explicitly take the
				-- camera off the dead humanoid/old death-site CFrame.
				task.wait()
				if player.Character == char then
					restoreCamera(hum)
					restoreOnNextCharacter = false
				end
			end
		end)
	end

	player.CharacterRemoving:Connect(function()
		if active then
			restoreOnNextCharacter = true
			disable()
		end
	end)
	player.CharacterAdded:Connect(bindCharacter)
	if player.Character then
		-- Bind the death listener without overriding an opening cutscene camera.
		bindCharacter(player.Character)
	end
end

function TargetingController.Start() end

return TargetingController
