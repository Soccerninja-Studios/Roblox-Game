--!strict
-- QuestGiverService: spawns "Sprig the Quartermaster", the quest-board NPC that
-- stands at the front-center of the house (between the shop and the gardener).
-- Sprig is a real R6 character (Humanoid + jointed body) that plays a looping
-- idle animation so he breathes and sways in place, not just a static prop. He
-- keeps a glowing walk-in pad, a floating "!" marker, and a ProximityPrompt named
-- "QuestPrompt" that the client hooks to open the quest board.

local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

local QuestGiverService = {}

-- Look --------------------------------------------------------------------
local SKIN = Color3.fromRGB(232, 190, 150)
local TUNIC = Color3.fromRGB(86, 150, 78) -- quartermaster green
local PANTS = Color3.fromRGB(120, 84, 52) -- brown trousers
local ZONE_FILL = Color3.fromRGB(250, 208, 96) -- warm gold, distinct from shop/gardener
local ZONE_EDGE = Color3.fromRGB(214, 164, 58)
local ACCENT = Color3.fromRGB(255, 226, 150)

-- The classic R6 idle animation (same one the Gardener uses) so Sprig sways.
local IDLE_ANIM_ID = "rbxassetid://180435571"

local function makePart(name: string, size: Vector3, color: Color3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Anchored = false
	p.CanCollide = false
	return p
end

-- Build one R6 Motor6D joint (part0 is the parent that owns the joint).
local function joint(name: string, part0: BasePart, part1: BasePart, c0: CFrame, c1: CFrame)
	local m = Instance.new("Motor6D")
	m.Name = name
	m.Part0 = part0
	m.Part1 = part1
	m.C0 = c0
	m.C1 = c1
	m.Parent = part0
end

-- Ground pulse so the walk-in pad reads as interactive.
local function pulse(zone: BasePart)
	task.spawn(function()
		while zone.Parent do
			TweenService:Create(zone, TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { Transparency = 0.72 }):Play()
			task.wait(1.1)
			TweenService:Create(zone, TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { Transparency = 0.42 }):Play()
			task.wait(1.1)
		end
	end)
end

local function buildSprig(): Model
	local model = Instance.new("Model")
	model.Name = "QuestGiver"

	-- Where the NPC stands. QUEST_GIVER_POSITION is the ground point; an R6
	-- character's HumanoidRootPart sits ~3 studs above its feet, so lift by 3.
	-- Rotate 180 degrees so Sprig faces out toward players walking up.
	local base = CFrame.new(GameConfig.QUEST_GIVER_POSITION + Vector3.new(0, 3, 0)) * CFrame.Angles(0, math.rad(180), 0)

	-- Core parts (names MUST match the R6 rig so the Humanoid + animations work).
	local rootPart = makePart("HumanoidRootPart", Vector3.new(2, 2, 1), SKIN)
	rootPart.Transparency = 1
	rootPart.Anchored = true -- pin him in place; joints keep the body attached + animated
	rootPart.CFrame = base
	rootPart.Parent = model

	local torso = makePart("Torso", Vector3.new(2, 2, 1), TUNIC)
	torso.CFrame = base
	torso.Parent = model

	local head = makePart("Head", Vector3.new(2, 1, 1), SKIN)
	head.CFrame = base * CFrame.new(0, 1.5, 0)
	head.Parent = model
	local headMesh = Instance.new("SpecialMesh")
	headMesh.MeshType = Enum.MeshType.Head
	headMesh.Scale = Vector3.new(1.25, 1.25, 1.25)
	headMesh.Parent = head
	local face = Instance.new("Decal")
	face.Name = "face"
	face.Texture = "rbxasset://textures/face.png"
	face.Face = Enum.NormalId.Front
	face.Parent = head

	local rightArm = makePart("Right Arm", Vector3.new(1, 2, 1), SKIN)
	rightArm.CFrame = base * CFrame.new(1.5, 0, 0)
	rightArm.Parent = model

	local leftArm = makePart("Left Arm", Vector3.new(1, 2, 1), SKIN)
	leftArm.CFrame = base * CFrame.new(-1.5, 0, 0)
	leftArm.Parent = model

	local rightLeg = makePart("Right Leg", Vector3.new(1, 2, 1), PANTS)
	rightLeg.CFrame = base * CFrame.new(0.5, -2, 0)
	rightLeg.Parent = model

	local leftLeg = makePart("Left Leg", Vector3.new(1, 2, 1), PANTS)
	leftLeg.CFrame = base * CFrame.new(-0.5, -2, 0)
	leftLeg.Parent = model

	-- Standard R6 Motor6D layout (canonical C0/C1 matrices).
	joint("RootJoint", rootPart, torso,
		CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0),
		CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0))
	joint("Neck", torso, head,
		CFrame.new(0, 1, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0),
		CFrame.new(0, -0.5, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0))
	joint("Right Shoulder", torso, rightArm,
		CFrame.new(1, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0),
		CFrame.new(-0.5, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0))
	joint("Left Shoulder", torso, leftArm,
		CFrame.new(-1, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0),
		CFrame.new(0.5, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0))
	joint("Right Hip", torso, rightLeg,
		CFrame.new(1, -1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0),
		CFrame.new(0.5, 1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0))
	joint("Left Hip", torso, leftLeg,
		CFrame.new(-1, -1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0),
		CFrame.new(-0.5, 1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0))

	-- Humanoid (defaults to R6 with these part names). Show his name overhead.
	local humanoid = Instance.new("Humanoid")
	humanoid.DisplayName = "Sprig the Quartermaster"
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.MaxHealth = 100
	humanoid.Health = 100
	humanoid.NameOcclusion = Enum.NameOcclusion.NoOcclusion
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.Parent = model

	local animator = Instance.new("Animator")
	animator.Parent = humanoid

	model.PrimaryPart = rootPart

	-- A green cap so he reads as a character, welded to the head.
	local cap = makePart("Cap", Vector3.new(1.4, 0.5, 1.4), TUNIC)
	cap.CFrame = head.CFrame * CFrame.new(0, 0.7, 0)
	cap.Parent = model
	local capWeld = Instance.new("WeldConstraint")
	capWeld.Part0 = head
	capWeld.Part1 = cap
	capWeld.Parent = cap

	-- Floating "!" quest marker above his head.
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Marker"
	billboard.Size = UDim2.new(0, 60, 0, 90)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
	billboard.AlwaysOnTop = true
	billboard.Adornee = head
	billboard.Parent = head

	local bang = Instance.new("TextLabel")
	bang.BackgroundTransparency = 1
	bang.Size = UDim2.new(1, 0, 1, 0)
	bang.Font = Enum.Font.FredokaOne
	bang.Text = "!"
	bang.TextColor3 = ACCENT
	bang.TextStrokeTransparency = 0.3
	bang.TextScaled = true
	bang.Parent = billboard

	-- Glowing walk-in pad + ring on the ground.
	local zone = makePart("QuestZone", Vector3.new(GameConfig.QUEST_GIVER_ZONE_RADIUS * 2, 0.2, GameConfig.QUEST_GIVER_ZONE_RADIUS * 2), ZONE_FILL)
	zone.Anchored = true
	zone.Material = Enum.Material.Neon
	zone.Shape = Enum.PartType.Cylinder
	zone.Transparency = 0.5
	-- Cylinder parts lie on their side; rotate so the flat face points up.
	zone.CFrame = CFrame.new(GameConfig.QUEST_GIVER_POSITION + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.rad(90))
	zone.Parent = model

	local ring = makePart("QuestZoneRing", Vector3.new(GameConfig.QUEST_GIVER_ZONE_RADIUS * 2 + 1.2, 0.3, GameConfig.QUEST_GIVER_ZONE_RADIUS * 2 + 1.2), ZONE_EDGE)
	ring.Anchored = true
	ring.Material = Enum.Material.Neon
	ring.Shape = Enum.PartType.Cylinder
	ring.Transparency = 0.25
	ring.CFrame = CFrame.new(GameConfig.QUEST_GIVER_POSITION + Vector3.new(0, 0.05, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = model

	-- Proximity prompt the client hooks to open the quest board.
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "QuestPrompt"
	prompt.ActionText = "Quests"
	prompt.ObjectText = "Sprig the Quartermaster"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = GameConfig.QUEST_GIVER_ZONE_RADIUS + 4
	prompt.Parent = rootPart

	pulse(zone)
	return model
end

local function playIdle(model: Model)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return
	end
	local anim = Instance.new("Animation")
	anim.AnimationId = IDLE_ANIM_ID
	local ok, track = pcall(function()
		return animator:LoadAnimation(anim)
	end)
	if ok and track then
		track.Looped = true
		track.Priority = Enum.AnimationPriority.Idle
		track:Play()
	end
end

local function spawnQuestGiver()
	local existing = Workspace:FindFirstChild("QuestGiver")
	if existing then
		existing:Destroy()
	end
	local model = buildSprig()
	model.Parent = Workspace
	playIdle(model)
end

function QuestGiverService.Init(_services: any) end

function QuestGiverService.Start()
	spawnQuestGiver()
	print("[QuestGiverService] Sprig the Quartermaster is ready.")
end

return QuestGiverService
