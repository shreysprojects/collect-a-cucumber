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
--.. A guardian is "asleep" to look at whenever it is sitting on its seat: Asleep is the
--.. night, Resting is the sit between patrols. Both get z's; a prowling or chasing one
--.. does not.
local SLEEPING = {Asleep = true, Resting = true}

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
