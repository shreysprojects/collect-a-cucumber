local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Controller = {}
-- 2026-09-22 (pets): panel -> opener paths are explicit; the Pets paw sits beside the left menu and is
-- optional, so a missing PetsPanel or paw never blocks Shop / Index
-- 2026-09-23: the Pets menu / paw were removed (backup backups/NewMap_PetsMenu_before-removal_2026-09-23.rbxm);
-- reserve pets live in the hotbar (PetInventoryService) and a click on a pet opens PetInfoClient's frame
local OPENERS = {Shop = {"LeftMenu", "Shop", "OpenShop"}, Index = {"LeftMenu", "Index", "OpenIndex"}, Manage = {"LeftMenu", "Manage", "ManageButton"}}
local OPTIONAL = {Manage = true}
local CLOSE_ON_BASE = {Shop = true, Index = true} -- their openers tuck away inside the base; Pets stays open
-- 2026-09-23: Manage's opener only shows inside the base (BaseHUDController), so leaving the base closes it;
-- BaseHUDController already gives that button its hover / press pop (HoverScale), so MenuController must not
local CLOSE_OUTSIDE = {Manage = true}
local NO_HOVER = {Manage = true}

function Controller.Start(gui, hud)
    local panels = {Shop = gui.ShopPanel.Content, Index = gui.IndexPanel.Content}
    -- 2026-09-23: no Pets panel any more (see OPENERS)
    -- 2026-09-23: the Manage panel (ManageController fills it)
    local managePanel = gui:FindFirstChild("ManagePanel")
    if managePanel and managePanel:FindFirstChild("Content") then panels.Manage = managePanel.Content end
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
    -- Fit each panel to the viewport, then reduce it by 14% to leave room around the menu.
    -- 2026-09-22: a panel's FitMargin attribute replaces the 0.86 (the Pets panel sets a larger one so phones get bigger text)
    local function fit()
        local size = gui.AbsoluteSize
        for _, panel in pairs(panels) do
            local design = panel.Parent.Size
            local width = math.max(1, design.X.Offset)
            local height = math.max(1, design.Y.Offset)
            local margin = tonumber(panel.Parent:GetAttribute("FitMargin")) or 0.86
            local scale = math.min(1, (size.X - 32) / width, (size.Y - 44) / height) * margin
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
            -- Keep outside-click dismissal without darkening the game.
            dimmer.BackgroundTransparency = 1
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
        -- 2026-09-22: the opener path comes from OPENERS; an OPTIONAL one waits up to 10 s per step in its
        -- own thread (Start never stalls on it) and is skipped with a warning when it never appears
        local path = OPENERS[name]
        local function wireOpener(opener)
            connect(opener.Activated, function()
                if activeName == name then show(nil) else show(name) end
            end)
            if not NO_HOVER[name] then hover(opener, opener.Parent) end
        end
        if OPTIONAL[name] then
            task.spawn(function()
                local node = hud
                for _, part in ipairs(path) do
                    node = node:WaitForChild(part, 10)
                    if not node then
                        if not destroyed then warn("[MenuController] " .. name .. " opener " .. table.concat(path, ".") .. " not found; the panel still opens by request") end
                        return
                    end
                end
                if not destroyed then wireOpener(node) end
            end)
        else
            wireOpener(hud[path[1]][path[2]]:WaitForChild(path[3]))
        end
        connect(panel.CloseButton.Activated, function() show(nil) end)
        hover(panel.CloseButton)
    end
    for _, item in gui:GetDescendants() do
        if item:IsA("GuiButton") and item:GetAttribute("PurchaseTemplate") then hover(item) end
    end
    connect(hud:GetAttributeChangedSignal("BaseMode"), function()
        -- 2026-09-22: only panels whose openers tuck away in the base close there (Pets stays open)
        if hud:GetAttribute("BaseMode") and activeName and CLOSE_ON_BASE[activeName] then show(nil) end
        if not hud:GetAttribute("BaseMode") and activeName and CLOSE_OUTSIDE[activeName] then show(nil) end
    end)
    -- 2026-09-22: entering build mode (its E prompt still works while a panel is open) closes whatever is open
    connect(hud:GetAttributeChangedSignal("BuildMode"), function()
        if hud:GetAttribute("BuildMode") == true and activeName then show(nil) end
    end)
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
