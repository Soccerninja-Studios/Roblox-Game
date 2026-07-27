--!strict
-- ToolService: builds a detailed, held cutting tool for each tier and gives it to
-- the player. The tool is a real Roblox Tool (equip/unequip); mowing requires it.
--
-- Every tool is built around an invisible `BladeRoot` that hangs off the Handle via
-- a Motor6D named "Pivot" (the swing arc). Shears additionally have a Motor6D named
-- "Snip" on the moving blade. ToolController animates whichever it finds.

local Players = game:GetService("Players")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

local ToolService = {}

local function c3(rgb: { number }): Color3
	return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

type PartProps = {
	name: string?,
	size: Vector3,
	color: Color3,
	material: Enum.Material?,
	shape: Enum.PartType?,
	reflectance: number?,
	transparency: number?,
	wedge: boolean?,
}

local function makePart(props: PartProps): BasePart
	local p: BasePart = if props.wedge then Instance.new("WedgePart") else Instance.new("Part")
	p.Name = props.name or "Part"
	p.Size = props.size
	p.Color = props.color
	p.Material = props.material or Enum.Material.SmoothPlastic
	p.Reflectance = props.reflectance or 0
	p.Transparency = props.transparency or 0
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = false -- so the tool never blocks the mouse ray to the grass
	p.CanTouch = false
	p.Massless = true
	if not props.wedge and p:IsA("Part") then
		(p :: Part).Shape = props.shape or Enum.PartType.Block
	end
	if not props.wedge then
		local smooth = Instance.new("SpecialMesh")
		smooth.MeshType = Enum.MeshType.Brick
		-- (kept as Brick; corner rounding via smaller detail parts instead)
		smooth:Destroy()
	end
	return p
end

-- Attach `sub` to `parent` with a Motor6D so the whole assembly moves together.
local function attach(tool: Tool, parent: BasePart, sub: BasePart, c0: CFrame, motorName: string?): Motor6D
	sub.Parent = tool
	local motor = Instance.new("Motor6D")
	motor.Name = motorName or ("Weld_" .. sub.Name)
	motor.Part0 = parent
	motor.Part1 = sub
	motor.C0 = c0
	motor.Parent = parent
	return motor
end

local function newTool(def: any, tier: number): (Tool, BasePart, BasePart)
	local tool = Instance.new("Tool")
	tool.Name = "Shears"
	tool.RequiresHandle = true
	tool.CanBeDropped = false
	tool.ToolTip = def.name
	tool.GripPos = Vector3.new(0, 0, 0)
	tool.GripForward = Vector3.new(0, 0, -1)
	tool.GripUp = Vector3.new(0, 1, 0)
	tool.GripRight = Vector3.new(1, 0, 0)
	tool:SetAttribute("Shears", true)
	tool:SetAttribute("ToolTier", tier)

	local scale = def.toolScale or 1

	local handle = makePart({
		name = "Handle",
		size = Vector3.new(0.35, 3.2 * scale, 0.35),
		color = c3(def.handleColor),
		material = Enum.Material.Wood,
		shape = Enum.PartType.Cylinder,
	})
	-- Cylinder's length runs along X; rotate so the grip stands upright along Y.
	handle.CFrame = CFrame.Angles(0, 0, math.rad(90))
	handle.Parent = tool

	local bladeRoot = makePart({
		name = "BladeRoot",
		size = Vector3.new(0.2, 0.2, 0.2),
		color = Color3.new(1, 1, 1),
		transparency = 1,
	})
	-- Rest pose: assembly sits above the grip, angled slightly forward.
	local restC0 = CFrame.new(0, 1.6 * scale, 0)
	local pivot = attach(tool, handle, bladeRoot, restC0, "Pivot")
	pivot:SetAttribute("RestC0", restC0)
	pivot:SetAttribute("SwungC0", restC0 * CFrame.Angles(math.rad(-58), 0, 0))

	return tool, handle, bladeRoot
end

-- ---- Individual tool styles -------------------------------------------------

local function buildShears(def: any, tier: number): Tool
	local tool, _handle, root = newTool(def, tier)
	local scale = def.toolScale or 1
	local bladeColor = c3(def.bladeColor)
	local mat = Enum.Material[def.bladeMaterial] or Enum.Material.Metal

	-- Pivot bolt joining the two blades
	local bolt = makePart({
		name = "Bolt",
		size = Vector3.new(0.4, 0.4, 0.4),
		color = Color3.fromRGB(60, 60, 66),
		material = Enum.Material.Metal,
		shape = Enum.PartType.Cylinder,
		reflectance = 0.2,
	})
	attach(tool, root, bolt, CFrame.Angles(0, 0, math.rad(90)))

	-- Fixed lower blade
	local fixed = makePart({
		name = "FixedBlade",
		size = Vector3.new(0.12, 0.55, 2.6 * scale),
		color = bladeColor,
		material = mat,
		reflectance = 0.15,
	})
	attach(tool, root, fixed, CFrame.new(0, -0.12, -1.2 * scale) * CFrame.Angles(0, 0, math.rad(6)))
	local fixedTip = makePart({
		name = "FixedTip",
		size = Vector3.new(0.12, 0.55, 0.7 * scale),
		color = bladeColor,
		material = mat,
		reflectance = 0.15,
		wedge = true,
	})
	attach(tool, root, fixedTip, CFrame.new(0, -0.12, -2.55 * scale) * CFrame.Angles(0, math.rad(90), math.rad(6)))

	-- Moving upper blade on the "Snip" motor
	local moving = makePart({
		name = "MovingBlade",
		size = Vector3.new(0.12, 0.55, 2.6 * scale),
		color = bladeColor,
		material = mat,
		reflectance = 0.15,
	})
	local openC0 = CFrame.new(0, 0.12, -1.2 * scale) * CFrame.Angles(math.rad(16), 0, math.rad(-6))
	local closedC0 = CFrame.new(0, 0.12, -1.2 * scale) * CFrame.Angles(0, 0, math.rad(-6))
	local snip = attach(tool, root, moving, openC0, "Snip")
	snip:SetAttribute("OpenC0", openC0)
	snip:SetAttribute("ClosedC0", closedC0)

	-- Two grip loops for the handles
	for i, side in { -1, 1 } do
		local loop = makePart({
			name = "Grip" .. i,
			size = Vector3.new(0.16, 1.0 * scale, 0.7),
			color = c3(def.handleColor),
			material = Enum.Material.Wood,
		})
		attach(tool, root, loop, CFrame.new(side * 0.18, -1.9 * scale, 0.4))
	end

	return tool
end

local function buildCurvedBlade(tool: Tool, root: BasePart, def: any, segments: number, radius: number, arc: number, thickness: number, forward: number)
	local bladeColor = c3(def.bladeColor)
	local mat = Enum.Material[def.bladeMaterial] or Enum.Material.Metal
	-- Approximate a curved blade with a fan of short segments along an arc.
	for i = 0, segments - 1 do
		local t = i / (segments - 1)
		local angle = -arc / 2 + arc * t
		local x = math.sin(angle) * radius
		local z = -math.cos(angle) * radius + radius
		local seg = makePart({
			name = "Blade" .. i,
			size = Vector3.new(0.12, 0.5 - t * 0.28, (arc * radius / segments) + 0.12),
			color = bladeColor,
			material = mat,
			reflectance = 0.2,
		})
		attach(tool, root, seg, CFrame.new(x, 0, forward - z) * CFrame.Angles(0, angle, 0))
	end
end

local function buildSickle(def: any, tier: number): Tool
	local tool, _handle, root = newTool(def, tier)
	local scale = def.toolScale or 1
	-- wooden neck
	local neck = makePart({
		name = "Neck",
		size = Vector3.new(0.28, 0.28, 1.4 * scale),
		color = c3(def.handleColor),
		material = Enum.Material.Wood,
	})
	attach(tool, root, neck, CFrame.new(0, 0, -0.7 * scale))
	buildCurvedBlade(tool, root, def, 8, 1.9 * scale, math.rad(150), 0.12, -1.3 * scale)
	return tool
end

local function buildScythe(def: any, tier: number): Tool
	local tool, handle, root = newTool(def, tier)
	local scale = def.toolScale or 1
	-- extend the snath (long pole) downward past the grip
	local snath = makePart({
		name = "Snath",
		size = Vector3.new(0.3, 3.0 * scale, 0.3),
		color = c3(def.handleColor),
		material = Enum.Material.Wood,
		shape = Enum.PartType.Cylinder,
	})
	attach(tool, root, snath, CFrame.new(0, -1.4 * scale, 0) * CFrame.Angles(0, 0, math.rad(90)))
	-- horizontal grip nub
	local nub = makePart({
		name = "Nub",
		size = Vector3.new(0.9, 0.22, 0.22),
		color = c3(def.handleColor),
		material = Enum.Material.Wood,
	})
	attach(tool, root, nub, CFrame.new(0.4, -0.4 * scale, 0))
	buildCurvedBlade(tool, root, def, 10, 2.8 * scale, math.rad(120), 0.14, -0.2 * scale)
	return tool
end

-- Tier 1 uses the hand-authored Shears model (synced via Rojo at
-- ReplicatedStorage.Assets.Shears). We clone it, tag it like our own tools, and
-- rebuild its hinge so BOTH scissor halves swing inward together when snipping.
-- If the asset is missing we fall back to the procedural shears below.
local SNIP_HALF_ANGLE = math.rad(14) -- each half turns this much (~28 deg total closure)

local function buildCustomShears(def: any, tier: number): Tool?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local template = assets and assets:FindFirstChild("Shears")
	if not template or not template:IsA("Tool") then
		return nil
	end

	local tool = template:Clone() :: Tool
	tool.Name = "Shears"
	tool.RequiresHandle = true
	tool.CanBeDropped = false
	tool.ToolTip = def.name
	tool:SetAttribute("Shears", true)
	tool:SetAttribute("ToolTier", tier)

	for _, d in tool:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = false -- parts must be free so the Motor6Ds can move them
			d.CanQuery = false -- never block the mouse ray to the grass
			d.CanTouch = false
			d.Massless = true
		end
	end

	-- The model ships with a single "Pivot" Motor6D joining the two scissor halves
	-- (Part0 = the grip half, Part1 = the other half). With that setup only Part1
	-- can move, because Part0 is the held Handle -- hence only one side moved. To
	-- make BOTH halves swing inward, we drop in a hidden central hinge part, make
	-- it the Tool's Handle, and hang each half off it with its own Motor6D that
	-- rotates in the opposite direction.
	local pivot: Motor6D? = nil
	for _, d in tool:GetDescendants() do
		if d:IsA("Motor6D") and d.Name == "Pivot" then
			pivot = d
			break
		end
	end

	if pivot and pivot.Part0 and pivot.Part1 then
		local rightHalf = pivot.Part0 :: BasePart
		local leftHalf = pivot.Part1 :: BasePart
		local c0 = pivot.C0
		local c1 = pivot.C1

		-- Hidden hinge part becomes the Tool.Handle. We place it EXACTLY where the
		-- original grip mesh sat and leave Tool.Grip untouched, so the shears sit in
		-- the hand exactly as authored (fixing the earlier orientation problem). The
		-- real scissor pivot is offset from this frame by C0, so each half rotates
		-- about that pivot instead of about the hinge origin.
		local hinge = Instance.new("Part")
		hinge.Name = "Handle"
		hinge.Size = Vector3.new(0.2, 0.2, 0.2)
		hinge.Transparency = 1
		hinge.Anchored = false
		hinge.CanCollide = false
		hinge.CanQuery = false
		hinge.CanTouch = false
		hinge.Massless = true
		hinge.CFrame = rightHalf.CFrame
		hinge.Parent = tool

		-- The old grip mesh is no longer the Handle; rename it so Tool.Handle
		-- resolves to our hinge part. Tool.Grip stays exactly as authored.
		rightHalf.Name = "ShearRight"

		pivot:Destroy()

		-- Right half: rests exactly in place, swings about the real pivot frame
		-- (offset C0 from the hinge). The C0 * rot * C0:Inverse() sandwich rotates
		-- about that pivot rather than about the hinge origin.
		local motorRight = Instance.new("Motor6D")
		motorRight.Name = "ScissorRight"
		motorRight.Part0 = hinge
		motorRight.Part1 = rightHalf
		motorRight.C1 = CFrame.new()
		motorRight.C0 = CFrame.new()
		motorRight:SetAttribute("RestC0", motorRight.C0)
		motorRight:SetAttribute("SwungC0", c0 * CFrame.Angles(0, 0, -SNIP_HALF_ANGLE) * c0:Inverse())
		motorRight.Parent = hinge

		-- Left half: rests in place, swings the opposite way about the same pivot.
		local motorLeft = Instance.new("Motor6D")
		motorLeft.Name = "ScissorLeft"
		motorLeft.Part0 = hinge
		motorLeft.Part1 = leftHalf
		motorLeft.C1 = CFrame.new()
		motorLeft.C0 = c0 * c1:Inverse()
		motorLeft:SetAttribute("RestC0", motorLeft.C0)
		motorLeft:SetAttribute("SwungC0", c0 * CFrame.Angles(0, 0, SNIP_HALF_ANGLE) * c1:Inverse())
		motorLeft.Parent = hinge
	end

	return tool
end

-- ---- Adopting hand-made model assets ---------------------------------------
-- Player-made tool models arrive in many shapes: some are Tools with a Handle,
-- some are bare Models, some are Accessories, and none ship the swing rig our
-- animation code expects. This normalizer clones whichever asset matches the
-- tool name, strips anything that would fight our setup, then rebuilds it into a
-- proper Tool: a hidden structural Handle, a BladeRoot on a "Pivot" Motor6D (so
-- ToolController's RestC0/SwungC0 swing works), and every visual part rigidly
-- welded to that BladeRoot so the whole blade swings as one piece.

local STRIP_CLASSES = {
	"Script", "LocalScript", "ModuleScript",
	"Motor6D", "Weld", "WeldConstraint", "Constraint",
	"Attachment", "Sound", "Animation", "Animator",
	"Keyframe", "KeyframeSequence", "Pose",
	"Camera", "ValueBase", "Configuration",
}

local function stripJunk(container: Instance)
	for _, d in container:GetDescendants() do
		for _, className in STRIP_CLASSES do
			if d:IsA(className) then
				d:Destroy()
				break
			end
		end
	end
end

local function collectParts(root: Instance): { BasePart }
	local parts: { BasePart } = {}
	if root:IsA("BasePart") then
		table.insert(parts, root)
	end
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(parts, d)
		end
	end
	return parts
end

-- Clone the asset named after this tool (def.model or def.name) and rebuild it
-- into one of our standard Tools. Returns nil when no matching asset exists, so
-- callers can fall back to the bespoke scissor asset or the procedural builders.
local function adoptCustomModel(def: any, tier: number): Tool?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local template = assets and assets:FindFirstChild(def.model or def.name)
	if not template then
		return nil
	end

	local source = template:Clone()
	stripJunk(source)

	local parts = collectParts(source)
	if #parts == 0 then
		source:Destroy()
		return nil
	end

	-- Anchor part: an existing "Handle" if the model has one, else the largest
	-- part by volume (usually the main body / grip).
	local primary: BasePart = parts[1]
	local bestVolume = -1
	for _, p in parts do
		if p.Name == "Handle" then
			primary = p
			break
		end
		local v = p.Size.X * p.Size.Y * p.Size.Z
		if v > bestVolume then
			bestVolume = v
			primary = p
		end
	end

	-- Capture every visual part's pose relative to the anchor BEFORE rebuilding.
	local anchorCFrame = primary.CFrame
	local rels: { { part: BasePart, c0: CFrame } } = {}
	for _, p in parts do
		table.insert(rels, { part = p, c0 = anchorCFrame:ToObjectSpace(p.CFrame) })
	end

	local tool = Instance.new("Tool")
	tool.Name = "Shears"
	tool.RequiresHandle = true
	tool.CanBeDropped = false
	tool.ToolTip = def.name
	tool.GripPos = Vector3.new(0, 0, 0)
	tool.GripForward = Vector3.new(0, 0, -1)
	tool.GripUp = Vector3.new(0, 1, 0)
	tool.GripRight = Vector3.new(1, 0, 0)
	tool:SetAttribute("Shears", true)
	tool:SetAttribute("ToolTier", tier)

	-- Hidden structural Handle: what the hand actually holds.
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.3, 0.3, 0.3)
	handle.Transparency = 1
	handle.Anchored = false
	handle.CanCollide = false
	handle.CanQuery = false
	handle.CanTouch = false
	handle.Massless = true
	handle.CFrame = anchorCFrame
	handle.Parent = tool

	-- BladeRoot hangs off the Handle on the "Pivot" Motor6D that ToolController
	-- tweens between RestC0 and SwungC0.
	local bladeRoot = Instance.new("Part")
	bladeRoot.Name = "BladeRoot"
	bladeRoot.Size = Vector3.new(0.2, 0.2, 0.2)
	bladeRoot.Transparency = 1
	bladeRoot.Anchored = false
	bladeRoot.CanCollide = false
	bladeRoot.CanQuery = false
	bladeRoot.CanTouch = false
	bladeRoot.Massless = true
	bladeRoot.CFrame = anchorCFrame
	bladeRoot.Parent = tool

	local restC0 = CFrame.new()
	local pivot = Instance.new("Motor6D")
	pivot.Name = "Pivot"
	pivot.Part0 = handle
	pivot.Part1 = bladeRoot
	pivot.C0 = restC0
	pivot:SetAttribute("RestC0", restC0)
	pivot:SetAttribute("SwungC0", restC0 * CFrame.Angles(math.rad(-58), 0, 0))
	pivot.Parent = handle

	-- Reparent each visual part under the Tool and rigidly weld it to BladeRoot,
	-- preserving its authored pose relative to the anchor.
	for _, entry in rels do
		local p = entry.part
		if p.Name == "Handle" then
			p.Name = "MeshHandle" -- free the name for our structural Handle
		end
		p.Anchored = false
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Massless = true
		p.Parent = tool
		local weld = Instance.new("Motor6D")
		weld.Name = "Weld_" .. p.Name
		weld.Part0 = bladeRoot
		weld.Part1 = p
		weld.C0 = entry.c0
		weld.Parent = bladeRoot
	end

	source:Destroy()
	return tool
end

local STYLE_BUILDERS: { [string]: (any, number) -> Tool } = {
	shears = buildShears,
	sickle = buildSickle,
	scythe = buildScythe,
}

local function buildTool(tier: number): Tool
	local def = GameConfig.TOOL_TIERS[tier] or GameConfig.TOOL_TIERS[1]

	-- Prefer a hand-made model asset that matches this tool by name.
	local custom = adoptCustomModel(def, tier)
	if custom then
		return custom
	end

	-- Rusty Shears still uses the bespoke scissor asset (named "Shears").
	if def.style == "shears" then
		local scissor = buildCustomShears(def, tier)
		if scissor then
			return scissor
		end
	end

	local builder = STYLE_BUILDERS[def.style] or buildShears
	return builder(def, tier)
end

local PlayerDataService
local CutsceneService

-- Remove any existing shears the player has, then hand them a freshly built one
-- for their current tier (auto-equipped).
function ToolService.GiveTool(player: Player)
	local profile = PlayerDataService and PlayerDataService.Get(player)
	local tier = (profile and profile.toolTier) or 1

	local function clearOld(container: Instance?)
		if not container then
			return
		end
		for _, child in container:GetChildren() do
			if child:IsA("Tool") and child:GetAttribute("Shears") then
				child:Destroy()
			end
		end
	end
	clearOld(player.Character)
	clearOld(player:FindFirstChildOfClass("Backpack"))

	local tool = buildTool(tier)
	-- Parent into the character to auto-equip.
	if player.Character then
		tool.Parent = player.Character
	else
		tool.Parent = player:FindFirstChildOfClass("Backpack")
	end
end

function ToolService.Init(services)
	PlayerDataService = services.PlayerDataService
	CutsceneService = services.CutsceneService
end

function ToolService.Start()
	-- During the intro cutscene the player shouldn't have any tools yet;
	-- CutsceneService hands them out the moment the intro finishes.
	local function introPending(player: Player): boolean
		return CutsceneService ~= nil and CutsceneService.IsIntroPending(player)
	end

	local function hookCharacter(player: Player)
		player.CharacterAdded:Connect(function()
			task.wait(0.4) -- let the character + backpack finish loading
			if introPending(player) then
				return
			end
			ToolService.GiveTool(player)
		end)
		if player.Character and not introPending(player) then
			ToolService.GiveTool(player)
		end
	end

	for _, player in Players:GetPlayers() do
		hookCharacter(player)
	end
	Players.PlayerAdded:Connect(hookCharacter)
	print("[ToolService] Tools ready.")
end

return ToolService
