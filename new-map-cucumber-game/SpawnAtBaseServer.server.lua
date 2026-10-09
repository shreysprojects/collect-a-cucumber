--[[
	SpawnAtBaseServer  (Script, ServerScriptService)  2026-09-11, fixed 2026-09-13
	Guarantee (user: "when user joins make them spawn at their base"): every character - the first
	one after joining included - starts on its own plot. PlotService already points
	Player.RespawnLocation at the plot's PlotSpawn and re-pivots a character that spawned elsewhere,
	but the first spawn can race the plot assignment (LobbyLayout / DataService are still settling on
	a fresh server) and land at the map's default spawn.
	This script waits for the player's plot (attribute Plot, PlotService) and then looks at the character
	TWICE at most (now and SECOND_TRY later) - and only while it is still a fresh spawn: the plot arrived
	within GRACE_SECONDS of the spawn, the player is not walking (Humanoid.MoveDirection is zero) and
	the character is outside the plot (+ MARGIN). It never loops and never fights the player
	(2026-09-13, user: "when first joining and try running out of my base i keep getting tped back into
	my base" - the old version re-checked every 0.25 s for 4 s counted from the moment the plot
	appeared, so a player already running out was shoved back again and again). The second look exists
	because the first pivot can lose to the client's own spawn replication, or to DayNightCycle's lane
	return when a player joins during the night (the default spawn is beyond the barrier for a frame).
]]

--..Services..--
local Players = game:GetService("Players")

--..Config..--
local GRACE_SECONDS = 4   -- the plot must be known this soon after the spawn, else the player is already playing
local SECOND_TRY = 0.6    -- seconds after the first look for the one and only second look
local MARGIN = 6          -- studs beyond the plot edge that still count as "at the base"
local PLOT_WAIT = 10      -- seconds to wait for PlotService's assignment
local ROOT_UP = 2.6       -- root height above the PlotSpawn (the spawn's top face is flush with the plot)

local Plots = workspace:WaitForChild("Map"):WaitForChild("Lobby"):WaitForChild("Plots")

local function PlotOf(player)
	local name = player:GetAttribute("Plot")
	return name and Plots:FindFirstChild(name) or nil
end

local function OnPlot(plot, position)
	local rp = plot.CFrame:PointToObjectSpace(position)
	return math.abs(rp.X) <= plot.Size.X * 0.5 + MARGIN and math.abs(rp.Z) <= plot.Size.Z * 0.5 + MARGIN
end

local function HomeCFrame(plot)
	local spawn = plot:FindFirstChild("PlotSpawn")
	if spawn then return spawn.CFrame * CFrame.new(0, ROOT_UP, 0) end
	local pos = plot.Position + Vector3.new(0, plot.Size.Y * 0.5 + 3, 0)
	return CFrame.lookAt(pos, pos + Vector3.new(1, 0, 0))
end

local function Settle(player, character)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not root then return end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local t0 = os.clock()
	local plot
	while os.clock() - t0 < PLOT_WAIT do
		plot = PlotOf(player)
		if plot then break end
		task.wait(0.2)
	end
	if not plot or player.Character ~= character or not character.Parent then return end
	if os.clock() - t0 > GRACE_SECONDS then return end -- the plot came late: they are already playing, leave them
	--.. two tries at most: the first can lose to the client's own spawn replication or to DayNightCycle's
	--.. lane return (a night join spawns beyond the barrier for a frame); a second look SECOND_TRY later
	--.. catches that - but never while the player is walking, and never a third time
	for attempt = 1, 2 do
		if player.Character ~= character or not character.Parent then return end
		if not humanoid or humanoid.Health <= 0 then return end
		if humanoid.MoveDirection.Magnitude > 0 then return end -- walking: the player has taken over
		if not OnPlot(plot, root.Position) then
			character:PivotTo(HomeCFrame(plot))
			for _, part in ipairs(character:GetDescendants()) do
				if part:IsA("BasePart") then
					part.AssemblyLinearVelocity = Vector3.zero
					part.AssemblyAngularVelocity = Vector3.zero
				end
			end
			print(("[SpawnAtBase] %s stood on %s (%.1fs after spawning, try %d)"):format(player.Name, plot.Name, os.clock() - t0, attempt))
		end
		if attempt == 1 then task.wait(SECOND_TRY) end
	end
end

local function OnPlayer(player)
	player.CharacterAdded:Connect(function(character) task.spawn(Settle, player, character) end)
	if player.Character then task.spawn(Settle, player, player.Character) end
end
Players.PlayerAdded:Connect(OnPlayer)
for _, player in ipairs(Players:GetPlayers()) do OnPlayer(player) end
print("[SpawnAtBase] a fresh spawn found off its plot within " .. GRACE_SECONDS .. " s is stood on it once")
