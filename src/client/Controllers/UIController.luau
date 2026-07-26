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
local Assets = require(ReplicatedStorage.Shared.Assets)

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
local DIAMOND = Color3.fromRGB(120, 210, 235)

-- Upgrade display metadata ----------------------------------------------------
local SKILL_ORDER = { "SharpBlades", "QuickHands", "ClippingMagnet", "GreenerThumb" }
local SKILL_META: { [string]: { icon: string, name: string, desc: string } } = {
	SharpBlades = { icon = "\u{2702}\u{FE0F}", name = "Sharp Blades", desc = "+5% cut power per level" },
	QuickHands = { icon = "\u{1F4A8}", name = "Quick Hands", desc = "+1% swing speed per level" },
	ClippingMagnet = { icon = "\u{1F9F2}", name = "Clipping Magnet", desc = "+6% collect range per level" },
	GreenerThumb = { icon = "\u{1F33F}", name = "Greener Thumb", desc = "+1% clipping value per level" },
}

-- State -----------------------------------------------------------------------
local latestState: any = { clippings = 0, gold = 0, diamonds = 0, bagCapacity = 25, toolTier = 1, skills = {} }
local isOpen = false
local openedByZone = false
local cardUpdaters: { (state: any) -> () } = {}
local bagPill: Frame
local bagCountLabel: TextLabel
local bagFill: Frame
local goldLabel: TextLabel
local diamondLabel: TextLabel
-- Counters that are mid roll-up. While a label is in here, updateUI leaves its
-- text alone so the server state push cannot snap it straight to the total.
local countingUp: { [TextLabel]: boolean } = {}
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

local function addCloseX(button: GuiObject, color: Color3?): Frame
	local icon = Instance.new("Frame")
	icon.Name = "XIcon"
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.Size = UDim2.fromScale(0.44, 0.44)
	icon.BackgroundTransparency = 1
	icon.ZIndex = button.ZIndex + 1
	icon.Parent = button
	for _, rot in { 45, -45 } do
		local bar = Instance.new("Frame")
		bar.Name = "Bar"
		bar.AnchorPoint = Vector2.new(0.5, 0.5)
		bar.Position = UDim2.fromScale(0.5, 0.5)
		bar.Size = UDim2.new(1, 0, 0, 4)
		bar.BackgroundColor3 = color or Color3.fromRGB(255, 255, 255)
		bar.BorderSizePixel = 0
		bar.Rotation = rot
		bar.ZIndex = icon.ZIndex
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(1, 0)
		c.Parent = bar
		bar.Parent = icon
	end
	return icon
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

-- Currency + bag HUD ----------------------------------------------------------
-- A small gold coin drawn purely with UI primitives (no image asset), so it
-- always renders in-game regardless of emoji/font support.
local function buildCoinIcon(diameter: number, baseZ: number): GuiObject
	-- Prefer the uploaded gold-coin artwork if its asset ID has been filled in
	-- (see src/shared/Assets.luau); otherwise draw the coin from UI primitives so
	-- something always renders.
	if Assets.GoldCoin ~= "" then
		local img = Instance.new("ImageLabel")
		img.Size = UDim2.fromOffset(diameter, diameter)
		img.BackgroundTransparency = 1
		img.Image = Assets.GoldCoin
		img.ScaleType = Enum.ScaleType.Fit
		img.ZIndex = baseZ
		return img
	end

	local coin = Instance.new("Frame")
	coin.Size = UDim2.fromOffset(diameter, diameter)
	coin.BackgroundColor3 = Color3.fromRGB(245, 196, 72)
	coin.BorderSizePixel = 0
	coin.ZIndex = baseZ
	corner(coin, math.floor(diameter / 2))
	stroke(coin, math.max(2, math.floor(diameter / 12)), Color3.fromRGB(196, 142, 38), 0)

	local inner = Instance.new("Frame")
	inner.AnchorPoint = Vector2.new(0.5, 0.5)
	inner.Position = UDim2.fromScale(0.5, 0.5)
	inner.Size = UDim2.fromScale(0.6, 0.6)
	inner.BackgroundTransparency = 1
	inner.ZIndex = baseZ + 1
	corner(inner, math.floor(diameter / 2))
	stroke(inner, math.max(1, math.floor(diameter / 16)), Color3.fromRGB(255, 226, 150), 0.15)
	inner.Parent = coin

	local shine = Instance.new("Frame")
	shine.AnchorPoint = Vector2.new(0.5, 0.5)
	shine.Position = UDim2.fromScale(0.36, 0.33)
	shine.Size = UDim2.fromScale(0.2, 0.2)
	shine.BackgroundColor3 = Color3.fromRGB(255, 244, 214)
	shine.BackgroundTransparency = 0.1
	shine.ZIndex = baseZ + 2
	corner(shine, 999)
	shine.Parent = coin

	return coin
end

local function buildCurrency(gui: ScreenGui)
	-- Bag meter (top-center): how full your carry bag is, with a fill bar.
	local pill = Instance.new("Frame")
	pill.Name = "BagMeter"
	pill.AnchorPoint = Vector2.new(0.5, 0)
	pill.Position = UDim2.new(0.5, 0, 0, 18)
	pill.Size = UDim2.fromOffset(250, 58)
	pill.BackgroundColor3 = GREEN_DARK
	pill.ZIndex = 5
	corner(pill, 26)
	gradient(pill, Color3.fromRGB(104, 194, 98), GREEN_DARK, 90)
	stroke(pill, 3, Color3.fromRGB(255, 255, 255), 0.35)
	pill.Parent = gui
	bagPill = pill

	-- Backpack icon: show the uploaded artwork when its asset ID is set
	-- (src/shared/Assets.luau); otherwise fall back to a single emoji. Exactly ONE
	-- of these is ever created, so the new image never stacks over an old icon.
	if Assets.Backpack ~= "" then
		local icon = Instance.new("ImageLabel")
		icon.Name = "BagIcon"
		icon.BackgroundTransparency = 1
		icon.Size = UDim2.fromOffset(46, 46)
		icon.Position = UDim2.fromOffset(12, 6)
		icon.Image = Assets.Backpack
		icon.ScaleType = Enum.ScaleType.Fit
		icon.ZIndex = 7
		icon.Parent = pill
	else
		local iconFallback = Instance.new("TextLabel")
		iconFallback.Name = "BagIconFallback"
		iconFallback.BackgroundTransparency = 1
		iconFallback.Size = UDim2.fromOffset(46, 46)
		iconFallback.Position = UDim2.fromOffset(12, 6)
		iconFallback.Text = "\u{1F392}"
		iconFallback.TextScaled = true
		iconFallback.ZIndex = 6
		iconFallback.Parent = pill
	end

	bagCountLabel = Instance.new("TextLabel")
	bagCountLabel.BackgroundTransparency = 1
	bagCountLabel.Size = UDim2.new(1, -78, 0, 34)
	bagCountLabel.Position = UDim2.fromOffset(70, 3)
	bagCountLabel.Font = Enum.Font.FredokaOne
	bagCountLabel.Text = "0 / 25"
	bagCountLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	bagCountLabel.TextScaled = true
	bagCountLabel.TextXAlignment = Enum.TextXAlignment.Left
	bagCountLabel.ZIndex = 6
	local bcp = Instance.new("UIPadding")
	bcp.PaddingTop = UDim.new(0, 5)
	bcp.PaddingBottom = UDim.new(0, 5)
	bcp.PaddingLeft = UDim.new(0, 8)
	bcp.PaddingRight = UDim.new(0, 14)
	bcp.Parent = bagCountLabel
	bagCountLabel.Parent = pill

	-- Fill-bar track along the bottom edge.
	local track = Instance.new("Frame")
	track.Name = "Track"
	track.AnchorPoint = Vector2.new(0.5, 1)
	track.Position = UDim2.new(0.5, 0, 1, -8)
	track.Size = UDim2.new(1, -28, 0, 8)
	track.BackgroundColor3 = Color3.fromRGB(28, 46, 26)
	track.BackgroundTransparency = 0.25
	track.BorderSizePixel = 0
	track.ZIndex = 6
	corner(track, 4)
	track.Parent = pill

	bagFill = Instance.new("Frame")
	bagFill.Name = "Fill"
	bagFill.Size = UDim2.new(0, 0, 1, 0)
	bagFill.BackgroundColor3 = Color3.fromRGB(180, 240, 150)
	bagFill.BorderSizePixel = 0
	bagFill.ZIndex = 7
	corner(bagFill, 4)
	bagFill.Parent = track

	-- Gold and diamond counters flank the bag meter: gold to its left, diamond to
	-- its right. The bag meter is 250px wide and centered, so its edges sit 125px
	-- either side of screen center; we anchor each counter just beyond that.
	local function makeCounter(icon: string, tint: Color3, anchorX: number, offsetX: number): TextLabel
		local c = Instance.new("Frame")
		c.AnchorPoint = Vector2.new(anchorX, 0)
		c.Position = UDim2.new(0.5, offsetX, 0, 22)
		c.Size = UDim2.fromOffset(120, 44)
		c.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		c.ZIndex = 5
		corner(c, 22)
		stroke(c, 2, tint, 0.1)
		c.Parent = gui

		if icon == "COIN" then
			local coin = buildCoinIcon(28, 6)
			coin.AnchorPoint = Vector2.new(0.5, 0.5)
			coin.Position = UDim2.new(0, 27, 0.5, 0)
			coin.Parent = c
		elseif icon == "DIAMOND" and Assets.Diamond ~= "" then
			local img = Instance.new("ImageLabel")
			img.AnchorPoint = Vector2.new(0.5, 0.5)
			img.Position = UDim2.new(0, 27, 0.5, 0)
			img.Size = UDim2.fromOffset(30, 30)
			img.BackgroundTransparency = 1
			img.Image = Assets.Diamond
			img.ScaleType = Enum.ScaleType.Fit
			img.ZIndex = 6
			img.Parent = c
		else
			local badge = Instance.new("TextLabel")
			badge.BackgroundTransparency = 1
			badge.Size = UDim2.fromOffset(30, 44)
			badge.Position = UDim2.fromOffset(12, 0)
			badge.Text = icon
			badge.TextScaled = true
			badge.ZIndex = 6
			local ep = Instance.new("UIPadding")
			ep.PaddingTop = UDim.new(0, 10)
			ep.PaddingBottom = UDim.new(0, 10)
			ep.Parent = badge
			badge.Parent = c
		end

		local lbl = Instance.new("TextLabel")
		lbl.BackgroundTransparency = 1
		lbl.Size = UDim2.new(1, -50, 1, 0)
		lbl.Position = UDim2.fromOffset(46, 0)
		lbl.Font = Enum.Font.FredokaOne
		lbl.Text = "0"
		lbl.TextColor3 = INK
		lbl.TextScaled = true
		lbl.TextXAlignment = Enum.TextXAlignment.Left
		lbl.ZIndex = 6
		local lpad = Instance.new("UIPadding")
		lpad.PaddingTop = UDim.new(0, 10)
		lpad.PaddingBottom = UDim.new(0, 10)
		lpad.PaddingRight = UDim.new(0, 12)
		lpad.Parent = lbl
		lbl.Parent = c
		return lbl
	end

	-- gold: right edge 135px left of center; diamond: left edge 135px right of center.
	goldLabel = makeCounter("COIN", GOLD, 1, -135)
	diamondLabel = makeCounter(Assets.Diamond ~= "" and "DIAMOND" or "\u{1F48E}", DIAMOND, 0, 135)
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
	-- Cost display: a centered [coin][price] group with a fixed gap (UIListLayout
	-- Padding) so the coin never crowds the number. Hidden for FREE/MAX buttons.
	local costGroup = Instance.new("Frame")
	costGroup.Name = "CostGroup"
	costGroup.BackgroundTransparency = 1
	costGroup.AnchorPoint = Vector2.new(0.5, 0.5)
	costGroup.Position = UDim2.fromScale(0.5, 0.5)
	costGroup.Size = UDim2.fromScale(1, 1)
	costGroup.ZIndex = 13
	costGroup.Visible = false
	local costLayout = Instance.new("UIListLayout")
	costLayout.FillDirection = Enum.FillDirection.Horizontal
	costLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	costLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	costLayout.SortOrder = Enum.SortOrder.LayoutOrder
	costLayout.Padding = UDim.new(0, 8)
	costLayout.Parent = costGroup
	local buyCoin = buildCoinIcon(22, 13)
	buyCoin.LayoutOrder = 1
	buyCoin.Parent = costGroup
	local costLabel = Instance.new("TextLabel")
	costLabel.Name = "CostLabel"
	costLabel.LayoutOrder = 2
	costLabel.AutomaticSize = Enum.AutomaticSize.X
	costLabel.Size = UDim2.fromOffset(0, 30)
	costLabel.BackgroundTransparency = 1
	costLabel.Font = Enum.Font.FredokaOne
	costLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	costLabel.TextSize = 20
	costLabel.Text = "0"
	costLabel.ZIndex = 13
	costLabel.Parent = costGroup
	costGroup.Parent = buy
	buy.Parent = card
	buy.Activated:Connect(onBuy)

	local function update(state: any)
		local data = getData(state)
		nameLabel.Text = data.name
		descLabel.Text = data.desc
		levelLabel.Text = data.level
		if data.maxed then
			buy.Text = "MAX"
			buy.TextXAlignment = Enum.TextXAlignment.Center
			costGroup.Visible = false
			buy.BackgroundColor3 = LOCKED
			buy.AutoButtonColor = false
			buyStroke.Transparency = 0.7
		else
			local cost = data.cost or 0
			local afford = (state.gold or 0) >= cost
			if cost == 0 then
				buy.Text = "FREE"
				buy.TextXAlignment = Enum.TextXAlignment.Center
				costGroup.Visible = false
			else
				buy.Text = ""
				costLabel.Text = formatNumber(cost)
				costGroup.Visible = true
			end
			buy.BackgroundColor3 = afford and GREEN or LOCKED
			buyStroke.Transparency = afford and 0.4 or 0.7
		end
	end

	table.insert(cardUpdaters, update)
end

-- Shop modal ------------------------------------------------------------------
-- The Market is a tabbed modal. Each tab is its own ScrollingFrame page and only
-- the active page is visible. Adding a future section means adding one entry to
-- TAB_ORDER plus one builder call - nothing else in here has to change.
--
-- Sections whose systems have not shipped yet render an "empty state" card rather
-- than being hidden, so the shell is walkable end to end while the real content
-- lands one piece at a time.
local TAB_ORDER = { "upgrades", "tools", "swords", "mowers", "packs" }
local TAB_META: { [string]: { label: string, icon: string } } = {
	upgrades = { label = "Upgrades", icon = "\u{2728}" },
	tools = { label = "Tools", icon = "\u{2702}\u{FE0F}" },
	swords = { label = "Swords", icon = "\u{1F5E1}\u{FE0F}" },
	mowers = { label = "Mowers", icon = "\u{1F69C}" },
	packs = { label = "Packs", icon = "\u{1F392}" },
}

local pages: { [string]: ScrollingFrame } = {}
local tabButtons: { [string]: TextButton } = {}

-- Show one page, dim the rest.
local function selectTab(id: string)
	if not pages[id] then
		return
	end
	for tabId, page in pages do
		local on = tabId == id
		page.Visible = on
		local btn = tabButtons[tabId]
		if btn then
			TweenService:Create(btn, TweenInfo.new(0.12), {
				BackgroundColor3 = if on then Color3.fromRGB(255, 255, 255) else Color3.fromRGB(228, 224, 210),
			}):Play()
			btn.TextColor3 = if on then GREEN_DARK else Color3.fromRGB(140, 136, 124)
		end
	end
end

-- A scrolling page inside the modal body.
local function makePage(parent: Instance, id: string): ScrollingFrame
	local page = Instance.new("ScrollingFrame")
	page.Name = id .. "Page"
	page.Size = UDim2.fromScale(1, 1)
	page.BackgroundTransparency = 1
	page.BorderSizePixel = 0
	page.ScrollBarThickness = 6
	page.ScrollBarImageColor3 = GREEN_DARK
	page.CanvasSize = UDim2.new(0, 0, 0, 0)
	page.AutomaticCanvasSize = Enum.AutomaticSize.Y
	page.Visible = false
	page.ZIndex = 11
	padding(page, 16)
	page.Parent = parent

	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 12)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = page

	pages[id] = page
	return page
end

-- Small section label.
local function sectionHeader(parent: Instance, order: number, text: string)
	local h = Instance.new("TextLabel")
	h.BackgroundTransparency = 1
	h.Size = UDim2.new(1, 0, 0, 24)
	h.Font = Enum.Font.FredokaOne
	h.Text = text
	h.TextColor3 = INK
	h.TextXAlignment = Enum.TextXAlignment.Left
	h.TextSize = 18
	h.LayoutOrder = order
	h.ZIndex = 11
	h.Parent = parent
end

-- Placeholder for a section whose system has not shipped yet.
local function emptyState(parent: Instance, order: number, icon: string, title: string, body: string)
	local card = Instance.new("Frame")
	card.Size = UDim2.new(1, 0, 0, 136)
	card.BackgroundColor3 = Color3.fromRGB(248, 245, 236)
	card.LayoutOrder = order
	card.ZIndex = 11
	corner(card, 14)
	stroke(card, 2, Color3.fromRGB(226, 221, 206))
	card.Parent = parent

	local glyph = Instance.new("TextLabel")
	glyph.BackgroundTransparency = 1
	glyph.Position = UDim2.fromOffset(0, 14)
	glyph.Size = UDim2.new(1, 0, 0, 34)
	glyph.Font = Enum.Font.FredokaOne
	glyph.Text = icon
	glyph.TextSize = 30
	glyph.ZIndex = 12
	glyph.Parent = card

	local head = Instance.new("TextLabel")
	head.BackgroundTransparency = 1
	head.Position = UDim2.fromOffset(14, 54)
	head.Size = UDim2.new(1, -28, 0, 24)
	head.Font = Enum.Font.FredokaOne
	head.Text = title
	head.TextColor3 = INK
	head.TextSize = 18
	head.ZIndex = 12
	head.Parent = card

	local sub = Instance.new("TextLabel")
	sub.BackgroundTransparency = 1
	sub.Position = UDim2.fromOffset(16, 80)
	sub.Size = UDim2.new(1, -32, 0, 46)
	sub.Font = Enum.Font.Gotham
	sub.Text = body
	sub.TextColor3 = Color3.fromRGB(132, 128, 118)
	sub.TextSize = 13
	sub.TextWrapped = true
	sub.TextYAlignment = Enum.TextYAlignment.Top
	sub.ZIndex = 12
	sub.Parent = card
end

-- A read-only ladder row: marks an entry as owned, equipped, or locked.
local function ladderRow(
	parent: Instance,
	order: number,
	index: number,
	label: string,
	costText: string,
	getOwnedTier: (state: any) -> number
)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 40)
	row.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	row.LayoutOrder = order
	row.ZIndex = 11
	corner(row, 10)
	stroke(row, 2, Color3.fromRGB(230, 226, 212))
	row.Parent = parent

	local mark = Instance.new("TextLabel")
	mark.BackgroundTransparency = 1
	mark.Position = UDim2.fromOffset(12, 0)
	mark.Size = UDim2.fromOffset(26, 40)
	mark.Font = Enum.Font.FredokaOne
	mark.TextSize = 16
	mark.ZIndex = 12
	mark.Parent = row

	local name = Instance.new("TextLabel")
	name.BackgroundTransparency = 1
	name.Position = UDim2.fromOffset(42, 0)
	name.Size = UDim2.new(1, -146, 1, 0)
	name.Font = Enum.Font.FredokaOne
	name.Text = label
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextSize = 15
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.ZIndex = 12
	name.Parent = row

	local cost = Instance.new("TextLabel")
	cost.BackgroundTransparency = 1
	cost.AnchorPoint = Vector2.new(1, 0)
	cost.Position = UDim2.new(1, -12, 0, 0)
	cost.Size = UDim2.fromOffset(96, 40)
	cost.Font = Enum.Font.FredokaOne
	cost.TextXAlignment = Enum.TextXAlignment.Right
	cost.TextSize = 14
	cost.ZIndex = 12
	cost.Parent = row

	local function update(state: any)
		local owned = getOwnedTier(state)
		if index < owned then
			mark.Text = "\u{2713}"
			mark.TextColor3 = Color3.fromRGB(120, 190, 110)
			name.TextColor3 = Color3.fromRGB(150, 146, 136)
			cost.TextColor3 = Color3.fromRGB(180, 176, 166)
			cost.Text = "Owned"
		elseif index == owned then
			mark.Text = "\u{25C6}"
			mark.TextColor3 = GREEN_DARK
			name.TextColor3 = INK
			cost.TextColor3 = GREEN_DARK
			cost.Text = "Equipped"
		else
			mark.Text = "\u{1F512}"
			mark.TextColor3 = Color3.fromRGB(190, 186, 176)
			name.TextColor3 = Color3.fromRGB(150, 146, 136)
			cost.TextColor3 = Color3.fromRGB(150, 146, 136)
			cost.Text = costText
		end
	end

	update(latestState)
	table.insert(cardUpdaters, update)
end

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
	title.Parent = header

	local close = Instance.new("TextButton")
	close.AnchorPoint = Vector2.new(1, 0.5)
	close.Position = UDim2.new(1, -16, 0.5, 0)
	close.Size = UDim2.fromOffset(40, 40)
	close.BackgroundColor3 = Color3.fromRGB(220, 88, 78)
	close.Font = Enum.Font.FredokaOne
	close.Text = ""
	close.TextColor3 = Color3.fromRGB(255, 255, 255)
	close.TextSize = 22
	close.ZIndex = 13
	corner(close, 20)
	stroke(close, 2, Color3.fromRGB(255, 255, 255), 0.4)
	addCloseX(close)
	close.Parent = header
	close.Activated:Connect(function()
		UIController.CloseShop()
	end)

	-- Tab rail --------------------------------------------------------------
	-- Tabs are scale-sized (1/N each) so the rail can never overflow no matter how
	-- many sections we end up adding.
	local rail = Instance.new("Frame")
	rail.Name = "TabRail"
	rail.Position = UDim2.fromOffset(0, 66)
	rail.Size = UDim2.new(1, 0, 0, 46)
	rail.BackgroundTransparency = 1
	rail.ZIndex = 12
	rail.Parent = modal

	local railPad = Instance.new("UIPadding")
	railPad.PaddingLeft = UDim.new(0, 12)
	railPad.PaddingRight = UDim.new(0, 12)
	railPad.PaddingTop = UDim.new(0, 7)
	railPad.PaddingBottom = UDim.new(0, 5)
	railPad.Parent = rail

	local railList = Instance.new("UIListLayout")
	railList.FillDirection = Enum.FillDirection.Horizontal
	railList.Padding = UDim.new(0, 5)
	railList.SortOrder = Enum.SortOrder.LayoutOrder
	railList.Parent = rail

	local tabCount = #TAB_ORDER
	for i, id in TAB_ORDER do
		local meta = TAB_META[id]
		local btn = Instance.new("TextButton")
		btn.Name = id .. "Tab"
		-- 1/N of the rail, minus the gap this tab contributes.
		btn.Size = UDim2.new(1 / tabCount, -5, 1, 0)
		btn.BackgroundColor3 = Color3.fromRGB(228, 224, 210)
		btn.AutoButtonColor = false
		btn.Font = Enum.Font.FredokaOne
		btn.Text = meta.icon .. " " .. meta.label
		btn.TextColor3 = Color3.fromRGB(140, 136, 124)
		btn.TextSize = 12
		btn.TextTruncate = Enum.TextTruncate.AtEnd
		btn.LayoutOrder = i
		btn.ZIndex = 13
		corner(btn, 9)
		btn.Parent = rail
		tabButtons[id] = btn
		btn.Activated:Connect(function()
			selectTab(id)
		end)
	end

	-- Body: one page per tab, stacked and toggled ---------------------------
	local bodyHost = Instance.new("Frame")
	bodyHost.Name = "Body"
	bodyHost.Position = UDim2.fromOffset(0, 112)
	bodyHost.Size = UDim2.new(1, 0, 1, -112)
	bodyHost.BackgroundTransparency = 1
	bodyHost.ZIndex = 11
	bodyHost.Parent = modal

	-- UPGRADES: the Kingdom Skills ------------------------------------------
	local upgradesPage = makePage(bodyHost, "upgrades")
	sectionHeader(upgradesPage, 0, "Kingdom Skills")
	for i, skillName in SKILL_ORDER do
		local meta = SKILL_META[skillName]
		local def = GameConfig.SKILLS[skillName]
		buildCard(upgradesPage, i, meta.icon, Color3.fromRGB(224, 240, 210), function(state)
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

	-- TOOLS: buy the next tier, plus the full ladder for context ------------
	local toolsPage = makePage(bodyHost, "tools")
	sectionHeader(toolsPage, 0, "Next Tool")
	buildCard(toolsPage, 1, "\u{2702}\u{FE0F}", Color3.fromRGB(210, 235, 205), function(state)
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
		local desc
		if nextDef.favored == "all" then
			desc = "\u{2B50} Cuts every grass type with ease"
		elseif nextDef.favored then
			local g = GameConfig.GRASS_TYPES[nextDef.favored]
			desc = "Specialist \u{2022} excels at " .. (g and g.displayName or nextDef.favored)
		else
			desc = "All-rounder \u{2022} cut power " .. nextDef.bladesPerSwing
		end
		return {
			name = nextDef.name,
			desc = desc,
			level = "Owned: " .. (current and current.name or "-"),
			cost = nextDef.cost,
			maxed = false,
		}
	end, function()
		Remotes.Get("PurchaseUpgrade"):FireServer("tool")
	end)

	sectionHeader(toolsPage, 2, "The Full Ladder")
	for i, def in GameConfig.TOOL_TIERS do
		ladderRow(toolsPage, 2 + i, i, def.name, formatNumber(def.cost) .. "g", function(state)
			return state.toolTier or 1
		end)
	end

	-- SWORDS ----------------------------------------------------------------
	local swordsPage = makePage(bodyHost, "swords")
	sectionHeader(swordsPage, 0, "Swords")
	emptyState(
		swordsPage,
		1,
		"\u{1F5E1}\u{FE0F}",
		"The forge is cold",
		"Swords arrive alongside the monsters worth swinging them at. Eleven blades are planned, one per boss tier."
	)

	-- AUTO-MOWERS -----------------------------------------------------------
	local mowersPage = makePage(bodyHost, "mowers")
	sectionHeader(mowersPage, 0, "Auto-Mowers")
	emptyState(
		mowersPage,
		1,
		"\u{1F69C}",
		"Out for repairs",
		"Mowers are being rebuilt to drive out on their own, cut the nearest grass, and haul the clippings back to the Gardener."
	)

	-- BACKPACKS -------------------------------------------------------------
	-- The five zone packs are not in yet, so the working bag upgrade stays here
	-- until they replace it. Nothing purchasable is taken away in the meantime.
	local packsPage = makePage(bodyHost, "packs")
	sectionHeader(packsPage, 0, "Storage")
	buildCard(packsPage, 1, "\u{1F392}", Color3.fromRGB(214, 232, 244), function(state)
		local tier = state.bagTier or 1
		local current = GameConfig.BAG_TIERS[tier]
		local nextDef = GameConfig.BAG_TIERS[tier + 1]
		if not nextDef then
			return {
				name = "Clipping Bag",
				desc = "The biggest bag in the kingdom!",
				level = "Capacity: " .. (current and current.capacity or 0),
				maxed = true,
			}
		end
		return {
			name = "Bigger Bag",
			desc = "Carry " .. current.capacity .. " \u{2192} " .. nextDef.capacity .. " clippings",
			level = "Tier " .. tier .. " / " .. #GameConfig.BAG_TIERS,
			cost = nextDef.cost,
			maxed = false,
		}
	end, function()
		Remotes.Get("PurchaseUpgrade"):FireServer("bag")
	end)

	sectionHeader(packsPage, 2, "Zone Packs")
	emptyState(
		packsPage,
		3,
		"\u{1F9F5}",
		"Five packs on the way",
		"One backpack per zone, each with its own model on your back and its own upgrade track. These will replace the single bag above."
	)

	selectTab("upgrades")
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
	local clippings = state.clippings or 0
	local capacity = state.bagCapacity or 0

	if bagCountLabel then
		bagCountLabel.Text = formatNumber(clippings) .. " / " .. formatNumber(capacity)
	end
	if bagFill then
		local frac = (capacity > 0) and math.clamp(clippings / capacity, 0, 1) or 0
		TweenService:Create(bagFill, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = UDim2.new(frac, 0, 1, 0),
		}):Play()
		local full = capacity > 0 and clippings >= capacity
		bagFill.BackgroundColor3 = full and Color3.fromRGB(255, 120, 96) or Color3.fromRGB(180, 240, 150)
	end
	if goldLabel and not countingUp[goldLabel] then
		goldLabel.Text = formatNumber(state.gold or 0)
	end
	if diamondLabel and not countingUp[diamondLabel] then
		diamondLabel.Text = formatNumber(state.diamonds or 0)
	end
	if bagPill and lastShown >= 0 and clippings ~= lastShown then
		-- little pop when the bag amount changes
		bagPill.Size = UDim2.fromOffset(236, 54)
		TweenService:Create(bagPill, TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Size = UDim2.fromOffset(250, 58),
		}):Play()
	end
	lastShown = clippings

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

-- Walk onto the Gardener pad to auto-deposit the whole bag. We fire once per entry
-- (reset when you step off) so a single walk-in banks everything, not every frame.
local function startGardenerWatch()
	local inside = false
	RunService.Heartbeat:Connect(function()
		local stand = Workspace:FindFirstChild("Gardener")
		local zone = stand and stand:FindFirstChild("GardenerZone") :: BasePart?
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not zone or not root then
			inside = false
			return
		end
		local delta = root.Position - zone.Position
		local horizontal = math.sqrt(delta.X * delta.X + delta.Z * delta.Z)
		if horizontal <= GameConfig.GARDENER_ZONE_RADIUS then
			if not inside then
				inside = true
				Remotes.Get("RequestDeposit"):FireServer()
			end
		else
			inside = false
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

-- If the shop model ships with a ProximityPrompt, let "hold to interact" open the
-- menu too (the walk-in zone already opens it automatically).
local function hookShopPrompt()
	task.spawn(function()
		for _ = 1, 60 do
			local shop = Workspace:FindFirstChild("Shop")
			local prompt = shop and shop:FindFirstChildWhichIsA("ProximityPrompt", true)
			if prompt then
				prompt.Triggered:Connect(function()
					UIController.OpenShop(false)
				end)
				return
			end
			task.wait(0.5)
		end
	end)
end

-- District reveal banner ------------------------------------------------------
-- Fired by DistrictService when a district (or the whole village) is cleared.
-- Slides a celebratory banner down from the top, holds, then slides away.
local function showBanner(title: string, subtitle: string?)
	local playerGui = player:FindFirstChild("PlayerGui")
	local gui = playerGui and playerGui:FindFirstChild("HUD")
	if not gui then
		return
	end

	local banner = Instance.new("Frame")
	banner.Name = "DistrictBanner"
	banner.AnchorPoint = Vector2.new(0.5, 0)
	banner.Position = UDim2.new(0.5, 0, 0, -100)
	banner.Size = UDim2.fromOffset(460, 84)
	banner.BackgroundColor3 = GREEN_DARK
	banner.ZIndex = 20
	corner(banner, 16)
	gradient(banner, GREEN, GREEN_DARK, 90)
	stroke(banner, 3, Color3.fromRGB(255, 255, 255), 0.25)
	shadow(banner, 20)
	banner.Parent = gui

	local titleLabel = Instance.new("TextLabel")
	titleLabel.BackgroundTransparency = 1
	titleLabel.Position = UDim2.fromOffset(18, 12)
	titleLabel.Size = UDim2.new(1, -36, 0, 36)
	titleLabel.Font = Enum.Font.FredokaOne
	titleLabel.Text = title
	titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	titleLabel.TextScaled = true
	titleLabel.TextXAlignment = Enum.TextXAlignment.Center
	titleLabel.ZIndex = 21
	titleLabel.Parent = banner

	local subLabel = Instance.new("TextLabel")
	subLabel.BackgroundTransparency = 1
	subLabel.Position = UDim2.fromOffset(18, 50)
	subLabel.Size = UDim2.new(1, -36, 0, 22)
	subLabel.Font = Enum.Font.GothamMedium
	subLabel.Text = subtitle or ""
	subLabel.TextColor3 = Color3.fromRGB(236, 248, 232)
	subLabel.TextScaled = true
	subLabel.TextXAlignment = Enum.TextXAlignment.Center
	subLabel.ZIndex = 21
	subLabel.Parent = banner

	TweenService:Create(banner, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.5, 0, 0, 92),
	}):Play()
	task.delay(3.6, function()
		local out = TweenService:Create(banner, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Position = UDim2.new(0.5, 0, 0, -100),
		})
		out.Completed:Connect(function()
			banner:Destroy()
		end)
		out:Play()
	end)
end

-- Floating "+N" popups -------------------------------------------------------
-- Two flavors, both parented to the HUD:
--   * clipping pickups pop in at a random spot in the UPPER HALF of the screen
--     and drift up as they fade ("+N clippings")
--   * deposit chips spawn near screen-center and FLY to the gold / diamond
--     counter, one per unit banked (batched when the amount is large)
local function hud(): ScreenGui?
	local playerGui = player:FindFirstChild("PlayerGui")
	return (playerGui and playerGui:FindFirstChild("HUD")) :: ScreenGui?
end

-- Remember each counter's TRUE resting size the first time it bumps. Deposits
-- fire one chip (and one bump) per unit banked, so reading frame.Size live let a
-- second bump capture an already-enlarged size as "base" -- the counter then grew
-- with every deposit and never shrank back. Anchoring to a stored base fixes it.
local counterBaseSize: { [Instance]: UDim2 } = {}
local function bumpCounter(frame: GuiObject)
	local base = counterBaseSize[frame]
	if not base then
		base = frame.Size
		counterBaseSize[frame] = base
	end
	TweenService:Create(frame, TweenInfo.new(0.08, Enum.EasingStyle.Quad), {
		Size = base + UDim2.fromOffset(8, 8),
	}):Play()
	task.delay(0.09, function()
		TweenService:Create(frame, TweenInfo.new(0.14, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Size = base,
		}):Play()
	end)
end

-- A "+N clippings" popup at a random spot in the upper half of the screen.
local function clippingPopup(amount: number, isCrit: boolean)
	local gui = hud()
	if not gui then
		return
	end
	local px = 0.22 + math.random() * 0.56
	local py = 0.16 + math.random() * 0.26
	local lbl = Instance.new("TextLabel")
	lbl.AnchorPoint = Vector2.new(0.5, 0.5)
	lbl.BackgroundTransparency = 1
	lbl.Size = UDim2.fromOffset(240, 40)
	lbl.Position = UDim2.fromScale(px, py)
	lbl.Font = Enum.Font.FredokaOne
	lbl.TextScaled = false
	lbl.TextSize = if isCrit then 30 else 24
	lbl.Text = (if isCrit then "\u{1F31F} +" else "+") .. formatNumber(amount) .. " clippings"
	lbl.TextColor3 = if isCrit then GOLD else Color3.fromRGB(150, 235, 120)
	lbl.ZIndex = 30
	local s = Instance.new("UIStroke")
	s.Thickness = 2.5
	s.Color = Color3.fromRGB(28, 40, 24)
	s.Parent = lbl
	lbl.Parent = gui

	TweenService:Create(lbl, TweenInfo.new(0.85, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.new(px, 0, py, -64),
		TextTransparency = 1,
	}):Play()
	TweenService:Create(s, TweenInfo.new(0.85), { Transparency = 1 }):Play()
	task.delay(0.95, function()
		if lbl.Parent then
			lbl:Destroy()
		end
	end)
end

-- One "+N <emoji>" chip that flies from `startAbs` (pixels) into the given counter.
local function flyChip(gui: ScreenGui, targetLabel: TextLabel, text: string, color: Color3, startAbs: Vector2, delay: number, showCoin: boolean?, onArrive: (() -> ())?)
	local chip = Instance.new("TextLabel")
	chip.AnchorPoint = Vector2.new(0.5, 0.5)
	chip.BackgroundTransparency = 1
	chip.Size = UDim2.fromOffset(96, 30)
	chip.Font = Enum.Font.FredokaOne
	chip.TextSize = 20
	chip.Text = text
	chip.TextColor3 = color
	chip.TextTransparency = 1
	chip.ZIndex = 40
	chip.Position = UDim2.fromOffset(startAbs.X, startAbs.Y)
	local s = Instance.new("UIStroke")
	s.Thickness = 2
	s.Color = Color3.fromRGB(28, 40, 24)
	s.Transparency = 1
	s.Parent = chip
	if showCoin then
		local coin = buildCoinIcon(18, 41)
		coin.AnchorPoint = Vector2.new(0.5, 0.5)
		coin.Position = UDim2.new(0.5, -20, 0.5, 0)
		coin.Parent = chip
	end
	chip.Parent = gui

	task.delay(delay, function()
		if not chip.Parent then
			return
		end
		local target = targetLabel.Parent :: GuiObject
		local center = target.AbsolutePosition + target.AbsoluteSize / 2
		TweenService:Create(chip, TweenInfo.new(0.12), { TextTransparency = 0 }):Play()
		TweenService:Create(s, TweenInfo.new(0.12), { Transparency = 0 }):Play()
		local flyTime = 0.55
		local move = TweenService:Create(chip, TweenInfo.new(flyTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Position = UDim2.fromOffset(center.X, center.Y),
			Size = UDim2.fromOffset(60, 20),
		})
		move.Completed:Connect(function()
			if chip.Parent then
				chip:Destroy()
			end
			bumpCounter(target)
			if onArrive then
				onArrive()
			end
		end)
		move:Play()
		task.delay(flyTime - 0.12, function()
			if chip.Parent then
				TweenService:Create(chip, TweenInfo.new(0.14), { TextTransparency = 1 }):Play()
				TweenService:Create(s, TweenInfo.new(0.14), { Transparency = 1 }):Play()
			end
		end)
	end)
end

-- Spawn a burst of counter-bound chips for a banked amount and roll the counter up
-- in step with them, instead of snapping to the new total the moment the deposit
-- lands. Each chip carries a share of the amount and adds it on arrival.
local function spawnDepositChips(
	gui: ScreenGui,
	amount: number,
	targetLabel: TextLabel,
	emoji: string,
	color: Color3,
	useCoin: boolean?,
	getTotal: (() -> number)?
)
	if amount <= 0 or not targetLabel then
		return
	end
	local vp = gui.AbsoluteSize
	local MAX_CHIPS = 20
	local STAGGER = 0.035
	local chips = math.min(amount, MAX_CHIPS)

	-- Split the amount into per-chip shares that sum to exactly `amount`, so the
	-- ticking counter can never drift away from the real total.
	local chunks: { number } = {}
	local share = math.floor(amount / chips)
	local remainder = amount - share * chips
	for i = 1, chips do
		chunks[i] = share + (if i <= remainder then 1 else 0)
	end

	-- Roll the counter back to its pre-deposit value, then climb as chips land.
	local final = if getTotal then getTotal() else amount
	local running = final - amount
	countingUp[targetLabel] = true
	targetLabel.Text = formatNumber(running)

	local landed = 0
	local settled = false
	local function settle()
		if settled then
			return
		end
		settled = true
		countingUp[targetLabel] = nil
		-- Snap to the authoritative total in case rounding or an early-destroyed chip
		-- left the running tally short.
		targetLabel.Text = formatNumber(if getTotal then getTotal() else final)
	end

	for i = 1, chips do
		local shown = chunks[i]
		local startAbs = Vector2.new(
			vp.X * (0.40 + math.random() * 0.20),
			vp.Y * (0.30 + math.random() * 0.16)
		)
		local label = if useCoin then "+" .. shown else "+" .. shown .. " " .. emoji
		flyChip(gui, targetLabel, label, color, startAbs, (i - 1) * STAGGER, useCoin, function()
			running += shown
			landed += 1
			if not settled then
				targetLabel.Text = formatNumber(running)
			end
			if landed >= chips then
				settle()
			end
		end)
	end

	-- Safety net: never leave the counter stuck on a rolled-back number if a chip
	-- gets destroyed before it can report in.
	task.delay(chips * STAGGER + 2, settle)
end

function UIController.Start()
	Remotes.Get("StateChanged").OnClientEvent:Connect(updateUI)
	Remotes.Get("DistrictCleared").OnClientEvent:Connect(showBanner)
	Remotes.Get("BagFull").OnClientEvent:Connect(function()
		showBanner("\u{1F392} Bag Full!", "Head to the Gardener to deposit your clippings")
	end)
	Remotes.Get("ClippingCollected").OnClientEvent:Connect(function(_position, amount, isCrit)
		clippingPopup(amount or 0, isCrit or false)
	end)
	Remotes.Get("Deposited").OnClientEvent:Connect(function(summary)
		summary = summary or {}
		local gui = hud()
		if not gui then
			return
		end
		-- Instead of a single summary banner, fly a chip to the gold counter for each
		-- gold banked and to the diamond counter for each diamond.
		spawnDepositChips(gui, summary.gold or 0, goldLabel, "", GOLD, true, function()
			return latestState.gold or 0
		end)
		spawnDepositChips(gui, summary.diamonds or 0, diamondLabel, "\u{1F48E}", DIAMOND, false, function()
			return latestState.diamonds or 0
		end)
	end)
	Remotes.Get("RequestState"):FireServer()
	startZoneWatch()
	startGardenerWatch()
	hookShopPrompt()
end

return UIController
