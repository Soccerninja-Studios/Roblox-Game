--!strict
-- StatCalculator: pure functions that turn profile data into gameplay stats.
-- Shared so server (authoritative) and client (display/prediction) always agree.

local GameConfig = require(script.Parent.GameConfig)

local SKILLS: { [string]: any } = GameConfig.SKILLS

local StatCalculator = {}

local function skillLevel(skills: { [string]: number }, name: string): number
	return (skills and skills[name]) or 0
end

-- Cut power of one swing: how much grass "health" a swing removes before armor.
-- Scales with the tool tier and the Sharp Blades skill.
function StatCalculator.GetCutPower(toolTier: number, skills: { [string]: number }): number
	local tool = GameConfig.TOOL_TIERS[toolTier] or GameConfig.TOOL_TIERS[1]
	local sharp = skillLevel(skills, "SharpBlades")
	local multiplier = 1 + sharp * SKILLS.SharpBlades.effectPerLevel
	return math.max(1, tool.bladesPerSwing * multiplier)
end

-- Seconds between swings, reduced by Quick Hands
function StatCalculator.GetSwingCooldown(skills: { [string]: number }): number
	local quick = skillLevel(skills, "QuickHands")
	return GameConfig.BASE_SWING_COOLDOWN / (1 + quick * SKILLS.QuickHands.effectPerLevel)
end

-- Studs within which dropped clippings are vacuumed up. Grown by Clipping Magnet.
function StatCalculator.GetCollectRange(skills: { [string]: number }): number
	local magnet = skillLevel(skills, "ClippingMagnet")
	return GameConfig.BASE_COLLECT_RANGE * (1 + magnet * SKILLS.ClippingMagnet.effectPerLevel)
end

-- Clipping value multiplier, raised by Greener Thumb.
function StatCalculator.GetClippingMultiplier(skills: { [string]: number }): number
	local thumb = skillLevel(skills, "GreenerThumb")
	return 1 + thumb * SKILLS.GreenerThumb.effectPerLevel
end

-- Clipping cost of the next level of a skill (exponential growth)
function StatCalculator.GetSkillCost(skillName: string, currentLevel: number): number
	local skill = SKILLS[skillName]
	return math.floor(skill.baseCost * skill.costGrowth ^ currentLevel + 0.5)
end

return StatCalculator
