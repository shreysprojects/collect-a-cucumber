-- Persistent, one-use paid portal unlocks shared by every portal service.
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PRODUCT_ID = 3709119039
local STORE_NAME = "PortalUnlockState_v1"
local store = DataStoreService:GetDataStore(STORE_NAME)

local remotes = ReplicatedStorage:FindFirstChild("PortalUnlockRemotes") or Instance.new("Folder")
remotes.Name = "PortalUnlockRemotes"
remotes.Parent = ReplicatedStorage

local requestUnlock = remotes:FindFirstChild("RequestUnlock") or Instance.new("RemoteFunction")
requestUnlock.Name = "RequestUnlock"
requestUnlock.Parent = remotes

local module = {}
local registrations = {}
local states = {}
local requestTimes = {}
local MAX_ATTEMPTS = 4

local function retryDelay(attempt)
	return math.min(8, 0.5 * (2 ^ (attempt - 1))) + math.random() * 0.35
end

local function dataKey(player)
	return "Player_" .. player.UserId
end

local function sanitize(raw)
	local clean = { loaded = true, credits = {}, pending = nil }
	if type(raw) == "table" then
		if type(raw.credits) == "table" then
			for key, value in pairs(raw.credits) do
				if type(key) == "string" and value == true then
					clean.credits[key] = true
				end
			end
		end
		if type(raw.pending) == "string" then
			clean.pending = raw.pending
		end
	end
	return clean
end

local function snapshot(state)
	local credits = {}
	for key, value in pairs(state.credits) do
		if value == true then credits[key] = true end
	end
	return { credits = credits, pending = state.pending }
end

local function save(player, state)
	local payload = snapshot(state)
	local ok, err = false, nil
	for attempt = 1, MAX_ATTEMPTS do
		ok, err = pcall(function()
			store:UpdateAsync(dataKey(player), function()
				return payload
			end)
		end)
		if ok then return true end
		if attempt < MAX_ATTEMPTS then task.wait(retryDelay(attempt)) end
	end
	warn("[PortalUnlockService] Could not save paid portal unlock state after retries", player, err)
	return false
end

local function refresh(player, key)
	local registration = registrations[key]
	if registration and registration.Refresh and player.Parent then
		task.spawn(registration.Refresh, player)
	end
end

local function load(player)
	local existing = states[player.UserId]
	if existing and existing.loaded then return existing end
	if existing and existing.loading then
		local deadline = os.clock() + 10
		while existing.loading and player.Parent and os.clock() < deadline do
			task.wait()
		end
		return existing.loaded and existing or nil
	end

	local state = existing or { loaded = false, loading = true, credits = {} }
	state.loading = true
	states[player.UserId] = state
	local ok, raw = false, nil
	for attempt = 1, MAX_ATTEMPTS do
		ok, raw = pcall(function()
			return store:GetAsync(dataKey(player))
		end)
		if ok or not player:IsDescendantOf(Players) then break end
		if attempt < MAX_ATTEMPTS then task.wait(retryDelay(attempt)) end
	end
	if not ok then
		state.loading = false
		warn("[PortalUnlockService] Could not load paid portal unlock state after retries", player, raw)
		return nil
	end
	if not player:IsDescendantOf(Players) then
		state.loading = false
		return nil
	end

	local clean = sanitize(raw)
	state.loaded = true
	state.loading = false
	state.credits = clean.credits
	state.pending = clean.pending
	for key in pairs(registrations) do refresh(player, key) end
	return state
end

function module.Register(key, registration)
	assert(type(key) == "string", "Portal key must be a string")
	assert(type(registration) == "table", "Portal registration must be a table")
	registrations[key] = registration
	for _, player in ipairs(Players:GetPlayers()) do
		local state = states[player.UserId]
		if state and state.loaded then refresh(player, key) end
	end
end

function module.HasCredit(player, key)
	local state = states[player.UserId]
	return state ~= nil and state.loaded == true and state.credits[key] == true
end

function module.Consume(player, key)
	local state = load(player)
	if not state or state.credits[key] ~= true then return false end
	state.credits[key] = nil
	if not save(player, state) then
		state.credits[key] = true
		refresh(player, key)
		return false
	end
	refresh(player, key)
	return true
end

function module.GrantPending(player)
	local state = load(player)
	if not state or type(state.pending) ~= "string" or not registrations[state.pending] then
		return false
	end
	local key = state.pending
	local oldCredit = state.credits[key]
	state.credits[key] = true
	state.pending = nil
	if not save(player, state) then
		state.credits[key] = oldCredit
		state.pending = key
		return false
	end
	refresh(player, key)
	return true
end

local function playerIsNear(player, part)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not part or not part:IsDescendantOf(workspace) then return false end
	return (root.Position - part.Position).Magnitude <= math.max(22, part.Size.Magnitude + 8)
end

local function request(player, key)
	if type(key) ~= "string" then return nil end
	local registration = registrations[key]
	if not registration or not playerIsNear(player, registration.Part) then return nil end

	local now = os.clock()
	if now - (requestTimes[player.UserId] or 0) < 1 then return nil end
	requestTimes[player.UserId] = now

	local state = load(player)
	if not state or state.credits[key] == true then return nil end
	local ok, locked = pcall(registration.IsLocked, player)
	if not ok or locked ~= true then return nil end

	local previous = state.pending
	state.pending = key
	if not save(player, state) then
		state.pending = previous
		return nil
	end
	return PRODUCT_ID
end

requestUnlock.OnServerInvoke = request

Players.PlayerAdded:Connect(function(player)
	task.spawn(load, player)
end)

Players.PlayerRemoving:Connect(function(player)
	local state = states[player.UserId]
	if state and state.loaded then save(player, state) end
	states[player.UserId] = nil
	requestTimes[player.UserId] = nil
end)

for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(load, player)
end

module.ProductId = PRODUCT_ID
return module
