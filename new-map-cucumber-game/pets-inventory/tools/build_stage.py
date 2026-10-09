"""Builds pets-inventory/stage/ for serve.ps1 (2026-09-23): patched/<file> = orig/<file> (live mirror) + the
hunks below (each old text exactly once, LF), stage/patches.json (apply_patches.lua), stage/_install.json +
the src/ files (install_new.lua).    py build_stage.py
"""
import json, os, shutil, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GAMES = os.path.dirname(os.path.dirname(ROOT))
ORIG, PATCHED, SRC, STAGE = [os.path.join(ROOT, d) for d in ("orig", "patched", "src", "stage")]

PATCHES = {
    # -- overhead card: name white on row 1, the rarity word in its colour on its own row under it
    "StarterPlayer.StarterPlayerScripts.PetCardClient.client.lua": ("game.StarterPlayer.StarterPlayerScripts.PetCardClient", [
        (
"""	  1. the pet's display name in its rarity gradient (PetsCatalog.RARITY_GRADIENTS), followed by
	     the rarity word at RARITY_SIZE of the name's height in the same gradient ("Cosmo Cat
	     · Mythical"), so rarity never reads by colour alone. The two widths come from the character
	     counts and shrink together when a long name would not fit, so the row always stays inside
	     the card (TextScaled then fits each text to its box).
""",
"""	  1. the pet's display name in plain WHITE, and under it (2026-09-23, user: "put their rarity
	     under their name instead of beside it, name white but rarity color coded") the rarity word
	     on a row of its own, RARITY_H studs tall, in its rarity gradient (PetsCatalog.RARITY_GRADIENTS).
	     Each width comes from the character count and shrinks when a long word would not fit, so
	     the row always stays inside the card (TextScaled then fits the text to its box).
"""),
        (
"""local RARITY_SIZE = 0.7 -- the rarity word's height relative to the name's
""",
"""local RARITY_SIZE = 0.7 -- the rarity word's height relative to the name's (kept for NameRowWidths)
local RARITY_H = 0.62 -- studs: the rarity row under the name (2026-09-23)
"""),
        (
"""--.. the card's height (studs) and its row heights as fractions of it: the tag row adds TAG_H
--.. studs and the name / cash rows keep their stud heights (NAME_FRAC / RATE_FRAC of CARD_H)
function Core.CardRows(hasTag)
	local total = hasTag and CARD_H + TAG_H or CARD_H
	local s = CARD_H / total
	return total, NAME_FRAC * s, RATE_FRAC * s, hasTag and TAG_H / total or 0
end
""",
"""--.. the card's height (studs) and its row heights as fractions of it: the rarity row adds RARITY_H
--.. studs (2026-09-23), the tag row TAG_H, and the name / cash rows keep their stud heights
--.. (NAME_FRAC / RATE_FRAC of CARD_H). Returns total, nameFrac, rateFrac, tagFrac, rarityFrac.
function Core.CardRows(hasTag)
	local total = CARD_H + RARITY_H + (hasTag and TAG_H or 0)
	local s = CARD_H / total
	return total, NAME_FRAC * s, RATE_FRAC * s, hasTag and TAG_H / total or 0, RARITY_H / total
end
"""),
        (
"""	local row = Row("AbilityTag", parent, frac, 3)
""",
"""	local row = Row("AbilityTag", parent, frac, 4) -- 2026-09-23: after name / rarity / cash
"""),
        (
"""		local cardH, nameFrac, rateFrac, tagFrac = Core.CardRows(glyph ~= nil)
""",
"""		local cardH, nameFrac, rateFrac, tagFrac, rarityFrac = Core.CardRows(glyph ~= nil)
"""),
        (
"""		--.. row 1: "Cosmo Cat · Mythical", both in the rarity gradient, bottom-aligned on one baseline
		local rarity = model:GetAttribute("Rarity")
		rarity = type(rarity) == "string" and rarity ~= "" and rarity or "Common"
		local name = model:GetAttribute("DisplayName")
		name = type(name) == "string" and name ~= "" and name or model.Name
		local rarityText = SEPARATOR .. rarity
		local nameRow = Row("NameRow", gui, nameFrac, 1, Enum.VerticalAlignment.Bottom)
		local nameW, rarityW = Core.NameRowWidths(utf8.len(name) or #name, utf8.len(rarityText) or #rarityText, CARD_W / (CARD_H * NAME_FRAC))
		local nameLabel = Label("PetName", nameRow, name, WHITE, DARK_STROKE, 1)
		nameLabel.Size = UDim2.fromScale(nameW, 1)
		nameLabel.TextYAlignment = Enum.TextYAlignment.Bottom
		Gradient(nameLabel, rarity)
		local rarityLabel = Label("RarityWord", nameRow, rarityText, WHITE, DARK_STROKE, 2)
		rarityLabel.Size = UDim2.fromScale(rarityW, RARITY_SIZE)
		rarityLabel.TextYAlignment = Enum.TextYAlignment.Bottom
		Gradient(rarityLabel, rarity)
		--.. row 2: the green "$X/s"
		local cashRow = Row("CashLine", gui, rateFrac, 2)
""",
"""		--.. row 1: "Cosmo Cat" in plain white (2026-09-23: the rarity moved to its own row under the name)
		local rarity = model:GetAttribute("Rarity")
		rarity = type(rarity) == "string" and rarity ~= "" and rarity or "Common"
		local name = model:GetAttribute("DisplayName")
		name = type(name) == "string" and name ~= "" and name or model.Name
		local nameRow = Row("NameRow", gui, nameFrac, 1, Enum.VerticalAlignment.Bottom)
		local nameW = Core.NameRowWidths(utf8.len(name) or #name, 0, CARD_W / (CARD_H * NAME_FRAC))
		local nameLabel = Label("PetName", nameRow, name, WHITE, DARK_STROKE, 1)
		nameLabel.Size = UDim2.fromScale(nameW, 1)
		nameLabel.TextYAlignment = Enum.TextYAlignment.Bottom
		--.. row 2: the rarity word, colour-coded by its rarity gradient
		local rarityRow = Row("RarityRow", gui, rarityFrac, 2)
		local rarityW = Core.NameRowWidths(utf8.len(rarity) or #rarity, 0, CARD_W / RARITY_H)
		local rarityLabel = Label("RarityWord", rarityRow, rarity, WHITE, DARK_STROKE, 1)
		rarityLabel.Size = UDim2.fromScale(rarityW, 1)
		Gradient(rarityLabel, rarity)
		--.. row 3: the green "$X/s"
		local cashRow = Row("CashLine", gui, rateFrac, 3)
"""),
    ]),
    # -- hotbar: reserve pets (PetInventoryService tools) get a live picture + a pet tooltip
    "StarterPlayer.StarterPlayerScripts.HotbarClient.client.lua": ("game.StarterPlayer.StarterPlayerScripts.HotbarClient", [
        (
"""local CucumberMutations = require(Modules:WaitForChild("CucumberMutations"))
""",
"""local CucumberMutations = require(Modules:WaitForChild("CucumberMutations"))
--.. 2026-09-23: reserve pets sit in the hotbar as tools (PetInventoryService, attribute PetTool); they show
--.. their pet model (PetsCatalog.ModelOf) the way eggs show their egg, and a pet tooltip
local okPets, PetsCatalog = pcall(function() return require(Modules:WaitForChild("PetsCatalog", 10)) end)
if not okPets then PetsCatalog = nil end
"""),
        (
"""local function IsEgg(tool)
	return CollectionService:HasTag(tool, "EggTool") or tool:GetAttribute("EggName") ~= nil
end
""",
"""local function IsEgg(tool)
	return CollectionService:HasTag(tool, "EggTool") or tool:GetAttribute("EggName") ~= nil
end

local function IsPet(tool) -- 2026-09-23
	return tool:GetAttribute("PetTool") == true
end

--.. the model a slot pictures: the egg tool's Egg, or the reserve pet's catalog model with its traits applied
local function SourceModel(tool)
	local egg = tool:FindFirstChild("Egg")
	if egg then return egg:Clone() end
	if IsPet(tool) and PetsCatalog then
		local ok, source = pcall(PetsCatalog.ModelOf, tool:GetAttribute("Pet"))
		if ok and source and source:IsA("Model") then
			local model = source:Clone()
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("LuaSourceContainer") or d:IsA("Sound") then d:Destroy() end
			end
			model:SetAttribute("PrismaticLoop", true) -- ApplyLook must not start its colour loop on a picture
			local material, mutations = tool:GetAttribute("Material"), tool:GetAttribute("Mutations")
			if (type(material) == "string" and material ~= "") or (type(mutations) == "string" and mutations ~= "") then
				pcall(CucumberMutations.ApplyLook, model, (type(material) == "string" and material ~= "") and material or nil, mutations)
			end
			return model
		end
	end
	return nil
end
"""),
        (
"""	local egg = tool:FindFirstChild("Egg")
	if not egg then return false end
	local viewport = Instance.new("ViewportFrame")
""",
"""	local model = SourceModel(tool) -- 2026-09-23: eggs or reserve pets
	if not model then return false end
	local viewport = Instance.new("ViewportFrame")
"""),
        (
"""	viewport.Parent = slot.Frame
	local model = egg:Clone()
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("WeldConstraint") or d:IsA("Weld") or d:IsA("ParticleEmitter") or d:IsA("Light") then d:Destroy() end
	end
""",
"""	viewport.Parent = slot.Frame
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("WeldConstraint") or d:IsA("Weld") or d:IsA("ParticleEmitter") or d:IsA("Light") or d:IsA("Trail") or d:IsA("Beam") then d:Destroy() end
	end
"""),
        (
"""	if not (IsEgg(tool) and BuildPicture(slot, tool)) then BuildText(slot, tool) end
""",
"""	if not ((IsEgg(tool) or IsPet(tool)) and BuildPicture(slot, tool)) then BuildText(slot, tool) end
"""),
        (
"""	else
		tipName.Text = tool.Name
		local tip = tool.ToolTip
""",
"""	elseif IsPet(tool) then -- 2026-09-23: a reserve pet
		local rarity = tostring(tool:GetAttribute("Rarity") or "Common")
		local glow = PetsCatalog and type(PetsCatalog.RARITY_GLOW) == "table" and PetsCatalog.RARITY_GLOW[rarity] or nil
		local display = tool:GetAttribute("DisplayName") or tool.Name
		tipName.Text = glow and CucumberMutations.Font(display, glow, true) or display
		local income = tonumber(tool:GetAttribute("Income")) or 0
		tipWeight.Text = ("%s  -  $%s/s in your base"):format(glow and CucumberMutations.Font(rarity, glow, true) or rarity, ("%.2f"):format(income):gsub("%.?0+$", ""))
		tipWeight.Visible = true
		local words = {}
		local material = tool:GetAttribute("Material")
		if type(material) == "string" and material ~= "" then words[#words + 1] = Colored(material) end
		for _, m in ipairs(CucumberMutations.Parse(tool:GetAttribute("Mutations"))) do words[#words + 1] = Colored(m) end
		tipMutations.Text = #words > 0 and ("Traits: " .. table.concat(words, ", ")) or "No traits"
		tipMutations.Visible = true
		tipMaterial.Text = "Click to let it out in your base"
		tipMaterial.Visible = true
	else
		tipName.Text = tool.Name
		local tip = tool.ToolTip
"""),
    ]),
    # -- the Pets menu is gone: MenuController / MenuClient / BaseHUDController forget it
    "StarterGui.CucumberMenus.MenuController.lua": ("game.StarterGui.CucumberMenus.MenuController", [
        (
"""local OPENERS = {Shop = {"LeftMenu", "Shop", "OpenShop"}, Index = {"LeftMenu", "Index", "OpenIndex"}, Pets = {"LeftMenu", "Pets", "OpenPets"}, Manage = {"LeftMenu", "Manage", "ManageButton"}}
local OPTIONAL = {Pets = true, Manage = true}
""",
"""-- 2026-09-23: the Pets menu / paw were removed (backup backups/NewMap_PetsMenu_before-removal_2026-09-23.rbxm);
-- reserve pets live in the hotbar (PetInventoryService) and a click on a pet opens PetInfoClient's frame
local OPENERS = {Shop = {"LeftMenu", "Shop", "OpenShop"}, Index = {"LeftMenu", "Index", "OpenIndex"}, Manage = {"LeftMenu", "Manage", "ManageButton"}}
local OPTIONAL = {Manage = true}
"""),
        (
"""    -- 2026-09-22: the Pets panel registers only once the pets builder has made it
    local petsPanel = gui:FindFirstChild("PetsPanel")
    if petsPanel and petsPanel:FindFirstChild("Content") then panels.Pets = petsPanel.Content end
""",
"""    -- 2026-09-23: no Pets panel any more (see OPENERS)
"""),
    ]),
    "StarterGui.CucumberMenus.MenuClient.client.lua": ("game.StarterGui.CucumberMenus.MenuClient", [
        (
"""-- 2026-09-22: the Pets menu starts last and guarded (require errors included), so it can never break Shop / Index
local okPets,pets=pcall(function() return require(script.Parent.PetController).Start(script.Parent,menus) end)
if not okPets then warn("[MenuClient] Pets menu unavailable: "..tostring(pets)) pets=nil end
-- 2026-09-23: the Manage panel, guarded the same way
""",
"""-- 2026-09-23: the Pets menu is gone (reserve pets live in the hotbar); the Manage panel starts guarded
"""),
        (
"""script.Destroying:Connect(function() if manage then manage.Destroy() end;if pets then pets.Destroy() end;shop.Destroy();index.Destroy();menus.Destroy() end)""",
"""script.Destroying:Connect(function() if manage then manage.Destroy() end;shop.Destroy();index.Destroy();menus.Destroy() end)"""),
    ]),
    "StarterGui.CucumberHUDDesign.BaseHUDController.lua": ("game.StarterGui.CucumberHUDDesign.BaseHUDController", [
        (
"""local SLOTS = {Shop = 1, Build = 1, Index = 2, Manage = 2, BenchStrength = 2, Pets = 3} -- 2026-09-22: Pets has its own slot
local OPTIONAL_SLOTS = {Pets = true} -- 2026-09-22: skipped when the pets builder has not run
""",
"""local SLOTS = {Shop = 1, Build = 1, Index = 2, Manage = 2, BenchStrength = 2} -- 2026-09-23: the Pets paw is gone (reserve pets live in the hotbar)
local OPTIONAL_SLOTS = {} -- 2026-09-23: none left (was Pets)
"""),
        (
"""            BenchStrength = onBench and not building,
            Pets = not building and not onBench, -- 2026-09-22: the paw stays in and out of the base
        }
""",
"""            BenchStrength = onBench and not building,
        }
"""),
    ]),
    # -- PetService.Equip takes the placement spot (2026-09-23 round 2)
    "ServerStorage.PetService.lua": ("game.ServerStorage.PetService", [
        (
"""function PetService.Equip(player, petId)
""",
"""--.. spot (2026-09-23, inventory placement): a world point on the plot top the pet spawns at (PetInventoryService
--.. validated it); nil = the saved / a free spot as before
function PetService.Equip(player, petId, spot)
"""),
        (
"""	if not rp.PresentationPending and not rp.Model then SpawnPet(player, rt, rp, nil) end
	RefreshStatus(player, rt, rp, true, false)
	ActiveDirty = true
	QueueDelta(player, petId, true)
""",
"""	if not rp.PresentationPending and not rp.Model then SpawnPet(player, rt, rp, typeof(spot) == "Vector3" and spot or nil) end
	RefreshStatus(player, rt, rp, true, false)
	ActiveDirty = true
	QueueDelta(player, petId, true)
"""),
    ]),
    # -- the egg reveal shows only the pet, its name, rarity and chance (2026-09-23 round 2)
    "StarterPlayer.StarterPlayerScripts.EggHatchClient.client.lua": ("game.StarterPlayer.StarterPlayerScripts.EggHatchClient", [
        (
"""	--.. 2026-09-22: cash/sec + ability and the inherited traits (labels authored by the pets-panel
	--.. builder; hidden when the template or the payload lacks them)
	for name, fill in pairs({PetStats = function() return StatsText(info.Stats) end, PetTraits = function() return TraitsText(info.Material, info.Mutations) end}) do
		local label = card:FindFirstChild(name)
		if label and label:IsA("TextLabel") then
			local ok, text = pcall(fill)
			local show = ok and type(text) == "string" and text ~= ""
			label.RichText = true
			label.Text = show and text or ""
			label.Visible = show
		end
	end
""",
"""	--.. 2026-09-23 (user: "just show pet - pet name/rarity and chance of getting pet, dont show all that other
	--.. info"): the cash/sec + ability and traits lines of 2026-09-22 stay hidden (StatsText / TraitsText kept
	--.. for the info frame's sake)
	for _, name in ipairs({"PetStats", "PetTraits"}) do
		local label = card:FindFirstChild(name)
		if label and label:IsA("TextLabel") then
			label.Text = ""
			label.Visible = false
		end
	end
"""),
    ]),
    "ReplicatedStorage.Modules.PetBalance.lua": ("game.ReplicatedStorage.Modules.PetBalance", [
        (
"""	MigrationNotice = "You can now choose six active pets. Your other pets are safe in Pets.",
""",
"""	MigrationNotice = "You can now choose your active pets. The rest wait in your inventory.", -- 2026-09-23: the Pets menu is gone
"""),
        (
"""	ReserveNotice = "Your new pet is in reserve - open Pets to equip it.",
""",
"""	ReserveNotice = "Your new pet is in your inventory - click it to let it out in your base.", -- 2026-09-23
"""),
    ]),
}

# files whose hunks go into patches.json THIS push (the round-1 hunks are live already; additive hunks whose
# old text survives inside the new one would apply twice, so they never ride again)
ACTIVE = {
    "ServerStorage.PetService.lua",
    "StarterPlayer.StarterPlayerScripts.EggHatchClient.client.lua",
}

SRC_FILES = [
    ("ServerScriptService.PetInventoryService.server.lua", "ServerScriptService.PetInventoryService", "Script"),
    ("StarterPlayer.StarterPlayerScripts.PetInventoryClient.client.lua", "StarterPlayer.StarterPlayerScripts.PetInventoryClient", "LocalScript"),
    ("StarterPlayer.StarterPlayerScripts.PetInfoClient.client.lua", "StarterPlayer.StarterPlayerScripts.PetInfoClient", "LocalScript"),
]


def main():
    os.makedirs(STAGE, exist_ok=True)
    for name in os.listdir(STAGE): # overwrite in place: serve.ps1 / OneDrive may hold the folder open
        try:
            os.remove(os.path.join(STAGE, name))
        except OSError:
            pass
    os.makedirs(PATCHED, exist_ok=True)
    entries = []
    for fname, (path, hunks) in PATCHES.items():
        text = open(os.path.join(ORIG, fname), encoding="utf-8").read().replace("\r\n", "\n")
        edits = []
        for old, new in hunks:
            n = text.count(old)
            if n != 1:
                sys.exit("%s: hunk occurs %d times:\n%s" % (fname, n, old[:300]))
            text = text.replace(old, new)
            edits.append({"old": old, "new": new})
        with open(os.path.join(PATCHED, fname), "w", encoding="utf-8", newline="\n") as f:
            f.write(text)
        if fname in ACTIVE:
            entries.append({"path": path, "file": fname, "edits": edits})
        print(fname, len(edits), "edits ->", len(text), "chars", "(staged)" if fname in ACTIVE else "(patched copy only)")
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
