--!strict
-- ShiftLockController: press Left Shift to toggle a shoulder/aim lock. While it is
-- on, the mouse is pinned to screen center and the character continuously turns to
-- face the camera's look direction -- so you can circle-strafe a monster and land
-- sword hits without over-running into it or having to fully retreat.
--
-- NOTE (manual Studio step): if Roblox's built-in "Shift Lock Switch" is also on,
-- Shift would toggle two systems at once. Turn the built-in one off by setting
-- StarterPlayer.EnableMouseLockOption = false.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ShiftLockController = {}

local player = Players.LocalPlayer

local TOGGLE_KEY = Enum.KeyCode.LeftShift
local BIND_NAME = "ShiftLockFace"

local enabled = false

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

-- Runs just after the default character update: keep the mouse pinned and turn the
-- character to match where the camera is looking (horizontal only, so the body
-- stays upright while you aim).
local function onStep()
	if not enabled then
		return
	end
	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	local camera = Workspace.CurrentCamera
	local root = currentRoot()
	if not camera or not root then
		return
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
	end
	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
end

local function disable()
	if not enabled then
		return
	end
	enabled = false
	local hum = currentHumanoid()
	if hum then
		hum.AutoRotate = true
	end
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
end

function ShiftLockController.Init()
	-- Bind just after the camera/character update so our facing override wins.
	RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Character.Value + 1, onStep)

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end
		if input.KeyCode == TOGGLE_KEY then
			if enabled then
				disable()
			else
				enable()
			end
		end
	end)

	-- On respawn, re-apply the lock state to the fresh character.
	player.CharacterAdded:Connect(function(char)
		if not enabled then
			return
		end
		local hum = char:WaitForChild("Humanoid", 5)
		if hum and hum:IsA("Humanoid") then
			hum.AutoRotate = false
		end
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	end)
end

function ShiftLockController.Start() end

return ShiftLockController
