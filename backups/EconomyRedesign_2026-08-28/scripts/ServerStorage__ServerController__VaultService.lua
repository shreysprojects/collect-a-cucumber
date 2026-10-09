--[[
	VaultService (2026-08-26, v2: rebirth upgrades)
	Runs the CUCUMBER BANK. Geometry is now DYNAMIC: script.BankBuilder
	rebuilds workspace.CucumberBank from per-stall upgrade levels, where a
	stall's level = its owner's REBIRTH count (leaderstats.Rebirths, watched
	live -- every rebirth upgrades the vault by exactly 1). Upgrading widens
	the stall (+2.5 studs/level, width capped at +8 levels) -- the whole row
	re-packs so neighbors are pushed aside, never overlapped -- and adds one
	display pedestal (+1 capacity, uncapped until the floor physically fills).
	After every rebuild this service re-binds instances, re-places stored
	cucumbers, and re-arms doors/prompts. Earning loop: each displayed
	cucumber pays its Rate in Coins to the stall owner every second.
	v5 (2026-08-26): PERSISTENCE -- stored cucumbers save to the profile
	(Data.VaultCucumbers, write-through via SaveVault on every mutation +
	the accrual tick; LoadVault restores them on stall assignment).
	v3 (2026-08-26): MULTI-FLOOR TOWERS -- every 13 slots the stall grows a
	storey (13 podiums per floor; with the 6-podium base capacity, floor 2
	opens after rebirth 7, 3 after 20, 4 after 33, 5 after 46; rebirths
	hard-cap at 50 in RebirthService).
	Storeys stack above the ground floor, reached through a corner hole +
	gold truss ladder column. All floor math lives in BankBuilder
	(FloorsFor / CapacityFor / SLOTS_PER_FLOOR).
	v4 (2026-08-26): LEVER SECURITY + STEALING -- every stall has a security
	lever (clone of ReplicatedStorage.Lever, placed by BankBuilder between
	the podiums and the gate) with a countdown card above it. A pull locks
	the stall for SECURE_DURATION (lasers up, door bounces intruders). When
	the timer lapses the lasers drop and ANY other player can walk in and
	hold F on a stored cucumber to steal it onto their arm, then carry it
	home to their own vault (teleports stay carry-blocked, so they must
	WALK). No victim-side recovery yet, by design. ANTI-CHEAT: prompt
	visibility is client state -- VaultService.Steal re-validates lock
	state, thief presence, and empty hands on the server.
	REVERT: delete workspace.CucumberBank + this module (incl. BankBuilder
	child) + the "Vault interop" block in CarryService. Backups:
	ServerStorage.CucumberBankBackup_v1/v2 + backups/*.rbxm files;
	pre-floors snapshot: ServerStorage.VaultBackup_PreFloors_2026_08_26
	(geometry + VaultService + RebirthService, see its README).
]]

--..Services..--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")

--..Modules..--
local ServerController = require(ServerStorage.ServerController)
local ControllerLoader = require(ReplicatedStorage.Modules.ControllerLoader)
local Network = ControllerLoader.GetController("Network")
local BankBuilder = require(script:WaitForChild("BankBuilder"))

--..Variables..--
local PUSH_DEBOUNCE = 0.6
local NSTALLS = 12 -- 6 per row (2026-08-27, was 16)

--.. CUCUMBER UPGRADES (2026-08-26): R-prompt on each stored cucumber.
--.. money/sec = base x 1.18^(level-1) (CarryService.EffectiveRate);
--.. upgrade cost = base cost x 1.35^(level-1), paid in CUKES.
local MAX_LEVEL = 20
local COST_MULT = 1.35
local BASE_COST_PER_RATE = 500 -- base cost = base rate x this, in Cukes

--.. VAULT SECURITY (2026-08-26): a lever pull keeps the stall locked for
--.. this many seconds; then the lasers drop until the owner pulls again
local SECURE_DURATION = 300

local Stalls = {} -- [id] = stable record; instance refs refreshed on every rebuild
local StallOf = {} -- [player] = stall record
local LastPush = {} -- [player] = os.clock()
local LastSteal = {} -- [player] = os.clock() of their last successful steal grab
local LastUpgradeClick = {} -- [player] = os.clock() rate limit for the sign buttons
local relayoutQueued = false

local VaultService = {}

--..Functions..--

local function Notify(plr, msg, kind)
	Network:FireClient(plr, "Notif", {Message = msg; Type = kind or "Error";})
end

--.. ===== SFX PASS (2026-08-26): vault sounds + client-FX plumbing =====
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

--.. server 3D one-shots go through SoundController.PlaySound (non-blocking,
--.. rolloff-capped). Resolved lazily + pcall'd so a SoundController hiccup
--.. can never take the vault down. Server sounds bypass the client SFX
--.. setting, so they are used ONLY for social moments (alarms, lever, zap,
--.. deposits, construction) -- personal feedback rides VaultFX below.
local SoundFX
local function PlaySound3D(name, parent, opts, cutAfter)
	if not (parent and parent.Parent) then return nil end
	if SoundFX == nil then
		local ok, sc = pcall(function()
			return ControllerLoader.GetController("SoundController")
		end)
		SoundFX = (ok and sc) or false
	end
	if not SoundFX then return nil end
	local ok, sound = pcall(SoundFX.PlaySound, name, parent, opts)
	if not ok then return nil end
	if sound and cutAfter then
		task.delay(cutAfter, function()
			pcall(function()
				if sound.Parent then sound:Stop() sound:Destroy() end
			end)
		end)
	end
	return sound
end

--.. owner-personal sounds/visuals ride one RemoteEvent ("VaultFX", created
--.. lazily by Network.GetEventHandler on the first Fire, same as Notif);
--.. VaultFXClient renders every {Kind = ...} payload
local function FireVaultFX(plr, payload)
	if not plr or plr.Parent ~= Players then return end
	pcall(function()
		Network:FireClient(plr, "VaultFX", payload)
	end)
end

--.. ambient bank hum: a low looped machinery buzz on the deck slab. Lazily
--.. (re-)created -- BankBuilder.Build destroys the whole bank on every
--.. relayout, so Relayout calls this right after each Build.
local function EnsureBankHum()
	pcall(function()
		local bank = workspace:FindFirstChild("CucumberBank")
		local slab = bank and (bank.PrimaryPart or bank:FindFirstChild("DeckSlab", true))
		if not slab or slab:FindFirstChild("BankHum") then return end
		local template = ReplicatedStorage.Assets.Sounds:FindFirstChild("Electric Buzz")
		if not template then return end
		local s = template:Clone()
		s.Name = "BankHum"
		s.Looped = true
		s.Volume = 0.08
		s.PlaybackSpeed = 0.5 -- reads as machinery/AC, not electricity
		s.RollOffMinDistance = 8
		s.RollOffMaxDistance = 90
		s.Parent = slab
		s:Play()
	end)
end

--.. $18.2K-style short numbers for the overhead cards and collect pads
local function Abbrev(n)
	n = math.floor(math.max(0, n))
	local function trim(v)
		local s = string.format("%.1f", v)
		return (s:gsub("%.0$", ""))
	end
	if n >= 1e9 then return trim(n / 1e9) .. "B"
	elseif n >= 1e6 then return trim(n / 1e6) .. "M"
	elseif n >= 1e3 then return trim(n / 1e3) .. "K" end
	return tostring(n)
end

--.. a stored cucumber's displayed worth -- CarryService.ValueOf is the one
--.. source of truth (the sell vendor pays the same number)
local function ValueOf(record)
	return ServerController.GetModule("CarryService").ValueOf(record)
end

local function EffRate(record)
	return ServerController.GetModule("CarryService").EffectiveRate(record)
end

--.. rates can be fractional after upgrades: show one decimal when it matters
local function RateText(r)
	if r >= 1000 then return Abbrev(r) end
	if math.abs(r - math.floor(r + 0.5)) < 0.05 then return tostring(math.floor(r + 0.5)) end
	return string.format("%.1f", r)
end

--.. cost to go from the record's CURRENT level to the next one
local function UpgradeCostFor(record)
	return math.floor((record.Rate or 1) * BASE_COST_PER_RATE * COST_MULT ^ ((record.Level or 1) - 1))
end

--.. the podium's UPGRADE control (2026-08-27, user request: the pedestal
--.. sign plates read as clutter, especially on mobile): a glossy green pill
--.. row INSIDE the cucumber's overhead EarnBillboard card, styled after the
--.. old physical board (green pill + gold Cukes price + cucumber icon).
--.. Workspace BillboardGuis never receive native GuiButton input, so clicks
--.. are a screen-rect test in VaultFXClient -- same "VaultUpgradeClick" net
--.. event, and VaultService.Upgrade keeps every ownership/cost check.
--.. Row always visible on occupied podiums (2026-08-27 -- the old
--.. hide-while-carrying rule made rows vanish for whole sessions whenever
--.. a pet carry proc'd); an empty podium has no billboard, hence no button.
--.. REVERT: ServerStorage.UpgradeBoardsBackup_2026_08_27.README
local CUKE_ICON = "rbxassetid://137909083365853" -- user-picked cucumber icon (2026-08-26)
local COIN_ICON = "rbxassetid://15402839520" -- the HUD wallet's coin (bottom-left indicator)
local UPGRADE_ROW_H = 36 -- must stay in sync with the card heights in DisplayOn
local function EnsureUpgradeRow(stall, spotIndex, record)
	local model = record and record.Model
	local primary = model and model.PrimaryPart
	local bb = primary and primary:FindFirstChild("EarnBillboard")
	if not bb then return nil end
	local row = bb:FindFirstChild("UpgradeRow")
	if row then return row end
	row = Instance.new("Frame")
	row.Name = "UpgradeRow"
	row.Size = UDim2.new(1, 0, 0, UPGRADE_ROW_H)
	row.BackgroundTransparency = 1
	row.LayoutOrder = 5
	--.. everything inside the row is SCALE-sized: VaultTextClient's stall
	--.. zoom scales the row's pixel height like a text line, and the pill
	--.. + labels ride along automatically
	local btn = Instance.new("TextButton")
	btn.Name = "UpgradeButton"
	btn.AnchorPoint = Vector2.new(0.5, 0.5)
	btn.Position = UDim2.fromScale(0.5, 0.5)
	btn.Size = UDim2.fromScale(0.86, 0.88)
	btn.BackgroundColor3 = Color3.fromRGB(88, 199, 88)
	btn.Text = ""
	btn.AutoButtonColor = false
	btn:SetAttribute("StallId", stall.Id)
	btn:SetAttribute("Spot", spotIndex)
	CollectionService:AddTag(btn, "VaultUpgradeButton")
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = btn
	local stroke = Instance.new("UIStroke")
	--.. Border mode is REQUIRED here: the default Contextual mode strokes a
	--.. TextButton's TEXT, and this button's Text is "" -- so it drew nothing
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = Color3.fromRGB(35, 90, 35)
	stroke.Thickness = 3
	stroke.Parent = btn
	local gloss = Instance.new("UIGradient")
	gloss.Rotation = 90
	gloss.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(170, 170, 170))
	gloss.Parent = btn
	local text = Instance.new("TextLabel")
	text.Name = "UpgradeText"
	text.BackgroundTransparency = 1
	text.AnchorPoint = Vector2.new(0, 0.5)
	text.Position = UDim2.fromScale(0.05, 0.5)
	text.Size = UDim2.fromScale(0.5, 0.82)
	text.Font = Enum.Font.FredokaOne
	text.TextScaled = true
	text.TextColor3 = Color3.new(1, 1, 1)
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.Text = "UPGRADE"
	local textStroke = Instance.new("UIStroke")
	textStroke.Color = Color3.fromRGB(25, 60, 25)
	textStroke.Thickness = 3
	textStroke.Parent = text
	text.Parent = btn
	local icon = Instance.new("ImageLabel")
	icon.Name = "CukeIcon"
	icon.BackgroundTransparency = 1
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.fromScale(0.58, 0.5)
	icon.Size = UDim2.fromScale(0.66, 0.66)
	icon.SizeConstraint = Enum.SizeConstraint.RelativeYY
	icon.Image = CUKE_ICON
	icon.Parent = btn
	local cost = Instance.new("TextLabel")
	cost.Name = "CostLabel"
	cost.BackgroundTransparency = 1
	cost.AnchorPoint = Vector2.new(1, 0.5)
	cost.Position = UDim2.fromScale(0.96, 0.5)
	cost.Size = UDim2.fromScale(0.26, 0.72)
	cost.FontFace = Font.new("rbxasset://fonts/families/FredokaOne.json", Enum.FontWeight.Bold)
	cost.TextScaled = true
	cost.TextColor3 = Color3.fromRGB(255, 221, 51)
	cost.TextXAlignment = Enum.TextXAlignment.Right
	cost.Text = ""
	local costStroke = Instance.new("UIStroke")
	costStroke.Color = Color3.fromRGB(25, 20, 35)
	costStroke.Thickness = 3
	costStroke.Parent = cost
	cost.Parent = btn
	btn.Parent = row
	row.Parent = bb
	return row
end

local function RefreshUpgradePrompt(stall, spotIndex, record)
	record = record or stall.Stored[spotIndex]
	if not record then return end -- empty podium: no billboard, nothing to refresh
	local row = EnsureUpgradeRow(stall, spotIndex, record)
	if not row then return end
	local btn = row:FindFirstChild("UpgradeButton")
	local text = btn and btn:FindFirstChild("UpgradeText")
	local icon = btn and btn:FindFirstChild("CukeIcon")
	local cost = btn and btn:FindFirstChild("CostLabel")
	if not (btn and text and icon and cost) then return end
	local level = record.Level or 1
	if level >= MAX_LEVEL then
		text.Text = "MAX LEVEL"
		text.Size = UDim2.fromScale(0.9, 0.82)
		text.TextXAlignment = Enum.TextXAlignment.Center
		btn.BackgroundColor3 = Color3.fromRGB(150, 150, 150)
		icon.Visible = false
		cost.Visible = false
	else
		text.Text = "UPGRADE"
		text.Size = UDim2.fromScale(0.5, 0.82)
		text.TextXAlignment = Enum.TextXAlignment.Left
		btn.BackgroundColor3 = Color3.fromRGB(88, 199, 88)
		icon.Visible = true
		cost.Visible = true
		cost.Text = Abbrev(UpgradeCostFor(record))
	end
	--.. ALWAYS visible on an occupied podium (2026-08-27, user report: rows
	--.. vanished for whole sessions). The old hide-while-carrying rule was
	--.. inherited from the R-prompt era (it conflicted with the podium's
	--.. Replace prompt); the overhead pill conflicts with nothing, and pet
	--.. auto-farm carries proc silently -- hiding on carry read as broken.
	row.Visible = true
end

--.. floating "Collect / $N" label on a spot's money pad
local function EnsurePadLabel(stall, spotIndex)
	local pad = stall.CollectPads and stall.CollectPads[spotIndex]
	if not pad then return nil end
	local gui = pad:FindFirstChild("CollectLabel")
	if not gui then
		gui = Instance.new("BillboardGui")
		gui.Name = "CollectLabel"
		gui.Adornee = pad
		gui.Size = UDim2.new(0, 180, 0, 110) -- 1.5x bigger 2026-08-27 + 29px offline line (81 before the line)
		gui.StudsOffsetWorldSpace = Vector3.new(0, 2.4, 0) -- +0.3 lift 2026-08-27 (user)
		gui.MaxDistance = 70
		gui.LightInfluence = 0
		local layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Vertical
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		--.. centered; the offline line keeps its slot RESERVED at all times
		--.. (always Visible, empty text when zero) so its appearance never
		--.. pushes Collect/amount down (user call 2026-08-27)
		layout.VerticalAlignment = Enum.VerticalAlignment.Center
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = gui
		--.. gray "(Offline Cash: N)" line above Collect (2026-08-27, user;
		--.. SaB reference): 1.25x smaller than the amount line. Stays Visible
		--.. with empty text while nothing is banked -- an invisible label
		--.. would be skipped by the UIListLayout and shift the stack
		local off = Instance.new("TextLabel")
		off.Name = "OfflineLine"
		off.Size = UDim2.new(1, 0, 0, 29) -- 15% smaller 2026-08-27 (was 34)
		off.BackgroundTransparency = 1
		off.Font = Enum.Font.FredokaOne
		off.TextScaled = true
		off.RichText = true -- gray prefix + gold amount via <font color>
		off.TextColor3 = Color3.fromRGB(185, 185, 190)
		off.Text = ""
		off.Visible = true -- reserved slot: see the layout note above
		off.LayoutOrder = 0
		local offStroke = Instance.new("UIStroke")
		offStroke.Color = Color3.fromRGB(40, 40, 46)
		offStroke.Thickness = 3
		offStroke.Parent = off
		off.Parent = gui
		local title = Instance.new("TextLabel")
		title.Name = "Title"
		title.Size = UDim2.new(1, 0, 0, 36) -- 1.5x (was 24)
		title.BackgroundTransparency = 1
		title.Font = Enum.Font.FredokaOne
		title.TextScaled = true
		title.TextColor3 = Color3.fromRGB(255, 255, 255)
		--.. real UIStroke thickness 3, contextual dark (matches the card
		--.. lines' stroke treatment) -- replaced the legacy TextStroke props
		local titleStroke = Instance.new("UIStroke")
		titleStroke.Color = Color3.fromRGB(25, 20, 35)
		titleStroke.Thickness = 3
		titleStroke.Parent = title
		title.Text = "Collect"
		title.LayoutOrder = 1
		title.Parent = gui
		--.. amount = COIN ICON + gold text (2026-08-27, user: wallet coin
		--.. symbol instead of "$", green -> gold). Same "CoinLine" structure
		--.. as the card money lines so the stall zoom scales it.
		local amountRow = Instance.new("Frame")
		amountRow.Name = "CoinLine"
		amountRow.Size = UDim2.new(1, 0, 0, 42) -- 1.5x (was 28)
		amountRow.BackgroundTransparency = 1
		amountRow.LayoutOrder = 2
		local inner = Instance.new("Frame")
		inner.Name = "Inner"
		inner.BackgroundTransparency = 1
		inner.AnchorPoint = Vector2.new(0.5, 0.5)
		inner.Position = UDim2.new(0.5, 0, 0.5, 0)
		inner.AutomaticSize = Enum.AutomaticSize.XY
		local lay = Instance.new("UIListLayout")
		lay.FillDirection = Enum.FillDirection.Horizontal
		lay.VerticalAlignment = Enum.VerticalAlignment.Center
		lay.SortOrder = Enum.SortOrder.LayoutOrder
		lay.Padding = UDim.new(0, 3)
		lay.Parent = inner
		local coin = Instance.new("ImageLabel")
		coin.Name = "CoinIcon"
		coin.BackgroundTransparency = 1
		coin.Size = UDim2.new(0, 36, 0, 36)
		coin.Image = "rbxassetid://15402839520" -- the HUD wallet's coin
		coin.LayoutOrder = 1
		coin.Parent = inner
		local amount = Instance.new("TextLabel")
		amount.Name = "Amount"
		amount.BackgroundTransparency = 1
		amount.AutomaticSize = Enum.AutomaticSize.X
		amount.Size = UDim2.new(0, 0, 0, 42)
		amount.Font = Enum.Font.FredokaOne
		amount.TextScaled = true
		amount.TextColor3 = Color3.fromRGB(255, 221, 51)
		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(82, 62, 10)
		stroke.Thickness = 3
		stroke.Parent = amount
		amount.Text = "0"
		amount.LayoutOrder = 2
		amount.Parent = inner
		inner.Parent = amountRow
		amountRow.Parent = gui
		gui.Parent = pad
	end
	return gui
end

local function UpdatePadLabel(stall, spotIndex, record)
	local gui = EnsurePadLabel(stall, spotIndex)
	local amount = gui and gui:FindFirstChild("Amount", true) -- nested in the CoinLine row
	if amount then
		--.. the big number is the TOTAL payout (accrued + offline), SaB-style
		amount.Text = Abbrev((record.Accrued or 0) + (record.OfflineCash or 0))
	end
	local off = gui and gui:FindFirstChild("OfflineLine")
	if off then
		local oc = math.floor(record.OfflineCash or 0)
		--.. text-only toggle: the label keeps its layout slot either way so
		--.. the Collect/amount lines never move
		off.Text = oc >= 1 and ("Offline Coins: <font color=\"#FFDD33\">$%s</font>"):format(Abbrev(oc)) or ""
	end
end

local function RemovePadLabel(stall, spotIndex)
	local pad = stall.CollectPads and stall.CollectPads[spotIndex]
	local gui = pad and pad:FindFirstChild("CollectLabel")
	if gui then gui:Destroy() end
end

--.. ===== PERSISTENCE (2026-08-26) =====
--.. Stored cucumbers finally SAVE. Every mutation of a stall's contents
--.. rewrites the owner's profile field Data.VaultCucumbers -- GetUserData
--.. returns the LIVE profile table, so this is a cheap in-memory write and
--.. ProfileService owns the actual DataStore cadence. The 1s accrual tick
--.. refreshes it too, so pad money rides along and no fragile
--.. save-on-leave hook is needed (ReleaseStall can wipe session state
--.. freely; the profile copy is already current).
local function SaveVault(stall)
	local plr = stall.Owner
	if not plr then return end
	--.. HARD GATE (2026-08-26, after live data loss): never write the profile
	--.. until LoadVault has finished for this owner. An owned-but-not-yet-
	--.. restored stall has an empty Stored table, and the 1s accrual tick was
	--.. saving that emptiness straight over the player's real VaultCucumbers.
	if not stall.VaultLoaded then return end
	pcall(function()
		local data = require(ServerStorage.ServerController.ProfileService).GetUserData(plr)
		if type(data) ~= "table" then return end
		local list = {}
		for spot, rec in pairs(stall.Stored) do
			table.insert(list, {
				Spot = spot; Zone = rec.Zone; Name = rec.Name;
				Rate = rec.Rate; Level = rec.Level or 1; Rarity = rec.Rarity;
				Mutation = rec.Mutation; Accrued = math.floor(rec.Accrued or 0); HeatT = math.floor(rec.HeatT or 0);
				OfflineCash = math.floor(rec.OfflineCash or 0);
			})
		end
		--.. entries that failed to restore this session ride along verbatim --
		--.. the profile never forgets a cucumber we couldn't rebuild
		for _, e in ipairs(stall.UnrestoredVault or {}) do
			table.insert(list, e)
		end
		data.VaultCucumbers = list
		--.. offline-coins stamp (2026-08-27): LoadVault measures time-away
		--.. from THIS field -- OfflineService's LastSeen resets on join
		--.. before the vault restore runs, so it can't be trusted here
		data.VaultLastSave = os.time()
	end)
end

--.. a model leaving its podium (take-back / replace / steal) must shed its
--.. podium-only attachments -- the card and prompts must not ride along on
--.. someone's arm
local function StripPodiumAttachments(model)
	local primary = model and model.PrimaryPart
	if not primary then return end
	for _, name in ipairs({"EarnBillboard", "StealPrompt", "UpgradePrompt", "LootShimmer"}) do
		local obj = primary:FindFirstChild(name)
		if obj then obj:Destroy() end
	end
	--.. undo DisplayOn's 1.25x podium scale-up so the arm carry (take-back /
	--.. replace / steal) is back at its original carry size
	local baseScale = model:GetAttribute("VaultBaseScale")
	if baseScale then
		pcall(function() model:ScaleTo(baseScale) end)
	end
end

local function SetLasers(stall, on)
	if not stall.Lasers then return end
	for _, l in ipairs(stall.Lasers:GetChildren()) do
		if l:IsA("BasePart") then
			l.Transparency = on and 0.05 or 1
		end
	end
	--.. SFX pass: armed hum -- a looped buzz lives on Laser2 exactly while
	--.. the lasers are up. Lazily created here (SetLasers runs on every
	--.. security refresh), so it self-heals after bank rebuilds.
	pcall(function()
		local l2 = stall.Lasers:FindFirstChild("Laser2")
		if not l2 then return end
		local buzz = l2:FindFirstChild("LaserBuzz")
		if on and not buzz then
			local template = ReplicatedStorage.Assets.Sounds:FindFirstChild("Electric Buzz")
			if template then
				buzz = template:Clone()
				buzz.Name = "LaserBuzz"
				buzz.Looped = true
				buzz.Volume = 0.2
				buzz.PlaybackSpeed = 1
				buzz.RollOffMinDistance = 8
				buzz.RollOffMaxDistance = 35
				buzz.Parent = l2
				buzz:Play()
			end
		elseif not on and buzz then
			buzz:Destroy()
		end
	end)
end

local function Capacity(stall)
	return stall.Spots and #stall.Spots or 0
end

local function StoredCount(stall)
	local n = 0
	for _ in pairs(stall.Stored) do n += 1 end
	return n
end

--.. ===== VAULT SECURITY (2026-08-26) =====

--.. a stall counts as SECURED while its lever timer runs; no owner = no
--.. lasers and nothing worth stealing either way
local function IsSecured(stall)
	return stall.Owner ~= nil and os.clock() < (stall.SecureUntil or 0)
end

local function FormatClock(sec)
	return ("%d:%02d"):format(math.floor(sec / 60), math.floor(sec % 60))
end

--.. ===== SFX pass: laser arm/disarm theatrics + spinning beacons =====

local function LaserParts(stall)
	local parts = {}
	if stall.Lasers and stall.Lasers.Parent then
		for i = 1, 4 do
			local p = stall.Lasers:FindFirstChild("Laser" .. i)
			if p and p:IsA("BasePart") then parts[#parts + 1] = p end
		end
	end
	return parts
end

--.. bottom-to-top power-up flicker + per-laser zap blip (lever pull).
--.. SetLasers stays the state authority: the sequence ends by re-asserting
--.. the real lock state, so mid-sequence rebuilds/expiries can't strand it.
local function ArmLasersSequence(stall)
	pcall(function()
		local parts = LaserParts(stall)
		if #parts == 0 then return end
		for _, p in ipairs(parts) do p.Transparency = 1 end
		for i, p in ipairs(parts) do
			task.delay((i - 1) * 0.1, function()
				if not p.Parent then return end
				p.Transparency = 0.05
				PlaySound3D("Zap", p, {Volume = 0.3, Speed = 1 + i * 0.15, RollOff = 45}, 0.4)
				task.delay(0.05, function() if p.Parent then p.Transparency = 0.5 end end)
				task.delay(0.1, function() if p.Parent then p.Transparency = 0.05 end end)
			end)
		end
		task.delay(0.55, function() SetLasers(stall, IsSecured(stall)) end)
	end)
end

--.. top-to-bottom power-down flicker (lock expiry) -- the arm sequence mirrored
local function DisarmLasersSequence(stall)
	pcall(function()
		local parts = LaserParts(stall)
		if #parts == 0 then return end
		for _, p in ipairs(parts) do p.Transparency = 0.05 end
		for k = 1, #parts do
			local p = parts[#parts - k + 1]
			task.delay((k - 1) * 0.1, function()
				if not p.Parent then return end
				p.Transparency = 0.5
				task.delay(0.05, function() if p.Parent then p.Transparency = 0.05 end end)
				task.delay(0.1, function() if p.Parent then p.Transparency = 1 end end)
			end)
		end
		task.delay(0.55, function() SetLasers(stall, IsSecured(stall)) end)
	end)
end

--.. red spinning siren bar + light. The spin is a repeating linear 180-degree
--.. CFrame tween (no Heartbeat connection); the bar is symmetric, so the loop
--.. seam is invisible. Caller owns the part's lifetime.
local function MakeBeacon(name, atPart, offsetY, parent)
	local beacon = Instance.new("Part")
	beacon.Name = name
	beacon.Size = Vector3.new(1.1, 0.28, 0.28)
	beacon.Color = Color3.fromRGB(255, 40, 40)
	beacon.Material = Enum.Material.Neon
	beacon.Anchored = true
	beacon.CanCollide = false
	beacon.CanQuery = false
	beacon.CanTouch = false
	beacon.CastShadow = false
	local base = CFrame.new(atPart.Position + Vector3.new(0, offsetY, 0))
	beacon.CFrame = base
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 60, 60)
	light.Brightness = 2
	light.Range = 14
	light.Parent = beacon
	beacon.Parent = parent
	TweenService:Create(beacon,
		TweenInfo.new(0.8, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, -1),
		{CFrame = base * CFrame.Angles(0, math.pi, 0)}):Play()
	return beacon
end

--.. a stored cucumber is grabbable exactly while its stall's lock has
--.. lapsed. The prompt's Enabled flag is client-visible convenience ONLY;
--.. VaultService.Steal re-validates everything on the server.
local function RefreshStealPrompt(stall, spotIndex, record)
	local model = record.Model
	local sp = model and model.PrimaryPart and model.PrimaryPart:FindFirstChild("StealPrompt")
	if not sp then return end
	--.. FROZEN cucumbers are theft-proof (2026-08-27): the prompt never arms
	sp.Enabled = stall.Owner ~= nil and not IsSecured(stall) and record.Mutation ~= "FROZEN"
end

--.. countdown card floating over the stall's security lever
local function EnsureLeverGui(stall)
	local hinge = stall.Lever and stall.Lever:FindFirstChild("LeverHinge")
	if not hinge then return nil end
	local gui = hinge:FindFirstChild("LeverTimer")
	if not gui then
		gui = Instance.new("BillboardGui")
		gui.Name = "LeverTimer"
		gui.Adornee = hinge
		gui.Size = UDim2.new(0, 150, 0, 64)
		gui.StudsOffsetWorldSpace = Vector3.new(0, 2.6, 0)
		gui.MaxDistance = 80
		gui.LightInfluence = 0
		gui.Enabled = false
		local layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Vertical
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = gui
		local function line(name, px, order)
			local t = Instance.new("TextLabel")
			t.Name = name
			t.Size = UDim2.new(1, 0, 0, px)
			t.BackgroundTransparency = 1
			t.Font = Enum.Font.FredokaOne
			t.TextScaled = true
			t.TextColor3 = Color3.fromRGB(255, 255, 255)
			t.TextStrokeColor3 = Color3.fromRGB(25, 20, 35)
			t.TextStrokeTransparency = 0.15
			t.LayoutOrder = order
			t.Parent = gui
		end
		line("State", 24, 1)
		line("Clock", 34, 2)
		gui.Parent = hinge
	end
	return gui
end

local LOCKED_GREEN = Color3.fromRGB(110, 220, 110)
local UNLOCKED_RED = Color3.fromRGB(255, 80, 70)

--.. one idempotent pass over everything the lock state touches: lasers,
--.. lever prompt + handle-ball color, the countdown card, and every stored
--.. cucumber's steal prompt. Called on every state change + the 1s tick.
local function RefreshSecurityUI(stall)
	local secured = IsSecured(stall)
	stall.WasSecured = secured
	SetLasers(stall, secured)
	if stall.LeverPrompt then
		stall.LeverPrompt.Enabled = stall.Owner ~= nil
		stall.LeverPrompt.ActionText = secured and "Re-lock Vault" or "LOCK VAULT!"
	end
	local ball = stall.Lever and stall.Lever:FindFirstChild("BallOnHandle")
	if ball then
		ball.Color = secured and LOCKED_GREEN or UNLOCKED_RED
	end
	--.. SFX pass: a red spinning beacon over the lever the whole time the
	--.. stall sits UNLOCKED. Lazily created here (this runs per stall after
	--.. every rebuild + on the 1s tick), destroyed the moment it locks.
	pcall(function()
		local hinge = stall.Lever and stall.Lever:FindFirstChild("LeverHinge")
		if not hinge then return end
		local beacon = stall.Lever:FindFirstChild("UnlockBeacon")
		if stall.Owner and not secured then
			if not beacon then
				MakeBeacon("UnlockBeacon", hinge, 3.6, stall.Lever)
			end
		elseif beacon then
			beacon:Destroy()
		end
	end)
	local gui = EnsureLeverGui(stall)
	if gui then
		local state, clock = gui:FindFirstChild("State"), gui:FindFirstChild("Clock")
		gui.Enabled = stall.Owner ~= nil
		if stall.Owner and state and clock then
			if secured then
				state.Text = "\u{1F512} LOCKED"
				state.TextColor3 = LOCKED_GREEN
				local left = math.max(0, math.floor((stall.SecureUntil or 0) - os.clock() + 0.5))
				clock.Text = FormatClock(left)
				clock.TextColor3 = left <= 30 and Color3.fromRGB(255, 200, 60) or Color3.fromRGB(255, 255, 255)
			else
				state.Text = "\u{1F513} UNLOCKED!"
				state.TextColor3 = UNLOCKED_RED
				clock.Text = "PULL LEVER!"
				clock.TextColor3 = UNLOCKED_RED
			end
		end
	end
	for idx, rec in pairs(stall.Stored) do
		RefreshStealPrompt(stall, idx, rec)
	end
end

--.. per-podium prompt titles track state: empty = Store Cucumber; occupied =
--.. Take Back, or Replace while the OWNER is carrying. Prompts are shared
--.. instances, so titles follow the owner's hands -- other players see the
--.. same text but are refused on trigger.
local function RefreshPrompts(stall)
	if not stall.PodiumPrompts then return end
	local carrying = false
	if stall.Owner then
		local CarryService = ServerController.GetModule("CarryService")
		carrying = CarryService.Get(stall.Owner) ~= nil
	end
	for idx, prompt in pairs(stall.PodiumPrompts) do
		local rec = stall.Stored[idx]
		if rec then
			prompt.ActionText = carrying and "Replace" or "Take Back"
			prompt.ObjectText = rec.Name
		else
			prompt.ActionText = "Store Cucumber"
			prompt.ObjectText = "Podium"
		end
	end
	--.. every occupied podium's card row: carry-state + cost stay fresh
	for idx, rec in pairs(stall.Stored) do
		RefreshUpgradePrompt(stall, idx, rec)
	end
end

local function RefreshSign(stall)
	local gui = stall.Sign and stall.Sign:FindFirstChild("SignGui")
	local label = gui and gui:FindFirstChild("Label")
	if not label then return end
	if stall.Owner then
		label.Text = string.upper(stall.Owner.DisplayName) .. "'S VAULT (" .. StoredCount(stall) .. "/" .. Capacity(stall) .. ")"
	else
		label.Text = "EMPTY"
	end
end

--.. place a carry record's model on a pedestal spot (idempotent: safe to
--.. call again after a rebuild -- old billboard/prompt are replaced)
local function DisplayOn(stall, spotIndex, record)
	local model = record.Model
	local spot = stall.Spots[spotIndex]
	if not spot then return end
	for _, obj in ipairs(model:GetDescendants()) do
		if obj:IsA("BasePart") then obj.Anchored = true end
	end
	--.. podium display renders 1.25x bigger than the arm carry (2026-08-27,
	--.. user). Scale from a remembered base so repeat DisplayOn calls never
	--.. compound; StripPodiumAttachments restores the base scale whenever
	--.. the model leaves its podium (take-back / replace / steal). Must run
	--.. BEFORE the bounding-box placement + card offset math below.
	local baseScale = model:GetAttribute("VaultBaseScale")
	if not baseScale then
		baseScale = model:GetScale()
		model:SetAttribute("VaultBaseScale", baseScale)
	end
	pcall(function() model:ScaleTo(baseScale * 1.25) end)
	--.. face the stall DOOR (2026-08-27, user: sliced cucumbers showed their
	--.. backs): identity rotation pointed every model the same world way --
	--.. into the back wall on the north row. North-row stalls (ids 1..6 in
	--.. BankBuilder.ROWS) need a 180 yaw; the south row already faces its
	--.. door. Rotate BEFORE the bounding-box pass so the centering delta is
	--.. measured in the final pose.
	local doorRot = CFrame.Angles(0, stall.Id <= 6 and math.pi or 0, 0)
	model:PivotTo(CFrame.new(spot.Position) * doorRot)
	local bboxCF, ext = model:GetBoundingBox()
	local delta = model:GetPivot().Position - bboxCF.Position
	model:PivotTo(CFrame.new(spot.Position + delta + Vector3.new(0, ext.Y / 2, 0)) * doorRot)
	model.Parent = stall.StoredFolder

	local primary = model.PrimaryPart
	if not primary then return end
	local oldGui = primary:FindFirstChild("EarnBillboard")
	if oldGui then oldGui:Destroy() end
	local oldPrompt = primary:FindFirstChild("TakeBackPrompt")
	if oldPrompt then oldPrompt:Destroy() end

	--.. overhead card: name + coins/s (+ mutation line, raised, when mutated)
	local mutated = record.Mutation ~= nil
	local gui = Instance.new("BillboardGui")
	gui.Name = "EarnBillboard"
	gui.Adornee = primary
	--.. heights = exact sum of the line px + the 36px UpgradeRow (2026-08-27)
	gui.Size = UDim2.new(0, 180, 0, mutated and 142 or 118)
	--.. keep the card clear of the storey ceiling (2026-08-27, user):
	--.. every storey has a uniform 13 studs of headroom above its walking
	--.. surface (BankBuilder FLOOR_H 14 minus the 1-thick slab); the surface
	--.. sits 3.2 under the spot (podium h 3.0 + 0.2 spot lift). Cap the
	--.. card's anchor 1.5 below the ceiling: short cucumbers keep the full
	--.. raise, tall ones pull down just enough. Clamping the real property
	--.. keeps VaultFXClient's pill screen-rect hit test in sync for free.
	local cardCeiling = (spot.Position.Y - 3.2) + 13
	--.. anchor a FIXED gap above the model's TOP, not ext above the primary
	--.. (2026-08-27, user: cards sat too close to some cucumbers and too far
	--.. from others -- PrimaryParts sit at different relative heights per
	--.. model, so a primary-based offset drifts by up to a stud either way).
	--.. The placement above seats the bbox bottom on the spot, so model top
	--.. = spot.Y + ext.Y exactly.
	local modelTop = spot.Position.Y + ext.Y
	local cardOffY = math.min(
		(modelTop + (mutated and 3.4 or 3.0)) - primary.Position.Y, -- +0.5 2026-08-27 (was 2.9/2.5)
		cardCeiling - 1.5 - primary.Position.Y)
	gui.StudsOffsetWorldSpace = Vector3.new(0, cardOffY, 0)
	--.. the card is OFFSET-sized (fixed px on screen), so from far away its
	--.. top half spans more world-studs than any anchor margin can reserve --
	--.. the roof then occludes it (user report 2026-08-27, twice). The fix is
	--.. AlwaysOnTop -- but only while the VIEWER is in the vault on this
	--.. card's storey (user call), which is per-viewer state: VaultTextClient
	--.. flips the property locally (local writes never replicate). Server
	--.. default stays false so anyone outside the vault gets normal occlusion.
	gui.AlwaysOnTop = false
	gui.MaxDistance = 55
	gui.LightInfluence = 0
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = gui
	--.. real UIStroke per line, thickness 3, color CONTEXTUAL to that line's
	--.. text color (2026-08-27, user) -- replaced the old thin TextStroke
	local function line(text, color, px, order, strokeColor)
		local t = Instance.new("TextLabel")
		t.Size = UDim2.new(1, 0, 0, px)
		t.BackgroundTransparency = 1
		t.Font = Enum.Font.FredokaOne
		t.TextScaled = true
		t.TextColor3 = color
		t.Text = text
		t.LayoutOrder = order
		local stroke = Instance.new("UIStroke")
		stroke.Color = strokeColor or Color3.fromRGB(25, 20, 35)
		stroke.Thickness = 3
		stroke.Parent = t
		t.Parent = gui
		return t
	end
	--.. money lines = COIN ICON + gold text (2026-08-27, user: "$" replaced
	--.. by the wallet's coin symbol, green -> gold). The icon can't live
	--.. inside a TextLabel, so each money line is a row Frame holding an
	--.. auto-centered [icon + auto-width TextScaled label] pair. Named
	--.. "CoinLine" -- VaultTextClient's stall zoom scales these rows and
	--.. their contents alongside the plain text lines.
	--.. darker = the value line's deeper gold (user 2026-08-27; rate line
	--.. keeps the bright gold)
	local function coinLine(text, px, order, darker)
		local row = Instance.new("Frame")
		row.Name = "CoinLine"
		row.Size = UDim2.new(1, 0, 0, px)
		row.BackgroundTransparency = 1
		row.LayoutOrder = order
		local inner = Instance.new("Frame")
		inner.Name = "Inner"
		inner.BackgroundTransparency = 1
		inner.AnchorPoint = Vector2.new(0.5, 0.5)
		inner.Position = UDim2.new(0.5, 0, 0.5, 0)
		inner.AutomaticSize = Enum.AutomaticSize.XY
		local lay = Instance.new("UIListLayout")
		lay.FillDirection = Enum.FillDirection.Horizontal
		lay.VerticalAlignment = Enum.VerticalAlignment.Center
		lay.SortOrder = Enum.SortOrder.LayoutOrder
		lay.Padding = UDim.new(0, 0) -- was 3: the coin art has baked-in margins, text hugs closer (user 2026-08-27)
		lay.Parent = inner
		local icon = Instance.new("ImageLabel")
		icon.Name = "CoinIcon"
		icon.BackgroundTransparency = 1
		icon.Size = UDim2.new(0, px - 6, 0, px - 6)
		icon.Image = COIN_ICON
		icon.LayoutOrder = 1
		icon.Parent = inner
		local t = Instance.new("TextLabel")
		t.Name = "Money"
		t.BackgroundTransparency = 1
		t.AutomaticSize = Enum.AutomaticSize.X
		t.Size = UDim2.new(0, 0, 0, px)
		t.Font = Enum.Font.FredokaOne
		t.TextScaled = true
		t.TextColor3 = darker and Color3.fromRGB(224, 164, 32) or Color3.fromRGB(255, 221, 51)
		t.Text = text
		t.LayoutOrder = 2
		local stroke = Instance.new("UIStroke")
		stroke.Color = darker and Color3.fromRGB(64, 45, 6) or Color3.fromRGB(82, 62, 10)
		stroke.Thickness = 3
		stroke.Parent = t
		t.Parent = inner
		inner.Parent = row
		row.Parent = gui
	end
	--.. Steal-a-Brainrot card order: [X] name (white, [MAX] at the level
	--.. cap) / mutation (in the rarity slot, only when present) /
	--.. coins-per-second / value (both gold coin lines)
	local cardLevel = record.Level or 1
	--.. a maxed cucumber's title is RAINBOW (2026-08-27, user; was gold for
	--.. an hour): a STATIC UIGradient over white text -- deliberately no
	--.. per-frame color animation, zero runtime cost
	local isMax = cardLevel >= MAX_LEVEL
	local title = line(("[%s] %s"):format(isMax and "MAX" or tostring(cardLevel), string.upper(record.Name)),
		Color3.fromRGB(255, 255, 255), 30, 1)
	if isMax then
		local rainbow = Instance.new("UIGradient")
		rainbow.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0.00, Color3.fromRGB(255, 70, 70)),
			ColorSequenceKeypoint.new(0.18, Color3.fromRGB(255, 160, 40)),
			ColorSequenceKeypoint.new(0.35, Color3.fromRGB(255, 230, 60)),
			ColorSequenceKeypoint.new(0.52, Color3.fromRGB(90, 235, 90)),
			ColorSequenceKeypoint.new(0.70, Color3.fromRGB(70, 190, 255)),
			ColorSequenceKeypoint.new(0.85, Color3.fromRGB(150, 110, 255)),
			ColorSequenceKeypoint.new(1.00, Color3.fromRGB(255, 110, 230)),
		})
		rainbow.Parent = title
	end
	if mutated then
		line(string.upper(record.Mutation), Color3.fromRGB(255, 90, 220), 24, 2, Color3.fromRGB(75, 15, 65))
	end
	coinLine(RateText(EffRate(record)) .. "/s", 26, 3)
	coinLine(Abbrev(ValueOf(record)), 26, 4, true) -- value = darker gold
	gui.Parent = primary
	UpdatePadLabel(stall, spotIndex, record)

	--.. upgrade UI (2026-08-26): the pedestal's clickable UPGRADE sign
	--.. replaced the old R-prompt; strip any legacy prompt off restored models
	local oldUp = primary:FindFirstChild("UpgradePrompt")
	if oldUp then oldUp:Destroy() end
	RefreshUpgradePrompt(stall, spotIndex, record)

	--.. steal prompt (2026-08-26): hold F to grab this cucumber off its
	--.. podium -- armed only while the stall's lever timer has lapsed
	local oldSteal = primary:FindFirstChild("StealPrompt")
	if oldSteal then oldSteal:Destroy() end
	local sp = Instance.new("ProximityPrompt")
	sp.Name = "StealPrompt"
	sp.KeyboardKeyCode = Enum.KeyCode.F
	sp.ActionText = "STEAL"
	sp.ObjectText = record.Name
	sp.HoldDuration = 2.5
	sp.MaxActivationDistance = 8
	sp.RequiresLineOfSight = false
	sp.Enabled = false
	sp.Parent = primary
	sp.Triggered:Connect(function(plr)
		VaultService.Steal(plr, stall, spotIndex)
	end)
	RefreshStealPrompt(stall, spotIndex, record)

	--.. SFX pass: hot loot (Lv15+ or mutated) sparkles on its podium so
	--.. thieves can spot it by eye. "LootShimmer" is in the
	--.. StripPodiumAttachments name list, so it never rides along on a
	--.. take-back/steal.
	pcall(function()
		local oldShimmer = primary:FindFirstChild("LootShimmer")
		if oldShimmer then oldShimmer:Destroy() end
		if (record.Level or 1) >= 15 or record.Mutation then
			local pe = Instance.new("ParticleEmitter")
			pe.Name = "LootShimmer"
			pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
			pe.Color = ColorSequence.new(Color3.fromRGB(255, 220, 90))
			pe.LightEmission = 0.8
			pe.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0)})
			pe.Lifetime = NumberRange.new(0.6, 1.1)
			pe.Rate = 6
			pe.Speed = NumberRange.new(0.4, 1)
			pe.SpreadAngle = Vector2.new(180, 180)
			pe.Parent = primary
		end
	end)
end

--.. Rebuild a rejoining owner's saved cucumbers onto their podiums. Waits
--.. for the profile (PlayerData appears once it loads), then resolves each
--.. entry's live type def (BreakablesService.FindType) and builds a fresh
--.. display model from its template (CarryService.BuildFromTemplate).
--.. Golden tint / mutation looks are re-applied onto the clean build via
--.. BreakablesService.ApplyStoredLook (2026-08-28 -- they used to be lost,
--.. leaving plain bodies under mutated cards; only the shimmer survived).
local function LoadVault(plr, stall)
	task.spawn(function()
		if not plr:WaitForChild("PlayerData", 60) then return end
		if StallOf[plr] ~= stall or stall.Owner ~= plr then return end
		local ok, list = pcall(function()
			local data = require(ServerStorage.ServerController.ProfileService).GetUserData(plr)
			return type(data) == "table" and data.VaultCucumbers or nil
		end)
		if not ok then
			--.. profile unreadable: keep saves DISABLED for this whole session
			--.. so the on-record data survives untouched for the next one
			warn("[VaultService] LoadVault could not read the profile for", plr.Name, "- vault saving stays off")
			return
		end
		if type(list) ~= "table" or #list == 0 then
			--.. nothing to restore (new player / empty vault): saving may begin
			stall.VaultLoaded = true
			return
		end
		local BreakablesService = ServerController.GetModule("BreakablesService")
		local CarryService = ServerController.GetModule("CarryService")
		--.. OFFLINE COINS (2026-08-27, user): mirror of OfflineService's cukes
		--.. tiers -- 50% of the rate for the first 6h away, then 30% until 6
		--.. full-rate hours are banked (counted absence caps at 16h = 57600s).
		--.. Time-away comes from Data.VaultLastSave (stamped by SaveVault's
		--.. ~1s cadence). Each restored cucumber banks EffRate x equivalent
		--.. seconds into rec.OfflineCash, shown gray on its pad and granted
		--.. with the next Collect.
		local offlineEquivSeconds = 0
		pcall(function()
			local data = require(ServerStorage.ServerController.ProfileService).GetUserData(plr)
			local last = type(data) == "table" and tonumber(data.VaultLastSave) or nil
			if last and last > 0 then
				local away = math.clamp(os.time() - last, 0, 57600)
				if away >= 120 then -- ignore quick rejoins, same as OfflineService
					local firstTier = math.min(away, 6 * 3600)
					local secondTier = math.max(0, away - 6 * 3600)
					offlineEquivSeconds = firstTier * 0.5 + secondTier * 0.3
				end
			end
		end)
		local restored = 0
		local leftover = {}
		for _, e in ipairs(list) do
			local placed = false
			if type(e) == "table" and e.Zone and e.Name then
				local okT, typeDef = pcall(BreakablesService.FindType, e.Zone, e.Name)
				if not (okT and typeDef) then
					--.. saved names can carry modifier prefixes ("Golden Cucumber");
					--.. the type registry only knows base names -- strip and retry
					local base = tostring(e.Name)
					base = base:gsub("^%s*[Gg][Oo][Ll][Dd][Ee][Nn]%s+", "")
					base = base:gsub("^%s*[Cc][Hh][Aa][Rr][Gg][Ee][Dd]%s+", "")
					base = base:gsub("^%s*[Dd][Ii][Aa][Mm][Oo][Nn][Dd]%s+", "")
					if base ~= e.Name then
						okT, typeDef = pcall(BreakablesService.FindType, e.Zone, base)
					end
				end
				--.. pcall'd: ONE unbuildable entry must not kill the whole restore
				local okB, model = pcall(function()
					return (okT and typeDef) and CarryService.BuildFromTemplate(typeDef) or nil
				end)
				if okB and model then
					--.. re-skin the clean template build: golden/diamond name
					--.. prefixes + the saved Mutation recolor (2026-08-28 fix --
					--.. mutations used to show only as the card + shimmer here)
					pcall(BreakablesService.ApplyStoredLook, model, e.Name, e.Mutation)
					local spot = tonumber(e.Spot)
					if not spot or spot ~= math.floor(spot) or stall.Stored[spot] then
						spot = nil
						for i = 1, 64 do
							if stall.Stored[i] == nil then spot = i break end
						end
					end
					if spot then
						local rec = {
							Model = model; Zone = e.Zone; TypeDef = typeDef; Name = e.Name;
							Rarity = tonumber(e.Rarity); Mutation = e.Mutation;
							Rate = tonumber(e.Rate) or 1;
							Level = math.clamp(tonumber(e.Level) or 1, 1, MAX_LEVEL);
							Accrued = math.max(0, tonumber(e.Accrued) or 0);
			HeatT = math.clamp(tonumber(e.HeatT) or 0, 0, 3600);
							OfflineCash = math.max(0, tonumber(e.OfflineCash) or 0);
						}
						--.. uncollected offline cash carries over AND this
						--.. absence's earnings stack on top
						rec.OfflineCash += EffRate(rec) * offlineEquivSeconds
						stall.Stored[spot] = rec
						--.. no-ops when the spot outruns current capacity (rebirths
						--.. still loading) -- the rebirth relayout re-displays all
						DisplayOn(stall, spot, rec)
						restored += 1
						placed = true
					else
						model:Destroy()
					end
				end
			end
			if not placed and type(e) == "table" then
				--.. couldn't rebuild or place it this session: carry the record
				--.. forward untouched (SaveVault appends these) so it is NEVER
				--.. dropped from the profile
				table.insert(leftover, e)
			end
		end
		stall.UnrestoredVault = leftover
		if #leftover > 0 then
			warn(("[VaultService] %d vault cucumber(s) could not be restored for %s - carried forward in the profile"):format(#leftover, plr.Name))
		end
		--.. restore finished: Stored + leftovers now represent the full truth,
		--.. so profile writes may begin
		stall.VaultLoaded = true
		if restored > 0 then
			RefreshSign(stall)
			RefreshPrompts(stall)
			RefreshSecurityUI(stall)
			SaveVault(stall) -- normalize spots after any fallback placement
			--.. SFX pass: a soft restore chime for the owner
			FireVaultFX(plr, {Kind = "Restored", Count = restored})
		end
	end)
end

local function OnDoorTouched(stall, hit)
	local char = hit:FindFirstAncestorOfClass("Model")
	local plr = char and Players:GetPlayerFromCharacter(char)
	if not plr then return end
	if stall.Owner == nil or stall.Owner == plr then return end
	if not IsSecured(stall) then return end -- lock lapsed: the door is open to anyone
	local now = os.clock()
	if now - (LastPush[plr] or 0) < PUSH_DEBOUNCE then return end
	LastPush[plr] = now
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if hrp then
		hrp.CFrame = CFrame.new(stall.Zone.Position + stall.Outward * 6 + Vector3.new(0, 1.5, 0))
			* CFrame.Angles(0, math.atan2(stall.Outward.X, stall.Outward.Z), 0)
		Notify(plr, "\u{26D4} NOT YOUR VAULT!")
		--.. SFX pass: a loud shared zap at the door, a white flare on the
		--.. laser bars, and the bounced player's personal sting/vignette/jolt
		PlaySound3D("Zap", stall.Zone, {Volume = 0.6, RollOff = 50}, 0.6)
		FireVaultFX(plr, {Kind = "Zapped"})
		pcall(function()
			local parts = LaserParts(stall)
			for _, p in ipairs(parts) do
				if not p:GetAttribute("VS_BaseColor") then
					p:SetAttribute("VS_BaseColor", p.Color)
				end
				p.Color = Color3.fromRGB(255, 255, 255)
			end
			task.delay(0.1, function()
				for _, p in ipairs(parts) do
					if p.Parent then
						p.Color = p:GetAttribute("VS_BaseColor") or Color3.fromRGB(255, 65, 55)
					end
				end
			end)
		end)
	end
end

--.. wire one stall record to its freshly built instances
local function Rebind(stall)
	local bank = workspace:FindFirstChild("CucumberBank")
	local stallModel = bank and bank.Stalls:FindFirstChild("Stall_" .. stall.Id)
	if not stallModel then return end
	local floor = stallModel:FindFirstChild("FloorTile")
	local zone = stallModel:FindFirstChild("DoorZone")
	local outward = (zone.Position - floor.Position) * Vector3.new(0, 0, 1)

	local storedFolder = Instance.new("Folder")
	storedFolder.Name = "Stored"
	storedFolder.Parent = stallModel

	local spots = {}
	local collectPads = {}
	local podiumPrompts = {}
	local upgradeSigns = {}
	for _, s in ipairs(stallModel.Pedestals:GetChildren()) do
		local idx = s:GetAttribute("SpotIndex")
		if idx then
			if s.Name:sub(1, 10) == "CollectPad" then
				collectPads[idx] = s
			elseif s.Name:sub(1, 11) == "UpgradeSign" then
				upgradeSigns[idx] = s
			elseif s.Name:sub(1, 8) == "Pedestal" then
				podiumPrompts[idx] = s:FindFirstChild("PodiumPrompt")
			elseif s.Name:sub(1, 4) == "Spot" then
				spots[idx] = s
			end
		end
	end

	stall.Model = stallModel
	stall.Sign = stallModel.NameSign
	stall.Lasers = stallModel.Lasers
	stall.Zone = zone
	stall.Outward = outward.Magnitude > 0 and outward.Unit or Vector3.new(0, 0, -1)
	stall.Spots = spots
	stall.CollectPads = collectPads
	stall.PodiumPrompts = podiumPrompts
	stall.UpgradeSigns = upgradeSigns
	stall.StoredFolder = storedFolder
	--.. refresh any still-displayed cucumbers' card rows (re-displays after a
	--.. relayout rebuild them anyway; this covers Rebind-without-redisplay)
	for idx, rec in pairs(stall.Stored) do
		RefreshUpgradePrompt(stall, idx, rec)
	end

	--.. security lever: fresh prompt every rebuild; the countdown card is
	--.. (re)created lazily by EnsureLeverGui
	stall.Lever = stallModel:FindFirstChild("VaultLever")
	stall.LeverPrompt = nil
	local leverHinge = stall.Lever and stall.Lever:FindFirstChild("LeverHinge")
	if leverHinge then
		local lp = Instance.new("ProximityPrompt")
		lp.Name = "LeverPrompt"
		lp.ActionText = "Lock Vault"
		lp.ObjectText = "Security Lever"
		lp.HoldDuration = 0.4
		lp.MaxActivationDistance = 8
		lp.RequiresLineOfSight = false
		lp.Enabled = false
		lp.Parent = leverHinge
		lp.Triggered:Connect(function(plr)
			VaultService.PullLever(plr, stall)
		end)
		stall.LeverPrompt = lp
	end

	zone.Touched:Connect(function(hit)
		OnDoorTouched(stall, hit)
	end)
	for idx, prompt in pairs(podiumPrompts) do
		prompt.Triggered:Connect(function(plr)
			VaultService.PodiumAction(plr, stall, idx)
		end)
	end
	for idx, cpad in pairs(collectPads) do
		cpad.Touched:Connect(function(hit)
			VaultService.Collect(stall, idx, hit)
		end)
	end
end

--.. full rebuild: detach stored models, regenerate geometry from levels,
--.. rebind, then restore signs/lasers/displays
local function Relayout()
	local levels = {}
	local extras = {}
	for id, stall in pairs(Stalls) do
		levels[id] = stall.Level or 0
		extras[id] = stall.Extra or 0
		for _, rec in pairs(stall.Stored) do
			if rec.Model then rec.Model.Parent = nil end
		end
	end
	BankBuilder.Build(levels, extras)
	--.. SFX pass: construction rumble at the fresh deck (skipped on empty
	--.. servers) + the bank's ambient machinery hum, re-created every rebuild
	pcall(function()
		if #Players:GetPlayers() > 0 then
			local bank = workspace:FindFirstChild("CucumberBank")
			local slab = bank and (bank.PrimaryPart or bank:FindFirstChild("DeckSlab", true))
			if slab then
				PlaySound3D("Rock Crumble", slab, {Volume = 0.5, RollOff = 150})
			end
		end
	end)
	EnsureBankHum()
	for _, stall in pairs(Stalls) do
		Rebind(stall)
		RefreshSign(stall)
		for spotIndex, rec in pairs(stall.Stored) do
			DisplayOn(stall, spotIndex, rec)
		end
		RefreshPrompts(stall)
		RefreshSecurityUI(stall) -- lasers, lever prompt, countdown card, steal prompts
	end
end

local function ScheduleRelayout()
	if relayoutQueued then return end
	relayoutQueued = true
	task.defer(function()
		relayoutQueued = false
		Relayout()
	end)
end

--.. mirror of WatchRebirths for the "Vault slots" board upgrade: the replicated
--.. PlayerData.Upgrades["Vault slots"] IntValue (created by UpgradeService on
--.. join, bumped on purchase) drives stall.Extra -> capacity/width via
--.. BankBuilder.CapacityFor(level, extra)
local function WatchVaultSlots(plr, stall)
	task.spawn(function()
		local pd = plr:WaitForChild("PlayerData", 15)
		local ups = pd and pd:WaitForChild("Upgrades", 10)
		local v = ups and ups:WaitForChild("Vault slots", 30)
		if not v or StallOf[plr] ~= stall then return end
		local extra = tonumber(v.Value) or 0
		if extra ~= (stall.Extra or 0) then
			stall.Extra = extra
			ScheduleRelayout()
		end
		stall.SlotsConn = v.Changed:Connect(function(nv)
			local newExtra = tonumber(nv) or 0
			if newExtra == (stall.Extra or 0) then return end
			local grew = newExtra > (stall.Extra or 0)
			local floorsBefore = BankBuilder.FloorsFor(BankBuilder.CapacityFor(stall.Level, stall.Extra))
			stall.Extra = newExtra
			ScheduleRelayout()
			if grew then
				local floorsAfter = BankBuilder.FloorsFor(BankBuilder.CapacityFor(stall.Level, newExtra))
				if floorsAfter > floorsBefore then
					FireVaultFX(plr, {Kind = "FloorUnlocked", StallId = stall.Id})
					Notify(plr, ("\u{1F3E6} FLOOR %d UNLOCKED!"):format(floorsAfter), "Success")
				else
					FireVaultFX(plr, {Kind = "VaultGrew"})
					Notify(plr, "\u{1F3E6} +1 VAULT SLOT!", "Success")
				end
			end
		end)
	end)
end

local function WatchRebirths(plr, stall)
	task.spawn(function()
		local ls = plr:WaitForChild("leaderstats", 15)
		local rb = ls and ls:WaitForChild("Rebirths", 10)
		if not rb or StallOf[plr] ~= stall then return end
		local level = tonumber(rb.Value) or 0
		if level ~= stall.Level then
			stall.Level = level
			ScheduleRelayout()
		end
		stall.RebirthConn = rb.Changed:Connect(function(v)
			local newLevel = tonumber(v) or 0
			if newLevel == stall.Level then return end
			local upgraded = newLevel > stall.Level
			local floorsBefore = BankBuilder.FloorsFor(BankBuilder.CapacityFor(stall.Level, stall.Extra))
			stall.Level = newLevel
			ScheduleRelayout()
			if upgraded then
				local floorsAfter = BankBuilder.FloorsFor(BankBuilder.CapacityFor(newLevel, stall.Extra))
				if floorsAfter > floorsBefore then
					--.. SFX pass: new-floor sting + light beam client-side
					FireVaultFX(plr, {Kind = "FloorUnlocked", StallId = stall.Id})
					Notify(plr, ("\u{1F3E6} FLOOR %d UNLOCKED!"):format(floorsAfter), "Success")
				else
					FireVaultFX(plr, {Kind = "VaultGrew"})
					Notify(plr, ("\u{1F3E6} VAULT LEVEL %d! +1 SLOT"):format(newLevel), "Success")
				end
			end
		end)
	end)
end

--.. ===== STEAL COMBAT (2026-08-27, user) =====
--.. A successful grab opens a live heist: the thief lugs the stolen cucumber
--.. at 1.5x slower speed (CarryingStolen attribute, applied in the
--.. Dictionaries.Upgrades walkspeed recompute) and BOTH sides keep their
--.. pickaxes -- even on the vault deck (the StealCombat attribute, holding the
--.. opponent's UserId, exempts VaultPickaxeGuard and BreakablesClient's
--.. no-mining rule). Clicking the opponent fires "StealStrike": every landed
--.. hit knocks the target back, and HitsToReclaim hits BY THE VICTIM return
--.. the cucumber to their podium automatically. The thief wins by banking it
--.. (any other carry end simply closes the heist). One local (chunk budget).
local Heist = {
	Sessions = {};   -- [thief] = {Thief, Victim, Stall, Spot, Hits, CarryConn}
	LastStrike = {}; -- [player] = os.clock() of their last landed strike
	HitsToReclaim = 3;
	StrikeRange = 16;
	StrikeCooldown = 0.7;
}

function Heist.RefreshSpeed(plr)
	task.spawn(function()
		pcall(function()
			ServerController.GetDictionary("Upgrades").SetWalkSpeed(plr)
		end)
	end)
end

function Heist.End(thief)
	local s = Heist.Sessions[thief]
	if not s then return end
	Heist.Sessions[thief] = nil
	if s.CarryConn then s.CarryConn:Disconnect() end
	if thief.Parent then
		thief:SetAttribute("CarryingStolen", nil)
		thief:SetAttribute("StealCombat", nil)
		Heist.RefreshSpeed(thief)
	end
	if s.Victim.Parent then
		s.Victim:SetAttribute("StealCombat", nil)
	end
end

function Heist.Return(thief)
	local s = Heist.Sessions[thief]
	if not s then return end
	local CarryService = ServerController.GetModule("CarryService")
	--.. disconnect BEFORE Take so the carry-end watcher can't double-resolve
	if s.CarryConn then s.CarryConn:Disconnect() s.CarryConn = nil end
	local record = CarryService.Take(thief)
	local stall, victim = s.Stall, s.Victim
	if record and victim.Parent and stall.Owner == victim then
		local spot = (stall.Stored[s.Spot] == nil and stall.Spots and stall.Spots[s.Spot] ~= nil) and s.Spot or nil
		if not spot and stall.Spots then
			for i = 1, #stall.Spots do
				if stall.Stored[i] == nil then spot = i break end
			end
		end
		if spot then
			stall.Stored[spot] = record
			DisplayOn(stall, spot, record)
			RefreshSign(stall)
			RefreshPrompts(stall)
			SaveVault(stall)
			FireVaultFX(victim, {Kind = "Deposit", StallId = stall.Id, Spot = spot})
			Notify(victim, ("\u{1F6E1} YOU WON! %s IS BACK IN YOUR VAULT!"):format(string.upper(record.Name or "CUCUMBER")), "Success")
		elseif CarryService.Restore(victim, record.Model, record) then
			--.. vault somehow full: hand it back onto the owner's arm instead
			Notify(victim, ("\u{1F6E1} YOU WON %s BACK!"):format(string.upper(record.Name or "IT")), "Success")
		elseif record.Model then
			record.Model:Destroy()
		end
		if thief.Parent then Notify(thief, "\u{1F4A5} THEY TOOK IT BACK!") end
	elseif record and record.Model then
		record.Model:Destroy()
	end
	Heist.End(thief)
end

function Heist.Start(thief, victim, stall, spotIndex)
	Heist.End(thief)
	local s = {Thief = thief; Victim = victim; Stall = stall; Spot = spotIndex; Hits = 0;}
	Heist.Sessions[thief] = s
	thief:SetAttribute("CarryingStolen", true)
	thief:SetAttribute("StealCombat", victim.UserId)
	victim:SetAttribute("StealCombat", thief.UserId)
	Heist.RefreshSpeed(thief)
	--.. any carry end that ISN'T our forced return closes the heist -- the
	--.. thief banked it (their win) or lost the carry some other way
	s.CarryConn = thief:GetAttributeChangedSignal("CarryingCucumber"):Connect(function()
		if thief:GetAttribute("CarryingCucumber") == nil then
			Heist.End(thief)
		end
	end)
end

function Heist.Strike(attacker)
	local foeId = attacker:GetAttribute("StealCombat")
	if not foeId then return end
	local target = Players:GetPlayerByUserId(foeId)
	if not target then return end
	--.. the session must actually pair these two, in either direction
	local s = Heist.Sessions[target]
	local role = (s and s.Victim == attacker) and "victim" or nil
	if not role then
		s = Heist.Sessions[attacker]
		if s and s.Victim == target then role = "thief" else return end
	end
	local now = os.clock()
	if now - (Heist.LastStrike[attacker] or 0) < Heist.StrikeCooldown then return end
	local ahrp = attacker.Character and attacker.Character:FindFirstChild("HumanoidRootPart")
	local thrp = target.Character and target.Character:FindFirstChild("HumanoidRootPart")
	local thum = target.Character and target.Character:FindFirstChildOfClass("Humanoid")
	if not (ahrp and thrp and thum and thum.Health > 0) then return end
	if (ahrp.Position - thrp.Position).Magnitude > Heist.StrikeRange then return end
	Heist.LastStrike[attacker] = now
	--.. knockback fling (boss-slam pattern, softened)
	local flat = (thrp.Position - ahrp.Position) * Vector3.new(1, 0, 1)
	local dir = flat.Magnitude > 0.05 and flat.Unit or Vector3.zAxis
	thrp.AssemblyLinearVelocity = dir * 26 + Vector3.new(0, 9, 0)
	pcall(function() PlaySound3D("EggPop", thrp, {Volume = 0.6, Speed = 0.7, RollOff = 60}) end)
	if role == "victim" then
		s.Hits += 1
		if s.Hits >= Heist.HitsToReclaim then
			Heist.Return(s.Thief)
		else
			Notify(attacker, ("\u{2694} HIT %d/%d!"):format(s.Hits, Heist.HitsToReclaim), "Success")
			Notify(target, ("\u{1F6A8} %d MORE HITS AND THEY RECLAIM IT!"):format(Heist.HitsToReclaim - s.Hits))
		end
	end
end

local function AssignStall(plr)
	if StallOf[plr] then return end
	for id = 1, NSTALLS do
		local stall = Stalls[id]
		if stall and stall.Owner == nil then
			stall.Owner = plr
			StallOf[plr] = stall
			--.. the client (tutorial, HUD) finds its own stall through this
			plr:SetAttribute("VaultStallId", stall.Id)
			--.. fresh owners start locked; from here the lever keeps it that way
			stall.SecureUntil = os.clock() + SECURE_DURATION
			RefreshSign(stall)
			RefreshSecurityUI(stall)
			RefreshPrompts(stall)
			--.. prompt titles flip Take Back <-> Replace with the owner's hands
			stall.CarryConn = plr:GetAttributeChangedSignal("CarryingCucumber"):Connect(function()
				RefreshPrompts(stall)
			end)
			WatchRebirths(plr, stall)
			WatchVaultSlots(plr, stall)
			LoadVault(plr, stall) -- restore saved cucumbers once the profile is up
			--.. SFX pass: tell fresh owners WHERE home is (there was no
			--.. assignment notif before) + a welcome shimmer client-side
			FireVaultFX(plr, {Kind = "Assigned", StallId = stall.Id})
			Notify(plr, ("\u{1F3E6} YOUR VAULT: STALL %d"):format(stall.Id), "Success")
			return
		end
	end
end

local function ReleaseStall(plr)
	local stall = StallOf[plr]
	StallOf[plr] = nil
	LastPush[plr] = nil
	LastSteal[plr] = nil
	Heist.LastStrike[plr] = nil
	--.. leaving mid-heist: a thief's stolen carry flies home to the victim;
	--.. a leaving victim just ends the fight (the thief keeps the goods)
	if Heist.Sessions[plr] then Heist.Return(plr) end
	for thief, s in pairs(Heist.Sessions) do
		if s.Victim == plr then Heist.End(thief) end
	end
	LastUpgradeClick[plr] = nil
	if plr.Parent == Players then plr:SetAttribute("VaultStallId", nil) end
	if not stall then return end
	if stall.SlotsConn then
		stall.SlotsConn:Disconnect()
		stall.SlotsConn = nil
	end
	if stall.RebirthConn then
		stall.RebirthConn:Disconnect()
		stall.RebirthConn = nil
	end
	if stall.CarryConn then
		stall.CarryConn:Disconnect()
		stall.CarryConn = nil
	end
	stall.Owner = nil
	--.. next owner must complete their own LoadVault before any profile write
	stall.VaultLoaded = nil
	stall.UnrestoredVault = nil
	for i, rec in pairs(stall.Stored) do
		if rec.Model and rec.Model.Parent then rec.Model:Destroy() end
		stall.Stored[i] = nil
	end
	stall.SecureUntil = 0
	RefreshSecurityUI(stall)
	RefreshSign(stall)
	RefreshPrompts(stall)
	if (stall.Level or 0) > 0 or (stall.Extra or 0) > 0 then
		stall.Level = 0
		stall.Extra = 0
		ScheduleRelayout()
	end
end

--.. cheapest next-level cost across the player's stored cucumbers (nil when
--.. nothing stored/upgradable) -- the tutorial's cukes top-up uses this
function VaultService.CheapestUpgradeCost(plr)
	local stall = StallOf[plr]
	if not stall then return nil end
	local cheapest = nil
	for _, rec in pairs(stall.Stored) do
		if (rec.Level or 1) < MAX_LEVEL then
			local cost = UpgradeCostFor(rec)
			if not cheapest or cost < cheapest then cheapest = cost end
		end
	end
	return cheapest
end

--.. UPGRADE-sign click on a stored cucumber: pay Cukes, +1 level, income x1.18
function VaultService.Upgrade(plr, stall, spotIndex)
	if stall.Owner ~= plr then
		Notify(plr, "\u{1F6AB} NOT YOUR VAULT!")
		return
	end
	local rec = stall.Stored[spotIndex]
	if not rec then return end
	--.. carrying no longer blocks upgrading (2026-08-27): the arm carry and
	--.. the stored cucumber are unrelated -- the refusal only existed for
	--.. the old R-prompt/Replace-prompt conflict
	local level = rec.Level or 1
	if level >= MAX_LEVEL then
		Notify(plr, ("\u{2B50} %s IS MAX LEVEL!"):format(string.upper(rec.Name), MAX_LEVEL))
		return
	end
	local cost = UpgradeCostFor(rec)
	local CurrencyHandler = ServerController.GetModule("CurrencyHandler")
	if not CurrencyHandler.CheckIfEnough({Player = plr; Currency = "Cucumbers"; Amount = cost;}) then
		--.. SFX pass: a deeper can't-afford buzz than the generic error
		FireVaultFX(plr, {Kind = "UpgradeFail"})
		Notify(plr, ("\u{1F952} NOT ENOUGH CUKES!"):format(Abbrev(cost)))
		return
	end
	CurrencyHandler.RemoveCurrency(plr, "Cucumbers", cost, "VaultCucumberUpgrade")
	--.. replicated upgrade counter: the tutorial's upgrade step watches this
	--.. (same pattern as VaultLeverPulls)
	plr:SetAttribute("VaultUpgrades", (tonumber(plr:GetAttribute("VaultUpgrades")) or 0) + 1)
	local prevRate = EffRate(rec)
	rec.Level = level + 1
	DisplayOn(stall, spotIndex, rec) -- rebuilds the card + upgrade prompt with new numbers
	SaveVault(stall)
	--.. SFX pass: level-laddered success ping, or the one-time MAX moment
	--.. (bystanders get a 3D shimmer at the pedestal for a maxed cucumber)
	if rec.Level >= MAX_LEVEL then
		FireVaultFX(plr, {Kind = "UpgradeMax", StallId = stall.Id, Spot = spotIndex})
		local spotPart = stall.Spots and stall.Spots[spotIndex]
		if spotPart then
			PlaySound3D("Magic Shimmer", spotPart, {Volume = 0.5, RollOff = 60})
		end
	else
		FireVaultFX(plr, {Kind = "Upgrade", StallId = stall.Id, Spot = spotIndex,
			Level = rec.Level, RateDelta = EffRate(rec) - prevRate})
	end
	--.. no success Notify (removed 2026-08-27, user): the card's live level +
	--.. $/s refresh and the upgrade SFX are feedback enough; the NOT ENOUGH
	--.. CUKES error notify above stays
end

--.. owner steps on a cucumber's money pad -> banked coins for what it accrued
function VaultService.Collect(stall, spotIndex, hit)
	local char = hit:FindFirstAncestorOfClass("Model")
	local plr = char and Players:GetPlayerFromCharacter(char)
	if not plr or stall.Owner ~= plr then return end
	local rec = stall.Stored[spotIndex]
	if not rec then return end
	local offline = math.floor(rec.OfflineCash or 0)
	local accrued = math.floor(rec.Accrued or 0)
	local amount = accrued + offline -- offline coins (2026-08-27) pay out with the pad
	if amount < 1 then return end
	local now = os.clock()
	if now - (rec.LastCollect or 0) < 1 then return end
	rec.LastCollect = now
	rec.Accrued = (rec.Accrued or 0) - accrued -- keep the sub-dollar remainder ticking
	rec.OfflineCash = 0
	rec.HeatT = 0 -- MOLTEN cools off on every collect
	UpdatePadLabel(stall, spotIndex, rec)
	SaveVault(stall)
	local CurrencyHandler = ServerController.GetModule("CurrencyHandler")
	pcall(function()
		--.. MultipliersApplied: pay EXACTLY what the pad labels show (user
		--.. 2026-08-27: coin multipliers were silently inflating the payout
		--.. past the displayed amount -- "gives me a lot more coins");
		--.. deliberately not WasPurchase so season stats still track it
		CurrencyHandler.AddCurrency({Player = plr; Currency = "Coins"; HasTotal = true; Amount = amount; MultipliersApplied = true;})
	end)
	--.. cha-ching moved CLIENT-SIDE (2026-08-27, user): VaultFXClient's
	--.. Collect handler plays Assets.Sounds.CollectCash at 0.5 through the
	--.. SFX-gated playFX pipeline -- the old server Sound on the pad could
	--.. not respect the collector's SFX setting (bystanders no longer hear it)
	local pad = stall.CollectPads and stall.CollectPads[spotIndex]
	--.. SFX pass: the owner's coin-burst fountain + pad highlight flash
	FireVaultFX(plr, {Kind = "Collect"; Amount = amount; StallId = stall.Id;
		Spot = spotIndex; PadPosition = pad and pad.Position or nil;})
end

--.. Admin panel: force a stall's security open (same writes ReleaseStall does)
function VaultService.AdminUnlock(target)
	local stall = StallOf[target]
	if not stall then return false end
	stall.SecureUntil = 0
	RefreshSecurityUI(stall)
	return true
end


function VaultService.StallOfPlayer(plr)
	return StallOf[plr]
end

function VaultService.GetStall(id)
	return Stalls[id]
end

--.. one prompt per podium: what it does depends on the podium + your hands
function VaultService.PodiumAction(plr, stall, spotIndex)
	if stall.Owner ~= plr then
		Notify(plr, "\u{1F6AB} NOT YOUR VAULT!")
		return
	end
	local CarryService = ServerController.GetModule("CarryService")
	local rec = stall.Stored[spotIndex]
	local carrying = CarryService.Get(plr) ~= nil
	if rec == nil then
		if carrying then
			VaultService.Deposit(plr, stall, spotIndex)
		else
			Notify(plr, "\u{1F952} CARRY A CUCUMBER FIRST!")
		end
	elseif carrying then
		VaultService.Replace(plr, stall, spotIndex)
	else
		VaultService.TakeBack(plr, stall, spotIndex)
	end
end

function VaultService.Deposit(plr, stall, spotIndex)
	if stall.Owner ~= plr then
		Notify(plr, "\u{1F6AB} NOT YOUR VAULT!")
		return
	end
	if stall.Stored[spotIndex] ~= nil or stall.Spots[spotIndex] == nil then return end
	local CarryService = ServerController.GetModule("CarryService")
	if not CarryService.Get(plr) then
		Notify(plr, "\u{1F952} CARRY A CUCUMBER FIRST!")
		return
	end
	local record = CarryService.Take(plr)
	if not record then return end
	stall.Stored[spotIndex] = record
	DisplayOn(stall, spotIndex, record)
	--.. SFX pass: a soft pop + collect blip at the pedestal (3D, bystanders
	--.. hear the deposit) and the owner's scale-pop/sparkle via VaultFX
	local spotPart = stall.Spots[spotIndex]
	if spotPart then
		PlaySound3D("EggPop", spotPart, {Volume = 0.5, Speed = 0.8, RollOff = 45})
		PlaySound3D("Collect", spotPart, {Volume = 0.35, Speed = 1.1, RollOff = 45})
	end
	FireVaultFX(plr, {Kind = "Deposit", StallId = stall.Id, Spot = spotIndex})
	RefreshSign(stall)
	RefreshPrompts(stall)
	SaveVault(stall)
	Notify(plr, ("\u{1F3E6} STORED THE %s!"):format(string.upper(record.Name)), "Success")
end

--.. carrying + occupied podium: the stored cucumber hops onto your arm and
--.. the carried one takes its place on that exact podium
function VaultService.Replace(plr, stall, spotIndex)
	if stall.Owner ~= plr then
		Notify(plr, "\u{1F6AB} NOT YOUR VAULT!")
		return
	end
	local recB = stall.Stored[spotIndex]
	if not recB then return end
	local CarryService = ServerController.GetModule("CarryService")
	if not CarryService.Get(plr) then return end
	local recA = CarryService.Take(plr)
	if not recA then return end

	--.. lift the displayed one off its podium
	local modelB = recB.Model
	StripPodiumAttachments(modelB)
	stall.Stored[spotIndex] = nil
	modelB.Parent = nil

	if CarryService.Restore(plr, modelB, recB) then
		stall.Stored[spotIndex] = recA
		DisplayOn(stall, spotIndex, recA)
		FireVaultFX(plr, {Kind = "Replace", StallId = stall.Id, Spot = spotIndex}) -- SFX pass
		Notify(plr, ("\u{1F501} SWAPPED!"):format(string.upper(recA.Name), string.upper(recB.Name)), "Success")
	else
		--.. couldn't put it on the arm (dead/respawning): undo everything
		stall.Stored[spotIndex] = recB
		DisplayOn(stall, spotIndex, recB)
		CarryService.Restore(plr, recA.Model, recA)
	end
	RefreshSign(stall)
	RefreshPrompts(stall)
	SaveVault(stall)
end

function VaultService.TakeBack(plr, stall, spotIndex)
	if stall.Owner ~= plr then
		Notify(plr, "\u{1F6AB} NOT YOUR VAULT!")
		return
	end
	local record = stall.Stored[spotIndex]
	if not record then return end
	local CarryService = ServerController.GetModule("CarryService")
	if CarryService.Get(plr) then
		Notify(plr, "\u{1F952} ARMS FULL!")
		return
	end
	local model = record.Model
	StripPodiumAttachments(model)
	stall.Stored[spotIndex] = nil
	RemovePadLabel(stall, spotIndex)
	model.Parent = nil
	if CarryService.Restore(plr, model, record) then
		RefreshSign(stall)
		FireVaultFX(plr, {Kind = "TakeBack", StallId = stall.Id, Spot = spotIndex}) -- SFX pass
		Notify(plr, ("\u{1F952} TOOK BACK THE %s!"):format(string.upper(record.Name)), "Success")
	else
		stall.Stored[spotIndex] = record
		DisplayOn(stall, spotIndex, record)
	end
	RefreshPrompts(stall)
	SaveVault(stall)
end

--.. the stall's security lever: an owner pull (re-)arms the lasers for
--.. SECURE_DURATION seconds; anyone else just gets told off
function VaultService.PullLever(plr, stall)
	if stall.Owner ~= plr then
		Notify(plr, "\u{1F6AB} NOT YOUR LEVER!")
		return
	end
	local now = os.clock()
	if now - (stall.LastLever or 0) < 0.5 then return end
	stall.LastLever = now
	local wasLive = IsSecured(stall) -- BEFORE re-lock: detects unlocked -> locked
	stall.SecureUntil = now + SECURE_DURATION
	--.. replicated pull counter: the tutorial's lock step watches this
	plr:SetAttribute("VaultLeverPulls", (tonumber(plr:GetAttribute("VaultLeverPulls")) or 0) + 1)
	RefreshSecurityUI(stall)
	--.. SFX pass: heavy ka-chunk at the lever + a down-and-back handle throw;
	--.. everything re-resolves instances (the bank rebuilds under us)
	pcall(function()
		local hinge = stall.Lever and stall.Lever:FindFirstChild("LeverHinge")
		if hinge then
			PlaySound3D("Metal Heavy", hinge, {Speed = 1.1, RollOff = 70}, 1.2)
		end
		for _, partName in ipairs({"Handle", "BallOnHandle"}) do
			local part = stall.Lever and stall.Lever:FindFirstChild(partName)
			if part then
				local orig = part.CFrame
				local down = TweenService:Create(part,
					TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{CFrame = CFrame.new(0, -0.45, 0) * orig})
				down.Completed:Once(function()
					if part.Parent then
						TweenService:Create(part,
							TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
							{CFrame = orig}):Play()
					end
				end)
				down:Play()
			end
		end
	end)
	if not wasLive then
		--.. fresh arming (not a mid-lock top-up): lasers flicker on
		--.. bottom-to-top with a zap blip each
		ArmLasersSequence(stall)
	end
	Notify(plr, ("\u{1F512} SECURED FOR %s!"):format(FormatClock(SECURE_DURATION)), "Success")
end

--.. STEALING (2026-08-26): while a vault's lock has lapsed, any OTHER
--.. player can hold F on a stored cucumber and walk off with it -- it goes
--.. onto their arm like any carry, so they must WALK it home (teleports
--.. are carry-blocked) and can bank it via their own podium prompts. The
--.. victim has no recovery path yet, by design.
--.. ANTI-CHEAT: prompts are client-visible state, so an exploiter can fire
--.. this with the lasers up or from across the map. Everything is
--.. re-validated here: IsSecured is the authority on the lock, the thief
--.. must really be standing at that podium, must be empty-handed, must not
--.. be the owner, and steals are rate-limited.
function VaultService.Steal(plr, stall, spotIndex)
	if stall.Owner == nil or stall.Owner == plr then return end
	local rec = stall.Stored[spotIndex]
	if not rec then return end
	if rec.Mutation == "FROZEN" then
		--.. FROZEN trades 0.8x earnings for theft immunity, even unlocked
		Notify(plr, "\u{2744} FROZEN SOLID \u{2014} CAN'T BE STOLEN!")
		return
	end
	if IsSecured(stall) then
		--.. locked vault = no steal, whatever the client claims
		warn(("[VaultService] BLOCKED steal: %s hit %s's SECURED stall %d"):format(plr.Name, stall.Owner.Name, stall.Id))
		Notify(plr, "\u{26D4} VAULT LOCKED!")
		return
	end
	local char = plr.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local spot = stall.Spots and stall.Spots[spotIndex]
	if not hrp or not spot or (hrp.Position - spot.Position).Magnitude > 14 then
		--.. remote-fired prompt: the thief isn't actually at the podium
		warn(("[VaultService] BLOCKED steal: %s not at stall %d spot %d"):format(plr.Name, stall.Id, spotIndex))
		return
	end
	local CarryService = ServerController.GetModule("CarryService")
	if CarryService.Get(plr) then
		Notify(plr, "\u{1F952} ARMS FULL!")
		return
	end
	local now = os.clock()
	if now - (LastSteal[plr] or 0) < 1 then return end
	LastSteal[plr] = now

	local victim = stall.Owner
	local model = rec.Model
	StripPodiumAttachments(model)
	stall.Stored[spotIndex] = nil
	RemovePadLabel(stall, spotIndex)
	rec.Accrued = 0 -- uncollected pad money never changes hands
	rec.OfflineCash = 0
	model.Parent = nil
	if CarryService.Restore(plr, model, rec) then
		RefreshSign(stall)
		RefreshPrompts(stall)
		--.. SFX pass: the whole street hears the heist -- alarm bell + a 5s
		--.. spinning siren at the robbed stall; the stolen goods trail red
		--.. sparkles on the thief's arm (carry-end paths destroy the model,
		--.. so trail cleanup is free). Emitter is added AFTER
		--.. StripPodiumAttachments ran above, so the strip can't eat it.
		pcall(function()
			local floorTile = stall.Model and stall.Model:FindFirstChild("FloorTile")
			if floorTile then
				PlaySound3D("Alarm Bell", floorTile, {Volume = 0.7, RollOff = 120}, 3.5)
				local siren = MakeBeacon("StealSiren", floorTile, 11, stall.Model)
				Debris:AddItem(siren, 5)
			end
			local primary = model.PrimaryPart
			if primary then
				local trail = Instance.new("ParticleEmitter")
				trail.Name = "StolenTrail"
				trail.Texture = "rbxasset://textures/particles/sparkles_main.dds"
				trail.Color = ColorSequence.new(Color3.fromRGB(255, 60, 60))
				trail.LightEmission = 0.6
				trail.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0)})
				trail.Lifetime = NumberRange.new(0.4, 0.7)
				trail.Rate = 14
				trail.Speed = NumberRange.new(0.5, 1.5)
				trail.SpreadAngle = Vector2.new(180, 180)
				trail.Parent = primary
			end
		end)
		FireVaultFX(plr, {Kind = "StoleIt"})
		FireVaultFX(victim, {Kind = "Robbed"})
		Notify(plr, ("\u{1F608} STOLE THE %s!"):format(string.upper(rec.Name)), "Success")
		Notify(victim, ("\u{1F6A8} %s STOLE YOUR %s!"):format(string.upper(plr.DisplayName), string.upper(rec.Name)))
		Heist.Start(plr, victim, stall, spotIndex)
	else
		--.. thief mid-respawn: put everything back
		stall.Stored[spotIndex] = rec
		DisplayOn(stall, spotIndex, rec)
		RefreshPrompts(stall)
	end
	SaveVault(stall) -- the victim's profile forgets stolen goods immediately
end

function VaultService.Initialize()
	--.. clicks from the pedestals' UPGRADE signs (VaultFXClient fires this;
	--.. Upgrade re-validates ownership, occupancy, level, and cost)
	Network:BindEvents({
		VaultUpgradeClick = function(plr, payload)
			if type(payload) ~= "table" then return end
			local now = os.clock()
			if LastUpgradeClick[plr] and now - LastUpgradeClick[plr] < 0.25 then return end
			LastUpgradeClick[plr] = now
			local stall = Stalls[tonumber(payload.StallId) or -1]
			local spot = tonumber(payload.Spot)
			if not stall or not spot then return end
			VaultService.Upgrade(plr, stall, spot)
		end,
		StealStrike = function(plr)
			Heist.Strike(plr)
		end,
	})
	for id = 1, NSTALLS do
		Stalls[id] = {Id = id; Owner = nil; Stored = {}; Level = 0; SecureUntil = 0; WasSecured = false;}
	end
	Relayout() -- fresh level-0 bank + bindings

	--.. DEV HOOK (Studio only, SpawnBossDev pattern): drive the heist flow
	--.. without gameplay RNG. Set on workspace from the dev console:
	--..   VaultStealDev = "seed:Name"       -> unlock Name's stall + seed a basic
	--..                                        cucumber onto their first free podium
	--..   VaultStealDev = "grab:Name:Thief" -> teleport Thief to Name's stall and
	--..                                        steal the first stored cucumber
	if game:GetService("RunService"):IsStudio() then
		workspace:GetAttributeChangedSignal("VaultStealDev"):Connect(function()
			local v = workspace:GetAttribute("VaultStealDev")
			if type(v) ~= "string" or v == "" then return end
			workspace:SetAttribute("VaultStealDev", nil)
			local cmd, a, b = string.match(v, "^(%w+):([%w_]+):?([%w_]*)$")
			local pa = a and Players:FindFirstChild(a)
			local pb = (b and b ~= "") and Players:FindFirstChild(b) or nil
			if cmd == "seed" and pa then
				local stall = StallOf[pa]
				if not (stall and stall.Spots) then return end
				stall.SecureUntil = 0
				RefreshSecurityUI(stall)
				local CarryService = ServerController.GetModule("CarryService")
				local BreakablesService = ServerController.GetModule("BreakablesService")
				local typeDef = BreakablesService.FindType("Spawn", "Cucumber")
				local model = typeDef and CarryService.BuildFromTemplate(typeDef)
				if not model then warn("[VaultStealDev] no template") return end
				local spot
				for i = 1, #stall.Spots do
					if stall.Stored[i] == nil then spot = i break end
				end
				if not spot then model:Destroy() return end
				-- Rarity is the NUMERIC spawn-share odds in carry metas (GiveCarry clamps it), not a label
				local rec = {Model = model; Zone = "Spawn"; TypeDef = typeDef; Name = typeDef.Name; Rarity = 1; Rate = 1; Level = 1; DevSeed = true;}
				if b and b ~= "" then rec.Mutation = b end -- "seed:Name:FROZEN" etc.
				--.. seeds get the real mutation skin too (same call as LoadVault)
				pcall(BreakablesService.ApplyStoredLook, model, rec.Name, rec.Mutation)
				stall.Stored[spot] = rec
				DisplayOn(stall, spot, rec)
				RefreshPrompts(stall)
				print(("[VaultStealDev] seeded spot %d for %s"):format(spot, pa.Name))
			elseif cmd == "unseed" and pa then
				--.. remove every dev-seeded record (and ONLY those -- a
				--.. stamp-all "mut" command once trashed real vault mutations)
				local stall = StallOf[pa]
				if not stall then return end
				local n = 0
				for i, rec in pairs(stall.Stored) do
					if rec.DevSeed then
						if rec.Model then rec.Model:Destroy() end
						stall.Stored[i] = nil
						RemovePadLabel(stall, i)
						n += 1
					end
				end
				RefreshSign(stall)
				RefreshPrompts(stall)
				SaveVault(stall)
				print(("[VaultStealDev] removed %d dev-seeded record(s) for %s"):format(n, pa.Name))
			elseif cmd == "heat" and pa then
				--.. dev-seeded records ONLY: never touch real vault data
				local stall = StallOf[pa]
				if not stall then return end
				for _, rec in pairs(stall.Stored) do
					if rec.DevSeed then rec.HeatT = tonumber(b) or 0 end
				end
				print(("[VaultStealDev] set HeatT=%s on dev seeds for %s"):format(tostring(b), pa.Name))
			elseif cmd == "grab" and pa and pb then
				local stall = StallOf[pa]
				if not stall then return end
				local spot
				for i in pairs(stall.Stored) do spot = i break end
				if not (spot and stall.Spots and stall.Spots[spot]) then return end
				local char = pb.Character
				if char then
					char:PivotTo(CFrame.new(stall.Spots[spot].Position + Vector3.new(3, 3, 0)))
				end
				VaultService.Steal(pb, stall, spot)
				print(("[VaultStealDev] grab attempted by %s at spot %d"):format(pb.Name, spot))
			end
		end)
	end

	Players.PlayerAdded:Connect(AssignStall)
	Players.PlayerRemoving:Connect(ReleaseStall)
	for _, plr in ipairs(Players:GetPlayers()) do
		AssignStall(plr)
	end

	--.. vault economy: every displayed cucumber ACCRUES its coins/s (at its
	--.. upgraded EffectiveRate) onto its own money pad; the owner steps on
	--.. the pad to collect (VaultService.Collect). 2026-08-26: the loop
	--.. ticks 5x/s and pays rate x actual-dt per tick -- SAME $/s total,
	--.. but the pad labels count up smoothly instead of jumping once a
	--.. second. Profile writes stay on a ~1s cadence.
	task.spawn(function()
		local CarryService = ServerController.GetModule("CarryService")
		local TICK = 0.2
		local sinceSave = 0
		while true do
			local dt = task.wait(TICK)
			sinceSave += dt
			local doSave = sinceSave >= 1
			if doSave then sinceSave = 0 end
			for _, stall in pairs(Stalls) do
				if stall.Owner then
					for idx, rec in pairs(stall.Stored) do
						local rate = CarryService.EffectiveRate(rec)
						--.. MOLTEN runs hot (2026-08-27): earn rate ramps to 2.5x
						--.. over an hour left uncollected (HeatT, saved with the
						--.. vault); Collect resets the heat. Live tick only --
						--.. offline coins keep the trusted flat rate.
						if rec.Mutation == "MOLTEN" then
							rec.HeatT = math.min((rec.HeatT or 0) + dt, 3600)
							rate *= 1 + 1.5 * (rec.HeatT / 3600)
						end
						rec.Accrued = (rec.Accrued or 0) + rate * dt
						UpdatePadLabel(stall, idx, rec)
					end
					if doSave then
						SaveVault(stall) -- keep the profile's accrued totals current
						--.. self-heal (2026-08-27, user report: some sessions the
						--.. UPGRADE rows never showed): any displayed card missing
						--.. its row gets it rebuilt -- idempotent, ~1s cadence
						for hIdx, hRec in pairs(stall.Stored) do
							local primary = hRec.Model and hRec.Model.PrimaryPart
							local bb = primary and primary:FindFirstChild("EarnBillboard")
							if bb and not bb:FindFirstChild("UpgradeRow") then
								RefreshUpgradePrompt(stall, hIdx, hRec)
							end
						end
					end
				end
			end
		end
	end)
	--.. security tick: the countdown above every lever; when a vault's
	--.. 5:00 lapses the lasers drop and its cucumbers turn stealable until
	--.. the owner pulls the lever again
	task.spawn(function()
		while true do
			task.wait(1)
			for _, stall in pairs(Stalls) do
				if stall.Owner then
					local wasSecured = stall.WasSecured
					RefreshSecurityUI(stall)
					--.. SFX pass: final-10s countdown -- owner beeps via
					--.. VaultFX + a laser brown-out flicker each second
					if stall.WasSecured then
						local left = math.floor((stall.SecureUntil or 0) - os.clock() + 0.5)
						if left >= 1 and left <= 10 then
							FireVaultFX(stall.Owner, {Kind = "LockTick", Left = left})
							pcall(function()
								for _, p in ipairs(LaserParts(stall)) do
									p.Transparency = 0.5
								end
								task.delay(0.15, function()
									if IsSecured(stall) then SetLasers(stall, true) end
								end)
							end)
						end
					end
					if wasSecured and not stall.WasSecured then
						--.. SFX pass: expiry theatrics -- owner klaxon (VaultFX),
						--.. a power-down whine at the lever (3D, social) and the
						--.. lasers flickering off top-to-bottom
						pcall(function()
							local hinge = stall.Lever and stall.Lever:FindFirstChild("LeverHinge")
							local template = ReplicatedStorage.Assets.Sounds:FindFirstChild("Electric Buzz")
							if hinge and template then
								local whine = template:Clone()
								whine.Name = "PowerDownWhine"
								whine.Looped = true
								whine.Volume = 0.3
								whine.PlaybackSpeed = 1
								whine.RollOffMinDistance = 8
								whine.RollOffMaxDistance = 60
								whine.Parent = hinge
								whine:Play()
								TweenService:Create(whine,
									TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
									{PlaybackSpeed = 0.3}):Play()
								task.delay(0.85, function()
									pcall(function() whine:Stop() whine:Destroy() end)
								end)
							end
						end)
						DisarmLasersSequence(stall)
						--.. mid-tutorial players haven't met the vault yet:
						--.. skip the scary expiry ping until the basics land
						local pd = stall.Owner:FindFirstChild("PlayerData")
						local done = pd and pd:FindFirstChild("DoneTutorial")
						if not done or done.Value == true then
							--.. urgent owner klaxon rides the same gate as the notif
							FireVaultFX(stall.Owner, {Kind = "Expired"})
							Notify(stall.Owner, "\u{1F6A8} VAULT UNLOCKED \u{2014} PULL YOUR LEVER!")
						end
					end
				end
			end
		end
	end)

	print("[VaultService] CUCUMBER BANK ready: " .. NSTALLS .. " upgradable vault stalls + lever security.")
end

--.. HUD VAULT button (2026-08-27): drop the owner on the walkway just outside
--.. their stall's gate, facing in. Geometry resolved per call -- BankBuilder
--.. rebuilds replace every instance, so nothing here may be cached.
--.. standing spot just outside the stall door, facing it -- nil while the
--.. player has no stall or BankBuilder is mid-rebuild (Stall_N briefly gone).
--.. Second return is the facing direction for AlignCamera.
function VaultService.StallSpawnCFrame(plr)
	local stall = VaultService.StallOfPlayer(plr)
	if not stall then return nil end
	local bank = workspace:FindFirstChild("CucumberBank")
	local stalls = bank and bank:FindFirstChild("Stalls")
	local model = stalls and stalls:FindFirstChild("Stall_" .. tostring(stall.Id))
	local door = model and model:FindFirstChild("DoorZone")
	if not door then return nil end
	local center = model:GetPivot().Position
	local out = door.Position - center
	out = Vector3.new(out.X, 0, out.Z)
	out = out.Magnitude > 0.1 and out.Unit or Vector3.new(0, 0, 1)
	local target = door.Position + out * 4 + Vector3.new(0, 2, 0)
	return CFrame.lookAt(target, Vector3.new(door.Position.X, target.Y, door.Position.Z)), -out
end

function VaultService.TeleportToStall(plr)
	local char = plr.Character
	local cf, look = VaultService.StallSpawnCFrame(plr)
	if not (char and cf) then return end
	Network:FireClient(plr, "AlignCamera", look) -- camera turns first, like the sell teleport
	char:PivotTo(cf)
end

return VaultService
