--!strict
-- CutsceneController: the client half of the intro cutscene.
--
-- The server (CutsceneService) drives the timing; this controller owns the things
-- that can only live on the client -- the camera, a black screen fade, and a Skip
-- button. It does nothing unless GameConfig.INTRO_CUTSCENE is on.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local CutsceneData = require(ReplicatedStorage.Shared.CutsceneData)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local CutsceneController = {}

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

local fadeFrame: Frame? = nil
local skipButton: TextButton? = nil

local function ensureGui()
	local gui = Instance.new("ScreenGui")
	gui.Name = "IntroCutscene"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 50
	gui.Parent = player:WaitForChild("PlayerGui")

	local frame = Instance.new("Frame")
	frame.Name = "Fade"
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Color3.new(0, 0, 0)
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.ZIndex = 10
	frame.Parent = gui
	fadeFrame = frame

	local btn = Instance.new("TextButton")
	btn.Name = "Skip"
	btn.AnchorPoint = Vector2.new(1, 1)
	btn.Position = UDim2.new(1, -24, 1, -24)
	btn.Size = UDim2.fromOffset(140, 44)
	btn.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	btn.BackgroundTransparency = 0.35
	btn.TextColor3 = Color3.fromRGB(255, 255, 255)
	btn.TextSize = 20
	btn.Font = Enum.Font.GothamMedium
	btn.Text = "Skip Intro"
	btn.AutoButtonColor = true
	btn.Visible = false
	btn.ZIndex = 11
	btn.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = btn
	skipButton = btn

	btn.Activated:Connect(function()
		btn.Visible = false
		Remotes.Get("CutsceneSkip"):FireServer()
	end)
end

local function setShot(shot: string)
	camera = Workspace.CurrentCamera
	if shot == "Custom" then
		camera.CameraType = Enum.CameraType.Custom
		if skipButton then
			skipButton.Visible = false
		end
		return
	end
	local components = CutsceneData.Shots[shot]
	if not components then
		return
	end
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = CutsceneData.toCFrame(components)
	if skipButton then
		skipButton.Visible = true
	end
end

local function doFade(mode: string, seconds: number?)
	if not fadeFrame then
		return
	end
	-- "out" fades to black (opaque), "in" fades back to clear.
	local goal = if mode == "out" then 0 else 1
	local info = TweenInfo.new(seconds or 0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	TweenService:Create(fadeFrame, info, { BackgroundTransparency = goal }):Play()
end

function CutsceneController.Start()
	if not GameConfig.INTRO_CUTSCENE then
		return
	end

	camera = Workspace.CurrentCamera
	ensureGui()

	Remotes.Get("CutsceneCamera").OnClientEvent:Connect(function(shot)
		setShot(shot)
	end)

	Remotes.Get("CutsceneFade").OnClientEvent:Connect(function(mode, seconds)
		doFade(mode, seconds)
	end)

	-- Let the character + camera settle, then tell the server we're ready to run.
	task.wait(0.5)
	Remotes.Get("CutsceneReady"):FireServer()
end

return CutsceneController
