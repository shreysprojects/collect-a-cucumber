-- WP-PETSVC roster / grant / presentation tests (2026-09-22): the stateful API over plain-table fakes
-- (fake DataService, player, plot, spawner, IncomeService, PetBuffService). No instances, no Start().
local HttpService = game:GetService("HttpService")
local H = loadstring(HttpService:GetAsync("http://127.0.0.1:8795/WP-PETSVC_harness.lua"))()
local C = H.Checker("roster")

local function StatusOf(ctx, id)
	for _, v in ipairs(ctx.PetService.GetFullState(ctx.Player).Pets) do
		if v.Id == id then return v.Status end
	end
	return nil
end
local function RecOf(ctx, id)
	for _, r in ipairs(ctx.Data().Base.Pets) do if type(r) == "table" and r.Id == id then return r end end
	return nil
end
local function ModelOf(ctx, id)
	local last
	for _, s in ipairs(ctx.Spawns) do if s.Id == id then last = s.Model end end
	return last
end

--..A: ensure + attach..--
C.Run("attach", function()
	local ctx = H.Setup({
		Pets = {H.PetRec("c1", "Cat"), H.PetRec("d1", "Dog"), H.PetRec("b1", "Bunny"), H.PetRec("u1", "Unicorn"), H.PetRec("f1", "Fox")},
		Roster = {"c1", "d1"},
	})
	local PS, P = ctx.PetService, ctx.Player
	C.Check(PS.IsStarted() == false, "not started (tests never Start)")
	C.Check(PS.IsReady(P) == false, "not ready before EnsureProfileState")
	C.Check(PS.EnsureProfileState(P) == true, "EnsureProfileState ok")
	C.Check(PS.IsReady(P) == true, "ready")
	C.Eq(StatusOf(ctx, "c1"), "Idle", "roster pet Idle before attach")
	C.Eq(StatusOf(ctx, "b1"), "Reserve", "reserve")
	C.Eq(StatusOf(ctx, "u1"), "Invalid", "unknown species Invalid")
	C.Eq(PS.AttachPlot(P, ctx.Plot), 2, "2 roster pets spawned")
	C.Eq(ctx.SpawnCount(), 2, "spawner called twice")
	C.Eq(StatusOf(ctx, "c1"), "Active", "Active after attach")
	C.Check(ctx.Income.Producers.c1 == 0.5 and ctx.Income.Producers.d1 ~= nil and ctx.Income.Producers.b1 == nil, "producers for spawned roster pets only")
	local m = ModelOf(ctx, "c1")
	C.Check(m.Attrs.PetId == "c1" and m.Attrs.PetName == "Cat" and m.Attrs.Owner == 1 and m.Attrs.Plot == "Plot 1", "model identity attributes")
	C.Check(m.Attrs.Rate == 0.5 and m.Attrs.Ability == "Yield" and m.Attrs.RoamSeq == 1 and m.Attrs.Mutations == "", "stats + segment attributes")
	C.Check(typeof(m.Attrs.RoamTo) == "Vector3" and m.Attrs.RoamGroundY == 0.5, "segment at the plot top")
	C.Eq(PS.AttachPlot(P, ctx.Plot), 0, "attach again spawns nothing")
	C.Eq(ctx.SpawnCount(), 2, "still 2 models")
	local active = PS.GetActivePets()
	C.Eq(#active, 2, "2 active pets")
	C.Check(active[1].UserId == 1 and active[1].Plot == ctx.Plot and active[1].Stats ~= nil and active[1].Model ~= nil, "ActivePet shape")
	local pos = PS.GetLogicalPosition("c1")
	C.Check(typeof(pos) == "Vector3" and pos.Y == 0.5 and math.abs(pos.X - 100) <= 28 and math.abs(pos.Z - 50) <= 28, "logical position inside the plot")
	C.Check(PS.GetLogicalPosition("b1") == nil, "reserve has no position")
	C.Check(PS.GetLogicalPosition("c1", 5) == pos, "foreign clock ignored")
	local plot2 = H.NewPlot(99, "Plot 2")
	PS.DetachPlot(P, "Reload")
	C.Eq(PS.AttachPlot(P, plot2), 0, "a plot the player does not own is refused")
	C.Eq(StatusOf(ctx, "c1"), "Idle", "detached -> Idle")
	C.Check(ctx.Income.Producers.c1 == nil, "producer removed on detach")
	C.Check(ModelOf(ctx, "c1").Destroyed, "model destroyed on detach")
	C.Check(RecOf(ctx, "c1") ~= nil and #ctx.Roster() == 2, "detach never touches records / roster")
end)

--..B: equip / unequip..--
C.Run("equip", function()
	local ctx = H.Setup({
		Pets = {H.PetRec("c1", "Cat"), H.PetRec("d1", "Dog"), H.PetRec("f1", "Fox", {AbilityRemaining = 12}), H.PetRec("u1", "Unicorn"),
			H.PetRec("c2", "Cat"), H.PetRec("c3", "Cat"), H.PetRec("c4", "Cat"), H.PetRec("b1", "Bunny")},
		Roster = {"c1", "d1"},
	})
	local PS, P = ctx.PetService, ctx.Player
	PS.EnsureProfileState(P)
	PS.AttachPlot(P, ctx.Plot)
	local saves = ctx.DS.Saves[P] or 0
	C.Check(PS.Equip(P, "f1") == true, "equip f1")
	C.Eq(table.concat(ctx.Roster(), ","), "c1,d1,f1", "roster appended")
	C.Eq(RecOf(ctx, "f1").AbilityRemaining, 60, "equip -> fresh 60 s")
	C.Eq(ctx.SpawnCount("f1"), 1, "f1 spawned")
	C.Check((ctx.DS.Saves[P] or 0) > saves, "save requested")
	C.Check(PS.Equip(P, "f1") == true, "equip twice ok")
	C.Eq(ctx.SpawnCount("f1"), 1, "no second model")
	local ok, err = PS.Equip(P, "u1")
	C.Check(not ok and err == "Unavailable", "unknown species cannot be equipped")
	ok, err = PS.Equip(P, "nope")
	C.Check(not ok and err == "NotOwned", "not owned")
	PS.Equip(P, "c2") PS.Equip(P, "c3") PS.Equip(P, "c4")
	C.Eq(#ctx.Roster(), 6, "six slots")
	ok, err = PS.Equip(P, "b1")
	C.Check(not ok and err == "SlotsFull", "slot cap")
	ctx.T.Phase = "Night"
	ok, err = PS.Equip(P, "b1")
	C.Check(not ok and err == "CombatLocked", "night locks equip")
	ok, err = PS.Unequip(P, "c4")
	C.Check(not ok and err == "CombatLocked", "night locks unequip")
	ok, err = PS.EquipBest(P, "Income")
	C.Check(not ok and err == "CombatLocked", "night locks best")
	ctx.T.Phase = "Day"
	P:SetAttribute("RaidLive", true)
	ok, err = PS.Unequip(P, "c4")
	C.Check(not ok and err == "CombatLocked", "RaidLive locks")
	C.Check(PS.IsCombatLocked(P) == true, "IsCombatLocked RaidLive")
	P:SetAttribute("RaidLive", nil)
	local fModel = ModelOf(ctx, "f1")
	C.Check(PS.Unequip(P, "f1") == true, "unequip f1")
	C.Check(fModel.Destroyed and ctx.Income.Producers.f1 == nil, "unequip despawns + removes producer")
	C.Eq(RecOf(ctx, "f1").AbilityRemaining, 60, "unequip resets the countdown")
	C.Eq(StatusOf(ctx, "f1"), "Reserve", "f1 back to reserve")
	C.Check(PS.Unequip(P, "f1") == true, "unequip absent ok")
	C.Eq(#ctx.Roster(), 5, "roster 5")
	C.Check(RecOf(ctx, "f1") ~= nil, "record kept")
	ok, err = PS.EquipBest(P, "Rarity")
	C.Check(not ok and err == "BadRequest", "bad mode")
end)

--..C: no plot..--
C.Run("noplot", function()
	local ctx = H.Setup({Pets = {H.PetRec("c1", "Cat"), H.PetRec("d1", "Dog")}, Roster = {"c1"}})
	local PS, P = ctx.PetService, ctx.Player
	PS.EnsureProfileState(P)
	local ok, err = PS.Equip(P, "d1")
	C.Check(not ok and err == "NoPlot", "equip without plot -> NoPlot")
	ok, err = PS.EquipBest(P, "Combat")
	C.Check(not ok and err == "NoPlot", "best without plot -> NoPlot")
	C.Check(PS.Unequip(P, "c1") == true and #ctx.Roster() == 0, "unequip allowed without plot")
	ctx.Plot.Attrs.Owner = 5
	PS.AttachPlot(P, ctx.Plot)
	ok, err = PS.Equip(P, "d1")
	C.Check(not ok and err == "NoPlot", "foreign plot -> NoPlot")
	local nobody = H.NewPlayer(2)
	ok, err = PS.Equip(nobody, "d1")
	C.Check(not ok and err == "NotLoaded", "no profile -> NotLoaded")
	C.Check(PS.EnsureProfileState(nobody) == false, "ensure without profile")
	C.Check(PS.HasSourceEgg(nobody, "E1") == false, "HasSourceEgg without profile")
	local rec, info = PS.GrantFromEgg(nobody, {EggId = "E1", EggName = "Basic"}, "Cat")
	C.Check(rec == nil and info.Error == "NotLoaded", "grant without profile")
	ctx.DS.Reports[P] = {Failed = true}
	local ctx2 = H.Setup({Pets = {H.PetRec("c1", "Cat")}})
	ctx2.DS.Reports[ctx2.Player] = {Failed = true}
	local okE, errE = ctx2.PetService.EnsureProfileState(ctx2.Player)
	C.Check(okE == false and errE == "MigrationFailed", "failed load migration -> pets inert")
	local okQ, errQ = ctx2.PetService.Equip(ctx2.Player, "c1")
	C.Check(not okQ and errQ == "MigrationFailed", "equip refused MigrationFailed")
end)

--..D: EquipBest..--
C.Run("equipbest", function()
	local ctx = H.Setup({
		Pets = {H.PetRec("c1", "Cat", {AbilityRemaining = 17}), H.PetRec("f1", "Fox", {AbilityRemaining = 33}), H.PetRec("g1", "Gregory"),
			H.PetRec("b1", "Bunny"), H.PetRec("x1", "Cosmo Cat", {AbilityRemaining = 5}), H.PetRec("d1", "Dog"), H.PetRec("c2", "Cat"),
			H.PetRec("h1", "Chest"), H.PetRec("u1", "Unicorn")},
		Roster = {"c1", "f1"},
	})
	local PS, P = ctx.PetService, ctx.Player
	PS.EnsureProfileState(P)
	PS.AttachPlot(P, ctx.Plot)
	local c1Model = ModelOf(ctx, "c1")
	C.Check(PS.EquipBest(P, "Income") == true, "best income ok")
	C.Eq(table.concat(ctx.Roster(), ","), "x1,h1,g1,f1,b1,d1", "income roster")
	C.Eq(RecOf(ctx, "f1").AbilityRemaining, 33, "kept member keeps its countdown")
	C.Eq(RecOf(ctx, "x1").AbilityRemaining, 60, "new member 60")
	C.Eq(RecOf(ctx, "c1").AbilityRemaining, 60, "removed member 60")
	C.Check(c1Model.Destroyed and StatusOf(ctx, "c1") == "Reserve", "removed member despawned")
	C.Eq(ctx.SpawnCount("f1"), 1, "kept member not respawned")
	local spawns, saves = ctx.SpawnCount(), ctx.DS.Saves[P] or 0
	C.Check(PS.EquipBest(P, "Income") == true, "best again ok")
	C.Eq(table.concat(ctx.Roster(), ","), "x1,h1,g1,f1,b1,d1", "same input -> same roster")
	C.Eq(ctx.SpawnCount(), spawns, "no respawns")
	C.Eq(ctx.DS.Saves[P] or 0, saves, "no save when nothing changed")
	C.Check(PS.EquipBest(P, "Combat") == true, "best combat ok")
	C.Eq(ctx.Roster()[1], "x1", "combat first = Cosmo Cat")
	C.Eq(ctx.Roster()[2], "g1", "combat second = Gregory")
	C.Check(not table.find(ctx.Roster(), "u1"), "unknown never chosen")
end)

--..D2: review #5 - a client's EquipBest requests share one model budget; the API is never throttled..--
C.Run("equipbest churn budget", function()
	local pets = {}
	for i = 1, 12 do pets[i] = H.PetRec(("a%02d"):format(i), "Cat") end -- equal stats: Id order decides
	local best = {"a01", "a02", "a03", "a04", "a05", "a06"}
	local worst = {"a07", "a08", "a09", "a10", "a11", "a12"}
	local ctx = H.Setup({Pets = pets, Roster = table.clone(worst)})
	local PS, P = ctx.PetService, ctx.Player
	PS.EnsureProfileState(P)
	PS.AttachPlot(P, ctx.Plot)
	local function Churn() -- model spawns + despawns so far
		local n = #ctx.Spawns
		for _, s in ipairs(ctx.Spawns) do if s.Model.Destroyed then n += 1 end end
		return n
	end
	local before = Churn()
	PS.HandleRequest(P, {RequestId = "b1", Action = "EquipBest", SortMode = "Income"})
	local r = ctx.LastSent()
	C.Check(r.RequestId == "b1" and r.Result.Ok == true, "a whole-team swap fits the budget")
	C.Eq(table.concat(ctx.Roster(), ","), table.concat(best, ","), "best team")
	C.Eq(Churn() - before, 12, "6 despawns + 6 spawns")
	for _, id in ipairs(best) do PS.Unequip(P, id) end -- the worst team back through the API (not a request)
	for _, id in ipairs(worst) do PS.Equip(P, id) end
	C.Eq(table.concat(ctx.Roster(), ","), table.concat(worst, ","), "worst team again")
	before = Churn()
	PS.HandleRequest(P, {RequestId = "b2", Action = "EquipBest", SortMode = "Combat"})
	r = ctx.LastSent()
	C.Check(r.RequestId == "b2" and r.Result.Ok == false and r.Result.Error == "RateLimited" and r.Result.Action == "EquipBest",
		"a second swap right away -> RateLimited")
	C.Eq(table.concat(ctx.Roster(), ","), table.concat(worst, ","), "the refused swap changed nothing")
	C.Eq(Churn(), before, "no model churn")
	C.Check(PS.EquipBest(P, "Income") == true, "the API (PetDev / server) is not throttled")
	C.Eq(table.concat(ctx.Roster(), ","), table.concat(best, ","), "API swap done")
	before = Churn()
	PS.HandleRequest(P, {RequestId = "b3", Action = "EquipBest", SortMode = "Income"})
	r = ctx.LastSent()
	C.Check(r.RequestId == "b3" and r.Result.Ok == true, "a no-change EquipBest costs nothing: allowed on an empty budget")
	C.Eq(Churn(), before, "and spawns nothing")
end)

--..E: grant + HasSourceEgg + finish..--
C.Run("grant", function()
	local ctx = H.Setup({Pets = {H.PetRec("c1", "Cat")}, Roster = {"c1"},
		Eggs = {{Id = "E1", EggName = "Basic", Kg = 2}, {Id = "E2", EggName = "Basic"}, {Id = "E3", EggName = "Desert"}}})
	local PS, P = ctx.PetService, ctx.Player
	PS.EnsureProfileState(P)
	PS.AttachPlot(P, ctx.Plot)
	local rec, info = PS.GrantFromEgg(P, {EggId = "E1", EggName = "Basic", Kg = 2, Material = "Golden", Mutations = "NEON"}, "Cat")
	C.Check(rec ~= nil and info.Equipped == true and info.Reserve == false, "granted into the roster")
	C.Check(PS.HasSourceEgg(P, "E1") == true, "HasSourceEgg right after the grant")
	C.Check(PS.HasSourceEgg(P, "E2") == false, "other egg not owned")
	C.Eq(#ctx.Data().Base.Eggs, 2, "egg record removed")
	C.Eq(#ctx.Data().Base.Pets, 2, "pet record added")
	C.Eq(StatusOf(ctx, rec.Id), "Pending", "Pending until the reveal ends")
	C.Eq(ctx.SpawnCount(rec.Id), 0, "not spawned during the reveal")
	C.Check(ctx.Income.Producers[rec.Id] == nil, "no income while pending")
	local again, info2 = PS.GrantFromEgg(P, {EggId = "E1", EggName = "Basic"}, "Fox")
	C.Check(again == rec and info2.Duplicate == true and #ctx.Data().Base.Pets == 2, "same egg twice -> the same pet")
	local spot = Vector3.new(90, 10, 40)
	C.Check(PS.FinishPresentation(P, rec.Id, spot, 1) == true, "finish ok")
	C.Eq(ctx.SpawnCount(rec.Id), 1, "spawned at finish")
	C.Eq(StatusOf(ctx, rec.Id), "Active", "Active after finish")
	C.Check(ctx.Spawns[#ctx.Spawns].Spot == spot, "spawned at the egg spot")
	local m = ModelOf(ctx, rec.Id)
	C.Check(m.Attrs.Material == "Golden" and m.Attrs.Mutations == "NEON", "inherited look attributes")
	PS.FinishPresentation(P, rec.Id, spot, 1)
	C.Eq(ctx.SpawnCount(rec.Id), 1, "finish twice -> one model")
	C.Check(PS.FinishPresentation(P, "forged-id", spot, 1) == false, "unknown id finishes nothing")
	local rec2 = PS.GrantFromEgg(P, {EggId = "E2", EggName = "Basic"}, "Dog")
	C.Check(PS.FinishPresentation(P, rec2.Id, nil, 99) == false, "stale generation refused")
	C.Eq(ctx.SpawnCount(rec2.Id), 0, "stale generation never spawns")
	C.Eq(StatusOf(ctx, rec2.Id), "Unavailable", "flag cleared, status recomputed (roster, attached, no model)")
	PS.Freeze(P)
	local rec3, info3 = PS.GrantFromEgg(P, {EggId = "E3", EggName = "Desert"}, "Chest")
	C.Check(rec3 == nil and info3.Error == "Closing", "frozen -> no grants")
	C.Check(PS.HasSourceEgg(P, "E3") == false and #ctx.Data().Base.Eggs == 1, "frozen grant touched nothing")
	local ok, err = PS.Equip(P, "c1")
	C.Check(not ok and err == "Closing", "frozen -> Closing")
end)

--..F: presentation sequences -> exactly one spawn..--
C.Run("presentation detach/attach", function()
	local ctx = H.Setup({Pets = {}, Roster = {}})
	local PS, P = ctx.PetService, ctx.Player
	PS.EnsureProfileState(P)
	PS.AttachPlot(P, ctx.Plot)
	local rec = PS.GrantFromEgg(P, {EggName = "Basic"}, "Cat")
	PS.DetachPlot(P, "Reload")
	C.Eq(StatusOf(ctx, rec.Id), "Pending", "Pending wins over Idle")
	PS.AttachPlot(P, ctx.Plot)
	C.Eq(ctx.SpawnCount(rec.Id), 0, "attach skips a pending pet")
	PS.FinishPresentation(P, rec.Id, nil, 1)
	C.Eq(ctx.SpawnCount(rec.Id), 1, "Pending > Detach > Attach > Finish = one spawn")
	--.. same generation rebuild keeps the flag
	local rec2 = PS.GrantFromEgg(P, {EggName = "Basic"}, "Dog")
	local pets = ctx.Data().Base.Pets
	local copy = {}
	for i, r in ipairs(pets) do copy[i] = r end
	ctx.Data().Base.Pets = copy
	C.Check(PS.EnsureProfileState(P) == true, "rebuild after the Pets array was replaced")
	C.Eq(StatusOf(ctx, rec2.Id), "Pending", "rebuild keeps PresentationPending")
	C.Eq(ctx.SpawnCount(rec2.Id), 0, "rebuild re-attach skips the pending pet")
	C.Eq(ctx.SpawnCount(rec.Id), 2, "rebuild re-attached the active pet (new model)")
	PS.FinishPresentation(P, rec2.Id, nil, 1)
	C.Eq(ctx.SpawnCount(rec2.Id), 1, "finish after rebuild spawns once")
end)
C.Run("presentation unequip/equip", function()
	local ctx = H.Setup({Pets = {}, Roster = {}})
	local PS, P = ctx.PetService, ctx.Player
	PS.EnsureProfileState(P)
	PS.AttachPlot(P, ctx.Plot)
	local rec = PS.GrantFromEgg(P, {EggName = "Basic"}, "Cat")
	C.Check(PS.Unequip(P, rec.Id) == true, "unequip while pending")
	C.Check(PS.Equip(P, rec.Id) == true, "equip while pending")
	C.Eq(ctx.SpawnCount(rec.Id), 0, "equip skips a pending pet")
	PS.FinishPresentation(P, rec.Id, nil, 1)
	C.Eq(ctx.SpawnCount(rec.Id), 1, "Pending > Unequip > Equip > Finish = one spawn")
	local rec2 = PS.GrantFromEgg(P, {EggName = "Basic"}, "Dog")
	PS.Unequip(P, rec2.Id)
	PS.FinishPresentation(P, rec2.Id, nil, 1)
	C.Eq(ctx.SpawnCount(rec2.Id), 0, "finish of an unequipped pet spawns nothing")
	C.Eq(StatusOf(ctx, rec2.Id), "Reserve", "stays in reserve")
end)

--..G: locked hatch -> reserve, auto-equip at unlock in grant order..--
C.Run("auto equip", function()
	local ctx = H.Setup({Pets = {H.PetRec("c1", "Cat"), H.PetRec("c2", "Cat"), H.PetRec("c3", "Cat"), H.PetRec("c4", "Cat")},
		Roster = {"c1", "c2", "c3", "c4"}, Phase = "Night"})
	local PS, P = ctx.PetService, ctx.Player
	PS.EnsureProfileState(P)
	PS.AttachPlot(P, ctx.Plot)
	C.Check(P:GetAttribute("PetCombatLocked") == true, "PetCombatLocked mirrored")
	local a, ia = PS.GrantFromEgg(P, {EggName = "Basic"}, "Fox")
	local b, ib = PS.GrantFromEgg(P, {EggName = "Basic"}, "Dog")
	local c, ic = PS.GrantFromEgg(P, {EggName = "Basic"}, "Bunny")
	C.Check(ia.Reserve == true and ia.AutoEquipAfterCombat == true, "locked hatch -> reserve, after combat")
	C.Check(ib.Reserve == true and ib.AutoEquipAfterCombat == true, "second hatch: the last free slot is promised")
	--.. review #8: 4 + 2 queued = 6, so the third is told the truth (plain reserve, no after-combat notice)
	C.Check(ic.Reserve == true and ic.AutoEquipAfterCombat == false, "third hatch: no slot left to promise")
	C.Eq(#ctx.Roster(), 4, "roster untouched during the lock")
	C.Eq(StatusOf(ctx, a.Id), "Reserve", "reserve while locked")
	--.. the three reveals end during the night: nothing spawns, all stay in reserve
	for _, rec in ipairs({a, b, c}) do PS.FinishPresentation(P, rec.Id, nil, 1) end
	C.Eq(ctx.SpawnCount(a.Id) + ctx.SpawnCount(b.Id) + ctx.SpawnCount(c.Id), 0, "reveal end while locked spawns nothing")
	C.Eq(StatusOf(ctx, b.Id), "Reserve", "still reserve after the reveal")
	ctx.T.Phase = "Day"
	PS.RefreshCombatLock(P)
	C.Eq(table.concat(ctx.Roster(), ","), "c1,c2,c3,c4," .. a.Id .. "," .. b.Id, "unlock equips in grant order while slots are free")
	C.Check(not table.find(ctx.Roster(), c.Id), "third stays in reserve (slots full)")
	C.Eq(ctx.SpawnCount(a.Id), 1, "auto-equipped pet spawned")
	C.Eq(RecOf(ctx, a.Id).AbilityRemaining, 60, "auto-equip countdown 60")
	C.Check(P:GetAttribute("PetCombatLocked") == false, "lock attribute cleared")
	C.Eq(PS.GetDiagnostics().AutoEquipped, 2, "AutoEquipped diag")
	ctx.T.Phase = "Night"
	PS.RefreshCombatLock(P)
	ctx.T.Phase = "Day"
	PS.RefreshCombatLock(P)
	C.Check(not table.find(ctx.Roster(), c.Id), "queue cleared: no late equip")
	--.. unequipping a queued pet during the lock drops it from the queue
	local ctx2 = H.Setup({Pets = {}, Roster = {}, Phase = "Night"})
	ctx2.PetService.EnsureProfileState(ctx2.Player)
	ctx2.PetService.AttachPlot(ctx2.Player, ctx2.Plot)
	local q = ctx2.PetService.GrantFromEgg(ctx2.Player, {EggName = "Basic"}, "Cat")
	ctx2.T.Phase = "Day"
	ctx2.PetService.RefreshCombatLock(ctx2.Player)
	C.Eq(ctx2.Roster()[1], q.Id, "single queued pet joins at dawn")
end)

--..G2: review #9 - dawn arrives while a queued hatch's reveal is still on screen..--
C.Run("auto equip mid-reveal", function()
	local ctx = H.Setup({Pets = {H.PetRec("c1", "Cat"), H.PetRec("c2", "Cat"), H.PetRec("c3", "Cat"), H.PetRec("c4", "Cat")},
		Roster = {"c1", "c2", "c3", "c4"}, Phase = "Night"})
	local PS, P = ctx.PetService, ctx.Player
	PS.EnsureProfileState(P)
	PS.AttachPlot(P, ctx.Plot)
	local a, ia = PS.GrantFromEgg(P, {EggName = "Basic"}, "Fox")
	C.Check(ia.AutoEquipAfterCombat == true, "queued")
	C.Eq(StatusOf(ctx, a.Id), "Reserve", "queued + revealing -> Reserve while locked")
	ctx.T.Phase = "Day"
	PS.RefreshCombatLock(P) -- dawn mid-reveal
	C.Check(table.find(ctx.Roster(), a.Id) ~= nil, "unlock equips it (the promise is kept)")
	C.Eq(ctx.SpawnCount(a.Id), 0, "but no model while its reveal is still on screen")
	C.Eq(StatusOf(ctx, a.Id), "Pending", "Pending until the reveal ends")
	C.Check(ctx.Income.Producers[a.Id] == nil, "no income while pending")
	C.Eq(#PS.GetActivePets(), 4, "not active yet")
	PS.Tick(ctx.T.Now)
	ctx.T.Now += 31
	PS.Tick(ctx.T.Now) -- the 30 s retry never spawns a pending pet
	C.Eq(ctx.SpawnCount(a.Id), 0, "retry skips the pending pet")
	local spot = Vector3.new(95, 3, 45)
	C.Check(PS.FinishPresentation(P, a.Id, spot, 1) == true, "reveal done")
	C.Eq(ctx.SpawnCount(a.Id), 1, "spawned once, at the reveal's end")
	C.Check(ctx.Spawns[#ctx.Spawns].Spot == spot, "at the egg spot")
	C.Eq(StatusOf(ctx, a.Id), "Active", "Active")
	C.Check(ctx.Income.Producers[a.Id] ~= nil, "producer after the spawn")
	PS.FinishPresentation(P, a.Id, spot, 1)
	C.Eq(ctx.SpawnCount(a.Id), 1, "a repeated finish spawns nothing")
	--.. a queued hatch whose reveal ended before dawn still joins + spawns at the unlock (plot spot)
	ctx.T.Phase = "Night"
	PS.RefreshCombatLock(P)
	local b = PS.GrantFromEgg(P, {EggName = "Basic"}, "Dog")
	PS.FinishPresentation(P, b.Id, spot, 1)
	C.Eq(ctx.SpawnCount(b.Id), 0, "reveal end at night: no spawn")
	ctx.T.Phase = "Day"
	PS.RefreshCombatLock(P)
	C.Check(table.find(ctx.Roster(), b.Id) ~= nil and ctx.SpawnCount(b.Id) == 1, "dawn: joined and spawned")
	C.Eq(StatusOf(ctx, b.Id), "Active", "Active at dawn")
	--.. a queued hatch whose reveal outlives the lock but whose slot is gone stays a normal reserve pet
	local ctx2 = H.Setup({Pets = {H.PetRec("c1", "Cat"), H.PetRec("c2", "Cat"), H.PetRec("c3", "Cat"), H.PetRec("c4", "Cat"),
		H.PetRec("c5", "Cat"), H.PetRec("c6", "Cat")}, Roster = {"c1", "c2", "c3", "c4", "c5"}, Phase = "Night"})
	ctx2.PetService.EnsureProfileState(ctx2.Player)
	ctx2.PetService.AttachPlot(ctx2.Player, ctx2.Plot)
	local q, iq = ctx2.PetService.GrantFromEgg(ctx2.Player, {EggName = "Basic"}, "Fox")
	C.Check(iq.AutoEquipAfterCombat == true, "5/6 locked -> promised")
	ctx2.Data().Base.PetRoster[6] = "c6" -- stand-in for a slot filled meanwhile (OD-11: it then stays in reserve)
	ctx2.T.Phase = "Day"
	ctx2.PetService.RefreshCombatLock(ctx2.Player)
	C.Check(not table.find(ctx2.Roster(), q.Id), "no slot at dawn -> reserve")
	ctx2.PetService.FinishPresentation(ctx2.Player, q.Id, spot, 1)
	C.Eq(ctx2.SpawnCount(q.Id), 0, "reserve pet never spawns at the reveal's end")
	C.Eq(StatusOf(ctx2, q.Id), "Reserve", "Reserve")
end)

--..H: inventory cap..--
C.Run("inventory full", function()
	local pets = table.create(1000)
	for i = 1, 1000 do pets[i] = H.PetRec("p" .. i, "Cat") end
	local ctx = H.Setup({Pets = pets, Roster = {}, Eggs = {{Id = "E1", EggName = "Basic"}}})
	local PS, P = ctx.PetService, ctx.Player
	PS.EnsureProfileState(P)
	local rec, info = PS.GrantFromEgg(P, {EggId = "E1", EggName = "Basic"}, "Cat")
	C.Check(rec == nil and info.Error == "InventoryFull", "InventoryFull at MAX_OWNED")
	C.Check(#ctx.Data().Base.Pets == 1000 and #ctx.Data().Base.Eggs == 1, "no mutation")
	C.Eq(PS.GetDiagnostics().InventoryFull, 1, "InventoryFull diag")
	C.Eq(PS.GetDiagnostics().OwnedMax, 1000, "OwnedMax diag")
end)

return C.Summary()
