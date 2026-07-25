--!strict
-- AutoMowerController: the client-side Auto-Mowers panel. A bottom-left button
-- opens a board listing the 5 auto-mowers; each card lets you BUY it (gold +
-- diamonds) once your zone is unlocked, then DEPLOY / RECALL it. Deployed mowers
-- show a live storage bar that fills until the server auto-banks it to gold. A
-- small toast pops whenever a mower banks.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)

local AutoMowerController = {}

local player = Players.LocalPlayer

-- Palette (matches the HUD / Quest Board) ------------------------------------
local CREAM = Color3.fromRGB(247, 244, 234)
local PANEL = Color3.fromRGB(255, 253, 247)
local INK = Color3.fromRGB(54, 62, 48)
local SUBTLE = Color3.fromRGB(120, 128, 112)
local GREEN = Color3.fromRGB(88, 178, 84)
local GREEN_DARK = Color3.fromRGB(58, 138, 64)
local LOCKED = Color3.fromRGB(168, 172, 162)
local GOLD = Color3.fromRGB(240, 190, 70)
local DIAMOND = Color3.fromRGB(96, 196, 224)
local HEADER = Color3.fromRGB(70, 96, 60)
local RED = Color3.fromRGB(226, 92, 84)

-- State -----------------------------------------------------------------------
local gui: ScreenGui
local backdrop: TextButton
local board: Frame
local listFrame: ScrollingFrame
local toastHolder: Frame
local isOpen = false
local latest: any = nil

-- Helpers ---------------------------------------------------------------------
local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
	return c
end

local function stroke(parent: Instance, thickness: number, col: Color3, transparency: number?)
	local s = Instance.new("UIStroke")
	s.Thickness = thickness
	s.Color = col
	s.Transparency = transparency or 0
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

local function formatNumber(n: number): string
	local rounded = math.floor(n + 0.5)
	local s = tostring(rounded)
	local out = ""
	local count = 0
	for i = #s, 1, -1 do
		out = string.sub(s, i, i) .. out
		count += 1
		if count % 3 == 0 and i > 1 then
			out = "," .. out
		end
	end
	return out
end

local function drawCloseX(button: TextButton)
	local xIcon = Instance.new("Frame")
	xIcon.Name = "XIcon"
	xIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	xIcon.Position = UDim2.fromScale(0.5, 0.5)
	xIcon.Size = UDim2.fromScale(0.44, 0.44)
	xIcon.BackgroundTransparency = 1
	xIcon.ZIndex = button.ZIndex + 1
	xIcon.Parent = button
	for _, rot in { 45, -45 } do
		local bar = Instance.new("Frame")
		bar.AnchorPoint = Vector2.new(0.5, 0.5)
		bar.Position = UDim2.fromScale(0.5, 0.5)
		bar.Size = UDim2.new(1, 0, 0, 4)
		bar.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		bar.BorderSizePixel = 0
		bar.Rotation = rot
		bar.ZIndex = xIcon.ZIndex
		local bc = Instance.new("UICorner")
		bc.CornerRadius = UDim.new(1, 0)
		bc.Parent = bar
		bar.Parent = xIcon
	end
end

-- Build the static shell once -------------------------------------------------
local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "AutoMowers"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 19
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = player:WaitForChild("PlayerGui")

	-- Open button (bottom-left, clear of the right-side shop button).
	local openBtn = Instance.new("TextButton")
	openBtn.Name = "OpenButton"
	openBtn.AnchorPoint = Vector2.new(0, 1)
	openBtn.Position = UDim2.new(0, 20, 1, -20)
	openBtn.Size = UDim2.new(0, 158, 0, 46)
	openBtn.BackgroundColor3 = GREEN
	openBtn.Font = Enum.Font.FredokaOne
	openBtn.Text = "\u{1F69C} Mowers"
	openBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	openBtn.TextSize = 22
	openBtn.Parent = gui
	corner(openBtn, 12)
	stroke(openBtn, 2, GREEN_DARK)
	openBtn.Activated:Connect(function()
		AutoMowerController.Toggle()
	end)

	backdrop = Instance.new("TextButton")
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.new(1, 0, 1, 0)
	backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	backdrop.BackgroundTransparency = 0.45
	backdrop.Text = ""
	backdrop.AutoButtonColor = false
	backdrop.Visible = false
	backdrop.Parent = gui
	backdrop.Activated:Connect(function()
		AutoMowerController.Close()
	end)

	board = Instance.new("Frame")
	board.Name = "Board"
	board.AnchorPoint = Vector2.new(0.5, 0.5)
	board.Position = UDim2.new(0.5, 0, 0.5, 0)
	board.Size = UDim2.new(0, 560, 0, 560)
	board.BackgroundColor3 = CREAM
	board.Visible = false
	board.Parent = gui
	corner(board, 20)
	stroke(board, 3, Color3.fromRGB(214, 208, 190))

	local header = Instance.new("Frame")
	header.Size = UDim2.new(1, 0, 0, 78)
	header.BackgroundColor3 = HEADER
	header.Parent = board
	corner(header, 20)
	local headerFix = Instance.new("Frame")
	headerFix.Size = UDim2.new(1, 0, 0.5, 0)
	headerFix.Position = UDim2.new(0, 0, 0.5, 0)
	headerFix.BackgroundColor3 = HEADER
	headerFix.BorderSizePixel = 0
	headerFix.Parent = header

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.new(0, 22, 0, 12)
	title.Size = UDim2.new(1, -90, 0, 34)
	title.Font = Enum.Font.FredokaOne
	title.Text = "Auto-Mowers"
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextScaled = true
	title.Parent = header

	local subtitle = Instance.new("TextLabel")
	subtitle.BackgroundTransparency = 1
	subtitle.Position = UDim2.new(0, 24, 0, 46)
	subtitle.Size = UDim2.new(1, -90, 0, 20)
	subtitle.Font = Enum.Font.GothamMedium
	subtitle.Text = "Deploy a mower to earn gold while you play"
	subtitle.TextColor3 = Color3.fromRGB(210, 226, 200)
	subtitle.TextXAlignment = Enum.TextXAlignment.Left
	subtitle.TextScaled = true
	subtitle.Parent = header

	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "Close"
	closeBtn.AnchorPoint = Vector2.new(1, 0.5)
	closeBtn.Position = UDim2.new(1, -18, 0, 39)
	closeBtn.Size = UDim2.new(0, 40, 0, 40)
	closeBtn.BackgroundColor3 = RED
	closeBtn.Text = ""
	closeBtn.Parent = header
	corner(closeBtn, 12)
	drawCloseX(closeBtn)
	closeBtn.Activated:Connect(function()
		AutoMowerController.Close()
	end)

	listFrame = Instance.new("ScrollingFrame")
	listFrame.Name = "List"
	listFrame.Position = UDim2.new(0, 14, 0, 90)
	listFrame.Size = UDim2.new(1, -28, 1, -104)
	listFrame.BackgroundTransparency = 1
	listFrame.BorderSizePixel = 0
	listFrame.ScrollBarThickness = 8
	listFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	listFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	listFrame.Parent = board

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 10)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = listFrame
	local pad = Instance.new("UIPadding")
	pad.PaddingRight = UDim.new(0, 6)
	pad.PaddingBottom = UDim.new(0, 6)
	pad.Parent = listFrame

	toastHolder = Instance.new("Frame")
	toastHolder.Name = "Toasts"
	toastHolder.AnchorPoint = Vector2.new(0.5, 1)
	toastHolder.Position = UDim2.new(0.5, 0, 1, -80)
	toastHolder.Size = UDim2.new(0, 360, 0, 0)
	toastHolder.BackgroundTransparency = 1
	toastHolder.Parent = gui
	local toastLayout = Instance.new("UIListLayout")
	toastLayout.Padding = UDim.new(0, 6)
	toastLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	toastLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	toastLayout.SortOrder = Enum.SortOrder.LayoutOrder
	toastLayout.Parent = toastHolder
end

-- Card builder ----------------------------------------------------------------
local function buildCard(mower: any, order: number, currency: { gold: number, diamonds: number })
	local card = Instance.new("Frame")
	card.Size = UDim2.new(1, 0, 0, 116)
	card.BackgroundColor3 = PANEL
	card.LayoutOrder = order
	corner(card, 14)
	stroke(card, 2, Color3.fromRGB(226, 220, 202))

	local swatch = Instance.new("Frame")
	swatch.Size = UDim2.new(0, 8, 1, -20)
	swatch.Position = UDim2.new(0, 12, 0, 10)
	swatch.BackgroundColor3 = Color3.fromRGB(mower.bodyColorR or 120, mower.bodyColorG or 196, mower.bodyColorB or 92)
	swatch.BorderSizePixel = 0
	corner(swatch, 4)
	swatch.Parent = card

	local name = Instance.new("TextLabel")
	name.BackgroundTransparency = 1
	name.Position = UDim2.new(0, 30, 0, 10)
	name.Size = UDim2.new(1, -140, 0, 24)
	name.Font = Enum.Font.FredokaOne
	name.Text = mower.name
	name.TextColor3 = INK
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextScaled = true
	name.Parent = card

	local info = Instance.new("TextLabel")
	info.BackgroundTransparency = 1
	info.Position = UDim2.new(0, 30, 0, 36)
	info.Size = UDim2.new(1, -140, 0, 18)
	info.Font = Enum.Font.Gotham
	info.Text = mower.desc .. "  \u{00B7}  +" .. formatNumber(mower.ratePerSec) .. "/s"
	info.TextColor3 = SUBTLE
	info.TextXAlignment = Enum.TextXAlignment.Left
	info.TextScaled = true
	info.Parent = card

	-- Storage bar (only meaningful when deployed).
	local barBg = Instance.new("Frame")
	barBg.Position = UDim2.new(0, 30, 0, 62)
	barBg.Size = UDim2.new(1, -170, 0, 14)
	barBg.BackgroundColor3 = Color3.fromRGB(232, 230, 220)
	barBg.BorderSizePixel = 0
	corner(barBg, 7)
	barBg.Parent = card

	local pct = math.clamp(mower.storage / math.max(1, mower.storageCap), 0, 1)
	local fill = Instance.new("Frame")
	fill.Size = UDim2.new(pct, 0, 1, 0)
	fill.BackgroundColor3 = GREEN
	fill.BorderSizePixel = 0
	corner(fill, 7)
	fill.Parent = barBg

	local barText = Instance.new("TextLabel")
	barText.BackgroundTransparency = 1
	barText.Position = UDim2.new(0, 30, 0, 80)
	barText.Size = UDim2.new(1, -170, 0, 18)
	barText.Font = Enum.Font.GothamMedium
	barText.TextXAlignment = Enum.TextXAlignment.Left
	barText.TextScaled = true
	barText.TextColor3 = SUBTLE
	if mower.deployed then
		barText.Text = "Storage " .. formatNumber(mower.storage) .. " / " .. formatNumber(mower.storageCap) .. " \u{2192} auto-banks to gold"
	else
		barBg.Visible = false
		barText.Text = "Not deployed"
	end
	barText.Parent = card

	-- Action button (Buy / Deploy / Recall / Locked).
	local action = Instance.new("TextButton")
	action.AnchorPoint = Vector2.new(1, 0.5)
	action.Position = UDim2.new(1, -14, 0.5, 0)
	action.Size = UDim2.new(0, 118, 0, 74)
	action.Font = Enum.Font.FredokaOne
	action.TextColor3 = Color3.fromRGB(255, 255, 255)
	action.TextScaled = true
	action.AutoButtonColor = true
	corner(action, 12)
	action.Parent = card

	local actionPad = Instance.new("UIPadding")
	actionPad.PaddingLeft = UDim.new(0, 8)
	actionPad.PaddingRight = UDim.new(0, 8)
	actionPad.PaddingTop = UDim.new(0, 8)
	actionPad.PaddingBottom = UDim.new(0, 8)
	actionPad.Parent = action

	if not mower.unlocked then
		action.BackgroundColor3 = LOCKED
		action.Text = "Locked\n(reach " .. mower.zone .. ")"
		action.AutoButtonColor = false
		action.Active = false
	elseif not mower.owned then
		local canAfford = currency.gold >= mower.goldCost and currency.diamonds >= mower.diamondCost
		action.BackgroundColor3 = if canAfford then GOLD else LOCKED
		action.TextColor3 = if canAfford then INK else Color3.fromRGB(240, 240, 236)
		action.Text = formatNumber(mower.goldCost) .. "g\n+ " .. formatNumber(mower.diamondCost) .. " \u{1F48E}"
		action.Activated:Connect(function()
			Remotes.Get("PurchaseAutoMower"):FireServer(mower.key)
		end)
	elseif mower.deployed then
		action.BackgroundColor3 = RED
		action.Text = "Recall"
		action.Activated:Connect(function()
			Remotes.Get("ToggleAutoMower"):FireServer(mower.key)
		end)
	else
		action.BackgroundColor3 = GREEN
		action.Text = "Deploy"
		action.Activated:Connect(function()
			Remotes.Get("ToggleAutoMower"):FireServer(mower.key)
		end)
	end

	card.Parent = listFrame
end

local function render()
	if not latest then
		return
	end
	for _, child in listFrame:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local currency = { gold = latest.gold or 0, diamonds = latest.diamonds or 0 }
	for i, mower in ipairs(latest.mowers) do
		buildCard(mower, i, currency)
	end
end

-- Toast when a mower banks -----------------------------------------------------
local function showToast(text: string)
	local toast = Instance.new("Frame")
	toast.Size = UDim2.new(1, 0, 0, 40)
	toast.BackgroundColor3 = GREEN_DARK
	corner(toast, 10)
	toast.Parent = toastHolder

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, -16, 1, 0)
	label.Position = UDim2.new(0, 8, 0, 0)
	label.Font = Enum.Font.FredokaOne
	label.Text = text
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextScaled = true
	label.Parent = toast

	task.delay(3, function()
		toast:Destroy()
	end)
end

-- Public API ------------------------------------------------------------------
function AutoMowerController.Open()
	isOpen = true
	backdrop.Visible = true
	board.Visible = true
	Remotes.Get("RequestAutoMowers"):FireServer()
end

function AutoMowerController.Close()
	isOpen = false
	backdrop.Visible = false
	board.Visible = false
end

function AutoMowerController.Toggle()
	if isOpen then
		AutoMowerController.Close()
	else
		AutoMowerController.Open()
	end
end

function AutoMowerController.Init()
	build()

	Remotes.Get("AutoMowerState").OnClientEvent:Connect(function(state)
		latest = state
		if isOpen then
			render()
		end
	end)

	Remotes.Get("AutoMowerBanked").OnClientEvent:Connect(function(payload)
		showToast("\u{1F69C} " .. tostring(payload.name) .. " banked +" .. formatNumber(payload.gold or 0) .. "g")
	end)
end

function AutoMowerController.Start()
	-- Ask once so deployed mowers respawn on rejoin even before the panel opens.
	task.wait(1)
	Remotes.Get("RequestAutoMowers"):FireServer()
end

return AutoMowerController
