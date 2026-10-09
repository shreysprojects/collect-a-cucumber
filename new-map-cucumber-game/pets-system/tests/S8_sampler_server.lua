--[[
	S8_sampler_server.lua  (pets-system/tests, S8 integration agent, 2026-09-22)
	1 Hz SERVER sampler for the S8 load scenario (same fields as the S0b rows in
	S0_baseline_*_server_sampler.json, plus the pet-system numbers and leak proxies).
	PASTE the whole file into mcp__robloxstudio__eval_server_runtime (no loadstring in that VM).
	Optional first line:  local S8_OPTS = {Seconds = 300, Label = "solo"}
	Read it later with:   return game:GetService("HttpService"):JSONEncode(_G.S8S.Report())
	Stop it with:         _G.S8S.Stop()
	Everything lives in _G of the play VM (gone with the teardown). Creates no instances.
]]
local opts = (type(S8_OPTS) == "table" and S8_OPTS) or {}
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")

if _G.S8S and _G.S8S.Stop then pcall(_G.S8S.Stop) end
local S = {Label = opts.Label or "?", Rows = {}, ServerEvents = {}, Conns = {}, T0 = os.clock(), Started = workspace:GetServerTimeNow()}
_G.S8S = S

local function req(name)
	local m = ServerStorage:FindFirstChild(name)
	if not m then return nil end
	local ok, r = pcall(require, m)
	return ok and r or nil
end
local PetService, IncomeService, PetCombatService, PetBuffService, PetEffectsBus =
	req("PetService"), req("IncomeService"), req("PetCombatService"), req("PetBuffService"), req("PetEffectsBus")

-- client -> server RemoteEvent counters
for _, r in ipairs(ReplicatedStorage:GetDescendants()) do
	if r:IsA("RemoteEvent") or r:IsA("UnreliableRemoteEvent") then
		local key = r:GetFullName():gsub("^ReplicatedStorage%.", "")
		table.insert(S.Conns, r.OnServerEvent:Connect(function()
			S.ServerEvents[key] = (S.ServerEvents[key] or 0) + 1
		end))
	end
end

local function Diag(mod)
	if not mod or type(mod.GetDiagnostics) ~= "function" then return nil end
	local ok, d = pcall(mod.GetDiagnostics)
	return ok and d or nil
end
local function AliveZombies()
	local folder = workspace:FindFirstChild("Zombies")
	if not folder then return 0 end
	local n = 0
	for _, z in ipairs(folder:GetChildren()) do
		local h = z:FindFirstChildOfClass("Humanoid")
		if h and h.Health > 0 then n += 1 end
	end
	return n
end
local function CashSum()
	local s = 0
	for _, p in ipairs(Players:GetPlayers()) do
		local d = p:FindFirstChild("Data")
		local v = d and d:FindFirstChild("Cash")
		if v then s += v.Value end
	end
	return s
end
local function Plots()
	local out = {}
	local plots = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Lobby") and workspace.Map.Lobby:FindFirstChild("Plots")
	if not plots then return out end
	for _, pl in ipairs(plots:GetChildren()) do
		local owner = pl:GetAttribute("Owner")
		if owner then
			table.insert(out, {Owner = owner, Lvl = pl:GetAttribute("ThreatLevel"), Stolen = pl:GetAttribute("RaidStolen"), Over = pl:GetAttribute("RaidOver")})
		end
	end
	return out
end

local frames, maxDt, lastT = 0, 0, os.clock()
local cash0 = CashSum()
local maxSeconds = tonumber(opts.Seconds) or 300
local diagEvery = 10
table.insert(S.Conns, RunService.Heartbeat:Connect(function(dt)
	frames += 1
	if dt > maxDt then maxDt = dt end
	local now = os.clock()
	if now - lastT < 1 then return end
	local t = now - S.T0
	local row = {
		t = math.floor(t * 10 + 0.5) / 10,
		fps = frames,
		hbMaxMs = math.floor(maxDt * 10000 + 0.5) / 10,
		send = Stats.DataSendKbps,
		recv = Stats.DataReceiveKbps,
		hbms = Stats.HeartbeatTimeMs,
		phys = Stats.PhysicsStepTimeMs,
		inst = Stats.InstanceCount,
		prims = Stats.PrimitivesCount,
		mem = math.floor(Stats:GetTotalMemoryUsageMb()),
		luaHeapMb = math.floor(Stats:GetMemoryUsageMbForTag(Enum.DeveloperMemoryTag.LuaHeap) * 10 + 0.5) / 10,
		gcKb = math.floor(gcinfo()),
		alive = AliveZombies(),
		cash = CashSum() - cash0,
		plotPets = #CollectionService:GetTagged("PlotPet"),
		placed = #CollectionService:GetTagged("PlacedCucumber"),
		plots = Plots(),
	}
	if #S.Rows % diagEvery == 0 then
		local pd = Diag(PetService)
		local inc = Diag(IncomeService)
		local cb = Diag(PetCombatService)
		local bf = Diag(PetBuffService)
		local fx = Diag(PetEffectsBus)
		row.diag = {
			Pet = pd and {Active = pd.Active, Reserve = pd.Reserve, Rolls = pd.Rolls, Denied = pd.DeniedRequests, SpawnFailures = pd.SpawnFailures, SchedulerErrors = pd.SchedulerErrors} or nil,
			Income = inc, Combat = cb, Buff = bf, Fx = fx,
		}
	end
	table.insert(S.Rows, row)
	frames, maxDt, lastT = 0, 0, now
	if t >= maxSeconds then S.Stop() end
end))

function S.Stop()
	for _, c in ipairs(S.Conns) do pcall(function() c:Disconnect() end) end
	S.Conns = {}
	S.Stopped = true
end
function S.Report(fromT, toT)
	local rows = {}
	for _, r in ipairs(S.Rows) do
		if (not fromT or r.t >= fromT) and (not toT or r.t <= toT) then table.insert(rows, r) end
	end
	return {Label = S.Label, Started = S.Started, Rows = rows, ServerEvents = S.ServerEvents, Stopped = S.Stopped == true}
end
return ("S8 server sampler started (%s): %d remote counters, up to %d s; PetService %s IncomeService %s Combat %s"):format(
	S.Label, #S.Conns - 1, maxSeconds, tostring(PetService ~= nil), tostring(IncomeService ~= nil), tostring(PetCombatService ~= nil))
