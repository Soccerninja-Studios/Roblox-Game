--!strict
-- ActionBarController: consolidates persistent navigation buttons into a tidy
-- two-column rectangle on the right. Moving an existing GuiButton preserves its
-- original Activated connections, so the old Shop still opens its real menu.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local UIIconProvider = require(ReplicatedStorage.Shared.UIIconProvider)

local ActionBarController = {}

local container: Frame
local registered: { [GuiButton]: boolean } = {}

local ORDER = {
	shop = 1,
	pets = 2,
	rewards = 3,
	villagers = 4,
	quests = 5,
	backpacks = 6,
	mowers = 7,
	skills = 8,
	admin = 9,
}

local EXACT_NAMES: { [string]: string } = {
	shopbutton = "shop",
	openshopbutton = "shop",
	marketbutton = "shop",
	openmarketbutton = "shop",
	petsbutton = "pets",
	petbutton = "pets",
	rewardsbutton = "rewards",
	luckbutton = "rewards",
	villagersbutton = "villagers",
	villagerbutton = "villagers",
	neighborsbutton = "villagers",
	questsbutton = "quests",
	questbutton = "quests",
	backpacksbutton = "backpacks",
	backpackbutton = "backpacks",
	automowersbutton = "mowers",
	automowerbutton = "mowers",
	mowersbutton = "mowers",
	skillsbutton = "skills",
	skillbutton = "skills",
	adminbutton = "admin",
}

local EXACT_TEXT: { [string]: string } = {
	SHOP = "shop",
	MARKET = "shop",
	PETS = "pets",
	REWARDS = "rewards",
	LUCK = "rewards",
	VILLAGERS = "villagers",
	NEIGHBORS = "villagers",
	QUESTS = "quests",
	QUEST = "quests",
	BACKPACKS = "backpacks",
	MOWERS = "mowers",
	["AUTO-MOWERS"] = "mowers",
	SKILLS = "skills",
	ADMIN = "admin",
}

local LABELS = {
	shop = "SHOP",
	pets = "PETS",
	rewards = "LUCK",
	villagers = "NEIGHBORS",
	quests = "QUESTS",
	backpacks = "PACKS",
	mowers = "MOWERS",
	skills = "SKILLS",
	admin = "ADMIN",
}

local function classify(button: GuiButton): string?
	local exact = EXACT_NAMES[string.lower(button.Name)]
	if exact then
		return exact
	end
	if button:IsA("TextButton") then
		local text = string.upper(string.gsub(button.Text, "^%s*(.-)%s*$", "%1"))
		local byText = EXACT_TEXT[text]
		if byText then
			return byText
		end
		-- Legacy open buttons sometimes prefix their label with an emoji or "OPEN".
		if string.find(text, "SHOP", 1, true) or string.find(text, "MARKET", 1, true) then
			return "shop"
		end
	end
	return nil
end

local function makeCorner(parent: Instance, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
end

local function styleButton(button: GuiButton, kind: string)
	registered[button] = true
	button:SetAttribute("RightActionBarButton", true)
	button.Name = string.upper(string.sub(kind, 1, 1)) .. string.sub(kind, 2) .. "Button"
	button.Size = UDim2.fromOffset(68, 68)
	button.AnchorPoint = Vector2.zero
	button.Position = UDim2.fromOffset(0, 0)
	button.LayoutOrder = ORDER[kind] or 99
	button.BackgroundColor3 = Color3.fromRGB(39, 46, 72)
	button.BackgroundTransparency = 0.04
	button.BorderSizePixel = 0
	button.Visible = true
	button.ZIndex = 42
	if button:IsA("TextButton") then
		button.Text = ""
	elseif button:IsA("ImageButton") then
		button.ImageTransparency = 1
	end
	for _, child in button:GetChildren() do
		if child:IsA("UIGridStyleLayout") or child.Name == "ActionIcon" or child.Name == "ActionLabel" then
			continue
		end
		if child:IsA("GuiObject") then
			child.Visible = false
		end
	end
	if not button:FindFirstChildOfClass("UICorner") then
		makeCorner(button, 12)
	end
	local stroke = button:FindFirstChild("ActionStroke") :: UIStroke?
	if not stroke then
		stroke = Instance.new("UIStroke")
		stroke.Name = "ActionStroke"
		stroke.Thickness = 2
		stroke.Transparency = 0.22
		stroke.Parent = button
	end
	stroke.Color = if kind == "shop" then Color3.fromRGB(236, 73, 96)
		elseif kind == "pets" then Color3.fromRGB(255, 170, 108)
		elseif kind == "rewards" then Color3.fromRGB(255, 184, 39)
		else Color3.fromRGB(128, 176, 220)

	if kind == "shop" or kind == "pets" or kind == "rewards" then
		UIIconProvider.Apply(button, kind)
	end
	local label = Instance.new("TextLabel")
	label.Name = "ActionLabel"
	label.AnchorPoint = Vector2.new(0.5, 1)
	label.Position = UDim2.new(0.5, 0, 1, -3)
	label.Size = UDim2.new(1, -6, 0, 16)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.Text = LABELS[kind] or string.upper(kind)
	label.TextColor3 = Color3.fromRGB(255, 255, 248)
	label.TextSize = 9
	label.TextStrokeTransparency = 0.65
	label.ZIndex = button.ZIndex + 2
	label.Parent = button
	button.Parent = container
end

local function consider(instance: Instance)
	if not instance:IsA("GuiButton") or registered[instance] or instance:IsDescendantOf(container) then
		return
	end
	local kind = classify(instance)
	if kind then
		styleButton(instance, kind)
	end
end

function ActionBarController.Init()
	local playerGui = player:WaitForChild("PlayerGui")
	local old = playerGui:FindFirstChild("RightActionBarGui")
	if old then
		old:Destroy()
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "RightActionBarGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.DisplayOrder = 40
	gui.Parent = playerGui

	local panel = Instance.new("Frame")
	panel.Name = "ActionPanel"
	panel.AnchorPoint = Vector2.new(1, 0.5)
	panel.Position = UDim2.new(1, -14, 0.5, 0)
	panel.Size = UDim2.fromOffset(158, 0)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.BackgroundColor3 = Color3.fromRGB(20, 25, 48)
	panel.BackgroundTransparency = 0.18
	panel.BorderSizePixel = 0
	panel.ZIndex = 40
	makeCorner(panel, 16)
	panel.Parent = gui

	local holder = Instance.new("Frame")
	holder.Name = "Buttons"
	holder.Position = UDim2.fromOffset(8, 30)
	holder.Size = UDim2.new(1, -16, 0, 0)
	holder.AutomaticSize = Enum.AutomaticSize.Y
	holder.BackgroundTransparency = 1
	holder.ZIndex = 41
	holder.Parent = panel
	container = holder

	local bottomSpace = Instance.new("UIPadding")
	bottomSpace.PaddingBottom = UDim.new(0, 10)
	bottomSpace.Parent = holder
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(68, 68)
	grid.CellPadding = UDim2.fromOffset(6, 6)
	grid.FillDirection = Enum.FillDirection.Horizontal
	grid.FillDirectionMaxCells = 2
	grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = holder

	local title = Instance.new("TextLabel")
	title.Name = "MenuTitle"
	title.AnchorPoint = Vector2.new(0.5, 0)
	title.Position = UDim2.new(0.5, 0, 0, 7)
	title.Size = UDim2.new(1, -16, 0, 18)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.FredokaOne
	title.Text = "MENU"
	title.TextColor3 = Color3.fromRGB(236, 241, 255)
	title.TextSize = 13
	title.ZIndex = 43
	title.Parent = panel

	for _, descendant in playerGui:GetDescendants() do
		consider(descendant)
	end
	playerGui.DescendantAdded:Connect(function(descendant)
		task.defer(consider, descendant)
	end)
end

function ActionBarController.Start()
	-- Some legacy controllers create their buttons after all Init calls. Rescan for
	-- a few seconds so they are still captured without changing those controllers.
	for _ = 1, 20 do
		task.wait(0.5)
		local playerGui = player:FindFirstChildOfClass("PlayerGui")
		if playerGui then
			for _, descendant in playerGui:GetDescendants() do
				consider(descendant)
			end
		end
	end
end

return ActionBarController
