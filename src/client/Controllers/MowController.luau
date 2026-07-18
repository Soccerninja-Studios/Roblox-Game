--!strict
-- MowController: handles mowing input. The player must be HOLDING the shears tool
-- and hold left-click (or touch) to keep cutting the grass tile under the cursor.
-- The server validates everything; this only requests cuts and plays the swing.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local StatCalculator = require(ReplicatedStorage.Shared.StatCalculator)

local MowController = {}

local player = Players.LocalPlayer
local mouse = player:GetMouse()

local ToolController: any

local mowing = false
local lastSwing = 0
local swingCooldown = GameConfig.BASE_SWING_COOLDOWN

local function tryCut()
	-- Mowing requires the physical shears to be equipped.
	if not ToolController or not ToolController.IsEquipped() then
		return
	end

	local target = mouse.Target
	if not target or target.Name ~= "GrassTile" then
		return
	end
	if (target:GetAttribute("Health") :: number? or 0) <= 0 then
		return
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root or (root.Position - target.Position).Magnitude > GameConfig.CUT_RANGE + target.Size.Y then
		return
	end

	lastSwing = os.clock()
	ToolController.PlaySwing()
	Remotes.Get("RequestCut"):FireServer(target)
end

function MowController.Init(controllers: any)
	ToolController = controllers.ToolController

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			mowing = true
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			mowing = false
		end
	end)

	-- Keep our swing speed in sync with purchased upgrades
	Remotes.Get("StateChanged").OnClientEvent:Connect(function(state: any)
		swingCooldown = StatCalculator.GetSwingCooldown(state.skills)
	end)
end

function MowController.Start()
	while true do
		task.wait(0.03)
		if mowing and os.clock() - lastSwing >= swingCooldown then
			tryCut()
		end
	end
end

return MowController
