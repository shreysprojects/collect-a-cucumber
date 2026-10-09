--[[
	WP-MENU_compact.lua  (2026-09-22, review fixes #2 / #7 / #11) - read-only for the DataModel.
	Run from an edit-peer execute_luau:
	  return loadstring(game:GetService("HttpService"):GetAsync("http://127.0.0.1:8795/WP-MENU_compact.lua"))()
	Builds the panel with the builder (module mode, source from WP-MENU_builder_embed.lua) into an
	UNPARENTED ScreenGui and starts PetView on it, then:
	  1. phone layout (#2): ResponsiveScale = MenuController.fit for an 844 x 390 landscape phone (S7: the
	     iPhone 13 simulator's GUI area is 749 x 310, FitMargin 1 -> 0.362; the old 844 x 332 case is checked
	     strictly too): Compact mode on, slot row + sort / filter tabs hidden, cycle /
	     best / back buttons shown, 2 grid columns; every compact button >= 40 real px on its short side;
	     every compact text's TextScaled size (TextService bounds of a realistic worst-case string in the
	     label's own font, box and SizeCap) >= 11 real px; the chip text too; no overlaps between the
	     compact rects that sit side by side; the Details page opens / closes (ShowDetails, closing the
	     panel); back above the threshold every authored (wide) value is restored exactly (compared with a
	     never-compacted build). Checker round: the Details traits line with a material + three / all eight
	     mutations (and the rich text PetView really renders for the all-eight pet) stays >= 30 design px in
	     its three-line compact box; a layout switch after view.SetFooter keeps those newer totals.
	  2. chips (#11): View.FitChips cases, and a rendered Diamond + RADIOACTIVE + PRISMATIC card whose chips
	     fit its row in both layouts (the "+N" count adds up).
	  3. big inventory (#7): 1000 pets -> the first render materialises 24 cards, the grid grows by batches
	     only while shown, the order stays contiguous, an unchanged re-render writes nothing, a changed
	     pet rewrites only its card; SetFooter touches only the footer.
	Nothing is parented into the DataModel. Returns "WP-MENU compact: PASS n / FAIL m: <first failures>".
]]
local HttpService = game:GetService("HttpService")
local StarterGui = game:GetService("StarterGui")
local TextService = game:GetService("TextService")

local pass, fail, failures, notes = 0, 0, {}, {}
local function check(name, condition, detail)
	if condition then
		pass += 1
	else
		fail += 1
		if #failures < 16 then table.insert(failures, name .. (detail ~= nil and (" [" .. tostring(detail) .. "]") or "")) end
	end
end

local builderSource = loadstring(HttpService:GetAsync("http://127.0.0.1:8795/WP-MENU_builder_embed.lua"))()
local Builder = loadstring(builderSource)({Mode = "module"})
local PetController = loadstring(HttpService:GetAsync("http://127.0.0.1:8793/StarterGui.CucumberMenus.PetController.lua"))()
local View = loadstring(HttpService:GetAsync("http://127.0.0.1:8793/StarterGui.CucumberMenus.PetView.lua"))()
local Core = PetController.Core
local NumberAbbrev = require(game:GetService("ReplicatedStorage").Modules.NumberAbbrev)
local art = StarterGui.CucumberMenus.IndexPanel.Content

-- MenuController.fit for the phone preset. S7 integration (2026-09-22): the iPhone 13 (844 x 390 landscape)
-- in Studio's device simulator gives a 749 x 310 GUI area (the notch / home-bar safe area and the 58 px top
-- bar), not the 844 x 332 assumed before, and the builder's FitMargin is 1 (was 0.95): fit = 0.3619. The
-- contract's rule is in DESIGN px (text >= 30, buttons >= 110), so the real-px floors are those at this fit
-- (10.86 / 39.8 px, "about 11 / about 40"); the 844 x 332 case is checked strictly against 11 / 40 below.
local FIT_MARGIN = 1
local PHONE = math.max(0.25, math.min(1, (749 - 32) / 1140, (310 - 44) / 735) * FIT_MARGIN)
local PHONE_844 = math.max(0.25, math.min(1, (844 - 32) / 1140, (332 - 44) / 735) * FIT_MARGIN)
local MIN_REAL_TEXT = 30 * PHONE - 1e-6
local MIN_REAL_TOUCH = 110 * PHONE - 1e-6

local fakeMenus = Instance.new("ScreenGui") -- never parented
fakeMenus.Name = "CucumberMenus"
local refMenus = Instance.new("ScreenGui") -- a never-compacted reference build
refMenus.Name = "CucumberMenus"
local view = nil

local function pet(id, key, income, rarity, extra)
	local v = {Id = id, Pet = key, DisplayName = "Pet " .. id, Rarity = rarity or "Common", Material = "", Mutations = {}, AcquiredAt = 0,
		Equipped = false, Status = "Reserve", AbilityRemaining = 60,
		Stats = {Income = income, ShotDamage = 3, ShotInterval = 2.5, DPS = 1.2, Range = 26, Ability = "Yield", AbilityChance = 0.01, AbilityDuration = 90, Fighter = false}}
	for k, value in pairs(extra or {}) do v[k] = value end
	return v
end

--.. TextScaled size a label gets for `text` in `box` (design px): the largest size in [min, max] whose bounds fit
local function Bounds(text, font, size, width, rich)
	local params = Instance.new("GetTextBoundsParams")
	params.Text = text
	params.Font = font
	params.Size = size
	params.Width = width
	params.RichText = rich == true -- the rendered traits line (Mutations.Font colour + <b> tags)
	local ok, bounds = pcall(TextService.GetTextBoundsAsync, TextService, params)
	if ok then return bounds end
	return TextService:GetTextSize(text, size, Enum.Font.FredokaOne, Vector2.new(width, 1e5))
end
--.. S7 integration (2026-09-22): PetView writes a cap's DESIGN value x the scale into MaxTextSize / MinTextSize
--.. (the engine applies them in screen px); the design value is Compact_<prop> while compact, else the
--.. DesignMaxTextSize / DesignMinTextSize attribute PetView keeps (or the authored property before a view ran)
local function DesignCap(cap, prop)
	local panel = cap:FindFirstAncestor("PetsPanel")
	local compactNow = panel ~= nil and panel:GetAttribute("Compact") == true
	local compactValue = cap:GetAttribute("Compact_" .. prop)
	if compactNow and type(compactValue) == "number" then return compactValue end
	local design = cap:GetAttribute("Design" .. prop)
	return type(design) == "number" and design or cap[prop]
end
local function ScaledSize(label, text, box, rich)
	local cap = label:FindFirstChildOfClass("UITextSizeConstraint")
	local lo, hi = cap and DesignCap(cap, "MinTextSize") or 1, cap and DesignCap(cap, "MaxTextSize") or 100
	local wrapped = label.TextWrapped
	local function fits(s)
		local b = Bounds(text, label.FontFace, s, wrapped and box.X or 1e5, rich)
		return b.X <= box.X + 0.5 and b.Y <= box.Y + 0.5
	end
	if not fits(lo) then return lo, false end
	while lo < hi do
		local mid = math.ceil((lo + hi) / 2)
		if fits(mid) then lo = mid else hi = mid - 1 end
	end
	return lo, true
end
local function DesignSize(inst, parentSize)
	local s = inst.Size
	parentSize = parentSize or Vector2.zero
	return Vector2.new(parentSize.X * s.X.Scale + s.X.Offset, parentSize.Y * s.Y.Scale + s.Y.Offset)
end
local function Rect(inst)
	local p, s = inst.Position, inst.Size
	local a = inst.AnchorPoint
	local x, y = p.X.Offset - a.X * s.X.Offset, p.Y.Offset - a.Y * s.Y.Offset
	return {x, y, x + s.X.Offset, y + s.Y.Offset}
end
local function Overlap(a, b)
	return a[1] < b[3] and b[1] < a[3] and a[2] < b[4] and b[2] < a[4]
end
local function cardsIn(grid)
	local list = {}
	for _, child in ipairs(grid:GetChildren()) do
		if child:IsA("TextButton") then list[#list + 1] = child end
	end
	return list
end

local ok, err = pcall(function()
	local panel = Builder.BuildPanel(fakeMenus, art)
	local refPanel = Builder.BuildPanel(refMenus, art)
	local content = panel.Content
	local toolbar, grid, details = content.Toolbar, content.PetGrid, content.Details

	--..builder: compact authoring..--
	check("CompactBelow attr", panel:GetAttribute("CompactBelow") == 0.55)
	check("cycle buttons authored hidden", toolbar:FindFirstChild("SortCycle") and toolbar.SortCycle.Visible == false and toolbar.SortCycle:GetAttribute("Compact_Visible") == true
		and toolbar:FindFirstChild("FilterCycle") and toolbar.FilterCycle.Visible == false)
	check("back button authored hidden", details:FindFirstChild("BackButton") and details.BackButton.Visible == false and details.BackButton:GetAttribute("Compact_Visible") == true)
	check("chip rows clip", panel.Templates.PetCard.Chips.ClipsDescendants == true)
	check("grid compact cells", grid.UIGridLayout:GetAttribute("Compact_CellSize") == UDim2.fromOffset(525, 196) and grid.UIGridLayout:GetAttribute("Compact_FillDirectionMaxCells") == 2)

	--..PetView: wide first..--
	view = View.Start(fakeMenus)
	task.wait()
	check("wide at the authored scale", panel:GetAttribute("Compact") == false and content.SlotRow.Visible and details.Visible)
	local pets = {
		pet("a", "Cat", 0.5, "Common", {Equipped = true, Status = "Active"}),
		pet("b", "Fox", 3.75, "Legendary", {Material = "Diamond", Mutations = {"RADIOACTIVE", "PRISMATIC"}}),
		pet("c", "Cosmo Cat", 15728640, "Mythical", {Status = "Unavailable", Mutations = {"SHADOW", "RADIOACTIVE", "FROZEN"}}),
	}
	for i = 1, 5 do table.insert(pets, pet("r" .. i, "Cat", i, "Rare")) end
	-- the longest traits line the game can make: a material + all eight known mutations (checker 2026-09-22)
	local ALL_MUTATIONS = {"NEON", "SHADOW", "FROZEN", "RADIOACTIVE", "MOLTEN", "ROYAL", "VOID", "PRISMATIC"}
	table.insert(pets, pet("z", "Fox", 0.25, "Mythical", {Material = "Diamond", Mutations = ALL_MUTATIONS}))
	local state = Core.ApplyState(nil, {Kind = "Full", Revision = 1, Generation = 1, Slots = 6, ServerTime = 100, EquippedIds = {"a"},
		Pets = pets, Totals = {Pet = 1230, Cucumber = 40200, CucumberBase = 40200, Total = 41430}, CombatLocked = false})
	local env = {Now = 110, Abbrev = NumberAbbrev.Abbrev}
	view.Render(Core.BuildViewModel(state, {Sort = "Income", Filter = "All"}, env))

	--..2. chips fitted by width (wide)..--
	local function chipCheck(tag, card)
		local row = card.Chips
		local layout = row:FindFirstChildOfClass("UIListLayout")
		local total, count, words = 0, 0, {}
		local size = nil
		for _, chip in ipairs(row:GetChildren()) do
			if chip.Name == "Chip" and chip.Visible then
				local label = chip.Label
				size = label.TextSize
				local pad = chip.Padding.PaddingLeft.Offset + chip.Padding.PaddingRight.Offset
				total += TextService:GetTextSize(label.Text, label.TextSize, Enum.Font.FredokaOne, Vector2.new(1e4, 1e4)).X + pad
				count += 1
				words[#words + 1] = label.Text
			end
		end
		total += math.max(0, count - 1) * layout.Padding.Offset
		check(tag .. " chips fit the row", total <= row.Size.X.Offset, ("%d > %d (%s)"):format(total, row.Size.X.Offset, table.concat(words, ",")))
		local shown = 0
		local plus = 0
		for _, w in ipairs(words) do
			local n = w:match("^%+(%d+)$")
			if n then plus = tonumber(n) else shown += 1 end
		end
		return shown, plus, table.concat(words, ","), size
	end
	local shownB, plusB, wordsB = chipCheck("wide Diamond+RADIOACTIVE+PRISMATIC", grid.Pet_b)
	check("wide chip count adds up", shownB + plusB == 3 and plusB >= 1, wordsB)
	local shownC, plusC, wordsC = chipCheck("wide SHADOW+RADIOACTIVE+FROZEN", grid.Pet_c)
	check("wide chip count adds up (c)", shownC + plusC == 3, wordsC)
	table.insert(notes, "wide chips b=" .. wordsB .. " c=" .. wordsC)

	--..FitChips (pure)..--
	local W = function(text) return #text * 10 end
	local function texts(list) local out = {} for i, c in ipairs(list) do out[i] = c.Text end return table.concat(out, ",") end
	local abc = {{Text = "aaa"}, {Text = "bbbb"}, {Text = "ccc"}}
	check("FitChips all fit", texts(View.FitChips(abc, W, 30 + 40 + 30 + 2 * 4, 4)) == "aaa,bbbb,ccc")
	check("FitChips folds the rest", texts(View.FitChips(abc, W, 30 + 4 + 20, 4)) == "aaa,+2", texts(View.FitChips(abc, W, 30 + 4 + 20, 4)))
	-- 107 < 108 (all three) but 30 + 4 + 40 + 4 + width("+1") 20 = 98 fits
	check("FitChips keeps 2 + '+1'", texts(View.FitChips(abc, W, 107, 4)) == "aaa,bbbb,+1", texts(View.FitChips(abc, W, 107, 4)))
	check("FitChips '+N' is counted in the width", texts(View.FitChips(abc, W, 97, 4)) == "aaa,+2", texts(View.FitChips(abc, W, 97, 4)))
	check("FitChips only '+N' when the first is too wide", texts(View.FitChips({{Text = "wiiiiiiiide"}, {Text = "b"}}, W, 25, 4)) == "+2")
	check("FitChips nothing fits", #View.FitChips(abc, W, 5, 4) == 0)
	check("FitChips empty", #View.FitChips({}, W, 100, 4) == 0 and #View.FitChips(nil, W, 100, 4) == 0)

	--..1. phone layout..--
	-- (checker 2026-09-22) the controller's Totals fast path writes only the footer; the switch below re-draws
	-- the held view model (footer "$41.4K/s") and must keep these newer totals
	view.SetFooter({Pet = "$5/s", Cucumber = "$4.99K/s", Total = "$5K/s"})
	panel.ResponsiveScale.Scale = PHONE
	task.wait()
	check("compact switch keeps the SetFooter totals", content.Footer.TotalCash.Text:find("$5K/s", 1, true) ~= nil
		and content.Footer.CucumberCash.Text:find("$4.99K/s", 1, true) ~= nil, content.Footer.TotalCash.Text)
	check("phone fit is ~0.362 (iPhone 13 safe area, FitMargin 1)", math.abs(PHONE - 0.3619) < 0.002, PHONE)
	check("builder FitMargin is the one fitted here", panel:GetAttribute("FitMargin") == FIT_MARGIN, panel:GetAttribute("FitMargin"))
	check("compact on", panel:GetAttribute("Compact") == true)
	check("slot row hidden", content.SlotRow.Visible == false)
	for _, name in ipairs({"SortIncome", "SortCombat", "SortRarity", "SortNewest", "FilterAll", "FilterActive", "FilterReserve"}) do
		check("tab hidden " .. name, toolbar[name].Visible == false)
	end
	for _, name in ipairs({"SortCycle", "FilterCycle", "BestIncome", "BestCombat"}) do
		check("compact button shown " .. name, toolbar[name].Visible == true)
	end
	check("cycle labels", toolbar.SortCycle.Label.Text == "SORT: INCOME" and toolbar.FilterCycle.Label.Text == "SHOW: ALL", toolbar.SortCycle.Label.Text)
	check("2 grid columns", grid.UIGridLayout.FillDirectionMaxCells == 2 and grid.UIGridLayout.CellSize == UDim2.fromOffset(525, 196))
	check("grid page shown, details hidden", grid.Visible and toolbar.Visible and details.Visible == false)
	check("compact card layout applied", grid.Pet_a.PetName.Size == UDim2.fromOffset(327, 44) and grid.Pet_a.Preview.Size == UDim2.fromOffset(172, 166))
	check("compact status tag replaces chips", grid.Pet_c.StatusTag.Visible == true and grid.Pet_c.Chips.Visible == false and grid.Pet_b.Chips.Visible == true)
	-- S7 integration: the live text caps are design x scale in screen px (compact design values here)
	local petNameCap = details.PetName:FindFirstChildOfClass("UITextSizeConstraint")
	check("S7 caps: Details.PetName compact 46 / 20 design -> screen px", petNameCap.MaxTextSize == math.floor(46 * PHONE + 0.5)
		and petNameCap.MinTextSize == math.floor(20 * PHONE + 0.5), petNameCap.MaxTextSize .. "/" .. petNameCap.MinTextSize)
	check("S7 caps: design values kept in attributes", petNameCap:GetAttribute("DesignMaxTextSize") == 36 and petNameCap:GetAttribute("DesignMinTextSize") == 8)
	local rarityCap = grid.Pet_a.RarityText:FindFirstChildOfClass("UITextSizeConstraint")
	check("S7 caps: a card's RarityText compact 30 -> 11 px", rarityCap.MaxTextSize == math.floor(30 * PHONE + 0.5) and rarityCap.MaxTextSize == 11, rarityCap.MaxTextSize)
	check("S7 caps: no cap has Min > Max", (function()
		for _, d in ipairs(content:GetDescendants()) do
			if d:IsA("UITextSizeConstraint") and d.MinTextSize > d.MaxTextSize then return false end
		end
		return true
	end)())

	-- touch targets (short side, real px)
	local cell = grid.UIGridLayout.CellSize
	local targets = {
		SortCycle = toolbar.SortCycle.Size, FilterCycle = toolbar.FilterCycle.Size, BestIncome = toolbar.BestIncome.Size,
		BestCombat = toolbar.BestCombat.Size, EquipButton = details.EquipButton.Size, BackButton = details.BackButton.Size,
		CloseButton = content.CloseButton.Size, PetCard = cell,
	}
	for name, size in pairs(targets) do
		local real = math.min(size.X.Offset, size.Y.Offset) * PHONE
		check("touch target " .. name .. " >= 110 design px (~40 px)", real >= MIN_REAL_TOUCH, ("%.1f px"):format(real))
		check("touch target " .. name .. " >= 40 px at 844 x 332", math.min(size.X.Offset, size.Y.Offset) * PHONE_844 >= 40)
	end
	-- the close button art stays centred in its bigger hit area
	local plate = content.CloseButton:FindFirstChild("Plate")
	if plate then
		local refPlate = refPanel.Content.CloseButton.Plate
		check("close art centred", plate.Position == refPlate.Position + UDim2.fromOffset(16, 16), tostring(plate.Position))
	end

	-- text sizes (real px) for realistic worst-case strings
	local cellSize = Vector2.new(cell.X.Offset, cell.Y.Offset)
	local card = grid.Pet_c
	local detailsSize = DesignSize(details)
	local texts = {
		{content.Header.Subtitle, "6 / 6 ACTIVE"},
		{content.LockBanner, "Finish defending your plot to change pets."},
		{content.Status, "Your pets are still loading - try again in a moment."},
		{toolbar.SortCycle.Label, "SORT: NEWEST", DesignSize(toolbar.SortCycle)},
		{toolbar.FilterCycle.Label, "SHOW: RESERVE", DesignSize(toolbar.FilterCycle)},
		{toolbar.BestIncome.Label, "BEST INCOME", DesignSize(toolbar.BestIncome)},
		{toolbar.BestCombat.Label, "BEST COMBAT", DesignSize(toolbar.BestCombat)},
		{card.PetName, "Flame Salamander", cellSize},
		{card.RarityText, "LEGENDARY", cellSize},
		{card.Rate, "$15.7M/s", cellSize},
		{card.EquippedTag, "ACTIVE", cellSize},
		{card.StatusTag, "Temporarily unavailable", cellSize},
		{grid.Empty, "No active pets - equip one from your reserve.", cellSize, cellSize},
		{details.PetName, "Flame Salamander", detailsSize},
		{details.Rarity, "LEGENDARY", detailsSize},
		{details.Traits, "Diamond  RADIOACTIVE  PRISMATIC", detailsSize},
		{details.Traits, "Diamond  RADIOACTIVE  PRISMATIC  SHADOW", detailsSize, nil, " (material + 3 mutations)"},
		{details.Traits, "Diamond  NEON  SHADOW  FROZEN  RADIOACTIVE  MOLTEN  ROYAL  VOID  PRISMATIC", detailsSize, nil, " (material + all 8)"},
		{details.CashLine, "Cash  $15.7M/s  (when active)", detailsSize},
		{details.CombatLine, "3.36K dmg every 2.5s  ·  1.34K nominal DPS  ·  range 26", detailsSize},
		{details.AbilityName, "Lucky Harvest", detailsSize},
		{details.AbilityEffect, "Lucky Harvest (x1.5 for 90s), Quick Grow (+25% for 90s) or Leaf Shield (blocks one theft for 240s)", detailsSize},
		{details.AbilityChance, "1% chance each active minute", detailsSize},
		{details.NextRoll, "Next chance roll in 0:42", detailsSize},
		{details.EquipButton.Label, "UNEQUIP ONE FIRST", DesignSize(details.EquipButton)},
		{details.BackButton.Label, "BACK", DesignSize(details.BackButton)},
		{content.Footer.PetCash, "Pets  $1.23K/s"},
		{content.Footer.CucumberCash, "Cucumbers  $40.2K/s"},
		{content.Footer.TotalCash, "Total  $41.4K/s"},
	}
	local smallest, smallestName = math.huge, ""
	for _, row in ipairs(texts) do
		local label, sample, parentSize, forced, tag = row[1], row[2], row[3], row[4], row[5]
		local box = forced or DesignSize(label, parentSize)
		local size, fits = ScaledSize(label, sample, box)
		local real = size * PHONE
		if real < smallest then smallest, smallestName = real, label.Name end
		check("text " .. label:GetFullName():match("[^%.]+%.[^%.]+$") .. (tag or "") .. " >= 30 design px (~11 px)", fits and real >= MIN_REAL_TEXT, ("%.1f px (size %d, box %dx%d)"):format(real, size, box.X, box.Y))
		check("text " .. label:GetFullName():match("[^%.]+%.[^%.]+$") .. (tag or "") .. " >= 11 px at 844 x 332", fits and size * PHONE_844 >= 11)
	end
	-- the traits line PetView actually renders (rich text: coloured, bold) for the material + all-eight pet
	view.Render(Core.BuildViewModel(state, {Sort = "Income", Filter = "All", SelectedId = "z"}, env))
	local traitsText = details.Traits.Text
	local _, bolds = traitsText:gsub("<b>", "")
	check("rendered traits carry all nine words", bolds == 9 and traitsText:find("PRISMATIC", 1, true) ~= nil and traitsText:find("Diamond", 1, true) ~= nil, traitsText)
	check("compact traits wrap (up to three lines)", details.Traits.TextWrapped == true and details.Traits.Size.Y.Offset >= 90
		and details.Traits.TextYAlignment == Enum.TextYAlignment.Top)
	local traitsSize, traitsFit = ScaledSize(details.Traits, traitsText, DesignSize(details.Traits, detailsSize), true)
	check("rendered 9-trait line >= 30 design px (rich)", traitsFit and traitsSize >= 30, ("size %d = %.1f px"):format(traitsSize, traitsSize * PHONE))
	table.insert(notes, ("rendered 9-trait line %d design px = %.1f real px"):format(traitsSize, traitsSize * PHONE))
	if traitsSize * PHONE < smallest then smallest, smallestName = traitsSize * PHONE, "Traits (rendered)" end
	view.Render(Core.BuildViewModel(state, {Sort = "Income", Filter = "All"}, env))
	table.insert(notes, ("smallest compact text %.1f px (%s)"):format(smallest, smallestName))
	local rarityStatus = ScaledSize(details.Rarity, "LEGENDARY  ·  TEMPORARILY UNAVAILABLE", DesignSize(details.Rarity))
	table.insert(notes, ("details rarity + status line %.1f px"):format(rarityStatus * PHONE))
	local shownPhone, plusPhone, wordsPhone, chipSize = chipCheck("compact Diamond+RADIOACTIVE+PRISMATIC", grid.Pet_b)
	check("compact chip count adds up", shownPhone + plusPhone == 3, wordsPhone)
	check("compact chip text >= 30 design px (~11 px)", chipSize and chipSize * PHONE >= MIN_REAL_TEXT, chipSize)
	table.insert(notes, "compact chips b=" .. wordsPhone)
	-- no overlaps between neighbouring compact rects
	local pairsToCheck = {
		{content.Toolbar, grid}, {grid, content.Footer}, {details, content.Footer}, {content.LockBanner, content.Status},
		{content.Status, content.Toolbar}, {content.LockBanner, content.CloseButton}, {content.Status, content.CloseButton},
		{details.EquipButton, details.CombatLine}, {details.BackButton, details.EquipButton}, {details.CashLine, details.EquipButton},
		{details.Preview, details.CombatLine}, {details.AbilityName, details.AbilityEffect}, {details.AbilityEffect, details.AbilityChance},
		{details.AbilityChance, details.NextRoll}, {card.Preview, card.PetName}, {card.RarityText, card.EquippedTag},
		{details.PetName, details.Rarity}, {details.Rarity, details.CashLine}, {details.CashLine, details.Traits},
		{details.Traits, details.CombatLine}, {details.Traits, details.EquipButton}, {details.Traits, details.Preview},
		{details.Traits, details.BackButton},
		{card.PetName, card.Chips}, {card.Chips, card.Rate}, {card.RarityText, card.PetName},
	}
	for _, pair in ipairs(pairsToCheck) do
		check("no overlap " .. pair[1].Name .. "/" .. pair[2].Name, not Overlap(Rect(pair[1]), Rect(pair[2])))
	end
	local d = Rect(details)
	check("details page inside the body", d[1] >= 10 and d[3] <= 1130 and d[2] >= 23 and d[4] <= 713)
	for _, child in ipairs(details:GetChildren()) do
		if child:IsA("GuiObject") and child.Visible then
			local r = Rect(child)
			check("details child inside " .. child.Name, r[1] >= 0 and r[2] >= 0 and r[3] <= detailsSize.X and r[4] <= detailsSize.Y, table.concat(r, ","))
		end
	end

	-- the Details page
	view.ShowDetails(true)
	check("details page opens", details.Visible and grid.Visible == false and toolbar.Visible == false and details.BackButton.Visible)
	check("focus target on the page", view.FocusTarget(false) == details.EquipButton)
	view.ShowDetails(false)
	check("details page closes", details.Visible == false and grid.Visible and toolbar.Visible)
	check("compact focus skips the hidden slots", view.FocusTarget(false) ~= content.SlotRow.Slot1)
	view.ShowDetails(true)
	content.Visible = true
	task.wait()
	content.Visible = false
	task.wait()
	check("closing the panel resets the page", details.Visible == false and grid.Visible)
	view.Render(Core.BuildViewModel(nil, {}, env))
	check("no state: page stays closed", details.Visible == false)
	view.Render(Core.BuildViewModel(state, {Sort = "Income", Filter = "All"}, env))
	view.SetFooter({Pet = "$6/s", Cucumber = "$5.99K/s", Total = "$6K/s"}) -- newer than the held view model's

	--..back to wide: every authored value restored..--
	panel.ResponsiveScale.Scale = 0.86
	task.wait()
	check("compact off", panel:GetAttribute("Compact") == false)
	local wideCap = details.PetName:FindFirstChildOfClass("UITextSizeConstraint")
	check("S7 caps: wide 36 / 8 design x 0.86", wideCap.MaxTextSize == 31 and wideCap.MinTextSize == 7, wideCap.MaxTextSize .. "/" .. wideCap.MinTextSize)
	check("wide switch keeps the SetFooter totals", content.Footer.TotalCash.Text:find("$6K/s", 1, true) ~= nil, content.Footer.TotalCash.Text)
	view.Render(Core.BuildViewModel(state, {Sort = "Income", Filter = "All"}, env))
	check("a real render still writes the view model's footer", content.Footer.TotalCash.Text:find("$6K/s", 1, true) == nil, content.Footer.TotalCash.Text)
	check("wide pages", details.Visible and grid.Visible and toolbar.Visible and content.SlotRow.Visible and details.BackButton.Visible == false)
	local shownAgain, plusAgain, wordsAgain, sizeAgain = chipCheck("wide again", grid.Pet_b)
	check("wide chips refitted at the wide size", shownAgain + plusAgain == 3 and sizeAgain == 14, wordsAgain .. " @" .. tostring(sizeAgain))
	view.ShowDetails(true)
	check("ShowDetails is a no-op in the wide layout", details.Visible and grid.Visible)
	local mismatches, compared = {}, 0
	local function compare(inst, ref)
		for name in pairs(ref:GetAttributes()) do
			if name:sub(1, 8) == "Compact_" then
				local prop = name:sub(9)
				compared += 1
				local value = inst[prop]
				-- S7: while a view runs, a text cap holds design x scale; its design value is the attribute
				if view and inst:IsA("UITextSizeConstraint") and (prop == "MaxTextSize" or prop == "MinTextSize") then
					value = inst:GetAttribute("Design" .. prop)
				end
				if value ~= ref[prop] then table.insert(mismatches, inst.Name .. "." .. prop) end
			end
		end
		for _, child in ipairs(ref:GetChildren()) do
			local mine = inst:FindFirstChild(child.Name)
			if mine and not (child.Name:match("^Pet_") or child.Name == "Chip") then compare(mine, child) end
		end
	end
	compare(content, refPanel.Content)
	check("wide values restored", #mismatches == 0 and compared > 60, table.concat(mismatches, ",") .. " / " .. compared)
	local refCard = refPanel.Templates.PetCard
	local cardMismatch = {}
	for _, name in ipairs({"PetName", "RarityText", "Rate", "Preview", "Chips", "StatusTag", "EquippedTag"}) do
		if grid.Pet_a[name].Size ~= refCard[name].Size or grid.Pet_a[name].Position ~= refCard[name].Position then table.insert(cardMismatch, name) end
	end
	check("wide card layout restored", #cardMismatch == 0, table.concat(cardMismatch, ","))
	-- a view destroyed while compact puts the authored layout back (a later view must capture wide values)
	panel.ResponsiveScale.Scale = PHONE
	task.wait()
	check("compact again before destroy", panel:GetAttribute("Compact") == true and content.SlotRow.Visible == false)
	view.Destroy()
	view = nil
	mismatches, compared = {}, 0
	compare(content, refPanel.Content)
	check("destroy while compact restores the wide layout", #mismatches == 0 and panel:GetAttribute("Compact") == false
		and details.Visible and grid.Visible and toolbar.Visible, table.concat(mismatches, ","))
	check("S7 caps: destroy puts the design caps back", wideCap.MaxTextSize == 36 and wideCap.MinTextSize == 8, wideCap.MaxTextSize .. "/" .. wideCap.MinTextSize)
	panel.ResponsiveScale.Scale = 0.86

	--..3. big inventory..--
	for _, child in ipairs(cardsIn(grid)) do child:Destroy() end
	view = View.Start(fakeMenus)
	local many = {}
	for i = 1, 1000 do many[i] = pet(("p%04d"):format(i), "Cat", i, "Common") end
	local big = Core.ApplyState(nil, {Kind = "Full", Revision = 1, Generation = 1, Slots = 6, ServerTime = 100, EquippedIds = {},
		Pets = many, Totals = {Pet = 0, Cucumber = 0, CucumberBase = 0, Total = 0}, CombatLocked = false})
	local t0 = os.clock()
	local vm = Core.BuildViewModel(big, {Sort = "Income", Filter = "All"}, env)
	local t1 = os.clock()
	view.Render(vm)
	local t2 = os.clock()
	table.insert(notes, ("1000 pets: BuildViewModel %.1f ms, first Render %.1f ms"):format((t1 - t0) * 1000, (t2 - t1) * 1000))
	check("first render materialises 24 cards", #cardsIn(grid) == 24, #cardsIn(grid))
	check("first card = best income", grid:FindFirstChild("Pet_p1000") and grid.Pet_p1000.LayoutOrder == 1)
	-- (an unparented ScreenGui still lays out: the 24th card sits ~8 rows down, far below the window)
	grid.CanvasPosition = Vector2.new(0, 1e6)
	task.wait(0.4)
	check("no growth while the panel is hidden", #cardsIn(grid) == 24, #cardsIn(grid))
	content.Visible = true
	grid.CanvasPosition = Vector2.new(0, 0)
	task.wait(0.4)
	check("no growth while the grid shows its top", #cardsIn(grid) == 24, #cardsIn(grid))
	grid.CanvasPosition = Vector2.new(0, 1e6) -- scrolled to the end: one batch, then the new last card is far again
	task.wait(0.5)
	local grown = #cardsIn(grid)
	check("grows one batch when scrolled to the end", grown == 24 + 18, grown)
	grid.CanvasPosition = Vector2.new(0, 1e6)
	task.wait(0.5)
	grown = #cardsIn(grid)
	check("grows again at the new end", grown == 24 + 2 * 18, grown)
	content.Visible = false
	-- order contiguous: the materialised cards are exactly display positions 1..n
	local orders, contiguous = {}, true
	for _, b in ipairs(cardsIn(grid)) do if b.Visible then orders[b.LayoutOrder] = b end end
	for i = 1, grown do if not orders[i] then contiguous = false end end
	check("materialised prefix is contiguous", contiguous)
	-- unchanged re-render writes nothing (a hand-written text survives), a changed pet rewrites its card
	grid.Pet_p1000.PetName.Text = "UNTOUCHED"
	grid.Pet_p0999.Rate.Text = "UNTOUCHED"
	view.Render(Core.BuildViewModel(big, {Sort = "Income", Filter = "All"}, env))
	check("unchanged cards are not rewritten", grid.Pet_p1000.PetName.Text == "UNTOUCHED" and grid.Pet_p0999.Rate.Text == "UNTOUCHED")
	local changed = table.clone(many[999])
	changed.Stats = table.clone(changed.Stats)
	changed.Stats.Income = 1234.5 -- now the best earner: its text and position change
	local big2 = Core.ApplyState(big, {Kind = "Delta", Revision = 2, BaseRevision = 1, Generation = 1, Upserts = {changed}, ServerTime = 120})
	grid.Pet_p0998.PetName.Text = "UNTOUCHED" -- keeps position 3, text and selection: must not be rewritten
	local t3 = os.clock()
	view.Render(Core.BuildViewModel(big2, {Sort = "Income", Filter = "All"}, env))
	table.insert(notes, ("1000 pets: one-pet delta build+render %.1f ms"):format((os.clock() - t3) * 1000))
	local expected = "$" .. NumberAbbrev.Abbrev(1234.5) .. "/s"
	check("changed card rewritten", grid.Pet_p0999.Rate.Text == expected and grid.Pet_p0999.LayoutOrder == 1, grid.Pet_p0999.Rate.Text)
	-- p1000 moved to position 2 and lost the default selection (the new first card has it), so it is rewritten
	check("moved card re-ordered + deselected", grid.Pet_p1000.LayoutOrder == 2 and grid.Pet_p1000.PetName.Text == "Pet p1000" and grid.Pet_p1000.Border.Thickness == 3)
	check("unaffected card not rewritten", grid.Pet_p0998.LayoutOrder == 3 and grid.Pet_p0998.PetName.Text == "UNTOUCHED")
	check("no extra cards from a re-render", #cardsIn(grid) == grown, #cardsIn(grid))
	-- a filter that shows fewer pets hides the pooled ones, a sort change keeps the prefix size
	view.Render(Core.BuildViewModel(big2, {Sort = "Newest", Filter = "All"}, env))
	local visible = 0
	for _, b in ipairs(cardsIn(grid)) do if b.Visible then visible += 1 end end
	check("sort change keeps the materialised prefix", visible == grown and #cardsIn(grid) <= grown + grown, visible)
	-- footer only
	local before = grid.Pet_p1000.PetName.Text
	view.SetFooter({Pet = "$9/s", Cucumber = "$8/s", Total = "$17/s"})
	check("SetFooter writes the footer", content.Footer.PetCash.Text:find("$9/s", 1, true) ~= nil and content.Footer.TotalCash.Text:find("$17/s", 1, true) ~= nil)
	check("SetFooter leaves the cards", grid.Pet_p1000.PetName.Text == before)
end)
if not ok then
	fail += 1
	table.insert(failures, 1, "ERROR " .. tostring(err))
end
if view then pcall(view.Destroy) end
fakeMenus:Destroy()
refMenus:Destroy()
return ("WP-MENU compact: PASS %d / FAIL %d%s || %s"):format(pass, fail, #failures > 0 and (": " .. table.concat(failures, "; ")) or "", table.concat(notes, " | "))
