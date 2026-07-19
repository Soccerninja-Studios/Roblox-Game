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

-- Tween a motor's C0 to `to`, then back to `from`.
local function swingMotor(motor: Motor6D, from: CFrame, to: CFrame, downTime: number, upTime: number)
	local down = TweenService:Create(motor, TweenInfo.new(downTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { C0 = to })
	local up = TweenService:Create(motor, TweenInfo.new(upTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { C0 = from })
	down.Completed:Connect(function()
		up:Play()
	end)
	down:Play()
end

-- Every Motor6D carrying the given pair of CFrame pose attributes.
local function motorsWithPose(tool: Tool, fromAttr: string, toAttr: string): { Motor6D }
	local motors: { Motor6D } = {}
	for _, d in tool:GetDescendants() do
		if d:IsA("Motor6D") then
			local from = d:GetAttribute(fromAttr)
			local to = d:GetAttribute(toAttr)
			if typeof(from) == "CFrame" and typeof(to) == "CFrame" then
				table.insert(motors, d)
			end
		end
	end
	return motors
end

-- Plays a swing on whatever motors the current tool has. Both scissor halves of
-- the model shears carry Rest/Swung poses, so they animate together symmetrically.
function ToolController.PlaySwing()
	local tool = ToolController.GetEquippedTool()
	if not tool then
		return
	end

	for _, motor in motorsWithPose(tool, "RestC0", "SwungC0") do
		local rest = motor:GetAttribute("RestC0") :: CFrame
		local swung = motor:GetAttribute("SwungC0") :: CFrame
		swingMotor(motor, rest, swung, 0.09, 0.16)
	end

	-- Procedural fallback shears use a separate blade-close joint.
	for _, motor in motorsWithPose(tool, "OpenC0", "ClosedC0") do
		local openC0 = motor:GetAttribute("OpenC0") :: CFrame
		local closedC0 = motor:GetAttribute("ClosedC0") :: CFrame
		swingMotor(motor, openC0, closedC0, 0.07, 0.11)
	end
end

function ToolController.Init() end

return ToolController
