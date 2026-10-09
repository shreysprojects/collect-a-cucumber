--[[
	TradeService — pet trading, unlocked at ⭐ 1 rebirth (both sides).
	State-driven: every change re-sends each side their own view of the
	session via the "TradeUpdate" event; the client just renders it.
]]

--..Services..--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

--..Modules..--
local ServerController = require(ServerStorage.ServerController)
local ControllerLoader = require(ReplicatedStorage.Modules.ControllerLoader)

local ProfileService = ServerController.GetModule("ProfileService")
local Network = ControllerLoader.GetController("Network")

--..Config..--
local REBIRTHS_REQUIRED = 1
local MAX_PETS_PER_SIDE = 4

--..Variables..--
local TradeService = {}

local Sessions = {} -- [player] = shared session table
local PendingRequests = {} -- [target] = requester

--..Functions..--

local function RebirthsOf(Player)
	local profile = ProfileService.GetUserData(Player)
	return profile and (profile.Rebirths or 0) or 0
end

local function PetName(Player, id)
	local profile = ProfileService.GetUserData(Player)
	local pet = profile and profile.PetData and profile.PetData[id]
	return pet and pet.Name or "?"
end

local function Tradeable(Player, id)
	local profile = ProfileService.GetUserData(Player)
	local pet = profile and profile.PetData and profile.PetData[id]
	if not pet or type(pet) ~= "table" then return false end
	if pet.Equipped then return false end
	return true
end

local function ViewFor(Player, session)
	if not session then
		local incoming = nil
		for target, requester in pairs(PendingRequests) do
			if target == Player and requester.Parent == Players then
				incoming = requester.Name
			end
		end
		return {State = "Idle"; Incoming = incoming;}
	end
	local partner = (session.A == Player) and session.B or session.A
	local function offerList(plr)
		local list = {}
		for id in pairs(session.Offer[plr]) do
			table.insert(list, {Id = id; Name = PetName(plr, id);})
		end
		return list
	end
	return {
		State = "Active";
		Partner = partner.Name;
		YourOffer = offerList(Player);
		TheirOffer = offerList(partner);
		YouConfirmed = session.Confirmed[Player] == true;
		TheyConfirmed = session.Confirmed[partner] == true;
	}
end

local function Push(Player)
	if Player.Parent == Players then
		Network:FireClient(Player, "TradeUpdate", ViewFor(Player, Sessions[Player]))
	end
end

local function PushBoth(session)
	Push(session.A)
	Push(session.B)
end

local function EndSession(session, reason)
	Sessions[session.A] = nil
	Sessions[session.B] = nil
	for _,plr in ipairs({session.A, session.B}) do
		if plr.Parent == Players then
			if reason then
				Network:FireClient(plr, "Notif", {Message = reason; Type = "Error";})
			end
			Push(plr)
		end
	end
end

local function Execute(session)
	local a, b = session.A, session.B
	local profileA, profileB = ProfileService.GetUserData(a), ProfileService.GetUserData(b)
	if not profileA or not profileB then EndSession(session, "TRADE FAILED: DATA UNAVAILABLE") return end

	--.. re-validate every pet at the moment of truth
	for id in pairs(session.Offer[a]) do
		if not Tradeable(a, id) then EndSession(session, "TRADE CANCELLED: A PET BECAME UNAVAILABLE") return end
	end
	for id in pairs(session.Offer[b]) do
		if not Tradeable(b, id) then EndSession(session, "TRADE CANCELLED: A PET BECAME UNAVAILABLE") return end
	end

	local function transfer(fromPlr, fromProfile, toPlr, toProfile, ids)
		local removed = {}
		local receivedNames = {}
		for id in pairs(ids) do
			local pet = fromProfile.PetData[id]
			fromProfile.PetData[id] = nil
			toProfile.PetData[id] = pet
			if type(pet) == "table" and pet.Name then
				table.insert(receivedNames, pet.Name)
			end
			table.insert(removed, id)
			fromPlr.PlayerData.Pets.Inventory.Value -= 1
			toPlr.PlayerData.Pets.Inventory.Value += 1
			Network:FireClient(toPlr, "AddPet", {Id = id; Table = pet;})
		end
		if #removed > 0 then
			Network:FireClient(fromPlr, "RemovePet", removed)
		end
		if #receivedNames > 0 then
			--.. traded-in pets count as discovered for the receiver (Pet Index)
			ServerController.GetModule("PetService").MarkDiscovered(toPlr, receivedNames)
		end
	end

	transfer(a, profileA, b, profileB, session.Offer[a])
	transfer(b, profileB, a, profileA, session.Offer[b])
	ProfileService.SetStatToProfile(a, "PetData", nil, profileA.PetData)
	ProfileService.SetStatToProfile(b, "PetData", nil, profileB.PetData)

	Sessions[a] = nil
	Sessions[b] = nil
	for _,plr in ipairs({a, b}) do
		Network:FireClient(plr, "Notif", {Message = "\u{1F91D} TRADE COMPLETE!"; Type = "Success";})
		Push(plr)
	end
end

--.. read-only: used by SellVendorServer to refuse pet sales mid-trade. Selling a pet
--.. that is sitting in an open offer makes the partner's panel render it as "?" and
--.. then hard-cancels the trade with "A PET BECAME UNAVAILABLE".
function TradeService.IsTrading(Player)
	return Sessions[Player] ~= nil
end

function TradeService.Initialize()
	Network:BindFunctions({
		GetTradeTargets = function(Player)
			if RebirthsOf(Player) < REBIRTHS_REQUIRED then
				return {Locked = true; Required = REBIRTHS_REQUIRED;}
			end
			local list = {}
			for _,other in ipairs(Players:GetPlayers()) do
				if other ~= Player and RebirthsOf(other) >= REBIRTHS_REQUIRED and not Sessions[other] then
					table.insert(list, {Name = other.Name; Rebirths = RebirthsOf(other);})
				end
			end
			return {Locked = false; Targets = list; View = ViewFor(Player, Sessions[Player]);}
		end,

		RequestTrade = function(Player, targetName)
			if type(targetName) ~= "string" then return "bad target" end
			if RebirthsOf(Player) < REBIRTHS_REQUIRED then return "locked" end
			if Sessions[Player] then return "busy" end
			local target = Players:FindFirstChild(targetName)
			if not target or target == Player then return "gone" end
			if RebirthsOf(target) < REBIRTHS_REQUIRED or Sessions[target] then return "unavailable" end
			PendingRequests[target] = Player
			Network:FireClient(target, "Notif", {Message = ("\u{1F91D} %s WANTS TO TRADE!"):format(string.upper(Player.Name)); Type = "Success";})
			Push(target)
			return "sent"
		end,

		RespondTrade = function(Player, accept)
			local requester = PendingRequests[Player]
			PendingRequests[Player] = nil
			if not accept then Push(Player) return "declined" end
			if not requester or requester.Parent ~= Players then Push(Player) return "gone" end
			if Sessions[requester] or Sessions[Player] then Push(Player) return "busy" end
			local session = {
				A = requester; B = Player;
				Offer = {[requester] = {}, [Player] = {}};
				Confirmed = {};
			}
			Sessions[requester] = session
			Sessions[Player] = session
			PushBoth(session)
			return "accepted"
		end,

		SetTradePet = function(Player, petId, adding)
			local session = Sessions[Player]
			if not session or type(petId) ~= "string" then return end
			if adding then
				local count = 0
				for _ in pairs(session.Offer[Player]) do count += 1 end
				if count >= MAX_PETS_PER_SIDE then return end
				if not Tradeable(Player, petId) then return end
				session.Offer[Player][petId] = true
			else
				session.Offer[Player][petId] = nil
			end
			session.Confirmed = {} -- any change resets both confirmations
			PushBoth(session)
		end,

		ConfirmTrade = function(Player)
			local session = Sessions[Player]
			if not session then return end
			session.Confirmed[Player] = true
			local partner = (session.A == Player) and session.B or session.A
			if session.Confirmed[partner] then
				Execute(session)
				--.. engagement analytics + both sides just had a win worth a like ask
				pcall(function()
					local AS = game:GetService("AnalyticsService")
					for _, p in ipairs({session.A, session.B}) do
						if p and p.Parent then
							AS:LogCustomEvent(p, "TradeCompleted", 1)
							p:SetAttribute("LastEpicWin", os.clock())
						end
					end
				end)
			else
				PushBoth(session)
			end
		end,

		CancelTrade = function(Player)
			local session = Sessions[Player]
			if session then
				EndSession(session, "TRADE CANCELLED")
			elseif PendingRequests[Player] then
				PendingRequests[Player] = nil
				Push(Player)
			end
		end,

		GetTradeablePets = function(Player)
			local profile = ProfileService.GetUserData(Player)
			if not profile or not profile.PetData then return {} end
			local list = {}
			for id, pet in pairs(profile.PetData) do
				if id ~= "Unlocked" and type(pet) == "table" and not pet.Equipped then
					table.insert(list, {Id = id; Name = pet.Name;})
				end
			end
			table.sort(list, function(x, y) return x.Name < y.Name end)
			return list
		end,
	})

	Players.PlayerRemoving:Connect(function(Player)
		PendingRequests[Player] = nil
		for target, requester in pairs(PendingRequests) do
			if requester == Player then PendingRequests[target] = nil Push(target) end
		end
		local session = Sessions[Player]
		if session then
			EndSession(session, "TRADE CANCELLED: PLAYER LEFT")
		end
	end)
end

return TradeService
