--!strict
-- QuestController: the client-side Quest Board. Opens when you press the prompt
-- on Sprig the Quartermaster (Workspace.QuestGiver), asks the server for the
-- full quest list, and renders it grouped by zone with progress bars + Claim
-- buttons. Locked zones show an unlock hint; objectives whose game systems are
-- not built yet (combat, pets, auto-mowers, abilities) are tagged "Coming soon".

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")
local TweenService = game:GetService("TweenService")

local Remotes = require(ReplicatedStorage.Shared.Remotes)

local QuestController = {}

local player = Players.LocalPlayer

-- Palette (matches the HUD) ---------------------------------------------------
local CREAM = Color3.fromRGB(247, 244, 234)
local PANEL = Color3.fromRGB(255, 253, 247)
local INK = Color3.fromRGB(54, 62, 48)
local SUBTLE = Color3.fromRGB(120, 128, 112)
local GREEN = Color3.fromRGB(88, 178, 84)
local GREEN_DARK = Color3.fromRGB(58, 138, 64)
local LOCKED = Color3.fromRGB(168, 172, 162)
local GOLD = Color3.fromRGB(240, 190, 70)
local HEADER = Color3.fromRGB(70, 96, 60)

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

local function stroke(parent: Instance, thickness: number, color: Color3, transparency: number?)
	local s = Instance.new("UIStroke")
	s.Thickness = thickness
	s.Color = color
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

local function rewardText(reward: any): string
	local parts = {}
	if (reward.gold or 0) > 0 then
		table.insert(parts, formatNumber(reward.gold) .. " gold")
	end
	if (reward.diamonds or 0) > 0 then
		table.insert(parts, formatNumber(reward.diamonds) .. " \u{1F48E}")
	end
	if (reward.essence or 0) > 0 and reward.essenceType ~= "" then
		table.insert(parts, formatNumber(reward.essence) .. " " .. reward.essenceType)
	end
	if reward.item and reward.item ~= "" then
		table.insert(parts, reward.item)
	end
	if #parts == 0 then
		return "Reward: -"
	end
	return "Reward: " .. table.concat(parts, " + ")
end

-- Build the static shell once -------------------------------------------------
local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "QuestBoard"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 20
	gui.Enabled = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = player:WaitForChild("PlayerGui")

	backdrop = Instance.new("TextButton")
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.new(1, 0, 1, 0)
	backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	backdrop.BackgroundTransparency = 0.45
	backdrop.Text = ""
	backdrop.AutoButtonColor = false
	backdrop.Parent = gui
	backdrop.Activated:Connect(function()
		QuestController.Close()
	end)

	board = Instance.new("Frame")
	board.Name = "Board"
	board.AnchorPoint = Vector2.new(0.5, 0.5)
	board.Position = UDim2.new(0.5, 0, 0.5, 0)
	board.Size = UDim2.new(0, 640, 0, 580)
	board.BackgroundColor3 = CREAM
	board.Parent = gui
	corner(board, 20)
	stroke(board, 3, Color3.fromRGB(214, 208, 190))

	local header = Instance.new("Frame")
	header.Name = "Header"
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
	title.Text = "Quest Board"
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextScaled = true
	title.Parent = header

	local subtitle = Instance.new("TextLabel")
	subtitle.BackgroundTransparency = 1
	subtitle.Position = UDim2.new(0, 24, 0, 46)
	subtitle.Size = UDim2.new(1, -90, 0, 20)
	subtitle.Font = Enum.Font.GothamMedium
	subtitle.Text = "Sprig the Quartermaster"
	subtitle.TextColor3 = Color3.fromRGB(210, 226, 200)
	subtitle.TextXAlignment = Enum.TextXAlignment.Left
	subtitle.TextScaled = true
	subtitle.Parent = header

	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "Close"
	closeBtn.AnchorPoint = Vector2.new(1, 0.5)
	closeBtn.Position = UDim2.new(1, -18, 0, 39)
	closeBtn.Size = UDim2.new(0, 40, 0, 40)
	closeBtn.BackgroundColor3 = Color3.fromRGB(226, 92, 84)
	closeBtn.Font = Enum.Font.FredokaOne
	closeBtn.Text = "\u{2715}"
	closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	closeBtn.TextScaled = true
	closeBtn.Parent = header
	corner(closeBtn, 12)
	closeBtn.Activated:Connect(function()
		QuestController.Close()
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
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = listFrame
	local pad = Instance.new("UIPadding")
	pad.PaddingRight = UDim.new(0, 6)
	pad.PaddingBottom = UDim.new(0, 6)
	pad.Parent = listFrame

	toastHolder = Instance.new("Frame")
	toastHolder.Name = "Toasts"
	toastHolder.AnchorPoint = Vector2.new(0.5, 0)
	toastHolder.Position = UDim2.new(0.5, 0, 0, 96)
	toastHolder.Size = UDim2.new(0, 420, 0, 0)
	toastHolder.BackgroundTransparency = 1
	toastHolder.Parent = gui
	local toastLayout = Instance.new("UIListLayout")
	toastLayout.Padding = UDim.new(0, 6)
	toastLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	toastLayout.SortOrder = Enum.SortOrder.LayoutOrder
	toastLayout.Parent = toastHolder
end

-- Row builders ----------------------------------------------------------------
local function zoneHeaderRow(text: string, order: number)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 34)
	row.BackgroundColor3 = HEADER
	row.BackgroundTransparency = 0.12
	row.LayoutOrder = order
	row.Parent = listFrame
	corner(row, 10)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Position = UDim2.new(0, 14, 0, 0)
	label.Size = UDim2.new(1, -28, 1, 0)
	label.Font = Enum.Font.FredokaOne
	label.Text = text
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextSize = 18
	label.Parent = row
end

local function lockedNoticeRow(ring: string, order: number)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 40)
	row.BackgroundColor3 = PANEL
	row.LayoutOrder = order
	row.Parent = listFrame
	corner(row, 10)
	stroke(row, 1.5, Color3.fromRGB(224, 218, 202))
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Position = UDim2.new(0, 14, 0, 0)
	label.Size = UDim2.new(1, -28, 1, 0)
	label.Font = Enum.Font.GothamMedium
	label.Text = "\u{1F512} Reach the " .. ring .. " to unlock these quests."
	label.TextColor3 = SUBTLE
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextSize = 15
	label.Parent = row
end

local function questRow(q: any, order: number)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 84)
	row.BackgroundColor3 = PANEL
	row.LayoutOrder = order
	row.Parent = listFrame
	corner(row, 12)
	stroke(row, 1.5, Color3.fromRGB(224, 218, 202))

	local name = Instance.new("TextLabel")
	name.BackgroundTransparency = 1
	name.Position = UDim2.new(0, 14, 0, 8)
	name.Size = UDim2.new(1, -170, 0, 20)
	name.Font = Enum.Font.GothamBold
	name.Text = q.name
	name.TextColor3 = INK
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextSize = 16
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Parent = row

	local desc = Instance.new("TextLabel")
	desc.BackgroundTransparency = 1
	desc.Position = UDim2.new(0, 14, 0, 28)
	desc.Size = UDim2.new(1, -170, 0, 18)
	desc.Font = Enum.Font.Gotham
	desc.Text = q.desc
	desc.TextColor3 = SUBTLE
	desc.TextXAlignment = Enum.TextXAlignment.Left
	desc.TextSize = 13
	desc.TextTruncate = Enum.TextTruncate.AtEnd
	desc.Parent = row

	local reward = Instance.new("TextLabel")
	reward.BackgroundTransparency = 1
	reward.Position = UDim2.new(0, 14, 0, 60)
	reward.Size = UDim2.new(1, -170, 0, 16)
	reward.Font = Enum.Font.GothamMedium
	reward.Text = rewardText(q.reward)
	reward.TextColor3 = GREEN_DARK
	reward.TextXAlignment = Enum.TextXAlignment.Left
	reward.TextSize = 12
	reward.TextTruncate = Enum.TextTruncate.AtEnd
	reward.Parent = row

	local barBg = Instance.new("Frame")
	barBg.Position = UDim2.new(0, 14, 0, 48)
	barBg.Size = UDim2.new(1, -170, 0, 8)
	barBg.BackgroundColor3 = Color3.fromRGB(228, 224, 212)
	barBg.Parent = row
	corner(barBg, 4)
	local pct = math.clamp((q.progress or 0) / math.max(1, q.target or 1), 0, 1)
	local fill = Instance.new("Frame")
	fill.Size = UDim2.new(pct, 0, 1, 0)
	fill.BackgroundColor3 = if q.claimed then LOCKED elseif pct >= 1 then GREEN else GOLD
	fill.BorderSizePixel = 0
	fill.Parent = barBg
	corner(fill, 4)

	local action = Instance.new("TextButton")
	action.AnchorPoint = Vector2.new(1, 0.5)
	action.Position = UDim2.new(1, -14, 0.5, 0)
	action.Size = UDim2.new(0, 132, 0, 56)
	action.Font = Enum.Font.GothamBold
	action.TextSize = 14
	action.AutoButtonColor = false
	action.TextColor3 = Color3.fromRGB(255, 255, 255)
	action.Parent = row
	corner(action, 10)

	if not q.live then
		action.BackgroundColor3 = LOCKED
		action.Text = "Coming soon"
		action.TextColor3 = Color3.fromRGB(245, 245, 240)
		action.Active = false
	elseif q.claimed then
		action.BackgroundColor3 = Color3.fromRGB(210, 214, 204)
		action.Text = "\u{2713} Claimed"
		action.TextColor3 = Color3.fromRGB(120, 128, 112)
		action.Active = false
	elseif (q.progress or 0) >= (q.target or 1) then
		action.BackgroundColor3 = GREEN
		action.Text = "Claim"
		action.Activated:Connect(function()
			Remotes.Get("ClaimQuest"):FireServer(q.id)
		end)
	else
		action.BackgroundColor3 = Color3.fromRGB(236, 232, 220)
		action.Text = formatNumber(q.progress or 0) .. " / " .. formatNumber(q.target or 1)
		action.TextColor3 = INK
		action.Active = false
	end
end

-- Repopulate the list from the latest server state ----------------------------
local function rebuild()
	if not latest then
		return
	end
	for _, child in listFrame:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	local byZone: { [string]: { any } } = {}
	for _, q in ipairs(latest.quests) do
		byZone[q.zone] = byZone[q.zone] or {}
		table.insert(byZone[q.zone], q)
	end

	local order = 0
	for _, zone in ipairs(latest.zones) do
		local quests = byZone[zone.key]
		if quests and #quests > 0 then
			order += 1
			zoneHeaderRow(zone.ring, order)
			if quests[1].unlocked then
				for _, q in ipairs(quests) do
					order += 1
					questRow(q, order)
				end
			else
				order += 1
				lockedNoticeRow(zone.ring, order)
			end
		end
	end
end

-- Toasts ----------------------------------------------------------------------
local function showToast(text: string, accent: Color3)
	local toast = Instance.new("Frame")
	toast.Size = UDim2.new(1, 0, 0, 40)
	toast.BackgroundColor3 = Color3.fromRGB(38, 46, 36)
	toast.BackgroundTransparency = 0.08
	toast.Parent = toastHolder
	corner(toast, 10)
	stroke(toast, 2, accent, 0.2)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, -24, 1, 0)
	label.Position = UDim2.new(0, 12, 0, 0)
	label.Font = Enum.Font.GothamBold
	label.Text = text
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextSize = 14
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Parent = toast
	task.delay(3, function()
		local tween = TweenService:Create(toast, TweenInfo.new(0.4), { BackgroundTransparency = 1 })
		local labelTween = TweenService:Create(label, TweenInfo.new(0.4), { TextTransparency = 1 })
		tween:Play()
		labelTween:Play()
		tween.Completed:Wait()
		toast:Destroy()
	end)
end

-- Public open/close -----------------------------------------------------------
function QuestController.Open()
	if isOpen then
		return
	end
	isOpen = true
	gui.Enabled = true
	Remotes.Get("RequestQuests"):FireServer()
end

function QuestController.Close()
	if not isOpen then
		return
	end
	isOpen = false
	gui.Enabled = false
end

function QuestController.Init(_controllers: any)
	build()
end

function QuestController.Start()
	Remotes.Get("QuestState").OnClientEvent:Connect(function(state: any)
		latest = state
		if isOpen then
			rebuild()
		end
	end)

	Remotes.Get("QuestToast").OnClientEvent:Connect(function(payload: any)
		if type(payload) ~= "table" then
			return
		end
		if payload.kind == "complete" then
			showToast("\u{2B50} Quest complete: " .. tostring(payload.name), GOLD)
		elseif payload.kind == "claimed" then
			local bits = {}
			if (payload.gold or 0) > 0 then
				table.insert(bits, formatNumber(payload.gold) .. " gold")
			end
			if (payload.diamonds or 0) > 0 then
				table.insert(bits, formatNumber(payload.diamonds) .. " \u{1F48E}")
			end
			local suffix = if #bits > 0 then " (+" .. table.concat(bits, ", ") .. ")" else ""
			showToast("\u{1F389} Reward claimed" .. suffix, GREEN)
		end
	end)

	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
		if prompt.Name == "QuestPrompt" then
			QuestController.Open()
		end
	end)
end

return QuestController
