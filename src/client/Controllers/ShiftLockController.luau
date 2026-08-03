--!strict
-- ShiftLockController: press Left Shift to toggle a shoulder/aim lock. While it is
-- on, the mouse cursor is hidden and pinned to screen center, a small crosshair
-- marks the aim point, the camera slides over the player's right shoulder, and the
-- character continuously turns to face the camera's look direction -- so you can
-- circle-strafe a monster and land sword hits without over-running into it, fully
-- retreating, or being blocked by your own avatar.
--
-- The crosshair is shared: TargetingController reuses it during lock-on. In BOTH
-- modes it is WHITE normally and turns RED when an enemy is within sword swing
-- range (shift-lock checks whatever is in front of you; lock-on checks the locked
-- target). That is why the crosshair helpers are public.
--
-- Lock-on takes priority: while TargetingController has a lock (player attribute
-- "LockOn" is true) this controller steps aside so the two don't fight over the
-- camera and the character's facing.
--
-- NOTE (manual Studio step): if Roblox's built-in "Shift Lock Switch" is also on,
-- Shift would toggle two systems at once. Turn the built-in one off by setting
-- StarterPlayer.EnableMouseLockOption = false.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatRange = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CombatRange"))

local ShiftLockController = {}

local player = Players.LocalPlayer

local TOGGLE_KEY = Enum.KeyCode.LeftShift
local BIND_NAME = "ShiftLockFace"
-- Slide the camera over the player's right shoulder and up (X = right, Y = up, in
-- camera space) so the avatar sits low-left on screen and the monsters ahead stay
-- visible -- the classic over-the-shoulder combat framing.
local SHOULDER_OFFSET = Vector3.new(4, 2, 0)
local WHITE = Color3.new(1, 1, 1)
local RED = Color3.fromRGB(220, 40, 40)

local enabled = false
local crosshair: ScreenGui? = nil
local crosshairH: Frame? = nil
local crosshairV: Frame? = nil

local function currentHumanoid(): Humanoid?
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum and hum:IsA("Humanoid") then
		return hum
	end
	return nil
end

local function currentRoot(): BasePart?
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

-- A tiny plus in the dead center of the screen. Because shift-lock hides the OS
-- cursor, this is what the player aims with. Built once and kept across respawns
-- (ResetOnSpawn = false); shown while shift-lock OR lock-on is on.
local function ensureCrosshair()
	if crosshair then
		return
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "ShiftLockCrosshair"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 30
	gui.Enabled = false

	local SIZE = 14
	local THICK = 2

	local horizontal = Instance.new("Frame")
	horizontal.Name = "H"
	horizontal.AnchorPoint = Vector2.new(0.5, 0.5)
	horizontal.Position = UDim2.fromScale(0.5, 0.5)
	horizontal.Size = UDim2.fromOffset(SIZE, THICK)
	horizontal.BackgroundColor3 = WHITE
	horizontal.BorderSizePixel = 0
	horizontal.Parent = gui

	local vertical = Instance.new("Frame")
	vertical.Name = "V"
	vertical.AnchorPoint = Vector2.new(0.5, 0.5)
	vertical.Position = UDim2.fromScale(0.5, 0.5)
	vertical.Size = UDim2.fromOffset(THICK, SIZE)
	vertical.BackgroundColor3 = WHITE
	vertical.BorderSizePixel = 0
	vertical.Parent = gui

	gui.Parent = player:WaitForChild("PlayerGui")
	crosshair = gui
	crosshairH = horizontal
	crosshairV = vertical
end

-- Public crosshair controls (also used by TargetingController during lock-on).
function ShiftLockController.SetCrosshairVisible(visible: boolean)
	if crosshair then
		crosshair.Enabled = visible
	end
end

function ShiftLockController.SetCrosshairColor(color: Color3)
	if crosshairH then
		crosshairH.BackgroundColor3 = color
	end
	if crosshairV then
		crosshairV.BackgroundColor3 = color
	end
end

-- Runs just after the default character update: keep the cursor pinned and turn
-- the character to match where the camera is looking (horizontal only, so the
-- body stays upright while you aim). Yields entirely to lock-on when it is active.
local function onStep()
	if not enabled then
		return
	end
	if player:GetAttribute("LockOn") then
		return -- TargetingController owns the camera + facing right now
	end
	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	-- Crosshair turns red when an enemy is within swing range in front of you.
	local inRange = CombatRange.AnyEnemyInSwingRange(player.Character)
	ShiftLockController.SetCrosshairColor(if inRange then RED else WHITE)
	local camera = Workspace.CurrentCamera
	local root = currentRoot()
	if not camera or not root then
		return
	end
	-- Re-assert manual facing every frame so nothing else (e.g. a just-disabled
	-- lock-on flipping AutoRotate back on) fights us and jitters the character.
	local hum = currentHumanoid()
	if hum then
		hum.AutoRotate = false
	end
	local look = camera.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.001 then
		return
	end
	local pos = root.Position
	root.CFrame = CFrame.lookAt(pos, pos + flat.Unit)
end

local function enable()
	if enabled then
		return
	end
	enabled = true
	local hum = currentHumanoid()
	if hum then
		hum.AutoRotate = false
		hum.CameraOffset = SHOULDER_OFFSET
	end
	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	UserInputService.MouseIconEnabled = false
	ShiftLockController.SetCrosshairColor(WHITE)
	ShiftLockController.SetCrosshairVisible(true)
end

local function disable()
	if not enabled then
		return
	end
	enabled = false
	local hum = currentHumanoid()
	if hum then
		-- Only hand facing back to the engine if lock-on isn't still driving it.
		hum.AutoRotate = not player:GetAttribute("LockOn")
		hum.CameraOffset = Vector3.zero
	end
	-- Keep the cursor hidden if lock-on is still active; otherwise restore it.
	if not player:GetAttribute("LockOn") then
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
	end
	ShiftLockController.SetCrosshairColor(WHITE)
	-- Keep the crosshair up if lock-on is still using it; otherwise hide it.
	if not player:GetAttribute("LockOn") then
		ShiftLockController.SetCrosshairVisible(false)
	end
end

-- Public API (used by the on-screen combat buttons).
function ShiftLockController.Toggle()
	if enabled then
		disable()
	else
		enable()
	end
end

function ShiftLockController.IsEnabled(): boolean
	return enabled
end

function ShiftLockController.Init()
	ensureCrosshair()

	-- Bind just after the camera/character update so our facing override wins.
	RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Character.Value + 1, onStep)

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end
		if input.KeyCode == TOGGLE_KEY then
			ShiftLockController.Toggle()
		end
	end)

	-- On respawn, re-apply the lock state (facing, cursor, and shoulder camera) to
	-- the fresh character.
	player.CharacterAdded:Connect(function(char)
		if not enabled then
			return
		end
		local hum = char:WaitForChild("Humanoid", 5)
		if hum and hum:IsA("Humanoid") then
			hum.AutoRotate = false
			hum.CameraOffset = SHOULDER_OFFSET
		end
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		UserInputService.MouseIconEnabled = false
	end)
end

function ShiftLockController.Start() end

return ShiftLockController
