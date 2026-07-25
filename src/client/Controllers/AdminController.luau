--!strict
-- AdminController: an in-game Admin panel for testers. A small button (top-left)
-- opens a panel where you can grant yourself any amount of gold or diamonds, plus
-- quick-add chips -- so you never have to grind resources to test a feature.
--
-- The button + panel only appear for usernames listed in GameConfig.ADMINS, and
-- the server re-validates every grant (see AdminService), so this is safe to ship.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local AdminController = {}

local player = Players.LocalPlayer

-- Palette (matches the HUD / other panels) -----------------------------------
local PANEL = Color3.fromRGB(255, 253, 247)
local INK = Color3.fromRGB(54, 62, 48)
local SUBTLE = Color3.fromRGB(120, 128, 112)
local GREEN = Color3.fromRGB(88, 178, 84)
local GOLD = Color3.fromRGB(240, 190, 70)
local DIAMOND = Color3.fromRGB(96, 196, 224)
local HEADER = Color3.fromRGB(70, 96, 60)
local FIELD = Color3.fromRGB(238, 240, 232)
local RED = Color3.fromRGB(226, 92, 84)
local WHITE = Color3.fromRGB(255, 255, 255)

local gui: ScreenGui
local panel: Frame
local isOpen = false

local function isAdmin(): boolean
	for _, name in GameConfig.ADMINS do
		if name == player.Name then
			return true
		end
	end
	return false
end

-- Helpers ---------------------------------------------------------------------
local function corner(inst: Instance, r: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = inst
end

local function stroke(inst: Instance, thickness: number, colr: Color3, transparency: number)
	local s = Instance.new("UIStroke")
	s.Thickness = thickness
	s.Color = colr
	s.Transparency = transparency
	s.Parent = inst
end

local function shortNum(n: number): string
	if n >= 1000000 then
		return string.format("%gM", n / 1000000)
	elseif n >= 1000 then
		return string.format("%gK", n / 1000)
	end
	return tostring(n)
end

local function grant(gold: number, diamonds: number)
	Remotes.Get("AdminGrantCurrency"):FireServer(gold, diamonds)
end

local function buildChip(parent: Instance, order: number, amount: number, onClick: () -> ())
	local b = Instance.new("TextButton")
	b.AutoButtonColor = true
	b.LayoutOrder = order
	b.Size = UDim2.fromOffset(66, 30)
	b.BackgroundColor3 = FIELD
	b.Font = Enum.Font.FredokaOne
	b.TextSize = 14
	b.TextColor3 = INK
	b.Text = "+" .. shortNum(amount)
	corner(b, 8)
	b.Parent = parent
	b.Activated:Connect(onClick)
	return b
end

local function buildSection(parent: Instance, order: number, title: string, accent: Color3, quicks: { number }, onGive: (number) -> ())
	local sec = Instance.new("Frame")
	sec.LayoutOrder = order
	sec.BackgroundTransparency = 1
	sec.Size = UDim2.new(1, 0, 0, 108)
	sec.Parent = parent

	local head = Instance.new("TextLabel")
	head.BackgroundTransparency = 1
	head.Size = UDim2.new(1, 0, 0, 22)
	head.Font = Enum.Font.FredokaOne
	head.TextSize = 16
	head.TextXAlignment = Enum.TextXAlignment.Left
	head.TextColor3 = accent
	head.Text = title
	head.Parent = sec

	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Position = UDim2.fromOffset(0, 26)
	row.Size = UDim2.new(1, 0, 0, 34)
	row.Parent = sec

	local box = Instance.new("TextBox")
	box.Size = UDim2.new(1, -104, 1, 0)
	box.BackgroundColor3 = FIELD
	box.Font = Enum.Font.FredokaOne
	box.TextSize = 16
	box.TextColor3 = INK
	box.PlaceholderText = "Amount..."
	box.PlaceholderColor3 = SUBTLE
	box.ClearTextOnFocus = false
	box.Text = ""
	box.TextXAlignment = Enum.TextXAlignment.Center
	corner(box, 8)
	box.Parent = row

	local give = Instance.new("TextButton")
	give.AnchorPoint = Vector2.new(1, 0)
	give.Position = UDim2.new(1, 0, 0, 0)
	give.Size = UDim2.fromOffset(96, 34)
	give.BackgroundColor3 = GREEN
	give.AutoButtonColor = true
	give.Font = Enum.Font.FredokaOne
	give.TextSize = 16
	give.TextColor3 = WHITE
	give.Text = "Give"
	corner(give, 8)
	give.Parent = row

	give.Activated:Connect(function()
		local digits = (box.Text:gsub("[^%d]", ""))
		local n = tonumber(digits)
		if n and n > 0 then
			onGive(n)
			box.Text = ""
		end
	end)

	local chips = Instance.new("Frame")
	chips.BackgroundTransparency = 1
	chips.Position = UDim2.fromOffset(0, 66)
	chips.Size = UDim2.new(1, 0, 0, 34)
	chips.Parent = sec
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = chips
	for i, amount in quicks do
		buildChip(chips, i, amount, function()
			onGive(amount)
		end)
	end
end

local function setOpen(open: boolean)
	isOpen = open
	panel.Visible = open
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "AdminPanel"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 60
	gui.Parent = player:WaitForChild("PlayerGui")

	local openBtn = Instance.new("TextButton")
	openBtn.Name = "AdminButton"
	openBtn.Position = UDim2.fromOffset(16, 16)
	openBtn.Size = UDim2.fromOffset(120, 38)
	openBtn.BackgroundColor3 = HEADER
	openBtn.AutoButtonColor = true
	openBtn.Font = Enum.Font.FredokaOne
	openBtn.TextSize = 16
	openBtn.TextColor3 = WHITE
	openBtn.Text = "Admin"
	corner(openBtn, 10)
	stroke(openBtn, 2, WHITE, 0.5)
	openBtn.Parent = gui

	panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(360, 320)
	panel.BackgroundColor3 = PANEL
	panel.Visible = false
	corner(panel, 16)
	stroke(panel, 3, HEADER, 0.2)
	panel.Parent = gui

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 16)
	pad.PaddingBottom = UDim.new(0, 16)
	pad.PaddingLeft = UDim.new(0, 18)
	pad.PaddingRight = UDim.new(0, 18)
	pad.Parent = panel

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, -34, 0, 26)
	title.Font = Enum.Font.FredokaOne
	title.TextSize = 20
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = INK
	title.Text = "Admin - Testing"
	title.Parent = panel

	local subtitle = Instance.new("TextLabel")
	subtitle.BackgroundTransparency = 1
	subtitle.Position = UDim2.fromOffset(0, 28)
	subtitle.Size = UDim2.new(1, 0, 0, 16)
	subtitle.Font = Enum.Font.Gotham
	subtitle.TextSize = 12
	subtitle.TextXAlignment = Enum.TextXAlignment.Left
	subtitle.TextColor3 = SUBTLE
	subtitle.Text = "Give yourself resources to test features."
	subtitle.Parent = panel

	local close = Instance.new("TextButton")
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, 0, 0, 0)
	close.Size = UDim2.fromOffset(30, 30)
	close.BackgroundColor3 = RED
	close.AutoButtonColor = true
	close.Font = Enum.Font.FredokaOne
	close.TextSize = 18
	close.TextColor3 = WHITE
	close.Text = "X"
	corner(close, 8)
	close.Parent = panel

	local holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.Position = UDim2.fromOffset(0, 54)
	holder.Size = UDim2.new(1, 0, 1, -54)
	holder.Parent = panel
	local hlist = Instance.new("UIListLayout")
	hlist.FillDirection = Enum.FillDirection.Vertical
	hlist.Padding = UDim.new(0, 14)
	hlist.SortOrder = Enum.SortOrder.LayoutOrder
	hlist.Parent = holder

	buildSection(holder, 1, "Gold", GOLD, { 1000, 10000, 100000, 1000000 }, function(n)
		grant(n, 0)
	end)
	buildSection(holder, 2, "Diamonds", DIAMOND, { 50, 250, 1000, 10000 }, function(n)
		grant(0, n)
	end)

	openBtn.Activated:Connect(function()
		setOpen(not isOpen)
	end)
	close.Activated:Connect(function()
		setOpen(false)
	end)
end

function AdminController.Init() end

function AdminController.Start()
	if not isAdmin() then
		return -- non-admins never see the button or panel
	end
	build()
end

return AdminController
