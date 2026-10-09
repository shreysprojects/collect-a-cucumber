--[[
	snapshot_profile.lua  (pets-system/tools, integration agent, 2026-09-22) - CONTRACTS 10.4 (+ 12 amendment)
	Saves the test account's live profile (DataService.GetData) as JSON into pets-system/tests/.

	The playtest SERVER VM cannot reach the loopback servers (HttpService "HTTP requests are not
	enabled" - game context) and has no loadstring, so the data travels through a scratch DataStore
	entry (store "PetTestTransfer", key "Snapshot_140977250"). The SAME file runs in two places:

	1. SERVER VM (mcp__robloxstudio__eval_server_runtime): paste the whole file as the eval code, with
	   ONE line in front of it:
	       local PROFILE_TOOL_OPTS = {Name = "profile_S3_1405.json"}
	   -> writes {Name, Json, At, Key} to the transfer entry and returns the counts.
	2. EDIT PEER (mcp__robloxstudio__execute_luau, default target):
	       local H = game:GetService("HttpService")
	       local src = H:GetAsync("http://127.0.0.1:8796/snapshot_profile.lua")   -- stage.ps1 copies it there
	       return loadstring("local PROFILE_TOOL_OPTS = ...\n" .. src)({Name = "profile_S3_1405.json"})
	   -> reads the transfer entry, POSTs it to the loopback receiver
	      (pets-remake/receive.ps1 -Port 8797 -Root <pets-system>\tests) and reads it back through the
	      tests file server (:8795) before it says OK.

	Options: Name (tests/ file name, default profile_S_<hhmm>.json; step 2 may omit it = take the
	entry's), Port (receiver, 8797). The file is ProfileStore-envelope shaped {Data = <profile Data>,
	MetaData = {Snapshot info}}, so restore_profile.lua reads it like a raw DataStore value.
	Only ever for UserId 140977250. Never writes to the profile.
]]
local opts = PROFILE_TOOL_OPTS
if type(opts) ~= "table" then opts = {} end

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local DataStoreService = game:GetService("DataStoreService")

local USER_ID = 140977250
local TRANSFER_STORE, TRANSFER_KEY = "PetTestTransfer", "Snapshot_" .. USER_ID
local PORT = tonumber(opts.Port) or 8797
local READ_PORT = 8795 -- pets-system/tests file server

local function Count(t) return type(t) == "table" and #t or -1 end
local function ValidName(n) return type(n) == "string" and n:match("^[%w_%-%.]+%.json$") ~= nil end
local store = DataStoreService:GetDataStore(TRANSFER_STORE)

if RunService:IsRunning() then
	--..1. SERVER VM: profile -> transfer entry..--
	local name = opts.Name or ("profile_S_%s.json"):format(os.date("%H%M"))
	if not ValidName(name) then return "snapshot_profile: FAIL bad file name " .. tostring(name) end
	local player = Players:GetPlayerByUserId(USER_ID)
	if not player then return "snapshot_profile: FAIL player " .. USER_ID .. " not in the server" end
	local DataService = require(ServerStorage:WaitForChild("DataService"))
	local data = DataService.GetData(player)
	local profile = DataService.GetProfile and DataService.GetProfile(player)
	if type(data) ~= "table" then return "snapshot_profile: FAIL no loaded profile" end
	local base = type(data.Base) == "table" and data.Base or {}
	local envelope = {
		Data = data,
		MetaData = {
			Snapshot = true,
			SnapshotAt = os.time(),
			ProfileKey = profile and profile.Key or "?",
			Generation = type(DataService.GetGeneration) == "function" and DataService.GetGeneration(player) or nil,
			PlaceId = game.PlaceId,
		},
	}
	local ok, json = pcall(HttpService.JSONEncode, HttpService, envelope)
	if not ok then return "snapshot_profile: FAIL JSONEncode " .. tostring(json) end
	local setOk, err = pcall(store.SetAsync, store, TRANSFER_KEY, {Name = name, Json = json, At = os.time()})
	if not setOk then return "snapshot_profile: FAIL transfer SetAsync " .. tostring(err) end
	return ("snapshot_profile STEP 1 OK: %s staged in %s/%s (%d bytes, key %s): Cash=%s Pets=%d Eggs=%d Cucumbers=%d Builds=%d Roster=%d. Now run step 2 in the edit peer."):format(
		name, TRANSFER_STORE, TRANSFER_KEY, #json, tostring(envelope.MetaData.ProfileKey), tostring(data.Cash), Count(base.Pets),
		Count(base.Eggs), Count(base.Cucumbers), Count(base.Builds), Count(base.PetRoster))
end

--..2. EDIT PEER: transfer entry -> tests/<Name>..--
local blob
local getOk, err = pcall(function()
	local o = Instance.new("DataStoreGetOptions")
	o.UseCache = false
	blob = store:GetAsync(TRANSFER_KEY, o)
end)
if not getOk then return "snapshot_profile: FAIL transfer GetAsync " .. tostring(err) end
if type(blob) ~= "table" or type(blob.Json) ~= "string" then return "snapshot_profile: FAIL no staged snapshot (run step 1 in the server VM first)" end
local name = opts.Name or blob.Name
if not ValidName(name) then return "snapshot_profile: FAIL bad file name " .. tostring(name) end
if opts.Name and blob.Name ~= opts.Name then
	return ("snapshot_profile: FAIL the staged snapshot is %s (at %s), not %s"):format(tostring(blob.Name), tostring(blob.At), opts.Name)
end
local postOk, reply = pcall(HttpService.PostAsync, HttpService, ("http://127.0.0.1:%d/%s"):format(PORT, name), blob.Json, Enum.HttpContentType.TextPlain)
if not postOk then return "snapshot_profile: FAIL POST (is receive.ps1 running on " .. PORT .. "?) " .. tostring(reply) end
local sent = HttpService:JSONDecode(blob.Json)
local back
local readOk, readErr = pcall(function()
	back = HttpService:JSONDecode(HttpService:GetAsync(("http://127.0.0.1:%d/%s?t=%d"):format(READ_PORT, name, math.floor(os.clock() * 1000))))
end)
local verdict = "NOT VERIFIED (" .. tostring(readErr) .. ")"
local d = sent.Data or {}
local b = type(d.Base) == "table" and d.Base or {}
if readOk and type(back) == "table" and type(back.Data) == "table" then
	local bb = type(back.Data.Base) == "table" and back.Data.Base or {}
	local same = back.Data.Cash == d.Cash and Count(bb.Pets) == Count(b.Pets) and Count(bb.Eggs) == Count(b.Eggs)
		and Count(bb.Cucumbers) == Count(b.Cucumbers) and Count(bb.Builds) == Count(b.Builds)
	verdict = same and "OK (read back)" or "READ BACK MISMATCH"
end
return ("snapshot_profile STEP 2 %s: tests/%s (%d bytes, staged %ds ago from key %s): Cash=%s Pets=%d Eggs=%d Cucumbers=%d Builds=%d Roster=%d; %s"):format(
	verdict, name, #blob.Json, os.time() - (tonumber(blob.At) or 0), tostring(sent.MetaData and sent.MetaData.ProfileKey), tostring(d.Cash),
	Count(b.Pets), Count(b.Eggs), Count(b.Cucumbers), Count(b.Builds), Count(b.PetRoster), tostring(reply))
