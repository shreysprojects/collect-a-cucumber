--[[
	CucumberLift  (ModuleScript, ReplicatedStorage.Modules)
	The click-to-lift pickup (2026-09-16, user: "delete the current cucumber pickup system
	entirely; a long bar with a strength icon that drifts left; every click pushes it right;
	all the way right = lifted, all the way left = the pickup fails; based on strength -- with
	lots of strength 2-3 clicks, without enough the icon always wins whatever your clicks per
	second; assign each cucumber a weight in kg and show the kg instead of a requirement").
	2026-09-17 (user): "even if the strength is slightly below the requirement the user still has
	a chance ... if he is within a certain range or really close he should be able to get it if he
	clicks fast enough" + "follow the signs in each biome that show the strength requirement".

	WEIGHTS  every field cucumber has a weight in kg (attribute WeightKg, stamped by
	CucumberCarry). 1 kg asks for 1 Strength: ratio = Strength / kg decides the lift.
	  kg = ZONE_BASE[zone]                        the lightest cucumber of the biome (the 3-reward slice)
	                                              = the "recommended" Strength on the biome's entrance
	                                              sign (Map.Biomes decor: Desert 300, Samurai 2K, Farm 15K,
	                                              Snow 400K, Underwater 6M, Volcano 40M, Narmek 750M,
	                                              Toyland 14B, Neon 1T; Spawn has no sign: 3 kg)
	       x (reward / 3) ^ REWARD_POWER          heavier types of the same biome (CucumberValues.REWARDS:
	                                              3 .. 360 -> x1 .. x6.8, so a biome's tree stays under
	                                              the NEXT biome's sign)
	       x MATERIAL_FACTOR (Golden x2, Diamond x4) x MUTATION_FACTOR per mutation
	       x SizeScale ^ SIZE_POWER               giants (CucumberMutations.SIZES)
	  rounded to two significant digits. Spawn: slice 3 kg, Cucumber 4.4 kg, Slice Stack 6.4 kg,
	  Vined 9.7 kg, Flowered 14 kg, Cucumber Tree 20 kg; Desert slice 300 kg .. Sandstone Tree 2K.

	THE BAR  progress p in 0..1, the icon starts at START. Every click adds Gain, the icon
	drifts left Drift per second. p >= 1 = lifted, p <= 0 = "Too heavy".
	  ONE CURVE over the strength ratio (2026-09-17, user: "more ranges of strength that do more ...
	  an algorithm to correlate strength with all this" + "vary the clicks needed and the fall-back
	  speed with strength, use formulas"). Two ways to draw it, CURVE_MODE picks one:
	    "formula" (live)  Clicks = ClicksAtSign x ratio ^ -ClickPower  (11 at the sign, never under MIN_CLICKS)
	                      Drift  = DriftAtSign x ratio ^ -DriftPower   (0.18 bar/s at the sign; x2 per halving)
	    "table"           CURVE rows {Ratio, Clicks, Cps} interpolated by log2(ratio) (shape any band by hand)
	    Gain = (1 - START) / Clicks; the click rate that only HOLDS the icon = Drift / Gain; clicking at
	    c per second wins in Clicks / (c - hold) seconds, slower than the hold loses.
	  formula: ratio 3.2 and up MIN_CLICKS = 4 clicks (2026-09-18, user: "1 click instant pick up is too
	  easy") .. 2 six .. 1.5 eight .. 1 = AT the sign: 11 clicks holding 3 cps (5 cps ~5 s) .. 0.9 hold 3.7 (click fast: 6 cps ~4 s) .. 0.8 hold 4.6 (click a LOT: 7 cps
	  ~4 s) .. 0.7 hold 5.9 (a masher: 8 cps ~5 s) .. 0.6 hold 7.9 (10 cps) .. 0.5 hold 11 (autoclicker,
	  15 cps) .. MIN_RATIO 0.4: 25 clicks holding 17 (MAX_CPS 20 wins in ~4 s).
	  ratio < MIN_RATIO  HOPELESS: Gain shrinks with the ratio, Drift 0.55 .. 1.15 per second: even
	                  MAX_CPS clicks per second never keep up -- the icon always wins.
	  The icon holds still for GRACE seconds after the bar appears (the camera pan and a
	  breath) before it starts drifting; clicks count from the first frame.
	  The server checks a "lifted" claim: Feasible (ratio >= MIN_RATIO) and at least
	  MinClicks / MAX_CPS seconds after the bar appeared (the bar itself runs on the client).
	  CucumberAdventure's carry traits (Slippery / Bouncy) play no part (user 2026-09-16).

	  Compute(zone, typeName, material, mutations, sizeScale) -> kg
	  Of(holder)                       -> kg (WeightKg attribute, else computed from Zone / TypeName /
	                                      Material / Golden / Mutations / SizeScale)
	  Format(kg)                       -> "12 kg", "1.2K kg", "1T kg"
	  Shown(kg, zone, typeName)        -> the weight the PLAYER sees (lower, off-curve, never the Strength number)
	  ShownOf(holder)                  -> ShownKg attribute, else Shown(Of(holder), ...)
	  Ratio(strength, kg)              -> strength / kg
	  WeightScale(zone, typeName, material, mutations) -> visual model scale from the kg (1 .. ~1.3; giants excluded)
	  Curve(ratio)                     -> Clicks, Cps (CURVE_MODE: CurveFormula or CurveTable)
	  Params(ratio)                    -> {Start, Gain, Drift, Clicks, Cps, MinClicks, MinTime, Feasible, Band}
	  SpeedFor(ratio)                  -> WalkSpeed multiplier while carrying (1 at the weight .. CARRY_SPEED_MIN)
	  CpsToWin(ratio)                  -> clicks per second needed to hold the icon still (math.huge = never)
	  TimeToWin(ratio, cps)            -> seconds a steady cps takes to fill the bar (math.huge = never / times out)
	  Difficulty(ratio)                -> name, colour, text, row (DIFFICULTY: "trivial" .. "impossible";
	                                      row.Hint = the prompt's nudge, row.Bar = the bar's shout)

	TIMELINE (seconds; CucumberCarry + CucumberLiftClient)
	  APPROACH   the client walks up to the cucumber before the bar appears
	  LIFT_LEN   the part of the CucumberLift clip the bar scrubs (0 = hands on the ground, 1 = chest)
	  HOIST_LEN  the rest of the clip, played once after the win (load goes onto the shoulder);
	             the server swaps the field cucumber for the shoulder copy at its end
	  FAIL_RELAX the pose and the cucumber sink back after a fail
	  MAX_TIME   a bar older than this fails on its own
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Modules = ReplicatedStorage:WaitForChild("Modules")
local CucumberValues = require(Modules:WaitForChild("CucumberValues"))
local NumberAbbrev = require(Modules:WaitForChild("NumberAbbrev"))

local M = {}

--..Weights..--
M.ZONE_BASE = { -- kg of the lightest (3-reward) cucumber per biome = the biome sign's "recommended" Strength
	Spawn = 3, Desert = 300, Samurai = 3000, Farm = 30000, Snow = 300000,
	Underwater = 3e6, Volcano = 3e7, Narmek = 3e8, Toyland = 3e9, Neon = 3e10, -- 2026-09-23 economy: x10 per biome (was 300 / 2K / 15K / 400K / 6M / 40M / 750M / 14B / 1T)
}
M.REWARD_BASE = 3 -- the reward of the lightest type (CucumberValues.REWARDS slices)
M.REWARD_POWER = 0.4 -- (reward / 3) ^ this: the 360-reward tree is x6.8 the slice, under the smallest sign-to-sign step (x6.7)
M.MATERIAL_FACTOR = {Golden = 2, Diamond = 4}
M.MUTATION_FACTOR = 1.5 -- per mutation ("NEON,FROZEN" = x2.25)
M.MUTATION_MAX = 4 -- mutations counted at most
M.SIZE_POWER = 1.8 -- giants: kg x SizeScale ^ this (x2 -> 3.5, x3 -> 7.2, x4 -> 12; was 1.5 = 2.8 / 5.2 / 8 until 2026-09-17, user: "mutated size cucumbers' kg a bit higher")

--..The bar..--
M.START = 0.35 -- where the icon starts (0 = the red end, 1 = the green end)
M.MAX_CPS = 20 -- clicks per second the server believes (plausibility of a "lifted" claim)
M.MAX_TIME = 12 -- seconds a bar may run before it fails on its own
M.GRACE = 0.7 -- seconds after the bar appears before the icon starts drifting (CAMERA_IN + a breath)
--.. THE CURVE, two ways (CURVE_MODE): ratio = Strength / kg
--.. "formula": Clicks = ClicksAtSign x ratio ^ -ClickPower (ClickPower = log(ClicksAtSign) / log(OneClickRatio):
--..   the slope that WOULD reach one click at OneClickRatio -- MIN_CLICKS stops it first), Drift = DriftAtSign x
--..   ratio ^ -DriftPower bar per second (DriftPower 1: twice the weight past you = the icon falls back twice as
--..   fast). Four knobs, smooth everywhere.
M.CURVE_MODE = "formula" -- "formula" | "table"
--.. 2026-09-23 (user: "green, yellow AND orange must be clickable without an autoclicker"): the drift no longer
--.. steepens with the weight (DriftPower 0) and is lower, so the click rate that just holds the icon is ~1.6 cps
--.. at the sign, ~2.7 at ratio 0.7 and ~3.5 at MIN_RATIO 0.4 (was 3 / 6 / 17): a steady 5-6 cps wins every
--.. liftable weight inside MAX_TIME; only the red "Too heavy" (below MIN_RATIO) cannot be won.
M.FORMULA = {ClicksAtSign = 11, OneClickRatio = 16, DriftAtSign = 0.095, DriftPower = 0}
M.MIN_CLICKS = 4 -- no lift takes fewer clicks than this whatever the strength (2026-09-18, user: "1 click instant pick up is too easy"); both modes, applied in Params
M.CLICK_MARGIN = 0.03 -- Clicks clicks fill the bar with this much to spare, so the slow drift of an easy lift does not cost a 5th click at a lazy rate
--.. "table": rows from the strongest down. Clicks = clicks that fill the bar from START with no drift
--.. (Gain = (1 - START) / Clicks); Cps = the click rate that only holds the icon still (Drift = Gain x Cps).
--.. Between rows: linear in log2(ratio). Shape any band by hand.
M.CURVE = {
	{Ratio = 16, Clicks = 1, Cps = 0}, -- one click (MIN_CLICKS floors it to 4 in Params)
	{Ratio = 8, Clicks = 2, Cps = 0}, -- two clicks (floored to 4)
	{Ratio = 4, Clicks = 3, Cps = 0.5}, -- three clicks (floored to 4); a pause costs a little
	{Ratio = 2.5, Clicks = 4, Cps = 0.8},
	{Ratio = 2, Clicks = 5, Cps = 1},
	{Ratio = 1.5, Clicks = 7, Cps = 1.5}, -- a casual 3-4 cps: ~3 s
	{Ratio = 1.2, Clicks = 9, Cps = 2},
	{Ratio = 1, Clicks = 11, Cps = 3}, -- AT the biome sign: steady clicking (5 cps ~5 s, 4 cps ~11 s)
	{Ratio = 0.9, Clicks = 12, Cps = 4.2}, -- click fast: 6-7 cps, no autoclicker (6 cps ~7 s)
	{Ratio = 0.8, Clicks = 14, Cps = 5.5}, -- click a LOT: 7-8 cps, still a human (8 cps ~6 s)
	{Ratio = 0.7, Clicks = 16, Cps = 7.5}, -- a real masher: 9-10 cps (10 cps ~6 s)
	{Ratio = 0.6, Clicks = 18, Cps = 10}, -- autoclicker territory (13 cps ~6 s)
	{Ratio = 0.5, Clicks = 20, Cps = 13}, -- (16 cps ~7 s)
	{Ratio = 0.4, Clicks = 22, Cps = 17}, -- MIN_RATIO: the last liftable weight (MAX_CPS 20 ~7 s)
}
M.MIN_RATIO = 0.4 -- below this no click rate wins (Feasible = false: the server refuses the claim too)
M.WEAK = {Clicks = 24, DriftMin = 0.55, DriftMax = 1.15} -- ratio < MIN_RATIO: Gain x MAX_CPS < DriftMin, the icon always wins

--..Timeline..--
M.APPROACH = 0.6
M.LIFT_LEN = 1.0
M.HOIST_LEN = 0.4
M.FAIL_RELAX = 0.45
M.CAMERA_IN = 0.35
M.CAMERA_OUT = 0.4

--..Difficulty (display: the prompt's colour + word, the bar's shout)..--
--.. colours (user 2026-09-18): GREEN = you lift it (trivial .. medium), YELLOW = work for it (hard, and the
--.. "Click fast!" / "Mash!" nudges), ORANGE = extreme (just the weight, no tag), RED = too heavy
M.COLORS = {Green = Color3.fromRGB(130, 255, 80), Yellow = Color3.fromRGB(255, 222, 65), Orange = Color3.fromRGB(255, 150, 50), Red = Color3.fromRGB(255, 79, 105)}
M.DIFFICULTY = { -- rows from the strongest down (MinRatio inclusive); Color = the prompt's weight colour, Hint = its nudge, Bar = the bar's shout
	{Name = "trivial", MinRatio = 8, Text = "Trivial", Color = M.COLORS.Green}, -- MIN_CLICKS (4) clicks, no drift to speak of
	{Name = "easy", MinRatio = 3, Text = "Easy", Color = M.COLORS.Green}, -- 4-5 clicks
	{Name = "medium", MinRatio = 1.5, Text = "Medium", Color = M.COLORS.Green}, -- 5-8 clicks, a slow drift
	{Name = "hard", MinRatio = 1, Text = "Hard", Color = M.COLORS.Yellow}, -- 8-11 clicks at a steady rate
	{Name = "close", MinRatio = 0.85, Text = "Close! Click fast", Color = M.COLORS.Yellow, Hint = "Click fast!", Bar = "CLICK FAST!"}, -- ~4 cps (2026-09-23 curve)
	{Name = "mash", MinRatio = 0.7, Text = "Very hard! Mash", Color = M.COLORS.Yellow, Hint = "Mash!", Bar = "CLICK FASTER!!"}, -- ~5 cps
	{Name = "extreme", MinRatio = M.MIN_RATIO, Text = "Extreme", Color = M.COLORS.Orange, Bar = "MASH!!!"}, -- 5-6 cps for ~9 s, a human's best, no autoclicker; the prompt shows just the weight
	{Name = "impossible", MinRatio = 0, Text = "Too heavy", Color = M.COLORS.Red},
}

--.. two significant digits: 5.13 -> 5.1, 42.3 -> 42, 1875 -> 1900
local function nice(n)
	if n <= 0 then return 0 end
	local mag = 10 ^ (math.floor(math.log10(n)) - 1)
	return math.floor(n / mag + 0.5) * mag
end

local function mutationCount(mutations)
	if type(mutations) == "table" then return math.min(#mutations, M.MUTATION_MAX) end -- the spawner's list before Join (WeightScale)
	if type(mutations) ~= "string" or mutations == "" then return 0 end
	local n = 0
	for _ in mutations:gmatch("[^,]+") do n += 1 end
	return math.min(n, M.MUTATION_MAX)
end

function M.Compute(zone, typeName, material, mutations, sizeScale)
	local base = M.ZONE_BASE[zone] or M.ZONE_BASE.Spawn
	local reward = CucumberValues.RewardOf(zone or "Spawn", typeName)
	local kg = base * (math.max(reward, M.REWARD_BASE) / M.REWARD_BASE) ^ M.REWARD_POWER
	kg *= M.MATERIAL_FACTOR[material] or 1
	kg *= M.MUTATION_FACTOR ^ mutationCount(mutations)
	sizeScale = tonumber(sizeScale) or 1
	if sizeScale > 1 then kg *= sizeScale ^ M.SIZE_POWER end
	return nice(kg)
end

function M.Of(holder)
	local stamped = holder and holder:GetAttribute("WeightKg")
	if type(stamped) == "number" then return stamped end
	if not holder then return M.ZONE_BASE.Spawn end
	local material = holder:GetAttribute("Material")
	if not material and holder:GetAttribute("Golden") == true then material = "Golden" end
	return M.Compute(holder:GetAttribute("Zone") or "Spawn", holder:GetAttribute("TypeName") or holder.Name,
		material, holder:GetAttribute("Mutations"), holder:GetAttribute("SizeScale"))
end

--.. the VISUAL size a cucumber gets from its weight (2026-09-17, user: "higher kg cucumbers slightly
--.. bigger, size depending on kg"): x(1 + WEIGHT_SIZE.Type per x10 of kg over the biome's lightest)
--.. -- the x6.8 tree reads ~8 % bigger than the slice, Golden +3 %, Diamond +6 % -- plus WEIGHT_SIZE.Biome
--.. per x10 of the biome's base over Spawn's (Desert +4 % .. Neon +23 %). CucumberSpawner multiplies it
--.. into the model scale next to TEMPLATE_SCALE and the giant SizeScale; the giant factor is NOT in this kg.
M.WEIGHT_SIZE = {Type = 0.1, Biome = 0.02}
function M.WeightScale(zone, typeName, material, mutations)
	local base = M.ZONE_BASE[zone] or M.ZONE_BASE.Spawn
	local kg = M.Compute(zone, typeName, material, mutations, 1)
	return 1 + M.WEIGHT_SIZE.Type * math.log10(math.max(kg / base, 1)) + M.WEIGHT_SIZE.Biome * math.log10(math.max(base / M.ZONE_BASE.Spawn, 1))
end

function M.Format(kg)
	kg = tonumber(kg) or 0
	return NumberAbbrev.Abbrev(kg) .. " kg"
end

--..The SHOWN weight (2026-09-17, user: "kg numbers not directly correlated with strength ... show
--..lower values / different numbers so the player doesn't know the exact strength they need; adds
--..mystery"; later: "make the displayed kg values less, e.g. 12 kg for 200 strength, 34 kg for 2.2K,
--..100 kg for 70K, like a big curve"). Everything the player reads (prompt, lift bar, shoulder
--..billboard) shows Shown(kg), never the requirement: a log-power curve through the two DISPLAY
--..anchors, Base + Scale x ln(kg) ^ Power, with Scale and Power solved from Low and High (200 -> 12,
--..70K -> 100; 2.2K then reads 34, Spawn's 3 kg slice 1.1, Desert 300 -> 15, Farm 15K -> 65, Snow
--..400K -> 150, Neon 1T -> 1.4K), nudged +-DISPLAY.Jitter by a stable hash of the biome + type (the
--..same kind always reads the same), two significant digits. It still rises with the real weight, it
--..just is nowhere near the Strength number. The requirement itself stays in WeightKg /
--..CarryingCucumberKg for the bar and the slowdown; the shown value rides along as ShownKg /
--..CarryingCucumberShownKg (stamped at spawn and at restore)..--
M.DISPLAY = {Base = 1, Low = {Strength = 200, Kg = 12}, High = {Strength = 70000, Kg = 100}, Jitter = 0.05}
local function hash01(s)
	local h = 5381
	for i = 1, #s do h = (h * 33 + s:byte(i)) % 4294967296 end
	return (h % 1000) / 999
end
--.. Scale and Power of the display curve from its two anchors
local function displayCurve()
	local d = M.DISPLAY
	local power = math.log((d.High.Kg - d.Base) / (d.Low.Kg - d.Base)) / math.log(math.log(d.High.Strength) / math.log(d.Low.Strength))
	local scale = (d.Low.Kg - d.Base) / math.log(d.Low.Strength) ^ power
	return scale, power
end
function M.Shown(kg, zone, typeName)
	kg = tonumber(kg) or 0
	if kg <= 0 then return 0 end
	local scale, power = displayCurve()
	local curve = kg > 1 and scale * math.log(kg) ^ power or 0
	local wobble = 1 + (hash01(tostring(zone) .. ":" .. tostring(typeName)) - 0.5) * 2 * M.DISPLAY.Jitter
	return nice((M.DISPLAY.Base + curve) * wobble)
end
--.. the shown weight of a field / placed cucumber (ShownKg attribute, else computed)
function M.ShownOf(holder)
	local stamped = holder and holder:GetAttribute("ShownKg")
	if type(stamped) == "number" then return stamped end
	if not holder then return 0 end
	return M.Shown(M.Of(holder), holder:GetAttribute("Zone") or "Spawn", holder:GetAttribute("TypeName") or holder.Name)
end

function M.Ratio(strength, kg)
	strength = tonumber(strength) or 0
	kg = tonumber(kg) or 0
	if kg <= 0 then return math.huge end
	return strength / kg
end

--.. the formula: Clicks and the hold rate (Drift / Gain) for a ratio
function M.CurveFormula(ratio)
	ratio = math.max(tonumber(ratio) or 0, 1e-9)
	local f = M.FORMULA
	local power = math.log(f.ClicksAtSign) / math.log(f.OneClickRatio)
	local clicks = ratio >= f.OneClickRatio and 1 or math.max(f.ClicksAtSign * ratio ^ -power, 1)
	local drift = f.DriftAtSign * ratio ^ -f.DriftPower
	return clicks, drift / ((1 - M.START) / clicks)
end

--.. Clicks (fill the bar with no drift) and Cps (the rate that holds the icon still) for a ratio
function M.Curve(ratio)
	if M.CURVE_MODE == "formula" then return M.CurveFormula(ratio) end
	return M.CurveTable(ratio)
end

--.. the table: CURVE interpolated by log2(ratio)
function M.CurveTable(ratio)
	ratio = math.max(tonumber(ratio) or 0, 0)
	local rows = M.CURVE
	if ratio >= rows[1].Ratio then return rows[1].Clicks, rows[1].Cps end
	local last = rows[#rows]
	if ratio <= last.Ratio then return last.Clicks, last.Cps end
	local x = math.log(ratio, 2)
	for i = 1, #rows - 1 do
		local a, b = rows[i], rows[i + 1]
		if ratio >= b.Ratio then
			local xa, xb = math.log(a.Ratio, 2), math.log(b.Ratio, 2)
			local t = (x - xa) / (xb - xa) -- 0 at row a .. 1 at row b
			return a.Clicks + (b.Clicks - a.Clicks) * t, a.Cps + (b.Cps - a.Cps) * t
		end
	end
	return last.Clicks, last.Cps
end

--.. the bar's numbers for a lift: how much a click is worth, how fast the icon slides back
function M.Params(ratio)
	ratio = math.max(tonumber(ratio) or 0, 0)
	local gain, drift, clicks, cps
	local feasible = ratio >= M.MIN_RATIO
	if feasible then
		clicks, cps = M.Curve(ratio)
		drift = (1 - M.START) / clicks * cps -- the curve's fall-back speed
		clicks = math.max(clicks, M.MIN_CLICKS) -- never an instant pickup: the floor shrinks the click, the drift stays
		gain = (1 - M.START) * (1 + M.CLICK_MARGIN) / clicks
		cps = drift / gain
	else
		local t = ratio / M.MIN_RATIO -- 1 just under the floor .. 0
		clicks, cps = M.WEAK.Clicks, math.huge
		gain = (1 - M.START) / M.WEAK.Clicks * t
		drift = M.WEAK.DriftMin + (M.WEAK.DriftMax - M.WEAK.DriftMin) * (1 - t)
	end
	local minClicks = gain > 0 and math.ceil((1 - M.START) / gain) or math.huge
	local band = M.Difficulty(ratio)
	return {
		Start = M.START,
		Gain = gain,
		Drift = drift,
		Clicks = clicks,
		Cps = cps,
		MinClicks = minClicks,
		MinTime = minClicks / M.MAX_CPS,
		Feasible = feasible,
		Band = band,
	}
end

--.. WalkSpeed multiplier while CARRYING a cucumber heavier than your strength (2026-09-17, user:
--.. "heavier cucumbers than the user's strength make them slightly slower, even more so the larger
--.. the difference"): 1 at the weight or above, sliding linearly to CARRY_SPEED_MIN at MIN_RATIO
--.. (nothing heavier can be lifted). StrengthProgressionServer applies it (attribute
--.. CarryingCucumberKg vs Data.Strength) and CucumberLiftClient keeps it when it restores the walk
--.. after a lift.
M.CARRY_SPEED_MIN = 0.45
function M.SpeedFor(ratio)
	ratio = tonumber(ratio) or math.huge
	if ratio >= 1 then return 1 end
	local t = math.clamp((1 - ratio) / (1 - M.MIN_RATIO), 0, 1)
	return 1 - t * (1 - M.CARRY_SPEED_MIN)
end

--.. clicks per second that hold the icon still (anything faster climbs); math.huge = no rate wins
function M.CpsToWin(ratio)
	local p = M.Params(ratio)
	if not p.Feasible or p.Gain <= 0 then return math.huge end
	return p.Drift / p.Gain
end

--.. seconds a steady click rate needs to fill the bar (the drift starts after GRACE); math.huge = it
--.. never gets there or the bar times out first (MAX_TIME)
function M.TimeToWin(ratio, cps)
	local p = M.Params(ratio)
	cps = tonumber(cps) or 0
	if not p.Feasible or p.Gain <= 0 or cps <= 0 then return math.huge end
	local left = 1 - p.Start
	local t = math.min(M.GRACE, left / (cps * p.Gain)) -- no drift yet
	left -= cps * p.Gain * t
	if left <= 0 then return t end
	local rate = cps * p.Gain - p.Drift
	if rate <= 0 then return math.huge end
	t += left / rate
	return t <= M.MAX_TIME and t or math.huge
end

function M.Difficulty(ratio)
	ratio = tonumber(ratio) or 0
	for _, row in ipairs(M.DIFFICULTY) do
		if ratio >= row.MinRatio then return row.Name, row.Color, row.Text, row end
	end
	local last = M.DIFFICULTY[#M.DIFFICULTY]
	return last.Name, last.Color, last.Text, last
end

return M
