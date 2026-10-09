-- appended after manifest.lua (SCRIPTS, DIRS); runs in the edit peer
local function resolve(path)
	local inst = game
	for seg in string.gmatch(path, "[^%.]+") do
		if inst == game then
			local ok, svc = pcall(function() return game:GetService(seg) end)
			inst = ok and svc or nil
		else
			inst = inst:FindFirstChild(seg)
		end
		if not inst then return nil end
	end
	return inst
end
local function ck(s)
	s = string.gsub(s, "\r\n", "\n")
	local h = 0
	for i = 1, #s do h = (h * 31 + string.byte(s, i)) % 2147483647 end
	return h, #s
end
local known = {}
local out = {}
local equal = 0
for _, e in ipairs(SCRIPTS) do
	local path, cls, n, h = e[1], e[2], e[3], e[4]
	known[path] = true
	local inst = resolve(path)
	if not inst then
		table.insert(out, "MISSING " .. path)
	elseif inst.ClassName ~= cls then
		table.insert(out, "CLASS " .. path .. " studio=" .. inst.ClassName .. " repo=" .. cls)
	else
		local sh, sn = ck(inst.Source)
		if sh ~= h or sn ~= n then
			table.insert(out, string.format("DIFF %s studio=%d/%d repo=%d/%d", path, sn, sh, n, h))
		else
			equal += 1
		end
	end
end
-- children a sync would delete (non-ignored dirs) + Studio-only scripts in ignored dirs
local dirIgnore = {}
for p, d in pairs(DIRS) do
	dirIgnore[p] = d.ignore
	local inst = resolve(p)
	if inst then
		local set = {}
		for _, c in ipairs(d.children) do set[c] = true end
		for _, ch in ipairs(inst:GetChildren()) do
			if not set[ch.Name] then
				if not d.ignore then
					table.insert(out, "WOULD-DELETE " .. p .. "." .. ch.Name .. " (" .. ch.ClassName .. ")")
				elseif ch:IsA("LuaSourceContainer") then
					table.insert(out, "STUDIO-ONLY-SCRIPT " .. p .. "." .. ch.Name .. " (" .. ch.ClassName .. ")")
				end
			end
		end
	else
		table.insert(out, "DIR-MISSING " .. p)
	end
end
-- any script under the managed roots not in the manifest (skip ServerStorage.Assets / Backups trees)
local roots = {"ReplicatedFirst", "ReplicatedStorage", "ServerScriptService", "ServerStorage", "StarterPlayer.StarterPlayerScripts"}
local skipped = {}
for _, r in ipairs(roots) do
	local inst = resolve(r)
	if inst then
		for _, d in ipairs(inst:GetDescendants()) do
			if d:IsA("LuaSourceContainer") then
				local p = d:GetFullName()
				if not known[p] then
					if string.find(p, "^ServerStorage%.Assets") or string.find(p, "^ServerStorage%.Backups") then
						local key = string.match(p, "^(ServerStorage%.%w+)")
						skipped[key] = (skipped[key] or 0) + 1
					elseif not string.find(table.concat(out, "\n"), p, 1, true) then
						table.insert(out, "UNKNOWN-SCRIPT " .. p .. " (" .. d.ClassName .. ")")
					end
				end
			end
		end
	end
end
for k, v in pairs(skipped) do table.insert(out, string.format("(skipped %d scripts under %s, ignored tree)", v, k)) end
table.insert(out, 1, string.format("equal=%d of %d scripts", equal, #SCRIPTS))
return table.concat(out, "\n")
