--!strict
-- VillagerController: rescue journal and permanent-perk summary. Actual rescues
-- only happen through the physical server prompts in each ring.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local VillagerController = {}

local panel: Frame? = nil
local list: ScrollingFrame? = nil
local summary: TextLabel? = nil
local notice: TextLabel? = nil
local latest: any = nil
local wired = false

local INK = Color3.fromRGB(42, 52, 47)
local CREAM = Color3.fromRGB(246, 240, 218)
local GREEN = Color3.fromRGB(79, 153, 84)
local LOCKED = Color3.fromRGB(119, 124, 121)

local function corner(parent: Instance, radius: number)
	local value = Instance.new("UICorner")
	value.CornerRadius = UDim.new(0, radius)
	value.Parent = parent
end

local function setOpen(open: boolean)
	if panel then
		panel.Visible = open
		if open then Remotes.Get("RequestVillagers"):FireServer() end
	end
end

local function clearRows()
	if not list then return end
	for _, child in list:GetChildren() do
		if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then child:Destroy() end
	end
end

local function render()
	if not latest or not list then return end
	clearRows()
	if summary then
		summary.Text = "Neighbors rescued: " .. tostring(latest.rescuedCount or 0) .. " / " .. tostring(#(latest.rows or {})) .. "   \u{2022}   Every rescue grants a permanent perk"
	end
	if notice then notice.Text = latest.message or "Find each trapped neighbor inside their ring and use the Rescue prompt." end
	for _, row in ipairs(latest.rows or {}) do
		local card = Instance.new("Frame")
		card.Name = row.key
		card.Size = UDim2.new(1, -10, 0, 92)
		card.BackgroundColor3 = if row.rescued then Color3.fromRGB(222, 241, 207) else Color3.fromRGB(228, 225, 211)
		card.BorderSizePixel = 0
		corner(card, 12)
		card.Parent = list
		local name = Instance.new("TextLabel")
		name.Position = UDim2.fromOffset(14, 8)
		name.Size = UDim2.new(0.55, -18, 0, 25)
		name.BackgroundTransparency = 1
		name.Font = Enum.Font.FredokaOne
		name.Text = row.name .. "  -  " .. row.zone
		name.TextColor3 = INK
		name.TextSize = 16
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.Parent = card
		local perk = Instance.new("TextLabel")
		perk.Position = UDim2.fromOffset(14, 35)
		perk.Size = UDim2.new(1, -150, 0, 44)
		perk.BackgroundTransparency = 1
		perk.Font = Enum.Font.Gotham
		perk.Text = row.feature .. ": " .. row.desc
		perk.TextColor3 = Color3.fromRGB(72, 81, 72)
		perk.TextSize = 13
		perk.TextWrapped = true
		perk.TextXAlignment = Enum.TextXAlignment.Left
		perk.TextYAlignment = Enum.TextYAlignment.Top
		perk.Parent = card
		local state = Instance.new("TextLabel")
		state.AnchorPoint = Vector2.new(1, 0.5)
		state.Position = UDim2.new(1, -12, 0.5, 0)
		state.Size = UDim2.fromOffset(124, 38)
		state.BackgroundColor3 = if row.rescued then GREEN else LOCKED
		state.BorderSizePixel = 0
		state.Font = Enum.Font.GothamBold
		state.Text = if row.rescued then "RESCUED" elseif row.reached then "FIND IN RING" else "RING LOCKED"
		state.TextColor3 = Color3.new(1, 1, 1)
		state.TextSize = 11
		corner(state, 9)
		state.Parent = card
	end
end

local function applyState(state: any)
	latest = state
	render()
end

local function build()
	local playerGui = player:WaitForChild("PlayerGui")
	local old = playerGui:FindFirstChild("VillagerGui")
	if old then old:Destroy() end
	local gui = Instance.new("ScreenGui")
	gui.Name = "VillagerGui"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 28
	gui.Parent = playerGui
	local button = Instance.new("TextButton")
	button.Name = "VillagersButton"
	button.Position = UDim2.new(1, -130, 0.5, 196)
	button.Size = UDim2.fromOffset(112, 44)
	button.AnchorPoint = Vector2.new(0, 0.5)
	button.BackgroundColor3 = Color3.fromRGB(92, 120, 76)
	button.BorderSizePixel = 0
	button.Font = Enum.Font.FredokaOne
	button.Text = "NEIGHBORS"
	button.TextColor3 = Color3.new(1, 1, 1)
	button.TextSize = 13
	corner(button, 10)
	button.Parent = gui

	local window = Instance.new("Frame")
	window.Name = "VillagerJournal"
	window.AnchorPoint = Vector2.new(0.5, 0.5)
	window.Position = UDim2.fromScale(0.5, 0.5)
	window.Size = UDim2.fromOffset(620, 460)
	window.BackgroundColor3 = CREAM
	window.BorderSizePixel = 0
	window.Visible = false
	corner(window, 18)
	window.Parent = gui
	panel = window
	local scale = Instance.new("UIScale")
	scale.Parent = window
	local camera = workspace.CurrentCamera
	local function resize()
		if not camera then return end
		local viewport = camera.ViewportSize
		scale.Scale = math.min(1, math.max(0.62, math.min((viewport.X - 32) / 620, (viewport.Y - 32) / 460)))
	end
	resize()
	if camera then camera:GetPropertyChangedSignal("ViewportSize"):Connect(resize) end

	local title = Instance.new("TextLabel")
	title.Position = UDim2.fromOffset(22, 12)
	title.Size = UDim2.new(1, -84, 0, 34)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.FredokaOne
	title.Text = "RESCUED NEIGHBORS & PERMANENT PERKS"
	title.TextColor3 = INK
	title.TextSize = 21
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = window
	local close = Instance.new("TextButton")
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -14, 0, 12)
	close.Size = UDim2.fromOffset(42, 34)
	close.BackgroundColor3 = Color3.fromRGB(188, 76, 78)
	close.BorderSizePixel = 0
	close.Font = Enum.Font.GothamBold
	close.Text = "X"
	close.TextColor3 = Color3.new(1, 1, 1)
	close.TextSize = 16
	corner(close, 9)
	close.Parent = window
	local sum = Instance.new("TextLabel")
	sum.Position = UDim2.fromOffset(22, 52)
	sum.Size = UDim2.new(1, -44, 0, 24)
	sum.BackgroundTransparency = 1
	sum.Font = Enum.Font.GothamBold
	sum.Text = "Neighbors rescued: 0 / 5"
	sum.TextColor3 = Color3.fromRGB(76, 105, 68)
	sum.TextSize = 13
	sum.TextXAlignment = Enum.TextXAlignment.Left
	sum.Parent = window
	summary = sum
	local info = Instance.new("TextLabel")
	info.Position = UDim2.fromOffset(22, 79)
	info.Size = UDim2.new(1, -44, 0, 36)
	info.BackgroundColor3 = Color3.fromRGB(232, 226, 193)
	info.BorderSizePixel = 0
	info.Font = Enum.Font.Gotham
	info.Text = "Find each trapped neighbor inside their ring and use the Rescue prompt."
	info.TextColor3 = INK
	info.TextSize = 12
	info.TextWrapped = true
	corner(info, 9)
	info.Parent = window
	notice = info
	local scroll = Instance.new("ScrollingFrame")
	scroll.Position = UDim2.fromOffset(18, 124)
	scroll.Size = UDim2.new(1, -36, 1, -140)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 6
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	scroll.Parent = window
	list = scroll
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = scroll
	local padding = Instance.new("UIPadding")
	padding.PaddingBottom = UDim.new(0, 8)
	padding.Parent = scroll
	button.Activated:Connect(function() setOpen(not window.Visible) end)
	close.Activated:Connect(function() setOpen(false) end)
end

function VillagerController.Init()
	build()
	if not wired then
		wired = true
		Remotes.Get("VillagerState").OnClientEvent:Connect(applyState)
		Remotes.Get("OpenVillagerMenu").OnClientEvent:Connect(function() setOpen(true) end)
	end
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.N then setOpen(not (panel and panel.Visible)) end
	end)
end

function VillagerController.Start()
	Remotes.Get("RequestVillagers"):FireServer()
end

return VillagerController
