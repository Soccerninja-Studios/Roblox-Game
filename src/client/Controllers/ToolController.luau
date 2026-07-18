--!strict
-- ToolController: owns the held cutting tool on the client. It reports whether the
-- tool is currently equipped (mowing requires holding it) and animates every swing
-- by tweening the tool's Motor6D joints:
--   "Pivot" -> the swing arc (all tools)
--   "Snip"  -> the blade closing (shears only)

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local ToolController = {}

local player = Players.LocalPlayer

-- Returns the equipped tool, or nil if not currently held.
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

local function findMotor(tool: Tool, name: string): Motor6D?
	for _, d in tool:GetDescendants() do
		if d:IsA("Motor6D") and d.Name == name then
			return d
		end
	end
	return nil
end

-- Tween a motor's C0 to `to`, then back to `from`.
local function swingMotor(motor: Motor6D, from: CFrame, to: CFrame, downTime: number, upTime: number)
	local down = TweenService:Create(motor, TweenInfo.new(downTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { C0 = to })
	local up = TweenService:Create(motor, TweenInfo.new(upTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { C0 = from })
	down.Completed:Connect(function()
		up:Play()
	end)
	down:Play()
end

-- Plays a swing on whatever motors the current tool has.
function ToolController.PlaySwing()
	local tool = ToolController.GetEquippedTool()
	if not tool then
		return
	end

	local pivot = findMotor(tool, "Pivot")
	if pivot then
		local rest = pivot:GetAttribute("RestC0")
		local swung = pivot:GetAttribute("SwungC0")
		if typeof(rest) == "CFrame" and typeof(swung) == "CFrame" then
			swingMotor(pivot, rest, swung, 0.09, 0.16)
		end
	end

	local snip = findMotor(tool, "Snip")
	if snip then
		local openC0 = snip:GetAttribute("OpenC0")
		local closedC0 = snip:GetAttribute("ClosedC0")
		if typeof(openC0) == "CFrame" and typeof(closedC0) == "CFrame" then
			swingMotor(snip, openC0, closedC0, 0.07, 0.11)
		end
	end
end

function ToolController.Init() end

return ToolController
