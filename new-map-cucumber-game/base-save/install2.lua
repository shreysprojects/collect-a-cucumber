-- install2.lua (base-save, round 2: saved eggs + the bench-tier fix). Same servers as install.lua:
--   serve.ps1 -Port 8770 -Root base-save (after stage.js)   +   receive.ps1 -Port 8766 -Root new-map-cucumber-game
-- Pushes DataService (Base.Eggs), EggPlacement (EggPlacementAPI.RestoreEgg / ClearEggs), BaseSaveService (eggs),
-- BenchRuntimeMesh (all-or-nothing tier builds), and patches BenchTierClient in place (no runtime build for tier 1).
local HttpService = game:GetService("HttpService")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local BASE, RECEIVE = "http://127.0.0.1:8770/", "http://127.0.0.1:8766/"
local report = {}
local function fetch(name)
	local ok, body = pcall(HttpService.GetAsync, HttpService, BASE .. name)
	assert(ok, "fetch " .. name .. ": " .. tostring(body))
	return (body:gsub("\r\n", "\n"))
end
local function compiled(name, src)
	local fn, err = loadstring(src)
	assert(fn, name .. ": " .. tostring(err))
	return fn
end
local function push(inst, name)
	local src = fetch(name)
	compiled(name, src)
	inst.Source = src
	table.insert(report, ("%s <- %s (%d)"):format(inst:GetFullName(), name, #src))
end
local function patch(inst, label, marker, edits)
	local src = inst.Source
	if src:find(marker, 1, true) then table.insert(report, label .. ": already patched") return end
	for _, e in ipairs(edits) do
		local i, j = src:find(e[1], 1, true)
		assert(i, label .. ": anchor missing: " .. e[1]:sub(1, 70))
		assert(not src:find(e[1], j + 1, true), label .. ": anchor not unique: " .. e[1]:sub(1, 70))
		src = src:sub(1, i - 1) .. e[2] .. src:sub(j + 1)
	end
	compiled(label, src)
	inst.Source = src
	table.insert(report, label .. ": patched (" .. #edits .. " edits)")
end
local function mirror(inst, name)
	local ok, res = pcall(HttpService.PostAsync, HttpService, RECEIVE .. name, inst.Source, Enum.HttpContentType.TextPlain)
	table.insert(report, "mirror " .. name .. ": " .. (ok and res or ("FAILED " .. tostring(res))))
end

push(ServerStorage:WaitForChild("DataService"), "DataService.lua")
push(ServerScriptService:WaitForChild("EggPlacement"), "EggPlacement.server.lua")
push(ServerScriptService:WaitForChild("BaseSaveService"), "BaseSaveService.server.lua")
push(ReplicatedStorage.Modules:WaitForChild("BenchRuntimeMesh"), "BenchRuntimeMesh.lua")

local tierClient = StarterPlayer.StarterPlayerScripts:WaitForChild("BenchTierClient")
patch(tierClient, "BenchTierClient", "no EditableMesh budget spent on it", {
	{"\tif fromAssets then return fromAssets end\n\tif runtimeModels[tier] then return runtimeModels[tier] end\n",
	 "\tif fromAssets then return fromAssets end\n\tif tier <= 1 then return nil end -- the server bench IS the Starter look: no EditableMesh budget spent on it (2026-09-12)\n\tif runtimeModels[tier] then return runtimeModels[tier] end\n"},
})
mirror(tierClient, "BenchTierClient.client.lua")

print("[install2 base-save]\n" .. table.concat(report, "\n"))
return table.concat(report, "\n")
