--[[
	WP-MENU_view.lua  (2026-09-22) - builder + PetView smoke test, read-only for the DataModel.
	Run from an edit-peer execute_luau:
	  return loadstring(game:GetService("HttpService"):GetAsync("http://127.0.0.1:8795/WP-MENU_view.lua"))()
	  1. loads builders/build_petspanel.lua in module mode (source text from the WP-MENU_builder_embed.lua
	     fixture, because builders/ is not served) and builds the panel into an UNPARENTED ScreenGui, the
	     opener into an unparented clone of StarterGui.CucumberHUDDesign and the reveal lines into an
	     unparented clone of StarterGui.EggRevealUI (StarterGui itself is only read / cloned);
	  2. checks every contract name (CONTRACTS 3.11.1) and that a second build is idempotent;
	  3. starts PetView on the fake ScreenGui, renders view models from PetController.Core (fake state),
	     checks cards / slots / details / footer / banner, filtering (hidden, pooled), removal (destroyed),
	     lazy previews (a few built per scan, real PetsCatalog models), then destroys everything.
	Nothing is parented into the DataModel. Returns "WP-MENU view: PASS n / FAIL m: <first failures>".
]]
local HttpService = game:GetService("HttpService")
local StarterGui = game:GetService("StarterGui")

local pass, fail, failures = 0, 0, {}
local function check(name, condition, detail)
	if condition then
		pass += 1
	else
		fail += 1
		if #failures < 14 then table.insert(failures, name .. (detail ~= nil and (" [" .. tostring(detail) .. "]") or "")) end
	end
end

local builderSource = loadstring(HttpService:GetAsync("http://127.0.0.1:8795/WP-MENU_builder_embed.lua"))()
local Builder = loadstring(builderSource)({Mode = "module"})
local PetController = loadstring(HttpService:GetAsync("http://127.0.0.1:8793/StarterGui.CucumberMenus.PetController.lua"))()
local View = loadstring(HttpService:GetAsync("http://127.0.0.1:8793/StarterGui.CucumberMenus.PetView.lua"))()
local Core = PetController.Core
local NumberAbbrev = require(game:GetService("ReplicatedStorage").Modules.NumberAbbrev)

local fakeMenus = Instance.new("ScreenGui") -- never parented
fakeMenus.Name = "CucumberMenus"
local fakeHud = StarterGui.CucumberHUDDesign:Clone() -- never parented (its scripts cannot run)
local fakeReveal = StarterGui.EggRevealUI:Clone()
local art = StarterGui.CucumberMenus.IndexPanel.Content
local view = nil

local ok, err = pcall(function()
	--..1. builder..--
	local panel = Builder.BuildPanel(fakeMenus, art)
	local count1 = #panel:GetDescendants()
	local contentBefore = panel.Content
	Builder.BuildPanel(fakeMenus, art)
	check("idempotent panel", fakeMenus.PetsPanel == panel and #panel:GetDescendants() == count1 and panel.Content == contentBefore, #panel:GetDescendants() .. " vs " .. count1)
	check("one PetsPanel", #fakeMenus:GetChildren() == 1)
	check("panel frame", panel:IsA("Frame") and panel.Size == UDim2.fromOffset(1140, 735) and panel.AnchorPoint == Vector2.new(0.5, 0.5))
	check("panel attrs", panel:GetAttribute("FitMargin") == 1 and type(panel:GetAttribute("Reference")) == "string") -- S7: 0.95 -> 1
	check("ResponsiveScale", panel:FindFirstChild("ResponsiveScale") and panel.ResponsiveScale:IsA("UIScale"))
	local content = panel.Content
	check("Content canvas", content:IsA("CanvasGroup") and content.Visible == false and content.GroupTransparency == 1)
	check("MotionScale", content:FindFirstChild("MotionScale") and content.MotionScale:IsA("UIScale"))
	for _, name in ipairs({"Shadow", "Body", "Header", "CloseButton", "SlotRow", "Toolbar", "PetGrid", "Details", "Footer", "LockBanner", "Status"}) do
		check("content." .. name, content:FindFirstChild(name) ~= nil)
	end
	check("header texts", content.Header.Title.Text == "PETS" and content.Header.Subtitle.Text == "0 / 6 ACTIVE")
	check("close selectable", content.CloseButton:IsA("GuiButton") and content.CloseButton.Selectable)
	for i = 1, 6 do
		local slot = content.SlotRow:FindFirstChild("Slot" .. i)
		check("Slot" .. i, slot and slot:IsA("TextButton") and slot.Visible and slot.Selectable and slot:FindFirstChild("Preview") and slot:FindFirstChild("PetName") and slot:FindFirstChild("Empty"))
	end
	check("SlotRow SelectionGroup", content.SlotRow.SelectionGroup == true)
	for _, name in ipairs({"SortIncome", "SortCombat", "SortRarity", "SortNewest", "FilterAll", "FilterActive", "FilterReserve", "BestIncome", "BestCombat"}) do
		local button = content.Toolbar:FindFirstChild(name)
		check("toolbar." .. name, button and button:IsA("GuiButton") and button.Selectable and button:FindFirstChild("Label") and button:FindFirstChild("Gradient"))
	end
	local grid = content.PetGrid
	check("PetGrid", grid:IsA("ScrollingFrame") and grid.SelectionGroup and grid:FindFirstChild("UIGridLayout") and grid:FindFirstChild("Empty"))
	for _, name in ipairs({"Preview", "PetName", "Rarity", "Traits", "CashLine", "CombatLine", "AbilityName", "AbilityEffect", "AbilityChance", "NextRoll", "EquipButton"}) do
		check("details." .. name, content.Details:FindFirstChild(name) ~= nil)
	end
	check("details preview viewport", content.Details.Preview:IsA("ViewportFrame"))
	check("equip button", content.Details.EquipButton:IsA("GuiButton") and content.Details.EquipButton.Selectable)
	for _, name in ipairs({"PetCash", "CucumberCash", "TotalCash"}) do check("footer." .. name, content.Footer:FindFirstChild(name) ~= nil) end
	local templates = panel:FindFirstChild("Templates")
	check("Templates folder", templates and templates:IsA("Folder"))
	local card = templates.PetCard
	check("PetCard", card:IsA("TextButton") and card.Selectable and card.AutoButtonColor == false and card.Visible == false)
	for _, name in ipairs({"Preview", "PetName", "RarityBar", "RarityText", "Chips", "Rate", "EquippedTag", "StatusTag"}) do
		check("PetCard." .. name, card:FindFirstChild(name) ~= nil)
	end
	check("PetCard types", card.Preview:IsA("ViewportFrame") and card.RarityBar:IsA("Frame") and card.Chips:FindFirstChildOfClass("UIListLayout") and card.EquippedTag.Text == "ACTIVE")
	check("SlotCard", templates.SlotCard:IsA("TextButton") and templates.SlotCard.Selectable and templates.SlotCard.Visible == false and templates.SlotCard.Empty.Text == "Empty")
	local chip = templates.Chip
	check("Chip", chip:IsA("Frame") and chip.AutomaticSize == Enum.AutomaticSize.X and chip.Visible == false and chip:FindFirstChild("Label") and chip:FindFirstChildOfClass("UICorner"))
	check("no stray UIScale on buttons", content.CloseButton:FindFirstChildOfClass("UIScale") == nil)

	local pets = Builder.BuildOpener(fakeHud)
	Builder.BuildOpener(fakeHud)
	local menu = fakeHud.LeftMenu
	local petsCount = 0
	for _, child in ipairs(menu:GetChildren()) do if child.Name == "Pets" then petsCount += 1 end end
	check("opener idempotent", petsCount == 1)
	pets = menu.Pets
	check("opener rect", pets.Position == UDim2.new(1.07, 0, 0, 0) and pets.Size == UDim2.new(1, 0, 0.455, 0) and pets.ZIndex == 2 and pets.Visible)
	local square = pets:FindFirstChild("Square")
	check("opener square", square and square:IsA("UIAspectRatioConstraint") and square.AspectRatio == 1 and square.DominantAxis == Enum.DominantAxis.Height)
	check("opener shell", pets:FindFirstChild("Fill") and pets:FindFirstChild("Outline") and pets:FindFirstChild("Corners"))
	check("opener no Index bits", pets:FindFirstChild("BookIcon") == nil and pets:FindFirstChild("OpenIndex") == nil)
	check("opener paw", pets:FindFirstChild("PawIcon") and pets.PawIcon:FindFirstChild("Pad") and pets.PawIcon:FindFirstChild("Toe1") and pets.PawIcon:FindFirstChild("Toe4"))
	check("opener label", pets:FindFirstChild("Label") and pets.Label.Text == "Pets")
	local open = pets:FindFirstChild("OpenPets")
	check("opener button", open and open:IsA("TextButton") and open.Size == UDim2.fromScale(1, 1) and open.ZIndex == 30 and open.BackgroundTransparency == 1)
	check("opener no FXScale/HoverScale", pets:FindFirstChild("FXScale") == nil and pets:FindFirstChild("HoverScale") == nil)
	check("opener did not touch Index", menu.Index:FindFirstChild("BookIcon") ~= nil and menu.Index:FindFirstChild("OpenIndex") ~= nil)

	Builder.BuildRevealLabels(fakeReveal)
	Builder.BuildRevealLabels(fakeReveal)
	local tpl = fakeReveal.SingleTemplate
	local statsLine, traitsLine = tpl:FindFirstChild("PetStats"), tpl:FindFirstChild("PetTraits")
	check("reveal PetStats", statsLine and statsLine:IsA("TextLabel") and statsLine.Size == UDim2.new(0.42, 0, 0.036, 0) and statsLine.Position == UDim2.new(0.5, 0, 0.8, 0) and statsLine.RichText and statsLine.TextScaled and statsLine.Visible == false)
	check("reveal PetTraits", traitsLine and traitsLine.Size == UDim2.new(0.42, 0, 0.03, 0) and traitsLine.Position == UDim2.new(0.5, 0, 0.762, 0) and traitsLine.Visible == false)
	local stroke = statsLine and statsLine:FindFirstChildOfClass("UIStroke")
	check("reveal stroke", stroke and stroke.Thickness == 2.5 and stroke.Color == Color3.fromRGB(12, 12, 12) and stroke.ApplyStrokeMode == Enum.ApplyStrokeMode.Contextual)
	local lines = 0
	for _, child in ipairs(tpl:GetChildren()) do if child.Name == "PetStats" or child.Name == "PetTraits" then lines += 1 end end
	check("reveal idempotent", lines == 2)

	--..2. PetView..--
	view = View.Start(fakeMenus)
	local selected, equipped, sorted = nil, nil, nil
	view.OnSelect(function(id) selected = id end)
	view.OnEquip(function(id, equip) equipped = {id, equip} end)
	view.OnSort(function(mode) sorted = mode end)
	local function pet(id, key, income, rarity, extra)
		local v = {Id = id, Pet = key, DisplayName = "Pet " .. id, Rarity = rarity, Material = "", Mutations = {}, AcquiredAt = 0,
			Equipped = false, Status = "Reserve", AbilityRemaining = 60,
			Stats = {Income = income, ShotDamage = 3, ShotInterval = 2.5, DPS = 1.2, Range = 26, Ability = "Yield", AbilityChance = 0.01, AbilityDuration = 90}}
		for k, value in pairs(extra or {}) do v[k] = value end
		return v
	end
	local payload = {Kind = "Full", Revision = 1, Generation = 1, Slots = 6, ServerTime = 100, EquippedIds = {"a"},
		Pets = {
			pet("a", "Cat", 0.5, "Common", {Equipped = true, Status = "Active"}),
			pet("b", "Fox", 3.75, "Legendary", {Material = "Golden", Mutations = {"NEON", "ROYAL"}}),
			pet("c", "Cosmo Cat", 15728640, "Mythical", {Mutations = {"PRISMATIC"}}),
			pet("d", "NoSuchPet", 1, "Common", {Status = "Invalid",
				Stats = {Income = 1, ShotDamage = 0, ShotInterval = 0, DPS = 0, Range = 0, Ability = "None", AbilityChance = 0, Fighter = false}}),
		},
		Totals = {Pet = 0.5, Cucumber = 40200, CucumberBase = 40200, Total = 40200.5}, CombatLocked = false}
	local state = Core.ApplyState(nil, payload)
	local env = {Now = 110, Abbrev = NumberAbbrev.Abbrev}
	local vm = Core.BuildViewModel(state, {Sort = "Income", Filter = "All"}, env)
	view.Render(vm)
	local shown = {}
	for _, child in ipairs(grid:GetChildren()) do
		if child:IsA("TextButton") and child.Visible then shown[#shown + 1] = child end
	end
	table.sort(shown, function(x, y) return x.LayoutOrder < y.LayoutOrder end)
	check("4 cards rendered", #shown == 4, #shown)
	check("card order", shown[1] and shown[1].Name == "Pet_c" and shown[4] and shown[4].Name == "Pet_a", shown[1] and shown[1].Name)
	local cardC = grid:FindFirstChild("Pet_c")
	check("card texts", cardC and cardC.PetName.Text == "Pet c" and cardC.Rate.Text == "$15.7M/s" and cardC.RarityText.Text == "MYTHICAL", cardC and cardC.Rate.Text)
	check("card selected border", cardC and cardC.Border.Thickness == 5)
	local cardB = grid:FindFirstChild("Pet_b")
	local chips = 0
	for _, child in ipairs(cardB.Chips:GetChildren()) do if child.Name == "Chip" and child.Visible then chips += 1 end end
	check("card chips", chips == 3, chips)
	check("equipped tag", grid.Pet_a.EquippedTag.Visible == true and cardB.EquippedTag.Visible == false)
	check("invalid status tag", grid.Pet_d.StatusTag.Visible and grid.Pet_d.StatusTag.Text == "Unknown pet")
	check("slot 1 filled", content.SlotRow.Slot1.PetName.Text == "Pet a" and content.SlotRow.Slot1.Empty.Visible == false)
	check("slot 2 empty", content.SlotRow.Slot2.Empty.Visible == true)
	check("slot 1 preview built", content.SlotRow.Slot1.Preview:FindFirstChild("PreviewModel") ~= nil)
	check("subtitle", content.Header.Subtitle.Text == "1 / 6 ACTIVE")
	local details = content.Details
	check("details name", details.PetName.Text == "Pet c")
	check("details cash rich", details.CashLine.Text:find("$15.7M/s", 1, true) ~= nil and details.CashLine.Text:find("#41EB14", 1, true) ~= nil, details.CashLine.Text)
	check("details traits rich", details.Traits.Text:find("PRISMATIC", 1, true) ~= nil)
	check("details equip", details.EquipButton.Visible and details.EquipButton.Label.Text == "EQUIP")
	check("details preview", details.Preview:FindFirstChild("PreviewModel") ~= nil and details.Preview.CurrentCamera ~= nil)
	check("footer", content.Footer.PetCash.Text:find("$0.5/s", 1, true) ~= nil and content.Footer.CucumberCash.Text:find("$40.2K/s", 1, true) ~= nil, content.Footer.PetCash.Text)
	check("banner hidden", content.LockBanner.Visible == false)
	check("empty hidden", grid.Empty.Visible == false)
	view.SetNextRoll("Next chance roll in 0:12")
	check("SetNextRoll", details.NextRoll.Text == "Next chance roll in 0:12")
	view.SetStatus("Loading pets...")
	check("SetStatus", content.Status.Visible and content.Status.Text == "Loading pets...")
	view.SetStatus(nil)
	check("SetStatus clear", content.Status.Visible == false)
	check("FocusTarget slot", view.FocusTarget(false) == content.SlotRow.Slot1)
	check("FocusTarget card", view.FocusTarget(true) == cardC)
	-- 2026-09-22 (review #10): the unknown-species pet is not shown as a fighter
	local stats = require(game:GetService("ReplicatedStorage").Modules.PetStats)
	local balance = require(game:GetService("ReplicatedStorage").Modules.PetBalance)
	view.Render(Core.BuildViewModel(state, {Sort = "Income", Filter = "All", SelectedId = "d"},
		{Now = 110, Abbrev = NumberAbbrev.Abbrev, Stats = stats, Abilities = balance.ABILITIES, Text = balance.TEXT}))
	check("invalid pet: No ability in white", details.AbilityName.Text == "No ability" and details.AbilityName.TextColor3 == Color3.new(1, 1, 1), details.AbilityName.Text)
	check("invalid pet: no fighter effect", details.AbilityEffect.Text == "" and not details.AbilityEffect.Text:find("Fighter", 1, true))
	check("invalid pet: does not fight", details.CombatLine.Text == "Does not fight", details.CombatLine.Text)
	view.Render(vm)

	-- lazy previews: nothing built while the panel is hidden, a few per scan once it shows
	local function built()
		local n = 0
		for _, child in ipairs(grid:GetChildren()) do
			if child:IsA("TextButton") and child.Preview:FindFirstChild("PreviewModel") then n += 1 end
		end
		return n
	end
	task.wait(0.4)
	check("no previews while hidden", built() == 0, built())
	content.Visible = true
	task.wait(0.6)
	local builtNow = built()
	check("previews built lazily", builtNow >= 3, builtNow)
	check("missing model has no preview", grid.Pet_d.Preview:FindFirstChild("PreviewModel") == nil)
	content.Visible = false

	-- filter hides (pooled), selection follows, removal destroys
	local vm2 = Core.BuildViewModel(state, {Sort = "Income", Filter = "Active"}, env)
	view.Render(vm2)
	check("filter hides pooled cards", grid:FindFirstChild("Pet_b") == cardB and cardB.Visible == false and grid.Pet_a.Visible == true)
	local state2 = Core.ApplyState(state, {Kind = "Delta", Revision = 2, BaseRevision = 1, Generation = 1, Removed = {"b"}, ServerTime = 120})
	view.Render(Core.BuildViewModel(state2, {Sort = "Income", Filter = "All"}, env))
	check("removed card destroyed", grid:FindFirstChild("Pet_b") == nil and cardB.Parent == nil)
	-- lock banner + disabled equip
	local locked = Core.ApplyState(state2, {Kind = "Delta", Revision = 3, BaseRevision = 2, Generation = 1, CombatLocked = true, ServerTime = 130})
	view.Render(Core.BuildViewModel(locked, {SelectedId = "a"}, {Now = 130, Abbrev = NumberAbbrev.Abbrev, Text = {LockBanner = "Finish defending your plot to change pets."}}))
	check("lock banner shown", content.LockBanner.Visible and content.LockBanner.Text == "Finish defending your plot to change pets.")
	check("locked equip text", details.EquipButton.Label.Text == "UNEQUIP")
	-- loading view model (no state) empties the grid
	view.Render(Core.BuildViewModel(nil, {}, env))
	local left = 0
	for _, child in ipairs(grid:GetChildren()) do if child:IsA("TextButton") then left += 1 end end
	check("no state clears cards", left == 0, left)
	check("no state details", details.EquipButton.Visible == false and details.PetName.Text == "")
	check("callbacks untouched by render", selected == nil and equipped == nil and sorted == nil)
end)
if not ok then
	fail += 1
	table.insert(failures, 1, "ERROR " .. tostring(err))
end
if view then pcall(view.Destroy) end
fakeMenus:Destroy()
fakeHud:Destroy()
fakeReveal:Destroy()
return ("WP-MENU view: PASS %d / FAIL %d%s"):format(pass, fail, #failures > 0 and (": " .. table.concat(failures, "; ")) or "")
