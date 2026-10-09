--[[
	build_hud.lua  (run in Studio EDIT mode through execute_luau; idempotent; receives the HUDClient
	source as its first vararg). Makes StarterGui.CucumberHUDDesign functional:
	  * CashIcon / CashValue -> CashIcon / CashValue with the Zombie game's gold cash (15402839520)
	    and gold text instead of green
	  * StrengthValue / CashValue anchored on their left-middle with a PopScale UIScale (value pops)
	  * AddStrength ("+") centre-anchored with a transparent OpenStrengthShop TextButton on top
	  * HUDClient LocalScript (live counters, night timer, the "+" -> Shop > Strength)
]]
local hudSource = ...
local gui = game:GetService("StarterGui"):WaitForChild("CucumberHUDDesign")
local counters = gui:WaitForChild("Counters")

local icon = counters:FindFirstChild("CashIcon") or counters:FindFirstChild("CashIcon")
assert(icon, "Counters.CashIcon / CashIcon missing")
icon.Name = "CashIcon"
icon.Image = "rbxassetid://15402839520"
icon.ImageColor3 = Color3.new(1, 1, 1)

local value = counters:FindFirstChild("CashValue") or counters:FindFirstChild("CashValue")
assert(value, "Counters.CashValue / CashValue missing")
value.Name = "CashValue"
value.Text = "0"
value.TextColor3 = Color3.fromRGB(255, 200, 60) -- the Zombie wallet's gold

local strength = counters:WaitForChild("StrengthValue")
strength.Text = "0"

for _, l in ipairs({strength, value}) do
	if l.AnchorPoint.Y ~= 0.5 then
		l.Position = UDim2.new(l.Position.X.Scale, l.Position.X.Offset, l.Position.Y.Scale + l.Size.Y.Scale * 0.5, l.Position.Y.Offset + l.Size.Y.Offset * 0.5)
		l.AnchorPoint = Vector2.new(0, 0.5)
	end
	l.TextXAlignment = Enum.TextXAlignment.Left
	if not l:FindFirstChild("PopScale") then
		local s = Instance.new("UIScale")
		s.Name = "PopScale"
		s.Parent = l
	end
end

local add = counters:WaitForChild("AddStrength")
if add.AnchorPoint ~= Vector2.new(0.5, 0.5) then
	add.Position = UDim2.new(add.Position.X.Scale + add.Size.X.Scale * 0.5, add.Position.X.Offset + add.Size.X.Offset * 0.5,
		add.Position.Y.Scale + add.Size.Y.Scale * 0.5, add.Position.Y.Offset + add.Size.Y.Offset * 0.5)
	add.AnchorPoint = Vector2.new(0.5, 0.5)
end
local button = add:FindFirstChild("OpenStrengthShop")
if not button then
	button = Instance.new("TextButton")
	button.Name = "OpenStrengthShop"
	button.Parent = add
end
button.Size = UDim2.fromScale(1, 1)
button.Position = UDim2.new()
button.BackgroundTransparency = 1
button.BorderSizePixel = 0
button.Text = ""
button.AutoButtonColor = false
button.ZIndex = 30

gui:WaitForChild("NightTimer"):WaitForChild("TimeLabel").Text = "in --"

gui:SetAttribute("DesignOnly", nil)
gui:SetAttribute("SampleValues", nil)
gui.LeftMenu.Shop:SetAttribute("DesignOnly", nil)
gui.LeftMenu.Index:SetAttribute("DesignOnly", nil)
gui:SetAttribute("Reference", "HUD: Shop/Index openers (MenuController), live Strength + Cash counters and the night timer (HUDClient), + button -> Shop > Strength")

local client = gui:FindFirstChild("HUDClient")
if not client then
	client = Instance.new("LocalScript")
	client.Name = "HUDClient"
	client.Parent = gui
end
if type(hudSource) == "string" and #hudSource > 0 then client.Source = hudSource end
print("[build_hud] HUD patched; HUDClient", #client.Source, "chars")
