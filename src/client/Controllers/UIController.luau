--!strict
-- UIController: builds and updates the HUD.
--
-- Layout:
--   * Clippings counter, top center.
--   * Main interactive buttons on the RIGHT side of the screen (currently the Shop
--     button; more can be added here later).
--   * All upgrades now live inside a centered Shop menu (a modal), NOT a permanent
--     side panel. The menu opens either by walking into the shop zone or by
--     clicking the always-on-screen Shop button.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local StatCalculator = require(ReplicatedStorage.Shared.StatCalculator)

local SKILLS: { [string]: any } = GameConfig.SKILLS

local UIController = {}

local player = Players.LocalPlayer

local clippingsLabel: TextLabel
local shopFrame: Frame
local backdrop: TextButton
local toolButton: TextButton
local skillButtons: { [string]: TextButton } = {}
local lastState: any = nil

local menuOpen = false
local openedByZone = false

local SKILL_ORDER = { "SharpBlades", "QuickHands" }
local SKILL_DISPLAY = {
	SharpBlades = "Sharp Blades (+2% power)",
	QuickHands = "Quick Hands (+1% speed)",
}

local function formatNumber(n: number): string
	local s = tostring(math.floor(n)):reverse()
	s = s:gsub("(%d%d%d)", "%1,")
	s = s:reverse()
	s = s:gsub("^,", "")
	return s
end

local function makeCorner(radius: number, parent: Instance)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
end

local function makeUpgradeButton(parent: Instance): TextButton
	local button = Instance.new("TextButton")
	button.Size = UDim2.new(1, -12, 0, 58)
	button.BackgroundColor3 = Color3.fromRGB(76, 140, 60)
	button.TextColor3 = Color3.new(1, 1, 1)
	button.Font = Enum.Font.FredokaOne
	button.TextScaled = true
	button.AutoButtonColor = true
	button.Text = ""
	makeCorner(10, button)
	button.Parent = parent
	return button
end

local function setMenuOpen(open: boolean, byZone: boolean)
	menuOpen = open
	openedByZone = open and byZone or false
	shopFrame.Visible = open
	backdrop.Visible = open
end

local function buildGui()
	local playerGui = player:WaitForChild("PlayerGui")

	local gui = Instance.new("ScreenGui")
	gui.Name = "HUD"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	-- Clippings counter (top center)
	clippingsLabel = Instance.new("TextLabel")
	clippingsLabel.AnchorPoint = Vector2.new(0.5, 0)
	clippingsLabel.Position = UDim2.new(0.5, 0, 0, 8)
	clippingsLabel.Size = UDim2.fromOffset(260, 44)
	clippingsLabel.BackgroundColor3 = Color3.fromRGB(34, 66, 34)
	clippingsLabel.BackgroundTransparency = 0.2
	clippingsLabel.TextColor3 = Color3.fromRGB(190, 255, 120)
	clippingsLabel.Font = Enum.Font.FredokaOne
	clippingsLabel.TextScaled = true
	clippingsLabel.Text = "\u{1F33F} 0"
	makeCorner(10, clippingsLabel)
	clippingsLabel.Parent = gui

	-- Right-side main buttons container
	local rightBar = Instance.new("Frame")
	rightBar.Name = "MainButtons"
	rightBar.AnchorPoint = Vector2.new(1, 0.5)
	rightBar.Position = UDim2.new(1, -12, 0.5, 0)
	rightBar.Size = UDim2.fromOffset(76, 200)
	rightBar.BackgroundTransparency = 1
	rightBar.Parent = gui

	local rightLayout = Instance.new("UIListLayout")
	rightLayout.Padding = UDim.new(0, 10)
	rightLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	rightLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	rightLayout.Parent = rightBar

	local shopToggle = Instance.new("TextButton")
	shopToggle.Name = "ShopButton"
	shopToggle.Size = UDim2.fromOffset(72, 72)
	shopToggle.BackgroundColor3 = Color3.fromRGB(214, 158, 54)
	shopToggle.TextColor3 = Color3.new(1, 1, 1)
	shopToggle.Font = Enum.Font.FredokaOne
	shopToggle.TextScaled = true
	shopToggle.Text = "\u{1F6D2}\nShop"
	makeCorner(14, shopToggle)
	shopToggle.Parent = rightBar

	-- Dark backdrop behind the modal (also click-to-close)
	backdrop = Instance.new("TextButton")
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	backdrop.BackgroundTransparency = 0.5
	backdrop.Text = ""
	backdrop.AutoButtonColor = false
	backdrop.Visible = false
	backdrop.ZIndex = 5
	backdrop.Parent = gui

	-- Shop menu (centered modal)
	shopFrame = Instance.new("Frame")
	shopFrame.Name = "ShopMenu"
	shopFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	shopFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
	shopFrame.Size = UDim2.fromOffset(360, 440)
	shopFrame.BackgroundColor3 = Color3.fromRGB(34, 66, 34)
	shopFrame.Visible = false
	shopFrame.ZIndex = 6
	makeCorner(16, shopFrame)
	shopFrame.Parent = gui

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, 0, 0, 52)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.FredokaOne
	title.TextScaled = true
	title.TextColor3 = Color3.fromRGB(236, 255, 200)
	title.Text = "Kingdom Shop"
	title.ZIndex = 7
	title.Parent = shopFrame
	local titlePad = Instance.new("UIPadding")
	titlePad.PaddingTop = UDim.new(0, 10)
	titlePad.PaddingLeft = UDim.new(0, 14)
	titlePad.PaddingRight = UDim.new(0, 48)
	titlePad.Parent = title
	title.TextXAlignment = Enum.TextXAlignment.Left

	local closeButton = Instance.new("TextButton")
	closeButton.Name = "Close"
	closeButton.AnchorPoint = Vector2.new(1, 0)
	closeButton.Position = UDim2.new(1, -10, 0, 10)
	closeButton.Size = UDim2.fromOffset(36, 36)
	closeButton.BackgroundColor3 = Color3.fromRGB(180, 64, 64)
	closeButton.TextColor3 = Color3.new(1, 1, 1)
	closeButton.Font = Enum.Font.FredokaOne
	closeButton.TextScaled = true
	closeButton.Text = "\u{2715}"
	closeButton.ZIndex = 8
	makeCorner(10, closeButton)
	closeButton.Parent = shopFrame

	local list = Instance.new("ScrollingFrame")
	list.Name = "List"
	list.Position = UDim2.new(0, 0, 0, 58)
	list.Size = UDim2.new(1, 0, 1, -66)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 6
	list.CanvasSize = UDim2.new(0, 0, 0, 0)
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ZIndex = 7
	list.Parent = shopFrame

	local listPad = Instance.new("UIPadding")
	listPad.PaddingLeft = UDim.new(0, 6)
	listPad.PaddingRight = UDim.new(0, 6)
	listPad.PaddingTop = UDim.new(0, 4)
	listPad.PaddingBottom = UDim.new(0, 8)
	listPad.Parent = list

	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 8)
	listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = list

	toolButton = makeUpgradeButton(list)
	toolButton.LayoutOrder = 1
	toolButton.ZIndex = 7
	for i, skillName in SKILL_ORDER do
		local button = makeUpgradeButton(list)
		button.LayoutOrder = i + 1
		button.ZIndex = 7
		skillButtons[skillName] = button
	end

	-- Wire up interactions
	shopToggle.Activated:Connect(function()
		setMenuOpen(not menuOpen, false)
	end)
	closeButton.Activated:Connect(function()
		setMenuOpen(false, false)
	end)
	backdrop.Activated:Connect(function()
		setMenuOpen(false, false)
	end)

	gui.Parent = playerGui
end

local function updateUI(state: any)
	lastState = state
	clippingsLabel.Text = "\u{1F33F} " .. formatNumber(state.clippings)

	local nextTool = GameConfig.TOOL_TIERS[state.toolTier + 1]
	if nextTool then
		toolButton.Text = `Next Tool: {nextTool.name}\n{formatNumber(nextTool.cost)} Clippings`
	else
		local current = GameConfig.TOOL_TIERS[state.toolTier]
		toolButton.Text = `Tool: {current.name} (MAX)`
	end

	for _, skillName in SKILL_ORDER do
		local button = skillButtons[skillName]
		local level = state.skills[skillName] or 0
		local def = SKILLS[skillName]
		if level >= def.maxLevel then
			button.Text = `{SKILL_DISPLAY[skillName]}\nLv {level} (MAX)`
		else
			local cost = StatCalculator.GetSkillCost(skillName, level)
			button.Text = `{SKILL_DISPLAY[skillName]}\nLv {level} \u{2192} {formatNumber(cost)} Clippings`
		end
	end
end

-- Opens the menu automatically when the player walks into the shop zone, and
-- closes it again when they leave (only if it was the zone that opened it).
local function watchShopZone()
	while true do
		task.wait(0.2)
		local shop = Workspace:FindFirstChild("Shop")
		local zone = shop and shop:FindFirstChild("ShopZone")
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if zone and zone:IsA("BasePart") and root then
			local delta = root.Position - zone.Position
			local horizontal = Vector3.new(delta.X, 0, delta.Z).Magnitude
			local inside = horizontal <= GameConfig.SHOP_ZONE_RADIUS
			if inside and not menuOpen then
				setMenuOpen(true, true)
			elseif not inside and menuOpen and openedByZone then
				setMenuOpen(false, true)
			end
		end
	end
end

function UIController.Init()
	buildGui()

	toolButton.Activated:Connect(function()
		Remotes.Get("PurchaseUpgrade"):FireServer("tool")
	end)

	for skillName, button in skillButtons do
		button.Activated:Connect(function()
			Remotes.Get("PurchaseUpgrade"):FireServer("skill", skillName)
		end)
	end

	Remotes.Get("StateChanged").OnClientEvent:Connect(updateUI)
end

function UIController.Start()
	-- Ask the server for our first snapshot now that the UI exists
	Remotes.Get("RequestState"):FireServer()
	task.spawn(watchShopZone)
end

return UIController
