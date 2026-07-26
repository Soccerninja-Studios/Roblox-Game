--!strict
-- DashController: press Q to burst a short distance in the direction you're moving.
--
-- Distance is expressed in CHARACTER HEIGHTS (GameConfig.DASH.distanceInHeights)
-- rather than a magic stud count, so it scales with the avatar. An R6 body is about
-- 5 studs tall, so the default 2 heights reads as a ~10-stud hop.
--
-- The burst is a short constant-velocity push from a LinearVelocity that only acts
-- on X and Z (MaxAxesForce leaves Y at zero). Gravity therefore keeps working
-- normally, so dashing mid-air neither launches you upward nor leaves you floating.
--
-- This lives on the client because a player's own character is client-owned:
-- applying the impulse locally is what makes the dash feel instant, and the motion
-- still replicates through the normal Roblox physics path. It's a movement flourish,
-- not an economy action, so there is nothing here for the server to validate.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Debris = game:GetService("Debris")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

local DashController = {}

local player = Players.LocalPlayer
local CFG = GameConfig.DASH

local lastDash = -math.huge

-- How tall this character actually is, so the dash scales with the avatar.
local function characterHeight(character: Model, humanoid: Humanoid): number
	local ok, size = pcall(function()
		return character:GetExtentsSize()
	end)
	if ok and size and size.Y > 0 then
		return size.Y
	end
	-- Fallback for an unusual rig: root height + hip height is a close approximation.
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	return ((root and root.Size.Y) or 2) + humanoid.HipHeight + 1
end

local function dash()
	local character = player.Character
	if not character then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not root or humanoid.Health <= 0 then
		return
	end
	-- WalkSpeed 0 means the player isn't in control right now (intro cutscene, etc).
	if humanoid.WalkSpeed <= 0 then
		return
	end

	local now = os.clock()
	if now - lastDash < CFG.cooldown then
		return
	end

	-- "The direction you're walking" = the live movement input. Standing still falls
	-- back to whichever way the character is currently facing.
	local dir = humanoid.MoveDirection
	if dir.Magnitude < 0.05 then
		dir = root.CFrame.LookVector
	end
	dir = Vector3.new(dir.X, 0, dir.Z)
	if dir.Magnitude < 0.05 then
		return
	end
	dir = dir.Unit

	lastDash = now

	local distance = characterHeight(character, humanoid) * CFG.distanceInHeights
	local speed = distance / CFG.duration

	local attachment = root:FindFirstChild("DashAttachment") :: Attachment?
	if not attachment then
		attachment = Instance.new("Attachment")
		attachment.Name = "DashAttachment"
		attachment.Parent = root
	end

	-- Clear any dash still in flight so spamming can't stack velocities.
	local previous = root:FindFirstChild("DashVelocity")
	if previous then
		previous:Destroy()
	end

	local lv = Instance.new("LinearVelocity")
	lv.Name = "DashVelocity"
	lv.Attachment0 = attachment
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	lv.VectorVelocity = dir * speed
	-- Horizontal axes only, so gravity is left completely untouched.
	lv.ForceLimitMode = Enum.ForceLimitMode.PerAxis
	lv.MaxAxesForce = Vector3.new(math.huge, 0, math.huge)
	lv.Parent = root

	Debris:AddItem(lv, CFG.duration)
end

function DashController.Init()
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		-- gameProcessed is true while the player is typing in a text box or the chat.
		if gameProcessed then
			return
		end
		if input.KeyCode == CFG.key then
			dash()
		end
	end)
end

function DashController.Start() end

return DashController
