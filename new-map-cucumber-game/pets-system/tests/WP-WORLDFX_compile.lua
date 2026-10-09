-- WP-WORLDFX compile check (2026-09-22): loadstring every file this package wrote, from the
-- loopback servers (src :8793, patched :8794). Read-only: nothing is run, nothing is created.
local H = game:GetService("HttpService")
local FILES = {
	{"http://127.0.0.1:8793/", "StarterPlayer.StarterPlayerScripts.PetEffectsClient.client.lua"},
	{"http://127.0.0.1:8793/", "StarterPlayer.StarterPlayerScripts.PetCardClient.client.lua"},
	{"http://127.0.0.1:8794/", "StarterPlayer.StarterPlayerScripts.PetRoamClient.client.lua"},
	{"http://127.0.0.1:8794/", "StarterPlayer.StarterPlayerScripts.PlacedCucumberCardClient.client.lua"},
}
local pass, fail, notes = 0, 0, {}
for _, f in ipairs(FILES) do
	local ok, src = pcall(H.GetAsync, H, f[1] .. f[2])
	if not ok then
		fail += 1
		table.insert(notes, f[2] .. ": fetch " .. tostring(src))
	else
		src = src:gsub("\r\n", "\n")
		local fn, err = loadstring(src)
		if fn then
			pass += 1
			table.insert(notes, f[2] .. ": ok (" .. #src .. " bytes)")
		else
			fail += 1
			table.insert(notes, f[2] .. ": COMPILE " .. tostring(err))
		end
	end
end
return ("WP-WORLDFX compile: PASS %d / FAIL %d: %s"):format(pass, fail, table.concat(notes, " | "))
