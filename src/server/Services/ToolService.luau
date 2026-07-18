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

local STYLE_BUILDERS: { [string]: (any, number) -> Tool } = {
	shears = buildShears,
	sickle = buildSickle,
	scythe = buildScythe,
}

local function buildTool(tier: number): Tool
	local def = GameConfig.TOOL_TIERS[tier] or GameConfig.TOOL_TIERS[1]
	local builder = STYLE_BUILDERS[def.style] or buildShears
	return builder(def, tier)
end

local PlayerDataService

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
end

function ToolService.Start()
	local function hookCharacter(player: Player)
		player.CharacterAdded:Connect(function()
			task.wait(0.4) -- let the character + backpack finish loading
			ToolService.GiveTool(player)
		end)
		if player.Character then
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
