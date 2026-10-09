--[[
	CucumberStrength  (ModuleScript, ReplicatedStorage.Modules)
	Shared rules for "how strong do you have to be to pick this cucumber up" plus the
	timeline of the collect choreography. The strength numbers are PLACEHOLDERS
	(user, 2026-09-06: "just make up something random, don't worry about the economy").
	The requirement is HIDDEN (user, 2026-09-06): nothing on screen shows the number,
	you find out by trying.

	THE LADDER (2026-09-07, user: "there are certain ranges user strength should be in
	for each thing"). ratio = strength / required; BANDS run from their MinRatio up to
	the next band's, and inside a band every number interpolates from its bottom (first
	value) to its top (second value):
	  easy      ratio >= 1.5   "pull it and carry it easily": clean lift (no tug), full
	                           speed, never slips
	  sturdy    1.0 .. 1.5     "a lot of steps but falls occasionally": tug 2.5 -> 0.5 s,
	                           walk x0.8, slips after 5 -> 10 s of walking (+-FALL_JITTER)
	  shaky     0.5 .. 1.0     "some steps but falls a lot": tug 2.5 s, walk x0.6, slips
	                           after 1.5 -> 4 s of walking
	  hopeless  < 0.5          "barely a step without falling": tug 2.5 s, walk x0.5, slips
	                           0.2 -> 0.8 s after standing up ("too far from the user's
	                           strength: keep it as is")
	Below FLOOR_RATIO (1.0) the lift is a WEAK lift (WEAK_CAN_LIFT; false = the old "one
	short tug, then refused" rule) and the load cannot be placed on a plot until the lobby
	settles it. LOBBY = SAFE for EVERY band (user 2026-09-07: "once the player is past the
	biomes and in the lobby don't let cucumbers slip and fall"): CucumberCarry clears
	Heavy / Weak / Speed the moment the carrier's root is inside the lobby box.

	  Required(holder)             strength a field cucumber asks for (reads the
	                               StrengthRequired attribute CucumberCarry stamps, else
	                               computes it from Zone / TypeName / Golden / Sliced / Tree)
	  Ratio(strength, required)    strength / required (math.huge when nothing is required)
	  BandFor(ratio)               -> band, t (0 = bottom of the band, 1 = top)
	  Evaluate(strength, required) -> verdict, pullSeconds, band
	                               verdict = the band name ("easy" | "sturdy" | "shaky" |
	                               "hopeless") or "fail" (below FLOOR_RATIO with
	                               WEAK_CAN_LIFT off: one FAIL_TUG tug, then refused)
	  SpeedFor(ratio)              WalkSpeed multiplier while carrying (1 = full speed)
	  HoldFor(ratio, rng?)         seconds of walking after the pick-up before the load
	                               slips, +-FALL_JITTER; nil = never (easy)
	  FallDelay(ratio, rng?)       seconds after the GRAB before the slip (the rest of the
	                               pick-up clip + HoldFor); nil = never
	  RetryFor(ratio)              seconds before another try when a slip could not happen
	  Format(n)                    short number ("40", "2.5K", "1M") for debugging / toasts

	Timeline (seconds) shared by CucumberCarry (server) and CollectAnimClient:
	  APPROACH        the client walks up to the cucumber
	  + pull          CucumberStruggle loop (rounded to STRUGGLE_STEP)
	  + GRAB_T        into CucumberPickUp: the server swaps the field cucumber for
	                  the shoulder copy (the hands have lifted it to the chest)
	  + rest of PICKUP_LENGTH: the player stands up, then is free again (the hold starts)
	  Stumble (user 2026-09-07: "drop the cucumber first, then fall"): the load leaves the
	  shoulder AT ONCE -- it tumbles to the slip spot (FALL_LAND_AHEAD studs ahead of
	  where the player stands) over FALL_FLIGHT seconds, where the server has re-spawned
	  it as a field cucumber -- inside ANY biome; outside the biomes (the lobby, off the
	  map) it flies home to its own field instead (same rule as the DROP button).
	  FALL_AFTER_DROP seconds later the player trips: the CucumberFall clip from
	  FALL_CLIP_START (its carry-pose lead-in is skipped, the hands are empty by then) to
	  the end, so the fall lasts FALL_LENGTH - FALL_CLIP_START. No fling.
]]
local M = {}

--..Requirements (placeholders)..--
M.ZONE_BASE = {
	Spawn = 0, Desert = 10, Samurai = 30, Farm = 100, Snow = 300,
	Underwater = 1000, Volcano = 3000, Narmek = 10000, Toyland = 30000, Neon = 100000,
}
M.TYPE_FACTORS = {0.6, 0.8, 1, 1.25, 1.5} -- one per TypeName, picked by a stable hash
M.SLICED_FACTOR = 0.5 -- slices are light
M.TREE_FACTOR = 3 -- landmark trees are heavy
M.GOLDEN_FACTOR = 2
--.. a giant asks for its own size ladder in strength: required x SizeScale ^ this
--.. (1 = a COLOSSAL is 4x the pull of the same cucumber; 0 = giants weigh nothing extra)
M.SIZE_STRENGTH_POWER = 1
M.GOLDEN_MIN = 6 -- a golden cucumber always asks for a few bench reps, even in Spawn
M.TREE_MIN = 12

--..The ladder (top band first; ratio = strength / required)..--
--.. MinRatio  where the band starts (it runs up to the band above)
--.. Pull      {bottom, top} seconds of tugging before the lift (rounded to STRUGGLE_STEP)
--.. Speed     WalkSpeed multiplier while carrying (CarryingCucumberSpeed attribute)
--.. Hold      {bottom, top} seconds of walking after the pick-up before the load slips,
--..           +-FALL_JITTER; nil = never slips
--.. Retry     seconds before another slip attempt when one could not happen (default FALL_RETRY)
--.. Weak      the "slipped right off" toast + hint (CarryingCucumberWeak attribute)
M.BANDS = {
	{Name = "easy", MinRatio = 1.5, Pull = {0, 0}, Speed = 1, Hold = nil},
	{Name = "sturdy", MinRatio = 1.0, Pull = {1, 0.5}, Speed = 0.8, Hold = {10, 16}},
	{Name = "shaky", MinRatio = 0.5, Pull = {1, 1}, Speed = 0.6, Hold = {6, 10}},
	{Name = "hopeless", MinRatio = 0, Pull = {1, 1}, Speed = 0.5, Hold = {3.5, 5}, Retry = 0.5, Weak = true},
}
M.EASY_RATIO = 1.5 -- = BANDS[1].MinRatio: this much spare strength never slips
M.FLOOR_RATIO = 1.0 -- the requirement itself: below it the lift is WEAK (no plot placement until the lobby settles it)
M.WEAK_CAN_LIFT = true -- false = below FLOOR_RATIO: one FAIL_TUG tug, then "Too heavy!" (the old rule)
M.STRUGGLE_STEP = 0.5 -- pull times round to this (half loops of the 1 s struggle clip)
M.FALL_JITTER = 0 -- +-25 % on every hold so it never feels like a timer
M.FALL_RETRY = 2 -- seconds before another try when a slip could not happen (busy, seated, fields closed, field full)

--..Timeline..--
M.APPROACH = 0.6
M.PICKUP_LENGTH = 1.4
M.GRAB_T = 1.0
M.STRUGGLE_LOOP = 1.0 -- length of the CucumberStruggle clip (the client's rocking visual keys off it)
M.FAIL_TUG = 1.0
M.FALL_LENGTH = 2.4 -- CucumberFall clip (full length)
M.FALL_CLIP_START = 0.233 -- seconds into the clip the trip starts (the carry-pose lead-in before it is skipped: the load is already gone)
M.FALL_AFTER_DROP = 0.4 -- seconds between the load leaving the shoulder and the trip (the tumble takes FALL_FLIGHT)
M.FALL_FLIGHT = 0.5 -- seconds the dropped load tumbles to the ground
M.FALL_LAND_AHEAD = 1.5 -- studs ahead of the player: where the slipped load lands

M.PERFECT_MIN = .08
M.PERFECT_MAX = .16
M.PERFECT_RECOVERY_FRACTION = .85
M.CARRY_MODES = {
 Normal = {Speed=1, Drain=1},
 Careful = {Speed=.8, Drain=.6},
 Sprint = {Speed=1.3, Drain=1.55},
}
M.RECOVERY_WINDOW = 0.3 -- final 30% of grip
M.RECOVERY_FRACTION = 0.5 -- regain half of the original hold, once per carry
-- Display tiers share the server's strength-ratio bands. Impossible remains
-- attemptable: it describes the toughest carry, rather than locking interaction.
M.BAND_LABELS = {
 easy = {Text = "Easy", Color = Color3.fromRGB(130, 255, 80)},
 sturdy = {Text = "Medium", Color = Color3.fromRGB(255, 222, 65)},
 shaky = {Text = "Hard", Color = Color3.fromRGB(255, 146, 55)},
 hopeless = {Text = "Impossible", Color = Color3.fromRGB(255, 79, 105)},
}
local function hash(s)
	local h = 5381
	for i = 1, #s do
		h = (h * 33 + s:byte(i)) % 4294967296
	end
	return h
end

--.. two significant digits: 37.5 -> 38, 1875 -> 1900
local function nice(n)
	if n <= 0 then return 0 end
	local mag = 10 ^ (math.floor(math.log10(n)) - 1)
	return math.floor(n / mag + 0.5) * mag
end

local function lerp(pair, t)
	return pair[1] + (pair[2] - pair[1]) * t
end

local function jitter(rng)
	local r = rng and rng:NextNumber(-1, 1) or (math.random() * 2 - 1)
	return 1 + M.FALL_JITTER * r
end

function M.IsTree(typeName)
	local s = string.lower(tostring(typeName or ""))
	return s:find("tree", 1, true) ~= nil or s:find("grove", 1, true) ~= nil or s:find("palm", 1, true) ~= nil
end

function M.Compute(zone, typeName, golden, sliced, tree, sizeScale)
	local base = M.ZONE_BASE[zone] or 0
	local factor = M.TYPE_FACTORS[hash(tostring(typeName)) % #M.TYPE_FACTORS + 1]
	if sliced then factor = M.SLICED_FACTOR end
	if tree then factor = M.TREE_FACTOR end
	local required = base * factor
	if golden then required = math.max(required * M.GOLDEN_FACTOR, M.GOLDEN_MIN) end
	if tree then required = math.max(required, M.TREE_MIN) end
	--.. giants (CucumberMutations.SIZES) are as heavy as they look
	sizeScale = tonumber(sizeScale) or 1
	if sizeScale > 1 and M.SIZE_STRENGTH_POWER ~= 0 then required *= sizeScale ^ M.SIZE_STRENGTH_POWER end
	return nice(required)
end

function M.Required(holder)
	local stamped = holder:GetAttribute("StrengthRequired")
	if type(stamped) == "number" then return stamped end
	local typeName = holder:GetAttribute("TypeName") or holder.Name
	local tree = holder:GetAttribute("Tree") == true or M.IsTree(typeName)
	return M.Compute(holder:GetAttribute("Zone") or "Spawn", typeName, holder:GetAttribute("Golden") == true, holder:GetAttribute("Sliced") == true, tree, holder:GetAttribute("SizeScale"))
end

function M.Ratio(strength, required)
	strength = tonumber(strength) or 0
	required = tonumber(required) or 0
	if required <= 0 then return math.huge end
	return strength / required
end

--.. the band a ratio falls in and where inside it (0 = bottom, 1 = top; the top band is
--.. always 1). A missing ratio counts as "nothing required" = the top band.
function M.BandFor(ratio)
	ratio = tonumber(ratio) or math.huge
	local bands = M.BANDS
	for i, band in ipairs(bands) do
		if ratio >= band.MinRatio then
			local top = i > 1 and bands[i - 1].MinRatio or nil
			local t = 1
			if top and top > band.MinRatio then
				t = math.clamp((ratio - band.MinRatio) / (top - band.MinRatio), 0, 1)
			end
			return band, t
		end
	end
	return bands[#bands], 0
end

function M.Evaluate(strength, required)
	local ratio = M.Ratio(strength, required)
	local band, t = M.BandFor(ratio)
	if ratio < M.FLOOR_RATIO and not M.WEAK_CAN_LIFT then return "fail", 0, band end
	local seconds = lerp(band.Pull, t)
	if seconds > 0 then
		--.. half loops of the struggle clip read best
		seconds = math.max(M.STRUGGLE_STEP, math.floor(seconds / M.STRUGGLE_STEP + 0.5) * M.STRUGGLE_STEP)
	end
	return band.Name, seconds, band
end

function M.SpeedFor(ratio)
	local band = M.BandFor(ratio)
	return band.Speed or 1
end

--.. seconds of walking after the pick-up before the load slips (nil = never)
function M.HoldFor(ratio, rng)
	local band, t = M.BandFor(ratio)
	if not band.Hold then return nil end
	return math.max(0.05, lerp(band.Hold, t) * jitter(rng))
end

--.. seconds after the GRAB (where the server starts the slip timer) before the load
--.. slips: the rest of the pick-up clip, then HoldFor (nil = never)
function M.FallDelay(ratio, rng)
	local hold = M.HoldFor(ratio, rng)
	if not hold then return nil end
	return (M.PICKUP_LENGTH - M.GRAB_T) + hold
end

function M.RetryFor(ratio)
	local band = M.BandFor(ratio)
	return band.Retry or M.FALL_RETRY
end

function M.Format(n)
	n = tonumber(n) or 0
	if n >= 1e9 then return string.format("%.3gB", n / 1e9) end
	if n >= 1e6 then return string.format("%.3gM", n / 1e6) end
	if n >= 1e3 then return string.format("%.3gK", n / 1e3) end
	return tostring(math.floor(n + 0.5))
end

-- Preview the next easier carry tier without changing the pickup verdict.
function M.NextTier(strength, required)
 local ratio=M.Ratio(strength,required)
 local band=M.BandFor(ratio)
 for i,b in ipairs(M.BANDS) do
  if b==band and i>1 then
   local nextBand=M.BANDS[i-1]
   local target=math.ceil(required*nextBand.MinRatio)
   return M.BAND_LABELS[nextBand.Name].Text,math.max(0,target-strength),target
  end
 end
 return nil
end
return M

