-- One reference layout; scale uniformly and keep each HUD group on its screen edge.
local GuiService = game:GetService("GuiService")
local Layout = {}
Layout.Reference = Vector2.new(1301, 611)
Layout.TrackerFactor = 0.92
Layout.TrackerBaseScale = 611 / 941

function Layout.GetTopInset(viewport)
	if viewport.X < 700 then
		return GuiService:GetGuiInset().Y
	end
	return 0
end

function Layout.GetScale(viewport)
	local referenceWidth = if viewport.X < viewport.Y then 700 else 1301
	return math.max(0.05, math.min(viewport.X / referenceWidth, (viewport.Y - Layout.GetTopInset(viewport)) / 611))
end

function Layout.GetBottomMargin(viewport)
	local s = Layout.GetScale(viewport)
	-- Portrait leaves the lower fifth clear for Roblox touch controls.
	return if viewport.X < viewport.Y then math.max(54*s, viewport.Y*0.2) else 28*s
end

local function scaleObject(object, scale)
	local value = object:FindFirstChild("ResponsiveScale") or Instance.new("UIScale")
	value.Name = "ResponsiveScale"
	value.Scale = scale
	value.Parent = object
end

function Layout.ApplyMain(main, viewport)
	local s = Layout.GetScale(viewport)
	local top = Layout.GetTopInset(viewport)
	local specs = {
		LeftDock = { Vector2.new(0, 0.5), UDim2.new(0, 18*s, 0.5, 10*s) },
		RightDock = { Vector2.new(1, 0.5), UDim2.new(1, -14*s, 0.5, -5*s) },
		FriendDock = { Vector2.new(1, 1), UDim2.new(1, -10*s, 1, -6*s) },
		BottomDock = { Vector2.new(0.5, 1), UDim2.new(0.5, 0, 1, -Layout.GetBottomMargin(viewport)) },
		ReadoutDock = { Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, top + 104*s) },
	}
	for name, spec in pairs(specs) do
		local dock = main:FindFirstChild(name)
		if dock then
			dock.AnchorPoint = spec[1]
			dock.Position = spec[2]
			scaleObject(dock, s)
		end
	end
	main:SetAttribute("HUDScale", s)
end

function Layout.BindMain(main)
	local screen = main:FindFirstAncestorWhichIsA("ScreenGui")
	local function update() Layout.ApplyMain(main, screen.AbsoluteSize) end
	update()
	return screen:GetPropertyChangedSignal("AbsoluteSize"):Connect(update)
end

function Layout.BindRide(root, screen)
	local function update()
		local s = Layout.GetScale(screen.AbsoluteSize)
		root.AnchorPoint = Vector2.new(0.5, 1)
		root.Position = UDim2.new(0.5, 0, 1, -Layout.GetBottomMargin(screen.AbsoluteSize)-66*s)
		root.Size = UDim2.fromOffset(318, 44)
		scaleObject(root, s)
	end
	update()
	return screen:GetPropertyChangedSignal("AbsoluteSize"):Connect(update)
end

function Layout.BindHint(screen)
	local hint = screen:WaitForChild("Hint")
	local function update()
		local s = Layout.GetScale(screen.AbsoluteSize)
		hint.AnchorPoint = Vector2.new(0.5, 1)
		hint.Position = UDim2.new(0.5, 0, 1, -Layout.GetBottomMargin(screen.AbsoluteSize)-72*s)
		hint.Size = UDim2.fromOffset(314, 35)
		scaleObject(hint, s)
	end
	update()
	return screen:GetPropertyChangedSignal("AbsoluteSize"):Connect(update)
end

return Layout
