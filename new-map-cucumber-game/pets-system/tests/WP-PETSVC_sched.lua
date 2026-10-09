-- WP-PETSVC scheduler / motion / PetState session tests (2026-09-22): PetService.Tick driven with an injected
-- clock over plain-table fakes. No instances, no Start().
local HttpService = game:GetService("HttpService")
local H = loadstring(HttpService:GetAsync("http://127.0.0.1:8795/WP-PETSVC_harness.lua"))()
local C = H.Checker("sched")
local BuildCatalog = require(game:GetService("ReplicatedStorage").Modules.BuildCatalog) -- live, read-only

local function RecOf(ctx, id)
	for _, r in ipairs(ctx.Data().Base.Pets) do if type(r) == "table" and r.Id == id then return r end end
	return nil
end
local function StatusOf(ctx, id)
	for _, v in ipairs(ctx.PetService.GetFullState(ctx.Player).Pets) do
		if v.Id == id then return v.Status end
	end
	return nil
end
local function ModelOf(ctx, id)
	local last
	for _, s in ipairs(ctx.Spawns) do if s.Id == id then last = s.Model end end
	return last
end
local function Advance(ctx, seconds, step)
	step = step or 0.25
	local n = math.floor(seconds / step + 0.5)
	for _ = 1, n do
		ctx.T.Now += step
		ctx.PetService.Tick(ctx.T.Now)
	end
end

--..I: ability countdowns..--
C.Run("ability", function()
	local fail = {Wolf = true}
	local ctx = H.Setup({
		Pets = {H.PetRec("c1", "Cat", {AbilityRemaining = 12}), H.PetRec("d1", "Dog"), H.PetRec("f1", "Fox", {AbilityRemaining = 5}),
			H.PetRec("x1", "Wolf", {AbilityRemaining = 20}), H.PetRec("b1", "Bunny", {AbilityRemaining = 7})},
		Roster = {"c1", "d1", "x1", "b1"}, SpawnFail = fail,
	})
	local PS, P = ctx.PetService, ctx.Player
	PS.EnsureProfileState(P)
	PS.AttachPlot(P, ctx.Plot)
	C.Eq(StatusOf(ctx, "x1"), "Unavailable", "failed spawn -> Unavailable (kept in roster)")
	C.Check(PS.GetDiagnostics().SpawnFailures >= 1, "SpawnFailures diag")
	C.Check(ctx.Income.Producers.x1 == nil, "no producer for an unavailable pet")
	local pending = PS.GrantFromEgg(P, {EggName = "Basic"}, "Cat")
	PS.Tick(ctx.T.Now) -- scheduler clocks start
	Advance(ctx, 11.75)
	C.Eq(PS.GetDiagnostics().Rolls, 0, "no roll before 12 s (no join roll)")
	Advance(ctx, 0.25)
	C.Eq(PS.GetDiagnostics().Rolls, 1, "Remaining 12 -> the roll lands at 12 s")
	C.Eq(RecOf(ctx, "c1").AbilityRemaining, 60, "reset to 60 after the roll")
	C.Eq(RecOf(ctx, "d1").AbilityRemaining, 48, "Guard pet counted down 12 s")
	C.Eq(RecOf(ctx, "f1").AbilityRemaining, 5, "reserve does not tick")
	C.Eq(RecOf(ctx, "x1").AbilityRemaining, 20, "unavailable does not tick")
	C.Eq(RecOf(ctx, "b1").AbilityRemaining, 7, "fighter (None) has no countdown")
	C.Eq(RecOf(ctx, pending.Id).AbilityRemaining, 60, "presentation-pending does not tick")
	P:SetAttribute("BaseRestored", nil)
	Advance(ctx, 1)
	C.Eq(RecOf(ctx, "d1").AbilityRemaining, 48, "no countdown before BaseRestored")
	P:SetAttribute("BaseRestored", true)
	local rolls = PS.GetDiagnostics().Rolls
	ctx.T.Now += 30 -- hitch
	PS.Tick(ctx.T.Now)
	C.Eq(RecOf(ctx, "d1").AbilityRemaining, 43, "a 30 s hitch counts 5 s")
	C.Eq(PS.GetDiagnostics().Rolls, rolls, "no burst after the hitch")
	--.. forced proc goes to PetBuffService.Grant with the pet's logical position
	C.Check(PS.DevSetAbilityRemaining(P, "c1", 0.1) and PS.DevForceProc(P, "c1"), "dev helpers (Studio)")
	Advance(ctx, 0.25)
	local g = ctx.Buffs.Grants[#ctx.Buffs.Grants]
	C.Check(g and g.Ability == "Yield" and g.Source.PetId == "c1" and g.Source.DisplayName == "Cucumber Deer", "Grant(player, source, ability)")
	C.Check(g and typeof(g.Source.From) == "Vector3" and g.Now == ctx.T.Now and g.Player == P, "Grant From + now")
	C.Check(PS.GetDiagnostics().ProcSuccess >= 1, "ProcSuccess diag")
	ctx.Buffs.Result = "NoTarget"
	PS.DevSetAbilityRemaining(P, "c1", 0.1)
	PS.DevForceProc(P, "c1")
	Advance(ctx, 0.25)
	C.Check(PS.GetDiagnostics().ProcNoTarget >= 1, "NoTarget consumed the attempt")
	C.Eq(RecOf(ctx, "c1").AbilityRemaining, 60, "attempt consumed -> 60")
	--.. the unavailable pet comes back on the 30 s retry once its asset exists
	fail.Wolf = nil
	Advance(ctx, 30, 1)
	C.Eq(StatusOf(ctx, "x1"), "Active", "retry respawned the unavailable pet")
	C.Check(ctx.Income.Producers.x1 ~= nil, "producer after the retry")
	--.. frozen: countdowns stop
	PS.Freeze(P)
	local before = RecOf(ctx, "d1").AbilityRemaining
	Advance(ctx, 2)
	C.Eq(RecOf(ctx, "d1").AbilityRemaining, before, "frozen -> no countdown")
	--.. no PetBuffService: countdowns run, rolls are skipped
	local ctx2 = H.Setup({Pets = {H.PetRec("c1", "Cat", {AbilityRemaining = 0.5})}, Roster = {"c1"}, NoBuffs = true})
	ctx2.PetService.EnsureProfileState(ctx2.Player)
	ctx2.PetService.AttachPlot(ctx2.Player, ctx2.Plot)
	ctx2.PetService.DevForceProc(ctx2.Player, "c1")
	ctx2.PetService.Tick(ctx2.T.Now)
	Advance(ctx2, 0.5)
	C.Eq(ctx2.PetService.GetDiagnostics().ProcSkipped, 1, "no buff service -> skipped roll")
end)

--..P: roaming = one shared planner, segments start in the future, server == client sample..--
C.Run("roam", function()
	local ctx = H.Setup({Pets = {H.PetRec("c1", "Cat"), H.PetRec("d1", "Dog")}, Roster = {"c1", "d1"}})
	local PS, P = ctx.PetService, ctx.Player
	local Motion = ctx.Fakes.PetMotion
	PS.EnsureProfileState(P)
	PS.AttachPlot(P, ctx.Plot)
	PS.Tick(ctx.T.Now)
	local m = ModelOf(ctx, "c1")
	local lastSeq, publishes, badLead, outside, mismatch = m.Attrs.RoamSeq, 0, 0, 0, 0
	for _ = 1, 150 do -- 30 s at 0.2 s
		ctx.T.Now += 0.2
		PS.Tick(ctx.T.Now)
		local a = m.Attrs
		if a.RoamSeq ~= lastSeq then
			publishes += 1
			if a.RoamSeq ~= lastSeq + 1 then badLead += 100 end
			lastSeq = a.RoamSeq
			if a.RoamStart < ctx.T.Now + 0.3 - 1e-6 or a.RoamEnd < a.RoamStart then badLead += 1 end
			local rel = ctx.Plot.CFrame:PointToObjectSpace(a.RoamTo)
			if math.abs(rel.X) > 26 + 1e-6 or math.abs(rel.Z) > 26 + 1e-6 or a.RoamGroundY ~= 0.5 then outside += 1 end
		end
		local server = PS.GetLogicalPosition("c1", ctx.T.Now)
		local client = Motion.Sample(Motion.ReadSegment(m), ctx.T.Now)
		if not server or not client or (server - client).Magnitude > 1e-6 then mismatch += 1 end
	end
	C.Check(publishes >= 3, ("planner published legs (%d)"):format(publishes))
	C.Eq(badLead, 0, "every leg starts >= ROAM_LEAD ahead, RoamSeq +1")
	C.Eq(outside, 0, "every leg inside the inset bounds at the plot top")
	C.Eq(mismatch, 0, "server logical position == client sample of the attributes")
end)

--..K: SyncRecords..--
C.Run("sync", function()
	local ctx = H.Setup({Pets = {H.PetRec("c1", "Cat"), H.PetRec("f1", "Fox")}, Roster = {"c1"}})
	local PS, P = ctx.PetService, ctx.Player
	PS.EnsureProfileState(P)
	PS.AttachPlot(P, ctx.Plot)
	PS.Tick(ctx.T.Now)
	Advance(ctx, 5, 0.2)
	PS.SyncRecords(P)
	local pos = RecOf(ctx, "c1").Pos
	C.Check(type(pos) == "table" and pos[2] == 0 and #pos == 3, "Pos = {x, 0, z}")
	local backZ = BuildCatalog.BackZ(ctx.Plot)
	local anchor = ctx.Plot.CFrame * CFrame.new(0, ctx.Plot.Size.Y * 0.5, backZ)
	local world = anchor:PointToWorldSpace(Vector3.new(pos[1], 0, pos[3]))
	local logical = PS.GetLogicalPosition("c1", ctx.T.Now)
	C.Check(math.abs(world.X - logical.X) < 1e-4 and math.abs(world.Z - logical.Z) < 1e-4, "Pos is the back-edge-local logical position")
	C.Check(RecOf(ctx, "f1").Pos == nil, "reserve pet Pos untouched")
	--.. close phase: frozen + closing still writes
	ctx.DS.Closing[P] = true
	PS.Freeze(P)
	RecOf(ctx, "c1").Pos = nil
	PS.SyncRecords(P)
	C.Check(type(RecOf(ctx, "c1").Pos) == "table", "close phase: SyncRecords still writes")
	local ok = pcall(PS.SyncRecords, H.NewPlayer(9))
	C.Check(ok, "no data -> silent")
	--.. the record's position is where the pet comes back
	local ctx2 = H.Setup({Pets = {H.PetRec("c1", "Cat", {Pos = {pos[1], 7, pos[3]}})}, Roster = {"c1"}})
	ctx2.PetService.EnsureProfileState(ctx2.Player)
	ctx2.PetService.AttachPlot(ctx2.Player, ctx2.Plot)
	local back = ctx2.PetService.GetLogicalPosition("c1")
	C.Check(back and math.abs(back.X - logical.X) < 1e-4 and math.abs(back.Z - logical.Z) < 1e-4, "saved Pos -> same spot on attach")
end)

--..J: PetState payloads + session..--
C.Run("state", function()
	local ctx = H.Setup({Pets = {H.PetRec("c1", "Cat"), H.PetRec("d1", "Dog"), H.PetRec("u1", "Unicorn")}, Roster = {"c1"}})
	local PS, P = ctx.PetService, ctx.Player
	ctx.Data().Base.PetNoticePending = true
	PS.EnsureProfileState(P)
	PS.AttachPlot(P, ctx.Plot)
	C.Eq(#ctx.Sent, 0, "nothing pushed before the first GetState")
	PS.HandleRequest(P, {RequestId = "g1", Action = "GetState"})
	local full = ctx.LastSent()
	C.Check(full and full.Kind == "Full" and full.Revision == 1 and full.RequestId == "g1" and full.Generation == 1, "Full header")
	C.Check(full.Slots == 6 and #full.EquippedIds == 1 and full.EquippedIds[1] == "c1" and #full.Pets == 3, "Full roster + pets (unknown kept)")
	C.Check(full.Totals and full.Totals.Pet == 1.5 and full.Totals.Total == 11.5 and full.Totals.CucumberBase == 8, "Full totals")
	C.Check(full.CombatLocked == false and full.ServerTime == ctx.T.Now, "Full lock + time")
	C.Eq(full.Notice, ctx.Fakes.PetBalance.TEXT.MigrationNotice, "migration notice once")
	C.Check(ctx.Data().Base.PetNoticePending == nil, "notice flag removed")
	local okJson = pcall(HttpService.JSONEncode, HttpService, full)
	C.Check(okJson, "Full is JSON-safe")
	local v = full.Pets[1]
	C.Check(v.Id and v.Pet and v.DisplayName and v.Rarity and v.Material and v.Mutations and v.AcquiredAt and v.Status and v.AbilityRemaining and v.Stats, "PetView fields")
	PS.HandleRequest(P, {RequestId = "g2", Action = "GetState"})
	C.Check(ctx.LastSent().Notice == nil, "notice not repeated")
	PS.HandleRequest(P, {RequestId = "e1", Action = "Equip", PetId = "d1"})
	local d = ctx.LastSent()
	C.Check(d.Kind == "Delta" and d.RequestId == "e1" and d.Result.Ok == true and d.Result.Action == "Equip", "Equip reply")
	C.Check(d.BaseRevision == d.Revision - 1 and d.Revision == 3, "Delta revision chain")
	C.Check(d.EquippedIds and #d.EquippedIds == 2 and d.Totals ~= nil, "Delta roster + totals")
	local up
	for _, u in ipairs(d.Upserts or {}) do if u.Id == "d1" then up = u end end
	C.Check(up and up.Equipped == true and up.Status == "Active", "Delta upsert of the equipped pet")
	PS.HandleRequest(P, {RequestId = "e2", Action = "Equip", PetId = "nope"})
	d = ctx.LastSent()
	C.Check(d.Result.Ok == false and d.Result.Error == "NotOwned" and d.RequestId == "e2", "refusal reply")
	PS.HandleRequest(P, {RequestId = "b1", Action = "Delete"})
	d = ctx.LastSent()
	C.Check(d.Result.Error == "BadRequest" and d.RequestId == "b1", "bad action reply")
	PS.HandleRequest(P, {RequestId = 5, Action = "Equip", PetId = "d1"})
	d = ctx.LastSent()
	C.Check(d.Result.Error == "BadRequest" and d.RequestId == nil, "bad RequestId -> reply without id")
	C.Eq(PS.GetFullState(P).Revision, d.Revision, "GetFullState does not advance Revision")
	--.. rebuild: unsolicited Full, next revision; generation change
	local rev = d.Revision
	local copy = {}
	for i, r in ipairs(ctx.Data().Base.Pets) do copy[i] = r end
	ctx.Data().Base.Pets = copy
	PS.EnsureProfileState(P)
	local f2 = ctx.LastSent()
	C.Check(f2.Kind == "Full" and f2.Revision == rev + 1 and f2.RequestId == nil, "rebuild -> unsolicited Full, next Revision")
	ctx.DS.Gen[P] = 2
	PS.EnsureProfileState(P)
	local f3 = ctx.LastSent()
	C.Check(f3.Kind == "Full" and f3.Generation == 2 and f3.Revision == rev + 2, "generation change -> Full with the new Generation")
	local monotonic = true
	for i = 2, #ctx.Sent do
		local a, b = ctx.Sent[i - 1].Revision, ctx.Sent[i].Revision
		if a and b and b <= a then monotonic = false end
	end
	C.Check(monotonic, "Revision strictly increasing over the session")
	--.. totals: unrevisioned
	local before = #ctx.Sent
	PS.PushTotals(P, {Pet = 2, Cucumber = 3, CucumberBase = 3, Total = 5})
	PS.Tick(ctx.T.Now + 1)
	local t = ctx.Sent[#ctx.Sent]
	C.Check(#ctx.Sent == before + 1 and t.Kind == "Totals" and t.Totals.Total == 5 and t.Revision == nil, "Totals message, no Revision")
	PS.PushTotals(P, {Pet = 2, Cucumber = 3, CucumberBase = 3, Total = 6})
	PS.Tick(ctx.T.Now + 1.1)
	C.Eq(#ctx.Sent, before + 1, "Totals throttled to 1 per TOTALS_PUSH")
	--.. deferred deltas (roll/lock changes) coalesce into one message
	before = #ctx.Sent
	PS.DevSetAbilityRemaining(P, "c1", 30)
	ctx.T.Phase = "Night"
	PS.RefreshCombatLock(P)
	task.wait()
	local q = ctx.Sent[#ctx.Sent]
	C.Check(#ctx.Sent == before + 1 and q.Kind == "Delta" and q.CombatLocked == true, "one deferred Delta with CombatLocked")
	local c1
	for _, u in ipairs(q.Upserts or {}) do if u.Id == "c1" then c1 = u end end
	C.Check(c1 and c1.AbilityRemaining == 30, "deferred upsert carries the new countdown")
end)

--..limiters: live in Session, survive a rebuild, bounded replies..--
C.Run("limits", function()
	local ctx = H.Setup({Pets = {H.PetRec("c1", "Cat"), H.PetRec("d1", "Dog")}, Roster = {}})
	local PS, P = ctx.PetService, ctx.Player
	PS.EnsureProfileState(P)
	PS.AttachPlot(P, ctx.Plot)
	for i = 1, 3 do PS.HandleRequest(P, {RequestId = "g" .. i, Action = "GetState"}) end
	C.Eq(#ctx.Sent, 2, "GetState burst 2, third dropped silently")
	local copy = {}
	for i, r in ipairs(ctx.Data().Base.Pets) do copy[i] = r end
	ctx.Data().Base.Pets = copy
	PS.EnsureProfileState(P)
	C.Eq(#ctx.Sent, 3, "rebuild pushed a Full")
	PS.HandleRequest(P, {RequestId = "g4", Action = "GetState"})
	C.Eq(#ctx.Sent, 3, "limiter survived the rebuild (still empty)")
	local replies = 0
	for i = 1, 7 do
		local n = #ctx.Sent
		PS.HandleRequest(P, {RequestId = "e" .. i, Action = i % 2 == 0 and "Unequip" or "Equip", PetId = "d1"})
		if #ctx.Sent > n then replies += 1 end
	end
	C.Eq(replies, 6, "4 in limit + 2 RateLimited replies, then silence")
	local limited = 0
	for _, s in ipairs(ctx.Sent) do if s.Result and s.Result.Error == "RateLimited" then limited += 1 end end
	C.Eq(limited, 2, "RateLimited replies bounded")
	C.Check(PS.GetDiagnostics().DeniedRequests >= 4, "DeniedRequests diag")
	--.. a player without a profile still gets bounded answers
	local nobody = H.NewPlayer(2)
	PS.HandleRequest(nobody, {RequestId = "n1", Action = "GetState"})
	local f = ctx.LastSent()
	C.Check(f.Kind == "Full" and f.Result and f.Result.Error == "NotLoaded" and #f.Pets == 0, "GetState before load -> Full NotLoaded")
	PS.HandleRequest(nobody, {RequestId = "n2", Action = "Equip", PetId = "d1"})
	f = ctx.LastSent()
	C.Check(f.Kind == "Delta" and f.Result.Error == "NotLoaded" and f.RequestId == "n2", "roster action before load -> NotLoaded")
	PS.HandleRequest(nobody, "garbage")
	C.Check(ctx.LastSent().Result.Error == "BadRequest", "non-table request")
end)

return C.Summary()
