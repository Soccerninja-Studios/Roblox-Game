--!strict
-- CombatRange: shared helpers for "is an enemy within sword range" checks, so the
-- shift-lock crosshair and the lock-on crosshair use ONE definition of reach and
-- in-range (no drift between the two). Requires nothing from the controllers, so
-- either client controller can require it without a dependency cycle.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local StatCalculator = require(Shared:WaitForChild("StatCalculator"))

local CombatRange = {}

-- Small fudge added to raw sword reach so the "in range" flip feels fair rather
-- than pixel-perfect. Shared by both crosshairs.
local IN_RANGE_PAD = 3
-- Enemies roughly ahead of the character count; behind-the-back ones do not.
local FRONT_DOT = 0.2

local function monsterFolder(): Folder?
	local f = Workspace:FindFirstChild("Monsters")
	if f and f:IsA("Folder") then
		return f
	end
	return nil
end

function CombatRange.IsAliveMonster(model: Instance): boolean
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

-- Reach (in studs) of the sword the character currently holds, plus the pad.
-- Returns 0 when no sword is equipped so nothing ever reads as "in range".
function CombatRange.GetReach(char: Model?): number
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
	return StatCalculator.GetSwordReach(held:GetAttribute("SwordKey")) + IN_RANGE_PAD
end

-- All alive monsters currently in the world.
function CombatRange.Monsters(): { Model }
	local list: { Model } = {}
	local folder = monsterFolder()
	if not folder then
		return list
	end
	for _, m in folder:GetChildren() do
		if CombatRange.IsAliveMonster(m) then
			table.insert(list, m :: Model)
		end
	end
	return list
end

-- True when a given world point is within the character's current sword reach.
function CombatRange.IsPointInReach(char: Model?, worldPos: Vector3): boolean
	if not char then
		return false
	end
	local root = char:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return false
	end
	local reach = CombatRange.GetReach(char)
	if reach <= 0 then
		return false
	end
	return (worldPos - (root :: BasePart).Position).Magnitude <= reach
end

-- True when any alive monster is within sword reach AND roughly in front of the
-- character (used to turn the shift-lock crosshair red while free-aiming).
function CombatRange.AnyEnemyInSwingRange(char: Model?): boolean
	if not char then
		return false
	end
	local root = char:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return false
	end
	local reach = CombatRange.GetReach(char)
	if reach <= 0 then
		return false
	end
	local origin = (root :: BasePart).Position
	local look = (root :: BasePart).CFrame.LookVector
	local flatLook = Vector3.new(look.X, 0, look.Z)
	if flatLook.Magnitude > 0.001 then
		flatLook = flatLook.Unit
	else
		flatLook = look
	end
	for _, m in CombatRange.Monsters() do
		local mroot = m.PrimaryPart :: BasePart
		local to = mroot.Position - origin
		if to.Magnitude <= reach then
			local flat = Vector3.new(to.X, 0, to.Z)
			if flat.Magnitude < 0.001 then
				return true
			end
			if flat.Unit:Dot(flatLook) > FRONT_DOT then
				return true
			end
		end
	end
	return false
end

return CombatRange
