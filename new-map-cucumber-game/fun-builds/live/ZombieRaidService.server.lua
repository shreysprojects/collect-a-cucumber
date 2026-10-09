--[[
	ZombieRaidService  (Script, ServerScriptService)  2026-09-10
	The night raid. When DayNightCycle flips workspace.CyclePhase to "Night" every player with a plot
	gets a wave of zombies sized by ZombieCatalog.ThreatOf (their placed cucumbers' biome / mutations /
	material / size + their Cash/s):

	  1. CUTSCENE  every client is told to look at the ZOMBIE NIGHT door: the arch on the lobby face of
	     Map.Borders.NightBarrier (the night wall DayNightCycle raises across the lobby entrance). Rows
	     of DOOR_COLUMNS zombies step out of the arch every DOOR_ROW_GAP seconds (the first after
	     DOOR_FIRST, once the wall is up) and shamble into the lobby; at CUTSCENE_SECONDS each raid's
	     zombies are teleported to a line BASE_OFFSET studs in front of its owner's plot and the
	     clients get their cameras back.
	  2. RAID  each zombie paths (PathfindingService, walls block, openings are found) to the nearest
	     placed cucumber on the plot, grabs it (the model is unanchored and welded over its head, its
	     "PlacedCucumber" tag dropped so the income stops) and carries it back across the lobby to the
	     door; within DOOR_REACH of the arch it has got away: the cucumber is gone and the owner is told
	     "stolen N/limit". A zombie stuck against a placed build for STUCK_SECONDS
	     bashes it (BASH_DAMAGE per swing through ServerStorage.BuildAPI = BuildHealthService) until
	     it BREAKS - never destroyed (2026-09-12): it fades, stops colliding, and mends by day.
	     Killing a carrier DROPS its cucumber where the zombie fell (2026-09-13, user: "drop cucumber on
	     the spot instead of sending cucumber straight back. another zombie can pick up cucumber from
	     there and carry on"): it is stood up as a placed cucumber again at that exact spot - plot,
	     lobby floor, wherever - at its usual height over the ground, still tagged and in the plot's
	     holder, so the raid's other zombies target it like any cucumber and carry it on toward the
	     door (raid.Dropped remembers its home; Grab / HomeRest hand that home on, so a second kill
	     drops it again and the chain keeps its origin). "Saved" tells the owner. Once the raid is
	     OVER - every zombie dead ("Survived"), the zombies win, dawn, the owner leaves - every
	     cucumber still lying where it fell goes home (ReturnDropped, + a BaseSave snapshot).
	  3. END  Limit = min(STEAL_LIMIT, cucumbers at the start). Stolen >= Limit -> "ZombiesWin" (the
	     rest sink away); every zombie dead -> "Survived"; day breaks -> "Dawn" (they burn away, any
	     carried cucumber is returned); the owner leaving ends the raid.

	Zombies live in workspace.Zombies (tag "Zombie", attributes Variety / Owner), rigs come from
	ServerStorage.Assets.Zombies/<Design> (build_zombies.lua) retinted per variety, animated with the
	Roblox zombie pack, collision group "Zombies" (they pass through each other), stud-sized name +
	health billboard, Persistent streaming.

	API for the bat and the defences: ServerStorage.ZombieAPI (BindableFunctions)
	  Damage(model, amount, source, attacker) -> ok, healthLeft   Zombies() -> list of live zombie models
	  (attacker = the Player swinging; a hit from a player turns that raid hostile to them, below)
	  IsZombie(model) -> bool                              Slow(model, seconds) / Stun(model, seconds)
	Client events: ReplicatedStorage.Remotes.ZombieRaid (RemoteEvent) with {Kind = "Cutscene" | "CutsceneEnd"
	  | "RaidStart" | "Grabbed" | "Stolen" | "Saved" | "BuildBroken" | "ZombiesWin" | "Survived" | "Dawn"}.
	Studio hook: workspace:SetAttribute("ZombieDev", "raid" | "raid:<level>" | "end" | "kill" | "cutscene"
	  | "spawn:<Variety Name>" | "thief") - edge-triggered, cleared after it runs.
	NightDurationSeconds on DayNightCycle is 45 (2026-09-11; was 10, then 90). A player with NO placed
	cucumbers gets no raid (no zombies, and no cutscene if nobody has any). When the night runs out
	with nothing stolen the player WINS the night ("Survived"); with some stolen the client hears
	"The night is over. You lost N cucumbers." (Kind "Dawn" carries Stolen).
	DAYTIME THIEVES (2026-09-11): every DAY_THIEF_MIN..MAX seconds of daylight (first DAY_THIEF_GRACE
	after dawn) one low-tier zombie steps out of the door and WALKS to a random base that has
	cucumbers (one thief per base at a time; owner told "Thief"), steals one the same way and walks
	it back to the door ("ThiefStole"); with nothing to steal it walks back and leaves. Thieves live
	in DayRaids (raid.Day = true, no win / lose, no plot attributes) and are cleared when night falls.
	None steps out within DAY_THIEF_NIGHT_GUARD s of the night (workspace.PhaseEndsAt, server time).
	Dev hook "thief" = one thief for player 1.
	SPECIAL KINDS (2026-09-11, ZombieCatalog flags): Shadow varieties phase - solid for SHADOW_VISIBLE
	s, then every part at SHADOW_TRANSPARENCY for SHADOW_HIDDEN s (SetShade): while shaded they are
	left out of ZombieAPI.Zombies (so turrets, traps, catapults and the bat never see them) and
	ZombieAPI.Damage refuses; carrying a cucumber keeps them solid. Health-1 sprinters need nothing
	special. Grapple varieties: in Seek within GrappleRange (line of sight not required) the zombie
	stops, a rope Beam runs from its right hand to the cucumber (GRAPPLE_HOOK s), the cucumber is
	reeled in over GRAPPLE_PULL s (the model slides, then Grab with its ORIGINAL rest pose so a kill
	still puts it back where it stood) and the zombie runs off at GRAPPLE_CARRY_SPEED x its speed.
	Digger varieties (StartDig): with a target at least DIG_RANGE_MIN away they sink DIG_DEPTH under the
	ground (root anchored, out of the zombie list and immune like a shadow), travel underground at
	DIG_SPEED with mound puffs on the surface, and surface within grab reach of the cucumber - walls,
	traps and the front line are simply passed under. Split varieties: when one dies, Split.Count
	children of Split.Variety stand up around it (same raid, counted BEFORE the raid-end check).
	HOSTILITY (2026-09-12, user: "when u start hitting zombies, zombies turn hostile towards you. they
	do NOT chase after you or follow you, but if you are in their way they hit you which knocks you
	back 10 studs"): the first bat hit a player lands on a raid's zombie puts them in raid.Hostile
	(the player hears "Hostile"; name tags do NOT change - user 2026-09-12). From then on every zombie of
	that raid that finds a hostile player within HIT_RANGE (x scale) inside its front HIT_CONE - in
	its way, whatever it was doing - stops for HIT_PAUSE, turns to them and swings (the R15 slash,
	ZombieCatalog.ANIMATIONS.Swing): SWING_DELAY later, if they are still in reach, HIT_DAMAGE off
	their health (HIT_DAMAGE, 0 since 2026-09-12: the blow only shoves) and a "Hit" event that makes THEIR client fly them KNOCKBACK_DISTANCE studs away
	from the zombie along a parabola over KNOCKBACK_TIME (the character's physics is client-owned,
	so the shove runs there). One swing per HIT_COOLDOWN per zombie; the zombie never changes its
	goal for a player. Shaded shadows, diggers underground and defence damage never trigger it.
	BUILD DURABILITY (2026-09-12, user: "zombies deal damage to builds ... never fully destroyed ...
	only stuff in their path"): Bash is unchanged in WHEN it happens - only a zombie stuck against a
	build in its way swings at it, never a detour - but the damage now goes through
	ServerStorage.BuildAPI.Damage (BuildHealthService: Health / MaxHealth attributes, a stud-sized
	health bar while damaged, Broken at 0 = faded + non-colliding + defences idle, healed through the
	day and set to 100 % when night falls). The raycast only considers builds that still stand, so a
	broken wall is walked through, not bashed again. "BuildBroken" replaces "BuildDestroyed".
	NIGHT TELEPORT (2026-09-11): when the raid starts every raided player is stood at the front of
	their own plot (PlotSpawn), 0.5 s in (after DayNightCycle's own lane returns) and again at the
	deploy if they are somehow not at the base. The wave itself is set down BASE_OFFSET (20) studs in
	front of the plot's front edge when the cutscene ends.
	The door's X / Z come from the arch (the NightBarrier's UnionOperation, else the part holding the
	Warning decal, else the old Zombie Den); the wall only moves in Y, so the door is the lobby entrance
	whether it is raised (night) or under the floor (a daytime dev raid).
	PETS (2026-09-22, pet-system polish; every pet module is resolved lazily and may be absent):
	  * LEAF SHIELD  Grab asks ServerStorage.PetBuffService.TryBlockTheft(cucumber, zombie) first (after
	    its own validity returns, before any mutation: ordinary grab, grapple final capture, a digger's
	    surfacing grab) and the grapple asks again before its pull. A block = the zombie stops
	    (StunUntil), drops its target, grabs NOTHING for GUARD.StunSeconds (BlockedUntil) and ignores
	    that cucumber for GUARD.AvoidSeconds (AvoidModel / AvoidUntil in NearestCucumber). No knockback,
	    no stolen count; a blocked grapple ends the whole attempt. Every real grab clears the
	    cucumber's pet buffs (ClearCucumber "Stolen"). The grapple now captures the cucumber's HOME
	    pose before the pull (the pulled pose used to become its carry rest).
	  * THREAT  IncomeOf reads IncomeService.GetThreatIncome (unboosted cucumber cash/s: pets, Yield and
	    Haste never raise a raid) once IncomeService has started, else Data.CashPerSec as before.
	  * RaidLive  player attribute true while their night raid is not over or a thief of theirs is alive
	    (nil otherwise), synced at every raid start / exit (the pet combat lock).
	  * ZombieAPI.TargetInfos() -> {{Model, Owner, State, Carrying, Grappling, Digging, Day, Health,
	    MaxHealth, Position}} for live, targetable zombies (PetCombatService).
	  * PRE-CLOSE  DataService.OnBeforeClose(PreCloseRaids, 35): before the leave / shutdown snapshot,
	    carried cucumbers go home and lobby-dropped ones back to their rest pose (RestoreCarry force,
	    ReturnDropped noSnapshot); EndRaid "Left" restores with force too. A cucumber still being hooked
	    or reeled in snaps back to its pre-grapple pose and the pull ends (SettleGrapple: entry.GrappleTarget
	    / GrappleRest), both here and at every EndRaid.
	  * GRAPPLE HOME (review fixes)  a grappler that dies or leaves lets go at once (Forget settles its rope
	    before any raid-end ReturnDropped) and its pull task never moves a settled cucumber again, so a
	    lobby-dropped one the raid sent home stays home (a raid already over puts an unsettled one home, not
	    back). One rope per cucumber (StartGrapple refuses one already hooked). A zombie that grabs a cucumber
	    mid-pull takes the home the grapple recorded before the pull as its rest (HomeRest -> HookedBy ->
	    entry.GrappleHome), never the dragged pose, and that rope lets go at the grab (Grab clears the hooker's
	    GrappleTarget / GrappleRest), so no later SettleGrapple or pull task moves the cucumber the carrier
	    took (a raid-end RestoreCarry had sent it home, then a stale rope put it back in the lobby).
	  * CO-OP NIGHTS (2026-09-24, user: "at night people can help each other fight each other's zombies only if
	    they're done their wave, both users get boosts"): a player's blow on ANOTHER player's night raid lands only
	    while their own raid is over (or they have none) - otherwise DamageZombie refuses it and they hear
	    "HelpBlocked". Every helper is remembered on the raid (raid.Helpers[player] = {Hits, Damage}, "HelperJoined"
	    to the owner / "Helping" to the helper on the first blow); when that raid is WON (every zombie dead, or dawn
	    with nothing stolen) the owner and every helper with HELP_MIN_HITS blows get TEAM_BOOST_SECONDS of the
	    potion boosts (ItemsCatalog.BOOSTS Cash + Strength attributes extended, never stacked) and a "Teamwork"
	    toast. Hostility is unchanged: a helped raid's zombies shove the helper too.
	  * ZOMBIE DEN (2026-09-24): every escape also fires ZombieAPI.CucumberStolen (BindableEvent: player, {Name,
	    Zone, Type}) AFTER ItemAPI.RecordLoss, so ZombieDenService can make a deal for the record it just wrote.
]]

--..Services..--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")
local PathfindingService = game:GetService("PathfindingService")
local PhysicsService = game:GetService("PhysicsService")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

--..Modules..--
local ZombieCatalog = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ZombieCatalog"))
local SoundController = require(ReplicatedStorage.Modules:WaitForChild("SoundController"))
local okItems, ItemsCatalog = pcall(function() return require(ReplicatedStorage.Modules:WaitForChild("ItemsCatalog", 10)) end) -- 2026-09-24 co-op boosts: the potion attributes
if not okItems then ItemsCatalog = nil end
local function Lazy(name) -- 2026-09-22: pet-system modules are optional until their stage is installed
	local cache
	return function()
		if cache then return cache end
		local module = ServerStorage:FindFirstChild(name)
		if not module then return nil end
		local ok, result = pcall(require, module)
		if ok and type(result) == "table" then cache = result end
		return cache
	end
end
local PetBuffs = Lazy("PetBuffService") -- TryBlockTheft / ClearCucumber
local IncomeSvc = Lazy("IncomeService") -- GetThreatIncome
local DataSvc = Lazy("DataService") -- OnBeforeClose
local GUARD_STUN_SECONDS, GUARD_AVOID_SECONDS = 0.8, 4 -- PetBalance.GUARD (these literals if it is missing)
do
	local ok, balance = pcall(function() return require(ReplicatedStorage.Modules:FindFirstChild("PetBalance")) end)
	local guard = ok and type(balance) == "table" and type(balance.GUARD) == "table" and balance.GUARD or {}
	local function finite(x) return type(x) == "number" and x == x and x >= 0 and x < math.huge end
	if finite(guard.StunSeconds) then GUARD_STUN_SECONDS = guard.StunSeconds end
	if finite(guard.AvoidSeconds) then GUARD_AVOID_SECONDS = guard.AvoidSeconds end
end
task.defer(function() PetBuffs() IncomeSvc() end) -- warm the requires now, never first inside Grab

--..Config..--
local CUTSCENE_SECONDS = 6.5 -- the door shot
local DOOR_FIRST = 1.2       -- seconds into the cutscene before the first row steps out (the night wall takes ~1 s to rise)
local DOOR_ROW_GAP = 0.5     -- seconds between rows
local DOOR_COLUMNS = 4       -- zombies per row across the arch
local DOOR_SPACING = 3       -- studs between columns
local DOOR_OUT = 1.8         -- the first row this far in front of the arch face
local DOOR_ROW_DEPTH = 2.8   -- studs between rows
local DOOR_REACH = 5         -- a carrier this close to the door has got away
local WALK_OUT = 14          -- studs into the lobby they shamble during the cutscene
local DAY_THIEF_MIN, DAY_THIEF_MAX = 50, 100 -- seconds of daylight between thieves (server-wide)
local DAY_THIEF_GRACE = 25   -- seconds into a day before the first thief
local DAY_THIEF_NIGHT_GUARD = 20 -- no thief steps out this close to nightfall (user 2026-09-12)
local THIEF_POOL = {"Rotten Shambler", "Scrawny Runner", "Plague Shambler", "Feral Runner"} -- by threat level
local BASE_OFFSET = 20       -- the drop line this far in front of the plot's front edge
local BASE_SPREAD = 4        -- studs between zombies on that line
local GRAB_RANGE = 4
local REPATH_SECONDS = 2
local WAYPOINT_REACH = 3
local STUCK_SECONDS = 1.6
local BASH_INTERVAL = 1.0
local BASH_DAMAGE = 25
local BASH_REACH = 5
local CARRY_SPEED = 0.85     -- walk multiplier while carrying a cucumber
local SLOW_MULT = 0.45       -- ... while slowed by a trap
local TICK = 0.1
local DEATH_FADE = 1.1
local WANDER_SECONDS = 4
local HIT_SOUND_GAP = 0.08
--.. hostility (2026-09-12): a zombie you have hit swings at you when you stand in its way
local HIT_RANGE = 4.5         -- studs (x scale) in front of a hostile zombie that count as "in its way"
local HIT_CONE = 0.5          -- cos 60 deg: half-angle of that front cone
local HIT_COOLDOWN = 1.4      -- seconds between swings per zombie
local HIT_PAUSE = 0.5         -- the zombie stands still this long to swing
local SWING_DELAY = 0.2       -- seconds into the swing the blow lands
local HIT_DAMAGE = 0          -- player health per blow: NONE (user 2026-09-12: "only knockback")
local KNOCKBACK_DISTANCE = 10 -- studs the blow throws the player back
local KNOCKBACK_TIME = 0.35   -- seconds of flight (peak g*T^2/8 = 3 studs: a shove, not a launch)
local FRONT_DIRECTION = Vector3.new(-1, 0, 0) -- = PlotService.FRONT_DIRECTION
local PLACED_TAG = "PlacedCucumber"
local BUILD_TAG = "PlacedBuild"
local COLLISION_GROUP = "Zombies"

--..Instances..--
local Map = workspace:WaitForChild("Map")
local Lobby = Map:WaitForChild("Lobby")
local Plots = Lobby:WaitForChild("Plots")
local Barrier = Map:WaitForChild("Borders"):WaitForChild("NightBarrier")
local Den = Lobby:WaitForChild("Stations"):FindFirstChild("Zombie Den ") -- fallback only
local LobbyFloorTop = -229
for _, part in ipairs(Lobby:WaitForChild("Floor"):GetDescendants()) do
	if part:IsA("BasePart") then LobbyFloorTop = part.Position.Y + part.Size.Y * 0.5 end
end
local Rigs = ServerStorage:WaitForChild("Assets"):WaitForChild("Zombies")

local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
if not Remotes then
	Remotes = Instance.new("Folder")
	Remotes.Name = "Remotes"
	Remotes.Parent = ReplicatedStorage
end
local Remote = Remotes:FindFirstChild(ZombieCatalog.REMOTE)
if not Remote then
	Remote = Instance.new("RemoteEvent")
	Remote.Name = ZombieCatalog.REMOTE
	Remote.Parent = Remotes
end
local ZombiesFolder = workspace:FindFirstChild(ZombieCatalog.FOLDER)
if not ZombiesFolder then
	ZombiesFolder = Instance.new("Folder")
	ZombiesFolder.Name = ZombieCatalog.FOLDER
	ZombiesFolder.Parent = workspace
end
local API = ServerStorage:FindFirstChild(ZombieCatalog.API)
if API then API:Destroy() end
API = Instance.new("Folder")
API.Name = ZombieCatalog.API
local function Bindable(name)
	local b = Instance.new("BindableFunction")
	b.Name = name
	b.Parent = API
	return b
end
local DamageAPI, ZombiesAPI, IsZombieAPI, SlowAPI, StunAPI = Bindable("Damage"), Bindable("Zombies"), Bindable("IsZombie"), Bindable("Slow"), Bindable("Stun")
local TargetInfosAPI = Bindable("TargetInfos") -- 2026-09-22: pet targeting (primitives + the Model)
local ThreatLevelAPI = Bindable("ThreatLevel") -- 2026-09-23 (Manage panel): (player) -> level, score, cucumbers a raid would be right now
local RaidResultEvent = Instance.new("BindableEvent") -- 2026-09-23 (Manage panel): (player, {Result, Level, Stolen, Limit}) at every night raid's end
RaidResultEvent.Name = "RaidResult"
RaidResultEvent.Parent = API
local function ReportResult(raid, result)
	if raid.Day or not raid.Player then return end
	RaidResultEvent:Fire(raid.Player, {Result = result, Level = raid.Level, Stolen = raid.Stolen, Limit = raid.Limit})
end
local CucumberStolenEvent = Instance.new("BindableEvent") -- 2026-09-24 (Zombie Den): (player, {Name, Zone, Type}) after every theft is recorded
CucumberStolenEvent.Name = "CucumberStolen"
CucumberStolenEvent.Parent = API
API.Parent = ServerStorage
--.. 2026-09-24 CO-OP NIGHTS (see the top): helping is allowed once your own wave is done; a won raid pays both sides
local HELP_MIN_HITS = 3        -- blows a helper must land before the win counts them
local HELP_TOAST_GAP = 3       -- seconds between "finish your own wave" toasts per player
local TEAM_BOOST_SECONDS = 300 -- 2x cash + 2x strength (the potion timers) for the owner and every helper
local TEAM_BOOSTS = {"Cash", "Strength"}
local HelpToastAt = {} -- [player] = os.clock()

pcall(PhysicsService.RegisterCollisionGroup, PhysicsService, COLLISION_GROUP)
pcall(PhysicsService.CollisionGroupSetCollidable, PhysicsService, COLLISION_GROUP, COLLISION_GROUP, false)

local Animations = {}
for name, id in pairs(ZombieCatalog.ANIMATIONS) do
	local anim = Instance.new("Animation")
	anim.Name = "Zombie" .. name
	anim.AnimationId = id
	anim.Parent = script
	Animations[name] = anim
end

--..State..--
local Raids = {}    -- [player] = raid {Player, UserId, Plot, Level, Limit, Stolen, Zombies = {entry}, Alive, Over}
local DayRaids = {} -- [player] = raid with Day = true: the daytime thief (one at a time)
local Zombies = {}  -- [model] = entry
local Phase = "Idle" -- Idle | Cutscene | Raid
local rng = Random.new()
local Kill -- defined below (Spawn connects Humanoid.Died to it)
local SyncRaidLive -- defined below (2026-09-22: the RaidLive player attribute)
local SettleGrapple -- defined below (2026-09-22: Forget lets go of a dying / leaving grappler's rope)

--..Geometry..--
local function halfAlong(part, direction)
	local cf, size = part.CFrame, part.Size
	return math.abs(direction:Dot(cf.RightVector)) * size.X * 0.5
		+ math.abs(direction:Dot(cf.UpVector)) * size.Y * 0.5
		+ math.abs(direction:Dot(cf.LookVector)) * size.Z * 0.5
end

local function FrontX(plot) -- world X of the plot's front edge
	return (plot.Position + FRONT_DIRECTION * halfAlong(plot, FRONT_DIRECTION)).X
end

local function PlotTop(plot)
	return plot.Position.Y + plot.Size.Y * 0.5
end

local function Flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

local function GroundY(x, z, fromY, fallback)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = {Map}
	local hit = workspace:Raycast(Vector3.new(x, fromY, z), Vector3.new(0, -40, 0), params)
	return hit and hit.Position.Y or fallback
end

local function PlotOf(player)
	for _, plot in ipairs(Plots:GetChildren()) do
		if plot:IsA("BasePart") and plot:GetAttribute("Owner") == player.UserId then return plot end
	end
	return nil
end

local function HolderOf(plot)
	return plot:FindFirstChild("Placed")
end

local function CucumbersOf(plot, userId)
	local list = {}
	local holder = HolderOf(plot)
	if not holder then return list end
	for _, model in ipairs(holder:GetChildren()) do
		if model:IsA("Model") and CollectionService:HasTag(model, PLACED_TAG) and model:GetAttribute("Owner") == userId then
			table.insert(list, model)
		end
	end
	return list
end

local function IncomeOf(player)
	--.. 2026-09-22: the UNBOOSTED cucumber income once IncomeService runs (pets / Yield / Haste never raise a raid)
	local income = IncomeSvc()
	local okThreat, v = pcall(function()
		return income and income.IsStarted and income.IsStarted() and income.GetThreatIncome(player)
	end)
	if okThreat and type(v) == "number" and v == v and v >= 0 and v < math.huge then return v end
	local data = player:FindFirstChild("Data")
	local raw = data and data:FindFirstChild("CashPerSec")
	return raw and raw.Value or 0
end

local function Send(raid, payload)
	if raid.Player and raid.Player.Parent then Remote:FireClient(raid.Player, payload) end
end

--..Co-op nights (2026-09-24)..--
local function HelpAllowed(player) -- your own night wave is over, or you have none
	local mine = Raids[player]
	return mine == nil or mine.Over == true
end

local function HelpBlocked(player)
	local now = os.clock()
	if HelpToastAt[player] and now - HelpToastAt[player] < HELP_TOAST_GAP then return end
	HelpToastAt[player] = now
	Remote:FireClient(player, {Kind = "HelpBlocked"})
end

local function RegisterHelp(raid, player, amount)
	raid.Helpers = raid.Helpers or {}
	local h = raid.Helpers[player]
	if not h then
		h = {Hits = 0, Damage = 0}
		raid.Helpers[player] = h
		Send(raid, {Kind = "HelperJoined", Name = player.Name})
		Remote:FireClient(player, {Kind = "Helping", Name = raid.Player and raid.Player.Name or "?"})
		print(("[ZombieRaid] %s is helping %s fight their wave"):format(player.Name, raid.Player and raid.Player.Name or "?"))
	end
	h.Hits += 1
	h.Damage += amount
end

local function GrantTeamBoost(player)
	if not (player and player.Parent) then return end
	local now = workspace:GetServerTimeNow()
	for _, boost in ipairs(TEAM_BOOSTS) do
		local info = ItemsCatalog and type(ItemsCatalog.BOOSTS) == "table" and ItemsCatalog.BOOSTS[boost]
		local attr = info and info.Attr or (boost .. "BoostUntil")
		local current = tonumber(player:GetAttribute(attr)) or 0
		player:SetAttribute(attr, math.max(now, current) + TEAM_BOOST_SECONDS)
	end
end

--.. the raid was won: the owner and every helper who really fought get the team boost (once per raid)
local function RewardHelpers(raid)
	if raid.Day or raid.Rewarded or type(raid.Helpers) ~= "table" then return end
	local helpers = {}
	for helper, h in pairs(raid.Helpers) do
		if h.Hits >= HELP_MIN_HITS and helper.Parent then table.insert(helpers, helper) end
	end
	if #helpers == 0 then return end
	raid.Rewarded = true
	table.sort(helpers, function(a, b) return a.Name < b.Name end)
	local owner = raid.Player
	local ownerName = owner and owner.Name or "?"
	local names = {}
	for _, helper in ipairs(helpers) do table.insert(names, helper.Name) end
	for _, helper in ipairs(helpers) do
		GrantTeamBoost(helper)
		Remote:FireClient(helper, {Kind = "Teamwork", With = ownerName, Seconds = TEAM_BOOST_SECONDS})
	end
	if owner and owner.Parent then
		GrantTeamBoost(owner)
		Send(raid, {Kind = "Teamwork", With = table.concat(names, ", "), Seconds = TEAM_BOOST_SECONDS})
	end
	print(("[ZombieRaid] teamwork: %s's wave was won with %s -> %d s of 2x cash + 2x strength for all of them"):format(ownerName, table.concat(names, ", "), TEAM_BOOST_SECONDS))
end

--..The door..--
--.. the arch on the night wall's lobby face; only its Y changes as the wall rises, so X / Z are stable
local function DoorArch()
	local arch = Barrier:FindFirstChildOfClass("UnionOperation")
	if arch then return arch end
	for _, d in ipairs(Barrier:GetDescendants()) do
		if d:IsA("Decal") and d.Name == "Warning" and d.Parent:IsA("BasePart") then return d.Parent end
	end
	return nil
end

local DoorCache, DoorCacheAt = nil, 0
local function DoorPoint()
	local now = os.clock()
	if DoorCache and now - DoorCacheAt < 1 then return DoorCache end
	local arch = DoorArch()
	local x, z
	if arch then
		x = arch.Position.X + arch.Size.X * 0.5 + DOOR_OUT
		z = arch.Position.Z
	elseif Den then
		local p = Den:GetPivot().Position
		x, z = p.X + 8, p.Z
	else
		x, z = 1150, 130
	end
	DoorCache = Vector3.new(x, GroundY(x, z, LobbyFloorTop + 20, LobbyFloorTop), z)
	DoorCacheAt = now
	Barrier:SetAttribute("DoorPoint", DoorCache)
	return DoorCache
end

--.. where the i-th zombie (0-based) steps out: rows of DOOR_COLUMNS across the arch, marching east
local function DoorSpawn(door, i)
	local col = i % DOOR_COLUMNS
	local row = math.floor(i / DOOR_COLUMNS)
	local x = door.X + row * DOOR_ROW_DEPTH
	local z = door.Z + (col - (DOOR_COLUMNS - 1) * 0.5) * DOOR_SPACING
	return Vector3.new(x, GroundY(x, z, LobbyFloorTop + 20, door.Y), z), row, col
end

--..Effects..--
local function Poof(position, color, count)
	local att = Instance.new("Attachment")
	att.WorldPosition = position
	att.Parent = workspace.Terrain
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = "rbxasset://textures/particles/smoke_main.dds"
	pe.Color = ColorSequence.new(color)
	pe.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 3)})
	pe.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1)})
	pe.Lifetime = NumberRange.new(0.6, 1.1)
	pe.Speed = NumberRange.new(4, 9)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Rate = 0
	pe.Parent = att
	pe:Emit(count or 18)
	Debris:AddItem(att, 2)
end

--..Billboard (sized in studs: BillboardGui scale units, scale-only children)..--
local function Billboard(entry)
	local variety = entry.Variety
	local head = entry.Model:FindFirstChild("Head")
	if not head then return end
	local gui = Instance.new("BillboardGui")
	gui.Name = "ZombieTag"
	gui.Adornee = head
	gui.Size = UDim2.fromScale(6, 1.5)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 1.3 + 0.7 * variety.Scale, 0)
	gui.MaxDistance = 140
	gui.LightInfluence = 0
	gui.ResetOnSpawn = false
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.fromScale(1, 0.58)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.Text = variety.Name
	label.TextColor3 = variety.Glow
	label.TextScaled = true
	label.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Color3.fromRGB(10, 10, 14)
	stroke.Parent = label
	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.Size = UDim2.fromScale(0.72, 0.22)
	bar.Position = UDim2.fromScale(0.14, 0.68)
	bar.BackgroundColor3 = Color3.fromRGB(28, 28, 34)
	bar.BorderSizePixel = 0
	bar.Parent = gui
	Instance.new("UICorner", bar).CornerRadius = UDim.new(0.5, 0)
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(92, 225, 92)
	fill.BorderSizePixel = 0
	fill.Parent = bar
	Instance.new("UICorner", fill).CornerRadius = UDim.new(0.5, 0)
	gui.Parent = head
	entry.Fill = fill
	entry.Label = label
end

local function UpdateBar(entry)
	local fill = entry.Fill
	if not fill or not fill.Parent then return end
	local f = math.clamp(entry.Humanoid.Health / math.max(1, entry.Humanoid.MaxHealth), 0, 1)
	fill.Size = UDim2.fromScale(f, 1)
	fill.BackgroundColor3 = f > 0.5 and Color3.fromRGB(92, 225, 92) or (f > 0.25 and Color3.fromRGB(255, 190, 60) or Color3.fromRGB(240, 58, 58))
end

--..Animation..--
local function SetMoving(entry, speed)
	local moving = speed > 1.5
	if moving ~= entry.Moving then
		entry.Moving = moving
		if moving then
			entry.Idle:Stop(0.2)
			entry.Walk:Play(0.2)
		else
			entry.Walk:Stop(0.2)
			entry.Idle:Play(0.2)
		end
	end
	if moving then
		local reference = entry.Runner and 16 or 11
		entry.Walk:AdjustSpeed(math.clamp(speed / reference, 0.5, 2.4))
	end
end

--..Spawning..--
local ROLE_DEFAULT = {}
local function Tint(model, variety)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			local role = d:GetAttribute("Role")
			if role == "Skin" then d.Color = variety.Skin
			elseif role == "Cloth" then d.Color = variety.Cloth
			elseif role == "Glow" then d.Color = variety.Glow end
			d.CollisionGroup = COLLISION_GROUP
		elseif d:IsA("PointLight") then
			d.Color = variety.Glow
		end
	end
end

--.. 2026-09-23: zombies alive on this server (the door holds further rows past ZombieCatalog.ALIVE_CAP)
local function AliveCount()
	local n = 0
	for _, e in pairs(Zombies) do
		if not e.Dead then n += 1 end
	end
	return n
end

local function Spawn(variety, cframe, raid)
	local template = Rigs:FindFirstChild(variety.Design) or Rigs:FindFirstChild(ZombieCatalog.DESIGNS[1])
	if not template then
		warn("[ZombieRaid] no rig for design " .. tostring(variety.Design))
		return nil
	end
	local model = template:Clone()
	model.Name = variety.Name
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	Tint(model, variety)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	local baseHip = tonumber(model:GetAttribute("BaseHip")) or humanoid.HipHeight
	if variety.Scale ~= 1 then
		model:ScaleTo(variety.Scale)
		if Rigs:GetAttribute("ScaleToScalesHip") ~= true then humanoid.HipHeight = baseHip * variety.Scale end
	end
	local hitPoints = ZombieCatalog.HealthOf(variety, raid and raid.Level or 1) -- 2026-09-23: role HP x3 per raid level
	humanoid.MaxHealth = hitPoints
	humanoid.Health = hitPoints
	humanoid.WalkSpeed = variety.Speed
	humanoid.JumpPower = 40
	--.. a zombie never ragdolls: with the root anchored for the den rise the Humanoid sat in FallingDown and
	--.. stayed there ~3 s after release, so the big ones toppled over (measured 2026-09-10)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Swimming, false)
	model:SetAttribute("Variety", variety.Name)
	model:SetAttribute("Owner", raid and raid.UserId or nil)
	model:SetAttribute("Zombie", true)
	CollectionService:AddTag(model, ZombieCatalog.TAG)
	model:PivotTo(cframe)
	model.Parent = ZombiesFolder
	local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)
	local runner = variety.Speed >= 14
	local baseTransparency = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then baseTransparency[d] = d.Transparency end
	end
	local entry = {
		Model = model, Humanoid = humanoid, Root = root, Variety = variety, Raid = raid,
		Runner = runner,
		Shadow = variety.Shadow == true, Shaded = false, ShadeAt = os.clock() + ZombieCatalog.SHADOW_VISIBLE,
		Grapple = variety.Grapple == true, BaseTransparency = baseTransparency,
		Digger = variety.Digger == true, Underground = false, DigCooldownUntil = 0,
		Swing = Animations.Swing and animator:LoadAnimation(Animations.Swing) or nil, NextHit = 0,
		Walk = animator:LoadAnimation(runner and Animations.Run or Animations.Walk),
		Idle = animator:LoadAnimation(rng:NextNumber() < 0.5 and Animations.Idle or Animations.Idle2),
		State = "Seek", Target = nil, Goal = nil, RepathAt = 0, Waypoints = nil, WaypointIndex = 1, Direct = true,
		LastPos = root.Position, LastMove = os.clock(), NextBash = 0, SlowUntil = 0, StunUntil = 0, NextHitSound = 0,
		Path = PathfindingService:CreatePath({AgentRadius = 2 + (variety.Scale - 1) * 2, AgentHeight = 5 * variety.Scale, AgentCanJump = false, WaypointSpacing = 4}),
		Dead = false, Moving = false,
	}
	entry.Idle.Priority = Enum.AnimationPriority.Idle
	entry.Walk.Priority = Enum.AnimationPriority.Movement
	if entry.Swing then entry.Swing.Priority = Enum.AnimationPriority.Action end
	entry.Idle:Play()
	Billboard(entry)
	Zombies[model] = entry
	humanoid.Died:Connect(function() Kill(entry, "Died") end)
	if raid then
		table.insert(raid.Zombies, entry)
		raid.Alive += 1
	end
	return entry
end

local function Unanchor(entry)
	for _, d in ipairs(entry.Model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.AssemblyLinearVelocity = Vector3.zero
			d.AssemblyAngularVelocity = Vector3.zero
		end
	end
	entry.Root.Anchored = false
	pcall(function() entry.Root:SetNetworkOwner(nil) end)
	entry.Humanoid:ChangeState(Enum.HumanoidStateType.Running)
end

--..Carrying..--
local function IsWelded(primary, part)
	for _, c in ipairs(part:GetChildren()) do
		if c:IsA("WeldConstraint") and ((c.Part0 == primary and c.Part1 == part) or (c.Part1 == primary and c.Part0 == part)) then return true end
	end
	for _, c in ipairs(primary:GetChildren()) do
		if c:IsA("WeldConstraint") and ((c.Part0 == primary and c.Part1 == part) or (c.Part1 == primary and c.Part0 == part)) then return true end
	end
	return false
end

--.. 2026-09-22: the zombie whose grapple rope is on this cucumber right now (entry.GrappleTarget; one rope per cucumber)
local function HookedBy(raid, model)
	if not raid then return nil end
	for _, other in ipairs(raid.Zombies) do
		if other.GrappleTarget == model then return other end
	end
	return nil
end

--.. where a cucumber belongs: its home rest pose if it is lying where a carrier fell (raid.Dropped), else where it is
--.. (2026-09-22: while a rope reels it in, the home that grapple recorded before the pull - never the dragged pose)
local function HomeRest(raid, model)
	local hook = HookedBy(raid, model)
	if hook and hook.GrappleHome then return hook.GrappleHome end
	local dropped = raid and raid.Dropped and raid.Dropped[model]
	return dropped and dropped.Rest or model:GetPivot()
end

local function TheftBlocked(entry, model) -- 2026-09-22: a pet Leaf Shield (or its grace) denies this attempt
	local buffs = PetBuffs()
	if not buffs then return false end
	local ok, blocked = pcall(buffs.TryBlockTheft, model, entry.Model) -- never pass os.clock() (different clock)
	if ok and blocked then
		entry.Target = nil
		entry.StunUntil = math.max(entry.StunUntil, os.clock() + GUARD_STUN_SECONDS)
		entry.BlockedUntil = os.clock() + GUARD_STUN_SECONDS -- no grab of ANY cucumber meanwhile
		entry.AvoidModel, entry.AvoidUntil = model, os.clock() + GUARD_AVOID_SECONDS -- OD-10
		return true
	end
	return false
end

local function Grab(entry, model, restCFrame)
	local raid = entry.Raid
	local primary = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	local hitbox = model:FindFirstChild("PlotHitbox")
	if not primary then return false end
	local torso = entry.Model:FindFirstChild("UpperTorso")
	if not torso then return false end
	if TheftBlocked(entry, model) then return false end -- 2026-09-22: before any mutation (a grab that fails anyway never spends a charge)
	local buffs = PetBuffs()
	if buffs then pcall(buffs.ClearCucumber, model, "Stolen") end -- 2026-09-22: a theft never keeps pet buffs (OD-12)
	local hbCF = hitbox and hitbox.CFrame or model:GetPivot()
	local size = hitbox and hitbox.Size or model:GetExtentsSize()
	local carry = {Model = model, Rest = restCFrame or HomeRest(raid, model), Holder = model.Parent, Parts = {}, Name = model:GetAttribute("CucumberName") or model.Name}
	local hook = HookedBy(raid, model) -- 2026-09-22: grabbed off another zombie's rope (its home is in carry.Rest now):
	if hook then hook.GrappleTarget, hook.GrappleRest = nil, nil end -- that rope lets go, so its SettleGrapple / task never moves it again
	if raid and raid.Dropped then raid.Dropped[model] = nil end -- picked up from where it lay: it is carried on
	CollectionService:RemoveTag(model, PLACED_TAG)
	model:SetAttribute("StolenBy", entry.Model.Name)
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then
			carry.Parts[p] = {Anchored = p.Anchored, CanCollide = p.CanCollide, CanQuery = p.CanQuery, CanTouch = p.CanTouch, Massless = p.Massless}
			if p ~= primary and not IsWelded(primary, p) then
				local w = Instance.new("WeldConstraint")
				w.Name = "CarryLink"
				w.Part0 = primary
				w.Part1 = p
				w.Parent = p
			end
		end
	end
	local up = torso.Size.Y * 0.5 + size.Y * 0.5 + 0.35
	local weld = Instance.new("Weld")
	weld.Name = "CarryWeld"
	weld.Part0 = torso
	weld.Part1 = primary
	weld.C0 = CFrame.new(0, up, 0) * (hbCF:Inverse() * primary.CFrame)
	weld.Parent = primary
	for p in pairs(carry.Parts) do
		p.Anchored = false
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Massless = true
	end
	model.Parent = entry.Model
	entry.Carry = carry
	entry.State = "Carry"
	entry.Target = nil
	entry.RepathAt = 0
	entry.Waypoints = nil
	SoundController.PlayFXAt("Dirt Dig", entry.Root.Position, {Volume = 0.8, RollOff = 60})
	Send(raid, {Kind = "Grabbed", Name = carry.Name, Zombie = entry.Variety.Name})
	return true
end

--.. stand a carried cucumber up again: at dropAt (the exact spot the carrier fell - plot or lobby - at its usual
--.. height over the ground; remembered in raid.Dropped so the next zombie can take it and it can go home later)
--.. or, with no dropAt, back where it stood
--.. force (2026-09-22: the pre-close settle / a leave): put it home even when the owner is already gone
local function RestoreCarry(entry, silent, dropAt, force)
	local carry = entry.Carry
	if not carry then return end
	entry.Carry = nil
	local model = carry.Model
	if not model or not model.Parent then return end
	local raid = entry.Raid
	local holder = carry.Holder
	if not (holder and holder.Parent) then
		holder = raid and raid.Plot and HolderOf(raid.Plot)
	end
	if not holder or not (force == true or (raid and raid.Player and raid.Player.Parent)) then
		model:Destroy()
		return
	end
	local primary = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	local weld = primary and primary:FindFirstChild("CarryWeld")
	if weld then weld:Destroy() end
	for p, state in pairs(carry.Parts) do
		if p.Parent then
			p.Anchored = state.Anchored
			p.CanCollide = state.CanCollide
			p.CanQuery = state.CanQuery
			p.CanTouch = state.CanTouch
			p.Massless = state.Massless
		end
	end
	local rest = carry.Rest
	if typeof(dropAt) == "Vector3" and raid.Plot and raid.Plot.Parent then
		local plotTop = PlotTop(raid.Plot)
		local ground = GroundY(dropAt.X, dropAt.Z, dropAt.Y + 3, plotTop) -- the map only: never the zombie or the load
		rest = CFrame.new(dropAt.X, ground + (carry.Rest.Y - plotTop), dropAt.Z) * carry.Rest.Rotation
		raid.Dropped = raid.Dropped or {}
		raid.Dropped[model] = {Rest = carry.Rest, Name = carry.Name}
	end
	model:PivotTo(rest)
	model:SetAttribute("StolenBy", nil)
	model.Parent = holder
	CollectionService:AddTag(model, PLACED_TAG)
	if not silent then Send(raid, {Kind = "Saved", Name = carry.Name, Zombie = entry.Variety.Name}) end
end

--.. the raid is over: every cucumber still lying where a carrier fell goes back where it stood
local function ReturnDropped(raid, noSnapshot) -- noSnapshot (2026-09-22): the pre-close snapshot follows anyway
	local dropped = raid.Dropped
	if not dropped then return end
	raid.Dropped = nil
	local holder = raid.Plot and raid.Plot.Parent and HolderOf(raid.Plot)
	local n = 0
	for model, info in pairs(dropped) do
		if holder and model.Parent == holder then
			model:PivotTo(info.Rest)
			n += 1
		end
	end
	if n > 0 then
		local api = ServerStorage:FindFirstChild("BaseSaveAPI") -- the base save keys off tag changes; a pivot needs a nudge
		local snapshot = api and api:FindFirstChild("Snapshot")
		if snapshot and raid.Player and raid.Player.Parent and not noSnapshot then pcall(snapshot.Invoke, snapshot, raid.Player) end
		print(("[ZombieRaid] %d dropped cucumber(s) went home on %s's plot"):format(n, raid.Player.Name))
	end
end

--..Death / despawn..--
local function Forget(entry)
	Zombies[entry.Model] = nil
	SettleGrapple(entry) -- 2026-09-22: a dying / leaving grappler lets go now (before any raid-end ReturnDropped)
	local raid = entry.Raid
	if raid and not entry.Counted then
		entry.Counted = true
		raid.Alive = math.max(0, raid.Alive - 1)
	end
end

local function FadeAway(entry, seconds, sink)
	local model = entry.Model
	local root = entry.Root
	pcall(function() entry.Walk:Stop(0.1) entry.Idle:Stop(0.1) end)
	entry.Humanoid.WalkSpeed = 0
	entry.Humanoid.PlatformStand = true
	root.Anchored = true
	local start = root.CFrame
	local t0 = os.clock()
	local parts = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d ~= root then
			parts[d] = d.Transparency
			d.CanCollide = false
		elseif d:IsA("BillboardGui") or d:IsA("PointLight") then
			d:Destroy()
		end
	end
	task.spawn(function()
		while model.Parent and os.clock() - t0 < seconds do
			local a = math.clamp((os.clock() - t0) / seconds, 0, 1)
			for p, base in pairs(parts) do
				if p.Parent then p.Transparency = base + (1 - base) * a end
			end
			if sink then root.CFrame = start - Vector3.new(0, sink * a, 0) end
			RunService.Heartbeat:Wait()
		end
		if model.Parent then model:Destroy() end
	end)
end

local function Publish(raid)
	if raid.Day then return end
	local plot = raid.Plot
	if not (plot and plot.Parent) then return end
	plot:SetAttribute("RaidAlive", raid.Alive)
	plot:SetAttribute("RaidStolen", raid.Stolen)
	plot:SetAttribute("RaidLimit", raid.Limit)
	plot:SetAttribute("RaidOver", raid.Over)
end

local function CheckRaidEndBody(raid)
	Publish(raid)
	if raid.Over then return end
	if raid.Day then
		if raid.Alive <= 0 then
			raid.Over = true
			ReturnDropped(raid)
			if DayRaids[raid.Player] == raid then DayRaids[raid.Player] = nil end
		end
		return
	end
	if raid.Alive <= 0 then
		raid.Over = true
		raid.Result = "Survived"
		ReturnDropped(raid)
		Publish(raid)
		Send(raid, {Kind = "Survived", Level = raid.Level, Stolen = raid.Stolen, Limit = raid.Limit})
		print(("[ZombieRaid] %s survived (level %d, stolen %d/%d)"):format(raid.Player.Name, raid.Level, raid.Stolen, raid.Limit))
		ReportResult(raid, "Survived") -- 2026-09-23 (Manage panel: days survived)
		RewardHelpers(raid) -- 2026-09-24 co-op nights
	end
end

local function CheckRaidEnd(raid) -- 2026-09-22: every exit syncs RaidLive (pet combat lock)
	CheckRaidEndBody(raid)
	if raid.Player then SyncRaidLive(raid.Player) end
end

function Kill(entry, source)
	if entry.Dead then return end
	entry.Dead = true
	RestoreCarry(entry, false, entry.Root.Position) -- dropped where it fell
	Forget(entry)
	--.. a splitter bursts into its children (spawned before the raid-end check so Alive never dips to 0)
	local split = entry.Variety.Split
	local raid = entry.Raid
	if split and raid and not raid.Ended then
		local child = ZombieCatalog.Variety(split.Variety)
		local count = split.Count or 3
		if child then
			local origin = entry.Root.Position
			for i = 1, count do
				local angle = i / count * 2 * math.pi
				local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
				local x, z = origin.X + dir.X * 2.4, origin.Z + dir.Z * 2.4
				local ground = Vector3.new(x, GroundY(x, z, origin.Y + 6, origin.Y - 3.2), z)
				local kid = Spawn(child, CFrame.new(ground), raid)
				if kid then
					local hip = kid.Humanoid.HipHeight + kid.Root.Size.Y * 0.5
					kid.Root.CFrame = CFrame.lookAt(ground + Vector3.new(0, hip + 0.05, 0), ground + Vector3.new(0, hip + 0.05, 0) + dir)
					Unanchor(kid)
					kid.Target = entry.Target
					kid.LastPos = kid.Root.Position
					kid.LastMove = os.clock()
				end
			end
			Poof(origin, entry.Variety.Glow, 28)
			Send(raid, {Kind = "Split", Zombie = entry.Variety.Name, Child = child.Name, Count = count})
			print(("[ZombieRaid] %s burst into %d %ss"):format(entry.Variety.Name, count, child.Name))
		end
	end
	SoundController.PlayFXAt("Wet Crunch", entry.Root.Position, {Volume = 1, RollOff = 70})
	Poof(entry.Root.Position, entry.Variety.Glow, 16)
	--.. 2026-09-23 (items): a killed zombie may drop an item where it fell (ItemService rolls ItemsCatalog by the variety's level)
	do
		local itemApi = ServerStorage:FindFirstChild("ItemAPI")
		local drop = itemApi and itemApi:FindFirstChild("Drop")
		if drop then
			local okDrop, errDrop = pcall(drop.Invoke, drop, entry.Root.Position, entry.Variety.MinLevel or 1)
			if not okDrop then warn("[ZombieRaid] item drop failed: " .. tostring(errDrop)) end
		end
	end
	FadeAway(entry, DEATH_FADE, 2.5)
	entry.Model:SetAttribute("Dead", true)
	if entry.Raid then CheckRaidEnd(entry.Raid) end
end

--.. leaves without dying (escaped with a cucumber, the raid was called off, dawn)
local function Despawn(entry, effect)
	if entry.Dead then return end
	entry.Dead = true
	Forget(entry)
	entry.Model:SetAttribute("Dead", true)
	if effect == "Burn" then
		Poof(entry.Root.Position, Color3.fromRGB(255, 150, 40), 22)
		FadeAway(entry, 1.4, 0)
	else
		Poof(entry.Root.Position, entry.Variety.Glow, 14)
		FadeAway(entry, 0.9, 3)
	end
end

local function Escape(entry)
	local raid = entry.Raid
	local carry = entry.Carry
	entry.Carry = nil
	local name = carry and carry.Name or "cucumber"
	--.. 2026-09-23 (items): remember what was stolen so a Redemption Token can bring it back (ItemService.RecordLoss)
	if carry and carry.Model and raid and raid.Player then
		local stolen = carry.Model
		local itemApi = ServerStorage:FindFirstChild("ItemAPI")
		local recordLoss = itemApi and itemApi:FindFirstChild("RecordLoss")
		if recordLoss then
			pcall(recordLoss.Invoke, recordLoss, raid.Player, {Name = name, Zone = stolen:GetAttribute("Zone"), Type = stolen:GetAttribute("TypeName"),
				Golden = stolen:GetAttribute("Golden") == true, Material = stolen:GetAttribute("Material"), Mutations = stolen:GetAttribute("Mutations"), SizeTier = stolen:GetAttribute("SizeTier")})
		end
		CucumberStolenEvent:Fire(raid.Player, {Name = name, Zone = stolen:GetAttribute("Zone"), Type = stolen:GetAttribute("TypeName")}) -- 2026-09-24 (Zombie Den: a deal for it)
	end
	if carry and carry.Model then carry.Model:Destroy() end
	if raid then
		raid.Stolen += 1
		if raid.Day then
			Send(raid, {Kind = "ThiefStole", Name = name})
			print(("[ZombieRaid] a thief got away with %s's %s"):format(raid.Player.Name, name))
		else
			Send(raid, {Kind = "Stolen", Name = name, Stolen = raid.Stolen, Limit = raid.Limit})
			print(("[ZombieRaid] %s's %s was stolen (%d/%d)"):format(raid.Player.Name, name, raid.Stolen, raid.Limit))
		end
	end
	SoundController.PlayFXAt("Slide Whistle", entry.Root.Position, {Volume = 0.7, RollOff = 60})
	Poof(DoorPoint() + Vector3.new(0.5, 3, 0), Color3.fromRGB(40, 200, 90), 18)
	Despawn(entry, "Escape")
	if raid and not raid.Over and raid.Stolen >= raid.Limit then
		raid.Over = true
		raid.Result = "ZombiesWin"
		Send(raid, {Kind = "ZombiesWin", Stolen = raid.Stolen, Limit = raid.Limit})
		print(("[ZombieRaid] the zombies win against %s"):format(raid.Player.Name))
		ReportResult(raid, "ZombiesWin") -- 2026-09-23 (Manage panel)
		for _, other in ipairs(raid.Zombies) do
			if not other.Dead then
				RestoreCarry(other, true) -- the raid is over: straight home
				Despawn(other, "Escape")
			end
		end
		ReturnDropped(raid)
		Publish(raid)
		SyncRaidLive(raid.Player) -- 2026-09-22: the raid is over
	elseif raid then
		CheckRaidEnd(raid) -- the last zombie may leave by escaping, not dying
	end
end

--..Shadow kinds..--
local function SetShade(entry, on)
	if entry.Shaded == on then return end
	entry.Shaded = on
	entry.Model:SetAttribute("Shaded", on)
	local level = ZombieCatalog.SHADOW_TRANSPARENCY
	for part, base in pairs(entry.BaseTransparency) do
		if part.Parent then part.Transparency = on and math.max(base, level) or base end
	end
	local head = entry.Model:FindFirstChild("Head")
	local tag = head and head:FindFirstChild("ZombieTag")
	if tag then
		local label = tag:FindFirstChild("Label")
		local bar = tag:FindFirstChild("Bar")
		if label then
			label.TextTransparency = on and 0.6 or 0
			local stroke = label:FindFirstChildOfClass("UIStroke")
			if stroke then stroke.Transparency = on and 0.6 or 0 end
		end
		if bar then
			bar.BackgroundTransparency = on and 0.6 or 0
			local fill = bar:FindFirstChild("Fill")
			if fill then fill.BackgroundTransparency = on and 0.6 or 0 end
		end
	end
	if on then Poof(entry.Root.Position, entry.Variety.Glow, 8) end
end

--..Damage API..--
local function Flash(entry)
	if entry.Flashing then return end
	entry.Flashing = true
	local colors = {}
	for _, d in ipairs(entry.Model:GetDescendants()) do
		if d:IsA("BasePart") and d.Transparency < 1 then
			colors[d] = d.Color
			d.Color = Color3.fromRGB(255, 80, 80)
		end
	end
	task.delay(0.1, function()
		for p, c in pairs(colors) do
			if p.Parent then p.Color = c end
		end
		entry.Flashing = false
	end)
end

local function DamageZombie(model, amount, source, attacker)
	local entry = Zombies[model]
	amount = tonumber(amount) or 0
	if not entry or entry.Dead or amount <= 0 then return false, 0 end
	if entry.Shaded or entry.Underground then return false, entry.Humanoid.Health end -- a shadow / a digger underground: nothing touches it
	--.. 2026-09-24 co-op nights: another player's blow lands only once their own wave is done (see the top)
	if typeof(attacker) == "Instance" and attacker:IsA("Player") and entry.Raid and entry.Raid.Player ~= attacker and not entry.Raid.Day then
		if not HelpAllowed(attacker) then
			HelpBlocked(attacker)
			return false, entry.Humanoid.Health
		end
		RegisterHelp(entry.Raid, attacker, amount)
	end
	entry.Humanoid:TakeDamage(amount)
	UpdateBar(entry)
	Flash(entry)
	local now = os.clock()
	if now >= entry.NextHitSound then
		entry.NextHitSound = now + HIT_SOUND_GAP
		SoundController.PlayFXAt("Hit Crunch", entry.Root.Position, {Volume = 0.9, RollOff = 60})
	end
	if source == "Bat" then entry.StunUntil = math.max(entry.StunUntil, now + 0.3) end
	--.. a player's blow turns the whole raid on them (before the kill check: a one-hit sprinter counts too)
	local raid = entry.Raid
	if typeof(attacker) == "Instance" and attacker:IsA("Player") and raid and not raid.Ended then
		raid.Hostile = raid.Hostile or {}
		if not raid.Hostile[attacker] then
			raid.Hostile[attacker] = true
			Remote:FireClient(attacker, {Kind = "Hostile", Zombie = entry.Variety.Name})
			print(("[ZombieRaid] %s hit a %s: %s's zombies are hostile to them now"):format(attacker.Name, entry.Variety.Name, raid.Player.Name))
		end
	end
	if entry.Humanoid.Health <= 0 then Kill(entry, source) end
	return true, entry.Humanoid.Health
end
DamageAPI.OnInvoke = DamageZombie
ZombiesAPI.OnInvoke = function()
	local list = {}
	for model, entry in pairs(Zombies) do
		if not entry.Dead and not entry.Shaded and not entry.Underground and model.Parent then table.insert(list, model) end
	end
	return list
end
--.. 2026-09-22: one batch per pet scan (CONTRACTS 7.5): the live, targetable zombies (no cutscene Hold ones)
--.. with what a pet's priority needs - none of it is replicated (Grappling / Carry are entry state)
TargetInfosAPI.OnInvoke = function()
	local list = {}
	for model, entry in pairs(Zombies) do
		if not entry.Dead and not entry.Shaded and not entry.Underground and not entry.Hold and model.Parent then
			local raid = entry.Raid
			local root = entry.Root
			table.insert(list, {
				Model = model,
				Owner = raid and raid.UserId or nil,
				State = entry.State,
				Carrying = entry.Carry ~= nil,
				Grappling = entry.Grappling == true,
				Digging = entry.Digging == true,
				Day = raid ~= nil and raid.Day == true,
				Health = entry.Humanoid.Health,
				MaxHealth = entry.Humanoid.MaxHealth,
				Position = (root and root.Parent) and root.Position or model:GetPivot().Position,
			})
		end
	end
	return list
end
IsZombieAPI.OnInvoke = function(model)
	local entry = Zombies[model]
	return entry ~= nil and not entry.Dead
end
SlowAPI.OnInvoke = function(model, seconds)
	local entry = Zombies[model]
	if entry and not entry.Dead then entry.SlowUntil = math.max(entry.SlowUntil, os.clock() + (tonumber(seconds) or 0.5)) return true end
	return false
end
StunAPI.OnInvoke = function(model, seconds)
	local entry = Zombies[model]
	if entry and not entry.Dead then entry.StunUntil = math.max(entry.StunUntil, os.clock() + (tonumber(seconds) or 0.3)) return true end
	return false
end

--..Bashing placed builds..--
local function BuildOf(part)
	local model = part:FindFirstAncestorOfClass("Model")
	while model do
		if CollectionService:HasTag(model, BUILD_TAG) then return model end
		model = model.Parent and model.Parent:FindFirstAncestorOfClass("Model") or nil
	end
	return nil
end

local BuildAPI -- ServerStorage.BuildAPI (BuildHealthService): the only way a build takes damage
local function DamageBuild(build, amount)
	if not (BuildAPI and BuildAPI.Parent) then BuildAPI = ServerStorage:FindFirstChild("BuildAPI") end
	local fn = BuildAPI and BuildAPI:FindFirstChild("Damage")
	if not fn then return nil end
	return fn:Invoke(build, amount, "Zombie")
end

local function Bash(entry, now)
	local raid = entry.Raid
	if not raid or now < entry.NextBash then return false end
	local root = entry.Root
	local holder = HolderOf(raid.Plot)
	if not holder then return false end
	local dir = entry.MoveTarget and Flat(entry.MoveTarget - root.Position) or root.CFrame.LookVector
	if dir.Magnitude < 0.1 then dir = root.CFrame.LookVector end
	dir = Flat(dir).Unit
	--.. only what is in its way, and only what still stands (a broken build is walked through, not bashed)
	local standing = {}
	for _, child in ipairs(holder:GetChildren()) do
		if child:GetAttribute("Broken") ~= true then table.insert(standing, child) end
	end
	if #standing == 0 then return false end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = standing
	local hit
	for _, dy in ipairs({-1, 1, 3}) do
		hit = workspace:Raycast(root.Position + Vector3.new(0, dy, 0), dir * (BASH_REACH * math.max(1, entry.Variety.Scale)), params)
		if hit then break end
	end
	local build = hit and BuildOf(hit.Instance)
	if not build or build:GetAttribute("IsFloor") == true or build:GetAttribute("IsStairs") == true then return false end
	entry.NextBash = now + BASH_INTERVAL
	local key = build:GetAttribute("BuildKey")
	local health, broken = DamageBuild(build, BASH_DAMAGE * ZombieCatalog.HpMult(entry.Raid and entry.Raid.Level or 1)) -- 2026-09-23: bashes climb with the level like the hit points
	if health == nil then return false end -- no BuildHealthService: nothing can be bashed
	SoundController.PlayFXAt("Big Thud", hit.Position, {Volume = 0.8, RollOff = 60})
	if key == "BarbedStoneWall" then DamageZombie(entry.Model, math.max(1, entry.Humanoid.MaxHealth * ZombieCatalog.BARBED_FRACTION), "Barbed") end -- 2026-09-23: a share of its max HP
	if broken then
		local name = tostring(build:GetAttribute("DisplayName") or key or build.Name)
		Send(raid, {Kind = "BuildBroken", Name = name})
		print(("[ZombieRaid] %s broke %s's %s (it mends by day)"):format(entry.Variety.Name, raid.Player.Name, name))
	end
	return true
end

--..Navigation..--
local function Navigate(entry, goal, now)
	local root = entry.Root
	local fresh = entry.Goal and (entry.Goal - goal).Magnitude < 2
	if not fresh or now >= entry.RepathAt then
		entry.Goal = goal
		entry.RepathAt = now + REPATH_SECONDS
		if not entry.Pathing then
			entry.Pathing = true
			task.spawn(function()
				local path = entry.Path
				local ok = pcall(path.ComputeAsync, path, root.Position, goal)
				if ok and path.Status == Enum.PathStatus.Success then
					entry.Waypoints = path:GetWaypoints()
					entry.WaypointIndex = 2
					entry.Direct = false
				else
					entry.Waypoints = nil
					entry.Direct = true
				end
				entry.Pathing = false
			end)
		end
	end
	local target = goal
	if entry.Waypoints then
		local wp = entry.Waypoints[entry.WaypointIndex]
		while wp and Flat(root.Position - wp.Position).Magnitude < WAYPOINT_REACH do
			entry.WaypointIndex += 1
			wp = entry.Waypoints[entry.WaypointIndex]
		end
		if wp then
			target = wp.Position
			if wp.Action == Enum.PathWaypointAction.Jump then entry.Humanoid.Jump = true end
		end
	end
	entry.MoveTarget = target
	entry.Humanoid:MoveTo(target)
end

--..Grapple kinds..--
--.. 2026-09-22: a cucumber being hooked / reeled in goes straight back to where it stood and the pull ends
--.. (its task sees GrappleTarget cleared on its next step) - the raid is ending or the owner's base is being
--.. saved for a leave, and the snapshot must never keep a half-pulled pose. Never yields. Also run by Forget: a
--.. grappler that dies / leaves lets go at once, so its task never puts the cucumber back after the raid sent it home.
function SettleGrapple(entry) -- forward-declared at the top (Forget calls it)
	local target, rest = entry.GrappleTarget, entry.GrappleRest
	if not target then return end
	entry.GrappleTarget, entry.GrappleRest = nil, nil
	if rest and target.Parent and CollectionService:HasTag(target, PLACED_TAG) then target:PivotTo(rest) end
end

local function StartGrapple(entry, target)
	if HookedBy(entry.Raid, target) then return false end -- 2026-09-22: one rope per cucumber (a 2nd hook took the dragged pose as its rest)
	local root = entry.Root
	local primary = target.PrimaryPart or target:FindFirstChildWhichIsA("BasePart", true)
	if not primary then return false end
	entry.Grappling = true
	entry.StunUntil = math.max(entry.StunUntil, os.clock() + ZombieCatalog.GRAPPLE_HOOK + ZombieCatalog.GRAPPLE_PULL + 0.2)
	entry.Humanoid:MoveTo(root.Position)
	local aim = target:GetPivot().Position
	root.CFrame = CFrame.lookAt(root.Position, Vector3.new(aim.X, root.Position.Y, aim.Z))
	local hand = entry.Model:FindFirstChild("RightHand") or root
	local a0 = Instance.new("Attachment")
	a0.Name = "GrappleA"
	a0.Parent = hand
	local a1 = Instance.new("Attachment")
	a1.Name = "GrappleB"
	a1.Parent = primary
	local rope = Instance.new("Beam")
	rope.Name = "GrappleRope"
	rope.Attachment0 = a0
	rope.Attachment1 = a1
	rope.Width0 = 0.18
	rope.Width1 = 0.18
	rope.Color = ColorSequence.new(Color3.fromRGB(70, 60, 50))
	rope.LightEmission = 0
	rope.FaceCamera = true
	rope.Segments = 1
	rope.Parent = hand
	SoundController.PlayFXAt("Whoosh", root.Position, {Volume = 0.8, RollOff = 70})
	Send(entry.Raid, {Kind = "Grappled", Name = target:GetAttribute("CucumberName") or target.Name, Zombie = entry.Variety.Name})
	task.spawn(function()
		local rest = target:GetPivot()
		local home = HomeRest(entry.Raid, target) -- 2026-09-22: its home BEFORE the pull (the pulled pose is no carry rest)
		entry.GrappleHome = home -- 2026-09-22: HomeRest hands it to a zombie that grabs the cucumber mid-pull (read while GrappleTarget is set)
		entry.GrappleTarget, entry.GrappleRest = target, rest -- 2026-09-22: SettleGrapple snaps it back + ends the pull
		task.wait(ZombieCatalog.GRAPPLE_HOOK)
		local ok = not entry.Dead and entry.GrappleTarget == target and target.Parent and CollectionService:HasTag(target, PLACED_TAG) and not TheftBlocked(entry, target)
		if ok then
			SoundController.PlayFXAt("Metal Heavy", target:GetPivot().Position, {Volume = 0.7, RollOff = 70})
			local t0 = os.clock()
			while true do
				local a = math.clamp((os.clock() - t0) / ZombieCatalog.GRAPPLE_PULL, 0, 1)
				if entry.Dead or entry.GrappleTarget ~= target or not target.Parent or not CollectionService:HasTag(target, PLACED_TAG) then ok = false break end
				local goal = root.Position + root.CFrame.LookVector * 2.5
				goal = Vector3.new(goal.X, rest.Position.Y, goal.Z)
				target:PivotTo(rest:Lerp(CFrame.new(goal) * rest.Rotation, a))
				if a >= 1 then break end
				RunService.Heartbeat:Wait()
			end
		end
		rope:Destroy()
		a0:Destroy()
		a1:Destroy()
		entry.Grappling = nil
		local settled = entry.GrappleTarget ~= target -- 2026-09-22: SettleGrapple (a death, the raid's end, a leave) already put it back
		if entry.GrappleTarget == target then entry.GrappleTarget, entry.GrappleRest = nil, nil end
		if ok and not entry.Dead then
			if not Grab(entry, target, home) then target:PivotTo(rest) end
		elseif not settled and target.Parent and CollectionService:HasTag(target, PLACED_TAG) then
			local raid = entry.Raid -- 2026-09-22: a raid already over (ReturnDropped done) wants it home, not back in the lobby
			target:PivotTo((raid and (raid.Over or raid.Ended)) and home or rest)
		end
	end)
	return true
end

--..Digger kinds..--
local function Mound(position)
	Poof(position + Vector3.new(0, 0.5, 0), Color3.fromRGB(110, 80, 50), 7)
end

local function StartDig(entry, target)
	local root = entry.Root
	local depth = ZombieCatalog.DIG_DEPTH
	entry.Digging = true
	entry.DigCooldownUntil = os.clock() + ZombieCatalog.DIG_COOLDOWN
	entry.Humanoid:MoveTo(root.Position)
	Send(entry.Raid, {Kind = "Digging", Zombie = entry.Variety.Name})
	task.spawn(function()
		local start = root.CFrame
		local hip = entry.Humanoid.HipHeight + root.Size.Y * 0.5
		local feet = start.Position - Vector3.new(0, hip, 0)
		Mound(feet)
		SoundController.PlayFXAt("Dirt Dig", feet, {Volume = 1, RollOff = 80})
		root.Anchored = true
		entry.Underground = true
		entry.Model:SetAttribute("Underground", true)
		pcall(function() entry.Walk:Stop(0.1) entry.Idle:Play(0.1) end)
		--.. sink
		local t0 = os.clock()
		while os.clock() - t0 < ZombieCatalog.DIG_DIVE do
			local a = (os.clock() - t0) / ZombieCatalog.DIG_DIVE
			root.CFrame = start - Vector3.new(0, depth * a, 0)
			RunService.Heartbeat:Wait()
		end
		--.. travel to the emerge point (within grab reach of the cucumber, on the side it came from)
		local goal = target:GetPivot().Position
		local away = Flat(start.Position - goal)
		away = away.Magnitude > 0.1 and away.Unit or Vector3.new(-1, 0, 0)
		local hb = target:FindFirstChild("PlotHitbox") -- (GrabReach is defined further down; same maths)
		local reach = GRAB_RANGE * math.max(1, entry.Variety.Scale * 0.8) + (hb and math.max(hb.Size.X, hb.Size.Z) * 0.5 or 1) - 1
		local ex, ez = goal.X + away.X * reach, goal.Z + away.Z * reach
		local emerge = Vector3.new(ex, GroundY(ex, ez, goal.Y + 12, feet.Y), ez)
		local from = feet - Vector3.new(0, depth, 0)
		local to = emerge - Vector3.new(0, depth, 0)
		local dist = (to - from).Magnitude
		local heading = Flat(to - from)
		heading = heading.Magnitude > 0.1 and heading.Unit or Vector3.new(1, 0, 0)
		local duration = dist / ZombieCatalog.DIG_SPEED
		t0 = os.clock()
		local lastMound = -1
		while os.clock() - t0 < duration do
			if entry.Dead then break end
			local a = (os.clock() - t0) / duration
			local p = from:Lerp(to, a)
			root.CFrame = CFrame.lookAt(p + Vector3.new(0, hip, 0), p + Vector3.new(0, hip, 0) + heading)
			if os.clock() - lastMound > 0.45 then
				lastMound = os.clock()
				Mound(Vector3.new(p.X, GroundY(p.X, p.Z, p.Y + depth + 12, p.Y + depth), p.Z))
			end
			RunService.Heartbeat:Wait()
		end
		--.. rise beside the cucumber, facing it
		if not entry.Dead then
			local face = Flat(goal - emerge)
			face = face.Magnitude > 0.1 and face.Unit or heading
			local up = CFrame.lookAt(emerge + Vector3.new(0, hip + 0.05, 0), emerge + Vector3.new(0, hip + 0.05, 0) + face)
			Mound(emerge)
			SoundController.PlayFXAt("Dirt Dig", emerge, {Volume = 1, RollOff = 80})
			t0 = os.clock()
			while os.clock() - t0 < ZombieCatalog.DIG_DIVE do
				local a = (os.clock() - t0) / ZombieCatalog.DIG_DIVE
				root.CFrame = up - Vector3.new(0, depth * (1 - a), 0)
				RunService.Heartbeat:Wait()
			end
			root.CFrame = up
		end
		entry.Underground = false
		entry.Model:SetAttribute("Underground", false)
		if not entry.Dead then Unanchor(entry) end
		entry.Digging = nil
		entry.LastPos = root.Position
		entry.LastMove = os.clock()
		entry.RepathAt = 0
	end)
	return true
end

local function NearestCucumber(entry)
	local raid = entry.Raid
	local best, bestScore
	local claims = {}
	for _, other in ipairs(raid.Zombies) do
		if other ~= entry and not other.Dead and other.Target then claims[other.Target] = (claims[other.Target] or 0) + 1 end
	end
	for _, model in ipairs(CucumbersOf(raid.Plot, raid.UserId)) do
		if model == entry.AvoidModel and os.clock() < (entry.AvoidUntil or 0) then continue end -- 2026-09-22: shield-blocked there (OD-10)
		local d = Flat(model:GetPivot().Position - entry.Root.Position).Magnitude + 8 * (claims[model] or 0)
		if not bestScore or d < bestScore then best, bestScore = model, d end
	end
	return best
end

local function GrabReach(model, entry)
	local hb = model:FindFirstChild("PlotHitbox")
	local extra = hb and math.max(hb.Size.X, hb.Size.Z) * 0.5 or 1
	return GRAB_RANGE * math.max(1, entry.Variety.Scale * 0.8) + extra
end

--..Hostility: a zombie you have hit swings at you when you stand in its way (it never comes after you)..--
local function HitReach(entry)
	return HIT_RANGE * math.max(1, entry.Variety.Scale * 0.85)
end

local function InTheWay(entry)
	local hostile = entry.Raid.Hostile
	if not hostile then return nil end
	local root = entry.Root
	local forward = Flat(root.CFrame.LookVector)
	if forward.Magnitude < 0.1 then return nil end
	forward = forward.Unit
	local reach = HitReach(entry)
	local best, bestDist
	for player in pairs(hostile) do
		local character = player.Parent and player.Character
		local proot = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if proot and humanoid and humanoid.Health > 0 then
			local offset = proot.Position - root.Position
			local flat = Flat(offset)
			local dist = flat.Magnitude
			if dist <= reach and math.abs(offset.Y) < 6 and (dist < 1.5 or flat.Unit:Dot(forward) >= HIT_CONE) then
				if not bestDist or dist < bestDist then best, bestDist = player, dist end
			end
		end
	end
	return best
end

local function Swat(entry, player, now)
	local root = entry.Root
	local character = player.Character
	local proot = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (proot and humanoid) then return end
	entry.NextHit = now + HIT_COOLDOWN
	entry.StunUntil = math.max(entry.StunUntil, now + HIT_PAUSE) -- Tick reads StunUntil as WalkSpeed 0: it stands to swing
	local away = Flat(proot.Position - root.Position)
	away = away.Magnitude > 0.05 and away.Unit or Flat(root.CFrame.LookVector).Unit
	root.CFrame = CFrame.lookAt(root.Position, root.Position + away)
	if entry.Swing then pcall(function() entry.Swing:Play(0.05) end) end
	SoundController.PlayFXAt("Air Slice", root.Position, {Volume = 0.7, RollOff = 40})
	task.delay(SWING_DELAY, function()
		if entry.Dead or not entry.Model.Parent or entry.Shaded then return end
		if player.Parent ~= Players or player.Character ~= character or humanoid.Health <= 0 then return end
		local offset = Flat(proot.Position - root.Position)
		if offset.Magnitude > HitReach(entry) + 2 then return end -- they got out of the way
		local dir = offset.Magnitude > 0.05 and offset.Unit or away
		if HIT_DAMAGE > 0 then humanoid:TakeDamage(HIT_DAMAGE) end
		SoundController.PlayFXAt("Hit Crunch", proot.Position, {Volume = 0.9, RollOff = 60})
		Remote:FireClient(player, {Kind = "Hit", Zombie = entry.Variety.Name, Direction = dir, Distance = KNOCKBACK_DISTANCE, Seconds = KNOCKBACK_TIME, Damage = HIT_DAMAGE})
	end)
end

local function Tick(entry, now)
	if entry.Dead then return end
	local raid = entry.Raid
	if not raid then return end
	if not entry.Model.Parent then -- destroyed from outside (fell out of the world, deleted)
		entry.Dead = true
		entry.Carry = nil
		Forget(entry)
		CheckRaidEnd(raid)
		return
	end
	local root, humanoid = entry.Root, entry.Humanoid
	local variety = entry.Variety
	--.. speed
	local speed = variety.Speed
	if entry.Carry then speed *= entry.Grapple and ZombieCatalog.GRAPPLE_CARRY_SPEED or CARRY_SPEED end
	if now < entry.SlowUntil then speed *= SLOW_MULT end
	if now < entry.StunUntil then speed = 0 end
	humanoid.WalkSpeed = speed
	SetMoving(entry, Flat(root.AssemblyLinearVelocity).Magnitude)
	if entry.Model:GetAttribute("State") ~= entry.State then entry.Model:SetAttribute("State", entry.State) end
	if entry.Shadow then
		if entry.Carry then
			if entry.Shaded then SetShade(entry, false) end
		elseif now >= entry.ShadeAt then
			SetShade(entry, not entry.Shaded)
			entry.ShadeAt = now + (entry.Shaded and ZombieCatalog.SHADOW_HIDDEN or ZombieCatalog.SHADOW_VISIBLE)
		end
	end
	if entry.Grappling or entry.Digging then return end -- reeling a cucumber in / underground: no walking
	--.. hostile: anyone who hit this raid and now stands in its way gets a swing (whatever it was doing)
	if raid.Hostile and not entry.Shaded and now >= entry.NextHit then
		local victim = InTheWay(entry)
		if victim then Swat(entry, victim, now) end
	end
	--.. state
	local plot = raid.Plot
	if entry.State == "Carry" then
		--.. back across the lobby to the door it came out of
		local door = DoorPoint()
		if Flat(root.Position - door).Magnitude <= DOOR_REACH then
			Escape(entry)
			return
		end
		Navigate(entry, door, now)
	else
		local target = entry.Target
		local holder = HolderOf(plot)
		if target and (target.Parent ~= holder or not CollectionService:HasTag(target, PLACED_TAG)) then target = nil end
		if not target then
			target = NearestCucumber(entry)
			entry.Target = target
		end
		if target then
			entry.State = "Seek"
			local pos = target:GetPivot().Position
			local dist = Flat(pos - root.Position).Magnitude
			if dist <= GrabReach(target, entry) then
				if os.clock() >= (entry.BlockedUntil or 0) then -- 2026-09-22: a shield-blocked zombie grabs nothing for a moment
					if not Grab(entry, target) then entry.Target = nil end
				end
				return
			end
			if entry.Grapple and dist <= (variety.GrappleRange or ZombieCatalog.GRAPPLE_RANGE) and now >= entry.StunUntil then
				if StartGrapple(entry, target) then return end
			end
			if entry.Digger and dist >= ZombieCatalog.DIG_RANGE_MIN and now >= entry.DigCooldownUntil and now >= entry.StunUntil then
				if StartDig(entry, target) then return end
			end
			Navigate(entry, Vector3.new(pos.X, PlotTop(plot), pos.Z), now)
		elseif raid.Day then
			--.. a thief with nothing left to steal walks back to the door and leaves
			entry.State = "Leave"
			local door = DoorPoint()
			if Flat(root.Position - door).Magnitude <= DOOR_REACH then
				Despawn(entry, "Escape")
				CheckRaidEnd(raid)
				return
			end
			Navigate(entry, door, now)
		else
			--.. nothing to steal: roam the base
			entry.State = "Wander"
			if not entry.WanderGoal or now > (entry.WanderUntil or 0) or Flat(entry.WanderGoal - root.Position).Magnitude < 4 then
				local hx, hz = plot.Size.X * 0.5 - 4, plot.Size.Z * 0.5 - 4
				entry.WanderGoal = (plot.CFrame * CFrame.new(rng:NextNumber(-hx, hx), 0, rng:NextNumber(-hz, hz))).Position
				entry.WanderGoal = Vector3.new(entry.WanderGoal.X, PlotTop(plot), entry.WanderGoal.Z)
				entry.WanderUntil = now + WANDER_SECONDS
			end
			Navigate(entry, entry.WanderGoal, now)
		end
	end
	--.. stuck?
	if Flat(root.Position - entry.LastPos).Magnitude > 0.6 then
		entry.LastPos = root.Position
		entry.LastMove = now
	elseif now - entry.LastMove > STUCK_SECONDS and speed > 0 then
		entry.LastMove = now
		entry.RepathAt = 0
		if not Bash(entry, now) then humanoid.Jump = true end
	end
end

--..Raid lifecycle..--
local function ThreatOf(player, plot)
	local cucumbers = CucumbersOf(plot, player.UserId)
	local income = IncomeOf(player)
	local score = ZombieCatalog.ThreatOf(cucumbers, income)
	return ZombieCatalog.LevelOf(score), score, #cucumbers
end
ThreatLevelAPI.OnInvoke = function(player) -- 2026-09-23 (Manage panel): the level a raid would be right now
	if typeof(player) ~= "Instance" or not player:IsA("Player") then return nil end
	local plot = PlotOf(player)
	if not plot then return nil end
	return ThreatOf(player, plot)
end

local function NewRaid(player, plot, forcedLevel, isDay)
	local level, score, count = ThreatOf(player, plot)
	if forcedLevel then level = math.clamp(forcedLevel, 1, ZombieCatalog.MAX_LEVEL) end
	local raid = {
		Player = player, UserId = player.UserId, Plot = plot, Level = level, Score = score,
		Limit = isDay and math.huge or math.min(ZombieCatalog.STEAL_LIMIT, count), Cucumbers = count, Stolen = 0,
		Zombies = {}, Alive = 0, Over = false, Day = isDay == true,
	}
	if not isDay then raid.Wave = ZombieCatalog.WaveFor(level, rng) end
	plot:SetAttribute("ThreatLevel", level)
	Publish(raid)
	return raid
end

local function EndRaid(raid, reason)
	if raid.Ended then return end
	raid.Ended = true
	for _, entry in ipairs(raid.Zombies) do
		SettleGrapple(entry) -- 2026-09-22: a half-pulled cucumber back in place before any snapshot (a dead grappler's pull may still be pending)
		if not entry.Dead then
			RestoreCarry(entry, reason ~= "Left", nil, reason == "Left") -- the raid is over: a carried load goes straight home (2026-09-22: force on a leave)
			if reason == "Left" then
				entry.Model:Destroy()
				Forget(entry)
				entry.Dead = true
			else
				Despawn(entry, reason == "Dawn" and "Burn" or "Escape")
			end
		end
	end
	ReturnDropped(raid)
	if not raid.Over then
		raid.Over = true
		raid.Result = reason
		if reason == "Dawn" and not raid.Day then
			--.. the night ran out: nothing stolen = the player won the night
			Send(raid, {Kind = raid.Stolen == 0 and "Survived" or "Dawn", Stolen = raid.Stolen, Limit = raid.Limit, Level = raid.Level})
			print(("[ZombieRaid] dawn for %s: stolen %d/%d -> %s"):format(raid.Player.Name, raid.Stolen, raid.Limit, raid.Stolen == 0 and "won the night" or "night over"))
			ReportResult(raid, raid.Stolen == 0 and "Survived" or "Dawn") -- 2026-09-23 (Manage panel: days survived)
			if raid.Stolen == 0 then RewardHelpers(raid) end -- 2026-09-24 co-op nights
		end
	end
	if raid.Day then
		if DayRaids[raid.Player] == raid then DayRaids[raid.Player] = nil end
	else
		Raids[raid.Player] = nil
	end
	if raid.Player then SyncRaidLive(raid.Player) end -- 2026-09-22
end

local function EndDayRaids(reason)
	for _, raid in pairs(DayRaids) do EndRaid(raid, reason) end
end

local function EndAll(reason)
	for player, raid in pairs(Raids) do EndRaid(raid, reason) end
	--.. strays (dev spawns without a raid)
	for model, entry in pairs(Zombies) do
		if not entry.Dead and not entry.Raid then Despawn(entry, reason == "Dawn" and "Burn" or "Escape") end
	end
	Phase = "Idle"
end

local function StandingCFrame(entry, groundPos, facing)
	local hip = entry.Humanoid.HipHeight + entry.Root.Size.Y * 0.5
	local pos = groundPos + Vector3.new(0, hip + 0.05, 0)
	return CFrame.lookAt(pos, pos + facing)
end

local function BasePoints(raid, n)
	local plot = raid.Plot
	local frontX = FrontX(plot)
	local top = PlotTop(plot)
	local points = {}
	for i = 1, n do
		local z = plot.Position.Z + (i - (n + 1) * 0.5) * BASE_SPREAD
		local x = frontX - BASE_OFFSET
		points[i] = Vector3.new(x, GroundY(x, z, top + 6, top - 0.3), z)
	end
	return points
end

--.. night falls: the raided player is stood at the front of their own plot (user 2026-09-11)
local function SendHome(raid)
	local player, plot = raid.Player, raid.Plot
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (root and humanoid) or humanoid.Health <= 0 then return end
	humanoid.Sit = false
	local seat = humanoid.SeatPart
	local weld = seat and seat:FindFirstChild("SeatWeld")
	if weld then weld:Destroy() end
	local spawn = plot:FindFirstChild("PlotSpawn")
	local cf
	if spawn then
		cf = spawn.CFrame * CFrame.new(0, 2.6, 0)
	else
		local pos = Vector3.new(FrontX(plot) + 4, PlotTop(plot) + 3, plot.Position.Z)
		cf = CFrame.lookAt(pos, pos + Vector3.new(1, 0, 0))
	end
	character:PivotTo(cf)
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			part.AssemblyLinearVelocity = Vector3.zero
			part.AssemblyAngularVelocity = Vector3.zero
		end
	end
end

local function AtBase(raid)
	local root = raid.Player.Character and raid.Player.Character:FindFirstChild("HumanoidRootPart")
	if not root then return true end
	local plot = raid.Plot
	local rp = plot.CFrame:PointToObjectSpace(root.Position)
	return math.abs(rp.X) <= plot.Size.X * 0.5 + 6 and math.abs(rp.Z) <= plot.Size.Z * 0.5 + 6
end

local function StartRaids(forcedLevel, withCutscene)
	if Phase ~= "Idle" then return false end
	local raids = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local plot = PlotOf(player)
		if plot and not Raids[player] then
			local raid = NewRaid(player, plot, forcedLevel)
			if raid.Cucumbers > 0 then -- nothing placed = nothing to raid (user 2026-09-11)
				Raids[player] = raid
				SyncRaidLive(player) -- 2026-09-22
				table.insert(raids, raid)
			end
		end
	end
	if #raids == 0 then
		print("[ZombieRaid] night: nobody has cucumbers placed, no raid")
		return false
	end
	EndDayRaids("Night")
	Phase = "Cutscene"
	local door = DoorPoint()
	local queue = {} -- {raid, variety} in the order they step out of the door
	for _, raid in ipairs(raids) do
		for _, variety in ipairs(raid.Wave) do table.insert(queue, {raid, variety}) end
	end
	local total = #queue
	local seconds = withCutscene and CUTSCENE_SECONDS or 1.5
	for _, player in ipairs(Players:GetPlayers()) do
		pcall(function() player:RequestStreamAroundAsync(door, 1) end)
	end
	if withCutscene then
		Remote:FireAllClients({Kind = "Cutscene", Focus = door, Seconds = seconds, Count = total})
	end
	print(("[ZombieRaid] night raid: %d raid(s), %d zombies through the door at (%.0f, %.0f)"):format(#raids, total, door.X, door.Z))
	task.spawn(function()
		local t0 = os.clock()
		task.delay(0.5, function() -- after DayNightCycle's own lane returns have run
			for _, raid in ipairs(raids) do
				if not raid.Ended then pcall(SendHome, raid) end
			end
		end)
		local rows = math.ceil(total / DOOR_COLUMNS)
		local window = seconds - DOOR_FIRST - 0.4
		local gap = math.min(DOOR_ROW_GAP, rows > 1 and window / (rows - 1) or DOOR_ROW_GAP)
		gap = math.max(0.12, gap)
		task.wait(DOOR_FIRST)
		local index = 0
		for row = 0, rows - 1 do
			for col = 0, DOOR_COLUMNS - 1 do
				local item = queue[index + 1]
				if not item then break end
				index += 1
				local raid, variety = item[1], item[2]
				if not raid.Ended then
					while AliveCount() >= ZombieCatalog.ALIVE_CAP and not raid.Ended do task.wait(0.5) end -- 2026-09-23: per-server cap
					local ground = DoorSpawn(door, index - 1)
					local entry = Spawn(variety, CFrame.new(ground), raid)
					if entry then
						entry.Hold = true -- not ticked until it stands at the base
						entry.Root.CFrame = StandingCFrame(entry, ground, Vector3.new(1, 0, 0))
						Unanchor(entry)
						entry.Humanoid:MoveTo(door + Vector3.new(WALK_OUT + row * 2 + rng:NextNumber(-2, 2), 0, (col - (DOOR_COLUMNS - 1) * 0.5) * DOOR_SPACING + rng:NextNumber(-1, 1)))
					end
				end
			end
			Poof(door + Vector3.new(0.5, 3, 0), Color3.fromRGB(40, 200, 90), 22)
			SoundController.PlayFXAt(row == 0 and "Thunder" or "Whoosh", door, {Volume = row == 0 and 1 or 0.6, RollOff = 220})
			if row < rows - 1 then task.wait(gap) end
		end
		for _, raid in ipairs(raids) do Publish(raid) end -- RaidAlive now counts the spawned wave
		task.wait(math.max(0, seconds - (os.clock() - t0)))
		--.. to the bases
		for _, raid in ipairs(raids) do
			if not raid.Ended then
				if not AtBase(raid) then pcall(SendHome, raid) end
				local points = BasePoints(raid, #raid.Zombies)
				for i, entry in ipairs(raid.Zombies) do
					if not entry.Dead then
						entry.Root.CFrame = StandingCFrame(entry, points[i], Vector3.new(1, 0, 0))
						entry.Root.AssemblyLinearVelocity = Vector3.zero
						entry.LastPos = entry.Root.Position
						entry.LastMove = os.clock()
					end
					entry.Hold = nil
				end
				if #points > 0 then Poof(points[math.ceil(#points / 2)] + Vector3.new(0, 2, 0), Color3.fromRGB(120, 255, 120), 30) end
				Send(raid, {Kind = "RaidStart", Level = raid.Level, Count = #raid.Zombies, Limit = raid.Limit, Cucumbers = raid.Cucumbers})
			end
		end
		if withCutscene then Remote:FireAllClients({Kind = "CutsceneEnd"}) end
		Phase = "Raid"
	end)
	return true
end

--..Daytime thieves..--
local function ThiefVariety(level)
	local top = level >= 7 and 4 or level >= 4 and 3 or level >= 2 and 2 or 1
	return ZombieCatalog.Variety(THIEF_POOL[rng:NextInteger(1, top)]) or ZombieCatalog.VARIETIES[1]
end

local function HasLiveThief(player)
	local raid = DayRaids[player]
	if not raid then return false end
	for _, e in ipairs(raid.Zombies) do
		if not e.Dead then return true end
	end
	return false
end

--.. 2026-09-22: RaidLive = their night raid is not over, or a thief of theirs is alive (nil when idle, never false)
SyncRaidLive = function(player)
	if not (typeof(player) == "Instance" and player.Parent) then return end -- a leaving player just keeps nil
	player:SetAttribute("RaidLive", (Raids[player] ~= nil and not Raids[player].Over) or HasLiveThief(player) or nil)
end

local function SpawnThief(player)
	if not player then return nil end
	local plot = PlotOf(player)
	if not plot or HasLiveThief(player) or #CucumbersOf(plot, player.UserId) == 0 then return nil end
	if AliveCount() >= ZombieCatalog.ALIVE_CAP then return nil end -- 2026-09-23: the server is full of zombies
	local raid = NewRaid(player, plot, nil, true)
	DayRaids[player] = raid
	SyncRaidLive(player) -- 2026-09-22
	local variety = ThiefVariety(raid.Level)
	local door = DoorPoint()
	local ground = DoorSpawn(door, rng:NextInteger(0, DOOR_COLUMNS - 1))
	local entry = Spawn(variety, CFrame.new(ground), raid)
	SyncRaidLive(player) -- 2026-09-22: the thief is alive (or failed to spawn)
	if not entry then return nil end
	entry.Root.CFrame = StandingCFrame(entry, ground, Vector3.new(1, 0, 0))
	Unanchor(entry)
	Poof(ground + Vector3.new(0, 3, 0), variety.Glow, 16)
	SoundController.PlayFXAt("Whoosh", ground, {Volume = 0.6, RollOff = 120})
	Send(raid, {Kind = "Thief", Zombie = variety.Name})
	print(("[ZombieRaid] a %s is walking toward %s's base"):format(variety.Name, player.Name))
	return entry
end

local function SecondsToNight()
	local endsAt = workspace:GetAttribute("PhaseEndsAt") -- DayNightCycle: the shared server time the day ends
	if typeof(endsAt) ~= "number" then return math.huge end
	return endsAt - workspace:GetServerTimeNow()
end

local nextThiefAt = os.clock() + DAY_THIEF_GRACE
task.spawn(function()
	while true do
		task.wait(1)
		if workspace:GetAttribute("CyclePhase") == "Day" and Phase == "Idle" and os.clock() >= nextThiefAt and SecondsToNight() >= DAY_THIEF_NIGHT_GUARD then
			nextThiefAt = os.clock() + rng:NextNumber(DAY_THIEF_MIN, DAY_THIEF_MAX)
			local candidates = {}
			for _, player in ipairs(Players:GetPlayers()) do
				local plot = PlotOf(player)
				if plot and not HasLiveThief(player) and #CucumbersOf(plot, player.UserId) > 0 then table.insert(candidates, player) end
			end
			if #candidates > 0 then SpawnThief(candidates[rng:NextInteger(1, #candidates)]) end
		end
	end
end)

--..Main loop..--
local acc = 0
RunService.Heartbeat:Connect(function(dt)
	acc += dt
	if acc < TICK then return end
	acc = 0
	local now = os.clock()
	for _, list in ipairs({Raids, DayRaids}) do
		for _, raid in pairs(list) do
			for _, entry in ipairs(raid.Zombies) do
				if not entry.Hold then
					local ok, err = pcall(Tick, entry, now)
					if not ok then warn("[ZombieRaid] tick: " .. tostring(err)) end
				end
			end
		end
	end
end)

--..Night watch..--
local function OnPhase()
	local phase = workspace:GetAttribute("CyclePhase")
	if phase == "Night" then
		if Phase == "Idle" then StartRaids(nil, true) end
	else
		if Phase ~= "Idle" then EndAll("Dawn") end
		if phase == "Day" then nextThiefAt = os.clock() + DAY_THIEF_GRACE end
	end
end
workspace:GetAttributeChangedSignal("CyclePhase"):Connect(OnPhase)

Players.PlayerRemoving:Connect(function(player)
	local raid = Raids[player]
	if raid then EndRaid(raid, "Left") end
	local day = DayRaids[player]
	if day then EndRaid(day, "Left") end
end)

--.. 2026-09-22 pre-close settle (DataService.OnBeforeClose order 35: after the pet / income flush, before
--.. BaseSave's snapshot at 40): a carried cucumber goes home, a half-pulled (grappled) one and a lobby-dropped
--.. one back to their rest pose, so the leave / shutdown snapshot never saves one lying in the lobby or loses
--.. one a carrier holds. Gates only on the profile being there (rule 0.13); never yields; each raid in its own pcall.
local function PreCloseRaids(player)
	local data = DataSvc()
	if not (data and type(data.GetData) == "function" and data.GetData(player) ~= nil) then return end
	local list = {}
	if Raids[player] then table.insert(list, Raids[player]) end
	if DayRaids[player] then table.insert(list, DayRaids[player]) end
	for _, raid in ipairs(list) do
		local ok, err = pcall(function()
			for _, entry in ipairs(raid.Zombies) do
				SettleGrapple(entry) -- any entry: a just-killed grappler's pull task may not have stepped yet
				if not entry.Dead and entry.Carry then
					RestoreCarry(entry, true, nil, true)
					entry.State = "Seek" -- empty-handed now: it must not walk to the door and "escape" with nothing
				end
			end
			ReturnDropped(raid, true)
		end)
		if not ok then warn("[ZombieRaid] pre-close settle: " .. tostring(err)) end
	end
end
do
	local data = DataSvc()
	if data and type(data.OnBeforeClose) == "function" then
		local ok, err = pcall(data.OnBeforeClose, PreCloseRaids, 35)
		if not ok then warn("[ZombieRaid] OnBeforeClose: " .. tostring(err)) end
	end
end

--..Studio hook..--
workspace:GetAttributeChangedSignal("ZombieDev"):Connect(function()
	local cmd = workspace:GetAttribute("ZombieDev")
	if type(cmd) ~= "string" or cmd == "" then return end
	workspace:SetAttribute("ZombieDev", nil)
	local kind, arg = cmd:match("^(%w+):?(.*)$")
	if kind == "raid" then
		if Phase ~= "Idle" then EndAll("Dawn") end
		StartRaids(tonumber(arg), true)
	elseif kind == "cutscene" then
		Remote:FireAllClients({Kind = "Cutscene", Focus = DoorPoint(), Seconds = CUTSCENE_SECONDS, Count = 0})
		task.delay(CUTSCENE_SECONDS, function() Remote:FireAllClients({Kind = "CutsceneEnd"}) end)
	elseif kind == "end" then
		EndAll("Dawn")
		EndDayRaids("Night")
		for _, p in ipairs(Players:GetPlayers()) do SyncRaidLive(p) end -- 2026-09-22
	elseif kind == "thief" then
		SpawnThief(Players:GetPlayers()[1])
	elseif kind == "kill" then
		for model, entry in pairs(Zombies) do
			if not entry.Dead then Kill(entry, "Dev") end
		end
		for _, p in ipairs(Players:GetPlayers()) do SyncRaidLive(p) end -- 2026-09-22
	elseif kind == "spawn" then
		local variety = ZombieCatalog.Variety(arg) or ZombieCatalog.VARIETIES[1]
		local player = Players:GetPlayers()[1]
		local root = player and player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if not root then return end
		local raid = Raids[player]
		if not raid then
			local plot = PlotOf(player)
			if not plot then return end
			raid = NewRaid(player, plot, nil)
			Raids[player] = raid
			SyncRaidLive(player) -- 2026-09-22
		elseif raid.Over then
			raid.Over = false
			raid.Result = nil
			raid.Stolen = 0
			raid.Limit = math.min(ZombieCatalog.STEAL_LIMIT, #CucumbersOf(raid.Plot, raid.UserId))
			SyncRaidLive(player) -- 2026-09-22: reopened
		end
		Phase = "Raid"
		local ground = root.Position + root.CFrame.LookVector * 10 - Vector3.new(0, 3, 0)
		ground = Vector3.new(ground.X, GroundY(ground.X, ground.Z, root.Position.Y + 5, root.Position.Y - 3), ground.Z)
		local entry = Spawn(variety, CFrame.new(ground), raid)
		if entry then
			entry.Root.CFrame = StandingCFrame(entry, ground, -root.CFrame.LookVector)
			Unanchor(entry)
			Poof(ground + Vector3.new(0, 2, 0), variety.Glow, 20)
		end
	end
end)

print(("[ZombieRaid] ready: %d varieties, %d rigs, steal limit %d, max level %d"):format(#ZombieCatalog.VARIETIES, #Rigs:GetChildren(), ZombieCatalog.STEAL_LIMIT, ZombieCatalog.MAX_LEVEL))
