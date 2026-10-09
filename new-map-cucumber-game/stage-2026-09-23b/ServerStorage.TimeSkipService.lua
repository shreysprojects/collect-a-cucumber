--[[
	TimeSkipService  (ModuleScript, ServerStorage)  2026-09-23
	The New Map's TIME SKIP maths, ported from the Zombie Cucumber Game's TimeSkipRateService /
	VaultTimeSkipService (user: "make a time skip system for cash and strength. it should calculate how
	much user is earning per second from cash, and how much they would earn per second if on benchpress").
	One authoritative quote for every consumer: the shop's Robux time-skip cards (live quotes over
	Remotes.TimeSkipQuote), their receipts (ShopProductsServer) and the portal reward spinner
	(RewardSpinnerService), so a card, a spin and a grant can never disagree.

	  CashRate(player)      Cash per second RIGHT NOW = player.Data.CashPerSec, the total IncomeService keeps
	                        (placed cucumbers x their live modifiers + pet income); while IncomeService is
	                        not running it falls back to the sum of the player's placed cucumbers' Rate
	                        attributes. 0 with nothing placed (an honest "nothing to fast-forward").
	  StrengthRate(player)  Strength per second IF the player were on their bench press:
	                        GymService.StrengthPerRep(data) x reps per second, reps per second =
	                        GymService.RepSpeed(data) / CLIP_LENGTH (BenchServer pays one rep per clip loop
	                        of CLIP_LENGTH s at 1x, sped up by the bench tier's RepSpeed). Deterministic on
	                        purpose: the bench level, the worn headband and nothing temporary (a Strength
	                        Potion doubles live reps but never a quote, exactly like the zombie game keeps
	                        friend boosts out of its quotes).
	  Quote(player, seconds) -> {Cash, Strength, CashRate, StrengthRate, Seconds}  (amounts floored)
	  GrantCash(player, seconds) / GrantStrength(player, seconds) -> amount   the ONLY grant paths: quote,
	                        DataService.Increment, RequestSave, a toast through Remotes.ItemEvent
	                        (ItemClient shows "Toast" payloads). A 0 quote grants nothing and says why.
	  FormatCash(n) / FormatStrength(n)   "$2.5M" / "12.3K" (NumberAbbrev)
	  Remotes.TimeSkipQuote (RemoteFunction, made by TimeSkipServer): (seconds) -> Quote(player, seconds)
]]
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local DataService = require(ServerStorage:WaitForChild("DataService"))
local GymService = require(ServerStorage:WaitForChild("GymService"))
local NumberAbbrev = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("NumberAbbrev"))

local M = {}

M.CLIP_LENGTH = 2 -- seconds of the bench-press clip at 1x (BenchServer.CLIP_LENGTH); one rep per loop
M.MAX_SECONDS = 604800 -- a week: the longest skip any product or reward asks for
M.PLACED_TAG = "PlacedCucumber"

local function Finite(x)
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

--.. the player's placed cucumbers' Rate attributes, summed (the fallback when IncomeService is not running)
local function PlacedRate(player)
	local total = 0
	local map = workspace:FindFirstChild("Map")
	local lobby = map and map:FindFirstChild("Lobby")
	local plots = lobby and lobby:FindFirstChild("Plots")
	if not plots then return 0 end
	for _, plot in ipairs(plots:GetChildren()) do
		if plot:GetAttribute("Owner") == player.UserId then
			local placed = plot:FindFirstChild("Placed")
			if placed then
				for _, model in ipairs(placed:GetChildren()) do
					if CollectionService:HasTag(model, M.PLACED_TAG) then
						local rate = tonumber(model:GetAttribute("Rate")) or tonumber(model:GetAttribute("BaseRate")) or 0
						if Finite(rate) and rate > 0 then total += rate end
					end
				end
			end
		end
	end
	return total
end

function M.CashRate(player)
	local data = player:FindFirstChild("Data")
	local value = data and data:FindFirstChild("CashPerSec")
	local rate = value and tonumber(value.Value) or 0
	if not Finite(rate) or rate <= 0 then rate = PlacedRate(player) end
	return math.max(0, rate)
end

function M.StrengthRate(player)
	local data = DataService.GetData(player)
	if not data then return 0 end
	local perRep = tonumber(GymService.StrengthPerRep(data)) or 0
	local speed = tonumber(GymService.RepSpeed(data)) or 1
	local rate = perRep * speed / M.CLIP_LENGTH
	return Finite(rate) and math.max(0, rate) or 0
end

function M.Quote(player, seconds)
	seconds = math.clamp(tonumber(seconds) or 0, 0, M.MAX_SECONDS)
	local cashRate, strengthRate = M.CashRate(player), M.StrengthRate(player)
	return {
		Seconds = seconds,
		CashRate = cashRate,
		StrengthRate = strengthRate,
		Cash = math.max(0, math.floor(cashRate * seconds)),
		Strength = math.max(0, math.floor(strengthRate * seconds)),
	}
end

function M.FormatCash(n)
	return "$" .. NumberAbbrev.Abbrev(math.max(0, math.floor(tonumber(n) or 0)))
end

function M.FormatStrength(n)
	return NumberAbbrev.Abbrev(math.max(0, math.floor(tonumber(n) or 0)))
end

function M.FormatDuration(seconds)
	seconds = math.max(0, math.floor(tonumber(seconds) or 0))
	if seconds >= 86400 and seconds % 86400 == 0 then local d = seconds // 86400 return d == 7 and "1 WEEK" or (d .. (d == 1 and " DAY" or " DAYS")) end
	if seconds >= 3600 and seconds % 3600 == 0 then local h = seconds // 3600 return h .. (h == 1 and " HOUR" or " HOURS") end
	if seconds >= 60 then local m = seconds // 60 return m .. " MIN" end
	return seconds .. " SEC"
end

local function Toast(player, text, style)
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local event = remotes and remotes:FindFirstChild("ItemEvent")
	if event and event:IsA("RemoteEvent") then
		event:FireClient(player, {Kind = "Toast", Text = text, Style = style or "Success"})
	end
end
M.Toast = Toast

--.. the only grant paths: the quote already IS the final amount (no multipliers applied twice)
function M.GrantCash(player, seconds, silent)
	if not DataService.IsLoaded(player) then return 0, "NotLoaded" end
	local quote = M.Quote(player, seconds)
	if quote.Cash <= 0 then
		if not silent then Toast(player, "Place a cucumber first - there is nothing to fast-forward!", "Warn") end
		return 0, "NoIncome"
	end
	if not DataService.Increment(player, "Cash", quote.Cash) then return 0, "IncrementFailed" end
	DataService.RequestSave(player)
	if not silent then Toast(player, ("TIME SKIP: +%s!"):format(M.FormatCash(quote.Cash)), "Success") end
	print(("[TimeSkipService] %s cash skip %s s -> +%d (rate %.2f/s)"):format(player.Name, tostring(seconds), quote.Cash, quote.CashRate))
	return quote.Cash
end

function M.GrantStrength(player, seconds, silent)
	if not DataService.IsLoaded(player) then return 0, "NotLoaded" end
	local quote = M.Quote(player, seconds)
	if quote.Strength <= 0 then
		if not silent then Toast(player, "Nothing to fast-forward!", "Warn") end
		return 0, "NoRate"
	end
	if not DataService.Increment(player, "Strength", quote.Strength) then return 0, "IncrementFailed" end
	DataService.RequestSave(player)
	pcall(GymService.Push, player) -- the gym boards / attributes follow the new total
	if not silent then Toast(player, ("TIME SKIP: +%s STRENGTH!"):format(M.FormatStrength(quote.Strength)), "Success") end
	print(("[TimeSkipService] %s strength skip %s s -> +%d (rate %.2f/s)"):format(player.Name, tostring(seconds), quote.Strength, quote.StrengthRate))
	return quote.Strength
end

--.. GrantCurrency("Cash" | "Strength", ...) for callers that hold the currency name (shop cards, spinner)
function M.Grant(player, currency, seconds, silent)
	if currency == "Strength" then return M.GrantStrength(player, seconds, silent) end
	return M.GrantCash(player, seconds, silent)
end

return M
