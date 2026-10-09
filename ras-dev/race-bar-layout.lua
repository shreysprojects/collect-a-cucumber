-- Re-applies the compact race progress bar layout to StarterGui.RaceProgressGui
-- (RAS - Dev). Run in EDIT mode via execute_luau (official Roblox_Studio MCP works).
-- The gui itself comes from assets/RaceProgressGui.rbxm (original tall layout); after
-- importing that, run this, then set RaceProgressController.Source from
-- src/RaceProgressController.lua (compact 44 px marker riding on the bar).
--
-- Layout: bar half the screen wide at the very top (y 14, 34 px tall), labels just
-- below the bar ends, markers frame sharing the bar box.
--
-- 2026-09-22: do NOT re-run this on the current Studio gui - it resets the team's 58 px
-- Track to 34 px. Only use it on a fresh import of assets/RaceProgressGui.rbxm. The
-- controller now handles the rest at runtime: DisplayOrder -1 (under HUD / Menu), a
-- UIScale that keeps the bar above MainUI.DistanceRolled / CoinsMade, and the slide-out
-- while PlayerGui "PanelOpen" is set.

local gui = game.StarterGui.RaceProgressGui
local root = gui.Root
local track = root.Track
local shadow = root.TrackShadow
local markers = root.Markers
local startLabel = root:FindFirstChild("StartLabel") or track:FindFirstChild("StartLabel")
local finishLabel = root:FindFirstChild("FinishLabel") or track:FindFirstChild("FinishLabel")

local WIDTH, TOP, HEIGHT = 0.5, 14, 34
local left = 0.5 - WIDTH / 2
local right = 0.5 + WIDTH / 2
local labelY = TOP + HEIGHT + 3

track.AnchorPoint = Vector2.new(0.5, 0)
track.Position = UDim2.new(0.5, 0, 0, TOP)
track.Size = UDim2.new(WIDTH, 0, 0, HEIGHT)
track.UICorner.CornerRadius = UDim.new(0, 17)
track.Outline.Thickness = 3
local sheen = track:FindFirstChild("TopSheen")
if sheen then
	sheen.Position = UDim2.new(0, 10, 0, 5)
	sheen.Size = UDim2.new(1, -20, 0, 2)
end

shadow.AnchorPoint = Vector2.new(0.5, 0)
shadow.Position = UDim2.new(0.5, 2, 0, TOP + 3)
shadow.Size = UDim2.new(WIDTH, 0, 0, HEIGHT)
shadow.UICorner.CornerRadius = UDim.new(0, 17)

markers.AnchorPoint = Vector2.new(0.5, 0)
markers.Position = UDim2.new(0.5, 0, 0, TOP)
markers.Size = UDim2.new(WIDTH, 0, 0, HEIGHT)
markers.ClipsDescendants = false

startLabel.Parent = root
startLabel.AnchorPoint = Vector2.new(0, 0)
startLabel.Position = UDim2.new(left, 2, 0, labelY)
startLabel.Size = UDim2.new(0, 80, 0, 22)
startLabel.TextXAlignment = Enum.TextXAlignment.Left
startLabel.TextSize = 18
startLabel.ZIndex = 8

finishLabel.Parent = root
finishLabel.AnchorPoint = Vector2.new(1, 0)
finishLabel.Position = UDim2.new(right, -2, 0, labelY)
finishLabel.Size = UDim2.new(0, 140, 0, 22)
finishLabel.TextXAlignment = Enum.TextXAlignment.Right
finishLabel.TextSize = 18
finishLabel.ZIndex = 8

root.Size = UDim2.new(1, 0, 0, labelY + 22 + 4)

return "compact race bar layout applied"
