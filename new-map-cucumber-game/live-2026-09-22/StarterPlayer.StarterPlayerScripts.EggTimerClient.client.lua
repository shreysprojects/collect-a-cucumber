-- Placed egg mutation/material, egg name, and hatch countdown labels.
local CollectionService = game:GetService("CollectionService")

local TAG = "PlacedEgg"
local LABEL_W, LABEL_H = 8, 4.2 -- studs
local LABEL_GAP = 0.2 -- studs between the egg's top and the label's bottom edge
local Mutations = require(game:GetService("ReplicatedStorage"):WaitForChild("Modules"):WaitForChild("CucumberMutations"))
local NAME_COLORS = {
	Basic = Color3.fromRGB(200, 255, 170), Desert = Color3.fromRGB(255, 210, 110),
	Samurai = Color3.fromRGB(255, 125, 150), Farm = Color3.fromRGB(110, 240, 125),
	Frozen = Color3.fromRGB(150, 225, 255), Ocean = Color3.fromRGB(65, 200, 255),
	Lava = Color3.fromRGB(255, 120, 45), Narmek = Color3.fromRGB(195, 130, 255),
}
local function EggLabels(model)
	local name = tostring(model:GetAttribute("EggName") or model.Name):gsub("%s+[Ee][Gg][Gg]$", "")
	local material = model:GetAttribute("Material")
	if not material or material == "" then material = model:GetAttribute("Golden") and "Golden" or nil end
	local words = {}
	if material and Mutations.ColorOf(material) then
		table.insert(words, Mutations.Font(material, Mutations.ColorOf(material), true))
	end
	for _, mutation in ipairs(Mutations.Parse(model:GetAttribute("Mutations"))) do
		table.insert(words, Mutations.Font(mutation, Mutations.ColorOf(mutation), true))
	end
	return Mutations.Font(name .. " Egg", NAME_COLORS[name] or Color3.new(1, 1, 1), true),
		#words > 0 and table.concat(words, " + ") or Mutations.Font("Normal", Color3.fromRGB(225, 225, 235))
end
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
	label.RichText = true
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
		if not root or active[model] or not model.Parent or not CollectionService:HasTag(model, TAG) then return end
		local gui = Instance.new("BillboardGui")
		gui.Name = "EggTimer"
		gui.Size = UDim2.fromScale(LABEL_W, LABEL_H) -- scale = studs: shrinks with distance
		gui.StudsOffset = Vector3.new(0, root.Size.Y * 0.5 + LABEL_GAP + LABEL_H * 0.5, 0) -- centred billboard: half its height above the egg's top
		gui.AlwaysOnTop = false
		gui.MaxDistance = 250
		gui.LightInfluence = 0
		gui.ResetOnSpawn = false
		local title = Label(gui, "Title", "", Color3.new(1, 1, 1), .3, .35, 3)
		local mutation = Label(gui, "Mutations", "", Color3.new(1, 1, 1), 0, .28, 2.5)
		local timer = Label(gui, "Timer", "", Color3.new(1, 1, 1), .67, .31, 2.5)
		local function refreshLabels() title.Text, mutation.Text = EggLabels(model) end
		refreshLabels()
		local connections = {}
		for _, attribute in ipairs({"EggName", "Material", "Golden", "Mutations"}) do
			table.insert(connections, model:GetAttributeChangedSignal(attribute):Connect(refreshLabels))
		end
		gui.Parent = root
		active[model] = {Gui = gui, Timer = timer, Connections = connections}
	end)
end

local function Detach(model)
	local entry = active[model]
	if not entry then return end
	active[model] = nil
	for _, connection in ipairs(entry.Connections) do connection:Disconnect() end
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
					entry.Timer.TextColor3 = Color3.new(1, 1, 1)
				end
			end
		end
		task.wait(TICK)
	end
end)