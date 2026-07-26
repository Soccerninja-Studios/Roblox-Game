--!strict
-- NpcRig: keeps a stationary NPC standing perfectly still while still letting its
-- idle animation play.
--
-- THE TORSO BUG THIS FIXES
-- A static NPC is normally pinned by anchoring its HumanoidRootPart and leaving the
-- limbs unanchored. The limbs have to stay unanchored because an anchored part
-- cannot be moved by a Motor6D, so anchoring the whole body would freeze the idle
-- animation solid. The catch is that an unanchored, jointed body still has a live
-- Humanoid state machine bolted to it. With nothing but air under an anchored root,
-- that state machine drops the character into Freefall -> FallingDown -> Ragdoll,
-- and the Torso sags or slides out of the model. A missing RootJoint does the same
-- thing on its own: models exported and re-imported through Studio often lose it,
-- which leaves the Torso attached to nothing at all.
--
-- Stabilize() closes both holes: it rebuilds a missing RootJoint, shuts the state
-- machine off so nothing can re-pose the body, and pins only the root.

local NpcRig = {}

-- Classic R6 catalog idles, one per rig type.
local IDLE_R6 = "rbxassetid://180435571"
local IDLE_R15 = "rbxassetid://507766388"

-- The canonical R6 RootJoint matrices (HumanoidRootPart -> Torso).
local ROOT_C0 = CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0)
local ROOT_C1 = CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0)

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

-- The Humanoid inside a model, wherever it happens to sit in the hierarchy.
function NpcRig.FindHumanoid(model: Instance): Humanoid?
	for _, d in model:GetDescendants() do
		if d:IsA("Humanoid") then
			return d
		end
	end
	return nil
end

-- Pin an NPC in place without killing its animation.
-- `model` may be the character itself or any container holding it (e.g. a whole
-- market stall model with the shopkeeper somewhere inside).
function NpcRig.Stabilize(model: Instance): boolean
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

	-- 1. Make sure the Torso is actually attached to the root. Without this joint
	--    the anchored root holds nothing and the body drifts off on its own.
	if root and torso then
		local rootJoint: Motor6D? = nil
		for _, d in character:GetDescendants() do
			if d:IsA("Motor6D") and (d.Part1 == torso or d.Part0 == torso) and (d.Part0 == root or d.Part1 == root) then
				rootJoint = d
				break
			end
		end
		if not rootJoint then
			local m = Instance.new("Motor6D")
			m.Name = "RootJoint"
			m.Part0 = root
			m.Part1 = torso
			m.C0 = ROOT_C0
			m.C1 = ROOT_C1
			m.Parent = root
		end
		-- Re-seat the torso on the root so it starts the animation in the right spot
		-- even if it had already sagged before we got here.
		torso.CFrame = root.CFrame
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
	-- Physics state = "the body is posed by joints, leave it alone".
	pcall(function()
		humanoid:ChangeState(Enum.HumanoidStateType.Physics)
	end)
	pcall(function()
		(humanoid :: any).EvaluateStateMachine = false
	end)

	-- 3. Pin the root, free the limbs so the Motor6Ds can animate them, and make the
	--    body weightless + non-colliding so a passing player can't shove it.
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
function NpcRig.PlayIdle(model: Instance, animId: string?): boolean
	local humanoid = NpcRig.FindHumanoid(model)
	if not humanoid then
		return false
	end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	local anim = Instance.new("Animation")
	anim.AnimationId = animId
		or (if humanoid.RigType == Enum.HumanoidRigType.R15 then IDLE_R15 else IDLE_R6)

	local ok, track = pcall(function()
		return (animator :: Animator):LoadAnimation(anim)
	end)
	if not ok or not track then
		return false
	end

	local t = track :: AnimationTrack
	t.Looped = true
	t.Priority = Enum.AnimationPriority.Idle
	t:Play()
	return true
end

return NpcRig
