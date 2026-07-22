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
-- The PLAYER's animations are also played on the client (via CutscenePose): a
-- player's character is client-owned, so animations played from the server don't
-- reliably show on it. The teddy bear is a server-owned model, so ITS animation
-- is played here on the server.
--
-- The whole sequence is wrapped so that a skip, an error, or a missing/unowned
-- animation can never strand the player: finish() always builds the plains,
-- hands control back, and gives the player their tools.
--
-- NOTE: this is a single-player-style intro (the scene is shared). Per-player
-- intros for real multiplayer come later; for now it's built for solo testing.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local CutsceneData = require(ReplicatedStorage.Shared.CutsceneData)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local CutsceneService = {}

local MapService: any
local ToolService: any

local sceneRoot: Model? = nil
local houseClone: Model? = nil
local housePivot: CFrame? = nil
local houseSpawnCF: CFrame? = nil
local teddyClone: Model? = nil
local plainsBuilt = false

local activeByPlayer: { [Player]: boolean } = {}
local readyByPlayer: { [Player]: boolean } = {}
local skipByPlayer: { [Player]: boolean } = {}
local finishedByPlayer: { [Player]: boolean } = {}

-- Client-driven pose handshake: every pose gets an id, and the client fires it
-- back via CutscenePoseDone when that animation finishes.
local poseAck: { [Player]: number } = {}
local poseSeq = 0

----------------------------------------------------------------------
-- Asset helpers
----------------------------------------------------------------------

-- Find a model by name no matter where it lives (ReplicatedStorage.Assets is the
-- intended home, but we also look in ServerStorage and Workspace so it works if
-- you keep the models in Workspace). Matching ignores spaces and case, so
-- "House 2", "Teddy Bear" and "Plains Assets" resolve without renaming.
local function normalizeName(s: string): string
	return (string.gsub(string.lower(s), "%s", ""))
end

local function searchContainer(container: Instance?, wanted: string): Instance?
	if not container then
		return nil
	end
	local direct = container:FindFirstChild(wanted)
	if direct then
		return direct
	end
	local target = normalizeName(wanted)
	for _, child in container:GetChildren() do
		if normalizeName(child.Name) == target then
			return child
		end
	end
	return nil
end

local function getAsset(name: string): Instance?
	local containers: { Instance? } = {
		ReplicatedStorage:FindFirstChild("Assets"),
		ServerStorage:FindFirstChild("Assets"),
		ServerStorage,
		ReplicatedStorage,
		Workspace,
	}
	for _, c in containers do
		local found = searchContainer(c, name)
		if found then
			return found
		end
	end
	return nil
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
-- Animation helpers (server side -- used for the teddy only)
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

-- Tell the client to play an animation on ITS OWN character, then wait for the
-- client to report it finished (or a safety budget, or a skip). This is how all
-- of the PLAYER's cutscene animations run -- see the file header for why.
local function playerPose(player: Player, animId: number, budget: number?)
	local limit = budget or 12
	poseSeq += 1
	local myId = poseSeq
	poseAck[player] = nil
	Remotes.Get("CutscenePose"):FireClient(player, myId, animId)
	local elapsed = 0
	while poseAck[player] ~= myId and elapsed < limit do
		elapsed += task.wait()
		if skipByPlayer[player] then
			break
		end
	end
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
	if newHouse then
		-- Land the player exactly on the authored "Spawn Point" inside House 2
		-- (falls back to a computed spot only if none is found).
		for _, d in newHouse:GetDescendants() do
			if d:IsA("BasePart") then
				local n = normalizeName(d.Name)
				if n == "spawnpoint" or n == "spawnlocation" or n == "spawn" then
					houseSpawnCF = d.CFrame + Vector3.new(0, 3, 0)
					break
				end
			end
		end
	end
	if houseClone then
		houseClone:Destroy()
		houseClone = nil
	end
end

local function spawnPoint(): CFrame
	if houseSpawnCF then
		return houseSpawnCF
	end
	-- Fallback: in front of the house, on the plains ground.
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

	local function skipped(): boolean
		return skipByPlayer[player] == true
	end

	-- The teddy bear is a server-owned model, so its animation plays server-side.
	local teddyAnimator = getAnimator(teddyClone)
	local teddyFalling = if teddyAnimator
		then loadTrack(teddyAnimator, CutsceneData.Anims.TeddyBearFalling)
		else nil

	-- Shot 1: the player types at the desk.
	cut(player, "Shot1")
	placeActor(character, "Rig1")
	fade(player, "in", 0.6)
	playerPose(player, CutsceneData.Anims.Typing, 12)
	if skipped() then
		return
	end

	-- The teddy bear falls out the window and freezes where it LANDS.
	if teddyFalling then
		pcall(function()
			(teddyFalling :: AnimationTrack):Play(0.1)
		end)
		task.spawn(function()
			local track = teddyFalling :: AnimationTrack
			-- AnimationTrack.Length reads 0 until the asset streams in; wait for a
			-- real value so we freeze on the last (landed) frame, not mid-air.
			local len = track.Length
			local guard = 0
			while len <= 0 and guard < 3 do
				guard += task.wait()
				len = track.Length
			end
			if len <= 0 then
				len = 2
			end
			task.wait(math.max(0, len - 0.03))
			pcall(function()
				track:AdjustSpeed(0)
			end)
		end)
	end

	-- The player reaches for the teddy.
	playerPose(player, CutsceneData.Anims.Grabbing, 12)
	if skipped() then
		return
	end

	-- Runs toward the window.
	placeActor(character, "Rig2")
	playerPose(player, CutsceneData.Anims.Running, 12)
	if skipped() then
		return
	end

	-- Shot 2: mid-run. Hold 3.3s, then cut back to Shot 1 while Running 2 plays out.
	cut(player, "Shot2")
	placeActor(character, "Rig3")
	poseSeq += 1
	local r2Id = poseSeq
	poseAck[player] = nil
	Remotes.Get("CutscenePose"):FireClient(player, r2Id, CutsceneData.Anims.Running2)
	task.wait(CutsceneData.Running2HoldSeconds)
	cut(player, "Shot1")
	local elapsed = 0
	while poseAck[player] ~= r2Id and elapsed < 12 do
		elapsed += task.wait()
		if skipped() then
			break
		end
	end
	if skipped() then
		return
	end

	-- Running 2 done: remove the teddy from the scene.
	if teddyClone then
		teddyClone:Destroy()
		teddyClone = nil
	end

	-- Swap the neighborhood for the plains BEHIND a fade to black so the build /
	-- pop-in is never seen; hold on black briefly to let the ground settle.
	fade(player, "out", 0.5)
	task.wait(0.6)
	swapNeighborhoodForPlains()
	task.wait(1.25)
	cut(player, "Shot2")
	placeActor(character, "Rig4")
	fade(player, "in", 0.5)
	task.wait(0.45)
	playerPose(player, CutsceneData.Anims.Running3, 12)

	-- Fade to black, swap the house for House 2, and hand back control at its spawn.
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
	-- Clear any leftover intro scenery (e.g. the neighborhood after an early skip).
	if sceneRoot then
		for _, child in sceneRoot:GetChildren() do
			if child ~= houseClone then
				child:Destroy()
			end
		end
	end
	if houseClone then
		swapHouse()
	end
	local character = player.Character
	if character then
		releaseActor(character, spawnPoint())
	end
	cut(player, "Custom")
	fade(player, "in", 0.4)
	-- Intro's over: mark it done and (finally) hand the player their tools.
	finishedByPlayer[player] = true
	if ToolService then
		ToolService.GiveTool(player)
	end
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
	ToolService = services.ToolService
end

-- True while the given player still needs to finish the intro. ToolService reads
-- this so it doesn't hand out tools until the cutscene is over.
function CutsceneService.IsIntroPending(player: Player): boolean
	if not GameConfig.INTRO_CUTSCENE then
		return false
	end
	return not finishedByPlayer[player]
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

	Remotes.Get("CutscenePoseDone").OnServerEvent:Connect(function(player, poseId)
		poseAck[player] = poseId
	end)

	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end

	Players.PlayerRemoving:Connect(function(player)
		activeByPlayer[player] = nil
		readyByPlayer[player] = nil
		skipByPlayer[player] = nil
		finishedByPlayer[player] = nil
		poseAck[player] = nil
	end)

	print("[CutsceneService] Intro cutscene armed.")
end

return CutsceneService
