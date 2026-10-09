local RS=game:GetService("ReplicatedStorage")
local Actions=game:GetService("ContextActionService")
local Input=game:GetService("UserInputService")
local Index={}
function Index.Start(gui,menus)
    local view=require(gui.IndexView).Start(gui,RS:WaitForChild("CucumberIndexPreviews"))
    local remotes=RS:WaitForChild("Remotes")
    local bookRemote=remotes:WaitForChild("CucumberCollectionBook")
    local equipRemote=remotes:WaitForChild("EquipCucumberCollection")
    local event=remotes:WaitForChild("CucumberAdventure")
    local loading,dirty,destroyed=false,false,false
    local connections={}
    local function open() return gui:GetAttribute("OpenPanel")=="Index" end
    local refresh
    refresh=function()
        if destroyed or not open() then return end
        if loading then dirty=true;return end
        loading=true;dirty=false
        if not view.GetSnapshot() then view.Status("Loading your collection...") end
        local ok,data=pcall(bookRemote.InvokeServer,bookRemote)
        loading=false
        if destroyed or not gui.Parent then return end
        if not ok or type(data)~="table" then view.Status("Collection unavailable — reopen to retry");return end
        if data.Retry or not data.Ready then task.delay(1,refresh);return end
        view.Render(data)
        if dirty then task.delay(.6,refresh) end
    end
    table.insert(connections,gui:GetAttributeChangedSignal("OpenPanel"):Connect(function()
        if open() then task.spawn(refresh) end
    end))
    table.insert(connections,event.OnClientEvent:Connect(function(payload)
        if type(payload)=="table" and (payload.Kind=="Records" or payload.Kind=="BookChanged") then task.delay(.6,refresh) end
    end))
    local lastEquip=-math.huge
    table.insert(connections,gui.IndexPanel.Content.EquipReward.Activated:Connect(function()
        local row,data=view.GetRow(),view.GetSnapshot()
        if not row or not data or not row.Unlocked or os.clock()-lastEquip<.35 then return end
        lastEquip=os.clock()
        equipRemote:FireServer(data.Equipped==row.Zone and "" or row.Zone)
    end))
    Actions:BindAction("CucumberCollectionBook",function(_,state)
        if Input:GetFocusedTextBox() then return Enum.ContextActionResult.Pass end
        if state==Enum.UserInputState.Begin then menus.Toggle("Index") end
        return Enum.ContextActionResult.Sink
    end,false,Enum.KeyCode.J,Enum.KeyCode.ButtonR3)
    view.Status("Open a biome to explore your collection")
    if open() then task.spawn(refresh) end
    return {Destroy=function()
        destroyed=true
        for _,connection in connections do connection:Disconnect() end
        Actions:UnbindAction("CucumberCollectionBook")
        view.Destroy()
    end}
end
return Index