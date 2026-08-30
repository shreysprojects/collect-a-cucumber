--..Services..--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

--..Modules..--
local ServerController = require(ServerStorage.ServerController)

--..Config..--
local GROUP_ID = 14583228          -- GROUP FRENZY
--.. non-members see the popup this many seconds into EVERY session: late enough
--.. that it clears the loading screen / streak + goal notifs.
local OFFER_DELAY = 60
--.. minimum seconds between walk-up-to-the-group-chest prompts, per player, so
--.. standing on the chest can't spam the popup
local WALKUP_COOLDOWN = 20

--..Variables..--
local GroupOfferService = {}

local PingCounter = {} -- [player] = number, bumped to re-fire the client popup
local LastWalkUp = {}  -- [player] = os.clock() of the last walk-up prompt

--..Functions..--

--.. bump the replicated attribute the client watches -> shows the popup once.
--.. a monotically increasing number guarantees the change signal always fires,
--.. even if the popup was already shown earlier this session.
local function Ping(Player)
	local n = (PingCounter[Player] or 0) + 1
	PingCounter[Player] = n
	Player:SetAttribute("GroupOfferPing", n)
end

--.. exposed for ChestHandler: nudge a non-member to join when they walk into the
--.. group chest. no-op for members / while on cooldown.
function GroupOfferService.PromptJoin(Player)
	if Player:GetAttribute("InGroupFrenzy") ~= false then return end
	local now = os.clock()
	if LastWalkUp[Player] and (now - LastWalkUp[Player]) < WALKUP_COOLDOWN then return end
	LastWalkUp[Player] = now
	Ping(Player)
end

function GroupOfferService.PlayerJoined(Player)
	-- Cache authoritative membership once. If Roblox cannot verify it, suppress
	-- the offer instead of risking showing it to an existing member.
	local ok, result = pcall(function()
		return Player:IsInGroup(GROUP_ID)
	end)
	if not ok then
		Player:SetAttribute("InGroupFrenzy", nil)
		return
	end

	local inGroup = result == true
	Player:SetAttribute("InGroupFrenzy", inGroup)
	if inGroup then return end

	task.delay(OFFER_DELAY, function()
		if not Player.Parent then return end            -- they left first
		if Player:GetAttribute("InGroupFrenzy") ~= false then return end -- member or membership is no longer verified
		Ping(Player)
	end)
end

function GroupOfferService.Initialize()
	--.. the client fires this after the native GroupService:PromptJoinAsync prompt,
	--.. so we can flip the 1.5x cucumber boost on the instant they join (no rejoin needed)
	local remote = ReplicatedStorage:WaitForChild("GroupJoinRemote")
	remote.OnServerEvent:Connect(function(Player, reportedJoined)
		--.. server re-check is authoritative when it resolves; otherwise trust the
		--.. client's PromptJoinAsync result. joining a community is free, so this perk
		--.. is intentionally low-stakes (per Roblox's own group-join reward guidance).
		local ok, inGroup = pcall(function() return Player:IsInGroup(GROUP_ID) end)
		if (ok and inGroup) or reportedJoined == true then
			Player:SetAttribute("InGroupFrenzy", true)
		end
	end)

	Players.PlayerRemoving:Connect(function(Player)
		PingCounter[Player] = nil
		LastWalkUp[Player] = nil
	end)
end

return GroupOfferService
