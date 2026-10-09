--[[
	S8_realkey_check_server.lua  (pets-system/tests, S8 integration agent, 2026-09-22)
	ONE-SHOT check of the REAL-key legacy migration (ServerStorage.PetTestProfileKey cleared).
	PASTE into mcp__robloxstudio__eval_server_runtime right after solo_playtest start. Read-only except
	for one line: if the client's first Full already delivered the one-time migration notice, it
	puts PetNoticePending = true back so the user still sees it in their own first session.
	Returns one summary string. Only for UserId 140977250.
]]
local Players = game:GetService("Players")
local SS = game:GetService("ServerStorage")
local RS = game:GetService("ReplicatedStorage")
local CS = game:GetService("CollectionService")
local H = game:GetService("HttpService")
local p
local t0 = os.clock()
repeat
	p = Players:GetPlayerByUserId(140977250)
	if p and p:GetAttribute("BaseRestored") == true then break end
	task.wait(0.1)
until os.clock() - t0 > 12
if not p then return "no player 140977250" end
local DS = require(SS.DataService)
local PS = require(SS.PetService)
local IS = require(SS.IncomeService)
local PetStats = require(RS.Modules.PetStats)
local d = DS.GetData(p)
local b = d.Base
local key = DS.GetProfile(p).Key
local report = DS.GetMigrationReport(p)
-- roster in income / DPS / Id order
local byId = {}
for _, r in ipairs(b.Pets) do byId[r.Id] = r end
local rosterRows, entries = {}, {}
for i, id in ipairs(b.PetRoster or {}) do
	local r = byId[id]
	local s = r and PetStats.Calculate(r) or {}
	entries[i] = {Id = id, Stats = s}
	table.insert(rosterRows, ("%d %s %s inc=%s dps=%s"):format(i, tostring(r and r.Pet), tostring(id):sub(1, 8), tostring(s.Income), tostring(s.DPS)))
end
local ordered = true
for i = 2, #entries do
	if PetStats.Compare(entries[i], entries[i - 1], "Income") then ordered = false end
end
local petRows = {}
local allIds = true
for _, r in ipairs(b.Pets) do
	if not PetStats.IsValidId(r.Id) then allIds = false end
	table.insert(petRows, ("%s %s src=%s mat=%q muts=%s pos=%s"):format(tostring(r.Pet), tostring(r.Id):sub(1, 8), tostring(r.SourceEgg), tostring(r.Material), H:JSONEncode(r.Mutations or {}), r.Pos and H:JSONEncode(r.Pos) or "-"))
end
local eggRows = {}
for _, e in ipairs(b.Eggs) do table.insert(eggRows, ("%s %s/%s/%s"):format(tostring(e.Id):sub(1, 8), tostring(e.EggName), tostring(e.Material), tostring(e.Mutations))) end
local cucRows = {}
for _, c in ipairs(b.Cucumbers) do table.insert(cucRows, ("%s %s"):format(tostring(c.Id):sub(1, 8), tostring(c.Name))) end
local plot
for _, pl in ipairs(workspace.Map.Lobby.Plots:GetChildren()) do if pl:GetAttribute("Owner") == p.UserId then plot = pl end end
local models = plot and plot:FindFirstChild("Pets") and #plot.Pets:GetChildren() or -1
local worldCuc, worldEggs, worldBuilds = 0, 0, 0
for _, m in ipairs(CS:GetTagged("PlacedCucumber")) do if plot and m:IsDescendantOf(plot) then worldCuc += 1 end end
for _, m in ipairs(CS:GetTagged("PlacedEgg")) do if plot and m:IsDescendantOf(plot) then worldEggs += 1 end end
for _, m in ipairs(CS:GetTagged("PlacedBuild")) do if plot and m:IsDescendantOf(plot) then worldBuilds += 1 end end
local noticeBefore = b.PetNoticePending
local noticeRestored = false
if report and report.Legacy == true and b.PetNoticePending ~= true then
	b.PetNoticePending = true
	noticeRestored = true
end
local totals = IS.GetTotals and IS.GetTotals(p) or {}
local diag = H:JSONDecode(SS:GetAttribute("PetDiag") or "{}")
return table.concat({
	("key=%s restored=%s gen=%s"):format(tostring(key), tostring(p:GetAttribute("BaseRestored")), tostring(DS.GetGeneration(p))),
	"report=" .. H:JSONEncode(report or {}),
	("Base Version=%s PetSchemaVersion=%s notice(before)=%s restoredNotice=%s"):format(tostring(b.Version), tostring(b.PetSchemaVersion), tostring(noticeBefore), tostring(noticeRestored)),
	("Cash=%.2f Strength=%s PlotLevel=%s Pets=%d Eggs=%d Cucumbers=%d Builds=%d allPetIds=%s"):format(d.Cash, tostring(d.Strength), tostring(d.PlotLevel), #b.Pets, #b.Eggs, #b.Cucumbers, #b.Builds, tostring(allIds)),
	("roster (%d, income order %s): %s"):format(#(b.PetRoster or {}), tostring(ordered), table.concat(rosterRows, "; ")),
	"pets: " .. table.concat(petRows, "; "),
	"eggs: " .. table.concat(eggRows, "; "),
	"cucumbers: " .. table.concat(cucRows, "; "),
	("world on %s: pet models=%d cucumbers=%d eggs=%d builds(tag PlacedBuild)=%d"):format(plot and plot.Name or "?", models, worldCuc, worldEggs, worldBuilds),
	"totals=" .. H:JSONEncode(totals) .. (" CashPerSec=%s"):format(tostring(p:FindFirstChild("Data") and p.Data:FindFirstChild("CashPerSec") and p.Data.CashPerSec.Value)),
	("PetDiag: Pet SpawnFailures=%s SchedulerErrors=%s Invalid=%s; Income CreditFailures=%s; Combat Errors=%s; Buff Errors=%s; Modules=%s"):format(
		tostring(diag.Pet and diag.Pet.SpawnFailures), tostring(diag.Pet and diag.Pet.SchedulerErrors), tostring(diag.Pet and diag.Pet.Invalid),
		tostring(diag.Income and diag.Income.CreditFailures), tostring(diag.Combat and diag.Combat.Errors), tostring(diag.Buff and diag.Buff.Errors), H:JSONEncode(diag.Modules or {})),
	("phase=%s ends in %.1f RaidLive=%s"):format(tostring(workspace:GetAttribute("CyclePhase")), (workspace:GetAttribute("PhaseEndsAt") or 0) - workspace:GetServerTimeNow(), tostring(p:GetAttribute("RaidLive"))),
}, "\n")
