--[[
	AdminService  (Script, ServerScriptService)
	The admin panel's server half (user, 2026-09-12): Remotes.AdminAction (RemoteFunction) answers
	(action, value) -> ok, message for the players in ADMINS only - everyone else gets "Not an admin",
	whatever the client says.
	  * "day" / "night": ends the current phase now through ServerStorage.DayNightAPI.Force (DayNightCycle;
	    a forced day runs a full day from now, a forced night a full night, then the shared clock resumes)
	  * "cash" / "strength" + a number: DataService.Set - the HUD, playerlist and physique follow
	  * "reset": BaseSaveAPI.Reset empties the plot (cucumbers, builds, pets) and Data.Base, DataService
	    .ResetProfile puts the whole profile back to the template (Cash 0, Strength 0, PlotLevel 0,
	    bench level 1, no headbands ...), the plot's Owner attribute is bounced so PlotUpgradeService,
	    GymService, EggPlacement and the badges re-sync from the fresh data, the character respawns
	    (physique + headband come off), and BaseSaveAPI.Resume turns the saving back on. Works in Studio
	    the same way (the profile is live there too - ProfileStore is not mocked).
	The panel itself: StarterGui.AdminPanel (build_adminpanel.lua + AdminPanelClient).
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local DataService = require(ServerStorage:WaitForChild("DataService"))
local NumberAbbrev = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("NumberAbbrev"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local PLOTS = workspace:WaitForChild("Map"):WaitForChild("Lobby"):WaitForChild("Plots")

local ADMINS = {[140977250] = "awesomeotheraccount"} -- UserId -> name (the name is only a note)
local COOLDOWN = 0.3 -- seconds between actions per admin
local MAX_VALUE = 1e300

local remote = Remotes:FindFirstChild("AdminAction")
if not remote then
	remote = Instance.new("RemoteFunction")
	remote.Name = "AdminAction"
	remote.Parent = Remotes
end

local LastAction = {}

local function PlotOf(player)
	for _, plot in ipairs(PLOTS:GetChildren()) do
		if plot:IsA("BasePart") and plot:GetAttribute("Owner") == player.UserId then return plot end
	end
	return nil
end

local function Bindable(folderName, name)
	local folder = ServerStorage:FindFirstChild(folderName)
	local fn = folder and folder:FindFirstChild(name)
	return fn
end

local function Number(value)
	local n = tonumber(value)
	if type(value) == "string" then n = tonumber((value:gsub("[,_%s]", ""))) end
	if not n or n ~= n or n == math.huge or n == -math.huge then return nil end
	return math.clamp(math.floor(n), 0, MAX_VALUE)
end

--..Actions..--
local function ForcePhase(phase)
	local api = ServerStorage:FindFirstChild("DayNightAPI")
	local force = api and api:FindFirstChild("Force")
	if not force then return false, "The day / night cycle is not running" end
	local current = workspace:GetAttribute("CyclePhase")
	if phase == "Night" and current == "Night" then return false, "It is already night" end
	if phase == "Day" and current ~= "Night" then return false, "It is already day" end
	force:Fire(phase)
	return true, phase == "Night" and "Night is falling" or "The day is starting"
end

local function SetValue(player, key, value)
	local n = Number(value)
	if not n then return false, "Enter a number, 0 or more" end
	if not DataService.IsLoaded(player) then return false, "Your data is still loading" end
	DataService.Set(player, key, n)
	return true, ("%s set to %s"):format(key, NumberAbbrev.Abbrev(n))
end

local function ResetData(player)
	if not DataService.IsLoaded(player) then return false, "Your data is still loading" end
	local baseReset = Bindable("BaseSaveAPI", "Reset")
	local baseResume = Bindable("BaseSaveAPI", "Resume")
	local cleared = 0
	if baseReset then
		local ok, _, n = pcall(baseReset.Invoke, baseReset, player)
		if ok then cleared = tonumber(n) or 0 else warn("[AdminService] BaseSave reset: " .. tostring(n)) end
	end
	if not DataService.ResetProfile(player) then return false, "Could not reset the profile" end
	--.. bounce the plot's Owner so every service that keys off it re-syncs from the fresh data:
	--.. PlotUpgradeService (level 0), GymService (bench 1), EggPlacement + PetHatchService (clear), badges
	local plot = PlotOf(player)
	if plot then
		local uid, name = plot:GetAttribute("Owner"), plot:GetAttribute("OwnerName")
		plot:SetAttribute("Owner", nil)
		plot:SetAttribute("OwnerName", nil)
		task.wait()
		plot:SetAttribute("Owner", uid)
		plot:SetAttribute("OwnerName", name)
		local deadline = os.clock() + 5
		while plot:GetAttribute("PlotLevel") ~= 0 and os.clock() < deadline do task.wait(0.1) end
	end
	if baseResume then pcall(baseResume.Invoke, baseResume, player) end
	task.defer(function()
		if player.Parent == Players then player:LoadCharacter() end -- physique, headband, carried load: all fresh
	end)
	print(("[AdminService] %s reset their data (%d things cleared off %s)"):format(player.Name, cleared, plot and plot.Name or "no plot"))
	return true, "Data reset: cash, strength, plot, base - everything back to zero"
end

remote.OnServerInvoke = function(player, action, value)
	if not ADMINS[player.UserId] then return false, "Not an admin" end
	local now = os.clock()
	if LastAction[player] and now - LastAction[player] < COOLDOWN then return false, "Too fast" end
	LastAction[player] = now
	action = tostring(action)
	local ok, result, message = pcall(function()
		if action == "day" then return ForcePhase("Day")
		elseif action == "night" then return ForcePhase("Night")
		elseif action == "cash" then return SetValue(player, "Cash", value)
		elseif action == "strength" then return SetValue(player, "Strength", value)
		elseif action == "reset" then return ResetData(player)
		end
		return false, "Unknown action " .. action
	end)
	if not ok then
		warn("[AdminService] " .. action .. ": " .. tostring(result))
		return false, "Something went wrong"
	end
	print(("[AdminService] %s: %s%s -> %s"):format(player.Name, action, value ~= nil and (" " .. tostring(value)) or "", tostring(message)))
	return result == true, message
end

Players.PlayerRemoving:Connect(function(player) LastAction[player] = nil end)

print("[AdminService] Remotes.AdminAction ready for " .. (function() local n = {} for _, name in pairs(ADMINS) do table.insert(n, name) end return table.concat(n, ", ") end)())
