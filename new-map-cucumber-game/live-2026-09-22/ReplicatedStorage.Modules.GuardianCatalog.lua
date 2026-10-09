--[[
	GuardianCatalog  (ReplicatedStorage.Modules.GuardianCatalog)  2026-09-15

	Every number the guardian chase is tuned by, in one place, plus the per-guardian
	character: how fast it is, how far it reaches, which behaviours it can pick when it
	wakes, and which of its clips is its signature move.

	One guardian per biome.  The names match ServerStorage.Assets.Guardians and the
	CucumberSpawner ZONES list exactly.
]]
local M = {}

M.REMOTE = "Guardian"                -- ReplicatedStorage.Remotes.Guardian (RemoteEvent)
M.DEV_ATTRIBUTE = "GuardianDev"      -- workspace attribute: "wake:Spawn" / "sleep:Neon" / "stun:Farm"
M.FOLDER = "Guardians"               -- workspace.Guardians, where the live ones live

--.. THE FINISH LINE.  A biome is bigger than its cucumber field: this place has no
--.. workspace.Zones.ZoneParts slabs, so the fence falls back to workspace.SpawnArea.<n>
--.. (120 x 44) grown by this margin on every side.  It has to be at least the seat
--.. offset below, or a guardian is outside its own biome the moment it stands up - which
--.. is exactly what happened the first time: it woke, failed the fence test on the next
--.. tick, turned round and went straight back to sleep.
M.FENCE_MARGIN = 20
M.SEAT_BEHIND = 7                    -- studs behind the field's back edge that it sits
M.SEAT_MAX_RISE = 6                  -- if the ground behind the field is higher than this
M.SEAT_INSIDE = 6                    -- ... sit this far INSIDE the field's back edge instead

--..The chase...............................................................--
-- Each guardian has a SET WalkSpeed, and it climbs with the biome ladder - the Spawn
-- scarecrow is something a new player can outrun, the Neon sentinel is not. The `speed`
-- field on each guardian below IS that number in studs per second, and it is the one
-- table to tune. Nothing is solved from the player any more.
M.SPEED_MIN = 8
M.SPEED_MAX = 260                    -- a sanity rail, not a balance knob

--.. sprint bursts with rests, so the gap opens and closes instead of being a constant
M.BURST_SECONDS = {2.6, 4.2}         -- how long a sprint lasts
M.REST_SECONDS = {1.1, 1.9}          -- how long it eases off afterwards
M.REST_SPEED = 0.72                  -- speed multiplier while resting

--..Lurking.................................................................--
-- A guardian does not perch on its seat all day - it PROWLS its own biome, eyes still
-- dark, and drops back onto the seat now and then for a rest. Being already on its feet
-- is why a lurking guardian comes after you faster than one that has to stand up.
M.LURK_SPEED = 0.34                  -- fraction of its chase speed while prowling
M.LURK_PAUSE = {1.2, 3.0}            -- seconds it stands and looks around at each stop
M.LURK_REACH = 5                     -- close enough to a lurk point to call it arrived
M.LURK_TIMEOUT = 9                   -- give up on an unreachable point after this
M.LURK_INSET = 10                    -- keep lurk points this far inside the fence
M.REST_AFTER_STOPS = {3, 6}          -- stops before it goes back to the seat for a sit
M.REST_SECONDS = {6, 14}             -- how long it sits there
M.WAKE_FROM_LURK = 0.35              -- multiplier on the wake delay when already up

--..Waking...................................................................--
M.WAKE_DELAY = {0.9, 1.8}            -- seconds between the theft and the guardian standing
M.WAKE_CLIP_HOLD = 0.55              -- of the Wake clip before it starts moving
--.. IT CHASES YOU TO THE LOBBY. The biome edge is no longer the finish line: a guardian
--.. follows you out of its own biome and only breaks off when you are safely inside the
--.. lobby (or you drop the cucumber, or it catches you). FENCE_MARGIN now only keeps a
--.. LURKING guardian in its own patch. This is just a safety rail.
M.GIVE_UP_SECONDS = 120
M.RETARGET_SECONDS = 1.1             -- how often it re-picks the nearest carrier
--.. The chase ends at the LOBBY, so this has to be long enough to cross the map behind
--.. someone. At 150 a guardian gave up before the runner was halfway home.
M.LOSE_DISTANCE = 700                -- target this far away is abandoned

--..Catching.................................................................--
M.REACH = 7                          -- studs between hitboxes for the grab
M.CATCH_COOLDOWN = 1.6
M.KNOCKBACK_DISTANCE = 10            -- fallback only (ZombieRaidService's own number; its client does the flight)
M.KNOCKBACK_TIME = 0.35              -- fallback air time
--.. 2026-09-17 (user): the throw scales with YOUR Strength against the guardian's. A guardian is as
--.. strong as STRENGTH_MULT x its biome's lightest cucumber (CucumberLift.ZONE_BASE = the biome sign);
--.. at a quarter of that or less you fly KNOCKBACK_MAX studs, at four times or more only
--.. KNOCKBACK_MIN, log2-scaled in between (KNOCKBACK_LOG_LOW / _HIGH are log2 of those ratios).
--.. 2026-09-18 (user: "make the knockback higher, I want the player flung"): the AIR TIME rides the
--.. same curve (KNOCKBACK_TIME_MAX when weak .. KNOCKBACK_TIME_MIN when strong). The client's arc
--.. peaks at gravity x time^2 / 8: 0.9 s = ~20 studs up, 0.5 s = ~6 studs (0.35 s was ~3 studs).
M.STRENGTH_MULT = 5
M.KNOCKBACK_MIN = 6
M.KNOCKBACK_MAX = 30
M.KNOCKBACK_TIME_MIN = 0.5
M.KNOCKBACK_TIME_MAX = 0.9
M.KNOCKBACK_LOG_LOW = -2
M.KNOCKBACK_LOG_HIGH = 2

--..Heat.....................................................................--
-- Shared by every guardian on the server, +1 per successful theft, back to 0 at dawn.
M.HEAT_MAX = 8
M.HEAT_WAKE_FASTER = 0.09            -- fraction off the wake delay per heat point
M.HEAT_SPEED_BONUS = 0.022           -- fraction onto the speed margin per heat point
M.HEAT_REACH_BONUS = 0.22            -- studs onto the reach per heat point
M.HEAT_HIGH = 4                      -- at or above this it is a "high-heat" guardian
M.HEAT_ATTRIBUTE = "GuardianHeat"    -- mirrored onto workspace so clients/HUD can read it

--..The bat..................................................................--
M.STUN_HITS = 4                      -- bat blows to knock one out
M.STUN_SECONDS = 60
M.STUN_WINDOW = 6                    -- hits this far apart do not accumulate
M.STUN_DROP_MUTATION = {"ROYAL", "VOID", "PRISMATIC"}  -- beating a HIGH-HEAT one drops one of these

--.. A cucumber a guardian takes back is simply put back where it grows. No mark, no
--.. bonus, no mutation: the guardian standing over the field IS the protection.

--..Sleeping Z's.............................................................--
M.ZZZ_COUNT = 3                      -- how many z's are drifting at once
M.ZZZ_RISE = 2.6                     -- studs each one climbs before it fades out
M.ZZZ_PERIOD = 2.4                   -- seconds for one z to rise and fade
M.ZZZ_SIZE = 1.5                     -- stud height of a z at its biggest
M.ZZZ_DRIFT = 0.9                    -- studs it wanders sideways on the way up
M.ZZZ_HEAD_GAP = 1.6                 -- studs above the tallest part they start

--..Decoys...................................................................--
M.DECOY_RADIUS = 60                  -- it notices a cucumber dropped this close
M.DECOY_SECONDS = 7                  -- how long it will spend reclaiming one
M.DECOY_REACH = 6

--..Per guardian.............................................................--
-- speed     ITS WALKSPEED in studs per second, climbing the biome ladder 24 -> 96.
--           Spawn 24 is outrunnable by a fresh player; Neon 96 is not.
-- reach     multiplier on M.REACH (a crab's claw and a worm's jaw are not a scarecrow's arm)
-- turn      how sharply it corrects course (1 = instant, lower = wide turns)
-- behaviours which openings it may pick on waking
-- signature the clip name in the model's Anims folder
-- start     "Charge" clips play at the start of a chase instead of on contact
M.GUARDIANS = {
	Strawman  = {zone = "Spawn",      speed = 24, reach = 1.0,  turn = 0.9,
	             behaviours = {"charge", "cutoff"},             signature = "CrowShake",
	             shakeEvery = {4, 7}},                          -- the escape window
	Dune      = {zone = "Desert",     speed = 32, reach = 1.25, turn = 0.5,
	             behaviours = {"cutoff", "charge"},             signature = "DiveSurface",
	             surfacesAhead = true},
	Kabuto    = {zone = "Samurai",    speed = 40, reach = 1.2,  turn = 0.7,
	             behaviours = {"charge", "feint", "cutoff"},    signature = "Slam"},
	Brisket   = {zone = "Farm",       speed = 48, reach = 1.15, turn = 0.35,
	             behaviours = {"charge"},                       signature = "Charge",
	             start = true},                                 -- it IS a charge
	Frostbite = {zone = "Snow",       speed = 56, reach = 1.1,  turn = 0.75,
	             behaviours = {"charge", "feint"},              signature = "Throw",
	             slowStart = 1.6},                              -- seconds to reach full speed
	Pinch     = {zone = "Underwater", speed = 64, reach = 1.3,  turn = 0.85,
	             behaviours = {"cutoff", "charge"},             signature = "Snap"},
	Ember     = {zone = "Volcano",    speed = 72, reach = 1.15, turn = 0.6,
	             behaviours = {"charge"},                       signature = "Throw",
	             relentless = true},                            -- never rests
	Orbit     = {zone = "Narmek",     speed = 80, reach = 1.1,  turn = 1.0,
	             behaviours = {"cutoff", "feint"},              signature = "Blink",
	             blink = {studs = 26, every = {5, 8}}},
	Tick      = {zone = "Toyland",    speed = 88, reach = 1.0,  turn = 0.8,
	             behaviours = {"charge", "cutoff"},             signature = "Rewind",
	             windDown = {run = 6, rest = 2.2}},             -- sprints 6 s, then rewinds
	Scan      = {zone = "Neon",       speed = 96, reach = 1.1,  turn = 1.0,
	             behaviours = {"cutoff", "feint"},              signature = "Blink",
	             blink = {studs = 30, every = {4, 7}}},
}

M.ORDER = {"Strawman", "Dune", "Kabuto", "Brisket", "Frostbite",
           "Pinch", "Ember", "Orbit", "Tick", "Scan"}

--.. zone -> guardian name
M.BY_ZONE = {}
for name, d in pairs(M.GUARDIANS) do
	M.BY_ZONE[d.zone] = name
end

function M.Of(name)
	return M.GUARDIANS[name]
end

function M.ForZone(zone)
	local name = M.BY_ZONE[zone]
	return name, name and M.GUARDIANS[name] or nil
end

return M
