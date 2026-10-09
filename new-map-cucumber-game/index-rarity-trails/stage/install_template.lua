-- Adds the "Chance" label to StarterGui.CucumberMenus.Templates.CucumberCard (edit mode, idempotent).
-- IndexView fills it with "[1 in X]" (white; gold for the biome landmark) and hides it on common cards.
local gui = game:GetService("StarterGui"):FindFirstChild("CucumberMenus")
local card = gui and gui:FindFirstChild("Templates") and gui.Templates:FindFirstChild("CucumberCard")
if not card then return "NO CucumberCard template" end
local number = card:FindFirstChild("Number")
local label = card:FindFirstChild("Chance")
if not label then
	label = Instance.new("TextLabel")
	label.Name = "Chance"
	label.Parent = card
end
label.BackgroundTransparency = 1
label.BorderSizePixel = 0
label.Position = UDim2.fromOffset(72, 8)
label.Size = UDim2.fromOffset(170, 30)
label.ZIndex = number and number.ZIndex or 10
label.Font = Enum.Font.FredokaOne
label.TextScaled = true
label.TextSize = 24
label.Text = "[1 in 10]"
label.TextColor3 = Color3.new(1, 1, 1)
label.TextXAlignment = Enum.TextXAlignment.Right
label.TextYAlignment = Enum.TextYAlignment.Center
label.Visible = false -- IndexView shows it per card
local stroke = label:FindFirstChild("TextOutline")
if not stroke then
	local source = number and number:FindFirstChild("TextOutline")
	stroke = source and source:Clone() or Instance.new("UIStroke")
	stroke.Name = "TextOutline"
	stroke.Parent = label
end
stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
stroke.Thickness = 2.5
stroke.Color = number and number:FindFirstChild("TextOutline") and number.TextOutline.Color or Color3.fromRGB(36, 25, 29)
return ("Chance label ready: pos=%s size=%s z=%d"):format(tostring(label.Position), tostring(label.Size), label.ZIndex)
