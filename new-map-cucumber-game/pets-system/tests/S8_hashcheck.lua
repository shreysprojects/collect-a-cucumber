-- S8: compare every live pet-system script with src/ + patched/ (loopback), read-only
local H = game:GetService("HttpService")
local SRC = {"ReplicatedStorage.Modules.PetBalance.lua","ReplicatedStorage.Modules.PetMotion.lua","ReplicatedStorage.Modules.PetStats.lua","ServerScriptService.PetServer.server.lua","ServerStorage.IncomeService.lua","ServerStorage.PetBuffService.lua","ServerStorage.PetCombatService.lua","ServerStorage.PetDataMigration.lua","ServerStorage.PetEffectsBus.lua","ServerStorage.PetService.lua","StarterGui.CucumberMenus.PetController.lua","StarterGui.CucumberMenus.PetView.lua","StarterPlayer.StarterPlayerScripts.PetCardClient.client.lua","StarterPlayer.StarterPlayerScripts.PetEffectsClient.client.lua"}
local PATCHED = {"ServerScriptService.BaseSaveService.server.lua","ServerScriptService.CucumberCarry.server.lua","ServerScriptService.EggPlacement.server.lua","ServerScriptService.LeaderstatsService.server.lua","ServerScriptService.PetHatchService.server.lua","ServerScriptService.PlotService.server.lua","ServerScriptService.ZombieRaidService.server.lua","ServerStorage.DataService.lua","StarterGui.CucumberHUDDesign.BaseHUDController.lua","StarterGui.CucumberMenus.MenuClient.client.lua","StarterGui.CucumberMenus.MenuController.lua","StarterPlayer.StarterPlayerScripts.EggHatchClient.client.lua","StarterPlayer.StarterPlayerScripts.PetRoamClient.client.lua","StarterPlayer.StarterPlayerScripts.PlacedCucumberCardClient.client.lua"}
local function norm(s)
	s = s:gsub("^\239\187\191", "")
	s = s:gsub("\r\n", "\n")
	return s
end
local function hash(s)
	local h = 0
	for i = 1, #s do h = (h * 31 + string.byte(s, i)) % 2147483647 end
	return h
end
local function resolve(f)
	local p = f:gsub("%.server%.lua$", ""):gsub("%.client%.lua$", ""):gsub("%.lua$", "")
	local cur = game
	for part in p:gmatch("[^%.]+") do
		if cur == game then cur = game:GetService(part) else cur = cur and cur:FindFirstChild(part) end
		if not cur then return nil end
	end
	return cur
end
local out, bad = {}, 0
local function check(list, port)
	for _, f in ipairs(list) do
		local inst = resolve(f)
		local ok, src = pcall(H.GetAsync, H, ("http://127.0.0.1:%d/%s"):format(port, f))
		if not inst then table.insert(out, "MISSING " .. f); bad += 1
		elseif not ok then table.insert(out, "NOLOCAL " .. f); bad += 1
		else
			local a, b = norm(inst.Source), norm(src)
			local eq = a == b
			if not eq then bad += 1 end
			table.insert(out, ("%s %s live=%d local=%d h=%d"):format(eq and "EQ" or "DIFF", f, #a, #b, hash(a)))
		end
	end
end
check(SRC, 8793)
check(PATCHED, 8794)
return ("bad=%d\n"):format(bad) .. table.concat(out, "\n")
