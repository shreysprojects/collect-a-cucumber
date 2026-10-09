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
local DAMAGE = 35

local api -- ServerStorage.ZombieAPI, created by ZombieRaidService
task.spawn(function()
	api = ServerStorage:WaitForChild("ZombieAPI", 120)
end)

-- 2026-09-18 (user): the bat no longer swings at biome guardians (the 2026-09-15 GuardianAPI
-- hook is gone; GuardianService's stun system is retired). Zombies only.

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
						if angle <= CONE then damageFn:Invoke(target, DAMAGE, "Bat", attacker) end
					end
				end
			end
		end
		if api then sweep(api.Zombies:Invoke(), api.Damage) end
		--.. 2026-09-18 (user): guardians can no longer be hit - the bat is zombies-only again
	end)
end)
