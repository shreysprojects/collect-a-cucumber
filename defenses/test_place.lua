--[[
	defenses/test_place.lua -- eval_server_runtime snippet for a solo playtest: stands player 1 at the
	front of their plot, places one defence of KEY on the plot the way BuildService would (a clone of
	the ReplicatedStorage.PlaceableBuilds.Defences template, pivoted onto the plot surface with the
	placement attributes and the PlacedBuild tag, so DefenceService registers it), then spawns
	ZOMBIES zombies of VARIETY in front of the player with the ZombieDev "spawn:" hook.
	Edit KEY / VARIETY / ZOMBIES / OFFSET before running. Returns a one-line summary.
]]
local KEY = "Mortar"
local VARIETY = "Rotten Shambler"
local ZOMBIES = 3
local OFFSET = Vector3.new(-10, 0, 0) -- from the plot centre, plot X is the front direction (-X = front)

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local RS = game:GetService("ReplicatedStorage")
local BuildCatalog = require(RS.Modules.BuildCatalog)
local player = Players:GetPlayers()[1]
local plot
for _, p in ipairs(workspace.Map.Lobby.Plots:GetChildren()) do
	if p:IsA("BasePart") and p:GetAttribute("Owner") == player.UserId then plot = p end
end
if not plot then return "no plot for " .. player.Name end
local template = RS:WaitForChild("PlaceableBuilds"):WaitForChild("Defences"):FindFirstChild(KEY)
if not template then return "no template " .. KEY end
local holder = plot:FindFirstChild("Placed") or Instance.new("Folder")
holder.Name = "Placed"
holder.Parent = plot
--.. drop any earlier test copy of this key
for _, m in ipairs(holder:GetChildren()) do
	if m:GetAttribute("BuildKey") == KEY and m:GetAttribute("TestBuild") then m:Destroy() end
end
local placed = template:Clone()
local surfaceY = BuildCatalog.SurfaceY(plot, 1)
local hitbox = placed.PrimaryPart
local pos = plot.Position + OFFSET
local cf = CFrame.new(pos.X, surfaceY + hitbox.Size.Y * 0.5, pos.Z) -- yaw 0: the prop's front (-Z) faces... the plot front is -X, so turn it
cf = CFrame.new(cf.Position) * CFrame.Angles(0, math.rad(90), 0) -- prop -Z -> world -X (the front of the plot)
placed:PivotTo(cf)
placed.Name = KEY
placed:SetAttribute("Owner", player.UserId)
placed:SetAttribute("BuildKey", KEY)
placed:SetAttribute("Category", "Defences")
placed:SetAttribute("DisplayName", template:GetAttribute("DisplayName"))
placed:SetAttribute("Cost", template:GetAttribute("Cost"))
placed:SetAttribute("Source", template:GetAttribute("Source"))
placed:SetAttribute("Level", 1)
placed:SetAttribute("PlotX", OFFSET.X)
placed:SetAttribute("PlotZ", OFFSET.Z)
placed:SetAttribute("Yaw", 90)
placed:SetAttribute("TestBuild", true)
placed.Parent = holder
CollectionService:AddTag(placed, BuildCatalog.PLACED_TAG)
--.. the player stands in front of the defence, looking out of the plot (toward -X)
local char = player.Character
local root = char and char:FindFirstChild("HumanoidRootPart")
local hum = char and char:FindFirstChildOfClass("Humanoid")
if root and hum then
	root.CFrame = CFrame.lookAt(Vector3.new(pos.X - 8, surfaceY + hum.HipHeight + root.Size.Y * 0.5 + 0.3, pos.Z), Vector3.new(pos.X - 30, surfaceY + 3, pos.Z))
	root.AssemblyLinearVelocity = Vector3.zero
end
task.wait(0.3)
for i = 1, ZOMBIES do
	workspace:SetAttribute("ZombieDev", nil)
	task.wait(0.05)
	workspace:SetAttribute("ZombieDev", "spawn:" .. VARIETY)
	task.wait(0.35)
end
return string.format("%s placed at %s (hitbox %s), %d x %s spawned in front of %s", KEY, tostring(cf.Position), tostring(hitbox.Size), ZOMBIES, VARIETY, player.Name)
