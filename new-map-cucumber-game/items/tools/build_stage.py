"""Builds items/stage/ for serve.ps1 (2026-09-23): patched/<file> = orig/<file> (live mirror) + the hunks below
(each old text exactly once, LF), stage/patches.json (pets-remake/apply_patches.lua), stage/_install.json + the
src/ files (pets-system/tools/install_new.lua), stage/_items.json + fbx/<Key>.parts.json + install_items.lua
(the item models).    py tools\\build_stage.py
"""
import json, os, shutil, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GAMES = os.path.dirname(os.path.dirname(ROOT))
ORIG, PATCHED, SRC, STAGE, FBX = [os.path.join(ROOT, d) for d in ("orig", "patched", "src", "stage", "fbx")]

PATCHES = {
    # -- saved inventory + the stolen-cucumber list
    "ServerStorage.DataService.lua": ("game.ServerStorage.DataService", [
        (
"""	Defense = {Survived = {}, LastSeen = 0, OfflineRate = 0, Level = 1}, -- zombie defence (ManageService, 2026-09-23): night raids survived per threat level (Survived["<level>"]), last-seen time + cucumber cash/s + threat level for offline earnings
}
""",
"""	Defense = {Survived = {}, LastSeen = 0, OfflineRate = 0, Level = 1}, -- zombie defence (ManageService, 2026-09-23): night raids survived per threat level (Survived["<level>"]), last-seen time + cucumber cash/s + threat level for offline earnings
	Items = {}, -- [ItemKey] = count: the drop items in the hotbar inventory (ItemService, 2026-09-23)
	LostCucumbers = {}, -- cucumbers the zombies stole, newest last (ZombieRaidService.Escape -> ItemAPI.RecordLoss; a Redemption Token brings the newest back)
}
"""),
    ]),
    # -- a killed zombie may drop an item; a stolen cucumber is remembered for the Redemption Token
    "ServerScriptService.ZombieRaidService.server.lua": ("game.ServerScriptService.ZombieRaidService", [
        (
"""	SoundController.PlayFXAt("Wet Crunch", entry.Root.Position, {Volume = 1, RollOff = 70})
	Poof(entry.Root.Position, entry.Variety.Glow, 16)
""",
"""	SoundController.PlayFXAt("Wet Crunch", entry.Root.Position, {Volume = 1, RollOff = 70})
	Poof(entry.Root.Position, entry.Variety.Glow, 16)
	--.. 2026-09-23 (items): a killed zombie may drop an item where it fell (ItemService rolls ItemsCatalog by the variety's level)
	do
		local itemApi = ServerStorage:FindFirstChild("ItemAPI")
		local drop = itemApi and itemApi:FindFirstChild("Drop")
		if drop then
			local okDrop, errDrop = pcall(drop.Invoke, drop, entry.Root.Position, entry.Variety.MinLevel or 1)
			if not okDrop then warn("[ZombieRaid] item drop failed: " .. tostring(errDrop)) end
		end
	end
"""),
        (
"""	local name = carry and carry.Name or "cucumber"
	if carry and carry.Model then carry.Model:Destroy() end
	if raid then
		raid.Stolen += 1
""",
"""	local name = carry and carry.Name or "cucumber"
	--.. 2026-09-23 (items): remember what was stolen so a Redemption Token can bring it back (ItemService.RecordLoss)
	if carry and carry.Model and raid and raid.Player then
		local stolen = carry.Model
		local itemApi = ServerStorage:FindFirstChild("ItemAPI")
		local recordLoss = itemApi and itemApi:FindFirstChild("RecordLoss")
		if recordLoss then
			pcall(recordLoss.Invoke, recordLoss, raid.Player, {Name = name, Zone = stolen:GetAttribute("Zone"), Type = stolen:GetAttribute("TypeName"),
				Golden = stolen:GetAttribute("Golden") == true, Material = stolen:GetAttribute("Material"), Mutations = stolen:GetAttribute("Mutations"), SizeTier = stolen:GetAttribute("SizeTier")})
		end
	end
	if carry and carry.Model then carry.Model:Destroy() end
	if raid then
		raid.Stolen += 1
"""),
    ]),
    # -- 2x strength per rep while the Strength Potion runs
    "ServerStorage.GymService.lua": ("game.ServerStorage.GymService", [
        (
"""	local gain = GymService.StrengthPerRep(data) * (multiplier or 1)
	DataService.Increment(player, "Strength", gain)
""",
"""	local gain = GymService.StrengthPerRep(data) * (multiplier or 1)
	--.. 2026-09-23 (items): a Strength Potion doubles every rep while StrengthBoostUntil (server time) is ahead
	local boostUntil = tonumber(player:GetAttribute("StrengthBoostUntil"))
	if boostUntil and boostUntil > workspace:GetServerTimeNow() then gain *= 2 end
	DataService.Increment(player, "Strength", gain)
"""),
    ]),
    # -- 2x cash on every payout while the Cash Potion runs
    "ServerStorage.IncomeService.lua": ("game.ServerStorage.IncomeService", [
        (
"""	local function Credit(player, amount)
		local ok, result = pcall(DataService.Increment, player, CASH_KEY, amount, true)
""",
"""	local function Credit(player, amount)
		--.. 2026-09-23 (items): a Cash Potion doubles every payout while CashBoostUntil (server time) is ahead
		if typeof(player) == "Instance" then
			local boostUntil = tonumber(player:GetAttribute("CashBoostUntil"))
			if boostUntil and boostUntil > workspace:GetServerTimeNow() then amount *= 2 end
		end
		local ok, result = pcall(DataService.Increment, player, CASH_KEY, amount, true)
"""),
    ]),
    # -- the hotbar: item stacks picture their parts, show a count and an item tooltip
    "StarterPlayer.StarterPlayerScripts.HotbarClient.client.lua": ("game.StarterPlayer.StarterPlayerScripts.HotbarClient", [
        (
"""local okPets, PetsCatalog = pcall(function() return require(Modules:WaitForChild("PetsCatalog", 10)) end)
if not okPets then PetsCatalog = nil end
""",
"""local okPets, PetsCatalog = pcall(function() return require(Modules:WaitForChild("PetsCatalog", 10)) end)
if not okPets then PetsCatalog = nil end
--.. 2026-09-23: drop items (ItemService) sit in the hotbar as stacks: their own parts as the picture, "xN", an item tooltip
local okItems, ItemsCatalog = pcall(function() return require(Modules:WaitForChild("ItemsCatalog", 10)) end)
if not okItems then ItemsCatalog = nil end
"""),
        (
"""local function IsPet(tool) -- 2026-09-23
	return tool:GetAttribute("PetTool") == true
end
""",
"""local function IsPet(tool) -- 2026-09-23
	return tool:GetAttribute("PetTool") == true
end

local function IsItem(tool) -- 2026-09-23: a drop item stack (ItemService)
	return tool:GetAttribute("ItemTool") == true
end
"""),
        (
"""	if egg then return egg:Clone() end
""",
"""	if egg then return egg:Clone() end
	if IsItem(tool) then -- 2026-09-23: the item's own parts (welded to its invisible Handle)
		local model = Instance.new("Model")
		for _, d in ipairs(tool:GetChildren()) do
			if d:IsA("BasePart") and d.Name ~= "Handle" then
				local c = d:Clone()
				for _, e in ipairs(c:GetChildren()) do
					if e:IsA("Constraint") or e:IsA("WeldConstraint") or e:IsA("JointInstance") then e:Destroy() end
				end
				c.Anchored = true
				c.Parent = model
			end
		end
		if #model:GetChildren() == 0 then model:Destroy() return nil end
		return model
	end
"""),
        (
"""	local slot = {Tool = tool, Frame = frame, Number = number, Stroke = stroke, Conns = {}}
	if not ((IsEgg(tool) or IsPet(tool)) and BuildPicture(slot, tool)) then BuildText(slot, tool) end
""",
"""	--.. 2026-09-23: item stacks show their count bottom-right ("x3")
	local count = Instance.new("TextLabel")
	count.Name = "Count"
	count.AnchorPoint = Vector2.new(1, 1)
	count.Position = UDim2.new(1, -5, 1, -3)
	count.Size = UDim2.fromOffset(30, 14)
	count.BackgroundTransparency = 1
	count.Font = Enum.Font.GothamBold
	count.TextSize = 13
	count.TextColor3 = TEXT_COLOR
	count.TextXAlignment = Enum.TextXAlignment.Right
	count.Text = ""
	count.ZIndex = 4
	count.Parent = frame
	local countStroke = Instance.new("UIStroke")
	countStroke.Color = Color3.fromRGB(12, 12, 12)
	countStroke.Thickness = 1.2
	countStroke.Parent = count
	local slot = {Tool = tool, Frame = frame, Number = number, Stroke = stroke, Count = count, Conns = {}}
	if IsItem(tool) then
		local function refreshCount()
			local n = tonumber(tool:GetAttribute("Count")) or 0
			count.Text = n > 1 and ("x" .. n) or ""
		end
		refreshCount()
		table.insert(slot.Conns, tool:GetAttributeChangedSignal("Count"):Connect(refreshCount))
	end
	if not ((IsEgg(tool) or IsPet(tool) or IsItem(tool)) and BuildPicture(slot, tool)) then BuildText(slot, tool) end
"""),
        (
"""	elseif IsPet(tool) then -- 2026-09-23: a reserve pet
""",
"""	elseif IsItem(tool) then -- 2026-09-23: a drop item stack
		local rarity = tostring(tool:GetAttribute("Rarity") or "Common")
		local color = ItemsCatalog and ItemsCatalog.RarityColor(rarity) or Color3.new(1, 1, 1)
		local display = tostring(tool:GetAttribute("DisplayName") or tool.Name)
		tipName.Text = CucumberMutations.Font(display, color, true)
		local n = tonumber(tool:GetAttribute("Count")) or 1
		tipWeight.Text = ("%s  -  x%d"):format(CucumberMutations.Font(rarity, color, true), n)
		tipWeight.Visible = true
		tipMutations.Text = tostring(tool:GetAttribute("Description") or "")
		tipMutations.Visible = tipMutations.Text ~= ""
		local kind = tool:GetAttribute("Kind")
		tipMaterial.Text = kind == "Throw" and "Take it in hand, then click where to throw" or (kind == "Drink" and "Take it in hand, then click to drink" or "Take it in hand, then click to use")
		tipMaterial.Visible = true
	elseif IsPet(tool) then -- 2026-09-23: a reserve pet
"""),
    ]),
    # -- the seed items need a random type name of a zone
    "ServerScriptService.CucumberSpawner.server.lua": ("game.ServerScriptService.CucumberSpawner", [
        (
"""bindable("Zones", function() return table.clone(ZONES) end)
""",
"""bindable("Zones", function() return table.clone(ZONES) end)
--.. 2026-09-23 (items): a random non-sliced type name of the zone (the Golden / Void Seed items plant one)
bindable("PickTypeName", function(zone)
	if not table.find(ZONES, zone) then return nil end
	local t = PickType(zone)
	return t and t.Name or nil
end)
"""),
    ]),
    # -- the boost pad must not cut a running Speed Potion short, nor end it with the character
    "ServerScriptService.BoostPadService.server.lua": ("game.ServerScriptService.BoostPadService", [
        (
"""		player:SetAttribute(ATTR, workspace:GetServerTimeNow() + BOOST_SECONDS)
""",
"""		--.. 2026-09-23 (items): never cut a running Speed Potion short - the longer of the two timers stays
		player:SetAttribute(ATTR, math.max(tonumber(player:GetAttribute(ATTR)) or 0, workspace:GetServerTimeNow() + BOOST_SECONDS))
"""),
        (
"""	player.CharacterRemoving:Connect(function() player:SetAttribute(ATTR, nil) end)
""",
"""	player.CharacterRemoving:Connect(function()
		--.. 2026-09-23 (items): only a pad boost ends with the character; a Speed Potion's longer timer survives a respawn
		local untilTime = tonumber(player:GetAttribute(ATTR))
		if not untilTime or untilTime - workspace:GetServerTimeNow() <= BOOST_SECONDS then player:SetAttribute(ATTR, nil) end
	end)
"""),
    ]),
}

# ROUND 1 (PATCHES above) went live on 2026-09-23 and several of its hunks are additive (their old text survives
# inside the new text), so they must NEVER ride again. Later rounds are checked against orig + round 1 = the live
# text and are the only edits staged.
ROUND2 = {
    # -- an item's part may be named "Egg" (the Zombie Egg): only a MODEL called Egg on a non-item tool is an egg picture
    "StarterPlayer.StarterPlayerScripts.HotbarClient.client.lua": ("game.StarterPlayer.StarterPlayerScripts.HotbarClient", [
        (
"""	local egg = tool:FindFirstChild("Egg")
	if egg then return egg:Clone() end
""",
"""	local egg = tool:FindFirstChild("Egg")
	if egg and egg:IsA("Model") and not IsItem(tool) then return egg:Clone() end -- 2026-09-23: an item's part may be named Egg too
"""),
    ]),
}
ROUND3 = {
    # -- a Tool replicates before its children: wait for the item's parts (PartCount, stamped by ItemService) before
    #    drawing the picture, else a rejoin shows text slots
    "StarterPlayer.StarterPlayerScripts.HotbarClient.client.lua": ("game.StarterPlayer.StarterPlayerScripts.HotbarClient", [
        (
"""	if IsItem(tool) then -- 2026-09-23: the item's own parts (welded to its invisible Handle)
		local model = Instance.new("Model")
""",
"""	if IsItem(tool) then -- 2026-09-23: the item's own parts (welded to its invisible Handle)
		--.. a Tool replicates before its children: wait (briefly) until the parts the server counted are here
		local wanted = math.max(1, tonumber(tool:GetAttribute("PartCount")) or 1)
		local deadline = os.clock() + 3
		local function partsHere()
			local n = 0
			for _, d in ipairs(tool:GetChildren()) do if d:IsA("BasePart") then n += 1 end end
			return n
		end
		while partsHere() < wanted and os.clock() < deadline and tool.Parent do task.wait(0.1) end
		local model = Instance.new("Model")
"""),
    ]),
}
ROUND4 = {
    # -- a respawn destroys the old Backpack / character WITH their tools (no ChildRemoved fires for those), so their
    #    slots stayed forever (pre-existing "stale slot on every respawn"); with ItemService rebuilding the item tools
    #    after each respawn that showed a stale text slot beside every live picture slot
    "StarterPlayer.StarterPlayerScripts.HotbarClient.client.lua": ("game.StarterPlayer.StarterPlayerScripts.HotbarClient", [
        (
"""local function BindCharacter(newCharacter)
	character = newCharacter
""",
"""--.. 2026-09-23: tools whose Backpack / character was destroyed never fire ChildRemoved - drop their slots
local function SweepDeadTools()
	for tool in pairs(slots) do
		if not tool:IsDescendantOf(game) then Untrack(tool) end
	end
end

local function BindCharacter(newCharacter)
	character = newCharacter
	SweepDeadTools()
"""),
        (
"""	if child.Name == "Backpack" and child ~= backpack then
		backpack = child
		Watch(child)
""",
"""	if child.Name == "Backpack" and child ~= backpack then
		backpack = child
		SweepDeadTools() -- 2026-09-23
		Watch(child)
"""),
    ]),
}
ROUND5 = {
    # -- MakeSlot can now yield (the item parts wait): a tool destroyed meanwhile (the join-time Backpack being
    #    replaced) must not end up as a slot nobody can untrack
    "StarterPlayer.StarterPlayerScripts.HotbarClient.client.lua": ("game.StarterPlayer.StarterPlayerScripts.HotbarClient", [
        (
"""local function Track(tool)
	if not tool:IsA("Tool") or slots[tool] then return end
	table.insert(order, tool)
	slots[tool] = MakeSlot(tool)
	Layout()
end
""",
"""local function Track(tool)
	if not tool:IsA("Tool") or slots[tool] then return end
	table.insert(order, tool)
	local slot = MakeSlot(tool) -- may yield for an item's parts (2026-09-23)
	if slots[tool] or not tool:IsDescendantOf(game) then
		--.. the tool died (or was tracked again) while its slot was being built: throw the slot away
		for _, c in ipairs(slot.Conns) do c:Disconnect() end
		slot.Frame:Destroy()
		local index = table.find(order, tool) -- this call's own order entry (one of two when tracked twice)
		if index then table.remove(order, index) end
		return
	end
	slots[tool] = slot
	Layout()
end
"""),
    ]),
}
ROUND6 = {
    # -- user (2026-09-23): "make the bat tool have an icon in hotbar" + "remove the final instruction line" from the
    #    hover cards ("Take it in hand, then click ..." on items, "Click to let it out in your base" on pets)
    "StarterPlayer.StarterPlayerScripts.HotbarClient.client.lua": ("game.StarterPlayer.StarterPlayerScripts.HotbarClient", [
        (
"""			return model
		end
	end
	return nil
end

--.. EggShop's FormatKg
""",
"""			return model
		end
	end
	--.. 2026-09-23 (user: "make the bat tool have an icon in hotbar"): any other tool with visible parts (the Bat)
	--.. pictures them, stood up on its longest axis and tilted a little. RequiresHandle tools replicate their Handle
	--.. with the rest of the parts, so a short wait for it covers the "Tool arrives before its children" case.
	if tool:IsA("Tool") then
		if not tool:FindFirstChildWhichIsA("BasePart") then
			tool:WaitForChild("Handle", 1.5)
			task.wait(0.15)
		end
		local model = Instance.new("Model")
		for _, d in ipairs(tool:GetChildren()) do
			if d:IsA("BasePart") and d.Transparency < 1 then
				local c = d:Clone()
				for _, e in ipairs(c:GetChildren()) do
					if e:IsA("Constraint") or e:IsA("WeldConstraint") or e:IsA("JointInstance") or e:IsA("LuaSourceContainer") then e:Destroy() end
				end
				c.Anchored = true
				c.Parent = model
			end
		end
		if #model:GetChildren() == 0 then model:Destroy() return nil end
		local cf, size = model:GetBoundingBox()
		model.WorldPivot = cf
		if size.X >= size.Y and size.X >= size.Z then
			model:PivotTo(cf * CFrame.Angles(0, 0, math.rad(90))) -- longest axis X -> up
		elseif size.Z >= size.Y then
			model:PivotTo(cf * CFrame.Angles(math.rad(90), 0, 0)) -- longest axis Z -> up
		end
		model:PivotTo(model:GetPivot() * CFrame.Angles(0, 0, math.rad(-25)))
		model.WorldPivot = CFrame.new(model:GetPivot().Position) -- identity rotation: BuildPicture's recentring keeps the tilt
		return model
	end
	return nil
end

--.. EggShop's FormatKg
"""),
        (
"""		local kind = tool:GetAttribute("Kind")
		tipMaterial.Text = kind == "Throw" and "Take it in hand, then click where to throw" or (kind == "Drink" and "Take it in hand, then click to drink" or "Take it in hand, then click to use")
		tipMaterial.Visible = true
""",
"""		tipMaterial.Visible = false -- 2026-09-23 (user): no "take it in hand ..." instruction line
"""),
        (
"""		tipMaterial.Text = "Click to let it out in your base"
		tipMaterial.Visible = true
""",
"""		tipMaterial.Visible = false -- 2026-09-23 (user): no "click to ..." instruction line
"""),
        (
"""	if not ((IsEgg(tool) or IsPet(tool) or IsItem(tool)) and BuildPicture(slot, tool)) then BuildText(slot, tool) end
""",
"""	--.. 2026-09-23: every tool without a TextureId gets a picture try (the Bat pictures its own parts)
	if not ((tool.TextureId == "" or IsEgg(tool) or IsPet(tool) or IsItem(tool)) and BuildPicture(slot, tool)) then BuildText(slot, tool) end
"""),
    ]),
}
ROUND7 = {
    # -- user (2026-09-23): "for pets if theres no mutation then dont say 'No traits' just leave it blank"
    "StarterPlayer.StarterPlayerScripts.HotbarClient.client.lua": ("game.StarterPlayer.StarterPlayerScripts.HotbarClient", [
        (
"""		tipMutations.Text = #words > 0 and ("Traits: " .. table.concat(words, ", ")) or "No traits"
		tipMutations.Visible = true
""",
"""		tipMutations.Text = #words > 0 and ("Traits: " .. table.concat(words, ", ")) or ""
		tipMutations.Visible = #words > 0 -- 2026-09-23 (user): blank when a pet has no traits
"""),
    ]),
    "StarterPlayer.StarterPlayerScripts.PetInfoClient.client.lua": ("game.StarterPlayer.StarterPlayerScripts.PetInfoClient", [
        (
"""	if #words == 0 then return string.format('<font color="%s">No traits</font>', Hex(C(255, 226, 232))) end
""",
"""	if #words == 0 then return "" end -- 2026-09-23 (user): blank when a pet has no traits
"""),
    ]),
}
LIVE_ROUNDS = [ROUND2, ROUND3, ROUND4, ROUND5, ROUND6, ROUND7]  # live already (2026-09-23); applied only to reproduce the live text
ACTIVE_ROUNDS = []  # round 8 (warp bounds) changed only the src/ scripts

SRC_FILES = [
    ("ReplicatedStorage.Modules.ItemsCatalog.lua", "ReplicatedStorage.Modules.ItemsCatalog", "ModuleScript"),
    ("ServerScriptService.ItemService.server.lua", "ServerScriptService.ItemService", "Script"),
    ("StarterPlayer.StarterPlayerScripts.ItemClient.client.lua", "StarterPlayer.StarterPlayerScripts.ItemClient", "LocalScript"),
]

ITEM_KEYS = ["SpeedPotion", "StrengthPotion", "CashPotion", "WarpPearl", "HolyWater", "GoldenSeed", "VoidSeed", "ZombieEgg", "RedemptionToken"]


def main():
    os.makedirs(STAGE, exist_ok=True)
    for name in os.listdir(STAGE):
        try:
            os.remove(os.path.join(STAGE, name))
        except OSError:
            pass
    os.makedirs(PATCHED, exist_ok=True)
    entries = []
    files = list(PATCHES.keys())
    for rnd in ACTIVE_ROUNDS:
        for fname in rnd:
            if fname not in files:
                files.append(fname)
    for fname in files:
        text = open(os.path.join(ORIG, fname), encoding="utf-8").read().replace("\r\n", "\n")
        live_edits, path = 0, None
        if fname in PATCHES:
            path, hunks = PATCHES[fname]
            for old, new in hunks:  # round 1: live already; applied here only to reproduce the live text
                n = text.count(old)
                if n != 1:
                    sys.exit("%s: round-1 hunk occurs %d times:\n%s" % (fname, n, old[:300]))
                text = text.replace(old, new)
                live_edits += 1
        for rnd in LIVE_ROUNDS:
            if fname in rnd:
                path, hunks = rnd[fname]
                for old, new in hunks:
                    n = text.count(old)
                    if n != 1:
                        sys.exit("%s: live-round hunk occurs %d times:\n%s" % (fname, n, old[:300]))
                    text = text.replace(old, new)
                    live_edits += 1
        edits = []
        for rnd in ACTIVE_ROUNDS:
            if fname not in rnd:
                continue
            path, hunks = rnd[fname]
            for old, new in hunks:
                n = text.count(old)
                if n != 1:
                    sys.exit("%s: staged hunk occurs %d times in the live text:\n%s" % (fname, n, old[:300]))
                text = text.replace(old, new)
                edits.append({"old": old, "new": new})
        with open(os.path.join(PATCHED, fname), "w", encoding="utf-8", newline="\n") as f:
            f.write(text)
        if edits:
            entries.append({"path": path, "file": fname, "edits": edits})
        print(fname, live_edits, "live edits +", len(edits), "staged ->", len(text), "chars")
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
    for key in ITEM_KEYS:
        shutil.copy(os.path.join(FBX, key + ".parts.json"), STAGE)
    with open(os.path.join(STAGE, "_items.json"), "w", encoding="utf-8") as f:
        json.dump(ITEM_KEYS, f)
    shutil.copy(os.path.join(ROOT, "install_items.lua"), STAGE)
    shutil.copy(os.path.join(GAMES, "pets-remake", "apply_patches.lua"), STAGE)
    shutil.copy(os.path.join(GAMES, "new-map-cucumber-game", "pets-system", "tools", "install_new.lua"), STAGE)
    print("staged ->", STAGE)


if __name__ == "__main__":
    main()
