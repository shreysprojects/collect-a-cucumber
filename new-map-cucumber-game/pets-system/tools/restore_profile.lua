--[[
	restore_profile.lua  (pets-system/tools, integration agent, 2026-09-22) - CONTRACTS 10.4 (+ 12 amendment)
	Puts a saved profile back into the test account's LIVE session and rebuilds the plot from it.

	The playtest SERVER VM cannot reach the loopback servers (HttpService "HTTP requests are not
	enabled" - game context) and has no loadstring, so the JSON travels through a scratch DataStore
	entry (store "PetTestTransfer", key "Restore_140977250"). The SAME file runs in two places:

	1. EDIT PEER (mcp__robloxstudio__execute_luau, default target):
	       local H = game:GetService("HttpService")
	       local src = H:GetAsync("http://127.0.0.1:8796/restore_profile.lua")   -- stage.ps1 copies it there
	       return loadstring("local PROFILE_TOOL_OPTS = ...\n" .. src)({Name = "WP-DATA_fixture_profile.json"})
	   -> fetches tests/<Name> from the tests file server (:8795), validates it and stages it in the
	      transfer entry; returns a Nonce.
	2. SERVER VM (mcp__robloxstudio__eval_server_runtime): paste the whole file as the eval code, with
	   ONE line in front of it:
	       local PROFILE_TOOL_OPTS = {Name = "WP-DATA_fixture_profile.json", Nonce = "<from step 1>"}
	   -> the restore below. Its summary string goes into tests/ (write it there yourself - the server VM
	      cannot POST).

	Accepted JSON: a raw ProfileStore envelope {Data = ..., MetaData = ...} (the DataStore value, or a
	snapshot_profile.lua file) or a bare Data table; it must hold a Base table and a finite Cash.

	Options (step 2): Name, Nonce (must match the staged entry), Reload = true (false: data only),
	AllowRealKey = false (the session must be on a Studio test key <prefix>_140977250 from DataService's
	PetTestProfileKey; true lets it write the REAL Player_140977250 profile - S8 only),
	Json = "<json text>" (optional: skip the transfer entry and restore this text).

	Step 2: if the saved PlotLevel differs from the plot's, resize the plot through PlotUpgradeService's
	Studio hook (workspace PlotUpgradeDev "<plot>:<level>") and wait for it -> ONE non-yielding block:
	every top-level key of DataService.GetData(player) replaced (keys absent from the JSON deleted; Cash /
	Playtime / Strength through DataService.Set(..., quiet) so the value objects follow) +
	DataService.RequestSave -> BaseSaveAPI.Reload (pauses the base synchronously, clears the plot,
	rebuilds it from the restored Base) -> re-read and compare Cash / #Base.Pets / Eggs / Cucumbers /
	Builds with the JSON; the world counts on the plot are listed too -> RequestSave again.
	Playtime is DataService's session clock (rewritten every second from the value it loaded), so it
	comes back only after a rejoin of a profile saved with it - never mid-session.
	Only ever for UserId 140977250 (refuses anyone else).
]]
local opts = PROFILE_TOOL_OPTS
if type(opts) ~= "table" then opts = {} end

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local HttpService = game:GetService("HttpService")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local DataStoreService = game:GetService("DataStoreService")

local USER_ID = 140977250
local NAME = opts.Name or "WP-DATA_fixture_profile.json"
local READ_PORT = 8795 -- pets-system/tests file server
local TRANSFER_STORE, TRANSFER_KEY = "PetTestTransfer", "Restore_" .. USER_ID
local VALUE_KEYS = {Cash = true, Playtime = true, Strength = true} -- DataService VALUE_ORDER
local TAGS = {Pets = "PlotPet", Eggs = "PlacedEgg", Cucumbers = "PlacedCucumber", Builds = "PlacedBuild"} -- BaseSaveService

local lines = {}
local failures = 0
local function Note(s) lines[#lines + 1] = s end
local function Check(label, ok, detail)
	if not ok then failures += 1 end
	Note(("%s %s%s"):format(ok and "PASS" or "FAIL", label, detail and (" (" .. detail .. ")") or ""))
end
local function Finite(x) return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge end
local function Count(t) return type(t) == "table" and #t or -1 end
local function Finish(stage)
	return ("restore_profile %s %s <- %s at %s\n%s"):format(stage, failures == 0 and "OK" or ("FAILED x" .. failures), NAME,
		os.date("%Y-%m-%d %H:%M:%S"), table.concat(lines, "\n"))
end
--.. decoded JSON -> the Data table (envelope or bare), or nil + why
local function DataOf(decoded)
	if type(decoded) ~= "table" then return nil, "not a JSON object" end
	local src = decoded
	if type(decoded.Data) == "table" and decoded.Base == nil then src = decoded.Data end
	if type(src.Base) ~= "table" or not Finite(src.Cash) then
		return nil, ("Base %s, Cash %s"):format(type(src.Base), tostring(src.Cash))
	end
	return src, src == decoded and "bare Data" or "envelope"
end
local store = DataStoreService:GetDataStore(TRANSFER_STORE)

if type(NAME) ~= "string" or not NAME:match("^[%w_%-%.]+%.json$") then
	Check("file name", false, tostring(NAME))
	return Finish("")
end

if not RunService:IsRunning() then
	--..1. EDIT PEER: tests/<Name> -> transfer entry..--
	local text
	local ok, err = pcall(function()
		text = HttpService:GetAsync(("http://127.0.0.1:%d/%s?t=%d"):format(READ_PORT, NAME, math.floor(os.clock() * 1000)))
	end)
	if not ok then Check("fetch tests/" .. NAME, false, tostring(err)) return Finish("STEP 1") end
	local decodeOk, decoded = pcall(HttpService.JSONDecode, HttpService, text)
	local src, how = DataOf(decodeOk and decoded or nil)
	if not src then Check("JSON holds Base + Cash", false, how) return Finish("STEP 1") end
	local nonce = HttpService:GenerateGUID(false):sub(1, 8)
	local setOk, setErr = pcall(store.SetAsync, store, TRANSFER_KEY, {Name = NAME, Json = text, At = os.time(), Nonce = nonce})
	Check("staged in " .. TRANSFER_STORE .. "/" .. TRANSFER_KEY, setOk, not setOk and tostring(setErr) or nil)
	Note(("%d bytes (%s): Cash=%s PlotLevel=%s Pets=%d Eggs=%d Cucumbers=%d Builds=%d"):format(#text, how, tostring(src.Cash),
		tostring(src.PlotLevel), Count(src.Base.Pets), Count(src.Base.Eggs), Count(src.Base.Cucumbers), Count(src.Base.Builds)))
	Note(("NEXT (server VM): local PROFILE_TOOL_OPTS = {Name = %q, Nonce = %q} + this file"):format(NAME, nonce))
	return Finish("STEP 1")
end

--..2. SERVER VM: the restore..--
local player = Players:GetPlayerByUserId(USER_ID)
if not player then Check("player in server", false, tostring(USER_ID)) return Finish("STEP 2") end
local DataService = require(ServerStorage:WaitForChild("DataService"))
local data = DataService.GetData(player)
local profile = DataService.GetProfile and DataService.GetProfile(player)
if type(data) ~= "table" or not profile then Check("profile loaded", false) return Finish("STEP 2") end
local key = tostring(profile.Key)
local isReal = key == ("Player_%d"):format(USER_ID)
Note("session key " .. key .. (isReal and " (REAL profile)" or " (test key)"))
if isReal and opts.AllowRealKey ~= true then
	Check("test key in use", false, "the session is on the REAL key; set ServerStorage.PetTestProfileKey in edit mode and restart the playtest, or pass AllowRealKey = true")
	return Finish("STEP 2")
end

local text = opts.Json
if type(text) ~= "string" then
	local blob
	local ok, err = pcall(function()
		local o = Instance.new("DataStoreGetOptions")
		o.UseCache = false
		blob = store:GetAsync(TRANSFER_KEY, o)
	end)
	if not ok or type(blob) ~= "table" or type(blob.Json) ~= "string" then
		Check("staged JSON", false, ok and "nothing staged - run step 1 in the edit peer" or tostring(err))
		return Finish("STEP 2")
	end
	if blob.Name ~= NAME or (opts.Nonce ~= nil and blob.Nonce ~= opts.Nonce) then
		Check("staged JSON matches", false, ("staged %s nonce %s at %s; asked %s nonce %s"):format(tostring(blob.Name),
			tostring(blob.Nonce), tostring(blob.At), NAME, tostring(opts.Nonce)))
		return Finish("STEP 2")
	end
	text = blob.Json
	Note(("staged JSON: %d bytes, nonce %s, staged %ds ago"):format(#text, tostring(blob.Nonce), os.time() - (tonumber(blob.At) or 0)))
end
local decodeOk, decoded = pcall(HttpService.JSONDecode, HttpService, text)
local src, how = DataOf(decodeOk and decoded or nil)
if not src then Check("JSON holds Base + Cash", false, how) return Finish("STEP 2") end
local want = {Pets = Count(src.Base.Pets), Eggs = Count(src.Base.Eggs), Cucumbers = Count(src.Base.Cucumbers), Builds = Count(src.Base.Builds)}
Note(("JSON (%s): Cash=%s Playtime=%s PlotLevel=%s Pets=%d Eggs=%d Cucumbers=%d Builds=%d Base.Version=%s"):format(
	how, tostring(src.Cash), tostring(src.Playtime), tostring(src.PlotLevel), want.Pets, want.Eggs, want.Cucumbers, want.Builds,
	tostring(src.Base.Version)))

--..the join-time BaseSave Restore must be over before the Reload (they would race): BaseRestored (S3+),
--..or the first 12 s of the server (legacy BaseSave has no flag; a solo playtest server starts at the join)..--
local waitStart = os.clock()
while player:GetAttribute("BaseRestored") ~= true and workspace.DistributedGameTime < 12 and os.clock() - waitStart < 15 do
	task.wait(0.25)
end
if os.clock() - waitStart > 0.1 then Note(("waited %.1f s for the join restore"):format(os.clock() - waitStart)) end

--..the plot must be the saved size before the rebuild (BaseSave's Restore waits for it otherwise)..--
local plot
for _, p in ipairs(workspace.Map.Lobby.Plots:GetChildren()) do
	if p:GetAttribute("Owner") == USER_ID then plot = p break end
end
if not plot then Check("plot assigned", false) return Finish("STEP 2") end
local wantLevel = tonumber(src.PlotLevel) or 0
if plot:GetAttribute("PlotLevel") ~= wantLevel and RunService:IsStudio() then
	workspace:SetAttribute("PlotUpgradeDev", nil)
	workspace:SetAttribute("PlotUpgradeDev", ("%s:%d"):format(plot.Name, wantLevel))
	local deadline = os.clock() + 5
	while plot:GetAttribute("PlotLevel") ~= wantLevel and os.clock() < deadline do task.wait(0.05) end
	workspace:SetAttribute("PlotUpgradeDev", nil)
end
Check("plot level", plot:GetAttribute("PlotLevel") == wantLevel, ("%s = %s, want %d"):format(plot.Name, tostring(plot:GetAttribute("PlotLevel")), wantLevel))

--..ONE non-yielding block: replace every top-level key, save, then Reload pauses the base..--
data = DataService.GetData(player) -- re-read after the yield (profile tables are never cached)
if type(data) ~= "table" then Check("profile still loaded", false) return Finish("STEP 2") end
local removed = {}
for k in pairs(data) do
	if src[k] == nil then table.insert(removed, tostring(k)) end
end
for _, k in ipairs(removed) do data[k] = nil end
for k, v in pairs(src) do
	if VALUE_KEYS[k] and Finite(v) then
		DataService.Set(player, k, v, true)
	else
		data[k] = v -- freshly decoded tables: nothing else holds them
	end
end
local cashAtWrite = data.Cash
local baseAtWrite = data.Base
DataService.RequestSave(player)
Check("Cash written", cashAtWrite == src.Cash, tostring(cashAtWrite))
if #removed > 0 then Note("keys removed (absent from the JSON): " .. table.concat(removed, ", ")) end

if opts.Reload ~= false then
	local api = ServerStorage:FindFirstChild("BaseSaveAPI")
	local reload = api and api:FindFirstChild("Reload")
	if reload then
		local t0 = os.clock()
		local ok, result, why = pcall(reload.Invoke, reload, player)
		Check("BaseSaveAPI.Reload", ok and result == true, ("%s %s %s in %.1f s"):format(tostring(ok), tostring(result), tostring(why or ""), os.clock() - t0))
	else
		Check("BaseSaveAPI.Reload", false, "ServerStorage.BaseSaveAPI.Reload missing")
	end
end

--..verify: the profile (after Reload's own snapshot) and the world on the plot..--
data = DataService.GetData(player)
if type(data) ~= "table" then Check("profile after reload", false) return Finish("STEP 2") end
local base = type(data.Base) == "table" and data.Base or {}
Note(("Base table %s"):format(base == baseAtWrite and "unchanged since the write" or "rebuilt by BaseSave (Collect)"))
for _, kind in ipairs({"Pets", "Eggs", "Cucumbers", "Builds"}) do
	Check("#Base." .. kind, Count(base[kind]) == want[kind], ("%d, want %d"):format(Count(base[kind]), want[kind]))
end
local world = {}
for kind, tag in pairs(TAGS) do
	local n = 0
	for _, inst in ipairs(CollectionService:GetTagged(tag)) do
		if inst:GetAttribute("Owner") == USER_ID and inst:IsDescendantOf(plot) then n += 1 end
	end
	world[kind] = n
end
Note(("world on %s: Pets=%d Eggs=%d Cucumbers=%d Builds=%d"):format(plot.Name, world.Pets, world.Eggs, world.Cucumbers, world.Builds))
Check("Cash after", Finite(data.Cash) and data.Cash >= src.Cash, ("%s (+%s income since the write)"):format(tostring(data.Cash), tostring((data.Cash or 0) - src.Cash)))
Note(("PlotLevel=%s Strength=%s Playtime=%s (session clock)"):format(tostring(data.PlotLevel), tostring(data.Strength), tostring(data.Playtime)))
DataService.RequestSave(player)
return Finish("STEP 2")
