--[[
	lift-rebuild/install.lua -- run through the Studio MCP (edit mode) while
	pets-remake/serve.ps1 -Port 8767 -Root new-map-cucumber-game serves the project folder.
	Installs the click-to-lift pickup (2026-09-16) and retires the old strength-band pickup:
	  1. backup folder ServerStorage.__LiftRebuildBackup_2026_09_16: clones of the scripts that
	     get overwritten + the old system's scripts / animation assets MOVED there (Disabled)
	  2. ReplicatedStorage.Modules.CucumberLift + CucumberLiftPoses (new ModuleScripts)
	  3. StarterPlayerScripts.CucumberLiftClient (new LocalScript)
	  4. CucumberCarry / CarryClient / CucumberPromptClient sources replaced
	Every source is loadstring-checked before it is written. Idempotent.
]]
local HttpService = game:GetService("HttpService")
local RS = game:GetService("ReplicatedStorage")
local SS = game:GetService("ServerStorage")
local SSS = game:GetService("ServerScriptService")
local SPS = game.StarterPlayer:WaitForChild("StarterPlayerScripts")
local BASE = "http://127.0.0.1:8767/"
local log = {}
local function say(s) log[#log + 1] = s end

local function fetch(name)
	local text
	for _ = 1, 15 do
		local ok, res = pcall(HttpService.GetAsync, HttpService, BASE .. name)
		if ok then text = res break end
		task.wait(0.5)
	end
	assert(text, "could not fetch " .. name)
	text = text:gsub("\r\n", "\n")
	local fn, err = loadstring(text)
	assert(fn, name .. " does not compile: " .. tostring(err))
	return text
end

--.. 1. backups
local backup = SS:FindFirstChild("__LiftRebuildBackup_2026_09_16")
if not backup then
	backup = Instance.new("Folder")
	backup.Name = "__LiftRebuildBackup_2026_09_16"
	backup.Parent = SS
end
local function backupClone(inst, label)
	if not inst or backup:FindFirstChild(label) then return end
	local c = inst:Clone()
	c.Name = label
	if c:IsA("BaseScript") then c.Enabled = false end
	c.Parent = backup
	say("backed up " .. label)
end
local function retire(inst, label)
	if not inst then return end
	if backup:FindFirstChild(label) then
		inst:Destroy()
		say("removed duplicate " .. label)
		return
	end
	if inst:IsA("BaseScript") then inst.Enabled = false end
	inst.Name = label
	inst.Parent = backup
	say("retired " .. label)
end
backupClone(SSS:FindFirstChild("CucumberCarry"), "CucumberCarry")
backupClone(SPS:FindFirstChild("CarryClient"), "CarryClient")
backupClone(SPS:FindFirstChild("CucumberPromptClient"), "CucumberPromptClient")
retire(RS.Modules:FindFirstChild("CucumberStrength"), "CucumberStrength")
retire(SPS:FindFirstChild("CollectAnimClient"), "CollectAnimClient")
retire(SPS:FindFirstChild("CucumberGripClient"), "CucumberGripClient")
local anims = RS:FindFirstChild("Assets") and RS.Assets:FindFirstChild("Animations")
if anims then
	for _, n in ipairs({"CucumberPickUp", "CucumberStruggle", "CucumberFall", "CucumberPickUpSequence", "CucumberStruggleSequence", "CucumberFallSequence"}) do
		retire(anims:FindFirstChild(n), "Anim_" .. n)
	end
end

--.. 2. modules
local function module(name)
	local m = RS.Modules:FindFirstChild(name)
	if not m then
		m = Instance.new("ModuleScript")
		m.Name = name
		m.Parent = RS.Modules
	end
	m.Source = fetch(name .. ".lua")
	say("wrote RS.Modules." .. name .. " (" .. #m.Source .. ")")
end
module("CucumberLift")
module("CucumberLiftPoses")

--.. 3. new client
local liftClient = SPS:FindFirstChild("CucumberLiftClient")
if not liftClient then
	liftClient = Instance.new("LocalScript")
	liftClient.Name = "CucumberLiftClient"
	liftClient.Parent = SPS
end
liftClient.Source = fetch("CucumberLiftClient.client.lua")
liftClient.Enabled = true
say("wrote SPS.CucumberLiftClient (" .. #liftClient.Source .. ")")

--.. 4. replaced sources
local carry = SSS:FindFirstChild("CucumberCarry")
assert(carry, "ServerScriptService.CucumberCarry missing")
carry.Source = fetch("CucumberCarry.server.lua")
say("wrote SSS.CucumberCarry (" .. #carry.Source .. ")")
local carryClient = SPS:FindFirstChild("CarryClient")
assert(carryClient, "CarryClient missing")
carryClient.Source = fetch("CarryClient.client.lua")
say("wrote SPS.CarryClient (" .. #carryClient.Source .. ")")
local promptClient = SPS:FindFirstChild("CucumberPromptClient")
assert(promptClient, "CucumberPromptClient missing")
promptClient.Source = fetch("CucumberPromptClient.client.lua")
say("wrote SPS.CucumberPromptClient (" .. #promptClient.Source .. ")")

return table.concat(log, "\n")
