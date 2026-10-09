--[[
	BankBuilder (2026-08-26, v3: multi-floor towers)
	Pure-geometry generator for the CUCUMBER BANK. Build(levels) destroys
	workspace.CucumberBank and rebuilds it from per-stall upgrade levels:
	a stall's width grows +5.75 studs per level (capped at +5 levels), its
	row re-packs so neighbors are PUSHED aside (never overlap), the deck /
	rails / carpet stretch to fit, and the user's loose gray east cap wall
	is refit to the end of the stall rows (the entry header + wing walls
	were deleted 2026-08-27 when the bank was docked at the lobby). Capacity is 6 + level (level = owner rebirths, capped 50),
	and EVERY 10 SLOTS THE STALL GROWS A FLOOR (2026-08-27, was 13): slots
	11+ live on storeys stacked above (floor 2 opens at rebirth 5, 3 at 15,
	4 at 25, 5 at 35, 6 at 45; max cap 56 = 6 floors). Each storey is reached through a small hole in
	its front-west corner with a gold truss ladder below it -- the holes
	stack in one column, so one continuous climb reaches the top. Roofs
	are per-stall and ride on the highest storey (a 1-floor stall's roof
	sits exactly where the old shared row roof did).
	v4 (2026-08-26): each stall gets a SECURITY LEVER (clone of
	ReplicatedStorage.Lever, named VaultLever) between the podium row and
	the gate, tucked to the EAST so it clears the door and the west ladder
	column. Pure prop here -- VaultService.Rebind adds its prompt and
	countdown card.
	No connections or state here -- VaultService rebinds after every Build.
]]

local BankBuilder = {}

local PURPLE = Color3.fromRGB(127, 139, 154)
local PURPLE_LIGHT = Color3.fromRGB(152, 160, 178)
local PURPLE_DARK = Color3.fromRGB(96, 104, 122)
local GOLD = Color3.fromRGB(255, 199, 56)
local CARPET_RED = Color3.fromRGB(196, 40, 28)
local LASER_RED = Color3.fromRGB(255, 55, 45)

--.. 2026-08-26: podiums + collect pads scaled 1.5x, so the whole stall
--.. plan scaled with them -- width, width-per-level, depth, podium row
--.. depth, spacings, and edge margins all x1.5 to keep everything clear
--.. of everything else (podiums, pads, the lever, the ladder hole, and
--.. the shared walls between neighboring vaults).
--.. 2026-08-27 (user): podiums spaced out 2 MORE studs per gap, so stall
--.. widths grew with them -- BASE_W +2 per base gap (5 gaps: 26 -> 36)
--.. and W_PER_LEVEL +2 (each level adds a podium = one more gap) -- the
--.. same podium counts fit inside at every level as before.
local BASE_W = 36          -- stall inner width at level 0 (fits the 6 default 3.6-wide podiums)
local W_PER_LEVEL = 5.75   -- width gained per upgrade
local MAX_W_LEVELS = 5     -- width stops growing past this (capacity keeps going). 2026-08-27: was 8 -- levels 6-8 of width only existed to fit podiums 11-13, dead space since floors cap at 10; max width 64.75 = exactly 10 podiums at full 6.65 spacing, and floors start at level 5 = max width
local WALL_T = 2.5         -- shared side-wall thickness
local DEPTH = 24.5         -- 2026-08-27: +5 deeper at the back (was 19.5); podium row d moved with it
local WALL_H = 13          -- ground-storey walls; keep = FLOOR_H - 1 so the wall top stays flush with the storey-2 slab bottom
local WALK_HALF = 9        -- walkway half-width (center z = 8)
local AISLE = 7
--.. 2026-08-27 (user): whole bank slid 54 studs WEST so the deck docks
--.. right at the lobby's east side (arch x 45, deck from x 42) -- the old
--.. red-carpet pier gap is gone, and the entry header/wing walls were
--.. deleted in Studio (only the loose east cap wall remains).
local X0 = 46
local NSTALL = 6           -- stalls per row (2026-08-27, was 8: stalls 7/8/15/16 removed, rows renumbered 1-6 / 7-12)
local BASE_CAPACITY = 6    -- podiums every vault starts with (2026-08-26, was 3)
local MAX_LEVEL = 50       -- mirrors RebirthService.MAX_REBIRTHS: capacity tops at 56 (+3 more via the Vault slots board upgrade = 59)
local MAX_EXTRA_SLOTS = 3  -- "Vault slots" upgrade-board purchases, +1 podium each (2026-08-27)
local FLOOR_H = 14         -- one storey, slab top to slab top (2026-08-27: +2 headroom, was 12; ground storey: 2.8 -> 16.8)
local SLOTS_PER_FLOOR = 10 -- every 10 slots is a new floor (2026-08-27, was 13; max cap 56 = 6 floors)
local HOLE_W = 8           -- corner ladder hole, along the stall width (2x'd 2026-08-26)
local HOLE_D = 6.8         -- corner ladder hole, in from the stall front

function BankBuilder.WidthFor(level)
	return BASE_W + W_PER_LEVEL * math.clamp(level or 0, 0, MAX_W_LEVELS)
end

function BankBuilder.CapacityFor(level, extra)
	return BASE_CAPACITY + math.clamp(level or 0, 0, MAX_LEVEL) + math.clamp(extra or 0, 0, MAX_EXTRA_SLOTS)
end

function BankBuilder.FloorsFor(capacity)
	return math.max(1, math.ceil((capacity or 0) / SLOTS_PER_FLOOR))
end

--.. one rank of podiums along the back wall of a storey; physical fit caps
--.. how many of `capacity` actually materialize (13 at max width)
function BankBuilder.SpotLayout(width, capacity)
	--.. ONE row of podiums along the back wall (user call 2026-08-26: never
	--.. spill into a second row). Spacing +2 across the board 2026-08-27:
	--.. spacing eases from 6.65 down to 5.9 as upgrades add podiums (3.6-
	--.. wide podiums keep >= 2.3 studs of air), edge margin 4.8 keeps the
	--.. outermost podium 0.6 clear of the shared side walls, so physical
	--.. capacity caps at floor((width-4.8)/5.9)+1 -- 11 fit at max width,
	--.. SLOTS_PER_FLOOR keeps rows to 10.
	local usable = width - 4.8
	local maxFit = math.max(1, math.floor(usable / 5.9) + 1)
	local n = math.min(capacity, maxFit)
	local spacing = n > 1 and math.min(6.65, usable / (n - 1)) or 0
	local spots = {}
	for k = 1, n do
		--.. d = DEPTH - 3.6: the row keeps its 3.6-stud gap to the back wall
		--.. (2026-08-27: 15.9 -> 20.9 alongside the +5 DEPTH extension)
		table.insert(spots, {ox = (k - (n + 1) / 2) * spacing, d = 20.9, h = 3.0})
	end
	return spots
end

function BankBuilder.Build(levels, extras)
	levels = levels or {}
	extras = extras or {}
	local old = workspace:FindFirstChild("CucumberBank")
	local leverSrc = game:GetService("ReplicatedStorage"):FindFirstChild("Lever")

	--.. STYLE INHERITANCE: the bank the user styles in Studio is the source
	--.. of truth for looks. Before rebuilding, sample Material/Color/
	--.. MaterialVariant per part KIND (names with trailing digits collapse:
	--.. Pedestal3 -> Pedestal) from the current bank, and apply that style to
	--.. every regenerated part. First boot samples the edit-time bank; later
	--.. relayouts sample the previous runtime bank, so the style never drifts
	--.. back to the hardcoded defaults below (they are only a fallback for
	--.. brand-new part kinds).
	local styleByKind = {}
	if old then
		for _, d in ipairs(old:GetDescendants()) do
			if d:IsA("BasePart") then
				local kind = d.Name:gsub("%d+$", "")
				if not styleByKind[kind] then
					styleByKind[kind] = {Material = d.Material; Color = d.Color; MaterialVariant = d.MaterialVariant;}
				end
			end
		end
	end

	--.. the user's Upgrader board now stands near the BANK ENTRANCE (moved
	--.. 2026-08-27; a loose workspace model, not part of the bank). Capture
	--.. its X-offset from the deck's WEST edge -- the entrance never moves
	--.. when stalls widen, so the board stays put through every rebuild
	--.. (east-edge anchoring would drift it eastward as the deck grows).
	local upgrader = workspace:FindFirstChild("Upgrader")
	local upgraderStartOffset
	if upgrader and old then
		local oldSlab = old:FindFirstChild("DeckSlab", true)
		if oldSlab then
			upgraderStartOffset = upgrader:GetPivot().Position.X - (oldSlab.Position.X - oldSlab.Size.X / 2)
		end
	end

	if old then old:Destroy() end

	local bank = Instance.new("Model")
	bank.Name = "CucumberBank"
	local deckF = Instance.new("Folder") deckF.Name = "Deck" deckF.Parent = bank
	local stallsF = Instance.new("Folder") stallsF.Name = "Stalls" stallsF.Parent = bank

	local function P(props, parent)
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = true
		p.CanQuery = true
		p.CanTouch = false
		p.Material = Enum.Material.Glacier
		p.Color = PURPLE
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		for k, v in pairs(props) do p[k] = v end
		--.. the user's Studio styling wins over the defaults above
		local st = styleByKind[p.Name:gsub("%d+$", "")]
		if st then
			p.Material = st.Material
			p.Color = st.Color
			pcall(function() p.MaterialVariant = st.MaterialVariant end)
		end
		p.Parent = parent or deckF
		return p
	end

	--.. per-row stall widths -> row lengths -> deck length
	local ROWS = {
		{front = 8 + WALK_HALF, dir = 1, face = Enum.NormalId.Front, ids = {1, 2, 3, 4, 5, 6}},
		{front = 8 - WALK_HALF, dir = -1, face = Enum.NormalId.Back, ids = {7, 8, 9, 10, 11, 12}},
	}
	local maxRowLen = 0
	for _, row in ipairs(ROWS) do
		local len = WALL_T
		row.widths = {}
		for k, id in ipairs(row.ids) do
			--.. bought vault slots widen the stall exactly like a rebirth level would,
			--.. keeping SpotLayout's one-podium-per-width-level fit guarantee intact
			row.widths[k] = BankBuilder.WidthFor((levels[id] or 0) + (extras[id] or 0))
			len += row.widths[k] + WALL_T
		end
		row.len = len
		maxRowLen = math.max(maxRowLen, len)
	end

	local DECK_X0 = 42
	local DECK_X1 = X0 + maxRowLen + 8
	local deckLen = DECK_X1 - DECK_X0
	local deckCX = (DECK_X0 + DECK_X1) / 2
	local Z_N_EDGE = 8 + WALK_HALF + DEPTH + 1.5 + AISLE
	local Z_S_EDGE = 8 - WALK_HALF - DEPTH - 1.5 - AISLE
	local deckW = Z_N_EDGE - Z_S_EDGE + 2
	local deckCZ = (Z_N_EDGE + Z_S_EDGE) / 2

	-- ===== deck =====
	local slab = P({Name = "DeckSlab"; Size = Vector3.new(deckLen, 1.2, deckW); CFrame = CFrame.new(deckCX, 2.2, deckCZ);})
	bank.PrimaryPart = slab
	P({Name = "DeckSkirt"; Size = Vector3.new(deckLen + 3, 2.6, deckW + 3); CFrame = CFrame.new(deckCX, 0.4, deckCZ); Color = PURPLE_DARK;})
	local x = 58
	while x < DECK_X1 - 6 do
		P({Name = "Support"; Size = Vector3.new(5, 34, 5); CFrame = CFrame.new(x, -16, deckCZ); Color = PURPLE_DARK;})
		x += 38
	end
	--.. one continuous run of red: the walkway carpet starts EXACTLY where
	--.. the apron carpet ends (x 43, same y) -- there used to be a 1-stud
	--.. seam of bare deck between the two
	P({Name = "Carpet"; Size = Vector3.new((DECK_X1 - 2) - 43, 0.18, 8); CFrame = CFrame.new((43 + DECK_X1 - 2) / 2, 2.88, 8); Color = CARPET_RED; CanCollide = false;})
	P({Name = "Apron"; Size = Vector3.new(9, 1.2, 18); CFrame = CFrame.new(38.5, 2.19, 8);})
	P({Name = "ApronCarpet"; Size = Vector3.new(9, 0.18, 8); CFrame = CFrame.new(38.5, 2.88, 8); Color = CARPET_RED; CanCollide = false;})

	-- ===== entry arch =====
	for _, z in ipairs({8 - WALK_HALF - 0.5, 8 + WALK_HALF + 0.5}) do
		P({Name = "ArchPillar"; Size = Vector3.new(2.2, 11, 2.2); CFrame = CFrame.new(45, 8.3, z); Color = GOLD; Material = Enum.Material.SmoothPlastic;})
	end
	local beam = P({Name = "ArchBeam"; Size = Vector3.new(2.6, 3.4, WALK_HALF * 2 + 3); CFrame = CFrame.new(45, 15.5, 8); Color = GOLD; Material = Enum.Material.SmoothPlastic;})
	for _, face in ipairs({Enum.NormalId.Left, Enum.NormalId.Right}) do
		local g = Instance.new("SurfaceGui")
		g.Face = face
		g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		g.PixelsPerStud = 40
		local t = Instance.new("TextLabel")
		t.Size = UDim2.fromScale(1, 1)
		t.BackgroundTransparency = 1
		t.Font = Enum.Font.FredokaOne
		t.TextScaled = true
		t.TextColor3 = Color3.fromRGB(60, 40, 5)
		t.Text = "\u{1F952} CUCUMBER BANK \u{1F952}"
		t.Parent = g
		g.Parent = beam
	end
	for _, z in ipairs({8 - WALK_HALF + 1, 8 + WALK_HALF - 1}) do
		local l = Instance.new("PointLight")
		l.Color = GOLD
		l.Range = 14
		l.Brightness = 1.2
		l.Parent = P({Name = "ArchLampGlow"; Size = Vector3.new(0.9, 0.9, 0.9); CFrame = CFrame.new(45, 13.4, z); Color = GOLD; Material = Enum.Material.Neon; CanCollide = false;})
	end

	-- ===== railings =====
	local function rail(cx, cz, sx, sz)
		P({Name = "RailBase"; Size = Vector3.new(sx, 2.6, sz); CFrame = CFrame.new(cx, 4.1, cz); Color = PURPLE_DARK;})
		P({Name = "RailCap"; Size = Vector3.new(sx + 0.4, 0.6, sz + 0.4); CFrame = CFrame.new(cx, 5.7, cz); Color = GOLD; Material = Enum.Material.SmoothPlastic;})
	end
	rail(deckCX, Z_N_EDGE + 0.9, deckLen, 1.2)
	rail(deckCX, Z_S_EDGE - 0.9, deckLen, 1.2)
	--.. the two short WEST entrance rails were removed by the user 2026-08-27
	--.. (they had been stranded mid-deck at x 96.6 since the 54-west move)

	-- ===== stall rows =====
	for _, row in ipairs(ROWS) do
		local zIn = row.front + row.dir * DEPTH / 2
		local zBack = row.front + row.dir * (DEPTH + 0.75)
		local zSign = row.front - row.dir * 0.35
		local wallCY = 2.8 + WALL_H / 2
		P({Name = "RowBackWall"; Size = Vector3.new(row.len + 2, WALL_H, 1.5); CFrame = CFrame.new(X0 + row.len / 2, wallCY, zBack);})
		P({Name = "RowFascia"; Size = Vector3.new(row.len + 4, 1.6, 1); CFrame = CFrame.new(X0 + row.len / 2, 2.8 + WALL_H - 0.4, row.front + row.dir * 0.4); Color = GOLD; Material = Enum.Material.SmoothPlastic;})

		local cursor = X0
		P({Name = "SideWall"; Size = Vector3.new(WALL_T, WALL_H, DEPTH + 1); CFrame = CFrame.new(cursor + WALL_T / 2, wallCY, row.front + row.dir * (DEPTH / 2 + 0.5));})
		for k, id in ipairs(row.ids) do
			local w = row.widths[k]
			local level = math.max(0, levels[id] or 0)
			local extra = math.max(0, extras[id] or 0)
			local cx = cursor + WALL_T + w / 2
			cursor += WALL_T + w
			P({Name = "SideWall"; Size = Vector3.new(WALL_T, WALL_H, DEPTH + 1); CFrame = CFrame.new(cursor + WALL_T / 2, wallCY, row.front + row.dir * (DEPTH / 2 + 0.5));})

			local stall = Instance.new("Model")
			stall.Name = "Stall_" .. id
			stall:SetAttribute("StallId", id)
			stall:SetAttribute("Level", level)
			stall.Parent = stallsF

			P({Name = "FloorTile"; Size = Vector3.new(w, 0.22, DEPTH + 0.4); CFrame = CFrame.new(cx, 2.9, zIn); Color = PURPLE_LIGHT;}, stall)

			local sign = P({Name = "NameSign"; Size = Vector3.new(math.min(w * 0.75, 16), 2.5, 0.5); CFrame = CFrame.new(cx, 2.8 + WALL_H - 2.3, zSign); Color = PURPLE_DARK; Material = Enum.Material.SmoothPlastic;}, stall)
			local sg = Instance.new("SurfaceGui")
			sg.Name = "SignGui"
			sg.Face = row.face
			sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			sg.PixelsPerStud = 45
			local tl = Instance.new("TextLabel")
			tl.Name = "Label"
			tl.Size = UDim2.fromScale(1, 1)
			tl.BackgroundTransparency = 1
			tl.Font = Enum.Font.FredokaOne
			tl.TextScaled = true
			tl.TextColor3 = Color3.fromRGB(235, 235, 245)
			tl.Text = "EMPTY"
			tl.Parent = sg
			sg.Parent = sign

			local lasers = Instance.new("Folder") lasers.Name = "Lasers" lasers.Parent = stall
			--.. VERTICAL bars (2026-08-27, user: Steal-a-Brainrot reference):
			--.. evenly spaced ~2 studs apart across the doorway, each running
			--.. from the stall floor up to the UNDERSIDE of the gold RowFascia
			--.. (fascia bottom = 2.8 + WALL_H - 1.2; user call same day --
			--.. bars poking past the fascia toward the roof read wrong).
			--.. Replaced the old 4 stacked horizontal beams.
			local barTop = 2.8 + WALL_H - 1.2
			local barH = barTop - 2.8
			local nBars = math.max(2, math.floor(w / 2 + 0.5))
			for li = 1, nBars do
				local bx = cx - w / 2 + (li - 0.5) * (w / nBars)
				local lp = P({Name = "Laser" .. li; Size = Vector3.new(0.35, barH, 0.35);
					CFrame = CFrame.new(bx, 2.8 + barH / 2, row.front); Color = LASER_RED; Material = Enum.Material.Neon;
					Transparency = 0.05; CanCollide = false; CastShadow = false;}, lasers)
				lp.CanTouch = false
			end
			local zone = P({Name = "DoorZone"; Size = Vector3.new(w, WALL_H - 0.6, 1.6); CFrame = CFrame.new(cx, 2.8 + (WALL_H - 0.6) / 2 + 0.3, row.front);
				Transparency = 1; CanCollide = false; CastShadow = false;}, stall)
			zone.CanTouch = true

			--.. security lever (stealing update 2026-08-26): stands between
			--.. the podium row and the gate, against the EAST wall so it
			--.. never blocks the door or the west ladder column. Pure prop --
			--.. VaultService.Rebind adds the prompt + countdown billboard.
			if leverSrc then
				local lever = leverSrc:Clone()
				lever.Name = "VaultLever"
				for _, d in ipairs(lever:GetDescendants()) do
					if d:IsA("ProximityPrompt") then d:Destroy() end
				end
				local _, lsize = lever:GetBoundingBox()
				--.. FloorTile top is y 3.01; pivot = bounding-box center
				lever:PivotTo(CFrame.new(cx + w / 2 - 2.1, 3.01 + lsize.Y / 2, row.front + row.dir * 3.4))
				lever.Parent = stall
			end

			local capacity = BankBuilder.CapacityFor(level, extra)
			local floorsN = BankBuilder.FloorsFor(capacity)
			local holeX0 = cx - w / 2 -- ladder column hugs the west wall at the stall FRONT

			--.. per-stall roof rides on the highest storey (13 studs of
			--.. headroom above each walking surface since the +2 FLOOR_H bump)
			P({Name = "RowRoof"; Size = Vector3.new(w + WALL_T, 1, DEPTH + 3);
				CFrame = CFrame.new(cx, 2.8 + floorsN * FLOOR_H - 0.5, zIn + row.dir * 0.6);}, stall)

			--.. ===== upper storeys (every 13 slots is a new floor) =====
			for f = 2, floorsN do
				local S = 2.8 + (f - 1) * FLOOR_H -- this storey's walking surface

				--.. slab in two parts, leaving a HOLE_W x HOLE_D opening at the
				--.. front-west corner; holes stack in one column so the truss
				--.. ladders line up into one continuous climb
				P({Name = "FloorTile"; Size = Vector3.new(w - HOLE_W, 1, DEPTH + 0.4);
					CFrame = CFrame.new(cx + HOLE_W / 2, S - 0.5, zIn);}, stall)
				local stripLen = DEPTH + 0.2 - HOLE_D
				P({Name = "FloorTile"; Size = Vector3.new(HOLE_W, 1, stripLen);
					CFrame = CFrame.new(holeX0 + HOLE_W / 2, S - 0.5, row.front + row.dir * (HOLE_D + stripLen / 2));}, stall)

				--.. storey walls: sides sit 0.6 into the shared 2.5-stud wall
				--.. zone so two neighboring towers never overlap; front + back
				--.. close the box (the front sits above the ground-floor door)
				for _, sx in ipairs({-1, 1}) do
					P({Name = "SideWall"; Size = Vector3.new(1.2, FLOOR_H, DEPTH + 1);
						CFrame = CFrame.new(cx + sx * (w / 2 + 0.6), S + FLOOR_H / 2, row.front + row.dir * (DEPTH / 2 + 0.5));}, stall)
				end
				P({Name = "RowBackWall"; Size = Vector3.new(w + 2.4, FLOOR_H, 1.5); CFrame = CFrame.new(cx, S + FLOOR_H / 2, zBack);}, stall)
				P({Name = "RowBackWall"; Size = Vector3.new(w + 2.4, FLOOR_H, 1.2); CFrame = CFrame.new(cx, S + FLOOR_H / 2, row.front);}, stall)

				--.. ceiling lamp so the enclosed storey isn't a cave
				local lamp = P({Name = "TowerLamp"; Size = Vector3.new(1.6, 0.4, 1.6);
					CFrame = CFrame.new(cx, S + FLOOR_H - 1.2, zIn); Color = GOLD; Material = Enum.Material.Neon; CanCollide = false;}, stall)
				local li = Instance.new("PointLight")
				li.Color = Color3.fromRGB(255, 236, 190)
				--.. light ONE storey only: modest range + real shadows. Without
				--.. Shadows, PointLights shine straight through the slabs and
				--.. walls, so a 5-floor tower stacked 4 overlapping 39-stud
				--.. lights and washed the upper storeys out.
				li.Range = 20
				li.Brightness = 0.65
				li.Shadows = true
				li.Parent = lamp

				--.. gold truss ladder up from the storey below, on the hole's
				--.. EAST edge so its face sits flush with the main slab -- a
				--.. clean step-off at the top instead of a jump across the hole
				local truss = Instance.new("TrussPart")
				truss.Name = "VaultLadder"
				truss.Anchored = true
				truss.Size = Vector3.new(2, FLOOR_H, 2)
				truss.CFrame = CFrame.new(holeX0 + HOLE_W - 1, S - FLOOR_H / 2, row.front + row.dir * 1.7)
				truss.Color = GOLD
				truss.Material = Enum.Material.Metal
				local st = styleByKind["VaultLadder"]
				if st then
					truss.Material = st.Material
					truss.Color = st.Color
				end
				truss.Parent = stall
			end

			--.. ===== podiums, 10 per storey, globally indexed 1..capacity =====
			local peds = Instance.new("Folder") peds.Name = "Pedestals" peds.Parent = stall
			for f = 1, floorsN do
				local S = 2.8 + (f - 1) * FLOOR_H
				local base = (f - 1) * SLOTS_PER_FLOOR
				local count = math.clamp(capacity - base, 0, SLOTS_PER_FLOOR)
				for si, s in ipairs(BankBuilder.SpotLayout(w, count)) do
					local idx = base + si
					local pz = row.front + row.dir * s.d
					local pedestal = P({Name = "Pedestal" .. idx; Shape = Enum.PartType.Cylinder; Size = Vector3.new(s.h, 3.6, 3.6);
						CFrame = CFrame.new(cx + s.ox, S + s.h / 2, pz) * CFrame.Angles(0, 0, math.rad(90));
						Color = GOLD; Material = Enum.Material.SmoothPlastic;}, peds)
					pedestal:SetAttribute("SpotIndex", idx)
					--.. every podium carries its own prompt: Store Cucumber / Take
					--.. Back / Replace, retitled live by VaultService
					local prompt = Instance.new("ProximityPrompt")
					prompt.Name = "PodiumPrompt"
					prompt.ActionText = "Store Cucumber"
					prompt.ObjectText = "Podium"
					prompt.HoldDuration = 0.25
					prompt.MaxActivationDistance = 7
					prompt.RequiresLineOfSight = false
					prompt.Parent = pedestal
					--.. NO physical upgrade sign anymore (2026-08-27, user: the
					--.. plates read as clutter): the UPGRADE pill now lives in the
					--.. cucumber's overhead EarnBillboard (VaultService). The old
					--.. RS.UpgradeSignTemplate is kept untouched for reverting --
					--.. see ServerStorage.UpgradeBoardsBackup_2026_08_27.README.
					local spot = P({Name = "Spot" .. idx; Size = Vector3.new(0.4, 0.4, 0.4);
						CFrame = CFrame.new(cx + s.ox, S + s.h + 0.2, pz);
						Transparency = 1; CanCollide = false; CastShadow = false;}, peds)
					spot:SetAttribute("SpotIndex", idx)
					--.. per-cucumber money pad, Steal-a-Brainrot style: earnings pile
					--.. up here; the owner steps on it to collect (VaultService).
					--.. size + spacing = the user's Studio-tuned pad (2026-08-27,
					--.. sampled from their edited CollectPad): 2.1 deep (was 3.3),
					--.. center d - 4.25 = podium radius 1.8 + pad half 1.05 + 1.4 gap
					local cpad = P({Name = "CollectPad" .. idx; Size = Vector3.new(3.3, 0.33, 2.1);
						CFrame = CFrame.new(cx + s.ox, S + 0.18, row.front + row.dir * (s.d - 4.25));
						Color = Color3.fromRGB(90, 255, 90); Material = Enum.Material.Neon;
						CanCollide = false; CastShadow = false;}, peds)
					cpad.CanTouch = true
					cpad:SetAttribute("SpotIndex", idx)
				end
			end
		end
	end

	--.. the plaza wayfinding sign (BankSignPost/Board "CUCUMBER BANK ->") was
	--.. removed by the user 2026-08-27 -- the bank docks at the lobby now, so
	--.. it no longer needs pointing at

	bank.Parent = workspace

	--.. 2026-08-27 (user): whole bank raised 1.6 studs. One final lift of the
	--.. finished model keeps every internal Y literal (the deck-top 2.8 math,
	--.. storey S, lasers, sign heights...) untouched -- do NOT re-derive them.
	bank:PivotTo(bank:GetPivot() + Vector3.new(0, 1.6, 0))

	-- ===== keep the Upgrader board at its entrance-relative spot =====
	if upgrader and upgraderStartOffset then
		local pivot = upgrader:GetPivot()
		local targetX = DECK_X0 + upgraderStartOffset
		upgrader:PivotTo(pivot + Vector3.new(targetX - pivot.Position.X, 0, 0))
	end

	-- ===== refit the user's loose east cap wall =====
	--.. 2026-08-27: the bank docks at the lobby now, and the user DELETED
	--.. the entry header facade + both wing walls -- only the loose east
	--.. cap remains. It rides flush against the END OF THE STALL ROWS
	--.. (not the deck edge -- user realignment), keeping its Studio size,
	--.. height and z placement.
	for _, wpart in ipairs(workspace:GetChildren()) do
		if wpart:IsA("BasePart") and wpart.Name == "Part" and wpart.Position.X > 150 then
			local p = wpart.Position
			wpart.CFrame = CFrame.new(X0 + maxRowLen + wpart.Size.X / 2, p.Y, p.Z)
		end
	end

	return bank
end

return BankBuilder
