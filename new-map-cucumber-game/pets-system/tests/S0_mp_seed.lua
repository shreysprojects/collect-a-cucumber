--[[
	S0_mp_seed.lua  (pets-system/tests, S0b integration agent, 2026-09-22)
	Load-scenario seed for the S0 baseline and its S8 repeat. PASTE this whole file into
	mcp__robloxstudio__eval_server_runtime (the server VM has no loadstring / HTTP) during a
	multiplayer_playtest. Studio's test players are Player1..N with UserIds -1..-N on fresh
	PetTest_-N keys, so they have no cucumbers and a night / ZombieDev raid skips them
	("nobody has cucumbers placed"). This places the fixture profile's two cucumber records
	(Spawn Cucumber Tree 2.14/s + MASSIVE Snow Frozen Tree 40,215.27/s = 40,217.41/s, threat
	score 41.743 -> level 5) on every test player's plot through CucumberCarryAPI.RestorePlaced,
	exactly the way BaseSave restores them.
	Only negative UserIds are touched. Never run it for UserId 140977250.
	Then fire the raid in the same VM:  workspace:SetAttribute("ZombieDev", "raid")
	With no builds on the plot the zombies steal both cucumbers (ZombiesWin), which also leaves
	the scratch keys PetTest_-N with 0 cucumbers again. If any seeded cucumber is left when you
	finish, destroy it before you stop (the tag removal re-snapshots the empty base).
	Gotcha: BuildCatalog.BackZ returns more than one value, so wrap it in parentheses before
	passing it to CFrame.new ("Invalid number of arguments: 4" otherwise).
]]
local Players = game:GetService("Players")
local SS = game:GetService("ServerStorage")
local BuildCatalog = require(game:GetService("ReplicatedStorage").Modules.BuildCatalog)
local restore = SS.CucumberCarryAPI.RestorePlaced
local function U(t) return CFrame.new(t[1], t[2], t[3], t[4], t[5], t[6], t[7], t[8], t[9], t[10], t[11], t[12]) end
local recs = {
	{Golden = false, Type = "Cucumber Tree", Name = "Cucumber Tree", Zone = "Spawn", Size = {5.827699184417725, 8.9362211227417, 6}, Mutations = "", Pivot = {1, 4.6542816162109375, 15, 0.6946608424186707, 0.00000036328424357634503, -0.7193417549133301, 0.00000041350833157594025, 0.9999994039535522, -0.00000010570506248086531, 0.7193423509597778, 0.00000022402304011848173, 0.694660484790802}, Box = {1, 4.6542816162109375, 15, 1,0,0, 0,1,0, 0,0,1}},
	{Type = "Frozen Tree", Zone = "Snow", SizeTier = "MASSIVE", Golden = false, Name = "MASSIVE Frozen Tree", Mutations = "", Size = {6.62786865234375, 29.3607120513916, 8.601905822753906}, Pivot = {-12, 12.899993896484375, 11, 0.992546796798706, 0.0000014447634839598322, 0.12186980247497559, -0.0000011377832151993061, 0.9999996423721313, -0.00000011560093327034338, -0.12186887115240097, -0.00000001964028939482887, 0.9925459027290344}, Box = {-12, 12.899993896484375, 11, 0,0,-1, 0,1,0, 1,0,0}},
}
local out = {}
for _, p in ipairs(Players:GetPlayers()) do
	local plot
	for _, pl in ipairs(workspace.Map.Lobby.Plots:GetChildren()) do if pl:GetAttribute("Owner") == p.UserId then plot = pl end end
	if plot and p.UserId < 0 then
		local backZ = (BuildCatalog.BackZ(plot))
		local anchor = plot.CFrame * CFrame.new(0, plot.Size.Y * 0.5, backZ)
		for _, rec in ipairs(recs) do
			local s = rec.Size
			local ok, res, reason = pcall(restore.Invoke, restore, p, plot, rec, anchor * U(rec.Pivot), anchor * U(rec.Box), Vector3.new(s[1], s[2], s[3]))
			table.insert(out, ("%s %s: %s %s"):format(p.Name, rec.Name, tostring(ok and res and res.Name or res), tostring(reason)))
		end
	end
end
return table.concat(out, "\n") .. ("\nphase %s ends in %.1f"):format(tostring(workspace:GetAttribute("CyclePhase")), (workspace:GetAttribute("PhaseEndsAt") or 0) - workspace:GetServerTimeNow())
