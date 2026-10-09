"""Builds manage-ui/stage/ for serve.ps1 (2026-09-23):
  * patched/<file>   = orig/<file> (the live mirror) + the surgical hunks below (each old text must occur
                       exactly once), LF line endings
  * stage/patches.json for pets-remake/apply_patches.lua (applied to the LIVE Source at push time)
  * stage/_install.json + the src/ files for pets-system/tools/install_new.lua
  * copies of apply_patches.lua / install_new.lua
    py build_stage.py
"""
import json, os, shutil, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GAMES = os.path.dirname(os.path.dirname(ROOT))
ORIG, PATCHED, SRC, STAGE = [os.path.join(ROOT, d) for d in ("orig", "patched", "src", "stage")]

PATCHES = {
    "ServerStorage.PetService.lua": ("game.ServerStorage.PetService", [
        (
"""local function RequestSave(player)
	if DataService and type(DataService.RequestSave) == "function" then
		pcall(DataService.RequestSave, player)
	end
end
""",
"""local function RequestSave(player)
	if DataService and type(DataService.RequestSave) == "function" then
		pcall(DataService.RequestSave, player)
	end
end

--.. 2026-09-23 (Manage panel): the roster limit grows with the plot level - ReplicatedStorage.Modules.ManageConfig
--.. .PetCapacity(Data.PlotLevel), never above SLOTS; without that module (or a profile) it is SLOTS. A roster that
--.. is already bigger keeps its pets (nothing is unequipped for it); new equips wait for room.
local ManageConfigCache = nil
local function SlotsOf(player)
	if ManageConfigCache == nil then
		local modules = ReplicatedStorage:FindFirstChild("Modules")
		local module = modules and modules:FindFirstChild("ManageConfig")
		local ok, result = false, nil
		if module then ok, result = pcall(require, module) end
		ManageConfigCache = (ok and type(result) == "table" and type(result.PetCapacity) == "function") and result or false
	end
	if not ManageConfigCache then return SLOTS end
	local data = GetDataOf(player)
	local ok, n = pcall(ManageConfigCache.PetCapacity, data and data.PlotLevel or 0)
	if ok and Finite(n) then return math.clamp(math.floor(n), 1, SLOTS) end
	return SLOTS
end
"""),
        ("\t\tSlots = SLOTS, MaxOwned = MAX_OWNED, IsSpawnable = IsSpawnable, Index = rt.Index, Pending = queued,",
         "\t\tSlots = SlotsOf(player), MaxOwned = MAX_OWNED, IsSpawnable = IsSpawnable, Index = rt.Index, Pending = queued,"),
        ("\t\tSlots = SLOTS, Locked = PetService.IsCombatLocked(player), HasPlot = HasPlot(player, rt),",
         "\t\tSlots = SlotsOf(player), Locked = PetService.IsCombatLocked(player), HasPlot = HasPlot(player, rt),"),
        ("\tend, IsSpawnable, mode, SLOTS)", "\tend, IsSpawnable, mode, SlotsOf(player))"),
        ("\t\tSlots = SLOTS, EquippedIds = {}, Pets = {}, Totals = TotalsOf(player),",
         "\t\tSlots = SlotsOf(player), EquippedIds = {}, Pets = {}, Totals = TotalsOf(player),"),
        ("\t\tif #roster >= SLOTS then break end", "\t\tif #roster >= SlotsOf(player) then break end"),
        (
"""		if #upserts > 0 then payload.Upserts = upserts end
		if pd.Roster then
""",
"""		if #upserts > 0 then payload.Upserts = upserts end
		if pd.Removed then -- 2026-09-23: sold pets leave the client's inventory
			local removed = {}
			for id in pairs(pd.Removed) do table.insert(removed, id) end
			if #removed > 0 then payload.Removed = removed end
		end
		if pd.Roster then
"""),
        (
"""QueueDelta = function(player, petId, roster, lock)
""",
"""QueueDelta = function(player, petId, roster, lock, removedId)
"""),
        (
"""	if lock then pd.Lock = true end
end
""",
"""	if lock then pd.Lock = true end
	if removedId then -- 2026-09-23 (Sell)
		pd.Removed = pd.Removed or {}
		pd.Removed[removedId] = true
	end
end
"""),
        (
"""--.. budget (a client request only: the session's ChurnLimiter) = the models this swap would spawn + despawn;
""",
"""--.. 2026-09-23 (Manage panel): SELL - the pet leaves the roster, its record leaves Data.Base.Pets for good and
--.. the client hears a Delta with Removed. Refused while combat-locked or mid-reveal (PresentationPending).
--.. The caller pays the cash (ManageService: ManageConfig.PetSellValue(stats.Income)).
--.. Returns true, nil, record, stats | false, err
function PetService.Sell(player, petId)
	local rt, data, err = RosterGuard(player)
	if not rt then return false, err end
	if PetService.IsCombatLocked(player) then return false, "CombatLocked" end
	if not IsValidId(petId) then return false, "BadRequest" end
	local rp = rt.Pets[petId]
	if not rp then return false, "NotOwned" end
	if rp.PresentationPending then return false, "Unavailable" end
	local base = data.Base
	if type(base.Pets) ~= "table" or base.Pets ~= rt.PetsArray then return false, "NotLoaded" end
	local queued = table.find(rt.PendingAutoEquip, petId)
	if queued then table.remove(rt.PendingAutoEquip, queued) end
	local roster = RosterArray(base)
	if table.find(roster, petId) then SetRoster(base, Core.Unequip(roster, petId)) end
	if rp.Model or rp.Producer then Despawn(rt, rp) end
	local index
	for i, rec in ipairs(base.Pets) do
		if rec == rp.Record then index = i break end
	end
	if index then table.remove(base.Pets, index) end
	rt.KnownCount = #base.Pets
	rt.Pets[petId] = nil
	rt.Spawned[petId] = nil
	if rt.Index.ById[petId] == rp.Record then rt.Index.ById[petId] = nil end
	local eggId = rp.Record.SourceEggId
	if IsValidId(eggId) and rt.Index.BySourceEgg[eggId] == rp.Record then rt.Index.BySourceEgg[eggId] = nil end
	ActiveDirty = true
	QueueDelta(player, nil, true, false, petId)
	RequestSave(player)
	return true, nil, rp.Record, rp.Stats
end

--.. budget (a client request only: the session's ChurnLimiter) = the models this swap would spawn + despawn;
"""),
    ]),
    "StarterGui.CucumberMenus.PetController.lua": ("game.StarterGui.CucumberMenus.PetController", [
        ("\t\tnew.EquippedIds = CleanIds(payload.EquippedIds, slots)",
         "\t\tnew.EquippedIds = CleanIds(payload.EquippedIds, Core.MAX_SLOTS) -- 2026-09-23: a roster over the plot's capacity is still shown whole"),
        ("\t\tif payload.EquippedIds ~= nil then new.EquippedIds = CleanIds(payload.EquippedIds, new.Slots) end",
         "\t\tif payload.EquippedIds ~= nil then new.EquippedIds = CleanIds(payload.EquippedIds, Core.MAX_SLOTS) end"),
        ("\tfor i = 1, slots do\n\t\tlocal id = equippedIds[i]",
         "\tfor i = 1, math.max(slots, #equippedIds) do -- 2026-09-23: an over-capacity roster (plot level) still shows every active pet\n\t\tlocal id = equippedIds[i]"),
    ]),
    "StarterGui.CucumberMenus.MenuController.lua": ("game.StarterGui.CucumberMenus.MenuController", [
        (
"""local OPENERS = {Shop = {"LeftMenu", "Shop", "OpenShop"}, Index = {"LeftMenu", "Index", "OpenIndex"}, Pets = {"LeftMenu", "Pets", "OpenPets"}}
local OPTIONAL = {Pets = true}
local CLOSE_ON_BASE = {Shop = true, Index = true} -- their openers tuck away inside the base; Pets stays open
""",
"""local OPENERS = {Shop = {"LeftMenu", "Shop", "OpenShop"}, Index = {"LeftMenu", "Index", "OpenIndex"}, Pets = {"LeftMenu", "Pets", "OpenPets"}, Manage = {"LeftMenu", "Manage", "ManageButton"}}
local OPTIONAL = {Pets = true, Manage = true}
local CLOSE_ON_BASE = {Shop = true, Index = true} -- their openers tuck away inside the base; Pets stays open
-- 2026-09-23: Manage's opener only shows inside the base (BaseHUDController), so leaving the base closes it;
-- BaseHUDController already gives that button its hover / press pop (HoverScale), so MenuController must not
local CLOSE_OUTSIDE = {Manage = true}
local NO_HOVER = {Manage = true}
"""),
        (
"""    if petsPanel and petsPanel:FindFirstChild("Content") then panels.Pets = petsPanel.Content end
""",
"""    if petsPanel and petsPanel:FindFirstChild("Content") then panels.Pets = petsPanel.Content end
    -- 2026-09-23: the Manage panel (ManageController fills it)
    local managePanel = gui:FindFirstChild("ManagePanel")
    if managePanel and managePanel:FindFirstChild("Content") then panels.Manage = managePanel.Content end
"""),
        (
"""            hover(opener, opener.Parent)
        end
""",
"""            if not NO_HOVER[name] then hover(opener, opener.Parent) end
        end
"""),
        (
"""        if hud:GetAttribute("BaseMode") and activeName and CLOSE_ON_BASE[activeName] then show(nil) end
""",
"""        if hud:GetAttribute("BaseMode") and activeName and CLOSE_ON_BASE[activeName] then show(nil) end
        if not hud:GetAttribute("BaseMode") and activeName and CLOSE_OUTSIDE[activeName] then show(nil) end
"""),
    ]),
    "StarterGui.CucumberMenus.MenuClient.client.lua": ("game.StarterGui.CucumberMenus.MenuClient", [
        (
"""if not okPets then warn("[MenuClient] Pets menu unavailable: "..tostring(pets)) pets=nil end
script.Destroying:Connect(function() if pets then pets.Destroy() end;shop.Destroy();index.Destroy();menus.Destroy() end)""",
"""if not okPets then warn("[MenuClient] Pets menu unavailable: "..tostring(pets)) pets=nil end
-- 2026-09-23: the Manage panel, guarded the same way
local okManage,manage=pcall(function() return require(script.Parent.ManageController).Start(script.Parent,menus) end)
if not okManage then warn("[MenuClient] Manage menu unavailable: "..tostring(manage)) manage=nil end
script.Destroying:Connect(function() if manage then manage.Destroy() end;if pets then pets.Destroy() end;shop.Destroy();index.Destroy();menus.Destroy() end)"""),
    ]),
    "ServerScriptService.CucumberCarry.server.lua": ("game.ServerScriptService.CucumberCarry", [
        (
"""local PetBuffs = Lazy("PetBuffService") -- StampFromRecord / ClearCucumber
""",
"""local PetBuffs = Lazy("PetBuffService") -- StampFromRecord / ClearCucumber
--.. 2026-09-23 (Manage panel): a base holds ManageConfig.CucumberCapacity(PlotLevel) placed cucumbers; without
--.. the module there is no cap. Restores (RestorePlaced) never count against it, placements (Place) do.
local ManageConfigCache = nil
local function CucumberCapacityOf(plot)
	if ManageConfigCache == nil then
		local modules = ReplicatedStorage:FindFirstChild("Modules")
		local module = modules and modules:FindFirstChild("ManageConfig")
		local ok, result = false, nil
		if module then ok, result = pcall(require, module) end
		ManageConfigCache = (ok and type(result) == "table" and type(result.CucumberCapacity) == "function") and result or false
	end
	if not ManageConfigCache then return nil end
	local ok, n = pcall(ManageConfigCache.CucumberCapacity, plot:GetAttribute("PlotLevel") or 0)
	if ok and type(n) == "number" and n == n then return math.floor(n) end
	return nil
end
"""),
        (
"""		return false, "not at base"
	end
	local model = entry.Model
""",
"""		return false, "not at base"
	end
	--.. 2026-09-23: the base's cucumber capacity (Manage panel); at it the placement is refused "base full"
	local capacity = CucumberCapacityOf(plot)
	if capacity then
		local standing = 0
		for _, placed in ipairs(HolderOf(plot):GetChildren()) do
			if placed:IsA("Model") and CollectionService:HasTag(placed, "PlacedCucumber") and placed:GetAttribute("Owner") == player.UserId then standing += 1 end
		end
		if standing >= capacity then return false, "base full" end
	end
	local model = entry.Model
"""),
    ]),
    "StarterPlayer.StarterPlayerScripts.CucumberPlacementClient.client.lua": ("game.StarterPlayer.StarterPlayerScripts.CucumberPlacementClient", [
        (
"""		elseif reason == "occupied" then
			Notify.Warn("Something is already standing there.")
		end
""",
"""		elseif reason == "occupied" then
			Notify.Warn("Something is already standing there.")
		elseif reason == "base full" then -- 2026-09-23: ManageConfig.CucumberCapacity (Manage panel)
			Notify.Warn("Your base is full. Upgrade your plot or sell a cucumber in Manage.")
		end
"""),
    ]),
    "ServerStorage.DataService.lua": ("game.ServerStorage.DataService", [
        (
"""	PortalCooldowns = {}, -- [PortalDestination] = server time (unix s) the portal opens again for this player (PortalService, 2026-09-22)
}
""",
"""	PortalCooldowns = {}, -- [PortalDestination] = server time (unix s) the portal opens again for this player (PortalService, 2026-09-22)
	Defense = {Survived = {}, LastSeen = 0, OfflineRate = 0, Level = 1}, -- zombie defence (ManageService, 2026-09-23): night raids survived per threat level (Survived["<level>"]), last-seen time + cucumber cash/s + threat level for offline earnings
}
"""),
    ]),
    "ServerScriptService.ZombieRaidService.server.lua": ("game.ServerScriptService.ZombieRaidService", [
        (
"""local TargetInfosAPI = Bindable("TargetInfos") -- 2026-09-22: pet targeting (primitives + the Model)
API.Parent = ServerStorage
""",
"""local TargetInfosAPI = Bindable("TargetInfos") -- 2026-09-22: pet targeting (primitives + the Model)
local ThreatLevelAPI = Bindable("ThreatLevel") -- 2026-09-23 (Manage panel): (player) -> level, score, cucumbers a raid would be right now
local RaidResultEvent = Instance.new("BindableEvent") -- 2026-09-23 (Manage panel): (player, {Result, Level, Stolen, Limit}) at every night raid's end
RaidResultEvent.Name = "RaidResult"
RaidResultEvent.Parent = API
local function ReportResult(raid, result)
	if raid.Day or not raid.Player then return end
	RaidResultEvent:Fire(raid.Player, {Result = result, Level = raid.Level, Stolen = raid.Stolen, Limit = raid.Limit})
end
API.Parent = ServerStorage
"""),
        (
"""		Send(raid, {Kind = "Survived", Level = raid.Level, Stolen = raid.Stolen, Limit = raid.Limit})
		print(("[ZombieRaid] %s survived (level %d, stolen %d/%d)"):format(raid.Player.Name, raid.Level, raid.Stolen, raid.Limit))
""",
"""		Send(raid, {Kind = "Survived", Level = raid.Level, Stolen = raid.Stolen, Limit = raid.Limit})
		print(("[ZombieRaid] %s survived (level %d, stolen %d/%d)"):format(raid.Player.Name, raid.Level, raid.Stolen, raid.Limit))
		ReportResult(raid, "Survived") -- 2026-09-23 (Manage panel: days survived)
"""),
        (
"""		Send(raid, {Kind = "ZombiesWin", Stolen = raid.Stolen, Limit = raid.Limit})
		print(("[ZombieRaid] the zombies win against %s"):format(raid.Player.Name))
""",
"""		Send(raid, {Kind = "ZombiesWin", Stolen = raid.Stolen, Limit = raid.Limit})
		print(("[ZombieRaid] the zombies win against %s"):format(raid.Player.Name))
		ReportResult(raid, "ZombiesWin") -- 2026-09-23 (Manage panel)
"""),
        (
"""			Send(raid, {Kind = raid.Stolen == 0 and "Survived" or "Dawn", Stolen = raid.Stolen, Limit = raid.Limit, Level = raid.Level})
			print(("[ZombieRaid] dawn for %s: stolen %d/%d -> %s"):format(raid.Player.Name, raid.Stolen, raid.Limit, raid.Stolen == 0 and "won the night" or "night over"))
""",
"""			Send(raid, {Kind = raid.Stolen == 0 and "Survived" or "Dawn", Stolen = raid.Stolen, Limit = raid.Limit, Level = raid.Level})
			print(("[ZombieRaid] dawn for %s: stolen %d/%d -> %s"):format(raid.Player.Name, raid.Stolen, raid.Limit, raid.Stolen == 0 and "won the night" or "night over"))
			ReportResult(raid, raid.Stolen == 0 and "Survived" or "Dawn") -- 2026-09-23 (Manage panel: days survived)
"""),
        (
"""	return ZombieCatalog.LevelOf(score), score, #cucumbers
end

local function NewRaid(player, plot, forcedLevel, isDay)
""",
"""	return ZombieCatalog.LevelOf(score), score, #cucumbers
end
ThreatLevelAPI.OnInvoke = function(player) -- 2026-09-23 (Manage panel): the level a raid would be right now
	if typeof(player) ~= "Instance" or not player:IsA("Player") then return nil end
	local plot = PlotOf(player)
	if not plot then return nil end
	return ThreatOf(player, plot)
end

local function NewRaid(player, plot, forcedLevel, isDay)
"""),
    ]),
}

SRC_FILES = [
    ("ReplicatedStorage.Modules.ManageConfig.lua", "ReplicatedStorage.Modules.ManageConfig", "ModuleScript"),
    ("ServerScriptService.ManageService.server.lua", "ServerScriptService.ManageService", "Script"),
    ("StarterGui.CucumberMenus.ManageController.lua", "StarterGui.CucumberMenus.ManageController", "ModuleScript"),
]


def main():
    if os.path.isdir(STAGE):
        shutil.rmtree(STAGE)
    os.makedirs(STAGE)
    os.makedirs(PATCHED, exist_ok=True)
    entries = []
    for fname, (path, hunks) in PATCHES.items():
        text = open(os.path.join(ORIG, fname), encoding="utf-8").read().replace("\r\n", "\n")
        edits = []
        for old, new in hunks:
            n = text.count(old)
            if n != 1:
                sys.exit("%s: hunk occurs %d times:\n%s" % (fname, n, old[:200]))
            text = text.replace(old, new)
            edits.append({"old": old, "new": new})
        with open(os.path.join(PATCHED, fname), "w", encoding="utf-8", newline="\n") as f:
            f.write(text)
        entries.append({"path": path, "file": fname, "edits": edits})
        print(fname, len(edits), "edits ->", len(text), "chars")
    with open(os.path.join(STAGE, "patches.json"), "w", encoding="utf-8") as f:
        json.dump(entries, f, indent=1)
    install = []
    for fname, path, cls in SRC_FILES:
        text = open(os.path.join(SRC, fname), encoding="utf-8").read().replace("\r\n", "\n")
        with open(os.path.join(STAGE, fname), "w", encoding="utf-8", newline="\n") as f:
            f.write(text)
        install.append({"file": fname, "path": path, "class": cls})
        print(fname, "->", len(text), "chars")
    with open(os.path.join(STAGE, "_install.json"), "w", encoding="utf-8") as f:
        json.dump(install, f, indent=1)
    shutil.copy(os.path.join(GAMES, "pets-remake", "apply_patches.lua"), STAGE)
    shutil.copy(os.path.join(GAMES, "new-map-cucumber-game", "pets-system", "tools", "install_new.lua"), STAGE)
    print("staged ->", STAGE)


if __name__ == "__main__":
    main()
