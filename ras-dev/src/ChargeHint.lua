--[[---------------------------------------DESCRIPTION------------------------------------------
	"HOLD TO LAUNCH" prompt. GUIFramework spawns the ScreenGui template
	(ServerStorage.Assets.UserInterfaces.ChargeHint.Interface) straight into PlayerGui as
	"ChargeHint" (self.UI, manifest Parent = {}). Its own ScreenGui, above the ride controls,
	so it can show while the charge bar itself is hidden; the Hint label scales with the HUD
	(HUDLayout.BindHint). CLIENT_Snowball shows it while the player stands on the launch pad
	and hides it while charging, riding or with a panel open.

--------------------------------------------------------------------------------------------]]--

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HUDLayout = require(ReplicatedStorage.Assets.Modules.Client.UI.HUDLayout)
local Notify = require(ReplicatedStorage.Assets.Modules.Client.UI.Notify)
local mountainConfig = require(ReplicatedStorage.Assets.Modules.Shared.MountainConfig)()

local api = {}
api.Connections = {}

function api:DisconnectEvents()
	for _, connection in self.Connections do
		connection:Disconnect()
	end
	table.clear(self.Connections)
end

function api:ConnectEvents()
	self:DisconnectEvents()
end

function api:GetLabel()
	local gui = self.UI
	return gui and gui:FindFirstChild("Hint")
end

function api:SetVisible(visible)
	local label = self:GetLabel()
	if label then
		label.Visible = visible == true
	end
end

function api:Initialize()
	local gui = self.UI
	if not (gui and gui:IsA("ScreenGui")) then
		warn("[CLIENT]: ChargeHint interface missing")
		return
	end
	self:DisconnectEvents()
	local label = gui:WaitForChild("Hint")
	local charge = mountainConfig.LAUNCH.Charge
	label.Text = (charge and charge.HintText) or "HOLD TO LAUNCH"
	label.Visible = false
	Notify.AvoidAbove(label) -- toasts stay above the hint while it shows
	table.insert(self.Connections, HUDLayout.BindHint(gui))
end

return api
