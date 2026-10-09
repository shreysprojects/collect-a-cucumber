-- Installs NEW scripts from pets-system/src through a loopback serve.ps1 (2026-09-22).
--   local f = loadstring(HttpService:GetAsync(BASE .. "install_new.lua"))()
--   return f(BASE, dryRun, onlyFiles)   -- onlyFiles = optional set {["ServerStorage.PetService.lua"] = true}
-- BASE serves pets-system/src (flat) and _install.json = [{file, path, class}].
-- All-or-nothing per call: every selected file must download, compile and have an existing parent,
-- otherwise nothing is written. Existing instances of the right class get their Source replaced;
-- missing ones are created. Returns a report string.
return function(BASE, dryRun, onlyFiles)
	local H = game:GetService("HttpService")
	local entries = H:JSONDecode(H:GetAsync(BASE .. "_install.json"))
	local function resolve(path)
		local inst = game
		for part in path:gmatch("[^%.]+") do
			if inst == game then
				local ok, svc = pcall(game.GetService, game, part)
				inst = ok and svc or game:FindFirstChild(part)
			else
				inst = inst and inst:FindFirstChild(part)
			end
		end
		return inst
	end
	local plan, out, ok = {}, {}, true
	for _, e in ipairs(entries) do
		if onlyFiles and not onlyFiles[e.file] then continue end
		local parentPath, name = e.path:match("^(.*)%.([^%.]+)$")
		local parent = parentPath and resolve(parentPath)
		local src = H:GetAsync(BASE .. H:UrlEncode(e.file))
		src = src:gsub("\r\n", "\n")
		local fn, err = loadstring(src)
		local existing = parent and parent:FindFirstChild(name)
		local note
		if not parent then
			ok = false
			note = "NO PARENT " .. tostring(parentPath)
		elseif not fn then
			ok = false
			note = "COMPILE " .. tostring(err)
		elseif existing and existing.ClassName ~= e.class then
			ok = false
			note = "CLASS MISMATCH " .. existing.ClassName
		else
			note = existing and ("update " .. #existing.Source .. " -> " .. #src) or ("create " .. #src)
			table.insert(plan, {parent = parent, name = name, class = e.class, src = src, existing = existing})
		end
		table.insert(out, e.path .. ": " .. note)
	end
	if ok and not dryRun then
		for _, p in ipairs(plan) do
			local inst = p.existing
			if not inst then
				inst = Instance.new(p.class)
				inst.Name = p.name
				inst.Source = p.src
				inst.Parent = p.parent
			elseif inst.Source ~= p.src then
				inst.Source = p.src
			end
		end
		table.insert(out, "WRITTEN " .. #plan)
	else
		table.insert(out, (dryRun and "DRY RUN" or "BLOCKED") .. " (" .. #plan .. " ready)")
	end
	return table.concat(out, "\n")
end
