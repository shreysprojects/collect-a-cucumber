-- WP-SERVER test helper (2026-09-22): plain-table fakes of the Roblox objects the WP-SERVER Scripts touch, so a
-- Script's source can be run inside a sandbox (setfenv) in a read-only Studio eval. Nothing here creates or
-- parents a real Instance. Loaded by the WP-SERVER_*.lua tests via the loopback server (:8795).
local F = {}

--..Signals..--
function F.Signal()
	local signal = {Conns = {}}
	function signal:Connect(fn)
		local conn = {Fn = fn, Connected = true}
		function conn:Disconnect() self.Connected = false end
		table.insert(self.Conns, conn)
		return conn
	end
	function signal:Fire(...)
		for _, conn in ipairs(self.Conns) do
			if conn.Connected then conn.Fn(...) end
		end
	end
	return signal
end

--..Instances..--
local Methods = {}
local MT = {}
MT.__index = function(self, key)
	if key == "Parent" then return rawget(self, "__parent") end
	local method = Methods[key]
	if method ~= nil then return method end
	for _, child in ipairs(rawget(self, "__children")) do
		if child.Name == key then return child end
	end
	return nil
end
MT.__newindex = function(self, key, value)
	if key == "Parent" then
		local old = rawget(self, "__parent")
		if old then
			local list = rawget(old, "__children")
			for i, child in ipairs(list) do
				if child == self then table.remove(list, i) break end
			end
		end
		rawset(self, "__parent", value)
		if value then table.insert(rawget(value, "__children"), self) end
		return
	end
	rawset(self, key, value)
end
MT.__tostring = function(self) return "Fake" .. rawget(self, "ClassName") .. "(" .. tostring(rawget(self, "Name")) .. ")" end

local ISA = {
	Part = {BasePart = true, Instance = true}, Model = {PVInstance = true, Instance = true},
	Player = {Instance = true}, Folder = {Instance = true}, RemoteEvent = {Instance = true},
	BindableFunction = {Instance = true}, ModuleScript = {LuaSourceContainer = true, Instance = true},
}

function F.Inst(className, name, fields)
	local obj = {ClassName = className, Name = name or className, __children = {}, __attrs = {}, __attrSignals = {}, __parent = nil}
	setmetatable(obj, MT)
	if className == "RemoteEvent" then rawset(obj, "OnServerEvent", F.Signal()) end
	for key, value in pairs(fields or {}) do obj[key] = value end
	return obj
end
function Methods:IsA(className)
	local own = rawget(self, "ClassName")
	return own == className or (ISA[own] and ISA[own][className]) or false
end
function Methods:FindFirstChild(name)
	for _, child in ipairs(rawget(self, "__children")) do
		if child.Name == name then return child end
	end
	return nil
end
function Methods:WaitForChild(name) return self:FindFirstChild(name) end -- never yields
function Methods:GetChildren()
	local list = {}
	for _, child in ipairs(rawget(self, "__children")) do table.insert(list, child) end
	return list
end
function Methods:GetDescendants()
	local list = {}
	local function walk(o) for _, c in ipairs(rawget(o, "__children")) do table.insert(list, c) walk(c) end end
	walk(self)
	return list
end
function Methods:IsDescendantOf(ancestor)
	local node = rawget(self, "__parent")
	while node do
		if node == ancestor then return true end
		node = rawget(node, "__parent")
	end
	return false
end
function Methods:GetAttribute(name) return rawget(self, "__attrs")[name] end
function Methods:GetAttributes() return rawget(self, "__attrs") end
function Methods:GetAttributeChangedSignal(name)
	local signals = rawget(self, "__attrSignals")
	signals[name] = signals[name] or F.Signal()
	return signals[name]
end
function Methods:SetAttribute(name, value)
	local attrs = rawget(self, "__attrs")
	local old = attrs[name]
	attrs[name] = value
	local signal = rawget(self, "__attrSignals")[name]
	if signal and old ~= value then signal:Fire() end
end
function Methods:GetPivot() return rawget(self, "Pivot") or CFrame.new() end
function Methods:Destroy() self.Parent = nil end
function Methods:ClearAllChildren() for _, child in ipairs(self:GetChildren()) do child.Parent = nil end end
function Methods:GetFullName() return tostring(rawget(self, "Name")) end
function Methods:Invoke(...) return rawget(self, "OnInvoke")(...) end -- BindableFunction
function Methods:FireClient(player, ...) -- RemoteEvent
	local log = rawget(self, "Sent") or {}
	rawset(self, "Sent", log)
	table.insert(log, {Player = player, Args = table.pack(...)})
end

--..Module scripts: require(fake) returns fake.__module..--
function F.Module(name, value, parent)
	local module = F.Inst("ModuleScript", name)
	rawset(module, "__module", value)
	if parent then module.Parent = parent end
	return module
end
function F.Require(module)
	if type(module) == "table" and rawget(module, "__module") ~= nil then
		local value = rawget(module, "__module")
		if type(value) == "function" then return value() end -- a throwing module
		return value
	end
	error("fake require: not a fake module: " .. tostring(module))
end

--..CollectionService..--
function F.CollectionService()
	local cs = {Tags = {}, Added = {}, Removed = {}}
	local function list(tag) cs.Tags[tag] = cs.Tags[tag] or {} return cs.Tags[tag] end
	function cs:GetTagged(tag)
		local out = {}
		for _, inst in ipairs(list(tag)) do if inst.Parent ~= nil then table.insert(out, inst) end end
		return out
	end
	function cs:AddTag(inst, tag) table.insert(list(tag), inst) if cs.Added[tag] then cs.Added[tag]:Fire(inst) end end
	function cs:RemoveTag(inst, tag)
		for i, other in ipairs(list(tag)) do if other == inst then table.remove(list(tag), i) break end end
		if cs.Removed[tag] then cs.Removed[tag]:Fire(inst) end
	end
	function cs:HasTag(inst, tag) for _, other in ipairs(list(tag)) do if other == inst then return true end end return false end
	function cs:GetInstanceAddedSignal(tag) cs.Added[tag] = cs.Added[tag] or F.Signal() return cs.Added[tag] end
	function cs:GetInstanceRemovedSignal(tag) cs.Removed[tag] = cs.Removed[tag] or F.Signal() return cs.Removed[tag] end
	return cs
end

--..Players..--
function F.Players()
	local players = F.Inst("Players", "Players")
	rawset(players, "PlayerAdded", F.Signal())
	rawset(players, "PlayerRemoving", F.Signal())
	rawset(players, "GetPlayers", function(self)
		local out = {}
		for _, child in ipairs(self:GetChildren()) do if child:IsA("Player") then table.insert(out, child) end end
		return out
	end)
	rawset(players, "GetPlayerByUserId", function(self, id)
		for _, p in ipairs(self:GetPlayers()) do if p.UserId == id then return p end end
		return nil
	end)
	return players
end
function F.Player(players, userId, name)
	local player = F.Inst("Player", name or ("Player" .. userId), {UserId = userId})
	player.Parent = players
	return player
end

--..task: spawn/defer run now (coroutines); wait >= 10 s suspends (the forever loops), shorter waits return at once..--
function F.Task(log)
	local t = {Delayed = {}, Deferred = {}, Suspended = {}, Errors = {}}
	local function run(fn, ...)
		local co = coroutine.create(fn)
		local ok, err = coroutine.resume(co, ...)
		if not ok then table.insert(t.Errors, tostring(err)) if log then table.insert(log, "TASK ERROR " .. tostring(err)) end end
		if coroutine.status(co) == "suspended" then table.insert(t.Suspended, co) end
		return co
	end
	t.spawn = function(fn, ...) return run(fn, ...) end
	t.defer = function(fn, ...) table.insert(t.Deferred, table.pack(fn, ...)) end
	t.delay = function(seconds, fn, ...) table.insert(t.Delayed, table.pack(fn, ...)) end
	t.wait = function(seconds)
		if (seconds or 0) >= 10 then coroutine.yield() end
		return seconds or 0
	end
	function t.RunDeferred()
		local list = t.Deferred
		t.Deferred = {}
		for _, item in ipairs(list) do run(item[1], table.unpack(item, 2, item.n)) end
		return #list
	end
	function t.RunDelayed()
		local list = t.Delayed
		t.Delayed = {}
		for _, item in ipairs(list) do run(item[1], table.unpack(item, 2, item.n)) end
		return #list
	end
	function t.Resume(co)
		local ok, err = coroutine.resume(co)
		if not ok then table.insert(t.Errors, tostring(err)) end
		return ok, err
	end
	return t
end

--..Sandbox: run a Script's source with a fake environment..--
function F.Run(source, env)
	local fn, err = loadstring(source)
	if not fn then error("compile: " .. tostring(err)) end
	local base = getfenv(1)
	setmetatable(env, {__index = base})
	setfenv(fn, env)
	return fn()
end

--..Logging print / warn..--
function F.Logger()
	local log = {}
	local function join(...)
		local parts = {}
		for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
		return table.concat(parts, " ")
	end
	return log, function(...) table.insert(log, "PRINT " .. join(...)) end, function(...) table.insert(log, "WARN " .. join(...)) end
end
function F.Find(log, pattern)
	for _, line in ipairs(log) do if line:find(pattern, 1, true) then return line end end
	return nil
end

--..Check collector..--
function F.Checker(label)
	local c = {Pass = 0, Fail = 0, Failures = {}}
	function c.Check(name, cond, detail)
		if cond then c.Pass += 1 else
			c.Fail += 1
			if #c.Failures < 10 then table.insert(c.Failures, name .. (detail ~= nil and (" (" .. tostring(detail) .. ")") or "")) end
		end
	end
	function c.Summary()
		return ("%s: PASS %d / FAIL %d%s"):format(label, c.Pass, c.Fail, #c.Failures > 0 and (": " .. table.concat(c.Failures, "; ")) or "")
	end
	return c
end

return F
