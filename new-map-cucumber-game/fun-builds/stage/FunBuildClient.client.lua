--[[
	FunBuildClient  (LocalScript, StarterPlayerScripts)  2026-09-24
	Client half of FUNCTIONAL BUILDS (fun-builds/CONTRACT.md). Every placed build (tag "PlacedBuild") that
	streams in and has a module in ReplicatedStorage.FunBehavioursClient gets Client(model, ctx) run for
	it; the ctx tears everything down when the build streams out, is sold, moved (re-run) or broken.
	Also, for every behaviour at once:
	  * build mode: while PlayerGui.CucumberHUDDesign has BuildMode = true every FunBuildPrompt is hidden,
	    so a click in build mode selects / sells the build instead of using it (BoostPadClient does the same)
	  * lying seats: a Seat with attribute Lie = true (FunBuildService ctx:Seat{Lie = true}) straightens its
	    occupant's joints every frame (the SeatWeld already turns the body flat), so people lie instead of sit
	  * ReplicatedStorage.Remotes.FunBuildAction server -> client events go to the module's OnEvent
]]

--..Services..--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

--..Modules..--
local Kit = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("FunBuildKit"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local Remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild(Kit.REMOTE, 60)

--..Config..--
local DEFAULT_STEP_RANGE = 180 -- studs from the camera: ctx:Step callbacks sleep beyond this
local HUD_NAME = "CucumberHUDDesign"

--..Behaviours (loaded on demand, the folder can arrive late)..--
local Behaviours = {}
local folder = ReplicatedStorage:WaitForChild(Kit.CLIENT_FOLDER, 60)
local function Load(m)
	if not m:IsA("ModuleScript") then return end
	local ok, mod = pcall(require, m)
	if ok and type(mod) == "table" and type(mod.Client) == "function" then
		for _, key in ipairs(type(mod.Keys) == "table" and mod.Keys or {m.Name}) do Behaviours[key] = mod end
	else
		warn("[FunBuildClient] behaviour " .. m.Name .. " failed to load: " .. tostring(mod))
	end
end
if folder then
	for _, m in ipairs(folder:GetChildren()) do Load(m) end
end

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
		Model = model, Key = key, Base = base, Variant = variant, Scale = Kit.Scale(model), Kit = Kit, Player = player,
		Behaviour = mod, _alive = true, _conns = {}, _insts = {}, _cleanups = {}, StepRange = mod.StepRange or DEFAULT_STEP_RANGE,
	}
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
	function ctx:State(k) return model:GetAttribute(Kit.STATE_PREFIX .. k) end
	--.. fn(value) now and whenever Fun_<k> changes
	function ctx:OnState(k, fn)
		local name = Kit.STATE_PREFIX .. k
		self:Connect(model:GetAttributeChangedSignal(name), function() fn(model:GetAttribute(name)) end)
		task.spawn(fn, model:GetAttribute(name))
	end
	function ctx:Send(action, payload) Remote:FireServer(model, action, payload) end
	--.. the camera's distance to the build
	function ctx:CameraDistance()
		local hitbox = Kit.Hitbox(model)
		local cam = workspace.CurrentCamera
		if not hitbox or not cam then return math.huge end
		return (cam.CFrame.Position - hitbox.Position).Magnitude
	end
	--.. fn(dt, now) every frame (RenderStepped; Heartbeat while Studio is unfocused and render stops), asleep
	--.. while the camera is farther than ctx.StepRange from the build. now = server time
	function ctx:Step(fn)
		local last = 0
		local function run(dt)
			local t = os.clock()
			if t - last < 0.004 then return end -- RenderStepped + Heartbeat both fire: run once per frame
			last = t
			if self:CameraDistance() > self.StepRange then return end
			local ok, err = pcall(fn, dt, Kit.Now())
			if not ok then warn("[FunBuildClient] " .. tostring(key) .. " Step: " .. tostring(err)) end
		end
		self:Connect(RunService.RenderStepped, run)
		self:Connect(RunService.Heartbeat, run)
	end
	function ctx:Every(seconds, fn)
		task.spawn(function()
			while true do
				task.wait(seconds)
				if not self:Alive() then return end
				local ok, err = pcall(fn)
				if not ok then warn("[FunBuildClient] " .. tostring(key) .. " Every: " .. tostring(err)) end
			end
		end)
	end
	function ctx:Sound(parent, nameOrId, props)
		local s = Kit.MakeSound(nameOrId, props)
		s.Parent = parent
		self:Add(s)
		return s
	end
	--.. a local-only helper Part (visual effects): anchored, non-colliding, parented to workspace.CurrentCamera's sibling folder
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
		if not p.Parent or p.Parent == workspace then p.Parent = workspace.CurrentCamera end
		self:Add(p)
		return p
	end
	function ctx:LocalCharacter()
		local humanoid, root = Kit.CharacterParts(player.Character)
		if humanoid and humanoid.Health > 0 and root then return humanoid, root, player.Character end
		return nil
	end
	--.. is the local character within dist studs of the build's hitbox?
	function ctx:Near(dist)
		local _, root = self:LocalCharacter()
		local hitbox = Kit.Hitbox(model)
		return root ~= nil and hitbox ~= nil and (root.Position - hitbox.Position).Magnitude <= dist
	end
	function ctx:IsOwner() return player.UserId == model:GetAttribute("Owner") end
	return ctx
end

local function Stop(model)
	local ctx = Running[model]
	if not ctx then return end
	Running[model] = nil
	ctx._alive = false
	for _, fn in ipairs(ctx._cleanups) do
		local ok, err = pcall(fn)
		if not ok then warn("[FunBuildClient] cleanup " .. tostring(ctx.Key) .. ": " .. tostring(err)) end
	end
	for _, c in ipairs(ctx._conns) do c:Disconnect() end
	for i = #ctx._insts, 1, -1 do
		local inst = ctx._insts[i]
		if typeof(inst) == "Instance" then inst:Destroy() end
	end
end

local function Start(model)
	if Running[model] then return end
	if not (model:IsA("Model") and model:IsDescendantOf(workspace)) then return end
	if Kit.IsBroken(model) or not Kit.Hitbox(model) then return end
	local mod = BehaviourOf(Kit.Key(model))
	if not mod then return end
	local ctx = NewContext(model, mod)
	Running[model] = ctx
	local ok, result = pcall(mod.Client, model, ctx)
	if not ok then
		warn("[FunBuildClient] " .. tostring(ctx.Key) .. " Client(): " .. tostring(result))
	elseif type(result) == "function" then
		ctx:OnCleanup(result)
	end
end

local Watched = {}
local function Watch(model)
	if Watched[model] or not model:IsA("Model") then return end
	if not model:IsDescendantOf(workspace) then return end
	--.. the BuildKey attribute and the Hitbox may land a moment after the tag while streaming
	if not Kit.Key(model) or not Kit.Hitbox(model) then
		local t0 = os.clock()
		while (not Kit.Key(model) or not Kit.Hitbox(model)) and os.clock() - t0 < 10 and model.Parent do task.wait(0.1) end
	end
	if Watched[model] or not BehaviourOf(Kit.Key(model)) then return end
	local hitbox = Kit.Hitbox(model)
	if not hitbox then return end
	local conns = {}
	Watched[model] = conns
	local pending = false
	local function queue()
		if pending then return end
		pending = true
		task.delay(0.3, function()
			pending = false
			if Watched[model] then Stop(model) Start(model) end
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

CollectionService:GetInstanceAddedSignal(Kit.PLACED_TAG):Connect(function(model) task.spawn(Watch, model) end)
CollectionService:GetInstanceRemovedSignal(Kit.PLACED_TAG):Connect(Unwatch)
for _, model in ipairs(CollectionService:GetTagged(Kit.PLACED_TAG)) do task.spawn(Watch, model) end
if folder then
	folder.ChildAdded:Connect(function(m)
		Load(m)
		for _, model in ipairs(CollectionService:GetTagged(Kit.PLACED_TAG)) do task.spawn(Watch, model) end
	end)
end

--..Server events..--
if Remote then
	Remote.OnClientEvent:Connect(function(model, action, payload)
		local ctx = Running[model]
		if not ctx then return end
		local handler = ctx.Behaviour.OnEvent
		if type(handler) ~= "function" then return end
		local ok, err = pcall(handler, model, action, payload, ctx)
		if not ok then warn("[FunBuildClient] " .. tostring(ctx.Key) .. " OnEvent " .. tostring(action) .. ": " .. tostring(err)) end
	end)
end

--..Build mode hides every functional-build prompt..--
local function InBuildMode()
	local hud = playerGui:FindFirstChild(HUD_NAME)
	return hud ~= nil and hud:GetAttribute("BuildMode") == true
end
local function SyncPrompt(prompt)
	if not prompt:IsA("ProximityPrompt") then return end
	if InBuildMode() then
		if prompt:GetAttribute("FunHidden") ~= true and prompt.Enabled then
			prompt:SetAttribute("FunHidden", true)
			prompt.Enabled = false
		end
	elseif prompt:GetAttribute("FunHidden") == true then
		prompt:SetAttribute("FunHidden", nil)
		prompt.Enabled = true
	end
end
local function SyncAllPrompts()
	for _, prompt in ipairs(CollectionService:GetTagged(Kit.PROMPT_TAG)) do SyncPrompt(prompt) end
end
CollectionService:GetInstanceAddedSignal(Kit.PROMPT_TAG):Connect(SyncPrompt)
task.spawn(function()
	local hud = playerGui:WaitForChild(HUD_NAME, 60)
	if hud then
		hud:GetAttributeChangedSignal("BuildMode"):Connect(SyncAllPrompts)
		SyncAllPrompts()
	end
end)

--..Lying seats: straighten the occupant every frame (after the Animator has posed it)..--
local LIE_FLEX = { -- joint name -> extra pose while lying (applied as the joint Transform); everything else goes straight
	LeftShoulder = CFrame.Angles(0, 0, math.rad(-8)), RightShoulder = CFrame.Angles(0, 0, math.rad(8)),
	LeftHip = CFrame.Angles(0, 0, math.rad(3)), RightHip = CFrame.Angles(0, 0, math.rad(-3)),
	Neck = CFrame.Angles(math.rad(-12), 0, 0),
}
local LieSeats = {} -- [seat] = true
local function TrackSeat(seat)
	if seat:IsA("Seat") and seat:GetAttribute(Kit.LIE_ATTR) == true then LieSeats[seat] = true end
end
local runtime = workspace:WaitForChild(Kit.RUNTIME_FOLDER, 30)
if runtime then
	for _, d in ipairs(runtime:GetDescendants()) do TrackSeat(d) end
	runtime.DescendantAdded:Connect(TrackSeat)
	runtime.DescendantRemoving:Connect(function(d) LieSeats[d] = nil end)
end
RunService.Stepped:Connect(function()
	for seat in pairs(LieSeats) do
		if not seat.Parent then
			LieSeats[seat] = nil
		else
			local humanoid = seat.Occupant
			local character = humanoid and humanoid.Parent
			if character then
				for joint in pairs(Kit.Joints(character)) do
					local name = joint.Name
					if name ~= "Root" and name ~= "RootJoint" then
						joint.Transform = LIE_FLEX[name] or CFrame.identity
					end
				end
			end
		end
	end
end)

print("[FunBuildClient] ready")
