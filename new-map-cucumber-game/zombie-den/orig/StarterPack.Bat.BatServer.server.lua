--[[
	BatServer  (Script inside StarterPack.Bat)  2026-09-10
	Swing: Tool.Activated (fires on the server) drops a "toolanim" = "Slash" StringValue into the tool,
	which the character's default Animate script turns into the R15 tool slash, plus a swing whoosh.
	Hit: HIT_DELAY later every live zombie (ServerStorage.ZombieAPI.Zombies) whose root is within RANGE
	of the character and inside a CONE in front of it takes DAMAGE (ZombieAPI.Damage, which also
	flashes it red, plays the crunch, and stuns it for a moment). One swing per COOLDOWN.
	The swinging Player goes along as the attacker: the first hit turns that zombie's raid hostile to
	them (ZombieRaidService HOSTILITY - stand in a hostile zombie's way and it knocks you back).
	Zombies only exist during the night raid, so outside it the bat just swings.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local tool = script.Parent
local handle = tool:WaitForChild("Handle")
local SoundController = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("SoundController"))

local COOLDOWN = 0.55
local HIT_DELAY = 0.18
local RANGE = 8
local CONE = math.rad(65)
local DAMAGE = 35 -- at Desert strength (DAMAGE_STRENGTH); x3 per tenfold of strength above it (2026-09-23 economy: zombies gain x3 HP per level)
local DAMAGE_STRENGTH = 300
local DataService = require(ServerStorage:WaitForChild("DataService"))
local function DamageFor(player)
	local strength = player and tonumber(DataService.Get(player, "Strength")) or 0
	local decades = math.max(0, math.log10(math.max(1, strength) / DAMAGE_STRENGTH))
	return math.floor(DAMAGE * 3 ^ decades + 0.5)
end

local api -- ServerStorage.ZombieAPI, created by ZombieRaidService
task.spawn(function()
	api = ServerStorage:WaitForChild("ZombieAPI", 120)
end)

-- 2026-09-18 (user): the bat no longer swings at biome guardians (the 2026-09-15 GuardianAPI
-- hook is gone; GuardianService's stun system is retired). Zombies only.

-- 2026-09-23 (user): PVP IN THE BIOMES. A swing also hits other players in the same arc when BOTH of you stand
-- inside the biome lane (the NightBarrier footprint + PVP_MARGIN; the lobby is safe): a PVP_DISTANCE knockback
-- through the ZombieRaid remote (the same flight zombies and guardians use, Silent, no damage) and the cucumber
-- they are carrying drops where they stand (CucumberCarryAPI.DropAtFeet, like a guardian catch). One hit per
-- victim per PVP_COOLDOWN.
local PVP_DISTANCE = 12
local PVP_SECONDS = 0.4
local PVP_COOLDOWN = 1.2
local PVP_MARGIN = 20
local zombieRemote, dropAtFeet, lane
task.spawn(function()
	local remotes = ReplicatedStorage:WaitForChild("Remotes", 60)
	zombieRemote = remotes and remotes:WaitForChild("ZombieRaid", 60)
	local carryApi = ServerStorage:WaitForChild("CucumberCarryAPI", 60)
	dropAtFeet = carryApi and carryApi:WaitForChild("DropAtFeet", 60)
	local map = workspace:WaitForChild("Map", 60)
	local borders = map and map:WaitForChild("Borders", 60)
	local barrier = borders and borders:WaitForChild("NightBarrier", 60)
	local fill
	for _, part in ipairs(barrier and barrier:GetDescendants() or {}) do
		if part:IsA("BasePart") and (not fill or part.Size.X * part.Size.Y * part.Size.Z > fill.Size.X * fill.Size.Y * fill.Size.Z) then fill = part end
	end
	if fill then lane = {X = fill.Position.X, Z = fill.Position.Z, HalfX = fill.Size.X * 0.5 + PVP_MARGIN, HalfZ = fill.Size.Z * 0.5 + PVP_MARGIN} end
end)
local function inBiomes(position)
	return lane ~= nil and math.abs(position.X - lane.X) <= lane.HalfX and math.abs(position.Z - lane.Z) <= lane.HalfZ
end
local lastPvpHit = setmetatable({}, {__mode = "k"})
local function sweepPlayers(attacker, origin, look)
	if not (attacker and inBiomes(origin)) then return end
	local t = os.clock()
	for _, other in ipairs(Players:GetPlayers()) do
		local oc = other ~= attacker and other.Character
		local oroot = oc and oc:FindFirstChild("HumanoidRootPart")
		local ohum = oc and oc:FindFirstChildOfClass("Humanoid")
		if oroot and ohum and ohum.Health > 0 and inBiomes(oroot.Position) and t - (lastPvpHit[other] or 0) >= PVP_COOLDOWN then
			local offset = oroot.Position - origin
			local flat = Vector3.new(offset.X, 0, offset.Z)
			local dist = flat.Magnitude
			if dist <= RANGE and math.abs(offset.Y) < 7 then
				local angle = dist < 1.5 and 0 or math.acos(math.clamp(flat.Unit:Dot(look), -1, 1))
				if angle <= CONE then
					lastPvpHit[other] = t
					local dir = dist > 0.1 and flat.Unit or look
					if zombieRemote then
						zombieRemote:FireClient(other, {Kind = "Hit", Zombie = attacker.Name, Direction = dir, Silent = true,
							Distance = PVP_DISTANCE, Seconds = PVP_SECONDS, Damage = 0})
					end
					if dropAtFeet and other:GetAttribute("CarryingCucumber") then pcall(dropAtFeet.Invoke, dropAtFeet, other) end
					SoundController.PlayFXAt("Big Thud", oroot.Position, {Volume = 0.7, RollOff = 50})
				end
			end
		end
	end
end

local lastSwing = 0
tool.Activated:Connect(function()
	local now = os.clock()
	if now - lastSwing < COOLDOWN then return end
	local character = tool.Parent
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (humanoid and root) or humanoid.Health <= 0 then return end
	lastSwing = now
	local anim = Instance.new("StringValue")
	anim.Name = "toolanim"
	anim.Value = "Slash"
	anim.Parent = tool
	SoundController.PlayFXAt("Air Slice", handle.Position, {Volume = 0.6, RollOff = 40})
	task.delay(HIT_DELAY, function()
		if tool.Parent ~= character then return end
		local attacker = Players:GetPlayerFromCharacter(character)
		local damage = DamageFor(attacker)
		local origin = root.Position
		local look = root.CFrame.LookVector
		--.. everything swingable: the night raid's zombies (ZombieAPI.Zombies + Damage)
		local function sweep(targets, damageFn)
			for _, target in ipairs(targets or {}) do
				local troot = target:FindFirstChild("HumanoidRootPart")
				if troot then
					local offset = troot.Position - origin
					local flat = Vector3.new(offset.X, 0, offset.Z)
					local reach = RANGE + math.max(0, troot.Size.X - 2)
					local dist = flat.Magnitude
					if dist <= reach and math.abs(offset.Y) < 7 then
						local angle = dist < 1.5 and 0 or math.acos(math.clamp(flat.Unit:Dot(look), -1, 1))
						if angle <= CONE then damageFn:Invoke(target, damage, "Bat", attacker) end
					end
				end
			end
		end
		if api then sweep(api.Zombies:Invoke(), api.Damage) end
		--.. 2026-09-18 (user): guardians can no longer be hit - the bat is zombies-only again
		sweepPlayers(attacker, origin, look) -- 2026-09-23: PvP inside the biomes
	end)
end)
