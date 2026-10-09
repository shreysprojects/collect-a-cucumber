-- Portal routes from Zombie Cucumber Game (no unlock costs). 2026-09-23: a finished run pays Cash, see REWARDS.
-- 2026-09-22: night rules (closed 1 min before night, 30 s warning, home at nightfall); see NIGHT RULES.
-- 2026-09-22 (later): 1 hour per-player cooldown per portal + a strength requirement per portal, shown on a
-- sign above each portal; see COOLDOWNS + STRENGTH.
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local PortalService = {}
local Transition = require(ServerStorage:WaitForChild("PortalTransitionService"))
local Hunt = require(ServerStorage:WaitForChild("DesertHuntService"))
local DataService = require(ServerStorage:WaitForChild("DataService"))
local NumberAbbrev = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("NumberAbbrev"))
local definitions = {
	StarterObby = {Template = "Classic Obby", Title = "Classic Obby", Spawn = "PortalSpawn", Finish = {"Reward Tresure", "Chest"}},
	DesertHunt = {Template = "Wild_West", Title = "Wild West", Spawn = "PortalSpawn"},
	SnowAvalanche = {Template = "Avalanche", Title = "Avalanche", Spawn = "SpawnLocation", Finish = {"Completion"}},
	LavaRun = {Template = "LavaRun", Title = "Lava Run", Spawn = "SpawnLocation", Finish = {"Completion"}},
	VoidBloxout = {Template = "BloxoutIncorporated", Title = "Bloxout Incorporated", Spawn = "SpawnLocation", Finish = {"Completion"}},
}
-- REWARDS (2026-09-23 economy): a FINISHED run (the map's finish trigger / the Wild West hunt's
-- completion, never the Home button or the night return) pays Cash = about 10 minutes of the biome's
-- income, keyed like the cooldown: the portal's PortalId attribute when it has one, else its
-- PortalDestination (the Neon Portal carries PortalId "NeonPortal" so it is not the Snow biome's
-- Avalanche). Credited through DataService.Increment and announced with a "Reward" state the HUD
-- turns into the game-wide toast.
PortalService.PORTAL_REWARDS = {
	StarterObby = 6000, DesertHunt = 48000, IcePortal = 25000000, LavaRun = 1600000000,
	VoidBloxout = 12600000000, NeonPortal = 800000000000,
}
local templates = ServerStorage:WaitForChild("PortalMaps")
local sessions, portals, connections = {}, {}, {}
local nextSlot, freeSlots, entryAfter = 0, {}, {}
local activeFolder, stateEvent
local started = false

-- NIGHT RULES (2026-09-22, user): portals close BLOCK_BEFORE_NIGHT seconds before night (a touch is
-- refused with BLOCKED_TEXT, shown at most once per BLOCKED_REPEAT seconds per player); anyone still
-- in a portal map is warned WARN_BEFORE_NIGHT seconds before night (StateChanged "NightWarning";
-- PortalHudClient also counts down) and is sent home as night falls. The trip home starts
-- RETURN_LEAD seconds early so the iris transition is over when DayNightCycle flips CyclePhase to
-- "Night": the raid's SendHome and its den cutscene then find the player in the lobby. Before this,
-- SendHome pulled a raided player to their plot and the fall check below threw them straight back
-- to the map's start, so they sat out the raid inside the portal and lost cucumbers.
-- The clock is DayNightCycle's shared one (workspace CyclePhase / PhaseEndsAt).
PortalService.BLOCK_BEFORE_NIGHT = 60
PortalService.WARN_BEFORE_NIGHT = 30
PortalService.RETURN_LEAD = 2
PortalService.BLOCKED_TEXT = "Portals are blocked 1 min before night!"
PortalService.NIGHT_TEXT = "Portals are closed at night!"
local BLOCKED_REPEAT = 3
local blockedNoticeAfter = {}

-- seconds of daylight left, or nil outside the "Day" phase
local function secondsToNight()
	if workspace:GetAttribute("CyclePhase") ~= "Day" then return nil end
	local endsAt = workspace:GetAttribute("PhaseEndsAt")
	if typeof(endsAt) ~= "number" then return nil end
	return endsAt - workspace:GetServerTimeNow()
end

-- true once everyone in a portal map should be on the way home for the night
local function nightReturnDue()
	if workspace:GetAttribute("CyclePhase") == "Night" then return true end
	local left = secondsToNight()
	return left ~= nil and left <= PortalService.RETURN_LEAD
end

-- nil while the portals are open, else the refusal shown to the player
function PortalService.ClosedReason()
	if workspace:GetAttribute("CyclePhase") == "Night" then return PortalService.NIGHT_TEXT end
	local left = secondsToNight()
	if left and left <= PortalService.BLOCK_BEFORE_NIGHT then return PortalService.BLOCKED_TEXT end
	return nil
end

-- COOLDOWNS + STRENGTH (2026-09-22, user): every portal has a COOLDOWN_SECONDS (1 hour) cooldown per
-- player, started when a run begins, saved in Data.PortalCooldowns[destination] (the server time it
-- opens again, so it survives a rejoin) and mirrored on the player attribute PortalReadyAt_<destination>
-- for the signs. Every portal model carries the authored attribute StrengthRequired (Spawn 75, Desert
-- 560, Snow "Ice Portal" 740K, Volcano "Volcano Portal" 73M, Narmek 1.35B, Neon 1.9T: the biome signs'
-- "recommended" numbers, changed up); Data.Strength must reach it. A portal frame WITHOUT a
-- PortalDestination is never hooked (no sign, no entry): the Snow and Volcano frames sat unhooked in
-- their biomes' Decor folders as "Model" until 2026-09-22. The sign above each portal is an invisible anchor part "PortalSign" (tag PortalSign, attrs
-- PortalDestination / StrengthRequired) that PortalSignClient dresses for the local player.
PortalService.COOLDOWN_SECONDS = 3600
local COOLDOWN_ATTR = "PortalReadyAt_"
local SIGN_TAG = "PortalSign"
local SIGN_LIFT = 1.5 -- studs between the portal's top and the sign's bottom edge

-- The cooldown is per PORTAL: its optional PortalId attribute, else its PortalDestination. Two portals
-- can lead to one map (2026-09-22: the Snow biome's Ice Portal and the Neon Portal both open the
-- Avalanche), and each keeps its own hour; the older portals have no PortalId, so their saved keys stay.
local function cooldownKey(portal)
	local id = portal:GetAttribute("PortalId")
	if typeof(id) == "string" and id ~= "" then return id end
	return portal:GetAttribute("PortalDestination")
end

-- 3600 -> "1:00:00", 3599 -> "59:59", 42 -> "0:42"
function PortalService.FormatTime(seconds)
	local s = math.max(0, math.ceil(seconds))
	if s >= 3600 then return ("%d:%02d:%02d"):format(s // 3600, s % 3600 // 60, s % 60) end
	return ("%d:%02d"):format(s // 60, s % 60)
end

-- seconds until the player may use this portal again (0 = ready)
function PortalService.CooldownLeft(player, key)
	local readyAt = player:GetAttribute(COOLDOWN_ATTR .. tostring(key))
	if typeof(readyAt) ~= "number" then return 0 end
	return math.max(0, readyAt - workspace:GetServerTimeNow())
end

local function startCooldown(player, key)
	local readyAt = workspace:GetServerTimeNow() + PortalService.COOLDOWN_SECONDS
	player:SetAttribute(COOLDOWN_ATTR .. key, readyAt)
	local data = DataService.GetData(player)
	if data then
		if type(data.PortalCooldowns) ~= "table" then data.PortalCooldowns = {} end
		data.PortalCooldowns[key] = readyAt
		DataService.RequestSave(player)
	end
end

-- saved cooldowns -> player attributes once the profile is in (expired entries are dropped)
local function loadCooldowns(player)
	local data = DataService.WaitForData(player, 60)
	if not data or player.Parent ~= Players or type(data.PortalCooldowns) ~= "table" then return end
	local now = workspace:GetServerTimeNow()
	for key, readyAt in pairs(data.PortalCooldowns) do
		if type(key) == "string" and type(readyAt) == "number" and readyAt > now then
			player:SetAttribute(COOLDOWN_ATTR .. key, readyAt)
		else
			data.PortalCooldowns[key] = nil
		end
	end
end

function PortalService.StrengthRequired(portal)
	local value = portal:GetAttribute("StrengthRequired")
	return typeof(value) == "number" and value or 0
end

local function strengthOf(player)
	local value = DataService.Get(player, "Strength")
	return typeof(value) == "number" and value or 0
end

-- the invisible anchor above the portal that PortalSignClient hangs the per-player sign on
local function addSign(portal)
	local cf, size = portal:GetBoundingBox()
	local sign = Instance.new("Part")
	sign.Name = "PortalSign"
	sign.Size = Vector3.new(1, 1, 1)
	sign.Transparency = 1
	sign.Anchored, sign.CanCollide, sign.CanQuery, sign.CanTouch, sign.CastShadow = true, false, false, false, false
	sign.CFrame = CFrame.new(cf.Position + Vector3.new(0, size.Y / 2 + SIGN_LIFT, 0))
	sign:SetAttribute("PortalDestination", portal:GetAttribute("PortalDestination"))
	sign:SetAttribute("CooldownKey", cooldownKey(portal))
	sign:SetAttribute("StrengthRequired", PortalService.StrengthRequired(portal))
	CollectionService:AddTag(sign, SIGN_TAG)
	sign.Parent = portal
	portal:GetAttributeChangedSignal("StrengthRequired"):Connect(function()
		sign:SetAttribute("StrengthRequired", PortalService.StrengthRequired(portal))
	end)
end

local function characterParts(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return character, humanoid, root
end

local function movePlayer(player, target)
	local character, humanoid, root = characterParts(player)
	if not root or not humanoid or humanoid.Health <= 0 then return false end
	local seat = humanoid.SeatPart
	local weld = seat and seat:FindFirstChild("SeatWeld")
	if weld then weld:Destroy() end
	humanoid.Sit = false
	humanoid.PlatformStand = false
	character:PivotTo(target)
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			part.AssemblyLinearVelocity = Vector3.zero
			part.AssemblyAngularVelocity = Vector3.zero
		end
	end
	return true
end

local function homeCFrame()
	local cf = workspace:GetAttribute("LobbyReturnCFrame")
	if typeof(cf) == "CFrame" then return cf + Vector3.new(0, 1, 0) end
	local marker = workspace.Map.Lobby:FindFirstChild("NightReturnPoint")
	if marker then return marker.CFrame + Vector3.new(0, 1, 0) end
	-- The day/night controller normally supplies the central lobby return point.
	local floor = workspace.Map.Lobby:FindFirstChild("Floor", true)
	if floor and floor:IsA("BasePart") then return floor.CFrame + Vector3.new(0, floor.Size.Y / 2 + 4, 0) end
	return CFrame.new(1190, -222, 130)
end

local function clearSession(player)
	local session = sessions[player]
	sessions[player] = nil
	player:SetAttribute("InPortalMinigame", false)
	player:SetAttribute("MinigameKey", nil)
	player:SetAttribute("MinigameName", nil)
	player:SetAttribute("MinigameRunStart", nil)
	if session then
		Hunt.Cleanup(player)
		for _, connection in ipairs(session.Connections) do connection:Disconnect() end
		if session.Map then session.Map:Destroy() end
		table.insert(freeSlots, session.Slot)
	end
	return session
end

function PortalService.ReturnHome(player, reason)
	local session = sessions[player]
	if not session or session.Busy then return false end
	session.Busy = true
	local elapsed = workspace:GetServerTimeNow() - session.StartedAt
	entryAfter[player] = os.clock() + 1.5
	local moved = Transition.Teleport(player, homeCFrame(), movePlayer)
	if not moved then moved = movePlayer(player, homeCFrame()) end
	player:SetAttribute("PortalPendingHome", not moved or nil)
	clearSession(player)
	player:SetAttribute("BiomeIndex", 1)
	if player.Parent == Players then
		stateEvent:FireClient(player, "Home", reason or "Home", elapsed)
	end
	-- REWARDS: only a finished run pays (Busy above makes sure one run pays once whichever finish
	-- path fired first); the Home button and the night return pay nothing
	local reward = reason == "Finished" and session.RewardKey and PortalService.PORTAL_REWARDS[session.RewardKey] or nil
	if reward and reward > 0 and player.Parent == Players then
		if DataService.Increment(player, "Cash", reward) then
			stateEvent:FireClient(player, "Reward", ("Portal cleared! +$%s"):format(NumberAbbrev.Abbrev(reward)))
		else
			warn(("[PortalService] %s finished %s but the %s Cash reward could not be credited"):format(player.Name, tostring(session.RewardKey), tostring(reward)))
		end
	end
	return true
end

local function inside(part, position, padding)
	local p = part.CFrame:PointToObjectSpace(position)
	local h = part.Size * 0.5 + Vector3.new(padding, padding, padding)
	return math.abs(p.X) <= h.X and math.abs(p.Y) <= h.Y and math.abs(p.Z) <= h.Z
end

local function partBounds(container)
	if container:IsA("BasePart") then return container.CFrame, container.Size end
	if container:IsA("Model") then return container:GetBoundingBox() end
	local low, high = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
	local found = false
	for _, part in ipairs(container:GetDescendants()) do
		if part:IsA("BasePart") then
			found = true
			for x = -1, 1, 2 do for y = -1, 1, 2 do for z = -1, 1, 2 do
				local p = part.CFrame:PointToWorldSpace(part.Size * Vector3.new(x, y, z) * 0.5)
				low, high = low:Min(p), high:Max(p)
			end end end
		end
	end
	if not found then return nil end
	return CFrame.new((low + high) * 0.5), high - low
end

local function resetToStart(player, session)
	if sessions[player] ~= session or os.clock() < session.ResetAfter then return end
	session.ResetAfter = os.clock() + 0.7
	movePlayer(player, session.Spawn)
end

local function configureMap(player, session, definition)
	local map = session.Map
	if definition.Finish then
		local finish = map
		for _, name in ipairs(definition.Finish) do finish = finish and finish:FindFirstChild(name) end
		local cf, size
		if finish then cf, size = partBounds(finish) end
		assert(cf and size, definition.Template .. " is missing its existing finish")
		local trigger = Instance.new("Part")
		trigger.Name = "PortalFinishTrigger"
		trigger.CFrame = cf
		trigger.Size = size + Vector3.new(2, 2, 2)
		trigger.Anchored, trigger.CanCollide, trigger.CanQuery = true, false, false
		trigger.Transparency = 1
		trigger.Parent = map
		session.Finish = trigger
		table.insert(session.Connections, trigger.Touched:Connect(function(hit)
			if sessions[player] == session and player.Character and hit:IsDescendantOf(player.Character) then
				PortalService.ReturnHome(player, "Finished")
			end
		end))
	end

	-- Keep the internal stage teleports required to traverse Bloxout's existing map.
	local teleports = map:FindFirstChild("Teleports")
	if teleports then
		for stage = 1, 3 do
			local trigger, target = teleports:FindFirstChild("Teleport" .. stage), teleports:FindFirstChild("Reach" .. stage)
			if trigger and target and trigger:IsA("BasePart") and target:IsA("BasePart") then
				trigger.CanCollide, trigger.CanTouch = false, true
				table.insert(session.Connections, trigger.Touched:Connect(function(hit)
					if sessions[player] ~= session or not player.Character or not hit:IsDescendantOf(player.Character)
						or os.clock() < session.ResetAfter then return end
					session.ResetAfter = os.clock() + 0.7
					movePlayer(player, target.CFrame * CFrame.new(0, 4, 0))
				end))
			end
		end
	end
end

function PortalService.Enter(player, portal)
	local definition = definitions[portal and portal:GetAttribute("PortalDestination")]
	local trigger = portals[portal]
	local character, humanoid, root = characterParts(player)
	if not definition or not trigger or sessions[player] or not root or not humanoid or humanoid.Health <= 0
		or os.clock() < (entryAfter[player] or 0) or not inside(trigger, root.Position, 5) then return false end
	-- Night rules (closed from BLOCK_BEFORE_NIGHT seconds before night until dawn), then this player's
	-- cooldown on this portal, then its strength requirement.
	local key = cooldownKey(portal)
	local refusal = PortalService.ClosedReason()
	if not refusal then
		local wait = PortalService.CooldownLeft(player, key)
		local required = PortalService.StrengthRequired(portal)
		if wait > 0 then
			refusal = "Portal on cooldown! Come back in " .. PortalService.FormatTime(wait)
		elseif strengthOf(player) < required then
			refusal = ("You need %s strength to enter this portal!"):format(NumberAbbrev.Abbrev(required))
		end
	end
	if refusal then
		if os.clock() >= (blockedNoticeAfter[player] or 0) then
			blockedNoticeAfter[player] = os.clock() + BLOCKED_REPEAT
			stateEvent:FireClient(player, "Blocked", refusal)
		end
		return false
	end
	-- Reserve before cloning so simultaneous touches cannot start two runs.
	local slot = table.remove(freeSlots)
	if not slot then nextSlot += 1 slot = nextSlot end
	local session = {Slot = slot, Connections = {}, ResetAfter = 0, Busy = true, StartedAt = workspace:GetServerTimeNow(), RewardKey = key} -- RewardKey: PORTAL_REWARDS on a finish
	sessions[player] = session
	local ok, err = pcall(function()
		local template = templates:FindFirstChild(definition.Template)
		assert(template and template:IsA("Model"), "Missing portal map " .. definition.Template)
		local map = template:Clone()
		session.Map = map
		map.Name = definition.Template .. "_" .. player.UserId
		map.ModelStreamingMode = Enum.ModelStreamingMode.PersistentPerPlayer
		map:SetAttribute("OwnerUserId", player.UserId)
		map:SetAttribute("PortalDestination", portal:GetAttribute("PortalDestination"))
		local spawn = map:FindFirstChild(definition.Spawn)
		assert(spawn and spawn:IsA("BasePart"), "Missing map spawn")
		local destination = Vector3.new((slot - 1) * 5000, 2000, 10000)
		local delta = destination - spawn.Position
		map:PivotTo(map:GetPivot() + delta)
		for _, d in ipairs(map:GetDescendants()) do
			if d:IsA("LuaSourceContainer") then d:Destroy()
			elseif d:IsA("SpawnLocation") then d.Enabled = false d.Transparency = 1 d.CanCollide = false end
		end
		session.Spawn = spawn.CFrame * CFrame.Angles(0, math.pi, 0) + Vector3.new(0, 4, 0)
		local cf, size = map:GetBoundingBox()
		session.FallY = cf.Position.Y - size.Y / 2 - 30
		configureMap(player, session, definition)
		map.Parent = activeFolder
		map:AddPersistentPlayer(player)
		assert(player.Character == character and Transition.Teleport(player, session.Spawn, movePlayer), "Portal entry was interrupted")
		assert(sessions[player] == session, "Portal session cancelled")
		session.StartedAt = workspace:GetServerTimeNow()
		player:SetAttribute("MinigameKey", portal:GetAttribute("PortalDestination"))
		player:SetAttribute("MinigameName", definition.Title)
		player:SetAttribute("MinigameRunStart", session.StartedAt)
		player:SetAttribute("InPortalMinigame", true)
		startCooldown(player, key) -- the hour starts with the run
		session.Busy = false
		if definition.Template == "Wild_West" then Hunt.Attach(player, session, function() PortalService.ReturnHome(player, "Finished") end) end
		stateEvent:FireClient(player, "Enter", definition.Title)
	end)
	if not ok then
		warn("[PortalService] " .. tostring(err))
		clearSession(player)
		movePlayer(player, homeCFrame())
		entryAfter[player] = os.clock() + 2
		return false
	end
	return true
end

local function hookPortal(portal)
	if portals[portal] or not portal:IsA("Model") or not definitions[portal:GetAttribute("PortalDestination")] then return end
	local plane
	for _, part in ipairs(portal:GetDescendants()) do
		if part:IsA("BasePart") and part.Transparency > 0 and part.Transparency < 1
			and math.min(part.Size.X, part.Size.Y, part.Size.Z) < 1 then plane = part break end
	end
	if not plane then warn("[PortalService] No entrance plane: " .. portal:GetFullName()) return end
	plane.CanCollide = false
	local trigger = Instance.new("Part")
	trigger.Name = "PortalEntryTrigger"
	trigger.Size = plane.Size + Vector3.new(0, 0, 4)
	trigger.CFrame = plane.CFrame
	trigger.Anchored, trigger.CanCollide, trigger.CanQuery = true, false, false
	trigger.Transparency = 1
	trigger.Parent = portal
	portals[portal] = trigger
	addSign(portal)
	table.insert(connections, trigger.Touched:Connect(function(hit)
		local character = hit:FindFirstAncestorOfClass("Model")
		local player = character and Players:GetPlayerFromCharacter(character)
		if player then PortalService.Enter(player, portal) end
	end))
end

local function watchPlayer(player)
	task.spawn(loadCooldowns, player)
	table.insert(connections, player.CharacterAdded:Connect(function(character)
		task.spawn(function()
			local root = character:WaitForChild("HumanoidRootPart", 10)
			if not root then return end
			task.wait(0.5) -- after the plot spawn handler
			if player.Character ~= character then return end
			local session = sessions[player]
			if session and session.Map and session.Map.Parent and not session.Busy and nightReturnDue() then
				-- respawned when the night return is due: the run is over and the player stays where
				-- the respawn put them (their plot / the lobby) instead of going back into the map
				clearSession(player)
				entryAfter[player] = os.clock() + 1.5
				player:SetAttribute("BiomeIndex", 1)
				stateEvent:FireClient(player, "Home", "Night", 0)
			elseif session and session.Map and session.Map.Parent then
				movePlayer(player, session.Spawn)
				Hunt.Equip(player)
			elseif player:GetAttribute("PortalPendingHome") then
				movePlayer(player, homeCFrame())
				player:SetAttribute("PortalPendingHome", nil)
			end
		end)
	end))
end

function PortalService.Start()
	if started then return end
	started = true
	activeFolder = Instance.new("Folder")
	activeFolder.Name = "PortalInstances"
	activeFolder.Parent = workspace
	local remotes = Instance.new("Folder")
	remotes.Name = "MinigameHudRemotes"
	-- the night-rule timings, read by PortalHudClient's countdown
	remotes:SetAttribute("BlockBeforeNight", PortalService.BLOCK_BEFORE_NIGHT)
	remotes:SetAttribute("WarnBeforeNight", PortalService.WARN_BEFORE_NIGHT)
	remotes:SetAttribute("ReturnLead", PortalService.RETURN_LEAD)
	remotes.Parent = ReplicatedStorage
	Transition.Start(remotes)
	Hunt.Start(remotes)
	local goHome = Instance.new("RemoteEvent")
	goHome.Name = "GoHome"
	goHome.Parent = remotes
	stateEvent = Instance.new("RemoteEvent")
	stateEvent.Name = "StateChanged"
	stateEvent.Parent = remotes
	goHome.OnServerEvent:Connect(function(player) PortalService.ReturnHome(player, "Home") end)
	for _, d in ipairs(workspace.Map.Biomes:GetDescendants()) do hookPortal(d) end
	workspace.Map.Biomes.DescendantAdded:Connect(hookPortal)
	Players.PlayerAdded:Connect(watchPlayer)
	Players.PlayerRemoving:Connect(function(player)
		clearSession(player)
		entryAfter[player] = nil
		blockedNoticeAfter[player] = nil
	end)
	for _, player in ipairs(Players:GetPlayers()) do watchPlayer(player) end
	local accumulated = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulated += dt
		if accumulated < 0.1 then return end
		accumulated = 0
		local left = secondsToNight()
		local homeForNight = nightReturnDue()
		for _, player in ipairs(Players:GetPlayers()) do
			local _, humanoid, root = characterParts(player)
			if root and humanoid and humanoid.Health > 0 then
				local session = sessions[player]
				if session and session.Map and session.Map.Parent and not session.Busy then
					-- night rules: one warning WARN_BEFORE_NIGHT seconds out, then home as night falls
					if not homeForNight and not session.NightWarned and left and left <= PortalService.WARN_BEFORE_NIGHT then
						session.NightWarned = true
						stateEvent:FireClient(player, "NightWarning", left)
					end
					if homeForNight then
						task.spawn(PortalService.ReturnHome, player, "Night") -- marks the session Busy before it yields
					elseif session.Finish and inside(session.Finish, root.Position, 2) then
						PortalService.ReturnHome(player, "Finished")
					elseif root.Position.Y < session.FallY then resetToStart(player, session) end
				elseif not session then
					for portal, trigger in pairs(portals) do
						if portal.Parent and inside(trigger, root.Position, 2) then
							PortalService.Enter(player, portal)
							break
						end
					end
				end
			end
		end
	end)
	print("[PortalService] Portal maps, run timer, home button, and existing finish returns ready")
end

return PortalService
