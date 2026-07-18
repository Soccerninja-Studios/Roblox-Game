--!strict
-- ToolController: owns the held shears tool on the client. It reports whether the
-- shears are currently equipped (so mowing requires holding the tool) and plays the
-- snipping animation on every swing by tweening the tool's Motor6D joint.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local ToolController = {}

local player = Players.LocalPlayer

-- Returns the equipped shears tool, or nil if not currently held.
function ToolController.GetEquippedTool(): Tool?
	local character = player.Character
	if not character then
		return nil
	end
	local tool = character:FindFirstChildOfClass("Tool")
	if tool and tool:GetAttribute("Shears") then
		return tool
	end
	return nil
end

function ToolController.IsEquipped(): boolean
	return ToolController.GetEquippedTool() ~= nil
end

-- Plays a quick close-then-open "snip" on the shears.
function ToolController.PlaySwing()
	local tool = ToolController.GetEquippedTool()
	if not tool then
		return
	end
	local handle = tool:FindFirstChild("Handle")
	local snip = handle and handle:FindFirstChild("Snip")
	if not snip or not snip:IsA("Motor6D") then
		return
	end

	local openC0 = snip:GetAttribute("OpenC0")
	local closedC0 = snip:GetAttribute("ClosedC0")
	if typeof(openC0) ~= "CFrame" or typeof(closedC0) ~= "CFrame" then
		return
	end

	local closeTween = TweenService:Create(
		snip,
		TweenInfo.new(0.07, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ C0 = closedC0 }
	)
	local openTween = TweenService:Create(
		snip,
		TweenInfo.new(0.11, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ C0 = openC0 }
	)
	closeTween.Completed:Connect(function()
		openTween:Play()
	end)
	closeTween:Play()
end

function ToolController.Init() end

return ToolController
