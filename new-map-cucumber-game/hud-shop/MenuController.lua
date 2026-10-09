local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Controller = {}

function Controller.Start(gui, hud)
    local panels = {Shop = gui.ShopPanel.Content, Index = gui.IndexPanel.Content}
    local dimmer = gui.Dimmer
    local connections, activeTweens = {}, {}
    local activeName = nil
    local revision = 0
    local destroyed = false
    local function connect(signal, callback)
        table.insert(connections, signal:Connect(callback))
    end
    local function animate(instance, duration, goals, style, direction)
        if activeTweens[instance] then activeTweens[instance]:Cancel() end
        local tween = TweenService:Create(instance, TweenInfo.new(duration, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), goals)
        activeTweens[instance] = tween
        tween:Play()
        return tween
    end
    -- 2026-09-10: each panel fits its OWN authored size (ShopPanel 1140x735 like the Zombie store,
    -- IndexPanel 860x580) into the screen with the same margins
    local function fit()
        local size = gui.AbsoluteSize
        for _, panel in pairs(panels) do
            local design = panel.Parent.Size
            local width = math.max(1, design.X.Offset)
            local height = math.max(1, design.Y.Offset)
            local scale = math.min(1, (size.X - 32) / width, (size.Y - 44) / height)
            panel.Parent.ResponsiveScale.Scale = math.max(0.25, scale)
        end
    end
    local function show(name)
        if destroyed then return end
        if name and not panels[name] then return end
        revision += 1
        local token = revision
        activeName = name
        gui:SetAttribute("OpenPanel", name or "")
        for key, panel in pairs(panels) do
            if key == name then
                if not panel.Visible then
                    panel.Position = UDim2.fromScale(0.5, 0.54)
                    panel.GroupTransparency = 1
                    panel.MotionScale.Scale = 0.9
                end
                panel.Visible = true
                animate(panel, 0.24, {Position = UDim2.fromScale(0.5, 0.5), GroupTransparency = 0})
                animate(panel.MotionScale, 0.32, {Scale = 1}, Enum.EasingStyle.Back)
            elseif panel.Visible then
                animate(panel, 0.16, {Position = UDim2.fromScale(0.5, 0.53), GroupTransparency = 1}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
                animate(panel.MotionScale, 0.16, {Scale = 0.94})
                task.delay(0.17, function()
                    if not destroyed and revision == token and activeName ~= key then panel.Visible = false end
                end)
            end
        end
        if name then
            dimmer.Visible = true
            animate(dimmer, 0.2, {BackgroundTransparency = 0.42})
        else
            animate(dimmer, 0.17, {BackgroundTransparency = 1})
            task.delay(0.18, function()
                if not destroyed and revision == token and not activeName then
                    dimmer.Visible = false
                    for _, panel in pairs(panels) do panel.Visible = false end
                end
            end)
        end
    end
    -- hover / press pops; a HoverBaseScale attribute on the target is the resting scale (the wide
    -- boost card's pills sit at 0.81 like the Zombie store's)
    local function hover(button, target)
        target = target or button
        local base = tonumber(target:GetAttribute("HoverBaseScale")) or 1
        local scale = target:FindFirstChild("HoverScale") or Instance.new("UIScale")
        scale.Name = "HoverScale"; scale.Scale = base; scale.Parent = target
        connect(button.MouseEnter, function() animate(scale, 0.12, {Scale = base * 1.035}) end)
        connect(button.MouseLeave, function() animate(scale, 0.12, {Scale = base}) end)
        connect(button.InputBegan, function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then animate(scale, 0.08, {Scale = base * 0.97}) end
        end)
        connect(button.InputEnded, function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then animate(scale, 0.1, {Scale = base}) end
        end)
    end
    for name, panel in pairs(panels) do
        panel.Visible = false
        panel.GroupTransparency = 1
        local opener = hud.LeftMenu[name]:WaitForChild("Open" .. name)
        connect(opener.Activated, function()
            if activeName == name then show(nil) else show(name) end
        end)
        hover(opener, opener.Parent)
        connect(panel.CloseButton.Activated, function() show(nil) end)
        hover(panel.CloseButton)
    end
    for _, item in gui:GetDescendants() do
        if item:IsA("GuiButton") and item:GetAttribute("PurchaseTemplate") then hover(item) end
    end
    connect(dimmer.Activated, function() show(nil) end)
    connect(UserInputService.InputBegan, function(input, processed)
        if not processed and input.KeyCode == Enum.KeyCode.Escape and activeName then show(nil) end
    end)
    connect(gui:GetPropertyChangedSignal("AbsoluteSize"), fit)
    -- 2026-09-10: other scripts open a panel on a section by writing the gui attribute
    -- OpenRequest = "<Panel>[:<Section>][#<nonce>]" (the HUD "+" writes "Shop:Strength#n");
    -- the section lands in the panel's RequestedTab attribute (ShopController scrolls to it)
    connect(gui:GetAttributeChangedSignal("OpenRequest"), function()
        local request = gui:GetAttribute("OpenRequest")
        if type(request) ~= "string" or request == "" then return end
        local name, section = request:match("^(%a+):?([%w_]*)")
        if not name or not panels[name] then return end
        local panel = panels[name].Parent
        if section ~= "" then
            -- clear first so an unchanged section still re-fires (deferred attribute signals
            -- read the final value; the defer keeps the two writes in separate steps)
            panel:SetAttribute("RequestedTab", "")
            task.defer(function() if not destroyed then panel:SetAttribute("RequestedTab", section) end end)
        end
        show(name)
    end)
    dimmer.Visible = false; dimmer.BackgroundTransparency = 1
    fit()
    local api = {}
    function api.Open(name, section)
        if section and panels[name] then
            local panel = panels[name].Parent
            panel:SetAttribute("RequestedTab", "")
            task.defer(function() if not destroyed then panel:SetAttribute("RequestedTab", section) end end)
        end
        show(name)
    end
    function api.Close() show(nil) end
    function api.Toggle(name)
        if activeName == name then show(nil) else show(name) end
    end
    function api.GetOpenPanel() return activeName end
    function api.Destroy()
        destroyed = true
        for _, connection in connections do connection:Disconnect() end
        for _, tween in pairs(activeTweens) do tween:Cancel() end
    end
    return api
end
return Controller
