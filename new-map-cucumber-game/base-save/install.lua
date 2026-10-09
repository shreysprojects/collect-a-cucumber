-- install.lua (base-save): ONE execute_luau in edit mode. Serve this folder first:
--   pets-remake/serve.ps1 -Port 8770 -Root new-map-cucumber-game/base-save
-- (stage.js copies the patched DataService / PetHatchService / BuildService mirrors in here first) and,
-- to refresh the mirrors of the scripts patched in place, run the receiver too:
--   pets-remake/receive.ps1 -Port 8766 -Root new-map-cucumber-game
-- Steps: whole-file pushes (DataService, PetHatchService, BuildService), the two new server scripts
-- (BaseSaveService, AdminService), StarterGui.AdminPanel (build_adminpanel.lua + AdminPanelClient), and
-- anchored in-place patches of CucumberCarry (RestorePlaced / ClearPlaced), CucumberSpawner (SpawnCarried
-- Force) and DayNightCycle (DayNightAPI.Force). Every patch is idempotent (a marker string skips it).
local HttpService = game:GetService("HttpService")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local BASE = "http://127.0.0.1:8770/"
local RECEIVE = "http://127.0.0.1:8766/"
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
local function ensureScript(parent, name, class, file)
	local inst = parent:FindFirstChild(name)
	if not inst then
		inst = Instance.new(class)
		inst.Name = name
		inst.Parent = parent
	end
	push(inst, file)
	return inst
end
--.. edits = {{anchor, replacement}}: every anchor must appear exactly once; marker = a string only the
--.. patched source contains (skips a second run); the result must still compile
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

--..1) whole files..--
push(ServerStorage:WaitForChild("DataService"), "DataService.lua")
push(ServerScriptService:WaitForChild("PetHatchService"), "PetHatchService.server.lua")
push(ServerScriptService:WaitForChild("BuildService"), "BuildService.server.lua")

--..2) new server scripts..--
ensureScript(ServerScriptService, "BaseSaveService", "Script", "BaseSaveService.server.lua")
ensureScript(ServerScriptService, "AdminService", "Script", "AdminService.server.lua")

--..3) the admin panel..--
compiled("build_adminpanel.lua", fetch("build_adminpanel.lua"))(fetch("AdminPanelClient.client.lua"))
table.insert(report, "StarterGui.AdminPanel rebuilt")

--..4) CucumberSpawner: SpawnCarried / SpawnBreakable take Force (closed fields + full biome)..--
patch(ServerScriptService.CucumberSpawner, "CucumberSpawner", "ex.Force == true", {
	{"\tif not FieldsOpen then return nil end\n\tlocal index = table.find(ZONES, zone)\n",
	 "\tif not FieldsOpen and not (fixed and fixed.Force == true) then return nil end -- Force: BaseSaveService restoring a plot, night included\n\tlocal index = table.find(ZONES, zone)\n"},
	{"\tif not FieldsOpen or not table.find(ZONES, zone) then return nil end\n\tlocal sliced, other = CountZonePopulation(zone)\n\tif sliced + other >= CUCUMBERS_PER_BIOME then return nil end\n\tlocal typeDef = TypeByName(zone, typeName)\n\tif not typeDef then return nil end\n\tlocal ex = type(extra) == \"table\" and extra or {}\n",
	 "\t--.. Force (BaseSaveService restoring a saved plot, 2026-09-12): spawn even while the fields are closed for\n\t--.. the night or the biome is full - the copy is taken off the field again at once\n\tlocal ex = type(extra) == \"table\" and extra or {}\n\tlocal force = ex.Force == true\n\tif (not FieldsOpen and not force) or not table.find(ZONES, zone) then return nil end\n\tif not force then\n\t\tlocal sliced, other = CountZonePopulation(zone)\n\t\tif sliced + other >= CUCUMBERS_PER_BIOME then return nil end\n\tend\n\tlocal typeDef = TypeByName(zone, typeName)\n\tif not typeDef then return nil end\n"},
	{"Anywhere = ex.Anywhere == true, SizeTier = ex.SizeTier,", "Anywhere = ex.Anywhere == true, Force = force, SizeTier = ex.SizeTier,"},
})

--..5) CucumberCarry: RestorePlaced / ClearPlaced bindables..--
local RESTORE_BLOCK = [[
--..Restore (profile -> plot): BaseSaveService stands a saved cucumber back up without the shoulder trip
--..(2026-09-12). A field cucumber of the saved kind is spawned (SpawnCarried with Force: even while the
--..fields are closed for the night or the biome is full), cloned into the self-contained model Grab()
--..makes (BuildCarryModel: rest pose, PlaceScale), the field one is destroyed at once, and the copy is
--..stood at the saved pivot with the saved footprint box - exactly where and how it stood before..--
local function RestorePlaced(player, plot, record, pivot, boxCF, boxSize)
	if not (SpawnCarried and plot and plot.Parent and type(record) == "table") then return nil, "no spawner" end
	if typeof(pivot) ~= "CFrame" or typeof(boxCF) ~= "CFrame" or typeof(boxSize) ~= "Vector3" then return nil, "bad record" end
	local holder = SpawnCarried:Invoke(record.Zone or "Spawn", record.Type, record.Golden == true, pivot.Position,
		{Anywhere = true, Force = true, Material = record.Material, Mutations = record.Mutations, SizeTier = record.SizeTier})
	if not holder then return nil, "spawn failed (" .. tostring(record.Zone) .. " / " .. tostring(record.Type) .. ")" end
	local meta = {
		Name = holder.Name, Zone = holder:GetAttribute("Zone") or "Spawn", TypeName = holder:GetAttribute("TypeName") or holder.Name,
		Golden = holder:GetAttribute("Golden") == true, Material = holder:GetAttribute("Material"), Mutations = holder:GetAttribute("Mutations"),
		SizeTier = holder:GetAttribute("SizeTier"), SizeScale = holder:GetAttribute("SizeScale"),
	}
	holder:SetAttribute("CollectingBy", nil)
	local model = BuildCarryModel(holder)
	holder:Destroy()
	if not model then return nil, "no model" end
	local placeScale = tonumber(model:GetAttribute("PlaceScale")) or 1
	if placeScale ~= 1 then
		model:ScaleTo(model:GetScale() * placeScale)
		ScaleLooks(model, placeScale)
	end
	model:PivotTo(pivot)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanQuery = false
		end
	end
	local hitbox = Instance.new("Part")
	hitbox.Name = "PlotHitbox"
	hitbox.Size = boxSize
	hitbox.CFrame = boxCF
	hitbox.Transparency = 1
	hitbox.Anchored = true
	hitbox.CanCollide = false
	hitbox.CanTouch = false
	hitbox.CanQuery = true
	hitbox.Parent = model
	local name = record.Name or meta.Name
	model.Name = name
	model:SetAttribute("Owner", player.UserId)
	model:SetAttribute("CucumberName", name)
	model:SetAttribute("Zone", meta.Zone)
	model:SetAttribute("TypeName", meta.TypeName)
	model:SetAttribute("Golden", meta.Golden)
	model:SetAttribute("Material", meta.Material)
	model:SetAttribute("Mutations", meta.Mutations or "")
	model:SetAttribute("SizeTier", meta.SizeTier)
	model:SetAttribute("SizeScale", meta.SizeScale)
	CollectionService:AddTag(model, "PlacedCucumber")
	model.Parent = HolderOf(plot)
	return model
end

local function ClearPlaced(plot)
	local holder = plot and plot:FindFirstChild("Placed")
	if not holder then return 0 end
	local n = 0
	for _, model in ipairs(holder:GetChildren()) do
		if CollectionService:HasTag(model, "PlacedCucumber") then
			CollectionService:RemoveTag(model, "PlacedCucumber")
			model:Destroy()
			n += 1
		end
	end
	return n
end

do
	local restore = carryAPI:FindFirstChild("RestorePlaced") or Instance.new("BindableFunction")
	restore.Name = "RestorePlaced"
	restore.OnInvoke = RestorePlaced
	restore.Parent = carryAPI
	local clear = carryAPI:FindFirstChild("ClearPlaced") or Instance.new("BindableFunction")
	clear.Name = "ClearPlaced"
	clear.OnInvoke = ClearPlaced
	clear.Parent = carryAPI
end

]]
local PICKUP_ANCHOR = "--..Pick up (plot -> shoulder) -- reachable only through the Studio dev hook..--\n"
patch(ServerScriptService.CucumberCarry, "CucumberCarry", "local function RestorePlaced(", {
	{PICKUP_ANCHOR, RESTORE_BLOCK .. PICKUP_ANCHOR},
})

--..6) DayNightCycle: DayNightAPI.Force ends the current phase now..--
patch(ServerScriptService.DayNightCycle, "DayNightCycle", "DayNightAPI", {
	{"local CYCLE_EPOCH = 1788652800",
	 "-- Admin panel (2026-09-12): ServerStorage.DayNightAPI.Force(\"Night\" | \"Day\") ends the current phase now.\n-- A forced night runs NightDurationSeconds from now; a forced day runs a full day from now; then the\n-- shared clock takes over again (the next schedule() call).\nlocal forced\ndo\n local api=ServerStorage:FindFirstChild(\"DayNightAPI\") or Instance.new(\"Folder\")\n api.Name=\"DayNightAPI\"\n api.Parent=ServerStorage\n local force=api:FindFirstChild(\"Force\") or Instance.new(\"BindableEvent\")\n force.Name=\"Force\"\n force.Parent=api\n force.Event:Connect(function(phase)\n  local current=workspace:GetAttribute(\"CyclePhase\")\n  if phase==\"Night\" and current~=\"Night\" then forced=\"Night\"\n  elseif phase==\"Day\" and current==\"Night\" then forced=\"Day\" end\n end)\nend\n\nlocal CYCLE_EPOCH = 1788652800"},
	{"local function nightWait(deadline)\n while workspace:GetServerTimeNow()<deadline do\n",
	 "local function nightWait(deadline)\n while workspace:GetServerTimeNow()<deadline do\n  if forced==\"Day\" then return false end -- the admin panel ends the night\n"},
	{" while true do\n  local now=workspace:GetServerTimeNow()\n  if now>=s.NightStart then break end\n",
	 " while true do\n  local now=workspace:GetServerTimeNow()\n  if forced==\"Night\" then -- the admin panel ends the day: a full night starts now\n   forced=nil\n   s.NightStart=now\n   s.NextDayStart=now+s.NightSeconds\n   workspace:SetAttribute(\"PhaseEndsAt\",now)\n   print(\"[DayNightCycle] night forced by the admin panel\")\n   break\n  end\n  if now>=s.NightStart then break end\n"},
	{" nightWait(s.NextDayStart-travel)\n moveBarrier(lowered,travel)\n nightWait(s.NextDayStart)\n if barrierTween then barrierTween:Cancel() end\n driver.Value=lowered\nend\n",
	 " nightWait(s.NextDayStart-travel)\n local endedEarly=false\n if forced==\"Day\" then -- the admin panel ends the night: lower the wall and start a full day\n  forced=nil\n  endedEarly=true\n  s.NextDayStart=workspace:GetServerTimeNow()+travel\n  print(\"[DayNightCycle] day forced by the admin panel\")\n end\n moveBarrier(lowered,travel)\n nightWait(s.NextDayStart)\n if barrierTween then barrierTween:Cancel() end\n driver.Value=lowered\n return endedEarly\nend\n"},
	{"while true do\n local s=schedule(workspace:GetServerTimeNow())\n if workspace:GetServerTimeNow()<s.NightStart then runDay(s) end\n runNight(s)\nend",
	 "local pending -- a schedule the admin panel asked for: a forced day is a full day from now, off the shared clock\nwhile true do\n local s=pending or schedule(workspace:GetServerTimeNow())\n pending=nil\n if workspace:GetServerTimeNow()<s.NightStart then runDay(s) end\n if runNight(s) then\n  local now=workspace:GetServerTimeNow()\n  pending={Day=s.Day+1,DayStart=now,NightStart=now+s.DaySeconds,NextDayStart=now+s.DaySeconds+s.NightSeconds,DaySeconds=s.DaySeconds,NightSeconds=s.NightSeconds}\n end\nend"},
})

--..7) mirrors of the scripts patched in place (receive.ps1 on 8766; skipped if it is not running)..--
mirror(ServerScriptService.CucumberCarry, "CucumberCarry.server.lua")
mirror(ServerScriptService.CucumberSpawner, "CucumberSpawner.server.lua")
mirror(ServerScriptService.DayNightCycle, "DayNightCycle.server.lua")

print("[install base-save]\n" .. table.concat(report, "\n"))
return table.concat(report, "\n")
