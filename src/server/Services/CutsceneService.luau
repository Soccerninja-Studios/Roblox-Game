--!strict
-- CutsceneService: the intro "teddy bear" cutscene.
--
-- Only runs when GameConfig.INTRO_CUTSCENE is true. It places the neighborhood +
-- house + teddy scene you built in Studio, drives the player's own character
-- through the shot list you described, then swaps the neighborhood out for the
-- plains map and drops the player in front of the (now House 2) house.
--
-- The camera + screen fade live on the client (CutsceneController); this service
-- just tells the client which shot to cut to and when to fade.
--
-- The whole sequence is wrapped so that a skip, an error, or a missing/unowned
-- animation can never strand the player: finish() always builds the plains and
-- hands control back.
--
-- NOTE: this is a single-player-style intro (the scene is shared). Per-player
-- intros for real multiplayer come later; for now it's built for solo testing.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local CutsceneData = require(ReplicatedStorage.Shared.CutsceneData)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local CutsceneService = {}

local MapService: any

local sceneRoot: Model? = nil
local houseClone: Model? = nil
local housePivot: CFrame? = nil
local teddyClone: Model? = nil
local plainsBuilt = false

local activeByPlayer: { [Player]: boolean } = {}
local readyByPlayer: { [Player]: boolean } = {}
local skipByPlayer: { [Player]: boolean } = {}

----------------------------------------------------------------------
-- Asset helpers
----------------------------------------------------------------------

local function getAsset(name: string): Instance?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	return (assets and assets:FindFirstChild(name)) or nil
end

local function cloneAsset(name: string, parent: Instance): Model?
	local template = getAsset(name)
	if template and template:IsA("Model") then
		local clone = template:Clone()
		clone.Parent = parent
		return clone
	end
	warn(`[CutsceneService] Missing asset model: {name}`)
	return nil
end

----------------------------------------------------------------------
-- Camera / fade (fire to the player running the intro)
----------------------------------------------------------------------

local function cut(player: Player, shot: string)
	Remotes.Get("CutsceneCamera"):FireClient(player, shot)
end

local function fade(player: Player, mode: string, seconds: number)
	Remotes.Get("CutsceneFade"):FireClient(player, mode, seconds)
end

----------------------------------------------------------------------
-- Animation helpers
----------------------------------------------------------------------

local function getAnimator(model: Instance?): Animator?
	if not model then
		return nil
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
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

local function loadTrack(animator: Animator?, animId: number): AnimationTrack?
	if not animator then
		return nil
	end
	local anim = Instance.new("Animation")
	anim.AnimationId = "rbxassetid://" .. tostring(animId)
	local ok, track = pcall(function()
		return animator:LoadAnimation(anim)
	end)
	if ok and track then
		track.Priority = Enum.AnimationPriority.Action
		track.Looped = false
		return track
	end
	warn(`[CutsceneService] Could not load animation {animId}`)
	return nil
end

-- Yield until a track stops, with a safety timeout so a missing/unowned animation
-- can never hard-freeze the intro.
local function waitForStop(track: AnimationTrack, maxSeconds: number)
	local done = false
	local conn = track.Stopped:Connect(function()
		done = true
	end)
	local elapsed = 0
	while not done and elapsed < maxSeconds do
		elapsed += task.wait()
	end
	conn:Disconnect()
end

local function playAndWait(track: AnimationTrack?, maxSeconds: number?)
	local budget = maxSeconds or 12
	if not track then
		task.wait(1.25)
		return
	end
	pcall(function()
		track:Play(0.15)
	end)
	waitForStop(track, budget)
end

----------------------------------------------------------------------
-- Actor = the player's own character
----------------------------------------------------------------------

local function prepActor(character: Model)
	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
		humanoid.AutoRotate = false
	end
	if hrp then
		hrp.Anchored = true
	end
end

local function placeActor(character: Model, rig: string)
	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if hrp then
		hrp.CFrame = CutsceneData.toCFrame(CutsceneData.Rigs[rig])
	end
end

local function releaseActor(character: Model, spawnCFrame: CFrame)
	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if hrp then
		hrp.Anchored = false
		hrp.CFrame = spawnCFrame
	end
	if humanoid then
		humanoid.WalkSpeed = 16
		humanoid.JumpPower = 50
		humanoid.AutoRotate = true
	end
end

----------------------------------------------------------------------
-- Scene setup + swaps
----------------------------------------------------------------------

local function placeScene()
	if sceneRoot then
		return
	end
	local root = Instance.new("Model")
	root.Name = "IntroScene"
	root.Parent = Workspace
	sceneRoot = root

	cloneAsset("Neighborhood", root)
	houseClone = cloneAsset("House", root)
	if houseClone then
		housePivot = houseClone:GetPivot()
	end
	teddyClone = cloneAsset("TeddyBear", root)
end

local function buildPlains()
	if plainsBuilt then
		return
	end
	plainsBuilt = true
	if MapService then
		MapService.BuildPlains(CutsceneData.HouseCenter)
	end
end

local function swapNeighborhoodForPlains()
	buildPlains()
	-- Drop the neighborhood, but keep the house until the very end (it becomes
	-- House 2 during the fade to black).
	if sceneRoot then
		for _, child in sceneRoot:GetChildren() do
			if child ~= houseClone then
				child:Destroy()
			end
		end
	end
end

local function swapHouse()
	local parent = (sceneRoot :: any) or Workspace
	local newHouse = cloneAsset("House2", parent)
	if newHouse and housePivot then
		newHouse:PivotTo(housePivot)
	end
	if houseClone then
		houseClone:Destroy()
		houseClone = nil
	end
end

local function spawnPoint(): CFrame
	-- In front of the house, on the plains ground.
	local c = CutsceneData.HouseCenter
	return CFrame.new(c.X, c.Y + 3, c.Z + 100) * CFrame.Angles(0, math.rad(180), 0)
end

----------------------------------------------------------------------
-- The sequence
----------------------------------------------------------------------

local function runSequence(player: Player)
	local character = player.Character
	if not character then
		return
	end

	prepActor(character)
	local actorAnimator = getAnimator(character)

	local tracks = {
		Typing = loadTrack(actorAnimator, CutsceneData.Anims.Typing),
		Grabbing = loadTrack(actorAnimator, CutsceneData.Anims.Grabbing),
		Running = loadTrack(actorAnimator, CutsceneData.Anims.Running),
		Running2 = loadTrack(actorAnimator, CutsceneData.Anims.Running2),
		Running3 = loadTrack(actorAnimator, CutsceneData.Anims.Running3),
	}

	local teddyAnimator = getAnimator(teddyClone)
	local teddyFalling = loadTrack(teddyAnimator, CutsceneData.Anims.TeddyBearFalling)

	local function skipped(): boolean
		return skipByPlayer[player] == true
	end

	-- Shot 1: the player types at the desk.
	cut(player, "Shot1")
	placeActor(character, "Rig1")
	fade(player, "in", 0.6)
	playAndWait(tracks.Typing, 12)
	if skipped() then
		return
	end

	-- The teddy bear falls out the window and freezes where it lands.
	if teddyFalling then
		pcall(function()
			teddyFalling:Play(0.1)
		end)
		task.spawn(function()
			local len = teddyFalling.Length
			if len <= 0 then
				len = 1.5
			end
			task.wait(len * 0.97)
			pcall(function()
				teddyFalling:AdjustSpeed(0)
			end)
		end)
	end

	-- The player reaches for the teddy.
	playAndWait(tracks.Grabbing, 12)
	if skipped() then
		return
	end

	-- Runs toward the window.
	placeActor(character, "Rig2")
	playAndWait(tracks.Running, 12)
	if skipped() then
		return
	end

	-- Shot 2: mid-run. Hold for 3.3s, then cut to shot 1 while Running 2 finishes.
	cut(player, "Shot2")
	placeActor(character, "Rig3")
	local r2 = tracks.Running2
	if r2 then
		pcall(function()
			r2:Play(0.15)
		end)
	end
	task.wait(CutsceneData.Running2HoldSeconds)
	cut(player, "Shot1")
	if r2 then
		waitForStop(r2, 12)
	end
	if skipped() then
		return
	end

	-- Running 2 is done: remove the teddy, cut to shot 2, and swap the neighborhood
	-- out for the plains behind it while the player runs off (Running 3 at Rig 4).
	if teddyClone then
		teddyClone:Destroy()
		teddyClone = nil
	end
	cut(player, "Shot2")
	swapNeighborhoodForPlains()
	placeActor(character, "Rig4")
	playAndWait(tracks.Running3, 12)

	-- Fade to black, swap the house for House 2, and hand back control out front.
	fade(player, "out", 0.6)
	task.wait(0.75)
	swapHouse()
	releaseActor(character, spawnPoint())
	cut(player, "Custom")
	fade(player, "in", 0.6)
end

local function finish(player: Player)
	-- Always leave the world real and the player free, even after a skip or error.
	buildPlains()
	if houseClone then
		swapHouse()
	end
	local character = player.Character
	if character then
		releaseActor(character, spawnPoint())
	end
	cut(player, "Custom")
	fade(player, "in", 0.4)
end

local function beginFor(player: Player)
	if activeByPlayer[player] then
		return
	end
	if not player.Character then
		return
	end
	if not readyByPlayer[player] then
		return
	end
	activeByPlayer[player] = true
	placeScene()
	local ok, err = pcall(runSequence, player)
	if not ok then
		warn(`[CutsceneService] intro errored: {err}`)
	end
	finish(player)
end

----------------------------------------------------------------------
-- Player prep: freeze + park at Rig 1 the instant the character loads so it
-- never falls through the (not-yet-built) world before the intro starts.
----------------------------------------------------------------------

local function onCharacter(player: Player, character: Model)
	task.wait(0.1)
	prepActor(character)
	placeActor(character, "Rig1")
	if readyByPlayer[player] then
		beginFor(player)
	end
end

local function onPlayer(player: Player)
	player.CharacterAdded:Connect(function(character)
		onCharacter(player, character)
	end)
	if player.Character then
		onCharacter(player, player.Character)
	end
end

function CutsceneService.Init(services)
	MapService = services.MapService
end

function CutsceneService.Start()
	if not GameConfig.INTRO_CUTSCENE then
		return
	end

	Remotes.Get("CutsceneReady").OnServerEvent:Connect(function(player)
		readyByPlayer[player] = true
		beginFor(player)
	end)

	Remotes.Get("CutsceneSkip").OnServerEvent:Connect(function(player)
		skipByPlayer[player] = true
	end)

	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end

	Players.PlayerRemoving:Connect(function(player)
		activeByPlayer[player] = nil
		readyByPlayer[player] = nil
		skipByPlayer[player] = nil
	end)

	print("[CutsceneService] Intro cutscene armed.")
end

return CutsceneService
