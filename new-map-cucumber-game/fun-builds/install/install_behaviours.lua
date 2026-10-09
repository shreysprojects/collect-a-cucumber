--[[
	fun-builds/install/install_behaviours.lua  (2026-09-24) -- edit-mode execute_luau with serve.ps1 on the stage folder:
	  local f = loadstring(game:GetService("HttpService"):GetAsync(BASE .. "install_behaviours.lua"))()
	  return f(BASE, dryRun)
	Reads _behaviours.json = {{File = "srv__TV.lua", Kind = "server"|"client", Name = "TV"}, ...} and writes each into
	ServerStorage.FunBehaviours.<Name> / ReplicatedStorage.FunBehavioursClient.<Name> (ModuleScripts), after a loadstring
	compile check. Also {Kind = "script", Parent = "StarterPlayer.StarterPlayerScripts", Class = "LocalScript", Name = ...}
	entries for stand-alone scripts. Nothing is written for an entry that does not compile.
]]
return function(BASE, dryRun)
	local HttpService = game:GetService("HttpService")
	local list = HttpService:JSONDecode(HttpService:GetAsync(BASE .. "_behaviours.json"))
	local function resolve(path)
		local inst = game
		for part in path:gmatch("[^%.]+") do inst = inst and inst:FindFirstChild(part) end
		return inst
	end
	local function folder(parent, name)
		local f = parent:FindFirstChild(name)
		if not f then
			f = Instance.new("Folder")
			f.Name = name
			f.Parent = parent
		end
		return f
	end
	local out = {}
	for _, e in ipairs(list) do
		local ok, src = pcall(HttpService.GetAsync, HttpService, BASE .. e.File)
		if not ok then
			table.insert(out, e.File .. ": FETCH FAILED")
			continue
		end
		local fn, err = loadstring(src)
		if not fn then
			table.insert(out, e.File .. ": COMPILE " .. tostring(err))
			continue
		end
		local parent, class
		if e.Kind == "server" then
			parent, class = folder(game:GetService("ServerStorage"), "FunBehaviours"), "ModuleScript"
		elseif e.Kind == "client" then
			parent, class = folder(game:GetService("ReplicatedStorage"), "FunBehavioursClient"), "ModuleScript"
		else
			parent, class = resolve(e.Parent), e.Class or "LocalScript"
		end
		if not parent then
			table.insert(out, e.File .. ": NO PARENT " .. tostring(e.Parent))
			continue
		end
		local s = parent:FindFirstChild(e.Name)
		local status = s and (s.Source == src and "same" or "updated") or "new"
		if not dryRun and status ~= "same" then
			if s and s.ClassName ~= class then s:Destroy() s = nil end
			if not s then
				s = Instance.new(class)
				s.Name = e.Name
				s.Parent = parent
			end
			s.Source = src
		end
		table.insert(out, ("%s -> %s.%s [%s] %d"):format(e.File, parent:GetFullName(), e.Name, status, #src))
	end
	return table.concat(out, "\n")
end
