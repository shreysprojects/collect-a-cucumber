--[[
	CucumberMoveServer  (Script, ServerScriptService)  2026-09-13
	Lets a player MOVE a cucumber that already stands on their plot, from build mode (user: "let users
	be able to move cucumbers around in build mode"). Remotes.requestCucumberMove (RemoteFunction):
	  InvokeServer(model, cframe) -> true | false, reason
	Same rules as CucumberCarry.Place: the caller owns the plot and the model (tag PlacedCucumber,
	attribute Owner, standing in plot.Placed - never one a zombie is carrying), stands at the base
	(AT_BASE_MARGIN), the target is rebuilt from the client's X / Z + yaw on the plot surface, the
	RestSize footprint at that yaw must fit inside the plot (BOUNDS_EPSILON), and its box (shrunk by
	COLLISION_SHRINK) may not overlap anything else in Placed (the model's own parts are ignored).
	The model is pivoted to its natural rest pose there (RestRotation / RestLift, exactly like Place)
	and its PlotHitbox is laid upright at the new footprint; BaseSaveAPI.Snapshot is asked for so the
	base save follows at once instead of on its 30 s heartbeat. Refused at night (build mode is
	closed then anyway). MOVE_COOLDOWN between moves.
]]

--..Services..--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")

local CucumberFootprint = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CucumberFootprint")) -- the collision box (smaller than the canopy for wide ones)

--..Config..--
local AT_BASE_MARGIN = 6      -- keep in step with CucumberCarry / BuildService
local COLLISION_SHRINK = 0.96 -- keep in step with CucumberCarry / CucumberPlacementClient
local BOUNDS_EPSILON = 0.05
local MOVE_COOLDOWN = 0.15
local TAG = "PlacedCucumber"

--..Instances..--
local Plots = workspace:WaitForChild("Map"):WaitForChild("Lobby"):WaitForChild("Plots")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local remote = Remotes:FindFirstChild("requestCucumberMove")
if not remote then
	remote = Instance.new("RemoteFunction")
	remote.Name = "requestCucumberMove"
	remote.Parent = Remotes
end

--..State..--
local LastMove = {} -- [player] = os.clock() of the last move

--..Helpers..--
local function PlotOf(player)
	for _, plot in ipairs(Plots:GetChildren()) do
		if plot:IsA("BasePart") and plot:GetAttribute("Owner") == player.UserId then return plot end
	end
	return nil
end

local function Footprint(size, yaw)
	local c, s = math.abs(math.cos(yaw)), math.abs(math.sin(yaw))
	return c * size.X + s * size.Z, s * size.X + c * size.Z
end

--..The move..--
local function Move(player, model, cframe)
	if typeof(model) ~= "Instance" or not model:IsA("Model") then return false, "Can't move that" end
	if typeof(cframe) ~= "CFrame" then return false, "Bad target" end
	if workspace:GetAttribute("CyclePhase") == "Night" then return false, "You can't build at night" end
	local now = os.clock()
	if LastMove[player] and now - LastMove[player] < MOVE_COOLDOWN then return false, "Too fast" end
	local plot = PlotOf(player)
	if not plot then return false, "You have no plot" end
	local holder = plot:FindFirstChild("Placed")
	if not holder or model.Parent ~= holder then return false, "That's not on your plot" end
	if not CollectionService:HasTag(model, TAG) or model:GetAttribute("Owner") ~= player.UserId then return false, "Not yours" end
	if model:GetAttribute("StolenBy") then return false, "A zombie has it" end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return false, "No character" end
	local rp = plot.CFrame:PointToObjectSpace(root.Position)
	if math.abs(rp.X) > plot.Size.X * 0.5 + AT_BASE_MARGIN or math.abs(rp.Z) > plot.Size.Z * 0.5 + AT_BASE_MARGIN then
		return false, "Go to your base"
	end
	local size = model:GetAttribute("RestSize")
	local restRot = model:GetAttribute("RestRotation")
	if typeof(size) ~= "Vector3" or typeof(restRot) ~= "CFrame" then return false, "Can't move that" end
	local lift = tonumber(model:GetAttribute("RestLift")) or size.Y * 0.5
	--.. rebuild the target from the client's X / Z + yaw only, on the plot surface (like Place)
	local relative = plot.CFrame:ToObjectSpace(cframe)
	local _, yaw = relative:ToEulerAnglesYXZ()
	local box = CucumberFootprint.Box(size)
	local fx, fz = Footprint(box, yaw)
	local x, z = relative.Position.X, relative.Position.Z
	if math.abs(x) + fx * 0.5 > plot.Size.X * 0.5 + BOUNDS_EPSILON or math.abs(z) + fz * 0.5 > plot.Size.Z * 0.5 + BOUNDS_EPSILON then
		return false, "Keep it inside your plot"
	end
	local top = plot.Size.Y * 0.5
	local boxCF = plot.CFrame * CFrame.new(x, top + size.Y * 0.5, z) * CFrame.Angles(0, yaw, 0)
	--.. occupied? (anything else in Placed: cucumbers, builds, eggs; its own parts do not count)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = {holder}
	for _, part in ipairs(workspace:GetPartBoundsInBox(boxCF, box, params)) do
		if not part:IsDescendantOf(model) then return false, "Something is already standing there" end
	end
	LastMove[player] = now
	model:PivotTo(plot.CFrame * CFrame.new(x, top + lift, z) * CFrame.Angles(0, yaw, 0) * restRot)
	local hitbox = model:FindFirstChild("PlotHitbox")
	if hitbox then
		hitbox.Size = box -- the footprint rule (an older, full-canopy box shrinks on its first move)
		hitbox.CFrame = boxCF
	end
	local api = ServerStorage:FindFirstChild("BaseSaveAPI")
	local snapshot = api and api:FindFirstChild("Snapshot")
	if snapshot then task.defer(function() pcall(snapshot.Invoke, snapshot, player) end) end
	return true
end

remote.OnServerInvoke = function(player, model, cframe)
	local ok, result, reason = pcall(Move, player, model, cframe)
	if not ok then
		warn("[CucumberMove] " .. tostring(result))
		return false, "Can't move that"
	end
	return result == true, reason
end
Players.PlayerRemoving:Connect(function(player) LastMove[player] = nil end)
print("[CucumberMove] Remotes.requestCucumberMove ready: placed cucumbers move in build mode (placement rules)")
