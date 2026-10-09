-- WP-INCOME core: IncomeService.Core pure maths + the public API before Init / Start (2026-09-22).
-- Read-only: loads the module from the loopback src server; creates no instances, touches no DataModel state.
local HttpService = game:GetService("HttpService")
local src = HttpService:GetAsync("http://127.0.0.1:8793/ServerStorage.IncomeService.lua")
local chunk, compileErr = loadstring(src)
if not chunk then return "WP-INCOME core: PASS 0 / FAIL 1: compile " .. tostring(compileErr) end
local IncomeService = chunk()
local Core = IncomeService.Core

local pass, fail, failures = 0, 0, {}
local function check(name, cond, detail)
	if cond then
		pass += 1
	else
		fail += 1
		if #failures < 8 then table.insert(failures, name .. (detail ~= nil and (" [" .. tostring(detail) .. "]") or "")) end
	end
end
local function near(a, b, eps)
	return type(a) == "number" and type(b) == "number" and math.abs(a - b) <= (eps or 1e-9) * math.max(1, math.abs(a), math.abs(b))
end

local T = 1000
local far = T + 1000
local YIELD = {Kind = "Yield", Mult = 1.5, ExpiresAt = far}
local HASTE = {Kind = "Haste", Mult = 1.25, ExpiresAt = far}

--.. EffectiveMult
check("mult: none = 1", Core.EffectiveMult({}, T, 2) == 1)
check("mult: nil mods = 1", Core.EffectiveMult(nil, T, 2) == 1)
check("mult: Yield 1.5", near(Core.EffectiveMult({YIELD}, T, 2), 1.5))
check("mult: Haste 1.25", near(Core.EffectiveMult({HASTE}, T, 2), 1.25))
check("mult: both 1.875", near(Core.EffectiveMult({YIELD, HASTE}, T, 2), 1.875))
check("mult: cap 2.0", near(Core.EffectiveMult({YIELD, {Kind = "X", Mult = 1.5, ExpiresAt = far}}, T, 2), 2))
check("mult: expired ignored", Core.EffectiveMult({{Kind = "Yield", Mult = 1.5, ExpiresAt = T - 1}}, T, 2) == 1)
check("mult: live strictly before ExpiresAt", Core.EffectiveMult({{Kind = "Yield", Mult = 1.5, ExpiresAt = T}}, T, 2) == 1)
check("mult: NaN mult ignored", Core.EffectiveMult({{Kind = "Yield", Mult = 0 / 0, ExpiresAt = far}}, T, 2) == 1)
check("mult: inf expiry ignored", Core.EffectiveMult({{Kind = "Yield", Mult = 1.5, ExpiresAt = math.huge}}, T, 2) == 1)
check("mult: garbage entries ignored", Core.EffectiveMult({5, "x", {Mult = "1.5", ExpiresAt = far}}, T, 2) == 1)
check("mult: bad cap -> default 2", near(Core.EffectiveMult({YIELD, YIELD}, T, 0 / 0), 2))

--.. SettleAmount
check("settle: base 10, 1 s = 10", near(Core.SettleAmount(10, {}, T, T + 1, 2), 10))
check("settle: Yield 15", near(Core.SettleAmount(10, {YIELD}, T, T + 1, 2), 15))
check("settle: Haste 12.5", near(Core.SettleAmount(10, {HASTE}, T, T + 1, 2), 12.5))
check("settle: both 18.75", near(Core.SettleAmount(10, {YIELD, HASTE}, T, T + 1, 2), 18.75))
check("settle: cap 20", near(Core.SettleAmount(10, {YIELD, {Kind = "X", Mult = 1.5, ExpiresAt = far}}, T, T + 1, 2), 20))
check("settle: split at expiry 0.4 -> 12",
	near(Core.SettleAmount(10, {{Kind = "Yield", Mult = 1.5, ExpiresAt = T + 0.4}}, T, T + 1, 2), 12))
check("settle: two expiries -> 13.375", near(Core.SettleAmount(10,
	{{Kind = "Haste", Mult = 1.25, ExpiresAt = T + 0.6}, {Kind = "Yield", Mult = 1.5, ExpiresAt = T + 0.3}}, T, T + 1, 2), 13.375))
check("settle: late wake splits (3 s, expiry 0.4) -> 32",
	near(Core.SettleAmount(10, {{Kind = "Yield", Mult = 1.5, ExpiresAt = T + 0.4}}, T, T + 3, 2), 32))
check("settle: expiry before the span ignored", near(Core.SettleAmount(10, {{Kind = "Yield", Mult = 1.5, ExpiresAt = T - 5}}, T, T + 1, 2), 10))
check("settle: same expiry twice", near(Core.SettleAmount(10,
	{{Kind = "Yield", Mult = 1.5, ExpiresAt = T + 0.5}, {Kind = "Haste", Mult = 1.25, ExpiresAt = T + 0.5}}, T, T + 1, 2), 10 * (1.875 * 0.5 + 0.5)))
check("settle: fractional kept (0.5 x 0.3)", near(Core.SettleAmount(0.5, {}, T, T + 0.3, 2), 0.15))
check("settle: NaN base -> 0", Core.SettleAmount(0 / 0, {}, T, T + 1, 2) == 0)
check("settle: negative base -> 0", Core.SettleAmount(-3, {}, T, T + 1, 2) == 0)
check("settle: t1 <= t0 -> 0", Core.SettleAmount(10, {}, T + 1, T, 2) == 0)
check("settle: inf times -> 0", Core.SettleAmount(10, {}, T, math.huge, 2) == 0)

--.. ClampElapsed
local s1, c1 = Core.ClampElapsed(T, T + 8, 5)
check("clamp: 8 s -> start t1-5, clamped", s1 == T + 3 and c1 == true, tostring(s1) .. "/" .. tostring(c1))
local s2, c2 = Core.ClampElapsed(T, T + 4, 5)
check("clamp: 4 s untouched", s2 == T and c2 == false)
local s3, c3 = Core.ClampElapsed(0 / 0, T + 4, 5)
check("clamp: NaN t0 -> zero span", s3 == T + 4 and c3 == false)
local s4 = Core.ClampElapsed(T + 5, T + 4, 5)
check("clamp: t0 after t1 -> zero span", s4 == T + 4)

--.. TotalsChanged
check("totals: equal -> unchanged", not Core.TotalsChanged(10, 10))
check("totals: zero/zero -> unchanged", not Core.TotalsChanged(0, 0))
check("totals: 1e-9 relative -> unchanged", not Core.TotalsChanged(1e6, 1e6 + 1e-3))
check("totals: 1e-3 relative -> changed", Core.TotalsChanged(10, 10.01))
check("totals: 0 -> small -> changed", Core.TotalsChanged(0, 0.01))

--.. IsValidId
check("id: guid ok", Core.IsValidId(HttpService:GenerateGUID(false)))
check("id: empty / long / number rejected", not Core.IsValidId("") and not Core.IsValidId(string.rep("a", 65)) and not Core.IsValidId(5))

--.. public API before Init / Start: safe answers, never errors
local fakePlayer = {UserId = 42}
check("preinit: IsStarted false", IncomeService.IsStarted() == false)
check("preinit: GetThreatIncome nil", IncomeService.GetThreatIncome(fakePlayer) == nil)
local t0 = IncomeService.GetTotals(fakePlayer)
check("preinit: GetTotals zeros", t0.Total == 0 and t0.CucumberBase == 0 and t0.Cucumber == 0 and t0.Pet == 0)
check("preinit: FlushOwner false", IncomeService.FlushOwner(fakePlayer) == false)
check("preinit: GetCucumberRates nil", IncomeService.GetCucumberRates({}) == nil)
check("preinit: diag Producers 0", IncomeService.GetDiagnostics().Producers == 0)
local okCalls = pcall(function()
	IncomeService.Refresh(nil)
	IncomeService.SetPetProducer(fakePlayer, "p", nil, 1)
	IncomeService.RemovePetProducer("p")
	IncomeService.SettleOwner(fakePlayer)
end)
check("preinit: mutators are silent no-ops", okCalls)
local disconnect = IncomeService.OnTotalsChanged(function() end)
check("preinit: OnTotalsChanged returns a disconnect fn", type(disconnect) == "function" and pcall(disconnect))

--.. after Init (fake DataService, no Start): still not started, threat still nil
local fakeDS = {GetData = function() return nil end, IsLoaded = function() return false end, Increment = function() return false end}
local okInit, initErr = pcall(IncomeService.Init, {DataService = fakeDS})
check("init: ok with a table DataService", okInit, initErr)
check("init: IsStarted still false", IncomeService.IsStarted() == false)
check("init: GetThreatIncome still nil before Start", IncomeService.GetThreatIncome(fakePlayer) == nil)
check("init: GetTotals zeros", IncomeService.GetTotals(fakePlayer).Total == 0)
check("init: Refresh before Start no-op", pcall(IncomeService.Refresh, {}) and IncomeService.GetDiagnostics().Producers == 0)

local summary = ("WP-INCOME core: PASS %d / FAIL %d"):format(pass, fail)
if #failures > 0 then summary ..= ": " .. table.concat(failures, "; ") end
return summary
