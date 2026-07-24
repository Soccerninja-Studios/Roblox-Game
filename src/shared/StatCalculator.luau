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

-- Cut power vs a SPECIFIC grass type. Specialist tools multiply their base power
-- against their favored grass (favoredMul) and are weaker against everything else
-- (offMul); the ultimate tool (favored == "all") applies favoredMul to every type.
-- Balanced tools (favored == nil) hit every type at their base power. This is what
-- makes a specialist shine in its zone but struggle outside it.
function StatCalculator.GetCutPowerForGrass(toolTier: number, grassType: string, skills: { [string]: number }): number
	local tool = GameConfig.TOOL_TIERS[toolTier] or GameConfig.TOOL_TIERS[1]
	local sharp = skillLevel(skills, "SharpBlades")
	local skillMul = 1 + sharp * SKILLS.SharpBlades.effectPerLevel

	local typeMul = 1
	local favored = tool.favored
	if favored == "all" then
		typeMul = tool.favoredMul or 1.6
	elseif favored ~= nil then
		typeMul = if favored == grassType then (tool.favoredMul or 2.6) else (tool.offMul or 0.7)
	end

	return math.max(1, tool.bladesPerSwing * skillMul * typeMul)
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

-- Zone gating: a tool can cut its own zone's grass and every EASIER zone before
-- it, but not tougher zones. Grass zones in difficulty order:
--   1 Meadow -> 2 Wild -> 3 Moss -> 4 Thick -> 5 Ironweed
-- Tools open a new zone every two tiers, so tiers 1-2 reach zone 1, 3-4 reach
-- zone 2, ... 9-10 reach zone 5, and the ultimate (tier 11) reaches everything.
-- This lines up each specialist tool with the zone it excels at.
local GRASS_ZONE_INDEX: { [string]: number } = {
	Meadow = 1,
	Wild = 2,
	Moss = 3,
	Thick = 4,
	Ironweed = 5,
}

function StatCalculator.GetToolMaxZone(toolTier: number): number
	return math.min(5, math.ceil(toolTier / 2))
end

function StatCalculator.CanCutGrass(toolTier: number, grassType: string): boolean
	local zoneIndex = GRASS_ZONE_INDEX[grassType] or 1
	return zoneIndex <= StatCalculator.GetToolMaxZone(toolTier)
end

return StatCalculator
