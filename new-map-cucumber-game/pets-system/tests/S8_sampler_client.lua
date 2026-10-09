--[[
	S8_sampler_client.lua  (pets-system/tests, S8 integration agent, 2026-09-22)
	1 Hz CLIENT sampler + OnClientEvent counters for the S8 load scenario (the S0b client fields in
	S0_baseline_client_samplers.json, plus pet presentation counts and leak proxies).
	PASTE the whole file into mcp__robloxstudio__eval_client_runtime (target client-N).
	Optional first line:  local S8_OPTS = {Seconds = 300, Label = "solo"}
	Read:  return game:GetService("HttpService"):JSONEncode(_G.S8C.Report())      Stop: _G.S8C.Stop()
	Lives in _G of the play VM only. Creates no instances.
]]
local opts = (type(S8_OPTS) == "table" and S8_OPTS) or {}
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")

if _G.S8C and _G.S8C.Stop then pcall(_G.S8C.Stop) end
local C = {Label = opts.Label or "?", Rows = {}, Events = {}, Conns = {}, T0 = os.clock(), Started = workspace:GetServerTimeNow()}
_G.S8C = C

-- payload size estimate: JSON of the args with Instances replaced by a short marker
local function Clean(v, depth)
	local t = typeof(v)
	if t == "Instance" then return "I" end
	if t == "table" then
		if depth > 6 then return "T" end
		local out = {}
		for k, x in pairs(v) do out[tostring(k)] = Clean(x, depth + 1) end
		return out
	end
	if t == "number" or t == "string" or t == "boolean" or t == "nil" then return v end
	return tostring(v)
end
for _, r in ipairs(ReplicatedStorage:GetDescendants()) do
	if r:IsA("RemoteEvent") or r:IsA("UnreliableRemoteEvent") then
		local key = r:GetFullName():gsub("^ReplicatedStorage%.", "")
		table.insert(C.Conns, r.OnClientEvent:Connect(function(...)
			local e = C.Events[key]
			if not e then e = {Count = 0, JsonBytes = 0}; C.Events[key] = e end
			e.Count += 1
			local ok, json = pcall(HttpService.JSONEncode, HttpService, Clean({...}, 0))
			if ok then e.JsonBytes += #json end
		end))
	end
end

local player = Players.LocalPlayer
-- only the tagged pet / cucumber models are scanned (cards and popups live under their parts)
local function Count(pred)
	local n = 0
	for _, tag in ipairs({"PlotPet", "PlacedCucumber"}) do
		for _, m in ipairs(CollectionService:GetTagged(tag)) do
			for _, d in ipairs(m:GetDescendants()) do if pred(d) then n += 1 end end
		end
	end
	return n
end
local frames, maxDt, lastT = 0, 0, os.clock()
local maxSeconds = tonumber(opts.Seconds) or 300
local heavyEvery = 10
table.insert(C.Conns, RunService.Heartbeat:Connect(function(dt)
	frames += 1
	if dt > maxDt then maxDt = dt end
	local now = os.clock()
	if now - lastT < 1 then return end
	local t = now - C.T0
	local cam = workspace.CurrentCamera
	local fxFolder = cam and cam:FindFirstChild("PetFxLocal")
	local row = {
		t = math.floor(t * 10 + 0.5) / 10,
		fps = frames,
		hbMaxMs = math.floor(maxDt * 10000 + 0.5) / 10,
		send = Stats.DataSendKbps,
		mem = math.floor(Stats:GetTotalMemoryUsageMb()),
		luaHeapMb = math.floor(Stats:GetMemoryUsageMbForTag(Enum.DeveloperMemoryTag.LuaHeap) * 10 + 0.5) / 10,
		gcKb = math.floor(gcinfo()),
		inst = Stats.InstanceCount,
		plotPets = #CollectionService:GetTagged("PlotPet"),
		fxParts = fxFolder and #fxFolder:GetDescendants() or 0,
		guiDesc = player and player:FindFirstChild("PlayerGui") and #player.PlayerGui:GetDescendants() or 0,
	}
	if #C.Rows % heavyEvery == 0 then
		row.petCards = Count(function(d) return d.Name == "PetCard" and d:IsA("BillboardGui") end)
		row.petPopups = Count(function(d) return d.Name == "PetIncomePopup" end)
		row.incomePopups = Count(function(d) return d.Name == "IncomePopup" end)
	end
	table.insert(C.Rows, row)
	frames, maxDt, lastT = 0, 0, now
	if t >= maxSeconds then C.Stop() end
end))

function C.Stop()
	for _, c in ipairs(C.Conns) do pcall(function() c:Disconnect() end) end
	C.Conns = {}
	C.Stopped = true
	C.StoppedAt = os.clock() - C.T0
end
function C.Report(fromT, toT)
	local rows = {}
	for _, r in ipairs(C.Rows) do
		if (not fromT or r.t >= fromT) and (not toT or r.t <= toT) then table.insert(rows, r) end
	end
	local window = (C.StoppedAt or (os.clock() - C.T0))
	local total = 0
	for _, e in pairs(C.Events) do total += e.Count end
	return {Label = C.Label, Started = C.Started, WindowSeconds = window, TotalEvents = total, PerSecond = total / math.max(window, 1e-3), Events = C.Events, Rows = rows, Stopped = C.Stopped == true}
end
return ("S8 client sampler started (%s) on %s: %d remote counters, up to %d s"):format(C.Label, player and player.Name or "?", #C.Conns - 1, maxSeconds)
