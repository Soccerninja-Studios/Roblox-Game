--!strict
-- ToolService: gives every player a physical, held "Shears" tool that they use to
-- mow grass. The tool is built entirely from parts (no external assets) and has a
-- snipping joint (Motor6D) that the client animates on every swing. When the player
-- buys a new tool tier, the held tool is rebuilt to match.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

local ToolService = {}

local PlayerDataService: any

local function color3(rgb: { number }): Color3
	return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

local function makePart(name: string, size: Vector3, color: Color3, material: Enum.Material): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = material
	part.Anchored = false
	part.CanCollide = false
	part.CanQuery = false -- never block the mouse ray used to target grass
	part.CanTouch = false
	part.Massless = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	return part
end

-- Builds a shears/scissors tool sized and colored for the given tool tier.
local function buildShears(tier: number): Tool
	local def = GameConfig.TOOL_TIERS[tier] or GameConfig.TOOL_TIERS[1]
	local scale = def.toolScale or 1
	local handleColor = color3(def.handleColor or { 92, 64, 40 })
	local bladeColor = color3(def.bladeColor or { 190, 190, 200 })
	local bladeMaterial = (Enum.Material :: any)[def.bladeMaterial or "Metal"] :: Enum.Material

	local tool = Instance.new("Tool")
	tool.Name = "Shears"
	tool.RequiresHandle = true
	tool.CanBeDropped = false
	tool.ToolTip = `{def.name} - hold left click on grass to mow`
	tool:SetAttribute("Shears", true)
	tool:SetAttribute("ToolTier", tier)

	-- Handle = the grip the character holds
	local handle = makePart("Handle", Vector3.new(0.35, 0.35, 1.0) * scale, handleColor, Enum.Material.Wood)
	handle.Parent = tool

	local bladeSize = Vector3.new(0.1, 0.45, 2.2) * scale

	-- Fixed (lower) blade: rigidly joined to the handle, angled down slightly
	local fixedBlade = makePart("FixedBlade", bladeSize, bladeColor, bladeMaterial)
	fixedBlade.Parent = tool
	local fixedJoint = Instance.new("Motor6D")
	fixedJoint.Name = "FixedJoint"
	fixedJoint.Part0 = handle
	fixedJoint.Part1 = fixedBlade
	fixedJoint.C0 = CFrame.new(0, -0.16, -1.05) * CFrame.Angles(0, 0, math.rad(-14))
	fixedJoint.C1 = CFrame.new()
	fixedJoint.Parent = handle

	-- Moving (upper) blade: joined by an animatable Motor6D so it can "snip"
	local movingBlade = makePart("MovingBlade", bladeSize, bladeColor, bladeMaterial)
	movingBlade.Parent = tool
	local openC0 = CFrame.new(0, 0.16, -1.05) * CFrame.Angles(0, 0, math.rad(16))
	local closedC0 = CFrame.new(0, 0.16, -1.05) * CFrame.Angles(0, 0, math.rad(-2))
	local snip = Instance.new("Motor6D")
	snip.Name = "Snip"
	snip.Part0 = handle
	snip.Part1 = movingBlade
	snip.C0 = openC0
	snip.C1 = CFrame.new()
	-- The client reads these to animate the snip without any server round-trip.
	snip:SetAttribute("OpenC0", openC0)
	snip:SetAttribute("ClosedC0", closedC0)
	snip.Parent = handle

	-- A small pin where the blades cross, for looks
	local pin = makePart("Pin", Vector3.new(0.22, 0.22, 0.22) * scale, Color3.fromRGB(60, 60, 65), Enum.Material.Metal)
	pin.Shape = Enum.PartType.Ball
	pin.Parent = tool
	local pinJoint = Instance.new("Motor6D")
	pinJoint.Name = "PinJoint"
	pinJoint.Part0 = handle
	pinJoint.Part1 = pin
	pinJoint.C0 = CFrame.new(0, 0, -0.55)
	pinJoint.C1 = CFrame.new()
	pinJoint.Parent = handle

	return tool
end

local function clearExistingShears(container: Instance?)
	if not container then
		return
	end
	for _, item in container:GetChildren() do
		if item:IsA("Tool") and item:GetAttribute("Shears") then
			item:Destroy()
		end
	end
end

-- Gives (or refreshes) the player's held shears to match their current tool tier.
function ToolService.GiveTool(player: Player)
	local character = player.Character
	if not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	local profile = PlayerDataService and PlayerDataService.Get(player)
	local tier = (profile and profile.toolTier) or 1

	clearExistingShears(character)
	clearExistingShears(player:FindFirstChildOfClass("Backpack"))

	local tool = buildShears(tier)
	-- Parenting the tool to the character auto-equips it into the player's hand.
	tool.Parent = character
end

local function onCharacterAdded(player: Player, character: Model)
	character:WaitForChild("Humanoid", 10)
	task.wait(0.3) -- let the profile load / character fully assemble
	ToolService.GiveTool(player)
end

function ToolService.Init(services: any)
	PlayerDataService = services.PlayerDataService
end

function ToolService.Start()
	local function hook(player: Player)
		player.CharacterAdded:Connect(function(character)
			task.spawn(onCharacterAdded, player, character)
		end)
		if player.Character then
			task.spawn(onCharacterAdded, player, player.Character)
		end
	end

	for _, player in Players:GetPlayers() do
		hook(player)
	end
	Players.PlayerAdded:Connect(hook)
end

return ToolService
