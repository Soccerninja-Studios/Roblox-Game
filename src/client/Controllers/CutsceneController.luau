--!strict
-- CutsceneController: the client half of the intro cutscene.
--
-- The server (CutsceneService) drives the timing; this controller owns the things
-- that can only live on the client -- the camera, a black screen fade, a Skip
-- button, hiding the game UI until the intro ends, and playing the PLAYER's own
-- animations. (A player's character is client-owned, so animations played from
-- the server don't reliably show on it -- they must be played here.)
--
-- It does nothing unless GameConfig.INTRO_CUTSCENE is on.

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

-- UI we hid for the duration of the intro, so we can put it back afterwards.
local hiddenGuis: { ScreenGui } = {}
local guiWatch: RBXScriptConnection? = nil

-- Player animation state.
local animTracks: { [number]: AnimationTrack } = {}
local currentTrack: AnimationTrack? = nil
local currentConn: RBXScriptConnection? = nil
local currentPoseId: number? = nil

----------------------------------------------------------------------
-- Hide / reveal the game UI
----------------------------------------------------------------------

local function hideGameUi()
	local pg = player:WaitForChild("PlayerGui")
	local function hideOne(inst: Instance)
		if inst:IsA("ScreenGui") and inst.Name ~= "IntroCutscene" and inst.Enabled then
			inst.Enabled = false
			table.insert(hiddenGuis, inst)
		end
	end
	for _, child in pg:GetChildren() do
		hideOne(child)
	end
	-- Anything the game builds during the intro (e.g. the HUD) gets hidden too.
	guiWatch = pg.ChildAdded:Connect(function(child)
		task.defer(hideOne, child)
	end)
end

local function revealGameUi()
	if guiWatch then
		guiWatch:Disconnect()
		guiWatch = nil
	end
	for _, gui in hiddenGuis do
		if gui and gui.Parent then
			gui.Enabled = true
		end
	end
	table.clear(hiddenGuis)
end

----------------------------------------------------------------------
-- Player animations (played on the client, on the local character)
----------------------------------------------------------------------

local function getLocalAnimator(): Animator?
	local char = player.Character
	if not char then
		return nil
	end
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	return animator
end

local function stopCurrentPose()
	if currentConn then
		currentConn:Disconnect()
		currentConn = nil
	end
	if currentTrack then
		pcall(function()
			(currentTrack :: AnimationTrack):Stop(0.1)
		end)
		currentTrack = nil
	end
	currentPoseId = nil
end

local function playPose(poseId: number, animId: number)
	local doneRemote = Remotes.Get("CutscenePoseDone")
	local animator = getLocalAnimator()
	if not animator then
		doneRemote:FireServer(poseId)
		return
	end
	stopCurrentPose()

	local track = animTracks[animId]
	if not track then
		local anim = Instance.new("Animation")
		anim.AnimationId = "rbxassetid://" .. tostring(animId)
		local ok, loaded = pcall(function()
			return animator:LoadAnimation(anim)
		end)
		if ok and loaded then
			track = loaded
			animTracks[animId] = loaded
		end
	end
	if not track then
		doneRemote:FireServer(poseId)
		return
	end

	track.Priority = Enum.AnimationPriority.Action
	track.Looped = false
	currentTrack = track
	currentPoseId = poseId

	local fired = false
	local function finishOnce()
		if fired then
			return
		end
		fired = true
		doneRemote:FireServer(poseId)
	end
	currentConn = track.Stopped:Connect(finishOnce)
	track:Play(0.15)

	-- Safety: if Stopped never fires (e.g. a bad/unowned anim), report done anyway
	-- so the server's sequence can't hang.
	task.delay(12, function()
		if currentPoseId == poseId then
			finishOnce()
		end
	end)
end

----------------------------------------------------------------------
-- Camera + fade + Skip button
----------------------------------------------------------------------

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
		-- The intro is over: stop any pose and give the UI back.
		stopCurrentPose()
		revealGameUi()
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
	hideGameUi()

	Remotes.Get("CutsceneCamera").OnClientEvent:Connect(function(shot)
		setShot(shot)
	end)

	Remotes.Get("CutsceneFade").OnClientEvent:Connect(function(mode, seconds)
		doFade(mode, seconds)
	end)

	Remotes.Get("CutscenePose").OnClientEvent:Connect(function(poseId, animId)
		playPose(poseId, animId)
	end)

	-- Let the character + camera settle, then tell the server we're ready to run.
	task.wait(0.5)
	Remotes.Get("CutsceneReady"):FireServer()
end

return CutsceneController
