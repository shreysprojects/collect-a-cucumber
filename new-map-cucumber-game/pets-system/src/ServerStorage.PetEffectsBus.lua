--[[
	PetEffectsBus  (ModuleScript, ServerStorage)  2026-09-22
	The pet system's cosmetic event bus (pets-system/CONTRACTS.md 3.10, 7.3; PLAN sections 11-12).

	Server modules (PetCombatService "Shot", PetBuffService "AbilityApplied" / "ShieldBlocked") hand plain
	event tables to Emit(event, owner, position). The bus stamps them (Id = server-wide increasing int,
	T = server time unless the caller set one, Owner = UserId) and queues each for its recipients: the
	owner (wherever they are - owner toasts work from a portal too, OD-26) plus every player whose
	character root is within PetBalance.FX.RADIUS studs of the position. One Heartbeat accumulator
	flushes every TIMING.FX_FLUSH seconds: one Remotes.PetEffects:FireClient(player, {T, Events}) per
	recipient with something queued. At most FX.MAX_EVENTS_PER_BATCH events wait per recipient; the
	oldest go first (Dropped). Dropping is purely cosmetic - callers applied damage / buffs before they
	emitted, and no client -> server handler exists for PetEffects.
	  * Emit never yields and never errors: an event that is not a table with a string Kind, or an owner
	    that is neither a Player nor a finite UserId, is dropped (Invalid). A missing / non-finite
	    position just means "owner only" (OwnerOnly).
	  * A recipient who left before the flush loses its queue (counted in Dropped).

	Use (ServerScriptService.PetServer):
		PetEffectsBus.Init({})   -- deps: Clock?, Players? (test fake), Fire? / RootOf? (test overrides)
		PetEffectsBus.Start()    -- find-or-create Remotes.PetEffects + the flush
		PetEffectsBus.Emit({Kind = "Shot", PetId = id, From = a, To = b, ...}, player, a)
	GetDiagnostics(): Emitted, Sent (events delivered, per recipient), Dropped, Invalid, OwnerOnly,
	Batches, SendErrors, Queued (events waiting now).
	Core (pure, unit tests): Recipients(ownerId, position, players, rootOf?, radius?), Enqueue(queue,
	event, cap) -> dropped, OwnerIdOf(owner).
]]

--..Services..--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

--..Pure helpers..--
local function Finite(x)
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

local function ValidVector(v)
	return typeof(v) == "Vector3" and Finite(v.X) and Finite(v.Y) and Finite(v.Z)
end

--..Config (PetBalance when installed; the same literals otherwise)..--
local BALANCE do
	local modules = ReplicatedStorage:FindFirstChild("Modules")
	local module = modules and modules:FindFirstChild("PetBalance")
	if module then
		local ok, result = pcall(require, module)
		if ok and type(result) == "table" then BALANCE = result end
	end
end
local FX = BALANCE and type(BALANCE.FX) == "table" and BALANCE.FX or {}
local TIMING = BALANCE and type(BALANCE.TIMING) == "table" and BALANCE.TIMING or {}
local RADIUS = Finite(FX.RADIUS) and FX.RADIUS > 0 and FX.RADIUS or 180 -- studs around the event
local MAX_EVENTS = Finite(FX.MAX_EVENTS_PER_BATCH) and math.max(1, math.floor(FX.MAX_EVENTS_PER_BATCH)) or 48 -- per recipient per flush
local FLUSH_PERIOD = Finite(TIMING.FX_FLUSH) and TIMING.FX_FLUSH > 0 and TIMING.FX_FLUSH or 0.1 -- seconds
local REMOTE_NAME = "PetEffects"
local WARN_INTERVAL = 60 -- seconds between two warns of the same kind

--..Module..--
local PetEffectsBus = {}
local Core = {}
PetEffectsBus.Core = Core
Core.RADIUS = RADIUS
Core.MAX_EVENTS = MAX_EVENTS

--..State..--
local Deps = {
	Clock = function() return workspace:GetServerTimeNow() end,
	Players = Players,
	Fire = nil, -- test override: fn(player, payload) instead of the remote
	RootOf = nil, -- test override: fn(player) -> Vector3? instead of the character root
}
local Initialized, Started = false, false
local Queues = {} -- [player] = {event...} waiting for the next flush
local NextId = 0
local Remote = nil
local HeartbeatConn = nil
local Diag = {Emitted = 0, Sent = 0, Dropped = 0, Invalid = 0, OwnerOnly = 0, Batches = 0, SendErrors = 0}
local LastWarn = {}

local function WarnOnce(key, message)
	local now = os.clock()
	if LastWarn[key] and now - LastWarn[key] < WARN_INTERVAL then return end
	LastWarn[key] = now
	warn(message)
end

--..Core..--
--.. the character root position of a real Player (nil when it has no character / root)
local function DefaultRootOf(player)
	local character = player.Character
	if typeof(character) ~= "Instance" then return nil end
	local root = character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart
	if root and root:IsA("BasePart") then return root.Position end
	return nil
end

--.. UserId of a Player or a finite number; nil otherwise
function Core.OwnerIdOf(owner)
	if typeof(owner) == "Instance" then
		if owner:IsA("Player") then return owner.UserId end
		return nil
	end
	if Finite(owner) then return owner end
	return nil
end

--.. the owner (matched by UserId, at any distance) + every player whose root is within radius of position.
--.. players = a list of Players (or fakes with UserId); rootOf(player) -> Vector3? (default: character root)
function Core.Recipients(ownerId, position, players, rootOf, radius)
	rootOf = rootOf or DefaultRootOf
	radius = Finite(radius) and radius or RADIUS
	local near = ValidVector(position)
	local list = {}
	if type(players) ~= "table" then return list end
	for _, player in ipairs(players) do
		local include = ownerId ~= nil and player.UserId == ownerId
		if not include and near then
			local ok, root = pcall(rootOf, player)
			if ok and ValidVector(root) and (root - position).Magnitude <= radius then include = true end
		end
		if include then list[#list + 1] = player end
	end
	return list
end

--.. append, then drop the oldest while over cap; returns how many were dropped
function Core.Enqueue(queue, event, cap)
	cap = Finite(cap) and math.max(1, math.floor(cap)) or MAX_EVENTS
	queue[#queue + 1] = event
	local dropped = 0
	while #queue > cap do
		table.remove(queue, 1)
		dropped += 1
	end
	return dropped
end

--..API..--
local function EmitBody(event, owner, position)
	if type(event) ~= "table" or type(event.Kind) ~= "string" then
		Diag.Invalid += 1
		return
	end
	local ownerId = Core.OwnerIdOf(owner)
	if not ownerId then
		Diag.Invalid += 1
		return
	end
	NextId += 1
	event.Id = NextId
	if not Finite(event.T) then event.T = Deps.Clock() end
	event.Owner = ownerId
	Diag.Emitted += 1
	if not ValidVector(position) then Diag.OwnerOnly += 1 end
	local recipients = Core.Recipients(ownerId, position, Deps.Players:GetPlayers(), Deps.RootOf)
	for _, player in ipairs(recipients) do
		local queue = Queues[player]
		if not queue then
			queue = {}
			Queues[player] = queue
		end
		Diag.Dropped += Core.Enqueue(queue, event, MAX_EVENTS)
	end
end

--.. queue one cosmetic event (never yields, never errors)
function PetEffectsBus.Emit(event, owner, position)
	local ok, err = pcall(EmitBody, event, owner, position)
	if not ok then
		Diag.Invalid += 1
		WarnOnce("emit", "[PetEffectsBus] Emit dropped an event: " .. tostring(err))
	end
end

--.. send every queued batch now (the Heartbeat calls this every FLUSH_PERIOD); returns batches sent
function PetEffectsBus.Flush(now)
	now = Finite(now) and now or Deps.Clock()
	local send = Deps.Fire
	if not send and Remote then
		send = function(player, payload) Remote:FireClient(player, payload) end
	end
	if not send then return 0 end
	local batches = 0
	for player, queue in pairs(Queues) do
		Queues[player] = nil
		if #queue > 0 then
			if typeof(player) == "Instance" and player.Parent ~= Players then
				Diag.Dropped += #queue -- left before the flush
			else
				local ok, err = pcall(send, player, {T = now, Events = queue})
				if ok then
					Diag.Sent += #queue
					Diag.Batches += 1
					batches += 1
				else
					Diag.SendErrors += 1
					WarnOnce("send", "[PetEffectsBus] FireClient failed: " .. tostring(err))
				end
			end
		end
	end
	return batches
end

function PetEffectsBus.Init(deps)
	if Initialized then
		warn("[PetEffectsBus] Init called twice - ignored")
		return
	end
	Initialized = true
	deps = type(deps) == "table" and deps or {}
	if type(deps.Clock) == "function" then Deps.Clock = deps.Clock end
	if deps.Players ~= nil then Deps.Players = deps.Players end
	if type(deps.Fire) == "function" then Deps.Fire = deps.Fire end
	if type(deps.RootOf) == "function" then Deps.RootOf = deps.RootOf end
end

function PetEffectsBus.Start()
	if Started then return true end
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if not remotes then
		remotes = Instance.new("Folder")
		remotes.Name = "Remotes"
		remotes.Parent = ReplicatedStorage
	end
	local remote = remotes:FindFirstChild(REMOTE_NAME)
	if not remote then
		remote = Instance.new("RemoteEvent")
		remote.Name = REMOTE_NAME
		remote.Parent = remotes
	elseif not remote:IsA("RemoteEvent") then
		warn("[PetEffectsBus] Remotes." .. REMOTE_NAME .. " is a " .. remote.ClassName .. ", not a RemoteEvent - effects are not sent")
		remote = nil
	end
	Remote = remote
	local elapsed = 0
	HeartbeatConn = RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < FLUSH_PERIOD then return end
		elapsed = 0 -- a hitch sends one flush, never a queue of them
		PetEffectsBus.Flush()
	end)
	Players.PlayerRemoving:Connect(function(player)
		Queues[player] = nil
	end)
	Started = true
	return true
end

function PetEffectsBus.IsStarted()
	return Started
end

function PetEffectsBus.GetDiagnostics()
	local copy = {}
	for key, value in pairs(Diag) do copy[key] = value end
	local queued = 0
	for _, queue in pairs(Queues) do queued += #queue end
	copy.Queued = queued
	return copy
end

return PetEffectsBus
