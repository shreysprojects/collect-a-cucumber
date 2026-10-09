--[[
	Scarecrow  (ModuleScript, ServerStorage.FunBehaviours)  2026-09-24  fun-builds package GardenLife
	Server half of the scarecrow's crow: it only DECIDES when the crow flies off and comes back, so every client
	flies the same bird (the client half, ReplicatedStorage.FunBehavioursClient.Scarecrow, builds and animates it).
	State (model attributes, server time in seconds):
	  Fun_CrowLeft  when it last took off (0 = never)
	  Fun_CrowBack  when it lands on the perch again (0 = it is sitting there)
	  Fun_CrowDir   the world heading it flew off on, radians: direction = (sin a, 0, cos a)
	A player whose root comes within SCARE_RANGE studs (flat) of Pivot_CrowPerch scares a perched crow (one that
	has sat at least SETTLE s): it flies off away from that player and stays away GONE_MIN..GONE_MAX s. RETURN_LEAD s
	before Fun_CrowBack (just before the clients start its RETURN_T s flight home) it looks again: somebody still
	standing there keeps it away PUSH_MIN..PUSH_MAX s longer. Cosmetic only - no prompts, no economy.
]]

--..Services..--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--..Modules..--
local Kit = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("FunBuildKit"))

--..Config..--
local SCARE_RANGE = 8            -- studs, flat distance root -> perch
local HEIGHT_RANGE = 14          -- ignore players far above / below (a tower next door)
local GONE_MIN, GONE_MAX = 20, 40
local RETURN_T = 2.8             -- the client's flight home (Scarecrow client RETURN_T) - keep in step
local RETURN_LEAD = 3.3          -- decide this long before Fun_CrowBack whether the coast is clear
local PUSH_MIN, PUSH_MAX = 6, 12
local SETTLE = 1                 -- a crow that just landed sits at least this long
local CHECK = 0.2                -- seconds between checks

local B = {}

function B.Server(model, ctx)
	local perch = Kit.Pivot(model, "CrowPerch")
	if not perch then
		local crow = Kit.Part(model, "Crow")
		perch = crow and crow.Position
	end
	if not perch then return end
	local rng = Random.new()
	ctx:SetState("CrowLeft", 0)
	ctx:SetState("CrowBack", 0)
	ctx:SetState("CrowDir", 0)
	local cleared = 0 -- the Fun_CrowBack whose landing has been cleared (nobody near at RETURN_LEAD)

	--.. the closest player root within the scare range, or nil
	local function Nearest()
		local best, bestDist
		for _, player in ipairs(Players:GetPlayers()) do
			local _, root = ctx:HumanoidOf(player)
			if root then
				local d = root.Position - perch
				local flat = Vector3.new(d.X, 0, d.Z).Magnitude
				if flat <= SCARE_RANGE and math.abs(d.Y) <= HEIGHT_RANGE and (not bestDist or flat < bestDist) then
					best, bestDist = root, flat
				end
			end
		end
		return best
	end

	ctx:Every(CHECK, function()
		local now = Kit.Now()
		local back = tonumber(ctx:GetState("CrowBack")) or 0
		if now >= back + SETTLE then
			--..Perched: anybody close?..--
			local root = Nearest()
			if not root then return end
			local away = perch - root.Position
			away = Vector3.new(away.X, 0, away.Z)
			local heading = away.Magnitude > 0.2 and math.atan2(away.X, away.Z) or rng:NextNumber(-math.pi, math.pi)
			ctx:SetState("CrowDir", heading + rng:NextNumber(-0.45, 0.45))
			ctx:SetState("CrowLeft", now)
			ctx:SetState("CrowBack", now + rng:NextNumber(GONE_MIN, GONE_MAX))
		elseif back > now and back ~= cleared and back - now <= RETURN_LEAD then
			--..Away, about to head home: still somebody there? (too late once the flight home has begun)..--
			if back - now > RETURN_T + 0.05 and Nearest() then
				ctx:SetState("CrowBack", back + rng:NextNumber(PUSH_MIN, PUSH_MAX))
			else
				cleared = back
			end
		end
	end)
end

return B
