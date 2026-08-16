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

-- Small fudge added to raw sword reach so the "in range" flip lands right at the
-- edge of what the server's swing box can actually hit (the box catches enemies
-- whose body overlaps it, a touch past their center). Kept SMALL so the crosshair
-- never reads red while you're still out of hitting distance.
local IN_RANGE_PAD = 0.5
-- Half-width (studs) of the swing box footprint, matching the server's forgiving
-- min width plus a little for the enemy's body. An enemy off to the side beyond
-- this is not actually hittable, so the crosshair must not go red for it.
local LATERAL_HALF = 2.5

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

-- Forward reach (in studs) of the sword the character currently holds, plus the
-- small pad. Returns 0 when no sword is equipped so nothing ever reads "in range".
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

-- True when a world point sits inside the character's actual sword SWING BOX: in
-- front of them (never behind), within reach, and within the box's half-width.
-- This mirrors the server's forward hit volume, so the crosshair turning red means
-- a swing right now would connect -- no more red-but-can't-hit at the edges or
-- while turning around an enemy.
function CombatRange.IsInSwingBox(char: Model?, worldPos: Vector3): boolean
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
	local rootPart = root :: BasePart
	local origin = rootPart.Position
	-- Radial specials do not use the ordinary forward box. Mirror the server's
	-- true 360-degree radius so lock-on and shift-lock feedback stay accurate.
	local held = char:FindFirstChildOfClass("Tool")
	if held and held:GetAttribute("Sword") then
		local def = StatCalculator.GetSwordDef(held:GetAttribute("SwordKey"))
		if def and def.special == "whirlwind" then
			local delta = worldPos - origin
			return Vector3.new(delta.X, 0, delta.Z).Magnitude <= (def.specialRadius or reach)
		end
	end
	local look = rootPart.CFrame.LookVector
	local flatLook = Vector3.new(look.X, 0, look.Z)
	if flatLook.Magnitude < 0.001 then
		return false
	end
	flatLook = flatLook.Unit
	local to = worldPos - origin
	local flatTo = Vector3.new(to.X, 0, to.Z)
	-- How far ahead (along facing) the point is; must be in front and within reach.
	local forward = flatTo:Dot(flatLook)
	if forward <= 0 or forward > reach then
		return false
	end
	-- Sideways distance from the swing line; must be within the box half-width.
	local lateral = (flatTo - flatLook * forward).Magnitude
	return lateral <= LATERAL_HALF
end

-- True when any alive monster is inside the swing box (turns the shift-lock
-- crosshair red while free-aiming).
function CombatRange.AnyEnemyInSwingRange(char: Model?): boolean
	for _, m in CombatRange.Monsters() do
		local mroot = m.PrimaryPart
		if mroot and CombatRange.IsInSwingBox(char, mroot.Position) then
			return true
		end
	end
	return false
end

return CombatRange
