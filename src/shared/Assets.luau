--!strict
-- Assets: central place for custom image asset IDs used by the UI.
--
-- HOW TO WIRE UP THE ARTWORK (one-time, done inside Roblox Studio):
--   Roblox will only render an image once it has been uploaded to Roblox and
--   given a numeric asset ID -- a raw .png file on disk cannot be shown in-game.
--   The source PNGs live in the repo under `assets/images/` for reference:
--       assets/images/gold-coin.png
--       assets/images/diamond.png
--       assets/images/backpack.png
--   To make them appear in the game:
--     1. Open Roblox Studio (connected to this place via Rojo).
--     2. View -> Asset Manager -> Images -> the green [+] (Add Images / Bulk Import).
--     3. Select the three PNGs from `assets/images/`.
--     4. Wait for moderation to finish, then right-click each -> Copy Asset ID.
--     5. Paste each ID below in the form "rbxassetid://<number>".
--
-- Until an ID is filled in, the UI falls back to the built-in drawn coin /
-- emoji, so nothing breaks while you wait for the uploads to moderate.

local Assets = {
	-- HUD currency + bag icons. Leave as "" to use the built-in fallback.
	GoldCoin = "rbxassetid://94643887905219", -- e.g. "rbxassetid://94643887905219"
	Diamond = "rbxassetid://136845340016196", -- e.g. "rbxassetid://136845340016196"
	Backpack = "rbxassetid://115805650328465", -- e.g. "rbxassetid://115805650328465"
}

return Assets
