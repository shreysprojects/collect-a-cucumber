-- WP-WORLDFX card tests (2026-09-22): PetCardClient's pure helpers (popup cap queue, rate text,
-- PRISMATIC detection, name/rarity row widths, prismatic colour, and since the world fix round the
-- ability tag + card rows + tag widths) and PlacedCucumberCardClient's
-- badge helpers (m:ss countdown, live-buff detection, badge widths/texts). Sources come from the
-- loopback servers; the popup cap is PetBalance.FX.MAX_POPUPS from src. No instances, nothing written.
local H = game:GetService("HttpService")
local SRC, PATCHED = "http://127.0.0.1:8793/", "http://127.0.0.1:8794/"

local function Fetch(base, file)
	return (H:GetAsync(base .. file):gsub("\r\n", "\n"))
end

local PetBalance = assert(loadstring(Fetch(SRC, "ReplicatedStorage.Modules.PetBalance.lua")))()
local NumberAbbrev = require(game:GetService("ReplicatedStorage").Modules.NumberAbbrev)
local Card = assert(loadstring(Fetch(SRC, "StarterPlayer.StarterPlayerScripts.PetCardClient.client.lua")))("__core")
local Badge = assert(loadstring(Fetch(PATCHED, "StarterPlayer.StarterPlayerScripts.PlacedCucumberCardClient.client.lua")))("__core")

local pass, fail, failures = 0, 0, {}
local function Check(name, cond, detail)
	if cond then pass += 1 else
		fail += 1
		if #failures < 8 then table.insert(failures, name .. (detail ~= nil and (" [" .. tostring(detail) .. "]") or "")) end
	end
end
local function Near(a, b, eps) return type(a) == "number" and math.abs(a - b) <= (eps or 1e-6) end

--..PetCardClient..--
-- popup cap queue: FX.MAX_POPUPS live, the next one dropped, a finished popup frees a slot
local max = PetBalance.FX.MAX_POPUPS
Check("MAX_POPUPS is 32", max == 32, max)
local cap = Card.NewCap(max)
local taken = 0
for _ = 1, max do if cap:Take() then taken += 1 end end
Check("cap takes MAX", taken == max and cap.Live == max, taken)
Check("cap drops the next", cap:Take() == false and cap.Dropped == 1)
Check("cap drops again", cap:Take() == false and cap.Dropped == 2 and cap.Live == max)
cap:Give()
Check("give frees one", cap.Live == max - 1)
Check("take after give", cap:Take() == true and cap.Live == max)
local small = Card.NewCap(2)
small:Give()
Check("give never below 0", small.Live == 0)
Check("zero cap drops all", Card.NewCap(0):Take() == false)
Check("garbage cap = 0", Card.NewCap("x"):Take() == false and Card.NewCap(0 / 0).Max == 0)
-- a 100-popup burst with 1-in-4 finishing: live never exceeds the cap
local burst = Card.NewCap(max)
local peak = 0
for i = 1, 100 do
	burst:Take()
	if i % 4 == 0 then burst:Give() end
	peak = math.max(peak, burst.Live)
end
Check("burst never exceeds cap", peak == max, peak)

-- rate text (NumberAbbrev, green "$X/s" convention)
Check("rate 0.5", Card.RateText(0.5, NumberAbbrev.Abbrev) == "$0.5/s", Card.RateText(0.5, NumberAbbrev.Abbrev))
Check("rate 15.7M", Card.RateText(15728640, NumberAbbrev.Abbrev) == "$15.7M/s", Card.RateText(15728640, NumberAbbrev.Abbrev))
Check("rate 0", Card.RateText(0, NumberAbbrev.Abbrev) == "$0/s", Card.RateText(0, NumberAbbrev.Abbrev))
Check("rate NaN", Card.RateText(0 / 0, NumberAbbrev.Abbrev) == "")
Check("rate inf", Card.RateText(math.huge, NumberAbbrev.Abbrev) == "")
Check("rate negative", Card.RateText(-1, NumberAbbrev.Abbrev) == "")
Check("rate nil", Card.RateText(nil, NumberAbbrev.Abbrev) == "")

-- PRISMATIC detection on the Mutations attribute string
Check("prismatic in list", Card.HasMutation("NEON,PRISMATIC", "PRISMATIC"))
Check("prismatic spaced lower", Card.HasMutation("neon, prismatic", "PRISMATIC"))
Check("prismatic alone", Card.HasMutation("PRISMATIC", "PRISMATIC"))
Check("prismatic substring no", not Card.HasMutation("PRISMATICX,NEON", "PRISMATIC"))
Check("prismatic absent", not Card.HasMutation("NEON,VOID", "PRISMATIC"))
Check("prismatic nil / non-string", not Card.HasMutation(nil, "PRISMATIC") and not Card.HasMutation({"PRISMATIC"}, "PRISMATIC"))
Check("prismatic empty", not Card.HasMutation("", "PRISMATIC"))

-- name + rarity word widths (fractions of the row): fit -> natural, too long -> shrunk together
local aspect = 5.2 / (1.9 * 0.52)
local nw, rw = Card.NameRowWidths(3, 8, aspect) -- "Cat" + "· Common"
Check("short fits", nw + rw <= 0.96 + 1e-9, nw + rw)
Check("short ratio", Near((rw / 8) / (nw / 3), 0.7), (rw / 8) / (nw / 3))
local lw, lrw = Card.NameRowWidths(16, 11, aspect) -- "Flame Salamander" + "· Legendary"
Check("long fills row", Near(lw + lrw, 0.96), lw + lrw)
Check("long keeps ratio", Near((lrw / 11) / (lw / 16), 0.7), (lrw / 11) / (lw / 16))
local zw, zrw = Card.NameRowWidths(nil, nil, 0 / 0)
Check("garbage widths finite", Card.Finite(zw) and Card.Finite(zrw) and zw > 0 and zrw == 0, zw)

-- PRISMATIC colour = ApplyLook's recipe
local c0 = Card.PrismaticColor(0)
local e0 = Color3.fromHSV(0, 0.65, 1)
Check("prismatic colour t=0", Near(c0.R, e0.R) and Near(c0.G, e0.G) and Near(c0.B, e0.B))
local c5 = Card.PrismaticColor(5)
local e5 = Color3.fromHSV((5 * 0.12) % 1, 0.65, 1)
Check("prismatic colour t=5", Near(c5.R, e5.R) and Near(c5.G, e5.G) and Near(c5.B, e5.B))
Check("prismatic colour NaN safe", typeof(Card.PrismaticColor(0 / 0)) == "Color3")

-- ability tag (2026-09-22 world fix round, S4 open issue 1): the row-high glyph + the ability's
-- DisplayName on a third row, only for ability pets; the other rows keep their stud heights
local GLYPHS, ABIL = Card.ABILITY_GLYPHS, PetBalance.ABILITIES
local tg, tw = Card.AbilityTag("Yield", ABIL, GLYPHS)
Check("tag Yield = sparkles + Lucky Harvest", tg == "\u{2728}" and tw == "Lucky Harvest", tostring(tg) .. " " .. tostring(tw))
for _, k in ipairs({"Yield", "Haste", "Guard", "Wild"}) do
	local gk, wk = Card.AbilityTag(k, ABIL, GLYPHS)
	Check("tag " .. k .. " = glyph + DisplayName", type(gk) == "string" and gk ~= "" and wk == ABIL[k].DisplayName, wk)
end
Check("tag None (Fighter) = no tag", Card.AbilityTag("None", ABIL, GLYPHS) == nil)
Check("tag unknown = no tag", Card.AbilityTag("Laser", ABIL, GLYPHS) == nil)
Check("tag non-string = no tag", Card.AbilityTag(5, ABIL, GLYPHS) == nil and Card.AbilityTag(nil, ABIL, GLYPHS) == nil)
Check("tag no glyph table = no tag", Card.AbilityTag("Yield", ABIL, nil) == nil)
Check("tag no ability row = the key", select(2, Card.AbilityTag("Yield", nil, GLYPHS)) == "Yield")
Check("tag empty DisplayName = the key", select(2, Card.AbilityTag("Haste", {Haste = {DisplayName = ""}}, GLYPHS)) == "Haste")

local fh, fn, fr, ft = Card.CardRows(false)
Check("fighter card unchanged 5.2 x 1.9", Near(fh, 1.9) and Near(fn, 0.52) and Near(fr, 0.48) and ft == 0, fh)
local ah, an, ar, at = Card.CardRows(true)
Check("ability card = 1.9 + TAG_H", Near(ah, 1.9 + Card.TAG_H), ah)
Check("ability card name row keeps its studs", Near(an * ah, 0.52 * 1.9), an * ah)
Check("ability card cash row keeps its studs", Near(ar * ah, 0.48 * 1.9), ar * ah)
Check("ability card tag row = TAG_H studs", Near(at * ah, Card.TAG_H), at * ah)
Check("ability card rows fill it", Near(an + ar + at, 1), an + ar + at)

local tagAspect = Card.CARD_W / Card.TAG_H
local sg, sw = Card.TagWidths(9, tagAspect) -- "Wild Card"
Check("tag glyph is a row-high square", Near(sg * Card.CARD_W, Card.TAG_H), sg * Card.CARD_W)
Check("tag short word natural width", Near(sw, 9 * 0.56 / tagAspect), sw)
Check("tag short fits the row", sg + 0.02 + sw <= 0.96 + 1e-9, sg + 0.02 + sw)
local lg, lw2 = Card.TagWidths(13, tagAspect) -- "Lucky Harvest"
Check("tag long word takes the room left", Near(lg + 0.02 + lw2, 0.96), lg + 0.02 + lw2)
-- legibility: the glyph box beats the old chip's 0.8 x 0.78 of the 0.912-stud cash row (0.569 studs)
-- by 40 %, and every word's text height (width-limited estimate) stays >= 0.55 studs
Check("tag glyph box >= 1.4 x the old emoji", Card.TAG_H >= 1.4 * 0.8 * 0.78 * 1.9 * 0.48, Card.TAG_H)
for _, k in ipairs({"Yield", "Haste", "Guard", "Wild"}) do
	local word = ABIL[k].DisplayName
	local chars = utf8.len(word)
	local _, ww = Card.TagWidths(chars, tagAspect)
	local textH = math.min(Card.TAG_H, ww * Card.CARD_W / (chars * 0.56))
	Check("tag " .. k .. " text >= 0.55 studs", textH >= 0.55, ("%.3f"):format(textH))
end
local zg, zw = Card.TagWidths(nil, 0 / 0)
Check("tag widths garbage finite", Card.Finite(zg) and Card.Finite(zw) and zw >= 0, tostring(zg) .. " " .. tostring(zw))

--..PlacedCucumberCardClient badges..--
local F = Badge.FormatCountdown
Check("m:ss 89.2", F(89.2) == "1:30", F(89.2))
Check("m:ss 90", F(90) == "1:30", F(90))
Check("m:ss 59.01", F(59.01) == "1:00", F(59.01))
Check("m:ss 60", F(60) == "1:00", F(60))
Check("m:ss 61", F(61) == "1:01", F(61))
Check("m:ss 9", F(9) == "0:09", F(9))
Check("m:ss 0.2 never 0:00 while live", F(0.2) == "0:01", F(0.2))
Check("m:ss 240", F(240) == "4:00", F(240))
Check("m:ss 600", F(600) == "10:00", F(600))
Check("m:ss 0", F(0) == "0:00")
Check("m:ss negative", F(-5) == "0:00")
Check("m:ss NaN", F(0 / 0) == "0:00")
Check("m:ss inf", F(math.huge) == "0:00")
Check("m:ss nil / string", F(nil) == "0:00" and F("90") == "0:00")
Check("m:ss capped", F(1e9) == "99:59", F(1e9))

local function FakeModel(attrs)
	local m = {Attrs = attrs}
	function m:GetAttribute(name) return self.Attrs[name] end
	return m
end
local now = 1000
local order = {"Yield", "Haste", "Guard"}
local live = Badge.LiveBuffs(FakeModel({PetBuff_Yield = now + 5, PetBuff_Haste = now - 1, PetBuff_Guard = now + 100}), now, order)
Check("live buffs skip expired", #live == 2 and live[1] == "Yield" and live[2] == "Guard", table.concat(live, ","))
local none = Badge.LiveBuffs(FakeModel({PetBuff_Yield = 0 / 0, PetBuff_Haste = "1e9", PetBuff_Guard = math.huge}), now, order)
Check("live buffs reject garbage", #none == 0, table.concat(none, ","))
local exact = Badge.LiveBuffs(FakeModel({PetBuff_Haste = now}), now, order)
Check("live buffs: expiry == now is expired", #exact == 0)
local all = Badge.LiveBuffs(FakeModel({PetBuff_Guard = now + 1, PetBuff_Haste = now + 1, PetBuff_Yield = now + 1}), now, order)
Check("live buffs keep badge order", table.concat(all, ",") == "Yield,Haste,Guard", table.concat(all, ","))
Check("live buffs NaN now", #Badge.LiveBuffs(FakeModel({PetBuff_Yield = now + 1}), 0 / 0, order) == 0)

Check("badge width 1", Near(Badge.BadgeWidth(1), 0.5))
Check("badge width 2", Near(Badge.BadgeWidth(2), 0.46))
Check("badge width 3", Near(Badge.BadgeWidth(3), 0.3))
Check("badge widths fit", 3 * Badge.BadgeWidth(3) + 2 * 0.02 <= 1)

local G = "<S>"
Check("badge yield", Badge.BadgeText("Yield", "x1.5", nil, 89.2, G) == "x1.5 1:30", Badge.BadgeText("Yield", "x1.5", nil, 89.2, G))
Check("badge haste", Badge.BadgeText("Haste", "+25%", nil, 12, G) == "+25% 0:12", Badge.BadgeText("Haste", "+25%", nil, 12, G))
Check("badge guard charges", Badge.BadgeText("Guard", "1", 1, 239.5, G) == "<S>1 4:00", Badge.BadgeText("Guard", "1", 1, 239.5, G))
Check("badge guard no charges attr", Badge.BadgeText("Guard", "1", nil, 30, G) == "<S>1 0:30", Badge.BadgeText("Guard", "1", nil, 30, G))
Check("badge guard NaN charges", Badge.BadgeText("Guard", "1", 0 / 0, 30, G) == "<S>1 0:30")
Check("badge empty text", Badge.BadgeText("Yield", "", nil, 5, G) == "0:05")

-- the badge texts the live module produces (PetStats.AbilityBadge from src, PetBalance injected)
local okStats, PetStats = pcall(function()
	local fn = assert(loadstring(Fetch(SRC, "ReplicatedStorage.Modules.PetStats.lua")))
	local function Fake(name)
		local inst = {Name = name}
		function inst:WaitForChild(child) return Fake(child) end
		function inst:FindFirstChild(child) return Fake(child) end
		return inst
	end
	local modules = {PetBalance = PetBalance, PetsCatalog = require(game:GetService("ReplicatedStorage").Modules.PetsCatalog)}
	local fakeGame = {}
	function fakeGame:GetService(service)
		if service == "ReplicatedStorage" then return Fake("ReplicatedStorage") end
		return game:GetService(service)
	end
	setfenv(fn, setmetatable({game = fakeGame, require = function(t) return assert(modules[t.Name], t.Name) end}, {__index = getfenv(0)}))
	return fn()
end)
if okStats then
	Check("PetStats badge Yield", Badge.BadgeText("Yield", PetStats.AbilityBadge("Yield"), nil, 90, G) == "x1.5 1:30", PetStats.AbilityBadge("Yield"))
	Check("PetStats badge Haste", Badge.BadgeText("Haste", PetStats.AbilityBadge("Haste"), nil, 90, G) == "+25% 1:30", PetStats.AbilityBadge("Haste"))
	Check("PetStats badge Guard", Badge.BadgeText("Guard", PetStats.AbilityBadge("Guard"), nil, 240, G) == "<S>1 4:00", PetStats.AbilityBadge("Guard"))
else
	Check("PetStats loads", false, PetStats)
end

return ("WP-WORLDFX cards: PASS %d / FAIL %d: %s"):format(pass, fail, table.concat(failures, "; "))
