-- Surgical script patcher: applies {old -> new} edits to the LIVE Source of each script, so
-- concurrent edits other sessions made elsewhere in the same scripts survive. Every edit must
-- match exactly once (plain text); an edit whose NEW text is already present is "already applied".
-- Nothing is written unless every edit of that script resolves and the result compiles.
--   local f = loadstring(HttpService:GetAsync(BASE .. "apply_patches.lua"))()
--   f(BASE, dryRun)
return function(BASE, dryRun)
	local H = game:GetService("HttpService")
	local patches = H:JSONDecode(H:GetAsync(BASE .. "patches.json"))
	local function count(hay, needle)
		local n, i = 0, 1
		while true do
			local s, e = string.find(hay, needle, i, true)
			if not s then return n end
			n += 1
			i = e + 1
		end
	end
	local function resolve(path)
		local inst = game
		for part in path:gsub("^game%.", ""):gmatch("[^%.]+") do
			inst = inst and inst:FindFirstChild(part)
		end
		return inst
	end
	local out = {}
	for _, p in ipairs(patches) do
		local inst = resolve(p.path)
		if not inst then
			table.insert(out, p.path .. ": NOT FOUND")
			continue
		end
		local src = inst.Source
		local ok, notes = true, {}
		for i, e in ipairs(p.edits) do
			local nOld, nNew = count(src, e.old), count(src, e.new)
			if nOld == 1 then
				local s, f = string.find(src, e.old, 1, true)
				src = src:sub(1, s - 1) .. e.new .. src:sub(f + 1)
				table.insert(notes, i .. ":applied")
			elseif nOld == 0 and nNew == 1 then
				table.insert(notes, i .. ":already")
			else
				ok = false
				table.insert(notes, ("%d:FAIL(old x%d, new x%d)"):format(i, nOld, nNew))
			end
		end
		local fn, err = loadstring(src)
		if not fn then ok = false table.insert(notes, "COMPILE: " .. tostring(err)) end
		if ok and not dryRun and src ~= inst.Source then
			inst.Source = src
			table.insert(notes, "WRITTEN " .. #src)
		end
		table.insert(out, ("%s [%s] %s"):format(p.path, ok and "ok" or "BLOCKED", table.concat(notes, " ")))
	end
	return table.concat(out, "\n")
end
