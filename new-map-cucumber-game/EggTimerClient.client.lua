--[[
	EggTimerClient  (LocalScript, StarterPlayerScripts)
	"Egg" + countdown label on every placed egg (models tagged "PlacedEgg" by EggPlacement), like the
	reference screenshot: red "Egg" in heavy text with a dark outline, the time left underneath in
	white ("1h 12m", "4m 47s", then "47s"); at zero it reads a green "Ready!" and the owner steps on the
	egg to hatch it (PetHatchService, 2026-09-07).
	The server stamps the egg with the attribute HatchAt (workspace:GetServerTimeNow() when it
	hatches), so every client counts down the same clock without per-second replication.
	The BillboardGui is sized in STUDS (scale units, scale-only layout) so it shrinks with distance
	exactly like the plot owner badges instead of staying a fixed pixel size. It is NOT AlwaysOnTop
	(2026-09-07, user), so it floats just above the egg's top where nothing hides it.
]]
local CollectionService = game:GetService("CollectionService")

local TAG = "PlacedEgg"
local LABEL_W, LABEL_H = 6, 3.2 -- studs
local LABEL_GAP = 0.2 -- studs between the egg's top and the label's bottom edge
local EGG_COLOR = Color3.fromRGB(235, 40, 40)
local STROKE_COLOR = Color3.fromRGB(14, 14, 20)
local READY_COLOR = Color3.fromRGB(92, 235, 98) -- "Ready!" once the countdown hits zero (2026-09-07: hatching lives in PetHatchService)
local TICK = 0.5

local active = {} -- [model] = {Gui, Timer}

local function FormatRemaining(seconds)
	seconds = math.max(0, math.floor(seconds + 0.5))
	if seconds >= 3600 then
		return ("%dh %dm"):format(seconds // 3600, (seconds % 3600) // 60)
	end
	if seconds >= 60 then
		return ("%dm %ds"):format(seconds // 60, seconds % 60)
	end
	return ("%ds"):format(seconds)
end

local function Label(parent, name, text, color, y, h, weight)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.fromScale(0.5, y)
	label.Size = UDim2.fromScale(1, h)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = color
	label.Text = text
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.Parent = parent
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = weight
	stroke.Color = STROKE_COLOR
	stroke.Transparency = 0.05
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.Parent = label
	return label
end

local function Attach(model)
	if active[model] or not model:IsA("Model") then return end
	task.spawn(function()
		local root = model.PrimaryPart or model:WaitForChild("Hitbox", 10)
		if not root or active[model] then return end
		local gui = Instance.new("BillboardGui")
		gui.Name = "EggTimer"
		gui.Size = UDim2.fromScale(LABEL_W, LABEL_H) -- scale = studs: shrinks with distance
		gui.StudsOffset = Vector3.new(0, root.Size.Y * 0.5 + LABEL_GAP + LABEL_H * 0.5, 0) -- centred billboard: half its height above the egg's top
		gui.AlwaysOnTop = false
		gui.MaxDistance = 250
		gui.LightInfluence = 0
		gui.ResetOnSpawn = false
		Label(gui, "Title", "Egg", EGG_COLOR, 0, 0.52, 3)
		local timer = Label(gui, "Timer", "", Color3.new(1, 1, 1), 0.5, 0.45, 2.5)
		gui.Parent = root
		active[model] = {Gui = gui, Timer = timer}
	end)
end

local function Detach(model)
	local entry = active[model]
	if not entry then return end
	active[model] = nil
	if entry.Gui then entry.Gui:Destroy() end
end

for _, model in ipairs(CollectionService:GetTagged(TAG)) do Attach(model) end
CollectionService:GetInstanceAddedSignal(TAG):Connect(Attach)
CollectionService:GetInstanceRemovedSignal(TAG):Connect(Detach)

task.spawn(function()
	while true do
		local now = workspace:GetServerTimeNow()
		for model, entry in pairs(active) do
			if not model.Parent then
				Detach(model)
			else
				local hatchAt = tonumber(model:GetAttribute("HatchAt"))
				if hatchAt and hatchAt - now <= 0 then
					--.. ready: the owner steps on it to hatch (PetHatchService)
					entry.Timer.Text = "Ready!"
					entry.Timer.TextColor3 = READY_COLOR
				else
					entry.Timer.Text = hatchAt and FormatRemaining(hatchAt - now) or ""
				end
			end
		end
		task.wait(TICK)
	end
end)
