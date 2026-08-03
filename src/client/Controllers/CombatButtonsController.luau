--!strict
-- CombatButtonsController: on-screen buttons (work on both desktop and mobile) for
-- the three combat camera/targeting modes, so players do not need a keyboard or a
-- scroll wheel:
--   * Shift Lock  -> toggles ShiftLockController
--   * Lock On     -> toggles TargetingController (lock-on)
--   * Swap Target -> cycles TargetingController to the next nearby enemy
-- The Shift Lock and Lock On buttons glow green while their mode is active.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local CombatButtonsController = {}

local player = Players.LocalPlayer

local ShiftLockController = require(script.Parent:WaitForChild("ShiftLockController"))
local TargetingController = require(script.Parent:WaitForChild("TargetingController"))

local ACTIVE_COLOR = Color3.fromRGB(60, 170, 90)
local IDLE_COLOR = Color3.fromRGB(45, 45, 52)

local shiftBtn: TextButton? = nil
local lockBtn: TextButton? = nil

local function makeButton(name: string, text: string, order: number): TextButton
	local btn = Instance.new("TextButton")
	btn.Name = name
	btn.Size = UDim2.fromOffset(150, 44)
	-- Stacked up from the bottom-right corner.
	btn.AnchorPoint = Vector2.new(1, 1)
	btn.Position = UDim2.new(1, -20, 1, -20 - order * 54)
	btn.BackgroundColor3 = IDLE_COLOR
	btn.BackgroundTransparency = 0.15
	btn.AutoButtonColor = true
	btn.Text = text
	btn.TextColor3 = Color3.fromRGB(240, 240, 245)
	btn.Font = Enum.Font.GothamMedium
	btn.TextSize = 16
	btn.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = btn
	return btn
end

function CombatButtonsController.Init()
	local gui = Instance.new("ScreenGui")
	gui.Name = "CombatButtons"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 25
	gui.Parent = player:WaitForChild("PlayerGui")

	local shift = makeButton("ShiftLock", "Shift Lock", 2)
	local lock = makeButton("LockOn", "Lock On", 1)
	local swap = makeButton("Swap", "Swap Target", 0)
	shift.Parent = gui
	lock.Parent = gui
	swap.Parent = gui
	shiftBtn = shift
	lockBtn = lock

	shift.Activated:Connect(function()
		ShiftLockController.Toggle()
	end)
	lock.Activated:Connect(function()
		TargetingController.Toggle()
	end)
	swap.Activated:Connect(function()
		TargetingController.SwapTarget()
	end)

	-- Keep the two toggle buttons' highlight in sync with their live state (they can
	-- also be toggled by keyboard / scroll wheel).
	RunService.Heartbeat:Connect(function()
		if shiftBtn then
			shiftBtn.BackgroundColor3 = if ShiftLockController.IsEnabled() then ACTIVE_COLOR else IDLE_COLOR
		end
		if lockBtn then
			lockBtn.BackgroundColor3 = if TargetingController.IsActive() then ACTIVE_COLOR else IDLE_COLOR
		end
	end)
end

function CombatButtonsController.Start() end

return CombatButtonsController
