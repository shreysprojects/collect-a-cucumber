--[[
	CarryService (2026-08-25)
	Chance-based cucumber pickup: destroying a cucumber can leave a mini copy
	of it cradled on the killer's LEFT ARM. The pickaxe stays equipped and
	mining keeps working the whole time. While carrying, only a break that is
	strictly RARER than the current carry (BreakablesService.CarryRarityOf:
	biome-pool weight share x biome tier x golden/mutation/lightning odds)
	rolls a pickup -- winning it swaps the arm cucumber for the rarer one.
	The DROP CUCUMBER button (StarterGui.CarryControls -> CarryClient -> the
	DropCucumber remote) re-plants it as a REAL breakable (full HP + bar,
	original size) -- but only in the cucumber FIELD of the biome it was
	grabbed in (workspace.SpawnArea regions; the lobby doesn't count).
	Hooked from BreakablesService.Break via a function-scope GetModule -- that
	module's top level is AT Luau's 200-local limit, never add locals there.
]]

--..Services..--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

--..Modules..--
local ServerController = require(ServerStorage.ServerController)
local ControllerLoader = require(ReplicatedStorage.Modules.ControllerLoader)
local Network = ControllerLoader.GetController("Network")

--..Variables..--
local CARRY_MODEL_NAME = "CarriedCucumber"
local CARRY_LONGEST_AXIS = 2.8 -- studs: an armful, whatever the source model's size
local BASE_CHANCE = 0.16 -- pickup odds scale for the most common produce (Weight 35)
local FLOOR_CHANCE = 0.04 -- even the rarest type keeps this much

local Carrying = {} -- [player] = {Model, Zone, TypeDef, Name, Rarity}

--.. A biome's cucumber FIELD is its workspace.SpawnArea part (Spawn=1 ..
--.. Narmek=8, same order as BreakablesService's ZONES / GetZonePoint). The
--.. zone *slab* (SlabZoneAt) is too generous for drops -- Spawn's slab
--.. includes the whole lobby.
local ZONE_FIELD_INDEX = {
	Spawn = "1"; Desert = "2"; Samurai = "3"; Farm = "4";
	Snow = "5"; Underwater = "6"; Volcano = "7"; Narmek = "8";
}
local FIELD_MARGIN = 6 -- studs of grace around the field's XZ footprint

local CarryService = {}

--..Functions..--

local function InZoneField(zoneName, position)
	local folder = workspace:FindFirstChild("SpawnArea")
	local region = folder and folder:FindFirstChild(ZONE_FIELD_INDEX[zoneName] or "")
	if not (region and region:IsA("BasePart")) then
		return true -- misconfigured/renamed map region: never hard-lock the carry
	end
	local lp = region.CFrame:PointToObjectSpace(position)
	return math.abs(lp.X) <= region.Size.X * 0.5 + FIELD_MARGIN
		and math.abs(lp.Z) <= region.Size.Z * 0.5 + FIELD_MARGIN
		and lp.Y >= -12 and lp.Y <= 60
end

--.. Rarer produce spawns with a lower Weight, so PICKUP odds scale with
--.. Weight: common (35) ~20%, mid (14-16) ~11%, trees (8) ~8%. Golden halves
--.. it. (Rarity COMPARISON between two cucumbers is CarryRarityOf's job.)
local function ChanceFor(typeDef)
	local chance = FLOOR_CHANCE + BASE_CHANCE * math.clamp((typeDef.Weight or 12) / 35, 0, 1)
	if typeDef.Golden then
		chance *= 0.5
	end
	return chance
end

--.. Coins-per-second a cucumber earns while displayed in a vault. Made-up
--.. economy (2026-08-25): in-biome rarity pushes the base from 1 (common,
--.. Weight 35) to ~5 (trees, Weight 8); each later biome multiplies x1.6
--.. (Narmek ~x27); golden x3, diamond x8, mutation x5 (PRISMATIC x20), lightning charge x4.
local function EarnRateOf(data)
	local typeDef = data.Type
	local base = 1 + (35 - math.clamp(typeDef.Weight or 12, 1, 35)) / 35 * 4
	local tier = tonumber(ZONE_FIELD_INDEX[data.Zone]) or 1
	local rate = base * (1.6 ^ (tier - 1))
	if typeDef.Golden then rate *= 3 end
	--.. diamond material (2026-08-27): spawn-rolled like golden, 75% rarer;
	--.. a mutation mult still stacks on top
	if typeDef.Diamond then rate *= 8 end
	if data.Mutation then rate *= (data.Mutation == "PRISMATIC" and 20 or 5) end
	if data.Lightning then rate *= 4 end
	return math.max(1, math.floor(rate))
end

--.. Clone the broken breakable's visual into a self-contained, welded,
--.. armful-sized Model. Works for both breakable shapes: template Models
--.. (PrimaryPart = invisible "Hitbox") and procedural lone Parts.
local function BuildCarryModel(src)
	local model
	if src:IsA("Model") then
		model = src:Clone()
	else
		local partClone = src:Clone()
		model = Instance.new("Model")
		partClone.Parent = model
		model.PrimaryPart = partClone
	end

	--.. gameplay leftovers have no place on a prop: HP bars, click targets,
	--.. the anchored ground-shadow disc
	for _, obj in ipairs(model:GetDescendants()) do
		if obj:IsA("BillboardGui") or obj:IsA("ClickDetector") or obj:IsA("ProximityPrompt")
			or obj:IsA("BaseScript") or (obj:IsA("BasePart") and obj.Name == "Shadow") then
			obj:Destroy()
		end
	end

	local primary = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	if not primary then
		model:Destroy()
		return nil
	end
	model.PrimaryPart = primary

	--.. breakables in the field are anchored with no welds; a carried copy
	--.. must be one rigid unanchored body, so weld everything to the root
	for _, obj in ipairs(model:GetDescendants()) do
		if obj:IsA("BasePart") then
			obj.Anchored = false
			obj.CanCollide = false
			obj.CanQuery = false
			obj.CanTouch = false
			obj.Massless = true
			if obj ~= primary then
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = primary
				weld.Part1 = obj
				weld.Parent = obj
			end
		end
	end

	--.. shrink to an armful; never upscale (a sliced disc is already fine)
	local ext = model:GetExtentsSize()
	local longest = math.max(ext.X, ext.Y, ext.Z, 0.001)
	if longest > CARRY_LONGEST_AXIS then
		model:ScaleTo(model:GetScale() * (CARRY_LONGEST_AXIS / longest))
	end
	return model
end

--.. ===== shoulder carry pose (2026-08-26) =====
--.. The cucumber rides the LEFT SHOULDER and the left hand reaches up to
--.. steady it. Deliberately NOT an animation asset: one upload can't serve
--.. both the group-owned live game and this out-of-group test save
--.. (animation assets only play in games owned by their creator). And NOT a
--.. Motor6D C0 offset either: these characters rig with AnimationConstraint
--.. joints, whose C0 is read-only. An IKControl is the supported posing
--.. surface -- the hand tracks a grip Attachment on the carried model
--.. itself, replicates to every viewer, and composes with walk/idle.
local function ApplyArmPose(plr, entry)
	local char = plr.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	local upperArm = char and char:FindFirstChild("LeftUpperArm")
	local hand = char and char:FindFirstChild("LeftHand")
	local primary = entry.Model and entry.Model.PrimaryPart
	if not (humanoid and upperArm and hand and primary) then return end
	local grip = Instance.new("Attachment")
	grip.Name = "CarryGrip"
	--.. front-underside of the shoulder load: the palm cups it from below
	grip.Position = Vector3.new(0.15, -0.3, -0.85)
	grip.Parent = primary
	local ik = Instance.new("IKControl")
	ik.Name = "CarrySteadyIK"
	ik.Type = Enum.IKControlType.Position
	ik.ChainRoot = upperArm
	ik.EndEffector = hand
	ik.Target = grip
	ik.SmoothTime = 0.12
	ik.Parent = humanoid
	entry.PoseIK = ik
end

local function RestoreArmPose(entry)
	if not entry then return end
	if entry.PoseIK then
		entry.PoseIK:Destroy()
		entry.PoseIK = nil
	end
end

--.. Dictionaries.Upgrades.SetWalkSpeed owns the stacked speed total; we
--.. re-trigger the recompute at carry start/end (HoverboardService's exact
--.. pattern). The carry 2x bonus itself was removed 2026-08-27 (user call),
--.. so this is now just a safety resync.
--.. task.spawn because SetWalkSpeed can yield on a gamepass web check.
local function RefreshCarrySpeed(plr)
	task.spawn(function()
		pcall(function()
			require(script.Parent.Dictionaries.Upgrades).SetWalkSpeed(plr)
		end)
	end)
end

local function ClearCarry(plr)
	local entry = Carrying[plr]
	if not entry then return end
	Carrying[plr] = nil
	RestoreArmPose(entry)
	if plr.Parent == Players then
		plr:SetAttribute("CarryingCucumber", nil)
		plr:SetAttribute("CarryingCucumberValue", nil)
		RefreshCarrySpeed(plr)
	end
	if entry.Model and entry.Model.Parent then
		entry.Model:Destroy()
	end
end

--.. Weld `carryModel` onto the character's LEFT ARM (the pickaxe hand stays
--.. free and mining keeps working) and record what/where it came from
--.. (meta = {Zone, TypeDef, Name, Rarity}). Replaces any current carry.
--.. Returns true on success.
local function GiveCarry(plr, carryModel, meta)
	local char = plr.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 or not char.Parent then
		return false
	end
	local mount = char:FindFirstChild("UpperTorso") -- R15
		or char:FindFirstChild("Torso") -- R6 fallback
		or char:FindFirstChild("HumanoidRootPart")
	if not mount then return false end

	ClearCarry(plr) -- rarity upgrade: the old cucumber makes way

	--.. rest it ON the left shoulder like a carried log: LONGEST axis lies
	--.. fore-aft (local Z), nose tipped up a touch, leaned into the neck
	local ext = carryModel:GetExtentsSize()
	local rot = CFrame.new()
	if ext.X >= ext.Y and ext.X >= ext.Z then
		rot = CFrame.Angles(0, math.rad(90), 0) -- longest X -> Z
	elseif ext.Y >= ext.X and ext.Y >= ext.Z then
		rot = CFrame.Angles(math.rad(90), 0, 0) -- longest Y -> Z
	end
	carryModel:PivotTo(mount.CFrame * CFrame.new(-1.05, 1.05, 0.05)
		* CFrame.Angles(math.rad(-10), 0, math.rad(8)) * rot)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = mount
	weld.Part1 = carryModel.PrimaryPart
	weld.Parent = carryModel.PrimaryPart
	carryModel.Name = CARRY_MODEL_NAME

	--.. special catches glitter on the arm (SFX pass 2026-08-26): mutated, or
	--.. rarer than ~1-in-500 by the same combined odds the showcase reports.
	--.. The emitter rides the PrimaryPart, so it travels with the weld free.
	--.. 100% catch mode: luck = spawn share alone (the catch itself is certain)
	local combinedOdds = math.clamp(meta.Rarity or 1, 1e-9, 1)
	if (meta.Mutation or (1 / combinedOdds) >= 500) and not carryModel.PrimaryPart:FindFirstChild("CarrySparkle") then
		local sparkle = Instance.new("ParticleEmitter")
		sparkle.Name = "CarrySparkle"
		sparkle.Rate = 4
		sparkle.Lifetime = NumberRange.new(0.4, 0.8)
		sparkle.Speed = NumberRange.new(0.5, 1.2)
		sparkle.SpreadAngle = Vector2.new(180, 180)
		sparkle.LightEmission = 0.9
		sparkle.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.22), NumberSequenceKeypoint.new(1, 0)})
		sparkle.Color = ColorSequence.new(Color3.fromRGB(255, 250, 190), Color3.fromRGB(255, 255, 255))
		sparkle.Parent = carryModel.PrimaryPart
	end

	carryModel.Parent = char

	local entry = {Model = carryModel; Zone = meta.Zone; TypeDef = meta.TypeDef; Name = meta.Name; Rarity = meta.Rarity; Mutation = meta.Mutation; Rate = meta.Rate; Level = meta.Level;}
	Carrying[plr] = entry
	--.. full label incl. mutation ("CHARGED GOLDEN ..."): CarryClient prints it
	--.. above the DROP button; the value drives the green worth line under it
	plr:SetAttribute("CarryingCucumber", (meta.Mutation and (meta.Mutation .. " ") or "") .. meta.Name)
	plr:SetAttribute("CarryingCucumberValue", CarryService.ValueOf(entry))
	ApplyArmPose(plr, entry) -- left arm up, steadying the shoulder load
	RefreshCarrySpeed(plr) -- speed resync (carry speed bonus removed 2026-08-27)

	--.. anything that displaces the model (death, respawn, resets) ends the
	--.. carry; the cucumber is lost. Swaps/drops clear Carrying first, so the
	--.. identity check keeps this from firing on them.
	carryModel.AncestryChanged:Connect(function(_, parent)
		local current = Carrying[plr]
		if not current or current.Model ~= carryModel then return end
		if parent == plr.Character then return end
		Carrying[plr] = nil
		RestoreArmPose(current)
		if plr.Parent == Players then
			plr:SetAttribute("CarryingCucumber", nil)
			plr:SetAttribute("CarryingCucumberValue", nil)
			RefreshCarrySpeed(plr)
		end
		if carryModel.Parent then
			task.defer(function() carryModel:Destroy() end)
		end
	end)
	return true
end

--.. Called from BreakablesService.Break (before RecycleBreakable, so the
--.. live visual can still be cloned). `data` is the breakable registry entry.
function CarryService.TryAwardFromBreak(part, data)
	local plr = data.LastAttacker
	if not plr or plr.Parent ~= Players then return end

	--.. dropping rebuilds from the type's Template, so template types only
	--.. (that is every regular breakable in every biome today)
	if not data.Type.Template then return end

	--.. mid-tutorial players keep their focus: no carries until the basics
	--.. land -- EXCEPT the tutorial's own bank arc: TutorialProgressServer
	--.. arms TutorialCarryPending for a guaranteed first catch (server-set
	--.. only; consumed on award below, and it also skips the odds roll)
	local wantTutorialCarry = plr:GetAttribute("TutorialCarryPending") == true
	local pd = plr:FindFirstChild("PlayerData")
	local done = pd and pd:FindFirstChild("DoneTutorial")
	--.. already-carrying players keep the rarer-swap path even mid-tutorial:
	--.. the tutorial banner promises it, so it has to actually work there
	if done and done.Value ~= true and not wantTutorialCarry and not Carrying[plr] then return end

	local BreakablesService = ServerController.GetModule("BreakablesService")
	local rarity = BreakablesService.CarryRarityOf(data)

	--.. already carrying: only a STRICTLY rarer cucumber may replace it
	local current = Carrying[plr]
	local upgrading = false
	if current then
		if rarity >= current.Rarity then return end
		upgrading = true
	end

	--.. 100% CATCH MODE (2026-08-27, user call): every break you land goes
	--.. straight onto your arm -- the odds rolls (ChanceFor weight scaling +
	--.. golden halving, and the tutorial's tiered first-catch roll) are
	--.. BYPASSED here, not removed; ChanceFor is now unused but kept for
	--.. the revert (display math uses spawn share alone). The rarer swap gate
	--.. above still refuses downgrades while carrying. Pre-change module:
	--.. ServerStorage.CarryOddsBackup_2026_08_27 (README has revert steps).

	local src = data.Holder or part
	local model = BuildCarryModel(src)
	if not model then return end

	local displayName = data.Type.Name or "Cucumber"
	--.. mutation rides along separately so vault billboards can show it on
	--.. its own line ("CHARGED" for lightning rolls, else the mutation name)
	local mutation = data.Mutation or (data.Lightning and "CHARGED") or nil
	local fullName = (mutation and (mutation .. " ") or "") .. displayName
	if GiveCarry(plr, model, {Zone = data.Zone; TypeDef = data.Type; Name = displayName; Rarity = rarity; Mutation = mutation; Rate = EarnRateOf(data);}) then
		if wantTutorialCarry then plr:SetAttribute("TutorialCarryPending", nil) end
		--.. center-screen showcase (CarryShowcaseClient) replaced the old green
		--.. Notif toasts for grabs AND rarity swaps (2026-08-26). OneIn is the
		--.. cucumber's spawn share (CarryRarityOf) alone -- in 100% catch mode
		--.. the catch itself is certain (was: spawn share x ChanceFor).
		local combined = math.clamp(rarity, 1e-9, 1)
		Network:FireClient(plr, "CarryShowcase", {
			Name = fullName;
			Upgraded = upgrading;
			OneIn = math.max(1, math.floor(1 / combined + 0.5));
			Position = part.Position; -- break point: the client arcs a pickup mote from here to the arm
		})
	else
		model:Destroy()
	end
end

--.. BOSS TROPHY (2026-08-27): a DEFEATED boss's cucumber goes to its top
--.. damager -- guaranteed (no odds roll), replacing any current carry the
--.. way a rarer swap would. Called only from BreakablesService.Break's boss
--.. block, so it can never fire for an escaped/despawned boss (that path
--.. never calls Break). The visual is the same procedural boss body the
--.. vault-restore path rebuilds (BuildBossVisual), so the trophy looks
--.. identical before and after a rejoin. Rate: base 8 (double a tree) x the
--.. usual 1.6^ biome-tier ladder; upgrades stack on top like any cucumber.
function CarryService.AwardBossTrophy(plr, part, data)
	if not plr or plr.Parent ~= Players then return false end
	--.. mid-tutorial players keep their focus, same rule as organic catches
	local pd = plr:FindFirstChild("PlayerData")
	local done = pd and pd:FindFirstChild("DoneTutorial")
	if done and done.Value ~= true then return false end

	local src
	pcall(function()
		src = ServerController.GetModule("BreakablesService").BuildBossVisual(data.Type)
	end)
	if not src then return false end
	local model = BuildCarryModel(src)
	src:Destroy()
	if not model then return false end

	local displayName = data.Type.Name or "Boss Cucumber"
	local tier = tonumber(ZONE_FIELD_INDEX[data.Zone]) or 1
	local rate = math.max(1, math.floor(8 * (1.6 ^ (tier - 1))))
	local rarity = 1e-4 -- rarer than any organic catch; arms the CarrySparkle too
	if GiveCarry(plr, model, {Zone = data.Zone; TypeDef = data.Type; Name = displayName; Rarity = rarity; Rate = rate;}) then
		Network:FireClient(plr, "CarryShowcase", {
			Name = displayName;
			Upgraded = false;
			OneIn = math.floor(1 / rarity + 0.5);
			Position = part and part.Position or nil;
		})
		return true
	end
	model:Destroy()
	return false
end

--.. ===== Vault interop (VaultService / CucumberBank, 2026-08-25) =====

function CarryService.Get(plr)
	return Carrying[plr]
end

--.. VAULT UPGRADES (2026-08-26): money/sec = base rate x 1.18^(level-1).
--.. Level rides in the record (default 1) so it survives take-back, replace,
--.. relayouts, and even the vendor sale price. Returns a FLOAT so low-rate
--.. cucumbers still visibly grow per level; callers floor at pay time.
function CarryService.EffectiveRate(record)
	local rate = (record.Rate or 1) * 1.18 ^ ((record.Level or 1) - 1)
	--.. FROZEN runs cold (2026-08-27): 0.8x everywhere the record earns or is
	--.. valued -- the tradeoff for being theft-proof on the vault podium
	if record.Mutation == "FROZEN" then rate *= 0.8 end
	return rate
end

--.. a cucumber's coin worth (~4 minutes of its earn rate): the green number
--.. on vault display cards, and the vendor's payout for a carried sale
function CarryService.ValueOf(record)
	return math.floor(CarryService.EffectiveRate(record) * 250)
end

--.. Vault persistence (2026-08-26): rebuild a display model for a SAVED
--.. vault cucumber from its type's template -- same strip/weld/shrink
--.. treatment as an organic catch, so restored cucumbers look the part.
function CarryService.BuildFromTemplate(typeDef)
	if type(typeDef) ~= "table" then return nil end
	--.. boss trophies (2026-08-27) have no template model: rebuild the same
	--.. procedural boss body AwardBossTrophy carved the original from
	if typeDef.Boss then
		local src
		pcall(function()
			src = ServerController.GetModule("BreakablesService").BuildBossVisual(typeDef)
		end)
		if not src then return nil end
		local model = BuildCarryModel(src)
		src:Destroy()
		return model
	end
	if not typeDef.Template then return nil end
	local templates = game:GetService("ServerStorage"):FindFirstChild("Assets")
	templates = templates and templates:FindFirstChild("BreakableModels")
	local src = templates and templates:FindFirstChild(typeDef.Template)
	if not src then return nil end
	return BuildCarryModel(src)
end

--.. Detach the carried model from the arm and hand it (plus its meta) to the
--.. caller. The caller owns re-parenting; nothing is destroyed here.
function CarryService.Take(plr)
	local entry = Carrying[plr]
	if not entry then return nil end
	Carrying[plr] = nil
	RestoreArmPose(entry)
	if plr.Parent == Players then
		plr:SetAttribute("CarryingCucumber", nil)
		plr:SetAttribute("CarryingCucumberValue", nil)
		RefreshCarrySpeed(plr)
	end
	local model = entry.Model
	if not (model and model.Parent) then return nil end
	local primary = model.PrimaryPart
	if primary then
		for _, w in ipairs(primary:GetChildren()) do
			if w:IsA("WeldConstraint") then w:Destroy() end
		end
	end
	model.Parent = nil
	return {Model = model; Zone = entry.Zone; TypeDef = entry.TypeDef; Name = entry.Name; Rarity = entry.Rarity; Mutation = entry.Mutation; Rate = entry.Rate; Level = entry.Level;}
end

--.. Put a previously Taken model back on the player's arm.
function CarryService.Restore(plr, model, meta)
	if Carrying[plr] then return false end
	for _, obj in ipairs(model:GetDescendants()) do
		if obj:IsA("BasePart") then obj.Anchored = false end
	end
	return GiveCarry(plr, model, meta)
end

function CarryService.Drop(Player)
	local entry = Carrying[Player]
	if not entry then return end
	local char = Player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	local BreakablesService = ServerController.GetModule("BreakablesService")

	local groundPos
	local sentHome = false
	if InZoneField(entry.Zone, hrp.Position) then
		--.. standing in the cucumber's own field: it lands right at your feet
		local rp = RaycastParams.new()
		rp.FilterType = Enum.RaycastFilterType.Exclude
		rp.FilterDescendantsInstances = {char, workspace:FindFirstChild("Breakables")}
		local hit = workspace:Raycast(hrp.Position, Vector3.new(0, -30, 0), rp)
		groundPos = hit and hit.Position or (hrp.Position - Vector3.new(0, 3, 0))
	else
		--.. anywhere else: no scolding -- the cucumber just flies home to a
		--.. random spot in the field it was grabbed from
		local ok, point = pcall(BreakablesService.RandomZonePoint, entry.Zone)
		if ok and typeof(point) == "Vector3" then
			groundPos = point
			sentHome = true
		end
	end
	if not groundPos then return end

	--.. back to being a normal cucumber: full HP, HP bar, original size
	if not BreakablesService.SpawnCarriedAt(entry.Zone, entry.TypeDef, groundPos) then
		return -- template missing (should not happen): keep carrying rather than eat it
	end

	--.. drop feedback (SFX pass 2026-08-26): the dropping player's client plays
	--.. replant dirt / fly-home whistle + comet off this (same FireClient shape
	--.. as the CarryShowcase event above)
	Network:FireClient(Player, "CarryFX", {
		Kind = sentHome and "FlyHome" or "Replant";
		Position = groundPos;
		Zone = entry.Zone;
	})

	if sentHome then
		Network:FireClient(Player, "Notif", {
			Message = ("\u{1F952} SENT THE %s HOME!"):format(string.upper(entry.Name), string.upper(entry.Zone));
			Type = "Success";
		})
	end
	ClearCarry(Player)
end

function CarryService.Initialize()
	Network:BindEvents({
		DropCucumber = function(Player)
			CarryService.Drop(Player)
		end,
	})

	Players.PlayerRemoving:Connect(function(plr)
		Carrying[plr] = nil
	end)
end

return CarryService
