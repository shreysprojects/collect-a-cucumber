--[[
	WP-HATCH EggHatchClient test (2026-09-22, read-only).
	Cuts three blocks out of the PATCHED StarterPlayer.StarterPlayerScripts.EggHatchClient source
	(loopback :8794) - the card-line helpers (AbilityLine / StatsText / TraitsText), BuildCard and the
	PetHatch.OnClientEvent handler - and runs each with plain-table fakes (setfenv). CucumberMutations,
	NumberAbbrev and PetsCatalog are the live modules (required read-only); PetStats / PetBalance are
	fakes that follow CONTRACTS 3.2 / 9. Nothing is created or changed in the DataModel.
	Checks CONTRACTS 4.4: token on all three acknowledgments (busy / watchdog / normal), the watchdog's
	Token bump (no second ack), reserve / locked-hatch notices after a successful reveal only, the
	PetStats line (green $X/s + ability line from the text helpers), PetTraits (material + mutation words),
	hidden labels when the payload or template lacks them.
	Returns "WP-HATCH client_reveal: PASS n / FAIL m: <first failures>".
]]
local HttpService = game:GetService("HttpService")
local RS = game:GetService("ReplicatedStorage")
local CucumberMutations = require(RS.Modules.CucumberMutations)
local NumberAbbrev = require(RS.Modules.NumberAbbrev)
local Catalog = require(RS.Modules.PetsCatalog)
local src = HttpService:GetAsync("http://127.0.0.1:8794/StarterPlayer.StarterPlayerScripts.EggHatchClient.client.lua")

local pass, fail, failures = 0, 0, {}
local function check(name, cond, detail)
	if cond then pass += 1 else
		fail += 1
		if #failures < 12 then table.insert(failures, name .. (detail and (" [" .. tostring(detail) .. "]") or "")) end
	end
end
local function Between(startMarker, endMarker)
	local a = src:find(startMarker, 1, true)
	if not a then return nil end
	local b = endMarker and src:find(endMarker, a + #startMarker, true) or (#src + 1)
	if not b then return nil end
	return src:sub(a, b - 1)
end
local function Line(prefix) return src:match("\n(" .. prefix:gsub("%p", "%%%0") .. "[^\r\n]*)") end

--..fakes shared by the chunks..--
local FakeBalance = {
	ABILITIES = {
		Yield = {DisplayName = "Lucky Harvest", Mult = 1.5, Duration = 90, Color = Color3.fromRGB(255, 205, 40)},
		Haste = {DisplayName = "Quick Grow", Mult = 1.25, Duration = 90, Color = Color3.fromRGB(60, 220, 255)},
		Guard = {DisplayName = "Leaf Shield", Charges = 1, Color = Color3.fromRGB(90, 230, 110)},
		Wild = {DisplayName = "Wild Card", Kinds = {"Yield", "Haste", "Guard"}, Color = Color3.fromRGB(255, 120, 230)},
		None = {DisplayName = "Fighter", Color = Color3.fromRGB(255, 90, 70)},
	},
	FIGHTER_MULT = 1.15,
	TEXT = {ReserveNotice = "Your new pet is in reserve - open Pets to equip it.",
		LockedHatchNotice = "Your new pet joins your team when the fight is over."},
}
local FakeStats = {}
function FakeStats.AbilityShort(kind, guardSeconds)
	local a = FakeBalance.ABILITIES[kind]
	if kind == "Yield" then return ("x%g for %ds"):format(a.Mult, a.Duration) end
	if kind == "Haste" then return ("+%d%% for %ds"):format((a.Mult - 1) * 100 + 0.5, a.Duration) end
	if kind == "Guard" then return ("blocks one theft for %ds"):format(guardSeconds or 205) end
	return ""
end
function FakeStats.AbilityEffect(kind)
	if kind == "None" then return ("Fighter: +%d%% damage"):format((FakeBalance.FIGHTER_MULT - 1) * 100 + 0.5) end
	return ""
end
local Installed = {Stats = true, Balance = true}

--..1. card lines..--
local cardChunkSrc = table.concat({
	Line("local CASH_HEX = ") or "error('CASH_HEX line missing')",
	Line("local SEPARATOR = ") or "error('SEPARATOR line missing')",
	Between("--..Card lines (2026-09-22)..--", "local function CardOut(card)") or "error('card block missing')",
	"return AbilityLine, StatsText, TraitsText, BuildCard",
}, "\n")

local function Label(name)
	local l = {Name = name, Text = "", Visible = false, RichText = false, Children = {}}
	function l:IsA(c) return c == "TextLabel" or c == "GuiObject" end
	function l:FindFirstChild(n) return self.Children[n] end
	return l
end
local function Card(withNew)
	local card = {Children = {}}
	for _, n in ipairs({"PetName", "PetRarity", "PetUnlocked", "PetChance"}) do card.Children[n] = Label(n) end
	if withNew then card.Children.PetStats = Label("PetStats") card.Children.PetTraits = Label("PetTraits") end
	function card:FindFirstChild(n) return self.Children[n] end
	return card
end
local NextCardHasNew = true
local SingleTemplate = {}
function SingleTemplate:Clone() return Card(NextCardHasNew) end
local cardEnv = {
	CucumberMutations = CucumberMutations, NumberAbbrev = NumberAbbrev, Catalog = Catalog,
	GetPetStats = function() return Installed.Stats and FakeStats or nil end,
	GetPetBalance = function() return Installed.Balance and FakeBalance or nil end,
	SingleTemplate = SingleTemplate, SingleLayer = {}, UDim2 = UDim2, Enum = Enum, TweenInfo = TweenInfo,
	TweenService = {Create = function() return {Play = function() end} end},
	string = string, table = table, math = math, type = type, typeof = typeof, tostring = tostring, tonumber = tonumber,
	pairs = pairs, ipairs = ipairs, pcall = pcall, error = error,
}
local cardChunk, cardErr = loadstring(cardChunkSrc, "=EggHatchClient card block")
check("card block compiles", cardChunk ~= nil, cardErr)
if cardChunk then
	setfenv(cardChunk, cardEnv)
	local ok, AbilityLine, StatsText, TraitsText, BuildCard = pcall(cardChunk)
	check("card block loads", ok, AbilityLine)
	if ok then
		local F = CucumberMutations.Font
		local SEP = "  \u{00B7}  "
		local cash = function(s) return '<font color="#41EB14">$' .. s .. '/s</font>' end
		local y = StatsText({Income = 3.75, Ability = "Yield", AbilityChance = 0.01, AbilityDuration = 90, Fighter = false})
		check("stats: Yield line", y == cash("3.75") .. SEP .. F("Lucky Harvest", FakeBalance.ABILITIES.Yield.Color, true) .. " x1.5 for 90s" .. SEP .. "1% / min", y)
		local h = StatsText({Income = 15728640, Ability = "Haste", AbilityChance = 0.12, AbilityDuration = 90, Fighter = false})
		check("stats: Haste line + abbreviated cash", h == cash("15.7M") .. SEP .. F("Quick Grow", FakeBalance.ABILITIES.Haste.Color, true) .. " +25% for 90s" .. SEP .. "12% / min", h)
		local gd = StatsText({Income = 7.8, Ability = "Guard", AbilityChance = 0.08, AbilityDuration = 240.4, Fighter = false})
		check("stats: Guard uses the payload duration", gd and gd:find("blocks one theft for 240s", 1, true) ~= nil and gd:find("8% / min", 1, true) ~= nil, gd)
		local w = StatsText({Income = 1, Ability = "Wild", AbilityChance = 0.02, Fighter = false})
		check("stats: Wild has no effect words", w == cash("1") .. SEP .. F("Wild Card", FakeBalance.ABILITIES.Wild.Color, true) .. SEP .. "2% / min", w)
		local fi = StatsText({Income = 0.5, Ability = "None", AbilityChance = 0, Fighter = true})
		check("stats: fighter line", fi == cash("0.5") .. SEP .. F("Fighter: +15% damage", FakeBalance.ABILITIES.None.Color, true), fi)
		local nan = StatsText({Income = 0 / 0, Ability = "Bogus", AbilityChance = 0 / 0})
		check("stats: NaN income -> $0/s, unknown ability dropped", nan == cash("0"), nan)
		check("stats: nil payload -> hidden", StatsText(nil) == nil)
		Installed.Stats = false
		check("stats: PetStats not installed -> hidden", StatsText({Income = 1, Ability = "Yield"}) == nil)
		Installed.Stats = true
		local t1 = TraitsText("Golden", "NEON,SHADOW")
		check("traits: material + mutations in their colours", t1 == F("Golden", CucumberMutations.ColorOf("Golden"), true) .. SEP
			.. F("NEON", CucumberMutations.ColorOf("NEON"), true) .. SEP .. F("SHADOW", CucumberMutations.ColorOf("SHADOW"), true), t1)
		check("traits: normal egg -> hidden", TraitsText(nil, "") == nil and TraitsText("", "BOGUS") == nil and TraitsText(nil, nil) == nil)
		check("traits: Diamond only", TraitsText("Diamond", "") == F("Diamond", CucumberMutations.ColorOf("Diamond"), true))

		local info = {PetDisplayName = "Cat", Pet = "Cat", Rarity = "Common", Chance = "[1 in 3]", Material = "Golden", Mutations = "NEON",
			Stats = {Income = 3.75, Ability = "Yield", AbilityChance = 0.01, AbilityDuration = 90, Fighter = false}}
		local card = BuildCard(info)
		local ps, pt = card.Children.PetStats, card.Children.PetTraits
		check("card: PetStats filled + visible + RichText", ps.Visible == true and ps.RichText == true and ps.Text == StatsText(info.Stats))
		check("card: PetTraits filled + visible", pt.Visible == true and pt.Text == TraitsText("Golden", "NEON"))
		check("card: existing labels unchanged", card.Children.PetName.Text == "CAT" and card.Children.PetRarity.Text == "COMMON"
			and card.Children.PetChance.Visible == true and card.Children.PetUnlocked.Visible == false)
		local card2 = BuildCard({PetDisplayName = "Dog", Rarity = "Common"})
		check("card: no Stats / normal egg -> both hidden and empty", card2.Children.PetStats.Visible == false and card2.Children.PetStats.Text == ""
			and card2.Children.PetTraits.Visible == false)
		NextCardHasNew = false
		local okOld, card3 = pcall(BuildCard, info)
		check("card: template without the new labels still builds", okOld and card3 ~= nil, card3)
		NextCardHasNew = true
	end
end

--..2. the PetHatch handler (acknowledgments + notices)..--
local handlerSrc = Between("PetHatch.OnClientEvent:Connect(function(action, info)", nil)
local Acks, Toasts, Restores, Delays = {}, {}, 0, {}
local RevealMode, RevealHook = "ok", nil
local Handler
local hEnv = {
	PetHatch = {
		OnClientEvent = {Connect = function(_, fn) Handler = fn end},
		FireServer = function(_, action, token) table.insert(Acks, {action, token}) end,
	},
	Camera = {CameraType = "Custom"},
	Reveal = function()
		if RevealHook then local hook = RevealHook RevealHook = nil hook() end
		if RevealMode == "error" then error("reveal broke") end
	end,
	Restore = function() Restores += 1 end,
	task = {delay = function(s, fn) local d = {Seconds = s, Fn = fn} table.insert(Delays, d) return d end},
	GetPetBalance = function() return FakeBalance end,
	Notify = {Info = function(text) table.insert(Toasts, text) end},
	warn = function() end, pcall = pcall, type = type, tostring = tostring, error = error,
}
local hChunk, hErr = loadstring("local Busy = false\nlocal Token = 0\nlocal WATCHDOG = 95\n" .. (handlerSrc or "error('handler block missing')"), "=EggHatchClient handler")
check("handler block compiles", hChunk ~= nil, hErr)
if hChunk then
	setfenv(hChunk, hEnv)
	local okH, errH = pcall(hChunk)
	check("handler block loads + connects", okH and type(Handler) == "function", errH)
	if okH and Handler then
		local function Begin(info) Handler("Begin", info) end
		local function Last() return Acks[#Acks] end
		-- a. normal
		Begin({Token = "T1"})
		check("normal: one Opened with the token", #Acks == 1 and Last()[1] == "Opened" and Last()[2] == "T1")
		check("normal: no notice for an equipped pet", #Toasts == 0)
		local watch1 = Delays[#Delays]
		check("watchdog armed at 95 s", watch1 and watch1.Seconds == 95)
		watch1.Fn()
		check("late watchdog after a finished reveal does nothing", #Acks == 1 and Restores == 0)
		-- b. reserve / c. locked
		Begin({Token = "T2", Reserve = true})
		check("reserve: ack + ReserveNotice", Last()[2] == "T2" and Toasts[#Toasts] == FakeBalance.TEXT.ReserveNotice and #Toasts == 1)
		Begin({Token = "T3", Reserve = true, AutoEquipAfterCombat = true})
		check("locked: LockedHatchNotice only", Last()[2] == "T3" and Toasts[#Toasts] == FakeBalance.TEXT.LockedHatchNotice and #Toasts == 2)
		-- d. reveal error
		RevealMode = "error"
		Begin({Token = "T4", Reserve = true})
		check("error: restored, acked once, no notice", Restores == 1 and Last()[2] == "T4" and #Acks == 4 and #Toasts == 2)
		RevealMode = "ok"
		-- e. busy: a second Begin arrives while the first reveal runs
		RevealHook = function() Begin({Token = "T6"}) end
		Begin({Token = "T5"})
		check("busy: second Begin acked at once with its own token, then the first", #Acks == 6 and Acks[5][2] == "T6" and Acks[6][2] == "T5")
		-- f. watchdog fires while the reveal is stuck: exactly one ack
		RevealHook = function() Delays[#Delays].Fn() end
		Begin({Token = "T7", Reserve = true})
		local sevens = 0
		for _, a in ipairs(Acks) do if a[2] == "T7" then sevens += 1 end end
		check("watchdog: one ack only (Token bump blocks the late finish)", sevens == 1 and #Acks == 7 and Restores == 2)
		check("watchdog: no notice", #Toasts == 2)
		-- next reveal after a watchdog works normally
		Begin({Token = "T8"})
		check("after a watchdog the next reveal acks normally", #Acks == 8 and Last()[2] == "T8")
		-- h. no / bad token from an old server
		Begin({Token = 123})
		check("non-string token -> Opened with nil", #Acks == 9 and Last()[1] == "Opened" and Last()[2] == nil)
		Handler("Other", {Token = "X"})
		Handler("Begin", "not a table")
		check("non-Begin / bad payload ignored", #Acks == 9)
	end
end

return ("WP-HATCH client_reveal: PASS %d / FAIL %d%s"):format(pass, fail, #failures > 0 and (": " .. table.concat(failures, "; ")) or "")
