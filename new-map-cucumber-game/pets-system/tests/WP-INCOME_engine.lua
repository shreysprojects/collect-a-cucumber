-- WP-INCOME engine: IncomeService.Core.NewEngine driven with plain-table fakes and a controlled clock
-- (2026-09-22). Read-only: no instances are created, nothing in the DataModel is touched.
local HttpService = game:GetService("HttpService")
local src = HttpService:GetAsync("http://127.0.0.1:8793/ServerStorage.IncomeService.lua")
local chunk, compileErr = loadstring(src)
if not chunk then return "WP-INCOME engine: PASS 0 / FAIL 1: compile " .. tostring(compileErr) end
local Core = chunk().Core

local pass, fail, failures = 0, 0, {}
local function check(name, cond, detail)
	if cond then
		pass += 1
	else
		fail += 1
		if #failures < 10 then table.insert(failures, name .. (detail ~= nil and (" [" .. tostring(detail) .. "]") or "")) end
	end
end
local function near(a, b, eps)
	return type(a) == "number" and type(b) == "number" and math.abs(a - b) <= (eps or 1e-9) * math.max(1, math.abs(a), math.abs(b))
end

local T0 = 1000
local FAR = T0 + 10000

--..Fake world..--
local function World()
	local W = {now = T0, data = {}, closing = {}, byUid = {}, deferred = {}, fired = {}, cps = {}, credits = 0,
		watches = 0, disconnects = 0, warns = 0}
	W.DataService = {
		GetData = function(p) return W.data[p] end,
		IsLoaded = function(p) return W.data[p] ~= nil end,
		IsClosing = function(p) return W.closing[p] == true end,
		Increment = function(p, key, delta, quiet)
			local d = W.data[p]
			if W.failCredit or not d or d[key] == nil then return false end
			d[key] += delta
			W.credits += 1
			W.lastQuiet = quiet
			return true
		end,
	}
	W.env = {
		Clock = function() return W.now end,
		DataService = W.DataService,
		ModifiersOf = function(model) return model.mods end,
		BaseRateOf = function(model) return model.base end,
		IsTagged = function(model) return model.tagged == true end,
		InWorld = function(model) return model.inWorld == true end,
		OwnerIdOf = function(model) return model.attrs.Owner end,
		PlayerByUserId = function(uid) return W.byUid[uid] end,
		IsPresent = function(p) return type(p) == "table" and p.present == true end,
		SetAttribute = function(model, name, value) model.attrs[name] = value end,
		WriteCashPerSec = function(p, total) W.cps[p] = total end,
		Watch = function()
			W.watches += 1
			return {{Disconnect = function() W.disconnects += 1 end}}
		end,
		Defer = function(fn) table.insert(W.deferred, fn) end,
		OnTotals = function(p, totals) table.insert(W.fired, {Player = p, Totals = totals}) end,
		Warn = function() W.warns += 1 end,
		RateCap = 2,
		MaxCatchup = 5,
	}
	W.E = Core.NewEngine(W.env)
	return W
end
local function Flush(W)
	for _ = 1, 10 do
		if #W.deferred == 0 then return end
		local queue = W.deferred
		W.deferred = {}
		for _, fn in ipairs(queue) do fn() end
	end
end
local function NewPlayer(W, uid)
	local p = {UserId = uid, present = true}
	W.data[p] = {Cash = 0}
	W.byUid[uid] = p
	return p
end
local function Leave(W, p)
	p.present = false
	if W.byUid[p.UserId] == p then W.byUid[p.UserId] = nil end
end
local function NewCucumber(owner, base, mods)
	return {attrs = {Owner = owner}, base = base, mods = mods or {}, tagged = true, inWorld = true}
end
local function Place(W, model, t) -- the tag-added path (Refresh registers a tagged model)
	W.now = t
	W.E.Refresh(model, t)
end
local function Tick(W, t)
	W.now = t
	Flush(W)
	local batch = W.E.Tick(t)
	Flush(W)
	return batch
end
local function Cash(W, p) return W.data[p] and W.data[p].Cash end

--..1. $0.50/s pays exactly 30 over 60 regular ticks (cucumber AND pet, one credit per tick)..--
do
	local W = World()
	local A = NewPlayer(W, 1)
	Place(W, NewCucumber(1, 0.5), T0)
	W.E.SetPetProducer(A, "pet-1", {inWorld = true, attrs = {}}, 0.5, T0)
	for i = 1, 60 do Tick(W, T0 + i) end
	local d = W.E.GetDiagnostics()
	check("steady: cucumber pays 30", near(d.PaidCucumberCash, 30), d.PaidCucumberCash)
	check("steady: pet pays 30", near(d.PaidPetCash, 30), d.PaidPetCash)
	check("steady: Cash 60", near(Cash(W, A), 60), Cash(W, A))
	check("steady: one Increment per owner per tick", W.credits == 60, W.credits)
	check("steady: Increment is quiet", W.lastQuiet == true)
	check("steady: no catch-up clamps", d.CatchupClamps == 0)
end

--..2. irregular ticks (0.9 / 1.1 / 1.7 / 0.3 ...) still pay exactly 30 per producer over 60 s..--
do
	local W = World()
	local A = NewPlayer(W, 1)
	Place(W, NewCucumber(1, 0.5), T0)
	W.E.SetPetProducer(A, "pet-1", {inWorld = true, attrs = {}}, 0.5, T0)
	local steps = {0.9, 1.1, 1.7, 0.3}
	local t = T0
	for i = 1, 60 do
		t += steps[(i - 1) % 4 + 1]
		Tick(W, t)
	end
	local d = W.E.GetDiagnostics()
	check("irregular: 60 s elapsed", near(t - T0, 60, 1e-12), t - T0)
	check("irregular: cucumber 30", near(d.PaidCucumberCash, 30), d.PaidCucumberCash)
	check("irregular: pet 30", near(d.PaidPetCash, 30), d.PaidPetCash)
end

--..3. buff maths on base 10 (+ Rate / BaseRate attributes)..--
local function OneTick(mods)
	local W = World()
	local A = NewPlayer(W, 1)
	local c = NewCucumber(1, 10, mods)
	Place(W, c, T0)
	Tick(W, T0 + 1)
	return Cash(W, A), c
end
local YIELD = {Kind = "Yield", Mult = 1.5, ExpiresAt = FAR}
local HASTE = {Kind = "Haste", Mult = 1.25, ExpiresAt = FAR}
check("buff: none 10", near(OneTick({}), 10))
check("buff: Yield 15", near(OneTick({YIELD}), 15))
check("buff: Haste 12.5", near(OneTick({HASTE}), 12.5))
local both, cBoth = OneTick({YIELD, HASTE})
check("buff: both 18.75", near(both, 18.75), both)
check("buff: cap 2.0 -> 20", near(OneTick({YIELD, {Kind = "Other", Mult = 1.5, ExpiresAt = FAR}}), 20))
check("buff: Rate attr = effective 18.75", near(cBoth.attrs.Rate, 18.75), cBoth.attrs.Rate)
check("buff: BaseRate attr = 10", near(cBoth.attrs.BaseRate, 10), cBoth.attrs.BaseRate)

--..4. split at modifier expiry, Rate restamped after the tick..--
do
	local W = World()
	local A = NewPlayer(W, 1)
	local c = NewCucumber(1, 10, {{Kind = "Yield", Mult = 1.5, ExpiresAt = T0 + 0.4}})
	Place(W, c, T0)
	check("expiry: Rate 15 while live", near(c.attrs.Rate, 15), c.attrs.Rate)
	Tick(W, T0 + 1)
	check("expiry: 15 x 0.4 + 10 x 0.6 = 12", near(Cash(W, A), 12), Cash(W, A))
	check("expiry: Rate back to 10 after paying", near(c.attrs.Rate, 10), c.attrs.Rate)
	Tick(W, T0 + 2)
	check("expiry: next tick plain 10", near(Cash(W, A), 22), Cash(W, A))
	-- a scheduler that wakes 3 s late still splits at the expiry
	local W2 = World()
	local A2 = NewPlayer(W2, 1)
	Place(W2, NewCucumber(1, 10, {{Kind = "Yield", Mult = 1.5, ExpiresAt = T0 + 0.4}}), T0)
	Tick(W2, T0 + 3)
	check("expiry: late wake 32 (never the expired rate for the whole span)", near(Cash(W2, A2), 32), Cash(W2, A2))
end

--..5. 5 s catch-up clamp + diagnostic..--
do
	local W = World()
	local A = NewPlayer(W, 1)
	Place(W, NewCucumber(1, 10), T0)
	Tick(W, T0 + 8)
	check("clamp: an 8 s stall pays 5 s = 50", near(Cash(W, A), 50), Cash(W, A))
	check("clamp: CatchupClamps 1", W.E.GetDiagnostics().CatchupClamps == 1)
end

--..6. a producer added mid-second earns only its span..--
do
	local W = World()
	local A = NewPlayer(W, 1)
	Tick(W, T0)
	Place(W, NewCucumber(1, 10), T0 + 0.6)
	Tick(W, T0 + 1)
	check("mid-second add: 0.4 s = 4", near(Cash(W, A), 4), Cash(W, A))
	local pet = {inWorld = true, attrs = {}}
	W.E.SetPetProducer(A, "pet-late", pet, 2, T0 + 1.75)
	local b = Tick(W, T0 + 2)
	check("mid-second pet: 10 + 2 x 0.25", near(Cash(W, A), 4 + 10 + 0.5), Cash(W, A))
	check("mid-second pet popup 0.5", b.PetIds[1] == "pet-late" and b.PetModels[1] == pet and near(b.PetAmounts[1], 0.5))
end

--..7. settle-then-tick never double pays (state change settles into the ledger, one popup per tick)..--
do
	local W = World()
	local A = NewPlayer(W, 1)
	local c = NewCucumber(1, 10)
	Place(W, c, T0)
	Tick(W, T0 + 1)
	W.now = T0 + 1.5
	W.E.Refresh(c, T0 + 1.5)
	check("settle: nothing credited mid-second", near(Cash(W, A), 10), Cash(W, A))
	check("settle: ledger holds 5", near(W.E.Owners[1].LedgerCucumber, 5), W.E.Owners[1].LedgerCucumber)
	local b = Tick(W, T0 + 2)
	check("settle: tick credits 20 total", near(Cash(W, A), 20), Cash(W, A))
	check("settle: one popup = the whole second (10)", #b.CucumberModels == 1 and b.CucumberModels[1] == c and near(b.CucumberAmounts[1], 10))
	W.E.SettleOwner(A, T0 + 2.5)
	Tick(W, T0 + 3)
	check("settle: SettleOwner then tick = 30", near(Cash(W, A), 30), Cash(W, A))
	-- same-instant double settle pays nothing extra
	W.E.Refresh(c, T0 + 3)
	W.E.Refresh(c, T0 + 3)
	Tick(W, T0 + 3)
	check("settle: repeated same-instant settles pay 0", near(Cash(W, A), 30), Cash(W, A))
	-- an older `now` never moves the clock back
	W.E.Refresh(c, T0 + 2)
	Tick(W, T0 + 4)
	check("settle: stale now ignored, tick pays 10", near(Cash(W, A), 40), Cash(W, A))
end

--..8. producer removed mid-second: its span is paid exactly once, no popup, listeners disconnected..--
do
	local W = World()
	local A = NewPlayer(W, 1)
	local c = NewCucumber(1, 10)
	Place(W, c, T0)
	Tick(W, T0 + 1)
	c.tagged, c.inWorld = false, false
	W.E.TagRemoved(c, T0 + 1.4)
	local b = Tick(W, T0 + 2)
	check("remove: 10 + 4", near(Cash(W, A), 14), Cash(W, A))
	check("remove: no popup for a removed model", #b.CucumberModels == 0)
	Tick(W, T0 + 3)
	check("remove: nothing more", near(Cash(W, A), 14), Cash(W, A))
	check("remove: producer dropped", W.E.GetDiagnostics().Producers == 0)
	check("remove: attribute listeners disconnected", W.disconnects == 1 and W.watches == 1)
	c.tagged, c.inWorld = true, true -- re-tag (RestoreCarry): registers again, one watcher set, no stacking
	Place(W, c, T0 + 3)
	Place(W, c, T0 + 3)
	check("retag: one registration, one watcher", W.watches == 2 and W.E.GetDiagnostics().Producers == 1)
end

--..9. totals: CucumberBase excludes modifiers and pets; ineligible producers excluded; CashPerSec = Total..--
do
	local W = World()
	local A = NewPlayer(W, 1)
	Place(W, NewCucumber(1, 10, {YIELD}), T0)
	local away = NewCucumber(1, 4)
	away.inWorld = false
	Place(W, away, T0)
	W.E.SetPetProducer(A, "p1", {inWorld = true, attrs = {}}, 0.5, T0)
	W.E.SetPetProducer(A, "p2", {inWorld = false, attrs = {}}, 0.25, T0)
	local t = W.E.GetTotals(A, T0)
	check("totals: CucumberBase 10", near(t.CucumberBase, 10), t.CucumberBase)
	check("totals: Cucumber 15", near(t.Cucumber, 15), t.Cucumber)
	check("totals: Pet 0.5", near(t.Pet, 0.5), t.Pet)
	check("totals: Total 15.5", near(t.Total, 15.5), t.Total)
	Tick(W, T0 + 1)
	check("totals: CashPerSec written = Total", near(W.cps[A], 15.5), W.cps[A])
	check("totals: rates query", near(select(1, W.E.GetCucumberRates(away, T0 + 1)), 4) and W.E.GetCucumberRates({}, T0) == nil)
	check("totals: unknown player zeros", W.E.GetTotals({UserId = 99}, T0).Total == 0 and W.E.GetTotals(nil, T0).Total == 0)
	check("totals: reserve / off-world pet earns 0", near(W.E.GetDiagnostics().PaidPetCash, 0.5))
end

--..10. closing owner: the tick skips it, FlushOwner credits ledger + span once, second call 0..--
do
	local W = World()
	local A = NewPlayer(W, 1)
	local c = NewCucumber(1, 10)
	Place(W, c, T0)
	Tick(W, T0 + 1)
	W.now = T0 + 1.5
	W.E.Refresh(c, T0 + 1.5) -- ledger 5
	W.closing[A] = true
	Tick(W, T0 + 2)
	check("closing: regular tick does not credit", near(Cash(W, A), 10), Cash(W, A))
	check("closing: flush ok", W.E.FlushOwner(A, T0 + 2.2) == true)
	check("closing: flush credits 5 + 7 once", near(Cash(W, A), 22), Cash(W, A))
	check("closing: second flush ok", W.E.FlushOwner(A, T0 + 3) == true)
	check("closing: second flush credits 0", near(Cash(W, A), 22), Cash(W, A))
	check("closing: state Flushed, Flushes 1", W.E.Owners[1].State == "Flushed" and W.E.GetDiagnostics().Flushes == 1)
	W.closing[A] = nil
	Tick(W, T0 + 4)
	check("flushed: later ticks never credit a flushed owner", near(Cash(W, A), 22), Cash(W, A))
	local late0 = W.E.GetDiagnostics().LateSettles
	W.E.Refresh(c, T0 + 4.5)
	c.tagged, c.inWorld = false, false
	W.E.TagRemoved(c, T0 + 5)
	check("flushed: late settlements discarded (LateSettles)", W.E.GetDiagnostics().LateSettles > late0)
	check("flushed: no ledger re-created", W.E.Owners[1].State == "Flushed" and W.E.Owners[1].LedgerCucumber == 0)
	check("flushed: cash unchanged", near(Cash(W, A), 22), Cash(W, A))
	W.data[A] = nil -- profile gone (Forget)
	check("flush: no data -> false, no credit", W.E.FlushOwner(A, T0 + 6) == false)
end

--..11. PlayerRemoving: flush (if data) then Forgotten; later settlements dropped; entry pruned..--
do
	local W = World()
	local A = NewPlayer(W, 1)
	local c = NewCucumber(1, 10)
	Place(W, c, T0)
	Tick(W, T0 + 1)
	Leave(W, A)
	W.E.PlayerRemoving(A, T0 + 1.5)
	check("leave: flush credited the half second", near(Cash(W, A), 15), Cash(W, A))
	check("leave: Forgotten", W.E.Owners[1].State == "Forgotten")
	local late0 = W.E.GetDiagnostics().LateSettles
	c.tagged, c.inWorld = false, false
	W.E.TagRemoved(c, T0 + 1.9) -- the deferred plot release
	check("leave: late removal counted LateSettles", W.E.GetDiagnostics().LateSettles == late0 + 1)
	check("leave: nothing stored", W.E.Owners[1].LedgerCucumber == 0 and near(Cash(W, A), 15))
	Tick(W, T0 + 2)
	check("leave: departed entry pruned", W.E.Owners[1] == nil)
	W.E.RemovePetProducer("never-registered", T0 + 2)
	check("leave: unknown pet removal no-op", W.E.GetDiagnostics().Producers == 0)
	-- rejoin: a new Player object of the same user gets a fresh Live ledger
	local A2 = NewPlayer(W, 1)
	Place(W, NewCucumber(1, 10), T0 + 10)
	Tick(W, T0 + 11)
	check("rejoin: new session earns", near(Cash(W, A2), 10), Cash(W, A2))
	check("rejoin: old profile untouched", near(Cash(W, A), 15), Cash(W, A))
end

--..12. unloaded owner: no credit, late settlement dropped, no ledger..--
do
	local W = World()
	local A = NewPlayer(W, 1)
	W.data[A] = nil -- present, profile not loaded
	local c = NewCucumber(1, 10)
	Place(W, c, T0)
	Tick(W, T0 + 1)
	c.tagged, c.inWorld = false, false
	W.E.TagRemoved(c, T0 + 1.5)
	local entry = W.E.Owners[1]
	check("unloaded: late settle counted", W.E.GetDiagnostics().LateSettles == 1, W.E.GetDiagnostics().LateSettles)
	check("unloaded: no ledger stored", entry == nil or (entry.LedgerCucumber == 0 and entry.LedgerPet == 0))
	-- an owner with no player at all: producer clock advances, no back pay when the player arrives
	local W2 = World()
	Place(W2, NewCucumber(9, 10), T0)
	Tick(W2, T0 + 1)
	Tick(W2, T0 + 10)
	local B = NewPlayer(W2, 9)
	Tick(W2, T0 + 10.5)
	check("absent owner: only the span after arrival is paid", near(Cash(W2, B), 5), Cash(W2, B))
	check("absent owner: no catch-up clamp", W2.E.GetDiagnostics().CatchupClamps == 0)
end

--..13. profile reset: ledger dropped, clocks restarted, a late removal settles 0..--
do
	local W = World()
	local A = NewPlayer(W, 1)
	local c = NewCucumber(1, 10)
	Place(W, c, T0)
	Tick(W, T0 + 1)
	W.now = T0 + 1.2
	W.E.Refresh(c, T0 + 1.2) -- ledger 2
	W.data[A].Cash = 0 -- DataService.ResetProfile
	W.E.ProfileReset(A, T0 + 1.5)
	check("reset: ledger dropped", W.E.Owners[1].LedgerCucumber == 0)
	c.tagged, c.inWorld = false, false
	W.E.TagRemoved(c, T0 + 1.5) -- BaseSaveAPI.Reset's deferred tag removal
	Tick(W, T0 + 2)
	check("reset: fresh profile gets 0", Cash(W, A) == 0, Cash(W, A))
	check("reset: no LateSettles", W.E.GetDiagnostics().LateSettles == 0)
end

--..14. Owner attribute change settles to the OLD owner, then re-keys..--
do
	local W = World()
	local A = NewPlayer(W, 1)
	local B = NewPlayer(W, 2)
	local c = NewCucumber(1, 10)
	Place(W, c, T0)
	Tick(W, T0 + 1)
	c.attrs.Owner = 2
	W.E.OwnerChanged(c, T0 + 1.3)
	check("owner change: old owner's ledger 3", near(W.E.Owners[1].LedgerCucumber, 3), W.E.Owners[1].LedgerCucumber)
	local b = Tick(W, T0 + 2)
	check("owner change: A 13", near(Cash(W, A), 13), Cash(W, A))
	check("owner change: B 7", near(Cash(W, B), 7), Cash(W, B))
	check("owner change: popup follows the new owner (7)", #b.CucumberModels == 1 and near(b.CucumberAmounts[1], 7))
	c.attrs.Owner = nil
	W.E.OwnerChanged(c, T0 + 2.5)
	Tick(W, T0 + 3)
	check("owner change: ownerless cucumber pays nobody", near(Cash(W, B), 12), Cash(W, B))
	c.attrs.Owner = 1
	W.E.OwnerChanged(c, T0 + 3.4)
	Tick(W, T0 + 4)
	check("owner change: back to A, no back pay", near(Cash(W, A), 13 + 6), Cash(W, A))
end

--..15. OnTotalsChanged fires on real changes only..--
do
	local W = World()
	local A = NewPlayer(W, 1)
	local c = NewCucumber(1, 10)
	Place(W, c, T0)
	Tick(W, T0 + 1)
	check("totals event: first totals fire once", #W.fired == 1, #W.fired)
	Tick(W, T0 + 2)
	Tick(W, T0 + 3)
	check("totals event: no fire on unchanged ticks", #W.fired == 1, #W.fired)
	c.mods = {{Kind = "Yield", Mult = 1.5, ExpiresAt = T0 + 5.5}}
	W.now = T0 + 3.5
	W.E.Refresh(c, T0 + 3.5)
	Tick(W, T0 + 4)
	check("totals event: buff -> one fire", #W.fired == 2, #W.fired)
	local last = W.fired[#W.fired].Totals
	check("totals event: payload Total 15 / CucumberBase 10", near(last.Total, 15) and near(last.CucumberBase, 10))
	check("totals event: player passed", W.fired[#W.fired].Player == A)
	Tick(W, T0 + 5)
	check("totals event: unchanged tick", #W.fired == 2, #W.fired)
	Tick(W, T0 + 6)
	check("totals event: expiry -> one fire back to 10", #W.fired == 3 and near(W.fired[3].Totals.Total, 10), #W.fired)
	Tick(W, T0 + 7)
	check("totals event: stable afterwards", #W.fired == 3, #W.fired)
	check("totals event: paid 10+10+10 + (15x0.5+10x0.5) + 15 + (15x0.5+10x0.5) + 10", near(Cash(W, A), 30 + 12.5 + 15 + 12.5 + 10), Cash(W, A))
end

--..16. credit failure: no popups, cash kept for the next tick..--
do
	local W = World()
	local A = NewPlayer(W, 1)
	Place(W, NewCucumber(1, 10), T0)
	W.failCredit = true
	local b = Tick(W, T0 + 1)
	check("credit fail: no popups", #b.CucumberModels == 0)
	check("credit fail: counted", W.E.GetDiagnostics().CreditFailures == 1)
	W.failCredit = false
	local b2 = Tick(W, T0 + 2)
	check("credit fail: retried next tick (20)", near(Cash(W, A), 20), Cash(W, A))
	check("credit fail: popup only for the credited second", near(b2.CucumberAmounts[1], 10))
end

--..17. pet producers: replace settles first, invalid rate -> 0 + diag, remove mid-second..--
do
	local W = World()
	local A = NewPlayer(W, 1)
	local pm = {inWorld = true, attrs = {}}
	W.E.SetPetProducer(A, "q", pm, 2, T0)
	W.E.SetPetProducer(A, "q", pm, 4, T0 + 0.5)
	Tick(W, T0 + 1)
	check("pet: rate change settles the old rate first (1 + 2)", near(Cash(W, A), 3), Cash(W, A))
	W.E.RemovePetProducer("q", T0 + 1.25)
	local b = Tick(W, T0 + 2)
	check("pet: removal pays its span once (1)", near(Cash(W, A), 4), Cash(W, A))
	check("pet: no popup after removal", #b.PetModels == 0)
	W.E.SetPetProducer(A, "bad", pm, 0 / 0, T0 + 2)
	check("pet: NaN rate -> InvalidRates", W.E.GetDiagnostics().InvalidRates == 1)
	W.E.SetPetProducer(A, "neg", pm, -5, T0 + 2)
	Tick(W, T0 + 3)
	check("pet: invalid rates earn 0", near(Cash(W, A), 4), Cash(W, A))
	check("pet: bad ids refused", W.E.SetPetProducer(A, "", pm, 1, T0) == false and W.E.SetPetProducer(A, string.rep("x", 65), pm, 1, T0) == false)
	check("pet: bad player refused", W.E.SetPetProducer(nil, "z", pm, 1, T0) == false and W.E.SetPetProducer(5, "z", pm, 1, T0) == false)
end

--..18. garbage inputs never error and never pay non-finite cash..--
do
	local W = World()
	local A = NewPlayer(W, 1)
	local weird = NewCucumber(1, 0 / 0, {{Kind = "Yield", Mult = math.huge, ExpiresAt = FAR}, "junk", {Mult = 1.5}})
	local okGarbage = pcall(function()
		Place(W, weird, T0)
		W.E.Refresh(nil, T0)
		W.E.TagRemoved({}, T0)
		W.E.OwnerChanged({}, T0)
		W.E.SettleOwner(nil, T0)
		W.E.ProfileReset(nil, T0)
		W.E.PlayerRemoving(nil, T0)
		Tick(W, T0 + 1)
	end)
	check("garbage: no error", okGarbage)
	check("garbage: NaN base rate paid 0 (finite cash)", Cash(W, A) == 0, Cash(W, A))
	check("garbage: InvalidRates counted", W.E.GetDiagnostics().InvalidRates >= 2, W.E.GetDiagnostics().InvalidRates)
	local thrower = NewCucumber(1, 10)
	W.env.ModifiersOf = function() error("boom") end
	local okThrow = pcall(Place, W, thrower, T0 + 1)
	Tick(W, T0 + 2)
	check("garbage: a throwing ModifiersOf is contained", okThrow and near(Cash(W, A), 10), Cash(W, A))
end

--..19. reset residue (S3 open issue 1, 2026-09-22 fix): producers registered before a ProfileReset settle NOTHING
--..    into the fresh profile - not even the sub-millisecond gap before a deferred TagRemoved - until a tick finds
--..    them eligible (then they re-join from that tick) or they are re-registered / re-keyed..--
do
	-- (a) the S3 case: BaseSaveAPI.Reset destroys the cucumber, its tag signal is deferred past ProfileReset
	local W = World()
	local A = NewPlayer(W, 1)
	local big = NewCucumber(1, 40200)
	local keep = NewCucumber(1, 10) -- a pre-reset producer still standing after the reset
	Place(W, big, T0)
	Place(W, keep, T0)
	W.E.SetPetProducer(A, "pet-r", {inWorld = true, attrs = {}}, 2, T0)
	Tick(W, T0 + 1)
	check("residue: pre-reset tick 40212", near(Cash(W, A), 40212), Cash(W, A))
	big.inWorld = false -- destroyed by ClearPlaced
	W.E.RemovePetProducer("pet-r", T0 + 1.2) -- DetachPlot "Reset" (synchronous, into the old ledger)
	W.data[A].Cash = 0 -- DataService.ResetProfile
	W.E.ProfileReset(A, T0 + 1.5)
	check("residue: old ledger dropped", W.E.Owners[1].LedgerCucumber == 0 and W.E.Owners[1].LedgerPet == 0)
	big.tagged = false
	W.now = T0 + 1.5003
	W.E.TagRemoved(big, T0 + 1.5003) -- the deferred TagRemoved, 0.3 ms later (12.06 at 40.2K/s before the fix)
	check("residue: late removal stores nothing", W.E.Owners[1].LedgerCucumber == 0, W.E.Owners[1].LedgerCucumber)
	check("residue: discard counted (LateSettles 1)", W.E.GetDiagnostics().LateSettles == 1, W.E.GetDiagnostics().LateSettles)
	W.now = T0 + 1.8
	W.E.Refresh(keep, T0 + 1.8) -- a held producer's state-change settle is discarded too
	check("residue: held Refresh stores nothing", W.E.Owners[1].LedgerCucumber == 0, W.E.Owners[1].LedgerCucumber)
	local pm = {inWorld = true, attrs = {}}
	W.E.SetPetProducer(A, "pet-new", pm, 4, T0 + 1.75) -- registered after the reset: earns normally
	local b = Tick(W, T0 + 2)
	check("residue: first tick pays only the post-reset pet (1)", near(Cash(W, A), 1), Cash(W, A))
	check("residue: no popup for the held cucumber", #b.CucumberModels == 0, #b.CucumberModels)
	check("residue: pet popup 1", #b.PetIds == 1 and b.PetIds[1] == "pet-new" and near(b.PetAmounts[1], 1))
	check("residue: held survivor re-joins in the totals (CashPerSec 14)", near(W.cps[A], 14), W.cps[A])
	check("residue: LateSettles 3 (TagRemoved + Refresh + tick)", W.E.GetDiagnostics().LateSettles == 3, W.E.GetDiagnostics().LateSettles)
	Tick(W, T0 + 3)
	check("residue: survivor earns again from the adopting tick (1 + 14)", near(Cash(W, A), 15), Cash(W, A))
	check("residue: fresh profile never got old income", near(W.E.GetDiagnostics().PaidCucumberCash, 40210 + 10), W.E.GetDiagnostics().PaidCucumberCash)

	-- (b) held while off-world: stays held through ineligible ticks, re-joins at its first eligible tick
	local W2 = World()
	local B = NewPlayer(W2, 1)
	local g = NewCucumber(1, 5)
	Place(W2, g, T0)
	Tick(W2, T0 + 1)
	g.inWorld = false
	W2.data[B].Cash = 0
	W2.E.ProfileReset(B, T0 + 1.5)
	Tick(W2, T0 + 2)
	g.inWorld = true
	Tick(W2, T0 + 3)
	check("held off-world: nothing until adopted", Cash(W2, B) == 0, Cash(W2, B))
	Tick(W2, T0 + 4)
	check("held off-world: earns after its first eligible tick", near(Cash(W2, B), 5), Cash(W2, B))

	-- (c) FlushOwner (leave right after a reset) credits post-reset producers only
	local W3 = World()
	local C = NewPlayer(W3, 1)
	Place(W3, NewCucumber(1, 10), T0)
	Tick(W3, T0 + 1)
	W3.data[C].Cash = 0
	W3.E.ProfileReset(C, T0 + 1.5)
	W3.E.SetPetProducer(C, "pf", {inWorld = true, attrs = {}}, 2, T0 + 1.6)
	W3.closing[C] = true
	check("reset flush: ok", W3.E.FlushOwner(C, T0 + 1.9) == true)
	check("reset flush: only the post-reset pet (0.6)", near(Cash(W3, C), 0.6), Cash(W3, C))
	check("reset flush: held cucumber discarded", W3.E.GetDiagnostics().LateSettles == 1, W3.E.GetDiagnostics().LateSettles)

	-- (d) re-key / re-registration ends the hold; the span before it still goes nowhere
	local W4 = World()
	local D = NewPlayer(W4, 1)
	local E2 = NewPlayer(W4, 2)
	local c4 = NewCucumber(1, 10)
	Place(W4, c4, T0)
	local ph = {inWorld = true, attrs = {}}
	W4.E.SetPetProducer(D, "ph", ph, 2, T0)
	Tick(W4, T0 + 1)
	W4.data[D].Cash = 0
	W4.E.ProfileReset(D, T0 + 1.5)
	c4.attrs.Owner = 2
	W4.E.OwnerChanged(c4, T0 + 1.6) -- [1.5, 1.6] of the reset owner: discarded
	W4.E.SetPetProducer(D, "ph", ph, 2, T0 + 1.7) -- PetService re-set after the reset: [1.5, 1.7] discarded
	Tick(W4, T0 + 2)
	check("re-key: new owner earns its span (4)", near(Cash(W4, E2), 4), Cash(W4, E2))
	check("re-register: pet earns from the re-set (0.6)", near(Cash(W4, D), 0.6), Cash(W4, D))
	check("re-key: both pre-reset spans counted", W4.E.GetDiagnostics().LateSettles == 2, W4.E.GetDiagnostics().LateSettles)
end

local summary = ("WP-INCOME engine: PASS %d / FAIL %d"):format(pass, fail)
if #failures > 0 then summary ..= ": " .. table.concat(failures, "; ") end
return summary
