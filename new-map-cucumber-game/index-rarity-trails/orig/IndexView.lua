local View = {}
local C=Color3.fromRGB

function View.Start(gui, previews)
    local panel=gui.IndexPanel.Content
    local grid=panel.CucumberGrid
    local template=gui.Templates.CucumberCard
    local tabs=panel.BiomeTabs
    local snapshot, selectedZone = nil, "Spawn"
    local tabConnections={}
    local currentRow=nil
    local function clearGrid()
        for _,o in grid:GetChildren() do if o:IsA("GuiObject") then o:Destroy() end end
    end
    local function addViewport(card,zone,name,seen)
        local vp=card.CucumberViewport
        vp:ClearAllChildren()
        local source=previews:FindFirstChild(zone.." "..name) or previews:FindFirstChild(name)
        if not source then
            local fallback={Cucumber="Spawn Cucumber",["Giant Cucumber"]="Spawn Cucumber",["Sliced Cucumber"]="Spawn Sliced Cucumber",["Cucumber Tree"]="Cucumber Tree"}
            source=previews:FindFirstChild(fallback[name] or "")
        end
        if not source then return end
        local world=Instance.new("WorldModel");world.Name="PreviewWorld";world.Parent=vp
        local model=source:Clone();model.Parent=world
        model:PivotTo(CFrame.Angles(0,math.rad(-18),0))
        -- 2026-09-18: Toyland / Neon have their own hand-modelled previews now; the purple / cyan
        -- repaint that dressed up the borrowed generic previews for those two biomes is gone
        local cf,size=model:GetBoundingBox()
        local camera=Instance.new("Camera");camera.Name="PreviewCamera";camera.FieldOfView=32;camera.Parent=vp
        local distance=math.max(size.Y,size.X/(232/151),size.Z)*1.95
        camera.CFrame=CFrame.lookAt(cf.Position+Vector3.new(.1,.18,1).Unit*distance,cf.Position)
        camera.Focus=cf;vp.CurrentCamera=camera
        vp.ImageColor3=Color3.new(1,1,1)
    end
    local render
    render=function()
        clearGrid()
        if not snapshot then return end
        currentRow=nil
        for _,row in ipairs(snapshot.Rows or {}) do if row.Zone==selectedZone then currentRow=row break end end
        if not currentRow then currentRow=(snapshot.Rows or {})[1];selectedZone=currentRow and currentRow.Zone or "Spawn" end
        if not currentRow then
            panel.CollectionCount.Text="No cucumbers available yet"
            panel.EquipReward.Visible=false
            return
        end
        local row=currentRow
        local count,total=0,0
        for _,zoneRow in ipairs(snapshot.Rows) do count+=zoneRow.Count or 0;total+=zoneRow.Total or 0 end
        panel.Header.Subtitle.Text=string.format("%d / %d DISCOVERED  ·  %d SECURED",count,total,snapshot.Total or 0)
        panel.CollectionCount.RichText=true
        panel.CollectionCount.Text=string.format('%s   <font color="#FFFFFF">%d/%d</font>',row.Zone,row.Count or 0,row.Total or 0)
        local progress=math.clamp((row.Total or 0)>0 and (row.Count or 0)/row.Total or 0,0,1)
        panel.CollectionProgress.Fill.Size=UDim2.fromScale(progress,1)
        panel.CollectionProgress.Fill.Visible=progress>0
        panel.CollectionProgress.Fill.BackgroundColor3=Color3.new(1,1,1)
        local equipped=snapshot.Equipped==row.Zone
        local equip=panel.EquipReward
        equip.Visible=true;equip.Active=row.Unlocked==true
        equip:SetAttribute("Unlocked",row.Unlocked==true)
        equip.LockIcon.Visible=not row.Unlocked
        equip.Label.Position=UDim2.fromOffset(row.Unlocked and 8 or 61,1)
        equip.Label.Size=UDim2.new(1,row.Unlocked and -16 or -73,1,-2)
        equip.Label.Text=row.Unlocked and (equipped and "UNEQUIP" or "EQUIP REWARD") or "LOCKED"
        equip.Gradient.Color=ColorSequence.new(row.Unlocked and C(149,255,70) or C(149,172,180),row.Unlocked and C(63,204,28) or C(104,130,143))
        panel.Footer.Text=row.Unlocked and "Title + carry trail unlocked!" or "Complete this biome to unlock its title + carry trail."
        panel.BestLift.Text="Best lift: "..(snapshot.BestName or "None yet")
        for _,tab in tabs:GetChildren() do
            if tab:IsA("TextButton") then
                local active=tab.Name==row.Zone
                tab.BackgroundColor3=Color3.new(1,1,1)
                tab.Gradient.Color=ColorSequence.new(active and C(15,224,255) or C(146,177,207),active and C(0,170,240) or C(74,113,148))
                tab.InnerRim.Border.Color=active and C(128,245,255) or C(184,213,238)
            end
        end
        for n,item in ipairs(row.Names or {}) do
            local card=template:Clone();card.Name="Cucumber_"..n;card.LayoutOrder=n;card.Visible=true
            card:SetAttribute("CucumberName",item.Name);card:SetAttribute("Zone",row.Zone);card:SetAttribute("Collected",item.Seen==true)
            card.NamePlate.CucumberName.Text=item.Name
            card.NamePlate.Status.Text=item.Seen and "COLLECTED" or "NOT COLLECTED"
            card.NamePlate.BackgroundColor3=Color3.new(1,1,1)
            card.NamePlate.Gradient.Color=ColorSequence.new(item.Seen and C(23,222,158) or C(113,157,190),item.Seen and C(0,154,101) or C(64,102,137))
            card.NamePlate.InnerRim.Border.Color=item.Seen and C(63,247,176) or C(146,185,205)
            card.CollectedCheck.Visible=item.Seen==true
            card.Number.Text=string.format("#%02d",n)
            local question=card:FindFirstChild("Undiscovered");if question then question:Destroy() end
            addViewport(card,row.Zone,item.Name,item.Seen)
            card.Parent=grid
        end
    end
    local api={}
    function api.Render(data)
        snapshot=data
        for _,connection in tabConnections do connection:Disconnect() end
        table.clear(tabConnections)
        local oldScroll=tabs.CanvasPosition
        for _,tab in tabs:GetChildren() do if tab:IsA("GuiObject") then tab:Destroy() end end
        for order,row in ipairs(data.Rows or {}) do
            local tab=gui.Templates.BiomeTab:Clone();tab.Name=row.Zone;tab.Text="";tab.Label.Text=row.Zone;tab.LayoutOrder=order;tab.Visible=true;tab.Parent=tabs
            table.insert(tabConnections,tab.Activated:Connect(function()
                selectedZone=row.Zone;grid.CanvasPosition=Vector2.zero;render()
            end))
        end
        tabs.CanvasPosition=oldScroll
        render()
    end
    function api.SelectZone(zone) selectedZone=zone;grid.CanvasPosition=Vector2.zero;render() end
    function api.GetRow() return currentRow end
    function api.GetSnapshot() return snapshot end
    function api.Status(text)
        panel.CollectionCount.Text=text
        if not snapshot then clearGrid();panel.EquipReward.Visible=false end
    end
    function api.Destroy()
        for _,connection in tabConnections do connection:Disconnect() end
    end
    return api
end
return View