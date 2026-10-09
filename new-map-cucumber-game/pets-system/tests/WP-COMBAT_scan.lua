-- WP-COMBAT scan tests (2026-09-22): the module-private Scan() driven through a fake Heartbeat. The module chunk
-- runs in a sandbox (fake game / RunService / ServerStorage.ZombieAPI, plain-table "instances" via a typeof shim,
-- warn captured): no instances, no DataModel reads or writes, no real Heartbeat connection.
-- Covers the review fix: a GetActivePets that errors or returns a non-table skips the scan and keeps every deadline
-- (no second shot one scan later), and makes no ZombieAPI call.
-- Run: return loadstring(game:GetService("HttpService"):GetAsync("http://127.0.0.1:8795/WP-COMBAT_scan.lua"))()
local HttpService = game:GetService("HttpService")
local src = HttpService:GetAsync("http://127.0.0.1:8793/ServerStorage.PetCombatService.lua")

local pass, fail, failures = 0, 0, {}
local function check(name, cond, detail)
	if cond then
		pass += 1
	else
		fail += 1
		if #failures < 10 then table.insert(failures, name .. (detail ~= nil and (" [" .. tostring(detail) .. "]") or "")) end
	end
end

local V = Vector3.new
local realTypeof = typeof

-- a fresh sandboxed module + its fakes; mode(callIndex) -> "ok" | "error" | "nil" | "empty" decides GetActivePets
local function Build(mode)
	local world = {Name = "Workspace"}
	local zombie = {Fake = true, Name = "z", Parent = world, IsA = function(_, c) return c == "Model" end}
	local calls = {Damage = {}, TargetInfos = 0, Pets = 0}
	local services = {ServerStorage = {}, RunService = {}, ReplicatedStorage = {FindFirstChild = function() return nil end}}
	local folder = {Fake = true, Name = "ZombieAPI", Parent = services.ServerStorage}
	local function Bindable(name, invoke)
		return {Fake = true, Name = name, Parent = folder, IsA = function(_, c) return c == "BindableFunction" end, Invoke = invoke}
	end
	local members = {
		Damage = Bindable("Damage", function(_, model, amount, source)
			table.insert(calls.Damage, {Model = model, Amount = amount, Source = source})
			return true, 40
		end),
		TargetInfos = Bindable("TargetInfos", function()
			calls.TargetInfos += 1
			return {{Model = zombie, Owner = 1, Position = V(5, 3, 0), Carrying = false, Grappling = false, Health = 50, MaxHealth = 50}}
		end),
	}
	folder.FindFirstChild = function(_, name) return members[name] end
	services.ServerStorage.FindFirstChild = function(_, name) if name == "ZombieAPI" then return folder end return nil end
	local handler
	services.RunService.Heartbeat = {Connect = function(_, fn) handler = fn; return {Disconnect = function() end} end}
	local fakeGame = {GetService = function(_, name) return services[name] end}
	local warns = {}
	local chunk, err = loadstring(src)
	if not chunk then return nil, err end
	local env = setmetatable({
		game = fakeGame,
		warn = function(...) table.insert(warns, table.concat({tostring((...))}, " ")) end,
		typeof = function(v) if type(v) == "table" and v.Fake then return "Instance" end return realTypeof(v) end,
	}, {__index = getfenv()})
	setfenv(chunk, env)
	local ok, M = pcall(chunk)
	if not ok then return nil, M end

	local now = 0
	local stats = {Valid = true, Range = 26, ShotInterval = 2.5, ShotDamage = 3, Rarity = "Common"}
	local list = {{PetId = "A", UserId = 1, Stats = stats}, {PetId = "B", UserId = 1, Stats = stats}}
	local petService = {
		GetActivePets = function()
			calls.Pets += 1
			local m = mode(calls.Pets)
			if m == "error" then error("cache rebuild") end
			if m == "nil" then return nil end
			if m == "empty" then return {} end
			return list
		end,
		GetLogicalPosition = function() return V(0, 0, 0) end,
	}
	M.Init({PetService = petService, Clock = function() return now end})
	M.Start()
	return {
		M = M, calls = calls, warns = warns,
		Step = function(t) now = t; handler(0.2) end, -- exactly one scan per step (accumulator 0 -> 0.2)
		HasHandler = function() return handler ~= nil end,
	}
end

--.. a failed read between two good scans: no second shot, no ZombieAPI call, error counted
for _, bad in ipairs({"error", "nil"}) do
	local h, err = Build(function(i) return i == 2 and bad or "ok" end)
	check(bad .. ": built", h ~= nil, err)
	if h then
		check(bad .. ": started", h.M.IsStarted() and h.HasHandler())
		h.Step(0) -- scan 1: both pets fire
		check(bad .. ": both pets fired", #h.calls.Damage == 2 and h.calls.Damage[1].Source == "Pet", #h.calls.Damage)
		local infosBefore = h.calls.TargetInfos
		h.Step(0.2) -- scan 2: the pet list cannot be read
		check(bad .. ": failed read makes no ZombieAPI call", h.calls.TargetInfos == infosBefore and #h.calls.Damage == 2)
		h.Step(0.4) -- scan 3: reads again, cooldowns must still run
		check(bad .. ": no burst after the failed read", #h.calls.Damage == 2, #h.calls.Damage)
		for k = 3, 12 do h.Step(k * 0.2) end -- 0.6 .. 2.4
		check(bad .. ": cooldown held", #h.calls.Damage == 2, #h.calls.Damage)
		h.Step(2.6)
		check(bad .. ": next pair at the interval", #h.calls.Damage == 4, #h.calls.Damage)
		local diag = h.M.GetDiagnostics()
		check(bad .. ": one error counted", diag.Errors == 1, diag.Errors)
		check(bad .. ": failed scan not counted as a scan", diag.Scans == 13, diag.Scans)
		check(bad .. ": shots", diag.Shots == 4 and diag.DamageDealt == 12, diag.Shots)
		local warned = false
		for _, w in ipairs(h.warns) do if w:find("GetActivePets failed") then warned = true end end
		check(bad .. ": warned", warned)
	end
end

--.. an empty list IS a real read: deadlines are forgotten and a returning pet fires at once (contract)
do
	local h, err = Build(function(i) return i == 2 and "empty" or "ok" end)
	check("empty: built", h ~= nil, err)
	if h then
		h.Step(0)
		h.Step(0.2) -- a real, empty read: nobody is active, no ZombieAPI call
		check("empty: no ZombieAPI call", h.calls.TargetInfos == 1)
		h.Step(0.4) -- both pets active again = newly active
		check("empty: re-activated pets fire at once", #h.calls.Damage == 4, #h.calls.Damage)
		local diag = h.M.GetDiagnostics()
		check("empty: no error, counted as a scan", diag.Errors == 0 and diag.Scans == 3, diag.Scans)
	end
end

return ("WP-COMBAT scan: PASS %d / FAIL %d%s"):format(pass, fail, fail > 0 and (": " .. table.concat(failures, "; ")) or "")
