--[[---------------------------------------DESCRIPTION------------------------------------------
	HUD module. GUIFramework spawns the empty "Interface" frame into PlayerGui.HUD.Base
	as "HUD" (self.UI); MainUI (side buttons, boosts, level bar) is cloned into it here.

	Shop / Mountains / Rebirth buttons open the frame of the same name IF one exists:
	  1. a panel already spawned by this module,
	  2. a template under this module (SetupInterfaces moves every frame from
	     ServerStorage.Assets.UserInterfaces.HUD here: MainUI, Shop, Mountains, ...),
	  3. anything under ReplicatedStorage.Assets.UserInterfaces,
	  4. any GuiObject of that name already in PlayerGui.
	Nothing named "Rebirth" exists yet, so that button only warns until a frame is added.

	Panels are cloned into PlayerGui.Menu.Basis.Window, one open at a time, toggled by
	their button, closed by their "X". PlayerGui attribute "PanelOpen" holds the open
	panel's name (hold-to-launch ignores presses while it is set). Dev hook: set the
	PlayerGui attribute "DevPanel" to a panel name to toggle it.

--------------------------------------------------------------------------------------------]]--

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BUTTON_PANELS = {
	Shop = "Shop",
	Mountains = "Mountains",
	Rebirth = "Rebirth",
}
local MENU_DISPLAY_ORDER = 5 -- panels draw above the HUD buttons

local api = {}
api.Connections = {}
api.Panels = {}

local function getPlayerGui()
	return Players.LocalPlayer:WaitForChild("PlayerGui")
end

local function getWindow()
	local playerGui = getPlayerGui()
	local menu = playerGui:FindFirstChild("Menu")
	if menu and menu:IsA("ScreenGui") and menu.DisplayOrder < MENU_DISPLAY_ORDER then
		menu.DisplayOrder = MENU_DISPLAY_ORDER
	end
	local basis = menu and menu:FindFirstChild("Basis")
	local window = basis and basis:FindFirstChild("Window")
	return window or playerGui:FindFirstChild("HUD") or playerGui
end

local function setPanelOpen(name)
	getPlayerGui():SetAttribute("PanelOpen", name)
end

-- Returns template, alreadySpawned
local function findFrame(self, name)
	local spawned = self.Panels[name]
	if spawned and spawned.Parent then
		return spawned, true
	end

	local template = script:FindFirstChild(name)
	if template and template:IsA("GuiObject") then
		return template, false
	end

	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local interfaces = assets and assets:FindFirstChild("UserInterfaces")
	if interfaces then
		for _, desc in interfaces:GetDescendants() do
			if desc:IsA("GuiObject") and desc.Name == name and not desc:IsDescendantOf(script) then
				return desc, false
			end
		end
	end

	for _, desc in getPlayerGui():GetDescendants() do
		if desc:IsA("GuiObject") and desc.Name == name and not (self.UI and desc:IsDescendantOf(self.UI)) then
			return desc, true
		end
	end

	return nil, false
end

function api:DisconnectEvents()
	for _, connection in self.Connections do
		connection:Disconnect()
	end
	table.clear(self.Connections)
end

function api:ConnectEvents()
	self:DisconnectEvents()
end

function api:WirePanel(panel)
	local close = panel:FindFirstChild("X", true)
	if close and close:IsA("GuiButton") then
		table.insert(self.Connections, close.Activated:Connect(function()
			panel.Visible = false
			setPanelOpen(nil)
		end))
	end
end

function api:ClosePanels(except)
	for name, panel in self.Panels do
		if name ~= except and panel.Parent then
			panel.Visible = false
		end
	end
	if not except then
		setPanelOpen(nil)
	end
end

function api:OpenPanel(name)
	local template, alreadySpawned = findFrame(self, name)
	if not template then
		warn("[CLIENT]: No frame named", name, "exists in the game yet")
		return nil
	end

	local panel = template
	if not alreadySpawned then
		panel = template:Clone()
		panel.Name = name
		panel.Visible = false
		panel.Parent = getWindow()
	end
	if self.Panels[name] ~= panel then
		self.Panels[name] = panel
		self:WirePanel(panel)
	end

	self:ClosePanels(name)
	panel.Visible = true
	setPanelOpen(name)
	return panel
end

function api:TogglePanel(name)
	local panel = self.Panels[name]
	if panel and panel.Parent and panel.Visible then
		panel.Visible = false
		setPanelOpen(nil)
		return nil
	end
	return self:OpenPanel(name)
end

function api:WireButtons(main)
	for buttonName, panelName in BUTTON_PANELS do
		local button = main:FindFirstChild(buttonName, true)
		if button and button:IsA("GuiButton") then
			table.insert(self.Connections, button.Activated:Connect(function()
				self:TogglePanel(panelName)
			end))
		else
			warn("[CLIENT]: HUD button not found:", buttonName)
		end
	end
end

function api:Initialize()
	local root = self.UI
	if not root then
		warn("[CLIENT]: HUD interface missing")
		return
	end

	local main = root:FindFirstChild("MainUI")
	if not main then
		local template = script:FindFirstChild("MainUI")
		if template then
			main = template:Clone()
			main.Parent = root
		end
	end
	if main then
		main.Visible = true
		self:WireButtons(main)
	else
		warn("[CLIENT]: HUD MainUI frame not found")
	end

	local playerGui = getPlayerGui()
	setPanelOpen(nil)
	table.insert(self.Connections, playerGui:GetAttributeChangedSignal("DevPanel"):Connect(function()
		local name = playerGui:GetAttribute("DevPanel")
		if typeof(name) == "string" and name ~= "" then
			self:TogglePanel(name)
		end
	end))

	print("[CLIENT]: HUD ready")
end

return api
