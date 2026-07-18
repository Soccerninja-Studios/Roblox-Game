--!strict
-- UIController: builds and drives the game HUD.
--   * Top-center clippings counter (animated pill)
--   * Right-side action buttons (always-on Shop toggle)
--   * A centered Shop modal with upgrade cards for the tool + every Kingdom Skill
--   * Walk-in shop zone: the menu auto-opens when you step into the stall and
--     auto-closes when you leave (manual toggling still works anywhere)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local StatCalculator = require(ReplicatedStorage.Shared.StatCalculator)

local UIController = {}

local player = Players.LocalPlayer

-- Palette ---------------------------------------------------------------------
local CREAM = Color3.fromRGB(247, 244, 234)
local INK = Color3.fromRGB(54, 62, 48)
local SUBTLE = Color3.fromRGB(120, 128, 112)
local GREEN = Color3.fromRGB(88, 178, 84)
local GREEN_DARK = Color3.fromRGB(58, 138, 64)
local LOCKED = Color3.fromRGB(168, 172, 162)
local GOLD = Color3.fromRGB(240, 190, 70)

-- Upgrade display metadata ----------------------------------------------------
local SKILL_ORDER = { "SharpBlades", "QuickHands", "ClippingMagnet", "GreenerThumb" }
local SKILL_META: { [string]: { icon: string, name: string, desc: string } } = {
	SharpBlades = { icon = "\u{2702}\u{FE0F}", name = "Sharp Blades", desc = "+5% cut power per level" },
	QuickHands = { icon = "\u{1F4A8}", name = "Quick Hands", desc = "+1% swing speed per level" },
	ClippingMagnet = { icon = "\u{1F9F2}", name = "Clipping Magnet", desc = "+6% collect range per level" },
	GreenerThumb = { icon = "\u{1F33F}", name = "Greener Thumb", desc = "+1% clipping value per level" },
}

-- State -----------------------------------------------------------------------
local latestState: any = { clippings = 0, toolTier = 1, skills = {} }
local isOpen = false
local openedByZone = false
local cardUpdaters: { (state: any) -> () } = {}
local clippingsLabel: TextLabel
local modal: Frame
local backdrop: TextButton
local lastShown = -1

-- Helpers ---------------------------------------------------------------------
local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
	return c
end

local function stroke(parent: Instance, thickness: number, color: Color3, transparency: number?)
	local s = Instance.new("UIStroke")
	s.Thickness = thickness
	s.Color = color
	s.Transparency = transparency or 0
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

local function gradient(parent: Instance, a: Color3, b: Color3, rotation: number)
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(a, b)
	g.Rotation = rotation
	g.Parent = parent
	return g
end

local function padding(parent: Instance, px: number)
	local p = Instance.new("UIPadding")
	p.PaddingLeft = UDim.new(0, px)
	p.PaddingRight = UDim.new(0, px)
	p.PaddingTop = UDim.new(0, px)
	p.PaddingBottom = UDim.new(0, px)
	p.Parent = parent
	return p
end

local function shadow(target: GuiObject, spread: number)
	local s = Instance.new("Frame")
	s.Name = "Shadow"
	s.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	s.BackgroundTransparency = 0.72
	s.Size = UDim2.new(1, spread, 1, spread)
	s.Position = UDim2.new(0, -spread / 2, 0, -spread / 2 + 3)
	s.ZIndex = target.ZIndex - 1
	corner(s, 16)
	s.Parent = target
	return s
end

local function formatNumber(n: number): string
	local s = tostring(math.floor(n))
	local formatted = s
	while true do
		local replaced
		formatted, replaced = string.gsub(formatted, "^(-?%d+)(%d%d%d)", "%1,%2")
		if replaced == 0 then
			break
		end
	end
	return formatted
end

-- Currency pill (top-center) --------------------------------------------------
local function buildCurrency(gui: ScreenGui)
	local pill = Instance.new("Frame")
	pill.Name = "Currency"
	pill.AnchorPoint = Vector2.new(0.5, 0)
	pill.Position = UDim2.new(0.5, 0, 0, 18)
	pill.Size = UDim2.fromOffset(220, 52)
	pill.BackgroundColor3 = GREEN
	pill.ZIndex = 5
	corner(pill, 26)
	gradient(pill, Color3.fromRGB(104, 194, 98), GREEN_DARK, 90)
	stroke(pill, 3, Color3.fromRGB(255, 255, 255), 0.35)
	shadow(pill, 10)
	pill.Parent = gui

	local icon = Instance.new("TextLabel")
	icon.BackgroundTransparency = 1
	icon.Size = UDim2.fromOffset(44, 52)
	icon.Position = UDim2.fromOffset(6, 0)
	icon.Text = "\u{1F33F}"
	icon.TextScaled = true
	icon.ZIndex = 6
	local ip = Instance.new("UIPadding")
	ip.PaddingTop = UDim.new(0, 8)
	ip.PaddingBottom = UDim.new(0, 8)
	ip.Parent = icon
	icon.Parent = pill

	clippingsLabel = Instance.new("TextLabel")
	clippingsLabel.BackgroundTransparency = 1
	clippingsLabel.Size = UDim2.new(1, -50, 1, 0)
	clippingsLabel.Position = UDim2.fromOffset(48, 0)
	clippingsLabel.Font = Enum.Font.FredokaOne
	clippingsLabel.Text = "0"
	clippingsLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	clippingsLabel.TextScaled = true
	clippingsLabel.TextXAlignment = Enum.TextXAlignment.Left
	clippingsLabel.ZIndex = 6
	local lp = Instance.new("UIPadding")
	lp.PaddingTop = UDim.new(0, 12)
	lp.PaddingBottom = UDim.new(0, 12)
	lp.PaddingRight = UDim.new(0, 14)
	lp.Parent = clippingsLabel
	stroke(clippingsLabel, 2, GREEN_DARK)
	clippingsLabel.Parent = pill
end

-- Right-side round action button ----------------------------------------------
local function buildActionButton(gui: ScreenGui, emoji: string, onClick: () -> ()): TextButton
	local holder = gui:FindFirstChild("ActionButtons") :: Frame
	if not holder then
		holder = Instance.new("Frame")
		holder.Name = "ActionButtons"
		holder.AnchorPoint = Vector2.new(1, 0.5)
		holder.Position = UDim2.new(1, -22, 0.5, 0)
		holder.Size = UDim2.fromOffset(72, 300)
		holder.BackgroundTransparency = 1
		holder.ZIndex = 5
		local list = Instance.new("UIListLayout")
		list.FillDirection = Enum.FillDirection.Vertical
		list.HorizontalAlignment = Enum.HorizontalAlignment.Center
		list.VerticalAlignment = Enum.VerticalAlignment.Center
		list.Padding = UDim.new(0, 14)
		list.Parent = holder
		holder.Parent = gui
	end

	local btn = Instance.new("TextButton")
	btn.Size = UDim2.fromOffset(66, 66)
	btn.BackgroundColor3 = GREEN
	btn.Text = emoji
	btn.TextScaled = true
	btn.AutoButtonColor = false
	btn.ZIndex = 6
	local bp = Instance.new("UIPadding")
	bp.PaddingTop = UDim.new(0, 10)
	bp.PaddingBottom = UDim.new(0, 10)
	bp.Parent = btn
	corner(btn, 33)
	gradient(btn, Color3.fromRGB(104, 194, 98), GREEN_DARK, 90)
	stroke(btn, 3, Color3.fromRGB(255, 255, 255), 0.3)
	shadow(btn, 10)
	btn.Parent = holder

	btn.MouseEnter:Connect(function()
		TweenService:Create(btn, TweenInfo.new(0.12), { Size = UDim2.fromOffset(72, 72) }):Play()
	end)
	btn.MouseLeave:Connect(function()
		TweenService:Create(btn, TweenInfo.new(0.12), { Size = UDim2.fromOffset(66, 66) }):Play()
	end)
	btn.Activated:Connect(onClick)
	return btn
end

-- One upgrade card ------------------------------------------------------------
local function buildCard(parent: Instance, order: number, icon: string, iconColor: Color3, getData: (state: any) -> { name: string, desc: string, level: string, cost: number?, maxed: boolean }, onBuy: () -> ())
	local card = Instance.new("Frame")
	card.Size = UDim2.new(1, 0, 0, 84)
	card.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	card.LayoutOrder = order
	card.ZIndex = 11
	corner(card, 14)
	stroke(card, 2, Color3.fromRGB(224, 220, 206))
	card.Parent = parent

	local iconBox = Instance.new("TextLabel")
	iconBox.Size = UDim2.fromOffset(58, 58)
	iconBox.Position = UDim2.fromOffset(13, 13)
	iconBox.BackgroundColor3 = iconColor
	iconBox.Text = icon
	iconBox.TextScaled = true
	iconBox.ZIndex = 12
	local ipad = Instance.new("UIPadding")
	ipad.PaddingTop = UDim.new(0, 8)
	ipad.PaddingBottom = UDim.new(0, 8)
	ipad.Parent = iconBox
	corner(iconBox, 12)
	iconBox.Parent = card

	local nameLabel = Instance.new("TextLabel")
	nameLabel.BackgroundTransparency = 1
	nameLabel.Position = UDim2.fromOffset(82, 12)
	nameLabel.Size = UDim2.new(1, -230, 0, 26)
	nameLabel.Font = Enum.Font.FredokaOne
	nameLabel.TextColor3 = INK
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextYAlignment = Enum.TextYAlignment.Bottom
	nameLabel.TextSize = 20
	nameLabel.ZIndex = 12
	nameLabel.Parent = card

	local descLabel = Instance.new("TextLabel")
	descLabel.BackgroundTransparency = 1
	descLabel.Position = UDim2.fromOffset(82, 40)
	descLabel.Size = UDim2.new(1, -230, 0, 20)
	descLabel.Font = Enum.Font.Gotham
	descLabel.TextColor3 = SUBTLE
	descLabel.TextXAlignment = Enum.TextXAlignment.Left
	descLabel.TextSize = 13
	descLabel.ZIndex = 12
	descLabel.Parent = card

	local levelLabel = Instance.new("TextLabel")
	levelLabel.BackgroundTransparency = 1
	levelLabel.Position = UDim2.fromOffset(82, 58)
	levelLabel.Size = UDim2.new(1, -230, 0, 18)
	levelLabel.Font = Enum.Font.GothamMedium
	levelLabel.TextColor3 = GREEN_DARK
	levelLabel.TextXAlignment = Enum.TextXAlignment.Left
	levelLabel.TextSize = 13
	levelLabel.ZIndex = 12
	levelLabel.Parent = card

	local buy = Instance.new("TextButton")
	buy.AnchorPoint = Vector2.new(1, 0.5)
	buy.Position = UDim2.new(1, -14, 0.5, 0)
	buy.Size = UDim2.fromOffset(128, 56)
	buy.BackgroundColor3 = GREEN
	buy.Font = Enum.Font.FredokaOne
	buy.TextColor3 = Color3.fromRGB(255, 255, 255)
	buy.TextSize = 18
	buy.AutoButtonColor = false
	buy.Text = ""
	buy.ZIndex = 12
	corner(buy, 12)
	local buyStroke = stroke(buy, 2, Color3.fromRGB(255, 255, 255), 0.4)
	buy.Parent = card
	buy.Activated:Connect(onBuy)

	local function update(state: any)
		local data = getData(state)
		nameLabel.Text = data.name
		descLabel.Text = data.desc
		levelLabel.Text = data.level
		if data.maxed then
			buy.Text = "MAX"
			buy.BackgroundColor3 = LOCKED
			buy.AutoButtonColor = false
			buyStroke.Transparency = 0.7
		else
			local cost = data.cost or 0
			local afford = state.clippings >= cost
			buy.Text = (cost == 0) and "FREE" or ("\u{1F33F} " .. formatNumber(cost))
			buy.BackgroundColor3 = afford and GREEN or LOCKED
			buyStroke.Transparency = afford and 0.4 or 0.7
		end
	end

	table.insert(cardUpdaters, update)
end

-- Shop modal ------------------------------------------------------------------
local function buildShopModal(gui: ScreenGui)
	backdrop = Instance.new("TextButton")
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	backdrop.BackgroundTransparency = 1
	backdrop.Text = ""
	backdrop.AutoButtonColor = false
	backdrop.Visible = false
	backdrop.ZIndex = 9
	backdrop.Parent = gui
	backdrop.Activated:Connect(function()
		UIController.CloseShop()
	end)

	modal = Instance.new("Frame")
	modal.Name = "ShopModal"
	modal.AnchorPoint = Vector2.new(0.5, 0.5)
	modal.Position = UDim2.fromScale(0.5, 0.5)
	modal.Size = UDim2.fromOffset(470, 560)
	modal.BackgroundColor3 = CREAM
	modal.Visible = false
	modal.ZIndex = 10
	corner(modal, 18)
	stroke(modal, 3, Color3.fromRGB(255, 255, 255), 0.2)
	shadow(modal, 22)
	local sizeConstraint = Instance.new("UISizeConstraint")
	sizeConstraint.MaxSize = Vector2.new(470, 560)
	sizeConstraint.Parent = modal
	modal.Parent = gui

	-- Header
	local header = Instance.new("Frame")
	header.Size = UDim2.new(1, 0, 0, 66)
	header.BackgroundColor3 = GREEN
	header.ZIndex = 11
	corner(header, 18)
	gradient(header, Color3.fromRGB(104, 194, 98), GREEN_DARK, 0)
	header.Parent = modal
	-- mask the bottom rounded corners of the header
	local headerMask = Instance.new("Frame")
	headerMask.Size = UDim2.new(1, 0, 0, 20)
	headerMask.Position = UDim2.new(0, 0, 1, -20)
	headerMask.BackgroundColor3 = GREEN_DARK
	headerMask.BorderSizePixel = 0
	headerMask.ZIndex = 11
	headerMask.Parent = header

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(20, 0)
	title.Size = UDim2.new(1, -80, 1, 0)
	title.Font = Enum.Font.FredokaOne
	title.Text = "\u{1F6D2}  Market"
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextSize = 28
	title.ZIndex = 12
	stroke(title, 2, GREEN_DARK)
	title.Parent = header

	local close = Instance.new("TextButton")
	close.AnchorPoint = Vector2.new(1, 0.5)
	close.Position = UDim2.new(1, -16, 0.5, 0)
	close.Size = UDim2.fromOffset(40, 40)
	close.BackgroundColor3 = Color3.fromRGB(220, 88, 78)
	close.Font = Enum.Font.FredokaOne
	close.Text = "\u{2715}"
	close.TextColor3 = Color3.fromRGB(255, 255, 255)
	close.TextSize = 22
	close.ZIndex = 13
	corner(close, 20)
	stroke(close, 2, Color3.fromRGB(255, 255, 255), 0.4)
	close.Parent = header
	close.Activated:Connect(function()
		UIController.CloseShop()
	end)

	-- Scrolling body
	local body = Instance.new("ScrollingFrame")
	body.Position = UDim2.fromOffset(0, 66)
	body.Size = UDim2.new(1, 0, 1, -66)
	body.BackgroundTransparency = 1
	body.BorderSizePixel = 0
	body.ScrollBarThickness = 6
	body.ScrollBarImageColor3 = GREEN_DARK
	body.CanvasSize = UDim2.new(0, 0, 0, 0)
	body.AutomaticCanvasSize = Enum.AutomaticSize.Y
	body.ZIndex = 11
	padding(body, 16)
	body.Parent = modal

	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 12)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = body

	-- Section label: Tools
	local toolsHeader = Instance.new("TextLabel")
	toolsHeader.BackgroundTransparency = 1
	toolsHeader.Size = UDim2.new(1, 0, 0, 24)
	toolsHeader.Font = Enum.Font.FredokaOne
	toolsHeader.Text = "Tools"
	toolsHeader.TextColor3 = INK
	toolsHeader.TextXAlignment = Enum.TextXAlignment.Left
	toolsHeader.TextSize = 18
	toolsHeader.LayoutOrder = 0
	toolsHeader.ZIndex = 11
	toolsHeader.Parent = body

	-- Tool upgrade card
	buildCard(body, 1, "\u{2702}\u{FE0F}", Color3.fromRGB(210, 235, 205), function(state)
		local tier = state.toolTier or 1
		local current = GameConfig.TOOL_TIERS[tier]
		local nextDef = GameConfig.TOOL_TIERS[tier + 1]
		if not nextDef then
			return {
				name = current and current.name or "Tool",
				desc = "Best tool in the kingdom!",
				level = "Max tier reached",
				maxed = true,
			}
		end
		return {
			name = nextDef.name,
			desc = "Cut power " .. current.bladesPerSwing .. " \u{2192} " .. nextDef.bladesPerSwing,
			level = "Owned: " .. (current and current.name or "-"),
			cost = nextDef.cost,
			maxed = false,
		}
	end, function()
		Remotes.Get("PurchaseUpgrade"):FireServer("tool")
	end)

	-- Section label: Skills
	local skillsHeader = Instance.new("TextLabel")
	skillsHeader.BackgroundTransparency = 1
	skillsHeader.Size = UDim2.new(1, 0, 0, 24)
	skillsHeader.Font = Enum.Font.FredokaOne
	skillsHeader.Text = "Kingdom Skills"
	skillsHeader.TextColor3 = INK
	skillsHeader.TextXAlignment = Enum.TextXAlignment.Left
	skillsHeader.TextSize = 18
	skillsHeader.LayoutOrder = 2
	skillsHeader.ZIndex = 11
	skillsHeader.Parent = body

	for i, skillName in SKILL_ORDER do
		local meta = SKILL_META[skillName]
		local def = GameConfig.SKILLS[skillName]
		buildCard(body, 2 + i, meta.icon, Color3.fromRGB(224, 240, 210), function(state)
			local level = (state.skills and state.skills[skillName]) or 0
			local maxed = level >= def.maxLevel
			return {
				name = meta.name,
				desc = meta.desc,
				level = "Level " .. level .. " / " .. def.maxLevel,
				cost = maxed and nil or StatCalculator.GetSkillCost(skillName, level),
				maxed = maxed,
			}
		end, function()
			Remotes.Get("PurchaseUpgrade"):FireServer("skill", skillName)
		end)
	end
end

-- Open / close ----------------------------------------------------------------
function UIController.OpenShop(byZone: boolean)
	if isOpen then
		return
	end
	isOpen = true
	openedByZone = byZone
	backdrop.Visible = true
	modal.Visible = true
	modal.Size = UDim2.fromOffset(400, 480)
	TweenService:Create(backdrop, TweenInfo.new(0.18), { BackgroundTransparency = 0.45 }):Play()
	TweenService:Create(modal, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.fromOffset(470, 560),
	}):Play()
end

function UIController.CloseShop()
	if not isOpen then
		return
	end
	isOpen = false
	openedByZone = false
	local fade = TweenService:Create(backdrop, TweenInfo.new(0.15), { BackgroundTransparency = 1 })
	fade:Play()
	TweenService:Create(modal, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Size = UDim2.fromOffset(400, 480),
	}):Play()
	fade.Completed:Connect(function()
		if not isOpen then
			backdrop.Visible = false
			modal.Visible = false
		end
	end)
end

function UIController.ToggleShop()
	if isOpen then
		UIController.CloseShop()
	else
		UIController.OpenShop(false)
	end
end

-- Refresh ---------------------------------------------------------------------
local function updateUI(state: any)
	latestState = state
	if clippingsLabel then
		clippingsLabel.Text = formatNumber(state.clippings or 0)
		if lastShown >= 0 and (state.clippings or 0) ~= lastShown then
			-- little pop when the balance changes
			clippingsLabel.Parent.Size = UDim2.fromOffset(206, 48)
			TweenService:Create(clippingsLabel.Parent, TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Size = UDim2.fromOffset(220, 52),
			}):Play()
		end
		lastShown = state.clippings or 0
	end
	for _, update in cardUpdaters do
		update(state)
	end
end

-- Walk-in zone detection ------------------------------------------------------
local function startZoneWatch()
	RunService.Heartbeat:Connect(function()
		local shop = Workspace:FindFirstChild("Shop")
		local zone = shop and shop:FindFirstChild("ShopZone") :: BasePart?
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not zone or not root then
			return
		end
		local delta = root.Position - zone.Position
		local horizontal = math.sqrt(delta.X * delta.X + delta.Z * delta.Z)
		local inside = horizontal <= GameConfig.SHOP_ZONE_RADIUS
		if inside and not isOpen then
			UIController.OpenShop(true)
		elseif not inside and isOpen and openedByZone then
			UIController.CloseShop()
		end
	end)
end

function UIController.Init()
	local playerGui = player:WaitForChild("PlayerGui")

	local gui = Instance.new("ScreenGui")
	gui.Name = "HUD"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Global
	gui.Parent = playerGui

	buildCurrency(gui)
	buildShopModal(gui)
	buildActionButton(gui, "\u{1F6D2}", function()
		UIController.ToggleShop()
	end)
end

function UIController.Start()
	Remotes.Get("StateChanged").OnClientEvent:Connect(updateUI)
	Remotes.Get("RequestState"):FireServer()
	startZoneWatch()
end

return UIController
