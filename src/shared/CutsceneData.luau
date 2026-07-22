--!strict
-- CutsceneData: every hand-authored position the intro cutscene needs.
-- These were measured straight out of the Studio models you sent (CamShots,
-- Rigs, Teddy Bear, House), so the camera + actor line up with the neighborhood.
--
-- CFrame component order is Roblox's 12-number constructor:
--   CFrame.new(x, y, z, R00,R01,R02, R10,R11,R12, R20,R21,R22)

local CutsceneData = {}

-- Camera shots.
CutsceneData.Shots = {
	Shot1 = { -561.7466, 28.5936, -1039.6189, 0.7918, 0.0408, -0.6094, 0, 0.9978, 0.0668, 0.6107, -0.0529, 0.7901 },
	Shot2 = { -539.6353, 0.0474, -1035.5265, 0.4725, 0.5515, 0.6875, 0, 0.7800, -0.6258, -0.8814, 0.2956, 0.3685 },
}

-- Where the player's character (its HumanoidRootPart) stands for each beat.
CutsceneData.Rigs = {
	Rig1 = { -559.9401, 25.8249, -1049.7281, 0, 0, -1, 0, 1, 0, 1, 0, 0 },
	Rig2 = { -559.5205, 25.8249, -1047.0282, -1, 0, 0, 0, 1, 0, 0, 0, -1 },
	Rig3 = { -553.0000, 25.4996, -1040.5000, 0, 0, -1, 0, 1, 0, 1, 0, 0 },
	Rig4 = { -568.4999, 6.2996, -1041.9999, 0, 0, -1, 0, 1, 0, 1, 0, 0 },
}

-- Animation asset IDs you provided.
CutsceneData.Anims = {
	Typing = 119023863884961,
	Grabbing = 71243548991962,
	TeddyBearFalling = 74559717209605,
	Running = 120603020751521,
	Running2 = 87016187754226,
	Running3 = 138688222852369,
}

-- The plains map is (re)built centered on the house when the neighborhood is
-- swapped out. This is the house's footprint center + ground level, measured
-- from House.rbxmx.
CutsceneData.HouseCenter = Vector3.new(-564.75, -1.5, -999.0)

-- How long shot 2 holds on "Running 2" before cutting to shot 1.
CutsceneData.Running2HoldSeconds = 3.3

-- Build a CFrame from a 12-number component array.
function CutsceneData.toCFrame(c: { number }): CFrame
	return CFrame.new(c[1], c[2], c[3], c[4], c[5], c[6], c[7], c[8], c[9], c[10], c[11], c[12])
end

return CutsceneData
