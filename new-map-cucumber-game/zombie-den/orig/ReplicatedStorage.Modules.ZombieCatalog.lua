--[[
	ZombieCatalog  (ModuleScript, ReplicatedStorage.Modules)  2026-09-10
	Everything the zombie raid shares between server and client: the roster of zombie
	varieties, the threat algorithm that turns a player's cucumbers into a raid level, and
	the wave composition for a level.

	  ZombieCatalog.ThreatOf(cucumbers, income) -> score   cucumbers = list of tables / instances
	                                                        with Zone / Mutations / Material / Golden /
	                                                        SizeTier; income = Cash per second
	  ZombieCatalog.LevelOf(score)               -> 1 .. MAX_LEVEL
	  ZombieCatalog.WaveFor(level, rng?)         -> ordered list of variety tables (hardest first)
	  ZombieCatalog.Variety(name)                -> the variety table
	  ZombieCatalog.BuildHealth(buildKey)        -> hit points of a placed build zombies bash

	THREAT (2026-09-23 economy): score = the base's VALUE = sum over placed cucumbers of CucumberValues
	reward x 8^(biome-1) x the mutation multiplier capped at THREAT_MULT_CAP (12). Income never counts.
	level = 1 + floor(log8(score / LEVEL_SCALE)), LEVEL_SCALE 128 = 16 typical cucumbers or two trees of a
	biome, so the level is the biome the bulk of the base comes from: a Spawn base is level 1, a Desert
	base 2 ... a Neon base 10. One tree of the next biome does not bump it, sixteen typicals do.

	WAVES: count = BASE_COUNT + PER_LEVEL x level (rounded, MIN_COUNT .. MAX_COUNT) = 4 .. 16. The pool is
	every variety whose MinLevel <= level, weighted by Weight x (1 + HARD_BIAS x MinLevel / level), so the
	hardest varieties available dominate; the single hardest variety unlocked is always in the wave.
	Hit points = variety.Health (a ROLE number: shambler ~60, runner ~40, brute 200-300, titan 600) x
	HpMult(level) (x3 per level to 2,187 at 8, then 3,281 / 4,921): HealthOf(variety, level).
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CucumberValues = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CucumberValues"))
local CucumberMutations = require(ReplicatedStorage.Modules:WaitForChild("CucumberMutations"))

local M = {}

M.STEAL_LIMIT = 3          -- cucumbers stolen before "The zombies win."
M.MAX_LEVEL = 10           -- the raid never gets harder than this
--.. 2026-09-23 (economy): see CucumberThreat / LevelOf / HpMult below
M.THREAT_MULT_CAP = 12   -- a cucumber's mutation multiplier counts at most this much toward the threat
M.LEVEL_BASE = 8         -- one level per x8 of base value = one biome
M.LEVEL_SCALE = 128      -- value of 16 typical cucumbers (reward 8) or two trees (64) of a biome = the level-2 threshold
M.BASE_COUNT = 3         -- wave = round(BASE_COUNT + PER_LEVEL x level): 4, 6, 7, 8, 10, 11, 12, 13, 15, 16
M.PER_LEVEL = 1.3
M.MIN_COUNT = 4
M.MAX_COUNT = 16
M.HARD_BIAS = 2
M.HP_STEP = 3            -- zombie hit points x3 per level (1 .. 2,187 at level 8)
M.HP_MULT_LATE = {[9] = 3281, [10] = 4921} -- levels 9-10 add bodies and specials, not another x3
M.ALIVE_CAP = 48         -- zombies alive per server; the door holds further rows until some die

M.ZONES = {"Spawn", "Desert", "Samurai", "Farm", "Snow", "Underwater", "Volcano", "Narmek", "Toyland", "Neon"}
M.DESIGNS = {"Shambler", "Runner", "Brute"} -- ServerStorage.Assets.Zombies/<Design>
M.ANIMATIONS = { -- the Roblox zombie animation pack (R15), free to use
	Walk = "rbxassetid://616168032",
	Run = "rbxassetid://616163682",
	Idle = "rbxassetid://616158929",
	Idle2 = "rbxassetid://616160636",
	Swing = "rbxassetid://522635514", -- the R15 tool slash: the swing a hostile zombie takes at a player in its way (2026-09-12)
}
M.FOLDER = "Zombies" -- workspace.Zombies holds every live zombie
M.TAG = "Zombie"
M.REMOTE = "ZombieRaid" -- ReplicatedStorage.Remotes.ZombieRaid (RemoteEvent, server -> client)
M.API = "ZombieAPI" -- ServerStorage.ZombieAPI (BindableFunctions Damage / Zombies / IsZombie)

--.. how much a placed build takes before zombies smash through it (BuildKey -> hit points)
--.. 2026-09-23 (economy): x3 per unlock tier (walls from a 150 / 400 / 400 / 500 base, defences 300 x 3^(tier-1));
--.. a zombie's bash climbs x3 per raid level too (ZombieRaidService), so a same-tier build takes ~12-20 swings
M.BUILD_HEALTH = {WoodenWall = 150, StoneWall = 1200, IronWall = 10800, BarbedStoneWall = 365000,
	SpikeTrap = 300, BoostPad = 300, Catapult = 900, Turret = 2700, LaserGate = 8100, FreezeTower = 24300,
	TeslaCoil = 72900, Mortar = 218700, Minigun = 656100}
M.BUILD_HEALTH_DEFAULT = 150
M.BARBED_FRACTION = 0.10 -- a zombie bashing a BarbedStoneWall loses this share of its max hit points per swing

--.. special kinds (2026-09-11): a variety may carry
--..   Shadow = true    it phases: SHADOW_VISIBLE s solid, then every BasePart at SHADOW_TRANSPARENCY for
--..                    SHADOW_HIDDEN s (defences do not see it, nothing can damage it), and so on;
--..                    carrying a cucumber keeps it solid
--..   Health = 1       the sprinters: any hit kills, but they are the fastest things on the map
--..   Grapple = true   within GrappleRange of its target it fires a hook, reels the cucumber in over
--..                    GRAPPLE_PULL s, then runs off with it at GRAPPLE_CARRY_SPEED x its speed
M.SHADOW_VISIBLE = 2.5
M.SHADOW_HIDDEN = 5
M.SHADOW_TRANSPARENCY = 0.7
M.GRAPPLE_RANGE = 24
M.GRAPPLE_HOOK = 0.25       -- seconds the hook flies before the pull
M.GRAPPLE_PULL = 0.6        -- seconds the cucumber slides to the zombie
M.GRAPPLE_CARRY_SPEED = 1.15 -- carry walk multiplier for grapplers (others: CARRY_SPEED 0.85)
--..   Digger = true    with a target at least DIG_RANGE_MIN away it burrows: sinks DIG_DEPTH in DIG_DIVE s,
--..                    travels underground at DIG_SPEED (walls, traps and turrets cannot touch it - it is
--..                    left out of the zombie list), surfaces beside the cucumber and grabs it; once per
--..                    DIG_COOLDOWN
--..   Split = {Variety, Count}   a fat slow one that bursts into Count small fast ones (a MinLevel-99
--..                    variety, never rolled on its own) when it dies
M.DIG_RANGE_MIN = 12
M.DIG_DEPTH = 6
M.DIG_SPEED = 18
M.DIG_DIVE = 0.6
M.DIG_COOLDOWN = 8

--.. every zombie variety, weakest first. Health = a ROLE number (2026-09-23: HealthOf scales it x3 per level). Design = which rig in ServerStorage.Assets.Zombies; MinLevel = the
--.. raid level that unlocks it; colours retint the rig (Skin = head/arms/hands + parts tagged Skin, Cloth =
--.. torso/legs, Glow = eyes / cracks / mohawk / lights); Scale = Model:ScaleTo
local function rgb(r, g, b) return Color3.fromRGB(r, g, b) end
M.VARIETIES = {
	{Name = "Rotten Shambler", Design = "Shambler", MinLevel = 1, Health = 60, Speed = 8, Scale = 1, Weight = 10,
		Skin = rgb(96, 150, 70), Cloth = rgb(70, 52, 40), Glow = rgb(190, 255, 90)},
	{Name = "Scrawny Runner", Design = "Runner", MinLevel = 2, Health = 40, Speed = 13, Scale = 0.9, Weight = 8,
		Skin = rgb(120, 140, 110), Cloth = rgb(60, 60, 68), Glow = rgb(255, 90, 60)},
	{Name = "Plague Shambler", Design = "Shambler", MinLevel = 3, Health = 80, Speed = 9, Scale = 1.05, Weight = 8,
		Skin = rgb(150, 170, 60), Cloth = rgb(56, 70, 40), Glow = rgb(230, 255, 60)},
	{Name = "Blitz Runner", Design = "Runner", MinLevel = 3, Health = 1, Speed = 26, Scale = 0.8, Weight = 6,
		Skin = rgb(255, 240, 120), Cloth = rgb(90, 80, 30), Glow = rgb(255, 255, 160)},
	{Name = "Bloated Brute", Design = "Brute", MinLevel = 3, Health = 200, Speed = 7, Scale = 1.35, Weight = 5,
		Skin = rgb(140, 175, 120), Cloth = rgb(64, 48, 36), Glow = rgb(170, 255, 120)},
	{Name = "Feral Runner", Design = "Runner", MinLevel = 4, Health = 50, Speed = 15, Scale = 0.95, Weight = 7,
		Skin = rgb(140, 92, 70), Cloth = rgb(50, 36, 30), Glow = rgb(255, 60, 40)},
	{Name = "Shadow Stalker", Design = "Shambler", MinLevel = 4, Health = 70, Speed = 11, Scale = 1, Weight = 6, Shadow = true,
		Skin = rgb(40, 40, 58), Cloth = rgb(18, 18, 30), Glow = rgb(170, 90, 255)},
	{Name = "Mole Digger", Design = "Shambler", MinLevel = 4, Health = 80, Speed = 9, Scale = 0.95, Weight = 6, Digger = true,
		Skin = rgb(120, 90, 60), Cloth = rgb(60, 40, 25), Glow = rgb(255, 200, 90)},
	{Name = "Iron Brute", Design = "Brute", MinLevel = 5, Health = 250, Speed = 7.5, Scale = 1.4, Weight = 5,
		Skin = rgb(120, 128, 140), Cloth = rgb(48, 50, 58), Glow = rgb(120, 200, 255)},
	{Name = "Hook Lurker", Design = "Runner", MinLevel = 5, Health = 100, Speed = 12, Scale = 1.05, Weight = 5, Grapple = true, GrappleRange = 24,
		Skin = rgb(70, 120, 110), Cloth = rgb(30, 50, 45), Glow = rgb(255, 150, 40)},
	{Name = "Bloated Splitter", Design = "Brute", MinLevel = 5, Health = 180, Speed = 6.5, Scale = 1.35, Weight = 5, Split = {Variety = "Spawnling", Count = 3},
		Skin = rgb(150, 190, 90), Cloth = rgb(70, 80, 40), Glow = rgb(200, 255, 120)},
	{Name = "Toxic Shambler", Design = "Shambler", MinLevel = 6, Health = 90, Speed = 10, Scale = 1.1, Weight = 7,
		Skin = rgb(70, 200, 90), Cloth = rgb(30, 60, 40), Glow = rgb(90, 255, 90)},
	{Name = "Blood Runner", Design = "Runner", MinLevel = 7, Health = 50, Speed = 17, Scale = 1, Weight = 6,
		Skin = rgb(110, 30, 30), Cloth = rgb(40, 18, 18), Glow = rgb(255, 40, 40)},
	{Name = "Lava Brute", Design = "Brute", MinLevel = 8, Health = 300, Speed = 8, Scale = 1.5, Weight = 5,
		Skin = rgb(50, 40, 40), Cloth = rgb(30, 24, 24), Glow = rgb(255, 140, 30)},
	{Name = "Lightning Runner", Design = "Runner", MinLevel = 8, Health = 1, Speed = 32, Scale = 0.8, Weight = 5,
		Skin = rgb(255, 255, 255), Cloth = rgb(60, 60, 90), Glow = rgb(120, 220, 255)},
	{Name = "Void Wraith", Design = "Shambler", MinLevel = 8, Health = 90, Speed = 12, Scale = 1.1, Weight = 5, Shadow = true,
		Skin = rgb(20, 10, 30), Cloth = rgb(10, 6, 16), Glow = rgb(255, 60, 220)},
	{Name = "Tunnel Fiend", Design = "Shambler", MinLevel = 8, Health = 100, Speed = 11, Scale = 1.05, Weight = 5, Digger = true,
		Skin = rgb(80, 50, 40), Cloth = rgb(40, 25, 20), Glow = rgb(255, 120, 60)},
	{Name = "Void Shambler", Design = "Shambler", MinLevel = 9, Health = 100, Speed = 11, Scale = 1.15, Weight = 6,
		Skin = rgb(60, 40, 90), Cloth = rgb(24, 16, 40), Glow = rgb(200, 80, 255)},
	{Name = "Chain Reaper", Design = "Brute", MinLevel = 9, Health = 220, Speed = 13, Scale = 1.3, Weight = 4, Grapple = true, GrappleRange = 32,
		Skin = rgb(60, 70, 80), Cloth = rgb(30, 30, 36), Glow = rgb(255, 120, 40)},
	{Name = "Gorged Splitter", Design = "Brute", MinLevel = 9, Health = 250, Speed = 7, Scale = 1.5, Weight = 4, Split = {Variety = "Goreling", Count = 3},
		Skin = rgb(120, 60, 70), Cloth = rgb(60, 30, 35), Glow = rgb(255, 80, 120)},
	{Name = "Neon Runner", Design = "Runner", MinLevel = 10, Health = 60, Speed = 19, Scale = 1, Weight = 5,
		Skin = rgb(40, 40, 60), Cloth = rgb(20, 20, 36), Glow = rgb(60, 255, 255)},
	{Name = "Titan Brute", Design = "Brute", MinLevel = 10, Health = 600, Speed = 8.5, Scale = 1.7, Weight = 4,
		Skin = rgb(90, 70, 40), Cloth = rgb(40, 32, 20), Glow = rgb(255, 220, 80)},
	--.. the splitters' children: never rolled on their own (MinLevel above the cap, Weight 0)
	{Name = "Spawnling", Design = "Runner", MinLevel = 99, Health = 20, Speed = 18, Scale = 0.6, Weight = 0,
		Skin = rgb(150, 190, 90), Cloth = rgb(70, 80, 40), Glow = rgb(200, 255, 120)},
	{Name = "Goreling", Design = "Runner", MinLevel = 99, Health = 30, Speed = 20, Scale = 0.65, Weight = 0,
		Skin = rgb(120, 60, 70), Cloth = rgb(60, 30, 35), Glow = rgb(255, 80, 120)},
}

local ByName = {}
for _, v in ipairs(M.VARIETIES) do ByName[v.Name] = v end

function M.Variety(name)
	return ByName[name]
end

--..Threat..--
local function attr(entry, key)
	if typeof(entry) == "Instance" then return entry:GetAttribute(key) end
	return type(entry) == "table" and entry[key] or nil
end

--.. 2026-09-23 (economy): threat = the VALUE of the base. One cucumber counts its CucumberValues break value
--.. (reward x 8^(biome-1)) times its mutation multiplier capped at THREAT_MULT_CAP, so a Golden tree of the next
--.. biome is a real step up but one Prismatic does not drag a Spawn base to level 4.
function M.CucumberThreat(entry)
	local zone = attr(entry, "Zone") or "Spawn"
	local typeName = attr(entry, "TypeName") or (typeof(entry) == "Instance" and entry.Name) or nil
	local material = attr(entry, "Material")
	if not material and attr(entry, "Golden") == true then material = "Golden" end
	local base = CucumberValues.RewardOf(zone, typeName) * CucumberValues.ZONE_VALUE_STEP ^ (CucumberValues.TierOf(zone) - 1)
	local mult = CucumberMutations.TotalMult(material, attr(entry, "Mutations"), attr(entry, "SizeTier"))
	return base * math.min(M.THREAT_MULT_CAP, math.max(1, tonumber(mult) or 1))
end

--.. income is accepted for the callers' sake but no longer counts: pets, potions and rates never raise the threat
function M.ThreatOf(cucumbers, income)
	local score = 0
	for _, entry in ipairs(cucumbers or {}) do score += M.CucumberThreat(entry) end
	return score
end

--.. level = 1 + floor(log8(score / LEVEL_SCALE)): the biome the bulk of the base comes from
function M.LevelOf(score)
	score = math.max(0, tonumber(score) or 0)
	if score < M.LEVEL_SCALE then return 1 end
	local level = 1 + math.floor(math.log(score / M.LEVEL_SCALE, M.LEVEL_BASE) + 1e-9)
	return math.clamp(level, 1, M.MAX_LEVEL)
end

--.. hit-point multiplier of a raid level: x HP_STEP per level to 8, then the HP_MULT_LATE table
function M.HpMult(level)
	level = math.clamp(math.floor(tonumber(level) or 1), 1, M.MAX_LEVEL)
	return M.HP_MULT_LATE[level] or M.HP_STEP ^ (level - 1)
end

--.. a variety's hit points at a raid level; the one-hit sprinters (Health 1) stay one-hit
function M.HealthOf(variety, level)
	local base = tonumber(variety and variety.Health) or 60
	if base <= 1 then return 1 end
	return math.max(1, math.floor(base * M.HpMult(level) + 0.5))
end

--..Waves..--
function M.CountFor(level)
	return math.clamp(math.round(M.BASE_COUNT + M.PER_LEVEL * level), M.MIN_COUNT, M.MAX_COUNT)
end

function M.PoolFor(level)
	local pool = {}
	for _, v in ipairs(M.VARIETIES) do
		if v.MinLevel <= level then table.insert(pool, v) end
	end
	return pool
end

function M.WaveFor(level, rng)
	level = math.clamp(math.floor(tonumber(level) or 1), 1, M.MAX_LEVEL)
	rng = rng or Random.new()
	local pool = M.PoolFor(level)
	local wave = {}
	--.. the hardest thing unlocked always shows up
	local hardest = pool[#pool]
	table.insert(wave, hardest)
	local total = 0
	local weights = {}
	for i, v in ipairs(pool) do
		weights[i] = v.Weight * (1 + M.HARD_BIAS * v.MinLevel / level)
		total += weights[i]
	end
	for _ = 2, M.CountFor(level) do
		local roll = rng:NextNumber() * total
		local pick = pool[#pool]
		for i, v in ipairs(pool) do
			roll -= weights[i]
			if roll <= 0 then pick = v break end
		end
		table.insert(wave, pick)
	end
	table.sort(wave, function(a, b)
		if a.MinLevel ~= b.MinLevel then return a.MinLevel > b.MinLevel end
		return a.Name < b.Name
	end)
	return wave
end

function M.BuildHealth(buildKey)
	return M.BUILD_HEALTH[buildKey] or M.BUILD_HEALTH_DEFAULT
end

return M
