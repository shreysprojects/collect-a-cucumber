--[[---------------------------------------DESCRIPTION------------------------------------------
	The "2x power!" gift by the present in the lobby: like & favorite the game and join the
	Ricky's Realm group, then claim a permanent PlayerProgress.GIFT_POWER (2x) on coins and XP
	(folded into PlayerProgress.RewardMultiplier).

	Client-callable (ReFunction):
	  GiftStatus(force)   refreshes the group membership (cached GROUP_CACHE seconds unless
	                      force, e.g. right after GroupService:PromptJoinAsync), replicates the
	                      GiftInGroup attribute and answers { Favorited, InGroup, Claimed }.
	  GiftFavorited()     the client reports a favorite (AvatarEditorService confirmed it: no
	                      server API can read favorites); saved on the profile.
	  GiftClaim()         verifies the favorite report and the group membership (fresh check)
	                      and grants the gift once; answers true, or false and a reason.

	Membership: Player:IsInGroupAsync, then GroupService:GetRolesInGroupAsync as a second
	opinion (both cache per peer; a join made through the in-experience prompt clears the
	client's cache, not the server's, so a freshly joined player may need a moment).

--------------------------------------------------------------------------------------------]]--

local GroupService = game:GetService("GroupService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local playerProgress = require(ReplicatedStorage.Assets.Modules.Shared.PlayerProgress)()

local GROUP_CACHE = 20 -- seconds a membership answer is reused without force

local MODULE = {}
local m_api = {}
local m_sapi = {}
local sself = m_sapi

local groupCache = setmetatable({}, { __mode = "k" })
local claiming = setmetatable({}, { __mode = "k" })

function MODULE.new(r_sapi)
	sself = r_sapi
	return m_api, m_sapi
end

local function isMember(player)
	local groupId = playerProgress.GIFT_GROUP_ID
	local ok, inGroup = pcall(function()
		return player:IsInGroupAsync(groupId)
	end)
	if ok and inGroup then
		return true
	end
	local ok2, roles = pcall(function()
		return GroupService:GetRolesInGroupAsync(player.UserId, groupId)
	end)
	if ok2 and type(roles) == "table" and roles.IsMember then
		return true
	end
	return false, (not ok and inGroup) or (not ok2 and roles) or nil
end

function m_sapi:GiftInGroup(player, force)
	local cached = groupCache[player]
	if cached and not force and os.clock() - cached.At < GROUP_CACHE then
		return cached.InGroup
	end
	local inGroup, err = isMember(player)
	if err then
		warn("[SERVER]: Group check for", player.Name, "failed:", err)
	end
	groupCache[player] = { At = os.clock(), InGroup = inGroup }
	if player.Parent then
		player:SetAttribute("GiftInGroup", inGroup)
	end
	return inGroup
end

function m_sapi:ReplicateGift(player)
	local data = sself:GetPlayerProgress(player)
	if not data or not player.Parent then
		return
	end
	player:SetAttribute("GiftFavorited", data.GiftFavorited == true)
	player:SetAttribute("GiftClaimed", data.GiftClaimed == true)
	player:SetAttribute("GiftMultiplier", playerProgress.GiftMultiplier(data))
end

function m_api:GiftStatus(player, force)
	local data = sself:GetPlayerProgress(player)
	if not data then
		return nil
	end
	local inGroup = sself:GiftInGroup(player, force == true)
	sself:ReplicateGift(player)
	return {
		Favorited = data.GiftFavorited == true,
		InGroup = inGroup,
		Claimed = data.GiftClaimed == true,
	}
end

function m_api:GiftFavorited(player)
	local data = sself:GetPlayerProgress(player)
	if not data then
		return false
	end
	if not data.GiftFavorited then
		data.GiftFavorited = true
		data.Dirty = true
		print("[SERVER]:", player.Name, "favorited the game (gift)")
	end
	sself:ReplicateGift(player)
	return true
end

function m_api:GiftClaim(player)
	if not player or claiming[player] then
		return false, "Already claiming"
	end
	local data = sself:GetPlayerProgress(player)
	if not data then
		return false, "Gift failed"
	end
	if data.GiftClaimed then
		return false, "Already claimed"
	end
	if not data.GiftFavorited then
		return false, "Favorite the game first"
	end
	claiming[player] = true
	local inGroup = sself:GiftInGroup(player, true)
	if not inGroup then
		claiming[player] = nil
		sself:ReplicateGift(player)
		return false, "Join " .. playerProgress.GIFT_GROUP_NAME .. " first"
	end

	data.GiftClaimed = true
	data.Dirty = true
	sself:ReplicateGift(player)
	sself:ReplicateProgress(player)
	local ok, err = pcall(function()
		sself:SavePlayerData(player, true)
	end)
	claiming[player] = nil
	if not ok then
		warn("[SERVER]: Gift claim saved in memory, but the save failed:", err)
	end
	print("[SERVER]:", player.Name, "claimed the gift: power x" .. tostring(playerProgress.GIFT_POWER))
	return true
end

return MODULE
