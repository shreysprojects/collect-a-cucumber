-- WP-WORLDFX effects tests (2026-09-22): PetEffectsClient's pure helpers -- shot travel time, ability
-- arc, camera culling, guard liveness, the projectile budget (FX.MAX_PROJECTILES from src PetBalance),
-- the FxShotAt / FxAimUntil stamp and the proc-toast seconds (+ the toast text via the src PetStats).
-- No instances, nothing written.
local H = game:GetService("HttpService")
local SRC = "http://127.0.0.1:8793/"

local function Fetch(file)
	return (H:GetAsync(SRC .. file):gsub("\r\n", "\n"))
end

local PetBalance = assert(loadstring(Fetch("ReplicatedStorage.Modules.PetBalance.lua")))()
local Core = assert(loadstring(Fetch("StarterPlayer.StarterPlayerScripts.PetEffectsClient.client.lua")))("__core")

local pass, fail, failures = 0, 0, {}
local function Check(name, cond, detail)
	if cond then pass += 1 else
		fail += 1
		if #failures < 8 then table.insert(failures, name .. (detail ~= nil and (" [" .. tostring(detail) .. "]") or "")) end
	end
end
local function Near(a, b, eps) return type(a) == "number" and math.abs(a - b) <= (eps or 1e-6) end
local function NearV(a, b) return typeof(a) == "Vector3" and (a - b).Magnitude <= 1e-6 end

local FX = PetBalance.FX
-- shot travel: distance / 180 clamped to SHOT_TRAVEL_MIN..MAX (0.12..0.2)
Check("travel 26 studs", Near(Core.TravelTime(26, FX.SHOT_TRAVEL_MIN, FX.SHOT_TRAVEL_MAX, 180), 26 / 180), Core.TravelTime(26, FX.SHOT_TRAVEL_MIN, FX.SHOT_TRAVEL_MAX, 180))
Check("travel point blank = min", Near(Core.TravelTime(1, FX.SHOT_TRAVEL_MIN, FX.SHOT_TRAVEL_MAX, 180), 0.12))
Check("travel far = max", Near(Core.TravelTime(100, FX.SHOT_TRAVEL_MIN, FX.SHOT_TRAVEL_MAX, 180), 0.2))
Check("travel NaN = max", Near(Core.TravelTime(0 / 0, 0.12, 0.2, 180), 0.2))
Check("travel bad speed = max", Near(Core.TravelTime(20, 0.12, 0.2, 0), 0.2))
local within = true
for d = 0, 60, 0.5 do
	local t = Core.TravelTime(d, 0.12, 0.2, 180)
	if t < 0.12 or t > 0.2 then within = false end
end
Check("travel always within 0.12..0.2", within)

-- ability arc: endpoints exact, apex = height at k = 0.5, clamped k
local from, to = Vector3.new(0, 1, 0), Vector3.new(10, 3, 0)
Check("arc k=0", NearV(Core.ArcPoint(from, to, 4, 0), from))
Check("arc k=1", NearV(Core.ArcPoint(from, to, 4, 1), to))
Check("arc apex", NearV(Core.ArcPoint(from, to, 4, 0.5), Vector3.new(5, 2 + 4, 0)))
Check("arc clamps k", NearV(Core.ArcPoint(from, to, 4, 1.7), to) and NearV(Core.ArcPoint(from, to, 4, -1), from))

-- culling (FX.RADIUS 180): cull only when every endpoint is beyond the radius
local cam = Vector3.new(0, 0, 0)
Check("RADIUS is 180", FX.RADIUS == 180)
Check("cull both far", Core.ShouldCull(cam, Vector3.new(200, 0, 0), Vector3.new(0, 0, 250), FX.RADIUS) == true)
Check("keep one near", Core.ShouldCull(cam, Vector3.new(200, 0, 0), Vector3.new(0, 0, 100), FX.RADIUS) == false)
Check("keep near from", Core.ShouldCull(cam, Vector3.new(10, 0, 0), nil, FX.RADIUS) == false)
Check("cull single far point", Core.ShouldCull(cam, Vector3.new(0, 181, 0), nil, FX.RADIUS) == true)
Check("no camera keeps", Core.ShouldCull(nil, Vector3.new(999, 0, 0), nil, FX.RADIUS) == false)
Check("no endpoints culled", Core.ShouldCull(cam, nil, nil, FX.RADIUS) == true)

-- guard shell liveness (server clock)
Check("guard live", Core.GuardLive(1240, 1000) == true)
Check("guard expired", Core.GuardLive(999, 1000) == false)
Check("guard at expiry", Core.GuardLive(1000, 1000) == false)
Check("guard garbage", not Core.GuardLive(0 / 0, 1000) and not Core.GuardLive(nil, 1000) and not Core.GuardLive("2000", 1000) and not Core.GuardLive(math.huge, 1000))

-- projectile budget (FX.MAX_PROJECTILES = 64): excess dropped, releases free slots
Check("MAX_PROJECTILES is 64", FX.MAX_PROJECTILES == 64)
local budget = Core.NewBudget(FX.MAX_PROJECTILES)
local n = 0
for _ = 1, 100 do if budget:Take() then n += 1 end end
Check("budget caps at 64", n == 64 and budget.Live == 64 and budget.Dropped == 36, n)
for _ = 1, 10 do budget:Give() end
Check("budget release", budget.Live == 54 and budget:Take() == true)
local empty = Core.NewBudget(1)
empty:Give()
empty:Give()
Check("budget never negative", empty.Live == 0 and empty:Take() and not empty:Take())
Check("budget garbage max", Core.NewBudget(0 / 0):Take() == false and Core.NewBudget(nil):Take() == false)

-- FxShotAt / FxAimUntil: the effect's start (T, or arrival when the batch came late) + AIM_HOLD
local s1, u1 = Core.AimStamp(10, 10.3, 0.6)
Check("aim stamp late batch", Near(s1, 10.3) and Near(u1, 10.9), s1)
local s2, u2 = Core.AimStamp(10.5, 10.3, 0.6)
Check("aim stamp future T", Near(s2, 10.5) and Near(u2, 11.1), s2)
local s3, u3 = Core.AimStamp(0 / 0, 10.3, 0.6)
Check("aim stamp NaN T", Near(s3, 10.3) and Near(u3, 10.9), s3)

-- proc toast seconds = floor(ExpiresAt - T + 0.5)
Check("toast 240", Core.ToastSeconds(1240, 1000) == 240)
Check("toast rounds", Core.ToastSeconds(1089.6, 1000) == 90 and Core.ToastSeconds(1089.4, 1000) == 89)
Check("toast never negative", Core.ToastSeconds(900, 1000) == 0)
Check("toast garbage", Core.ToastSeconds(nil, 1000) == nil and Core.ToastSeconds(1000, 0 / 0) == nil)

-- the owner toast text exactly as PetEffectsClient builds it (src PetStats with PetBalance injected)
local okStats, PetStats = pcall(function()
	local fn = assert(loadstring(Fetch("ReplicatedStorage.Modules.PetStats.lua")))
	local function Fake(name)
		local inst = {Name = name}
		function inst:WaitForChild(child) return Fake(child) end
		function inst:FindFirstChild(child) return Fake(child) end
		return inst
	end
	local modules = {PetBalance = PetBalance, PetsCatalog = require(game:GetService("ReplicatedStorage").Modules.PetsCatalog)}
	local fakeGame = {}
	function fakeGame:GetService(service)
		if service == "ReplicatedStorage" then return Fake("ReplicatedStorage") end
		return game:GetService(service)
	end
	setfenv(fn, setmetatable({game = fakeGame, require = function(t) return assert(modules[t.Name], t.Name) end}, {__index = getfenv(0)}))
	return fn()
end)
if okStats then
	local function Toast(petName, ability, expiresAt, t)
		return PetBalance.TEXT.ProcToast:format(petName, PetBalance.ABILITIES[ability].DisplayName, PetStats.AbilityShort(ability, Core.ToastSeconds(expiresAt, t)))
	end
	local y = Toast("Cat", "Yield", 1090, 1000)
	Check("toast Yield", y == "Cat gave Lucky Harvest to your cucumber - x1.5 for 90s", y)
	local h = Toast("Wolf", "Haste", 1090, 1000)
	Check("toast Haste", h == "Wolf gave Quick Grow to your cucumber - +25% for 90s", h)
	local g = Toast("Dog", "Guard", 1240, 1000)
	Check("toast Guard", g == "Dog gave Leaf Shield to your cucumber - blocks one theft for 240s", g)
else
	Check("PetStats loads", false, PetStats)
end

return ("WP-WORLDFX effects: PASS %d / FAIL %d: %s"):format(pass, fail, table.concat(failures, "; "))
