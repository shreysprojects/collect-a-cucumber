--..Services..--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

--..Modules..--
local ServerController = require(ServerStorage.ServerController)
local ControllerLoader = require(ReplicatedStorage.Modules.ControllerLoader)

local ProfileService = ServerController.GetModule("ProfileService")
local Network = ControllerLoader.GetController("Network")
local NumberController = ControllerLoader.GetController("NumberController")

--..Config..--
local BASE_COST = 100000 -- cucumbers for rebirth 1
local COST_GROWTH = 3.5 -- gentler than x5: each rebirth lands ~1-3h at its tier
local BONUS_PER_REBIRTH = 0.5 -- +50% CUCUMBERS + SELL VALUE per rebirth (nothing else)
local MAX_REBIRTHS = 50 -- hard cap (2026-08-26): the vault tower tops out at floor 5 here

--..Variables..--
local RebirthService = {}

local Debounce = {}

--..Functions..--

function RebirthService.CostOf(rebirths)
	return BASE_COST * COST_GROWTH ^ rebirths
end

function RebirthService.TryRebirth(Player)
	if Debounce[Player] then return end
	Debounce[Player] = true
	task.delay(2, function() Debounce[Player] = nil end)

	local profile = ProfileService.GetUserData(Player)
	if not profile then return end

	if (profile.Rebirths or 0) >= MAX_REBIRTHS then
		Network:FireClient(Player, "Notif", {Message = ("\u{2B50} MAX REBIRTH!"):format(MAX_REBIRTHS); Type = "Error";})
		return
	end

	--.. COINS economy (2026-08-26): rebirths are priced in COINS now — cucumbers
	--.. only buy vault cucumber upgrades. leaderstats stays the source of truth.
	local coins = (Player.leaderstats and Player.leaderstats:FindFirstChild("Coins") and Player.leaderstats.Coins.Value) or (profile.Stats.Coins or 0)

	local cost = RebirthService.CostOf(profile.Rebirths or 0)
	if coins < cost then
		Network:FireClient(Player, "Notif", {Message = ("NOT ENOUGH COINS!"):format(NumberController.SuffixNumber(cost), NumberController.SuffixNumber(math.floor(coins))); Type = "Error";})
		return
	end

	local CurrencyHandler = ServerController.GetModule("CurrencyHandler")
	--.. THE PRICE OF A REBIRTH IS EXACTLY THREE THINGS: cucumbers, coins, and every
	--.. unlocked zone. Nothing else. This matches the Rebirth panel's own promise
	--.. ("YOU KEEP: PICKAXES / PETS / SHARDS", "YOU LOSE: Cukes / COINS / BIOMES").
	--..
	--.. Until 2026-08-05 this function ALSO wiped the entire owned-pickaxe list, the
	--.. equipped pickaxe, the shop's BuyAmount gate, Stats.Radius and the "Faster
	--.. walkspeed" upgrade -- none of which the panel ever warned about. Those writes
	--.. are gone. If you are tempted to restore any of them, change the panel first.
	--..
	--.. Pickaxes need no restore logic here: PickaxeService.CharacterJoined re-grants the
	--.. equipped pickaxe from the live profile on the LoadCharacter() below.
	profile.Rebirths = (profile.Rebirths or 0) + 1
	--.. Analytics (2026-08-22): ZoneProgression step 3 on the first rebirth (the
	--.. mid-game commitment moment), plus the RebirthDepth one-time funnel on every
	--.. rebirth up to 8 -- prestige depth is the cleanest long-term retention proxy
	pcall(function()
		local AS = game:GetService("AnalyticsService")
		if profile.Rebirths == 1 then
			AS:LogFunnelStepEvent(Player, "ZoneProgression", nil, 3, "FirstRebirth")
		end
		local depth = math.min(profile.Rebirths, 8)
		AS:LogFunnelStepEvent(Player, "RebirthDepth", nil, depth, "Rebirth" .. depth)
	end)
	local rebirthStat = Player.leaderstats and Player.leaderstats:FindFirstChild("Rebirths")
	if rebirthStat then rebirthStat.Value = profile.Rebirths end
	CurrencyHandler.SetCurrency({Player = Player; Currency = "Cucumbers"; Amount = 0;})
	CurrencyHandler.SetCurrency({Player = Player; Currency = "Coins"; Amount = 0;})

	--.. zones -> spawn only
	ProfileService.SetStatToProfile(Player, "DoorData", nil, "Spawn")

	--.. live mirror so nothing waits for a rejoin. ONLY doors: there is no
	--.. instance -> profile writeback for Pickaxes/Doors/Upgrades (only leaderstats is
	--.. mirrored back), so profile writes and mirror writes must always move together.
	--.. Pickaxes and Upgrades are no longer reset in either place.
	local pd = Player:FindFirstChild("PlayerData")
	if pd then
		local doors = pd:FindFirstChild("Doors")
		if doors and doors:FindFirstChild("OwnedString") then doors.OwnedString.Value = "Spawn" end
	end

	--.. pets survive: unequip cleanly (multipliers subtracted), remember, re-equip after respawn
	local EquipService = require(script.Parent.PetService.EquipService)
	local reequip = {}
	for id, tbl in pairs(profile.PetData or {}) do
		if id ~= "Unlocked" and type(tbl) == "table" and tbl.Equipped then
			local ok, res = pcall(EquipService.EquipPet, {Player = Player; PetId = id}) -- toggles OFF
			--.. Queue for re-equip ONLY on a confirmed unequip. EquipPet's unequip
			--.. branch now always does its bookkeeping even when the pet's Model is
			--.. already gone (it dies with the character), so "Unequipped" is the
			--.. normal result; anything else means the pcall itself failed, and we
			--.. skip re-equip so the OnJoin pass can't take the EQUIP branch and add
			--.. that pet's Multi1/Multi2/Damage a second time.
			if ok and res == "Unequipped" then
				reequip[#reequip + 1] = id
			elseif tbl.Equipped then
				warn(("[RebirthService] pet unequip failed for %s (pet %s); skipping re-equip so its multipliers are not double-counted"):format(Player.Name, tostring(id)))
			end
		end
	end

	--.. every zone door comes back (client-sided doors)
	Network:FireClient(Player, "ReplaceDoors")

	Network:FireClient(Player, "Notif", {Message = ("\u{2B50} REBIRTH %d! +%d%% FOREVER!"):format(profile.Rebirths, profile.Rebirths * BONUS_PER_REBIRTH * 100); Type = "Success";})
	Network:FireOtherClients(Player, "Notif", {Message = ("\u{2B50} %s JUST REBIRTHED (x%d)!"):format(string.upper(Player.Name), profile.Rebirths); Type = "Success";})

	--.. respawn back at Spawn (all zones are locked again). The player keeps their
	--.. pickaxe: PickaxeService.CharacterJoined re-grants ToolData.Equipped on the new
	--.. character, and UpgradeService.CharacterJoined re-applies their walkspeed.
	task.wait(0.3)
	Player:LoadCharacter()

	task.spawn(function()
		local char = Player.Character or Player.CharacterAdded:Wait()
		char:WaitForChild("Pets", 10)
		task.wait(1)
		for _,id in ipairs(reequip) do
			pcall(EquipService.EquipPet, {Player = Player; PetId = id; OnJoin = true})
			task.wait()
		end
		RebirthService.UpdateTag(Player)
	end)
end

--.. Playtime-reward "FREE rebirth": +1 rebirth and its permanent bonus with
--.. NO cucumber cost and NO reset/respawn - purely a gift. The next paid
--.. rebirth's cost still scales off the new count (inherent to CostOf).
function RebirthService.GrantFree(Player)
	local profile = ProfileService.GetUserData(Player)
	if not profile then return false end

	if (profile.Rebirths or 0) >= MAX_REBIRTHS then
		Network:FireClient(Player, "Notif", {Message = ("\u{2B50} MAX REBIRTH!"):format(MAX_REBIRTHS); Type = "Error";})
		return false
	end

	profile.Rebirths = (profile.Rebirths or 0) + 1
	--.. same analytics as the paid path: free rebirths count toward both funnels
	pcall(function()
		local AS = game:GetService("AnalyticsService")
		if profile.Rebirths == 1 then
			AS:LogFunnelStepEvent(Player, "ZoneProgression", nil, 3, "FirstRebirth")
		end
		local depth = math.min(profile.Rebirths, 8)
		AS:LogFunnelStepEvent(Player, "RebirthDepth", nil, depth, "Rebirth" .. depth)
	end)
	local rebirthStat = Player.leaderstats and Player.leaderstats:FindFirstChild("Rebirths")
	if rebirthStat then rebirthStat.Value = profile.Rebirths end

	Network:FireClient(Player, "Notif", {Message = ("\u{2B50} FREE REBIRTH! NOW x%d!"):format(profile.Rebirths, profile.Rebirths * BONUS_PER_REBIRTH * 100); Type = "Success";})
	Network:FireOtherClients(Player, "Notif", {Message = ("\u{2B50} %s GOT A FREE REBIRTH (x%d)!"):format(string.upper(Player.Name), profile.Rebirths); Type = "Success";})
	--.. SFX pass 2026-08-26: free rebirths get the SAME client celebration the
	--.. panel's paid path renders locally. ClientNetwork routes "RebirthFX" to
	--.. RebirthNewFrame.PlayCelebration. Payload: {Before = count before grant}.
	Network:FireClient(Player, "RebirthFX", {Before = profile.Rebirths - 1})
	RebirthService.UpdateTag(Player)
	return true
end

function RebirthService.Multiplier(Player)
	local ok, rebirths = pcall(function()
		return ProfileService.GetUserData(Player).Rebirths
	end)
	return 1 + BONUS_PER_REBIRTH * ((ok and rebirths) or 0)
end

function RebirthService.UpdateTag(Player)
	local char = Player.Character
	local head = char and char:FindFirstChild("Head")
	local tag = head and head:FindFirstChild("Tag")
	local frame = tag and tag:FindFirstChild("Frame")
	local nameLabel = frame and frame:FindFirstChild("PlayerName")
	if not nameLabel then return end

	local profile = ProfileService.GetUserData(Player)
	local rebirths = profile and profile.Rebirths or 0

	--.. legacy cleanup: rebirths used to be appended to the name text as " ⭐N";
	--.. they now live in the RebirthBadge (icon + count) under the name
	nameLabel.Text = string.gsub(nameLabel.Text, " ?\u{2B50}%d*$", "")

	local badge = frame:FindFirstChild("RebirthBadge")
	if badge then
		local text = tostring(rebirths)
		badge.RebirthCount.Text = text
		--.. size the count box to the digit count so the icon+number pair
		--.. stays visually centered under the name (empty box width would
		--.. drag the UIListLayout centering off to one side)
		badge.RebirthCount.Size = UDim2.new(0.09 * #text, 0, 1, 0)
		badge.Visible = rebirths > 0
	end
end

function RebirthService.CharacterJoined(Character)
	local Player = Players:GetPlayerFromCharacter(Character)
	if not Player then return end
	task.spawn(function()
		local head = Character:WaitForChild("Head", 15)
		if head then head:WaitForChild("Tag", 15) end
		task.wait(1)
		RebirthService.UpdateTag(Player)
	end)
end

function RebirthService.Initialize()
	--.. rebirth lives in the left-side UI now (shrine retired)
	Network:BindFunctions({
		GetRebirthInfo = function(Player)
			local profile = ProfileService.GetUserData(Player)
			if not profile then return nil end
			local rebirths = profile.Rebirths or 0
			local cost = RebirthService.CostOf(rebirths)
			local coins = (Player.leaderstats and Player.leaderstats:FindFirstChild("Coins") and Player.leaderstats.Coins.Value) or (profile.Stats.Coins or 0)
			--.. vault tower numbers for the panel's SLOTS IN VAULT line
			--.. (BankBuilder owns capacity/floor math; pcall so the panel
			--.. never breaks if the vault module is absent)
			local slots, nextSlots, floors, nextFloors = 0, 0, 1, 1
			pcall(function()
				local BankBuilder = require(ServerStorage.ServerController.VaultService.BankBuilder)
				--.. bought "Vault slots" board upgrades count toward the shown totals
				local extra = (profile.Upgrades and profile.Upgrades["Vault slots"]) or 0
				slots = BankBuilder.CapacityFor(rebirths, extra)
				nextSlots = BankBuilder.CapacityFor(rebirths + 1, extra)
				floors = BankBuilder.FloorsFor(slots)
				nextFloors = BankBuilder.FloorsFor(nextSlots)
			end)
			return {
				Rebirths = rebirths;
				Bonus = rebirths * BONUS_PER_REBIRTH * 100;
				NextBonus = (rebirths + 1) * BONUS_PER_REBIRTH * 100;
				Cost = cost;
				Coins = math.floor(coins);
				CanAfford = coins >= cost;
				MaxRebirths = MAX_REBIRTHS;
				AtMax = rebirths >= MAX_REBIRTHS;
				VaultSlots = slots;
				NextVaultSlots = nextSlots;
				VaultFloors = floors;
				NextVaultFloors = nextFloors;
			}
		end,

		DoRebirth = function(Player)
			RebirthService.TryRebirth(Player)
			local profile = ProfileService.GetUserData(Player)
			return profile and profile.Rebirths or 0
		end,
	})

	Players.PlayerRemoving:Connect(function(Player)
		Debounce[Player] = nil
	end)
end

return RebirthService
