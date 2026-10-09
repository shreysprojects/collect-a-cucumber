-- WP-COMBAT config tests (2026-09-22): PetCombatService reads TIMING.COMBAT_SCAN / FX.MUZZLE_HEIGHT from
-- ReplicatedStorage.Modules.PetBalance when present, and falls back to 0.2 / 1.5 on a missing, erroring or
-- garbage module. The module chunk runs in a sandbox (fake game/require via setfenv): no instances, no DataModel reads.
-- Run: return loadstring(game:GetService("HttpService"):GetAsync("http://127.0.0.1:8795/WP-COMBAT_config.lua"))()
local HttpService = game:GetService("HttpService")
local src = HttpService:GetAsync("http://127.0.0.1:8793/ServerStorage.PetCombatService.lua")

local pass, fail, failures = 0, 0, {}
local function check(name, cond, detail)
	if cond then
		pass += 1
	else
		fail += 1
		if #failures < 10 then table.insert(failures, name .. (detail ~= nil and (" [" .. tostring(detail) .. "]") or "")) end
	end
end

-- balance: a table (require result), "missing" (no ModuleScript), or "error" (require throws)
local function LoadWith(balance)
	local marker = {}
	local modules = {FindFirstChild = function(_, name) if name == "PetBalance" and balance ~= "missing" then return marker end return nil end}
	local services = {
		ReplicatedStorage = {FindFirstChild = function(_, name) if name == "Modules" then return modules end return nil end},
		ServerStorage = {}, RunService = {},
	}
	local fakeGame = {GetService = function(_, name) return services[name] end}
	local fakeRequire = function(module)
		if module ~= marker then error("unexpected require") end
		if balance == "error" then error("PetBalance broke") end
		return balance
	end
	local chunk, err = loadstring(src)
	if not chunk then return nil, err end
	local env = setmetatable({game = fakeGame, require = fakeRequire}, {__index = getfenv()})
	setfenv(chunk, env)
	local ok, result = pcall(chunk)
	if not ok then return nil, result end
	return result
end

local M1 = LoadWith({TIMING = {COMBAT_SCAN = 0.25}, FX = {MUZZLE_HEIGHT = 2}})
check("balance present: scan", M1 and M1.Core.SCAN == 0.25, M1 and M1.Core.SCAN)
check("balance present: muzzle", M1 and M1.Core.MUZZLE_HEIGHT == 2, M1 and M1.Core.MUZZLE_HEIGHT)

local M2 = LoadWith("missing")
check("balance missing: defaults", M2 and M2.Core.SCAN == 0.2 and M2.Core.MUZZLE_HEIGHT == 1.5)

local M3 = LoadWith("error")
check("balance require error: defaults", M3 and M3.Core.SCAN == 0.2 and M3.Core.MUZZLE_HEIGHT == 1.5)

local M4 = LoadWith({TIMING = {COMBAT_SCAN = 0 / 0}, FX = {MUZZLE_HEIGHT = math.huge}})
check("balance garbage numbers: defaults", M4 and M4.Core.SCAN == 0.2 and M4.Core.MUZZLE_HEIGHT == 1.5)

local M5 = LoadWith({TIMING = {COMBAT_SCAN = -1}, FX = "nope"})
check("balance negative scan / non-table FX: defaults", M5 and M5.Core.SCAN == 0.2 and M5.Core.MUZZLE_HEIGHT == 1.5)

local M6 = LoadWith({})
check("balance empty table: defaults", M6 and M6.Core.SCAN == 0.2 and M6.Core.MUZZLE_HEIGHT == 1.5)

-- the Shot origin follows the configured muzzle height
if M1 then
	local event, from = M1.Core.ShotEvent({PetId = "P", Stats = {Rarity = "Mythical"}}, {Model = {}, Position = Vector3.new(5, 3, 0)}, 24.3, Vector3.new(0, 10, 0))
	check("shot origin uses PetBalance muzzle", from == Vector3.new(0, 12, 0) and event.From == from and event.Rarity == "Mythical")
	local event2 = M1.Core.ShotEvent({PetId = "P"}, {Model = {}, Position = Vector3.new(5, 3, 0)}, 3, Vector3.new(0, 0, 0))
	check("shot rarity fallback", event2.Rarity == "Common")
end

-- require-time purity: loading the module did not touch ServerStorage / RunService (fakes are empty tables)
check("no side effects at require time", M1 ~= nil and M2 ~= nil)

return ("WP-COMBAT config: PASS %d / FAIL %d%s"):format(pass, fail, fail > 0 and (": " .. table.concat(failures, "; ")) or "")
