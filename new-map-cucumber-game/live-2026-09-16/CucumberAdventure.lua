-- Server-owned collection records, field traits and cosmetic rewards.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Http = game:GetService("HttpService")
local Data = require(script.Parent.DataService)
local M = {}
local remotes = RS:WaitForChild("Remotes")
local function remote(class, name)
 local r = remotes:FindFirstChild(name) or Instance.new(class)
 r.Name, r.Parent = name, remotes
 return r
end
local event = remote("RemoteEvent", "CucumberAdventure")
local bookRemote = remote("RemoteFunction", "CucumberCollectionBook")
local equipRemote = remote("RemoteEvent", "EquipCucumberCollection")
local catalog, order = {}, {}
local lastBook, lastEquip = {}, {}
local colors = {Spawn=Color3.fromRGB(125,255,95), Desert=Color3.fromRGB(255,199,85), Samurai=Color3.fromRGB(255,135,188), Farm=Color3.fromRGB(250,226,97), Snow=Color3.fromRGB(158,231,255), Underwater=Color3.fromRGB(60,210,232), Volcano=Color3.fromRGB(255,110,62), Narmek=Color3.fromRGB(176,117,255), Toyland=Color3.fromRGB(255,133,235), Neon=Color3.fromRGB(58,255,207)}
local function state(player)
 local d = Data.GetData(player)
 if not d then return nil end
 if type(d.CucumberCollection) ~= "table" then d.CucumberCollection = {} end
 local s = d.CucumberCollection
 s.Seen = type(s.Seen)=="table" and s.Seen or {}
 s.Families = type(s.Families)=="table" and s.Families or {}
 s.BestRequired = tonumber(s.BestRequired) or 0
 s.BestSize = tonumber(s.BestSize) or 0
 s.TotalSecured = tonumber(s.TotalSecured) or 0
 return s
end
function M.SetCatalog(zones, typesFor)
 catalog, order = {}, table.clone(zones)
 for _,zone in order do
  local names = {}
  for _,t in typesFor(zone) do if not t.Missing and not table.find(names,t.Name) then table.insert(names,t.Name) end end
  table.sort(names)
  catalog[zone] = names
 end
end
local function snapshot(player)
 local s = state(player)
 if not s then return {Ready=false} end
 local rows = {}
 for _,zone in order do
  local names, count = {}, 0
  for _,name in catalog[zone] do
   local seen = s.Seen[zone..":"..name] == true
   if seen then count += 1 end
   table.insert(names,{Name=name,Seen=seen})
  end
  table.insert(rows,{Zone=zone,Names=names,Count=count,Total=#names,Unlocked=s.Families[zone]==true,Color=colors[zone]})
 end
 return {Ready=true,Rows=rows,Equipped=s.Equipped,BestRequired=s.BestRequired,BestName=s.BestName,Total=s.TotalSecured,FirstImpossible=s.FirstImpossible==true}
end
local function title(player)
 local char = player.Character
 local head = char and char:FindFirstChild("Head")
 if not head then return end
 local old = head:FindFirstChild("CucumberCollectorTitle")
 if old then old:Destroy() end
 local zone = player:GetAttribute("CucumberCollectorCosmetic")
 if not zone then return end
 local gui=Instance.new("BillboardGui")
 gui.Name,gui.Size,gui.StudsOffset,gui.AlwaysOnTop = "CucumberCollectorTitle",UDim2.fromOffset(210,28),Vector3.new(0,3.4,0),true
 gui.MaxDistance=65
 local text=Instance.new("TextLabel")
 text.Size,text.BackgroundTransparency,text.Text=UDim2.fromScale(1,1),1,zone.." Collector"
 text.Font,text.TextSize,text.TextColor3=Enum.Font.FredokaOne,18,colors[zone] or Color3.new(1,1,1)
 text.TextStrokeTransparency,text.TextStrokeColor3=0,Color3.fromRGB(15,25,20)
 text.Parent,gui.Parent=gui,head
end
function M.ApplyCosmetic(player, model)
 for _,v in model:GetDescendants() do if v.Name=="CollectionTrail" or v.Name=="CollectionTrailA" or v.Name=="CollectionTrailB" then v:Destroy() end end
 local zone=player:GetAttribute("CucumberCollectorCosmetic")
 local part=model.PrimaryPart
 if not zone or not part then return end
 local a,b=Instance.new("Attachment"),Instance.new("Attachment")
 a.Name,b.Name="CollectionTrailA","CollectionTrailB"
 a.Position,b.Position=Vector3.new(-.35,0,0),Vector3.new(.35,0,0)
 a.Parent,b.Parent=part,part
 local trail=Instance.new("Trail")
 trail.Name,trail.Attachment0,trail.Attachment1="CollectionTrail",a,b
 trail.Lifetime,trail.MinLength,trail.LightEmission=.4,.08,.6
 trail.Color=ColorSequence.new(colors[zone] or Color3.new(1,1,1))
 trail.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,.15),NumberSequenceKeypoint.new(1,1)})
 trail.Parent=part
end
local function equip(player,zone)
 local s=state(player)
 if not s or (zone~="" and (type(zone)~="string" or not catalog[zone] or not s.Families[zone])) then return false end
 s.Equipped=zone~="" and zone or nil
 player:SetAttribute("CucumberCollectorCosmetic",s.Equipped)
 title(player)
 local model=player.Character and player.Character:FindFirstChild("CarriedCucumber")
 if model then M.ApplyCosmetic(player,model) end
 Data.RequestSave(player)
 event:FireClient(player,{Kind="BookChanged"})
 return true
end
bookRemote.OnServerInvoke=function(player)
 local now=os.clock()
 if now-(lastBook[player] or -10)<.5 then return {Retry=true} end
 lastBook[player]=now
 return snapshot(player)
end
equipRemote.OnServerEvent:Connect(function(player,zone)
 if os.clock()-(lastEquip[player] or -10)<.3 then return end
 lastEquip[player]=os.clock()
 equip(player,zone)
end)
function M.Secured(player, entry)
 if entry.Recorded then return end
 local s=state(player)
 if not s then
  task.spawn(function()
   if Data.WaitForData(player,20) then M.Secured(player,entry) end
  end)
  return
 end
 entry.Recorded=true
 entry.RecordedBy=player.UserId
 s.TotalSecured+=1
 local messages={}
 local required=tonumber(entry.Required) or 0
 local size=tonumber(entry.SizeScale) or 1
 if s.TotalSecured==1 or required>s.BestRequired or (required==s.BestRequired and size>s.BestSize) then
  s.BestRequired,s.BestSize,s.BestName=required,size,entry.Name
  table.insert(messages,"New heaviest cucumber secured! "..entry.Name)
 end
 if entry.OriginalBand=="hopeless" and not s.FirstImpossible then
  s.FirstImpossible=true
  table.insert(messages,"First Impossible carry secured!")
 end
 if workspace:GetAttribute("CyclePhase")=="Day" then
  local left=(workspace:GetAttribute("PhaseEndsAt") or 0)-workspace:GetServerTimeNow()
  if left>0 and left<=5 then table.insert(messages,string.format("Close call! Home with %.1fs to spare!",left)) end
 end
 local key=entry.Zone..":"..entry.TypeName
 local names=catalog[entry.Zone]
 if names and table.find(names,entry.TypeName) and not s.Seen[key] then
  s.Seen[key]=true
  local count=0
  for _,name in names do if s.Seen[entry.Zone..":"..name] then count+=1 end end
  if count==#names and not s.Families[entry.Zone] then
   s.Families[entry.Zone]=true
   table.insert(messages,entry.Zone.." collection complete! Title + carry trail unlocked!")
   if not s.Equipped then equip(player,entry.Zone) end
  else
   table.insert(messages,string.format("New discovery! %s collection: %d/%d",entry.Zone,count,#names))
  end
 end
 Data.RequestSave(player)
 event:FireClient(player,{Kind="Records",Messages=messages})
end
function M.Decorate(holder, fixed, roll)
 local trait=fixed and fixed.Trait
 if not trait then
  local mutations=holder:GetAttribute("Mutations") or ""
  local r=roll()
  trait=holder:GetAttribute("SizeTier") and "Giant" or (mutations:find("FROZEN",1,true) and "Slippery") or (r<.18 and "Slippery") or (r<.33 and "Bouncy") or "Normal"
 end
 holder:SetAttribute("CarryTrait",trait)
 holder:SetAttribute("JourneyId",fixed and fixed.JourneyId or Http:GenerateGUID(false))
 holder:SetAttribute("JourneyRecorded",fixed and fixed.Recorded==true or false)
 holder:SetAttribute("JourneyRecordedBy",fixed and fixed.RecordedBy or nil)
 holder:SetAttribute("JourneyRecoveryUsed",fixed and fixed.RecoveryUsed==true or false)
 holder:SetAttribute("RescueCount",fixed and fixed.Rescues or 0)
end
function M.DropMetadata(entry)
 return {Material=entry.Material,Mutations=entry.Mutations,SizeTier=entry.SizeTier,Trait=entry.Trait,JourneyId=entry.JourneyId,Recorded=entry.Recorded,RecordedBy=entry.RecordedBy,RecoveryUsed=entry.RecoveryUsed,Rescues=entry.Rescues}
end
function M.Rescue(holder, player, entry)
 if (entry.Rescues or 0)>=1 then return end
 holder:SetAttribute("RescueOwner",player.UserId)
 holder:SetAttribute("RescueUntil",workspace:GetServerTimeNow()+8)
 event:FireClient(player,{Kind="Rescue",Text="Dropped it? Grab it back quickly for a rescue pickup!"})
end
function M.Bounce(holder, delaySeconds)
 if holder:GetAttribute("CarryTrait")~="Bouncy" then return end
 task.delay(delaySeconds or 0,function()
  if not holder.Parent then return end
  local origin=holder:GetPivot()
  local started=os.clock()
  local connection
  connection=RunService.Heartbeat:Connect(function()
   if not holder.Parent then connection:Disconnect() return end
   local t=(os.clock()-started)/.8
   if t>=1 or holder:GetAttribute("CollectingBy") then holder:PivotTo(origin) connection:Disconnect() return end
   holder:PivotTo(origin+Vector3.new(0,math.abs(math.sin(t*math.pi*2))*2*(1-t),0))
  end)
 end)
end
Data.OnProfileLoaded(function(player)
 local s=state(player)
 if s and s.Equipped and s.Families[s.Equipped] then player:SetAttribute("CucumberCollectorCosmetic",s.Equipped) end
 title(player)
end)
local function added(player)
 player.CharacterAdded:Connect(function(char) char:WaitForChild("Head",10) title(player) end)
end
Players.PlayerAdded:Connect(added)
for _,p in Players:GetPlayers() do added(p) end
Players.PlayerRemoving:Connect(function(p) lastBook[p],lastEquip[p]=nil,nil end)
return M
