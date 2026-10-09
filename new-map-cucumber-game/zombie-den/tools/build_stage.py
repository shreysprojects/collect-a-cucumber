"""Builds zombie-den/stage/ for serve.ps1 (2026-09-24):
  * patched/<file>   = orig/<file> (the live mirror pulled 2026-09-23 23:42) + the surgical hunks below (each
                       old text must occur exactly once), LF line endings
  * stage/patches.json for pets-remake/apply_patches.lua (applied to the LIVE Source at push time)
  * stage/_install.json + the src/ files for pets-system/tools/install_new.lua
  * copies of apply_patches.lua / install_new.lua / build_denpanel.lua
    py build_stage.py
"""
import json, os, shutil, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GAMES = os.path.dirname(os.path.dirname(ROOT))
ORIG, PATCHED, SRC, STAGE = [os.path.join(ROOT, d) for d in ("orig", "patched", "src", "stage")]

PATCHES = {
    "ServerScriptService.ZombieRaidService.server.lua": ("game.ServerScriptService.ZombieRaidService", [
        # header doc
        (
"""	    took (a raid-end RestoreCarry had sent it home, then a stale rope put it back in the lobby).
]]
""",
"""	    took (a raid-end RestoreCarry had sent it home, then a stale rope put it back in the lobby).
	  * CO-OP NIGHTS (2026-09-24, user: "at night people can help each other fight each other's zombies only if
	    they're done their wave, both users get boosts"): a player's blow on ANOTHER player's night raid lands only
	    while their own raid is over (or they have none) - otherwise DamageZombie refuses it and they hear
	    "HelpBlocked". Every helper is remembered on the raid (raid.Helpers[player] = {Hits, Damage}, "HelperJoined"
	    to the owner / "Helping" to the helper on the first blow); when that raid is WON (every zombie dead, or dawn
	    with nothing stolen) the owner and every helper with HELP_MIN_HITS blows get TEAM_BOOST_SECONDS of the
	    potion boosts (ItemsCatalog.BOOSTS Cash + Strength attributes extended, never stacked) and a "Teamwork"
	    toast. Hostility is unchanged: a helped raid's zombies shove the helper too.
	  * ZOMBIE DEN (2026-09-24): every escape also fires ZombieAPI.CucumberStolen (BindableEvent: player, {Name,
	    Zone, Type}) AFTER ItemAPI.RecordLoss, so ZombieDenService can make a deal for the record it just wrote.
]]
"""),
        # modules: the potion attribute names
        (
"""local ZombieCatalog = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ZombieCatalog"))
local SoundController = require(ReplicatedStorage.Modules:WaitForChild("SoundController"))
""",
"""local ZombieCatalog = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ZombieCatalog"))
local SoundController = require(ReplicatedStorage.Modules:WaitForChild("SoundController"))
local okItems, ItemsCatalog = pcall(function() return require(ReplicatedStorage.Modules:WaitForChild("ItemsCatalog", 10)) end) -- 2026-09-24 co-op boosts: the potion attributes
if not okItems then ItemsCatalog = nil end
"""),
        # API: the stolen event + the co-op numbers
        (
"""local function ReportResult(raid, result)
	if raid.Day or not raid.Player then return end
	RaidResultEvent:Fire(raid.Player, {Result = result, Level = raid.Level, Stolen = raid.Stolen, Limit = raid.Limit})
end
API.Parent = ServerStorage
""",
"""local function ReportResult(raid, result)
	if raid.Day or not raid.Player then return end
	RaidResultEvent:Fire(raid.Player, {Result = result, Level = raid.Level, Stolen = raid.Stolen, Limit = raid.Limit})
end
local CucumberStolenEvent = Instance.new("BindableEvent") -- 2026-09-24 (Zombie Den): (player, {Name, Zone, Type}) after every theft is recorded
CucumberStolenEvent.Name = "CucumberStolen"
CucumberStolenEvent.Parent = API
API.Parent = ServerStorage
--.. 2026-09-24 CO-OP NIGHTS (see the top): helping is allowed once your own wave is done; a won raid pays both sides
local HELP_MIN_HITS = 3        -- blows a helper must land before the win counts them
local HELP_TOAST_GAP = 3       -- seconds between "finish your own wave" toasts per player
local TEAM_BOOST_SECONDS = 300 -- 2x cash + 2x strength (the potion timers) for the owner and every helper
local TEAM_BOOSTS = {"Cash", "Strength"}
local HelpToastAt = {} -- [player] = os.clock()
"""),
        # helpers after Send
        (
"""local function Send(raid, payload)
	if raid.Player and raid.Player.Parent then Remote:FireClient(raid.Player, payload) end
end
""",
"""local function Send(raid, payload)
	if raid.Player and raid.Player.Parent then Remote:FireClient(raid.Player, payload) end
end

--..Co-op nights (2026-09-24)..--
local function HelpAllowed(player) -- your own night wave is over, or you have none
	local mine = Raids[player]
	return mine == nil or mine.Over == true
end

local function HelpBlocked(player)
	local now = os.clock()
	if HelpToastAt[player] and now - HelpToastAt[player] < HELP_TOAST_GAP then return end
	HelpToastAt[player] = now
	Remote:FireClient(player, {Kind = "HelpBlocked"})
end

local function RegisterHelp(raid, player, amount)
	raid.Helpers = raid.Helpers or {}
	local h = raid.Helpers[player]
	if not h then
		h = {Hits = 0, Damage = 0}
		raid.Helpers[player] = h
		Send(raid, {Kind = "HelperJoined", Name = player.Name})
		Remote:FireClient(player, {Kind = "Helping", Name = raid.Player and raid.Player.Name or "?"})
		print(("[ZombieRaid] %s is helping %s fight their wave"):format(player.Name, raid.Player and raid.Player.Name or "?"))
	end
	h.Hits += 1
	h.Damage += amount
end

local function GrantTeamBoost(player)
	if not (player and player.Parent) then return end
	local now = workspace:GetServerTimeNow()
	for _, boost in ipairs(TEAM_BOOSTS) do
		local info = ItemsCatalog and type(ItemsCatalog.BOOSTS) == "table" and ItemsCatalog.BOOSTS[boost]
		local attr = info and info.Attr or (boost .. "BoostUntil")
		local current = tonumber(player:GetAttribute(attr)) or 0
		player:SetAttribute(attr, math.max(now, current) + TEAM_BOOST_SECONDS)
	end
end

--.. the raid was won: the owner and every helper who really fought get the team boost (once per raid)
local function RewardHelpers(raid)
	if raid.Day or raid.Rewarded or type(raid.Helpers) ~= "table" then return end
	local helpers = {}
	for helper, h in pairs(raid.Helpers) do
		if h.Hits >= HELP_MIN_HITS and helper.Parent then table.insert(helpers, helper) end
	end
	if #helpers == 0 then return end
	raid.Rewarded = true
	table.sort(helpers, function(a, b) return a.Name < b.Name end)
	local owner = raid.Player
	local ownerName = owner and owner.Name or "?"
	local names = {}
	for _, helper in ipairs(helpers) do table.insert(names, helper.Name) end
	for _, helper in ipairs(helpers) do
		GrantTeamBoost(helper)
		Remote:FireClient(helper, {Kind = "Teamwork", With = ownerName, Seconds = TEAM_BOOST_SECONDS})
	end
	if owner and owner.Parent then
		GrantTeamBoost(owner)
		Send(raid, {Kind = "Teamwork", With = table.concat(names, ", "), Seconds = TEAM_BOOST_SECONDS})
	end
	print(("[ZombieRaid] teamwork: %s's wave was won with %s -> %d s of 2x cash + 2x strength for all of them"):format(ownerName, table.concat(names, ", "), TEAM_BOOST_SECONDS))
end
"""),
        # DamageZombie: the gate + the helper record, before the blow lands
        (
"""	if entry.Shaded or entry.Underground then return false, entry.Humanoid.Health end -- a shadow / a digger underground: nothing touches it
	entry.Humanoid:TakeDamage(amount)
""",
"""	if entry.Shaded or entry.Underground then return false, entry.Humanoid.Health end -- a shadow / a digger underground: nothing touches it
	--.. 2026-09-24 co-op nights: another player's blow lands only once their own wave is done (see the top)
	if typeof(attacker) == "Instance" and attacker:IsA("Player") and entry.Raid and entry.Raid.Player ~= attacker and not entry.Raid.Day then
		if not HelpAllowed(attacker) then
			HelpBlocked(attacker)
			return false, entry.Humanoid.Health
		end
		RegisterHelp(entry.Raid, attacker, amount)
	end
	entry.Humanoid:TakeDamage(amount)
"""),
        # won by killing every zombie
        (
"""		ReportResult(raid, "Survived") -- 2026-09-23 (Manage panel: days survived)
	end
end
""",
"""		ReportResult(raid, "Survived") -- 2026-09-23 (Manage panel: days survived)
		RewardHelpers(raid) -- 2026-09-24 co-op nights
	end
end
"""),
        # won at dawn with nothing stolen
        (
"""			ReportResult(raid, raid.Stolen == 0 and "Survived" or "Dawn") -- 2026-09-23 (Manage panel: days survived)
""",
"""			ReportResult(raid, raid.Stolen == 0 and "Survived" or "Dawn") -- 2026-09-23 (Manage panel: days survived)
			if raid.Stolen == 0 then RewardHelpers(raid) end -- 2026-09-24 co-op nights
"""),
        # Escape: tell the den (after ItemService recorded the loss)
        (
"""		if recordLoss then
			pcall(recordLoss.Invoke, recordLoss, raid.Player, {Name = name, Zone = stolen:GetAttribute("Zone"), Type = stolen:GetAttribute("TypeName"),
				Golden = stolen:GetAttribute("Golden") == true, Material = stolen:GetAttribute("Material"), Mutations = stolen:GetAttribute("Mutations"), SizeTier = stolen:GetAttribute("SizeTier")})
		end
""",
"""		if recordLoss then
			pcall(recordLoss.Invoke, recordLoss, raid.Player, {Name = name, Zone = stolen:GetAttribute("Zone"), Type = stolen:GetAttribute("TypeName"),
				Golden = stolen:GetAttribute("Golden") == true, Material = stolen:GetAttribute("Material"), Mutations = stolen:GetAttribute("Mutations"), SizeTier = stolen:GetAttribute("SizeTier")})
		end
		CucumberStolenEvent:Fire(raid.Player, {Name = name, Zone = stolen:GetAttribute("Zone"), Type = stolen:GetAttribute("TypeName")}) -- 2026-09-24 (Zombie Den: a deal for it)
"""),
    ]),
    "StarterPlayer.StarterPlayerScripts.ZombieRaidClient.client.lua": ("game.StarterPlayer.StarterPlayerScripts.ZombieRaidClient", [
        (
"""	  Hostile    {Kind = "Hostile"}: the raid has turned on you (you hit one of them) - a warning.
""",
"""	  Hostile    {Kind = "Hostile"}: the raid has turned on you (you hit one of them) - a warning.
	  Co-op      (2026-09-24) HelpBlocked (your own wave is not done) / HelperJoined {Name} / Helping {Name} /
	             Teamwork {With, Seconds} (the wave was won together: 2x cash + strength for Seconds) -> toasts.
"""),
        (
"""	Thief = function(p) Notify.Warn(("A %s is sneaking toward your base!"):format(p.Zombie or "thief"), 3) end,
""",
"""	--.. 2026-09-24 co-op nights
	HelpBlocked = function() Notify.Error("Finish your own wave before helping others!", 2.5) end,
	HelperJoined = function(p) Notify.Info(("%s is helping you fight!"):format(p.Name or "A player"), 2.5) end,
	Helping = function(p) Notify.Info(("You are helping %s! Win the wave together for a boost."):format(p.Name or "them"), 3) end,
	Teamwork = function(p)
		local minutes = math.max(1, math.floor((tonumber(p.Seconds) or 300) / 60 + 0.5))
		Notify.Success(("TEAMWORK with %s! 2x cash + 2x strength for %d min"):format(p.With or "your team", minutes), 4)
		SoundController.PlayFX("Victory Sting", {Volume = 0.9})
	end,
	Thief = function(p) Notify.Warn(("A %s is sneaking toward your base!"):format(p.Zombie or "thief"), 3) end,
"""),
    ]),
    "StarterGui.CucumberMenus.MenuController.lua": ("game.StarterGui.CucumberMenus.MenuController", [
        (
"""    local buyShopPanel = gui:FindFirstChild("BuyShopPanel")
    if buyShopPanel and buyShopPanel:FindFirstChild("Content") then panels.BuyShop = buyShopPanel.Content end
""",
"""    local buyShopPanel = gui:FindFirstChild("BuyShopPanel")
    if buyShopPanel and buyShopPanel:FindFirstChild("Content") then panels.BuyShop = buyShopPanel.Content end
    -- 2026-09-24: the ZOMBIE DEN panel (DenController opens it when the player walks up to the den and fills it);
    -- no HUD opener, so it is wired for close / dimmer / Escape / OpenRequest only like BuyShop
    local denPanel = gui:FindFirstChild("DenPanel")
    if denPanel and denPanel:FindFirstChild("Content") then panels.Den = denPanel.Content end
"""),
    ]),
    "StarterGui.CucumberMenus.MenuClient.client.lua": ("game.StarterGui.CucumberMenus.MenuClient", [
        (
"""if not okItemShop then warn("[MenuClient] Item shop unavailable: "..tostring(itemShop)) itemShop=nil end
script.Destroying:Connect(function() if itemShop then itemShop.Destroy() end;if manage then manage.Destroy() end;shop.Destroy();index.Destroy();menus.Destroy() end)""",
"""if not okItemShop then warn("[MenuClient] Item shop unavailable: "..tostring(itemShop)) itemShop=nil end
-- 2026-09-24: the ZOMBIE DEN panel (DenPanel, opened by walking up to the den), guarded the same way
local okDen,den=pcall(function() return require(script.Parent.DenController).Start(script.Parent,menus) end)
if not okDen then warn("[MenuClient] Zombie Den unavailable: "..tostring(den)) den=nil end
script.Destroying:Connect(function() if den then den.Destroy() end;if itemShop then itemShop.Destroy() end;if manage then manage.Destroy() end;shop.Destroy();index.Destroy();menus.Destroy() end)"""),
    ]),
}

SRC_FILES = [
    ("ReplicatedStorage.Modules.DenConfig.lua", "ReplicatedStorage.Modules.DenConfig", "ModuleScript"),
    ("ServerScriptService.ZombieDenService.server.lua", "ServerScriptService.ZombieDenService", "Script"),
    ("StarterGui.CucumberMenus.DenController.lua", "StarterGui.CucumberMenus.DenController", "ModuleScript"),
]


def main():
    if os.path.isdir(STAGE):  # OneDrive refuses rmdir on a synced folder: empty it instead
        for name in os.listdir(STAGE):
            full = os.path.join(STAGE, name)
            if os.path.isdir(full):
                shutil.rmtree(full)
            else:
                os.remove(full)
    else:
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
    shutil.copy(os.path.join(ROOT, "build_denpanel.lua"), STAGE)
    print("staged ->", STAGE)


if __name__ == "__main__":
    main()
