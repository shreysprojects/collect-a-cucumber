--[[
	PlotService  (Script, ServerScriptService)
	Assigns every joining player a random free plot from workspace.Map.Lobby.Plots
	and makes them spawn (and respawn) at the very front of that plot.

	  * plots = the BaseParts inside the Plots folder ("Plot 1".."Plot 6"); a plot
	    is free while it has no Owner attribute
	  * "front" = the plot edge facing the lobby interior: FRONT_DIRECTION below
	    (world -X, the west edge at x~1224; the east edge sits against the lobby wall)
	  * one invisible SpawnLocation is created per plot at that edge; the player's
	    RespawnLocation points at it, so every respawn lands there too. A
	    CharacterAdded check re-pivots the character if the engine spawned it
	    anywhere else (first-join race / overflow).
	  * attributes: plot.Owner (UserId), plot.OwnerName, player.Plot (plot name)
	  * on leave the plot is released and its attributes cleared
	  * more players than plots: the extra player gets no plot, spawns at
	    FALLBACK_SPAWN (lobby centre) and a warning is logged. Set MaxPlayers in
	    Game Settings to the plot count (6) to avoid that.
]]

--..Services..--
local Players = game:GetService("Players")

--..Config..--
local PLOTS_FOLDER = workspace:WaitForChild("Map"):WaitForChild("Lobby"):WaitForChild("Plots")
local FRONT_DIRECTION = Vector3.new(-1, 0, 0) -- world direction from a plot's centre to its front edge (toward the lobby interior)
local FRONT_INSET = 3 -- studs inside the front edge, so the player stands on the plot, not on its lip
local FACE_INTO_PLOT = true -- true: spawn looking into the plot; false: looking out at the lobby
local FALLBACK_SPAWN = CFrame.new(1234, -226, 130) -- lobby centre, used only when every plot is taken
local SPAWN_TOLERANCE = 8 -- studs; if the freshly spawned character is farther than this from its spawn point it is moved there

--..State..--
local Plots = {} -- ordered list of plot parts
local SpawnFor = {} -- [plot] = SpawnLocation
local PlotOf = {} -- [player] = plot
local OwnerOf = {} -- [plot] = player

--..Geometry..--
local function FrontCFrame(plot)
	--.. half-extent of the plot along FRONT_DIRECTION, whatever way the part is rotated
	local cf, size = plot.CFrame, plot.Size
	local half = math.abs(FRONT_DIRECTION:Dot(cf.RightVector)) * size.X * 0.5
		+ math.abs(FRONT_DIRECTION:Dot(cf.UpVector)) * size.Y * 0.5
		+ math.abs(FRONT_DIRECTION:Dot(cf.LookVector)) * size.Z * 0.5
	local top = plot.Position.Y + size.Y * 0.5
	local pos = Vector3.new(plot.Position.X, top, plot.Position.Z) + FRONT_DIRECTION * (half - FRONT_INSET)
	local facing = FACE_INTO_PLOT and -FRONT_DIRECTION or FRONT_DIRECTION
	return CFrame.lookAt(pos, pos + facing)
end

local function BuildSpawn(plot)
	local existing = plot:FindFirstChild("PlotSpawn")
	if existing then existing:Destroy() end
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "PlotSpawn"
	spawn.Size = Vector3.new(4, 1, 4)
	spawn.CFrame = FrontCFrame(plot) * CFrame.new(0, 0.5, 0) -- top face flush with the plot surface
	spawn.Anchored = true
	spawn.CanCollide = false
	spawn.CanQuery = false
	spawn.CanTouch = false
	spawn.Transparency = 1
	spawn.Neutral = true
	spawn.Enabled = false -- never a default spawn; only reached through Player.RespawnLocation
	spawn.Duration = 0 -- no spawn forcefield
	spawn.Parent = plot
	return spawn
end

--..Plots..--
for _, p in ipairs(PLOTS_FOLDER:GetChildren()) do
	if p:IsA("BasePart") then Plots[#Plots + 1] = p end
end
table.sort(Plots, function(a, b)
	local ia, ib = tonumber(a:GetAttribute("PlotIndex")), tonumber(b:GetAttribute("PlotIndex"))
	if ia and ib then return ia < ib end
	return a.Name < b.Name
end)
for _, plot in ipairs(Plots) do
	plot:SetAttribute("Owner", nil)
	plot:SetAttribute("OwnerName", nil)
	SpawnFor[plot] = BuildSpawn(plot)
end
if #Plots == 0 then warn("[PlotService] no plots found in " .. PLOTS_FOLDER:GetFullName()) end

local function FreePlots()
	local free = {}
	for _, plot in ipairs(Plots) do
		if not OwnerOf[plot] then free[#free + 1] = plot end
	end
	return free
end

local function SpawnCFrameFor(player)
	local plot = PlotOf[player]
	if plot then return FrontCFrame(plot) * CFrame.new(0, 3, 0) end -- HumanoidRootPart sits ~3 studs above the ground
	return FALLBACK_SPAWN
end

--..Assignment..--
local function Assign(player)
	if PlotOf[player] then return PlotOf[player] end
	local free = FreePlots()
	if #free == 0 then
		warn(("[PlotService] no free plot for %s (%d plots, %d players)"):format(player.Name, #Plots, #Players:GetPlayers()))
		player.RespawnLocation = nil
		return nil
	end
	local plot = free[math.random(#free)]
	PlotOf[player] = plot
	OwnerOf[plot] = player
	plot:SetAttribute("Owner", player.UserId)
	plot:SetAttribute("OwnerName", player.Name)
	player:SetAttribute("Plot", plot.Name)
	player.RespawnLocation = SpawnFor[plot]
	print(("[PlotService] %s -> %s"):format(player.Name, plot.Name))
	return plot
end

local function Release(player)
	local plot = PlotOf[player]
	if not plot then return end
	PlotOf[player] = nil
	OwnerOf[plot] = nil
	plot:SetAttribute("Owner", nil)
	plot:SetAttribute("OwnerName", nil)
	player:SetAttribute("Plot", nil)
end

--..Spawning..--
local function PlaceCharacter(player, character)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not root then return end
	if not character:IsDescendantOf(workspace) then
		character.AncestryChanged:Wait()
	end
	task.wait() -- let the engine finish its own spawn placement first
	local target = SpawnCFrameFor(player)
	if (root.Position - target.Position).Magnitude > SPAWN_TOLERANCE then
		character:PivotTo(target)
	end
end

local function OnPlayer(player)
	Assign(player)
	player.CharacterAdded:Connect(function(character)
		PlaceCharacter(player, character)
	end)
	if player.Character then
		PlaceCharacter(player, player.Character)
	end
end

Players.PlayerAdded:Connect(OnPlayer)
Players.PlayerRemoving:Connect(Release)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(OnPlayer, player)
end
