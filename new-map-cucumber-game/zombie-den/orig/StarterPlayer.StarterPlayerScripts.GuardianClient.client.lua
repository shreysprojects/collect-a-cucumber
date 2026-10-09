--[[
	GuardianClient  (StarterPlayer.StarterPlayerScripts)  2026-09-15

	Two jobs:

	  1. Everything the guardian chase SAYS to a player, in the one notification style the
	     game uses everywhere else (ReplicatedStorage.Modules.Notify).
	  2. The drifting z's over a guardian that is sitting down.

	The KNOCKBACK is deliberately NOT here: a guardian's catch fires the ZombieRaid remote
	with {Kind = "Hit"}, so ZombieRaidClient's proven 10-stud parabola does the flight and
	its own toast reads "A Strawman knocked you back!" with no change to that script.

	The z's are built on the SERVER (so they replicate once) and animated HERE, stepped on
	Heartbeat rather than tweened - the same split the cucumber idle FX uses. It costs no
	network traffic, and Heartbeat keeps running while the Studio window is unfocused,
	which TweenService does not.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Notify = require(Modules:WaitForChild("Notify"))
local Catalog = require(Modules:WaitForChild("GuardianCatalog"))

local Remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild(Catalog.REMOTE)

--================================================================ toasts
local SHOW = {
	Error = Notify.Error,
	Warn = Notify.Warn,
	Success = Notify.Success,
	Info = Notify.Info,
}

Remote.OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" then return end
	if payload.Kind == "Toast" then
		local show = SHOW[payload.Tone] or Notify.Info
		show(tostring(payload.Text or ""), tonumber(payload.Seconds) or 2.5)
	end
end)

--================================================================ sleeping z's
--.. 2026-09-23 (user): only a real sleep gets z's - the night, and the day-time NAP (SleepUntil on the model).
--.. A guardian sitting with its eyes lit between patrols is AWAKE, and the label over its head says so.
local SLEEPING = {Asleep = true}

--================================================================ the sleep timer
--.. "💤 23s" over a napping guardian (counting down SleepUntil, a server time), "AWAKE" in red while it is up by
--.. day, nothing at night. Sized in studs like every overhead label in this game.
local timers = {} -- [model] = label
local function timerFor(model, zzz)
	local label = timers[model]
	if label and label.Parent then return label end
	local root = model:FindFirstChild("HumanoidRootPart")
	if not root then return nil end
	local gui = Instance.new("BillboardGui")
	gui.Name = "SleepTimer"
	gui.Size = UDim2.fromScale(Catalog.TIMER_WIDTH or 6, Catalog.TIMER_HEIGHT or 1.4)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 7, 0) -- placed properly by placeTimer once the z's are streamed in
	gui.MaxDistance = 260
	gui.AlwaysOnTop = false
	gui.ResetOnSpawn = false
	label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(130, 255, 80)
	label.Text = ""
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Color3.fromRGB(12, 12, 12)
	stroke.Parent = label
	label.Parent = gui
	gui.Parent = root
	timers[model] = label
	return label
end

--.. 2026-09-23 (user): the label sits RIGHT above the head. The server's Zzz gui is centred ZZZ_HEAD_GAP above the
--.. head top, so the head top is its offset minus that gap; the label's centre goes half its height above the head
--.. (+ a small gap) and the z's are lifted (locally) to start above the label instead of through it.
local function placeTimer(label, zzz)
	local gui = label.Parent
	if not (gui and zzz) or gui:GetAttribute("Placed") then return end
	local headTop = zzz.StudsOffsetWorldSpace.Y - (Catalog.ZZZ_HEAD_GAP or 1.6)
	local height = Catalog.TIMER_HEIGHT or 1.4
	gui.StudsOffsetWorldSpace = Vector3.new(0, headTop + 0.3 + height * 0.5, 0)
	zzz.StudsOffsetWorldSpace = Vector3.new(0, headTop + 0.3 + height + (Catalog.ZZZ_HEAD_GAP or 1.6), 0)
	gui:SetAttribute("Placed", true)
end

local function labelsOf(gui)
	local out = {}
	for _, c in ipairs(gui:GetChildren()) do
		if c:IsA("TextLabel") then table.insert(out, c) end
	end
	table.sort(out, function(a, b) return a.Name < b.Name end)
	return out
end

local cache = {}          -- [model] = {gui, labels}

local function entryFor(model)
	local hit = cache[model]
	if hit and hit.gui.Parent then return hit end
	local root = model:FindFirstChild("HumanoidRootPart")
	local gui = root and root:FindFirstChild("Zzz")
	if not gui then return nil end
	hit = {gui = gui, labels = labelsOf(gui)}
	cache[model] = hit
	return hit
end

RunService.Heartbeat:Connect(function()
	local folder = Workspace:FindFirstChild(Catalog.FOLDER)
	if not folder then return end
	local clock = os.clock()
	for _, model in ipairs(folder:GetChildren()) do
		if model:IsA("Model") and model:GetAttribute("Guardian") then
			local hit = entryFor(model)
			--.. the sleep timer / AWAKE label (2026-09-23)
			local label = timerFor(model, hit and hit.gui)
			if label then
				placeTimer(label, hit and hit.gui)
				local state = model:GetAttribute("State")
				local day = Workspace:GetAttribute("CyclePhase") == "Day"
				local sleepUntil = tonumber(model:GetAttribute("SleepUntil"))
				if not day then
					label.Text = ""
				elseif state == "Asleep" and sleepUntil then
					local left = math.max(0, math.ceil(sleepUntil - Workspace:GetServerTimeNow()))
					label.Text = "💤 " .. left .. "s"
					label.TextColor3 = Color3.fromRGB(130, 255, 80)
				elseif state == "Asleep" then
					label.Text = "💤"
					label.TextColor3 = Color3.fromRGB(130, 255, 80)
				else
					--.. 2026-09-23 (user): "AWAKE FOR 12s" counting down AwakeUntil; a chase that outlasts its window
					--.. (or a guardian up without a clock) just says AWAKE
					local awakeUntil = tonumber(model:GetAttribute("AwakeUntil"))
					local left = awakeUntil and math.ceil(awakeUntil - Workspace:GetServerTimeNow()) or 0
					label.Text = left > 0 and ("AWAKE FOR " .. left .. "s") or "AWAKE"
					label.TextColor3 = Color3.fromRGB(255, 79, 105)
				end
			end
			if hit then
				local sleeping = SLEEPING[model:GetAttribute("State")] == true
				if hit.gui.Enabled ~= sleeping then hit.gui.Enabled = sleeping end
				if sleeping then
					local n = #hit.labels
					for i, label in ipairs(hit.labels) do
						--.. each z is the same rise, offset in phase, so they file upward
						local t = ((clock / Catalog.ZZZ_PERIOD) + (i - 1) / n) % 1
						local rise = t * Catalog.ZZZ_RISE
						local drift = math.sin(t * math.pi * 1.6 + i) * Catalog.ZZZ_DRIFT
						--.. fade in over the first fifth, out over the last half
						local alpha = math.clamp(t / 0.2, 0, 1) * (1 - math.clamp((t - 0.5) / 0.5, 0, 1))
						label.Position = UDim2.fromScale(0.5 + drift * 0.18, 0.62 - rise * 0.22)
						label.Size = UDim2.fromScale(0.26 + t * 0.34, 0.26 + t * 0.34)
						label.Rotation = drift * 14
						label.TextTransparency = 1 - alpha
						local stroke = label:FindFirstChildOfClass("UIStroke")
						if stroke then stroke.Transparency = 1 - alpha * 0.9 end
					end
				end
			end
		end
	end
end)
