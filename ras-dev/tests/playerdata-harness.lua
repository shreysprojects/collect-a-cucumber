-- Mock harness for SERV_PlayerData + SERV_PlayerEvents (edit peer, plugin context).
-- Runs the given sources with fake DataStoreService / Players / RunService /
-- TeleportService / MountainPlaces; nothing touches the real DataStore or place.
local Http = game:GetService("HttpService")
local BASE = "http://127.0.0.1:18794/"

local function fetch(name)
	return (Http:GetAsync(BASE .. name, true):gsub("\r\n", "\n"))
end

local function deepcopy(v)
	if type(v) ~= "table" then
		return v
	end
	local t = {}
	for k, x in v do
		t[k] = deepcopy(x)
	end
	return t
end

local function newStore()
	local S = { data = {}, writes = {}, getFails = 0, getDelay = 0, updDelay = 0, getCalls = 0, updCalls = 0 }
	function S:GetAsync(key)
		self.getCalls += 1
		if self.getDelay > 0 then
			task.wait(self.getDelay)
		end
		if self.getFails > 0 then
			self.getFails -= 1
			error("fake GetAsync failure")
		end
		return deepcopy(self.data[key])
	end
	function S:UpdateAsync(key, fn)
		self.updCalls += 1
		if self.updDelay > 0 then
			task.wait(self.updDelay)
		end
		local new = fn(deepcopy(self.data[key]))
		if new ~= nil then
			self.data[key] = deepcopy(new)
			table.insert(self.writes, new.Coins)
		end
		return new
	end
	return S
end

local function savedProfile()
	return {
		Level = 10, XP = 5, Coins = 5000, TotalCoinsCollected = 9000, TotalDistanceRolled = 7000,
		UnlockedMountains = { "Frostpeak" }, UnlockedSnowballs = { "Classic", "Rocky" },
		UnlockedLaunchers = { "Wooden Shovel" }, EquippedSnowball = "Rocky",
		EquippedLauncher = "Wooden Shovel", Rebirths = 1,
	}
end

local function fakePlayer(name, userId)
	local p = { Name = name, UserId = userId, Parent = true }
	function p:Kick(msg)
		self.Kicked = msg
	end
	return p
end

local function fakeMountains(current)
	return {
		START_MOUNTAIN = "Frostpeak",
		GetCurrentMountainId = function() return current end,
		GetPlaceId = function() return 123, "Test" end,
		NormalizeMountainId = function(x) return x end,
	}
end

local function build(src, opts)
	opts.log = {}
	opts.teleports = {}
	opts.players = opts.players or {}
	opts.mountainPlaces = opts.mountainPlaces or fakeMountains("Frostpeak")
	local services = {
		DataStoreService = { GetDataStore = function() return opts.store end },
		RunService = { IsStudio = function() return opts.studio end },
		Players = {
			GetPlayers = function() return opts.players end,
			GetPlayerByUserId = function(_, id)
				for _, p in opts.players do
					if p.UserId == id then
						return p
					end
				end
				return nil
			end,
		},
		TeleportService = { TeleportAsync = function(_, placeId) table.insert(opts.teleports, placeId) end },
	}
	local gameProxy = setmetatable({}, { __index = function(_, k)
		if k == "GetService" then
			return function(_, name) return services[name] or game:GetService(name) end
		elseif k == "BindToClose" then
			return function() end
		end
		return game[k]
	end })
	local function envRequire(m)
		if m.Name == "MountainPlaces" then
			return function() return opts.mountainPlaces end
		end
		return require(m)
	end
	local function out(tag)
		return function(...)
			local t = { tag }
			for i = 1, select("#", ...) do
				table.insert(t, tostring((select(i, ...))))
			end
			table.insert(opts.log, table.concat(t, " "))
		end
	end
	local env = setmetatable({ game = gameProxy, require = envRequire, warn = out("WARN"), print = out("PRINT") }, { __index = getfenv(1) })
	local sapi = { DATAFILES = {}, PlayerDataBound = true }
	for _, text in { src.data, src.events } do
		local fn = assert(loadstring(text))
		setfenv(fn, env)
		local a, s = fn().new(sapi)
		for k, f in a do
			sapi[k] = f
		end
		for k, f in s do
			sapi[k] = f
		end
	end
	sapi.SetupCalls = 0
	sapi.GetPlayerProgress = function(_, p) return sapi.DATAFILES[p.Name] end
	sapi.SetupPlayerProgress = function(_, p)
		sapi.SetupCalls += 1
		return sapi.DATAFILES[p.Name]
	end
	sapi.ReplicateProgress = function() end
	sapi.ClearSnowball = function() end
	sapi.ClearLauncher = function() end
	return sapi
end

local function leave(sapi, opts, p)
	-- Roblox order: PlayerRemoving runs while the player is still in Players.
	sapi:PlayerRemoving(p)
	p.Parent = nil
	local i = table.find(opts.players, p)
	if i then
		table.remove(opts.players, i)
	end
end

return function(dataFile, eventsFile, only)
	local src = { data = fetch(dataFile), events = fetch(eventsFile) }
	local R = {}
	local function rec(name, fmt, ...)
		table.insert(R, name .. ": " .. string.format(fmt, ...))
	end
	local function want(name)
		return only == nil or string.find(only, name, 1, true) ~= nil
	end
	local KEY = "u_101"

	if want("T1") then -- live server, every read fails; the player stands on a locked mountain
		local store = newStore()
		store.data[KEY] = savedProfile()
		store.getFails = 99
		local p = fakePlayer("Alice", 101)
		local opts = { store = store, studio = false, players = { p }, mountainPlaces = fakeMountains("Christmas") }
		local sapi = build(src, opts)
		local t0 = os.clock()
		sapi:PlayerAdded(p)
		local d = sapi.DATAFILES[p.Name]
		local loaded, failed, dirty = d and d.Loaded, d and d.LoadFailed, d and d.Dirty
		local auto = sapi:SavePlayerData(p, false)
		sapi:SaveAllPlayerData(true)
		sapi:EnforceMountainAccess(p)
		leave(sapi, opts, p)
		rec("T1 live read fails", "%.1fs gets=%d kicked=%s setup=%d loaded=%s failed=%s dirty=%s autosave=%s updates=%d teleports=%d stored Coins/Total=%s/%s",
			os.clock() - t0, store.getCalls, tostring(p.Kicked), sapi.SetupCalls, tostring(loaded), tostring(failed), tostring(dirty),
			tostring(auto), store.updCalls, #opts.teleports, tostring(store.data[KEY].Coins), tostring(store.data[KEY].TotalCoinsCollected))
	end

	if want("T2") then -- Studio, every read fails: keep playing, save nothing
		local store = newStore()
		store.data[KEY] = savedProfile()
		store.getFails = 99
		local p = fakePlayer("Bob", 101)
		local opts = { store = store, studio = true, players = { p } }
		local sapi = build(src, opts)
		sapi:PlayerAdded(p)
		local d = sapi.DATAFILES[p.Name]
		local loaded, failed = d and d.Loaded, d and d.LoadFailed
		if d then
			d.Coins += 50
			d.Dirty = true
		end
		local force = sapi:SavePlayerData(p, true)
		leave(sapi, opts, p)
		rec("T2 studio read fails", "kicked=%s setup=%d loaded=%s failed=%s force=%s updates=%d stored Coins=%s",
			tostring(p.Kicked), sapi.SetupCalls, tostring(loaded), tostring(failed), tostring(force), store.updCalls, tostring(store.data[KEY].Coins))
	end

	if want("T3") then -- two failed reads, then one succeeds
		local store = newStore()
		store.data[KEY] = savedProfile()
		store.getFails = 2
		local p = fakePlayer("Cara", 101)
		local opts = { store = store, studio = false, players = { p } }
		local sapi = build(src, opts)
		sapi:PlayerAdded(p)
		local d = sapi.DATAFILES[p.Name]
		local coins, loaded = d and d.Coins, d and d.Loaded
		local force = sapi:SavePlayerData(p, true)
		rec("T3 transient read failure", "gets=%d kicked=%s setup=%d loaded=%s coins=%s force=%s updates=%d stored Coins=%s",
			store.getCalls, tostring(p.Kicked), sapi.SetupCalls, tostring(loaded), tostring(coins), tostring(force), store.updCalls, tostring(store.data[KEY].Coins))
	end

	if want("T4") then -- player leaves while GetAsync is still yielding
		local store = newStore()
		store.data[KEY] = savedProfile()
		store.getDelay = 1
		local p = fakePlayer("Dan", 101)
		local opts = { store = store, studio = false, players = { p } }
		local sapi = build(src, opts)
		local done = false
		task.spawn(function()
			sapi:PlayerAdded(p)
			done = true
		end)
		task.wait(0.2)
		leave(sapi, opts, p)
		local deadline = os.clock() + 3
		while not done and os.clock() < deadline do
			task.wait()
		end
		rec("T4 leave during load", "done=%s setup=%d entry=%s updates=%d stored Coins/Total=%s/%s",
			tostring(done), sapi.SetupCalls, tostring(sapi.DATAFILES[p.Name] ~= nil), store.updCalls,
			tostring(store.data[KEY].Coins), tostring(store.data[KEY].TotalCoinsCollected))
	end

	if want("T5") then -- player leaves while the autosave is mid-UpdateAsync
		local store = newStore()
		store.data[KEY] = savedProfile()
		local p = fakePlayer("Eve", 101)
		local opts = { store = store, studio = false, players = { p } }
		local sapi = build(src, opts)
		sapi:PlayerAdded(p)
		local d = sapi.DATAFILES[p.Name]
		store.updDelay = 1
		d.Coins += 10
		d.Dirty = true
		local auto, dirtyAfterAuto = "unset", nil
		task.spawn(function()
			auto = sapi:SavePlayerData(p, false)
			dirtyAfterAuto = d.Dirty
		end)
		task.wait(0.3)
		d.Coins += 100 -- a buy / award lands while the autosave writes
		d.Dirty = true
		local t0 = os.clock()
		leave(sapi, opts, p)
		local leaveTime = os.clock() - t0
		local deadline = os.clock() + 3
		while auto == "unset" and os.clock() < deadline do
			task.wait()
		end
		rec("T5 leave during autosave", "autosave=%s dirtyAfterAutosave=%s leaveSave=%.2fs writes=%s stored Coins=%s (want 5110) entry=%s",
			tostring(auto), tostring(dirtyAfterAuto), leaveTime, table.concat(store.writes, ","), tostring(store.data[KEY].Coins), tostring(sapi.DATAFILES[p.Name] ~= nil))
	end

	if want("T6") then -- another session already saved higher lifetime totals
		local store = newStore()
		store.data[KEY] = savedProfile()
		local p = fakePlayer("Finn", 101)
		local opts = { store = store, studio = false, players = { p } }
		local sapi = build(src, opts)
		sapi:PlayerAdded(p)
		local d = sapi.DATAFILES[p.Name]
		store.data[KEY].TotalCoinsCollected = 9500
		store.data[KEY].Coins = 5400
		d.Coins += 1
		d.Dirty = true
		local r1 = sapi:SavePlayerData(p, true)
		local dirty1 = d.Dirty
		local coins1, total1 = store.data[KEY].Coins, store.data[KEY].TotalCoinsCollected
		d.TotalCoinsCollected = 9600
		local r2 = sapi:SavePlayerData(p, true)
		local warned = 0
		for _, line in opts.log do
			if string.find(line, "Not saving", 1, true) then
				warned += 1
			end
		end
		rec("T6 stale guard", "behind: save=%s dirty=%s stored Coins/Total=%s/%s warns=%d | caught up: save=%s stored Coins/Total=%s/%s",
			tostring(r1), tostring(dirty1), tostring(coins1), tostring(total1), warned, tostring(r2),
			tostring(store.data[KEY].Coins), tostring(store.data[KEY].TotalCoinsCollected))
	end

	if want("T7") then -- brand-new player (no save yet) still gets a first save
		local store = newStore()
		local p = fakePlayer("Gail", 101)
		local opts = { store = store, studio = false, players = { p } }
		local sapi = build(src, opts)
		sapi:PlayerAdded(p)
		local d = sapi.DATAFILES[p.Name]
		local loaded, dirty = d and d.Loaded, d and d.Dirty
		local auto = sapi:SavePlayerData(p, false)
		local s = store.data[KEY]
		rec("T7 new player", "setup=%d loaded=%s dirty=%s autosave=%s stored=%s",
			sapi.SetupCalls, tostring(loaded), tostring(dirty), tostring(auto),
			s and string.format("%s/%s/%s", tostring(s.Coins), tostring(s.EquippedSnowball), tostring(s.EquippedLauncher)) or "nil")
	end

	if want("T8") then -- loaded player on a locked mountain is still sent to the start
		local store = newStore()
		store.data[KEY] = savedProfile()
		local p = fakePlayer("Hal", 101)
		local opts = { store = store, studio = false, players = { p }, mountainPlaces = fakeMountains("Christmas") }
		local sapi = build(src, opts)
		sapi:PlayerAdded(p)
		rec("T8 locked mountain, loaded", "teleports=%d updates=%d stored Coins=%s", #opts.teleports, store.updCalls, tostring(store.data[KEY].Coins))
	end

	if want("T9") then -- quick rejoin to this server while the leave save is still writing
		local store = newStore()
		store.data[KEY] = savedProfile()
		local p1 = fakePlayer("Ivy", 101)
		local opts = { store = store, studio = false, players = { p1 } }
		local sapi = build(src, opts)
		sapi:PlayerAdded(p1)
		local d1 = sapi.DATAFILES[p1.Name]
		d1.Coins += 7
		d1.Dirty = true
		store.updDelay = 0.5
		local done = false
		task.spawn(function()
			sapi:PlayerRemoving(p1)
			done = true
		end)
		p1.Parent = nil
		table.clear(opts.players)
		task.wait(0.1)
		local p2 = fakePlayer("Ivy", 101)
		table.insert(opts.players, p2)
		sapi:PlayerAdded(p2)
		while not done do
			task.wait()
		end
		local d2 = sapi.DATAFILES[p2.Name]
		local force = sapi:SavePlayerData(p2, true)
		rec("T9 rejoin during leave save", "gets=%d sameProfile=%s entryKept=%s force=%s stored Coins=%s (want 5007)",
			store.getCalls, tostring(d2 == d1), tostring(d2 ~= nil), tostring(force), tostring(store.data[KEY].Coins))
	end

	return table.concat(R, "\n")
end
