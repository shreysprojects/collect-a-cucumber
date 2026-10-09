--[[---------------------------------------DESCRIPTION------------------------------------------
	Hold-to-launch charge bar (the LoadingProgressGui from RAS - Maps). GUIFramework spawns the
	ScreenGui template (ServerStorage.Assets.UserInterfaces.ChargeBar.Interface) straight into
	PlayerGui as "ChargeBar" (self.UI, manifest Parent = {}), disabled. CLIENT_Snowball enables
	it while the player holds to charge and drives ProgressBar.Track.Fill / ProgressBar.Percent
	and the ResponsiveScale itself (see buildChargeBar / renderCharge there); this module only
	puts the bar into its resting state.

--------------------------------------------------------------------------------------------]]--

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

function api:Reset()
	local gui = self.UI
	if not gui then
		return
	end
	gui.Enabled = false
	local bar = gui:FindFirstChild("ProgressBar")
	local track = bar and bar:FindFirstChild("Track")
	local fill = track and track:FindFirstChild("Fill")
	local label = bar and bar:FindFirstChild("Percent")
	if fill then
		fill.Size = UDim2.fromScale(1, 0)
	end
	if label then
		label.Text = "0%"
	end
end

function api:Initialize()
	local gui = self.UI
	if not (gui and gui:IsA("ScreenGui")) then
		warn("[CLIENT]: ChargeBar interface missing")
		return
	end
	self:Reset()
end

return api
