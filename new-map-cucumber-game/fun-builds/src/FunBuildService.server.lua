--[[
	FunBuildService  (Script, ServerScriptService)  2026-09-24
	Server half of FUNCTIONAL BUILDS (fun-builds/CONTRACT.md). Every placed build (tag "PlacedBuild" in a
	plot's Placed folder: placed, moved, restored by BaseSaveService) whose base key has a module in
	ServerStorage.FunBehaviours gets that module's Server(model, ctx) run for it. The ctx owns everything
	the behaviour makes (prompts, seats, sounds, loops, connections) and tears it all down when the build
	is sold / cleared, and re-runs the behaviour from scratch when the build is MOVED (its Hitbox turns
	up somewhere else) or when BuildHealthService breaks / mends it (a Broken build runs nothing).
	One RemoteEvent, ReplicatedStorage.Remotes.FunBuildAction, carries both ways:
	  client -> server  (model, action, payload): the module's Actions[action](model, player, payload, ctx),
	                    only for a running build within ActionRange (default 40) studs of the player,
	                    at most ACTION_RATE per player per second
	  server -> client  (model, action, payload): ctx:Fire - the client module's OnEvent
	Studio hook: workspace:SetAttribute("FunBuildDev", "list" | "restart")
]]

--..Services..--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

--..Modules..--
local Kit = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("FunBuildKit"))

--..Config..--
local ACTION_RATE = 12          -- actions per player per second
local DEFAULT_ACTION_RANGE = 40 -- studs from the build's hitbox
local RESTART_DEBOUNCE = 0.25   -- a move sets CFrame on every part; restart once it settles
local DEFAULT_PROMPT_DISTANCE = 10

--..Instances..--
local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
if not Remotes then
	Remotes = Instance.new("Folder")
	Remotes.Name = "Remotes"
	Remotes.Parent = ReplicatedStorage
end
local Remote = Remotes:FindFirstChild(Kit.REMOTE)
if not Remote then
	Remote = Instance.new("RemoteEvent")
	Remote.Name = Kit.REMOTE
	Remote.Parent = Remotes
end
local Runtime = workspace:FindFirstChild(Kit.RUNTIME_FOLDER)
if Runtime then Runtime:ClearAllChildren() else
	Runtime = Instance.new("Folder")
	Runtime.Name = Kit.RUNTIME_FOLDER
	Runtime.Parent = workspace
end

--..Behaviours..--
local Behaviours = {} -- [base key] = module table
local function LoadBehaviours()
	local folder = ServerStorage:WaitForChild(Kit.SERVER_FOLDER, 30)
	if not folder then
		warn("[FunBuildService] ServerStorage." .. Kit.SERVER_FOLDER .. " missing - no functional builds")
		return 0
	end
	local n = 0
	for _, m in ipairs(folder:GetChildren()) do
		if m:IsA("ModuleScript") then
			local ok, mod = pcall(require, m)
			if ok and type(mod) == "table" and type(mod.Server) == "function" then
				for _, key in ipairs(type(mod.Keys) == "table" and mod.Keys or {m.Name}) do Behaviours[key] = mod end
				n += 1
			else
				warn("[FunBuildService] behaviour " .. m.Name .. " failed to load: " .. tostring(mod))
			end
		end
	end
	return n
end

--.. the module for a key: the exact key first ("Lantern_A"), then its base ("Lantern")
local function BehaviourOf(key)
	if type(key) ~= "string" then return nil end
	if Behaviours[key] then return Behaviours[key] end
	local base = Kit.Split(key)
	return base and Behaviours[base] or nil
end

--..Running builds..--
local Running = {} -- [model] = ctx

local function NewContext(model, mod)
	local key = Kit.Key(model)
	local base, variant = Kit.Split(key)
	local ctx = {
		Model = model, Key = key, Base = base, Variant = variant, Scale = Kit.Scale(model), Kit = Kit,
		Behaviour = mod, _alive = true, _conns = {}, _insts = {}, _cleanups = {}, _states = {},
	}
	local folder = Instance.new("Folder")
	folder.Name = tostring(key) .. "_" .. tostring(model:GetAttribute("Owner") or 0) .. "_" .. string.format("%x", math.random(0, 0xFFFFFF))
	folder.Parent = Runtime
	ctx.Folder = folder -- helper parts live here (never inside the build: the placement overlap test and the broken-fade would see them)
	table.insert(ctx._insts, folder)

	function ctx:Alive() return self._alive and model.Parent ~= nil end
	function ctx:Connect(signal, fn)
		local c = signal:Connect(fn)
		table.insert(self._conns, c)
		return c
	end
	function ctx:Add(inst)
		table.insert(self._insts, inst)
		return inst
	end
	function ctx:OnCleanup(fn) table.insert(self._cleanups, fn) end
	function ctx:SetState(k, v)
		self._states[k] = true
		model:SetAttribute(Kit.STATE_PREFIX .. k, v)
	end
	function ctx:GetState(k) return model:GetAttribute(Kit.STATE_PREFIX .. k) end
	function ctx:Fire(action, payload) Remote:FireAllClients(model, action, payload) end
	function ctx:FireTo(player, action, payload) Remote:FireClient(player, model, action, payload) end
	--.. run fn every `seconds` (first call after one period) until the behaviour stops
	function ctx:Every(seconds, fn)
		task.spawn(function()
			while true do
				task.wait(seconds)
				if not self:Alive() then return end
				local ok, err = pcall(fn)
				if not ok then warn("[FunBuildService] " .. tostring(key) .. " Every: " .. tostring(err)) end
			end
		end)
	end
	function ctx:Heartbeat(fn) return self:Connect(RunService.Heartbeat, fn) end
	function ctx:IsOwner(player) return player and player.UserId == model:GetAttribute("Owner") end
	function ctx:HumanoidOf(player)
		local character = player and player.Character
		local humanoid, root = Kit.CharacterParts(character)
		if humanoid and humanoid.Health > 0 and root then return humanoid, root end
		return nil
	end
	function ctx:Near(player, dist)
		local _, root = self:HumanoidOf(player)
		local hitbox = Kit.Hitbox(model)
		return root ~= nil and hitbox ~= nil and (root.Position - hitbox.Position).Magnitude <= (dist or DEFAULT_ACTION_RANGE)
	end
	--.. a Custom-style ProximityPrompt (StarterPlayerScripts.CucumberPromptClient draws it like the game's other prompts)
	--.. opts: Action, Object, Hold (s), Distance, Key (KeyCode), Name, Offset (Vector3 in the part's space), Exclusivity
	function ctx:Prompt(part, opts)
		opts = opts or {}
		local parent = part
		if opts.Offset then
			local att = Instance.new("Attachment")
			att.Name = "FunPromptAt"
			att.Position = opts.Offset
			att.Parent = part
			self:Add(att)
			parent = att
		end
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = opts.Name or "FunPrompt"
		prompt.ObjectText = opts.Object or tostring(model:GetAttribute("DisplayName") or base)
		prompt.ActionText = opts.Action or "Use"
		prompt.Style = Enum.ProximityPromptStyle.Custom
		prompt.KeyboardKeyCode = opts.Key or Enum.KeyCode.E
		prompt.GamepadKeyCode = opts.Gamepad or Enum.KeyCode.ButtonX
		prompt.HoldDuration = opts.Hold or 0
		prompt.MaxActivationDistance = opts.Distance or DEFAULT_PROMPT_DISTANCE
		prompt.RequiresLineOfSight = false
		prompt.Exclusivity = opts.Exclusivity or Enum.ProximityPromptExclusivity.OnePerButton
		prompt:SetAttribute("BaseDistance", prompt.MaxActivationDistance)
		CollectionService:AddTag(prompt, Kit.PROMPT_TAG)
		prompt.Parent = parent
		self:Add(prompt)
		return prompt
	end
	--.. an invisible anchored Seat at a WORLD cframe (the occupant's hips rest on its top face), with a "Sit" prompt.
	--.. opts: Name, Size (Vector3, default 2 x 0.4 x 2), Lie (lay the occupant flat: head toward the seat's LookVector),
	--.. LieLift (studs from the seat's top face to the root's centre, default 0.55), Prompt (action text, false = none),
	--.. Object, Distance, PromptOffset
	function ctx:Seat(cframe, opts)
		opts = opts or {}
		local seat = Instance.new("Seat")
		seat.Name = opts.Name or "FunSeat"
		seat.Size = opts.Size or Vector3.new(2, 0.4, 2)
		seat.CFrame = cframe
		seat.Transparency = 1
		seat.Anchored = true
		seat.CanCollide = false
		seat.CanTouch = false -- no sitting by walking into it: the prompt (or Seat:Sit) seats people
		seat.CanQuery = false
		seat.CastShadow = false
		seat.Parent = self.Folder
		if opts.Lie then
			seat:SetAttribute(Kit.LIE_ATTR, true)
			local lift = opts.LieLift or 0.55
			self:Connect(seat.ChildAdded, function(child)
				if child:IsA("Weld") and child.Name == "SeatWeld" then
					task.defer(function()
						if child.Parent then
							child.C0 = CFrame.new(0, seat.Size.Y * 0.5 + lift, 0) * Kit.LIE_ROTATION
							child.C1 = CFrame.new()
						end
					end)
				end
			end)
		end
		if opts.Prompt ~= false then
			local prompt = self:Prompt(seat, {Action = opts.Prompt or "Sit", Object = opts.Object, Distance = opts.Distance or 8, Name = "SitPrompt", Offset = opts.PromptOffset})
			self:Connect(prompt.Triggered, function(player)
				if seat.Occupant then return end
				local humanoid = self:HumanoidOf(player)
				if not humanoid or humanoid.Sit or humanoid.SeatPart then return end
				seat:Sit(humanoid)
			end)
			--.. a taken seat hides its prompt
			self:Connect(seat:GetPropertyChangedSignal("Occupant"), function()
				prompt.Enabled = seat.Occupant == nil
			end)
		end
		self:Add(seat)
		return seat
	end
	--.. a helper Part in the runtime folder (anchored, no collide/query/touch unless opts say so)
	function ctx:Part(props)
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		for k, v in pairs(props or {}) do p[k] = v end
		if not p.Parent or p.Parent == workspace then p.Parent = self.Folder end
		self:Add(p)
		return p
	end
	function ctx:Sound(parent, nameOrId, props)
		local s = Kit.MakeSound(nameOrId, props)
		s.Parent = parent
		self:Add(s)
		return s
	end
	return ctx
end

local function Stop(model)
	local ctx = Running[model]
	if not ctx then return end
	Running[model] = nil
	ctx._alive = false
	for _, fn in ipairs(ctx._cleanups) do
		local ok, err = pcall(fn)
		if not ok then warn("[FunBuildService] cleanup " .. tostring(ctx.Key) .. ": " .. tostring(err)) end
	end
	for _, c in ipairs(ctx._conns) do c:Disconnect() end
	for i = #ctx._insts, 1, -1 do
		local inst = ctx._insts[i]
		if typeof(inst) == "Instance" then inst:Destroy() end
	end
	if model.Parent then
		for k in pairs(ctx._states) do model:SetAttribute(Kit.STATE_PREFIX .. k, nil) end
	end
end

local function Start(model)
	if Running[model] then return end
	if not (model:IsA("Model") and model:IsDescendantOf(workspace) and CollectionService:HasTag(model, Kit.PLACED_TAG)) then return end
	if Kit.IsBroken(model) or not Kit.Hitbox(model) then return end
	local mod = BehaviourOf(Kit.Key(model))
	if not mod then return end
	local ctx = NewContext(model, mod)
	Running[model] = ctx
	local ok, result = pcall(mod.Server, model, ctx)
	if not ok then
		warn("[FunBuildService] " .. tostring(ctx.Key) .. " Server(): " .. tostring(result))
	elseif type(result) == "function" then
		ctx:OnCleanup(result)
	end
end

local function Restart(model)
	Stop(model)
	Start(model)
end

--.. watchers per build: moved (the hitbox CFrame changes; the move pivots every part) / broken / mended
local Watched = {}
local function Watch(model)
	if Watched[model] or not model:IsA("Model") then return end
	local key = Kit.Key(model)
	if not BehaviourOf(key) then return end
	local hitbox = Kit.Hitbox(model)
	if not hitbox then return end
	local conns = {}
	Watched[model] = conns
	local pending = false
	local function queue()
		if pending then return end
		pending = true
		task.delay(RESTART_DEBOUNCE, function()
			pending = false
			if Watched[model] then Restart(model) end
		end)
	end
	table.insert(conns, hitbox:GetPropertyChangedSignal("CFrame"):Connect(queue))
	table.insert(conns, model:GetAttributeChangedSignal("Broken"):Connect(queue))
	table.insert(conns, model.AncestryChanged:Connect(function()
		if not model:IsDescendantOf(workspace) then
			Stop(model)
			for _, c in ipairs(conns) do c:Disconnect() end
			Watched[model] = nil
		end
	end))
	Start(model)
end

local function Unwatch(model)
	Stop(model)
	local conns = Watched[model]
	if conns then
		for _, c in ipairs(conns) do c:Disconnect() end
		Watched[model] = nil
	end
end

--..Actions from clients..--
local Budget = {} -- [player] = {t, n}
Remote.OnServerEvent:Connect(function(player, model, action, payload)
	if typeof(model) ~= "Instance" or type(action) ~= "string" or #action > 40 then return end
	local now = os.clock()
	local b = Budget[player]
	if not b or now - b.t >= 1 then b = {t = now, n = 0} Budget[player] = b end
	b.n += 1
	if b.n > ACTION_RATE then return end
	local ctx = Running[model]
	if not ctx then return end
	local mod = ctx.Behaviour
	local handler = type(mod.Actions) == "table" and mod.Actions[action]
	if type(handler) ~= "function" then return end
	if not ctx:Near(player, mod.ActionRange or DEFAULT_ACTION_RANGE) then return end
	local ok, err = pcall(handler, model, player, payload, ctx)
	if not ok then warn("[FunBuildService] " .. tostring(ctx.Key) .. " action " .. action .. ": " .. tostring(err)) end
end)
Players.PlayerRemoving:Connect(function(player) Budget[player] = nil end)

--..Setup..--
local loaded = LoadBehaviours()
CollectionService:GetInstanceAddedSignal(Kit.PLACED_TAG):Connect(function(model)
	task.defer(Watch, model) -- BuildService tags before it parents; look a frame later
end)
CollectionService:GetInstanceRemovedSignal(Kit.PLACED_TAG):Connect(Unwatch)
for _, model in ipairs(CollectionService:GetTagged(Kit.PLACED_TAG)) do task.defer(Watch, model) end

workspace:GetAttributeChangedSignal("FunBuildDev"):Connect(function()
	local cmd = workspace:GetAttribute("FunBuildDev")
	if cmd == nil or cmd == "" then return end
	workspace:SetAttribute("FunBuildDev", nil)
	if cmd == "list" then
		local rows = {}
		for model, ctx in pairs(Running) do table.insert(rows, tostring(ctx.Key) .. "@" .. model:GetFullName()) end
		print("[FunBuildService] running: " .. #rows .. "\n  " .. table.concat(rows, "\n  "))
	elseif cmd == "restart" then
		for model in pairs(Watched) do Restart(model) end
		print("[FunBuildService] restarted every functional build")
	end
end)

local names = {}
for k in pairs(Behaviours) do table.insert(names, k) end
table.sort(names)
print(("[FunBuildService] %d behaviour module(s): %s"):format(loaded, table.concat(names, ", ")))
