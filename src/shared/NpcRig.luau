--!strict
-- NpcRig: keeps a stationary NPC standing still while letting its idle animation
-- drive the WHOLE body.
--
-- ---------------------------------------------------------------------------
-- WHY THE FARMER BROKE (read this before touching anything below)
-- ---------------------------------------------------------------------------
-- The Gardener asset's NPC (the model is called "Farmer") is a hand-built R6 rig at
-- 0.79 scale, and it is wired in a NON-STANDARD way:
--
--   * Every limb Motor6D hangs off HumanoidRootPart, not off the Torso.
--   * The joints are named after the PART they move ("Right Arm", "Head",
--     "Left Leg") instead of the standard R6 joint names ("Right Shoulder",
--     "Neck", "Left Hip").
--   * The Torso has NO joint at all. Nothing connects it to the rig.
--
-- Those three facts explain both bugs we chased:
--
--   Bug 1 - "the torso falls out of place". The Torso was an unanchored part
--   attached to nothing, so gravity simply took it.
--
--   Bug 2 - "only his chest moves". Roblox animations address joints BY NAME. A
--   stock R6 animation drives RootJoint / Neck / Right Shoulder / Left Shoulder /
--   Right Hip / Left Hip. This rig has none of those names, so a stock animation
--   can move nothing. The first version of this module "fixed" the falling torso by
--   adding a Motor6D named RootJoint - which handed the animation exactly one joint
--   it recognised, so the torso became the only thing that moved.
--
-- The fix is therefore the opposite of what you would guess: do NOT rename these
-- joints to the standard set. The asset ships its own animations (Animations/Idle,
-- Animations/Attack) that were authored against these custom joint names, so they
-- animate the entire body correctly. Renaming the joints would break them.
--
-- So we:
--   1. Hold the Torso with a plain WELD, never a Motor6D named RootJoint. A weld
--      cannot be targeted by an animation track, so the torso stays put instead of
--      becoming the only moving part.
--   2. Play the rig's OWN bundled idle when it has one, and fall back to the stock
--      catalog idle only for rigs that use standard joint names (e.g. Sprigman,
--      who is built in code and is correctly named).
--
-- Rigs that are already wired correctly are left completely alone.

local NpcRig = {}

-- Stock catalog idles. Only usable by rigs with STANDARD R6/R15 joint names.
local IDLE_R6 = "rbxassetid://180435571"
local IDLE_R15 = "rbxassetid://507766388"

-- Every state that can move, drop, or re-pose a body we want held still.
local DISABLED_STATES = {
	"Freefall",
	"FallingDown",
	"Ragdoll",
	"GettingUp",
	"Landed",
	"Running",
	"RunningNoPhysics",
	"Climbing",
	"Jumping",
	"Swimming",
	"PlatformStanding",
	"Flying",
	"Seated",
	"StrafingNoPhysics",
	"Dead",
}

-- Free-model "package" scripts. These are the same family of scripts that threw
-- `lacking capability LoadUnownedAsset` from Plains Assets earlier in the project:
-- they try to require assets the place does not own. The Gardener asset ships
-- eleven of them. They are pure decoration helpers, so we delete them on spawn.
local JUNK_SCRIPT_NAMES = {
	Package = true,
	TextureConfiguration = true,
	PoseTexture = true,
	LightConfig = true,
	EasyConfiguration = true,
	Type = true,
}

-- The Humanoid inside a model, wherever it sits in the hierarchy.
function NpcRig.FindHumanoid(model: Instance): Humanoid?
	for _, d in model:GetDescendants() do
		if d:IsA("Humanoid") then
			return d
		end
	end
	return nil
end

-- Delete embedded free-model scripts and Studio animation-editor leftovers.
-- Returns how many instances were removed. Safe to call on any model.
function NpcRig.StripJunk(model: Instance): number
	local removed = 0
	for _, d in model:GetDescendants() do
		local kill = false
		if d:IsA("LuaSourceContainer") and JUNK_SCRIPT_NAMES[d.Name] then
			-- A junk script's config modules live inside it, so removing the parent
			-- takes the children with it.
			kill = true
		elseif d:IsA("Model") and d.Name == "AnimSaves" then
			-- Animation editor save data. Pure weight, never used at runtime.
			kill = true
		elseif d:IsA("KeyframeSequence") then
			kill = true
		end
		if kill then
			removed += 1
			pcall(function()
				d:Destroy()
			end)
		end
	end
	return removed
end

-- Does this rig use the standard R6/R15 joint names? If so a stock catalog
-- animation will drive it; if not, only its own bundled animations will.
function NpcRig.HasStandardJointNames(character: Model): boolean
	for _, d in character:GetDescendants() do
		if d:IsA("Motor6D") then
			local n = d.Name
			if n == "Neck" or n == "Right Shoulder" or n == "Left Shoulder" or n == "Right Hip" or n == "Left Hip" then
				return true
			end
		end
	end
	return false
end

-- Find an Animation the asset shipped with, e.g. Animations/Idle.
-- Returns the animation id, or nil when the rig has none.
function NpcRig.FindBundledAnim(model: Instance, animName: string): string?
	for _, d in model:GetDescendants() do
		if d:IsA("Animation") and d.Name:lower() == animName:lower() then
			local id = d.AnimationId
			if id and id ~= "" then
				return id
			end
		end
	end
	return nil
end

-- Is the Torso already joined to the rig by anything at all?
local function torsoIsAttached(character: Model, root: BasePart, torso: BasePart): boolean
	for _, d in character:GetDescendants() do
		if d:IsA("Motor6D") or d:IsA("Weld") then
			if (d.Part0 == torso and d.Part1 ~= nil) or (d.Part1 == torso and d.Part0 ~= nil) then
				return true
			end
		elseif d:IsA("WeldConstraint") then
			if d.Part0 == torso or d.Part1 == torso then
				return true
			end
		end
	end
	return false
end

-- Pin an NPC in place without killing its animation.
-- `model` may be the character itself or any container holding it (e.g. the whole
-- Gardener stall, with the Farmer somewhere inside).
function NpcRig.Stabilize(model: Instance): boolean
	NpcRig.StripJunk(model)

	local humanoid = NpcRig.FindHumanoid(model)
	if not humanoid then
		return false
	end
	local character = humanoid.Parent
	if not character or not character:IsA("Model") then
		return false
	end

	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local torso = (character:FindFirstChild("Torso") or character:FindFirstChild("UpperTorso")) :: BasePart?

	-- 1. Attach an orphaned Torso with a WELD.
	--
	--    A weld is deliberate: welds carry no animation channel, so no animation
	--    track can ever grab the torso and make it the only thing that moves. If the
	--    torso is already jointed (a correctly built rig like Sprigman), do nothing.
	if root and torso and not torsoIsAttached(character, root, torso) then
		torso.CFrame = root.CFrame
		local weld = Instance.new("Weld")
		weld.Name = "TorsoWeld"
		weld.Part0 = root
		weld.Part1 = torso
		weld.C0 = CFrame.new()
		weld.C1 = CFrame.new()
		weld.Parent = root
	end

	-- 2. Silence the state machine so nothing tries to walk, fall, or ragdoll.
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.AutoRotate = false
	humanoid.BreakJointsOnDeath = false
	pcall(function()
		humanoid.RequiresNeck = false
	end)
	for _, name in DISABLED_STATES do
		pcall(function()
			humanoid:SetStateEnabled((Enum.HumanoidStateType :: any)[name], false)
		end)
	end
	-- Physics state = "this body is posed by its joints, leave it alone".
	pcall(function()
		humanoid:ChangeState(Enum.HumanoidStateType.Physics)
	end)
	pcall(function()
		(humanoid :: any).EvaluateStateMachine = false
	end)

	-- 3. Pin the root, free the limbs so their Motor6Ds can animate them, and make
	--    the body weightless + non-colliding so a passing player cannot shove it.
	for _, p in character:GetDescendants() do
		if p:IsA("BasePart") then
			if p == root then
				p.Anchored = true
			else
				p.Anchored = false
				p.Massless = true
			end
			p.CanCollide = false
		end
	end

	if root then
		character.PrimaryPart = root
	end

	return true
end

-- Loop a gentle idle so the NPC breathes instead of standing like a mannequin.
--
-- Animation choice matters here. A rig with custom joint names can ONLY be driven
-- by animations authored against that rig, so we always prefer one the asset
-- shipped with. The stock catalog idle is a fallback for standard-named rigs.
function NpcRig.PlayIdle(model: Instance, animId: string?): boolean
	local humanoid = NpcRig.FindHumanoid(model)
	if not humanoid then
		return false
	end
	local character = humanoid.Parent
	if not character or not character:IsA("Model") then
		return false
	end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	-- Preference order:
	--   1. an idle the asset shipped with (the only thing a custom rig understands)
	--   2. the id the caller asked for
	--   3. the stock catalog idle, but ONLY if the joints are standard-named
	local chosen = NpcRig.FindBundledAnim(model, "Idle") or animId
	if not chosen and NpcRig.HasStandardJointNames(character) then
		chosen = if humanoid.RigType == Enum.HumanoidRigType.R15 then IDLE_R15 else IDLE_R6
	end
	if not chosen then
		-- A custom rig with no bundled idle. Playing a stock animation here would do
		-- nothing at best, or twitch a single joint at worst, so stand still instead.
		warn(`[NpcRig] {character.Name} has custom joint names and no bundled idle - leaving it static.`)
		return false
	end

	local anim = Instance.new("Animation")
	anim.AnimationId = chosen

	local ok, track = pcall(function()
		return (animator :: Animator):LoadAnimation(anim)
	end)
	if not ok or not track then
		warn(`[NpcRig] could not load idle {chosen} for {character.Name}`)
		return false
	end

	local t = track :: AnimationTrack
	t.Looped = true
	t.Priority = Enum.AnimationPriority.Idle
	t:Play()
	return true
end

return NpcRig
