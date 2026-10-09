-- WP-PETSVC leave / load-failure tests (2026-09-22, review-fix round): the PlayerRemoving drop in either
-- handler order (CONTRACTS 8.3), late reads for a departed player, and a partial install failing the require
-- at once instead of hanging its lazy callers (0.5). Plain-table fakes; the one Instance (a departed-player
-- stand-in) is never parented. No Start().
local HttpService = game:GetService("HttpService")
local H = loadstring(HttpService:GetAsync("http://127.0.0.1:8795/WP-PETSVC_harness.lua"))()
local C = H.Checker("lifecycle")

local function Setup()
	local ctx = H.Setup({Pets = {H.PetRec("c1", "Cat"), H.PetRec("d1", "Dog")}, Roster = {"c1"}})
	local PS, P = ctx.PetService, ctx.Player
	PS.EnsureProfileState(P)
	PS.AttachPlot(P, ctx.Plot)
	PS.HandleRequest(P, {Action = "GetState"})
	return ctx, PS, P
end

--..A: PetService's PlayerRemoving handler runs BEFORE DataService's close phase..--
C.Run("leave: PetService handler first", function()
	local ctx, PS, P = Setup()
	C.Check(PS.GetFullState(P).Revision >= 1, "session revision advanced before the leave")
	PS.HandlePlayerRemoving(P)
	C.Check(ctx.Spawns[1].Model.Destroyed == true, "leave despawned the model")
	C.Eq(ctx.Income.Producers.c1, nil, "leave removed the producer")
	C.Eq(#PS.GetActivePets(), 0, "no active pets after the leave")
	--.. DataService's handler: RunBeforeClose (Freeze 10, SyncRecords 30) while the profile is still loaded
	PS.Freeze(P)
	PS.SyncRecords(P)
	local ok, err = PS.EnsureProfileState(P)
	C.Check(not ok and err == "Closing", "the late Freeze re-keyed the player (the leak condition)")
	ctx.DS.Data[P] = nil -- DataService Forget
	task.wait() -- after the deferred drop
	ctx.DS.Data[P] = H.NewProfile({H.PetRec("c1", "Cat")}, {"c1"}) -- probe only
	C.Check(PS.EnsureProfileState(P) == true, "deferred drop cleared Frozen")
	C.Eq(PS.GetFullState(P).Revision, 0, "deferred drop cleared the session (fresh revision)")
	C.Eq(ctx.SpawnCount("c1"), 1, "nothing respawned by the leave")
end)

--..B: DataService's close phase runs BEFORE PetService's handler..--
C.Run("leave: DataService handler first", function()
	local ctx, PS, P = Setup()
	local seg = PS.GetLogicalPosition("c1")
	PS.Freeze(P)
	PS.SyncRecords(P)
	local rec = ctx.Data().Base.Pets[1]
	C.Check(type(rec.Pos) == "table" and rec.Pos[2] == 0, "order-30 SyncRecords wrote Pos while frozen")
	C.Check(seg ~= nil, "logical position existed before the leave")
	ctx.DS.Data[P] = nil -- Forget
	PS.HandlePlayerRemoving(P) -- no data: no sync, drop only
	C.Check(ctx.Spawns[1].Model.Destroyed == true, "leave despawned the model")
	C.Eq(PS.GetLogicalPosition("c1"), nil, "runtime dropped")
	task.wait()
	ctx.DS.Data[P] = H.NewProfile({H.PetRec("c1", "Cat")}, {"c1"})
	C.Check(PS.EnsureProfileState(P) == true, "Frozen cleared")
	C.Eq(PS.GetFullState(P).Revision, 0, "session cleared")
end)

--..C: a departed Player instance (Parent nil): late requests / reads never re-key it..--
C.Run("departed player", function()
	local ctx, PS = Setup()
	local gone = Instance.new("Folder") -- never parented: stands in for a Player after PlayerRemoving
	local sent = #ctx.Sent
	PS.HandleRequest(gone, {Action = "GetState", RequestId = "r1"})
	PS.HandleRequest(gone, {Action = "Equip", PetId = "c1", RequestId = "r2"})
	C.Eq(#ctx.Sent, sent, "late requests are dropped without a reply")
	local ok, state = pcall(PS.GetFullState, gone)
	C.Check(ok and type(state) == "table" and state.Kind == "Full", "GetFullState still answers")
	C.Eq(ok and state.Revision, 0, "throwaway session")
	C.Eq(ok and state.Result and state.Result.Error, "NotLoaded", "not loaded")
	gone:Destroy()
end)

--..D: a partial install fails the require at once (no infinite WaitForChild)..--
C.Run("missing sibling module", function()
	for _, name in ipairs({"PetMotion", "PetStats", "PetBalance"}) do
		local fakes = {__missing = {[name] = true}}
		if name ~= "PetBalance" then fakes.PetBalance = H.LoadFile("ReplicatedStorage.Modules.PetBalance.lua", fakes) end
		if name == "PetMotion" then fakes.PetStats = H.LoadFile("ReplicatedStorage.Modules.PetStats.lua", fakes) end
		local t0 = os.clock()
		local ok, err = pcall(H.LoadFile, "ServerStorage.PetService.lua", fakes)
		C.Check(not ok and tostring(err):find(name .. " is missing", 1, true) ~= nil, name .. ": require fails with a clear error (" .. tostring(err) .. ")")
		C.Check(os.clock() - t0 < 1, name .. ": fails fast")
	end
	local PetService = H.LoadPetService()
	C.Check(type(PetService) == "table" and type(PetService.Init) == "function", "full install still loads")
end)

return C.Summary()
