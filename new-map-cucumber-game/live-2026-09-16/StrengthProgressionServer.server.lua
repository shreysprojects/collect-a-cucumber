-- Reads saved numeric strength; never writes strength or profile data.
local Players=game:GetService("Players")
local Progression=require(game.ReplicatedStorage:WaitForChild("Modules"):WaitForChild("StrengthProgression"))
local Physique=require(game.ServerStorage:WaitForChild("CharacterPhysique"))
local CucumberLift=require(game.ReplicatedStorage.Modules:WaitForChild("CucumberLift"))
local sessions={}
local remotes=game.ReplicatedStorage:WaitForChild("Remotes")
local slowModeRequest=remotes:FindFirstChild("SetSlowMode")
if not slowModeRequest then
 slowModeRequest=Instance.new("RemoteEvent")
 slowModeRequest.Name="SetSlowMode"
 slowModeRequest.Parent=remotes
end
slowModeRequest.OnServerEvent:Connect(function(player,enabled)
 if typeof(enabled)~="boolean" or not sessions[player] then return end
 player:SetAttribute("SlowMode",enabled)
end)
local function disconnect(list)
 for _,connection in list do connection:Disconnect() end
 table.clear(list)
end
-- 2026-09-19: the boost pad (BoostPadService) doubles the walk while the player attribute
-- SpeedBoostUntil (server time) is still ahead; every speed written below goes through this
local BOOST_MULT=2
local function boostMult(player)
 local untilTime=tonumber(player:GetAttribute("SpeedBoostUntil"))
 return (untilTime and untilTime>workspace:GetServerTimeNow()) and BOOST_MULT or 1
end
local function onPlayer(player)
 if sessions[player] then return end
 local state={connections={},characterConnections={},ready=false,pending=false}
 sessions[player]=state
 if player:GetAttribute("SlowMode")==nil then player:SetAttribute("SlowMode",false) end
 local function refresh()
  if sessions[player]~=state then return end
  local strength=state.strength and state.strength.Value or 0
  local tier,stage=Progression.GetStage(strength)
  local speed=Progression.GetWalkSpeed(strength)
  player:SetAttribute("StrengthWalkSpeed",speed)
  player:SetAttribute("UnlockedPhysiqueStage",tier)
  local character=player.Character
  local humanoid=character and character:FindFirstChildOfClass("Humanoid")
  if not humanoid then return end
  -- 2026-09-17: a carried cucumber heavier than the strength slows the walk (CucumberLift.SpeedFor, 1 at the weight .. 0.45 at the lightest liftable)
  local kg=tonumber(player:GetAttribute("CarryingCucumberKg"))
  local mult=kg and CucumberLift.SpeedFor(CucumberLift.Ratio(strength,kg)) or 1
  local movementSpeed=(player:GetAttribute("SlowMode")==true and 16 or speed*mult)*boostMult(player)
  humanoid.WalkSpeed=movementSpeed
  if not state.ready or humanoid.Health<=0 then return end
  if character:GetAttribute("PhysiqueStage")==tier then return end
  -- Wait for standing/empty shoulder so training and carrying are not disrupted.
  if humanoid.SeatPart or humanoid.Sit or player:GetAttribute("CarryingCucumber") then return end
  local ok,result=pcall(Physique.Apply,character,strength)
  if ok then
   -- Physique.Apply also sets speed; restore the movement setting after resizing.
   humanoid.WalkSpeed=movementSpeed
   player:SetAttribute("PhysiqueStage",tier)
   player:SetAttribute("PhysiqueName",stage.Name)
   player:SetAttribute("PhysiqueHeight",character:GetAttribute("PhysiqueHeight"))
  else
   warn("[StrengthProgression] "..player.Name..": "..tostring(result))
  end
 end
 local function queueRefresh()
  if state.pending then return end
  state.pending=true
  task.defer(function()
   state.pending=false
   refresh()
  end)
 end
 local function characterAdded(character)
  disconnect(state.characterConnections)
  state.ready=false
  task.spawn(function()
   local humanoid=character:WaitForChild("Humanoid",15)
   local root=character:WaitForChild("HumanoidRootPart",15)
   if not humanoid or not root or player.Character~=character or sessions[player]~=state then return end
   humanoid.WalkSpeed=(player:GetAttribute("SlowMode")==true and 16 or Progression.GetWalkSpeed(state.strength and state.strength.Value or 0))*boostMult(player)
   local deadline=os.clock()+20
   while not player:HasAppearanceLoaded() and os.clock()<deadline and player.Character==character do task.wait(.05) end
   if player.Character~=character or sessions[player]~=state then return end
   -- Native avatar scales, meshes and accessories must be present before calibration.
   for _,name in {"BodyHeightScale","BodyWidthScale","BodyDepthScale","HeadScale","BodyTypeScale","BodyProportionScale"} do
    if not humanoid:WaitForChild(name,5) then
     warn("[StrengthProgression] Missing R15 avatar scales for "..player.Name)
     return
    end
   end
   state.ready=true
   table.insert(state.characterConnections,humanoid:GetPropertyChangedSignal("SeatPart"):Connect(queueRefresh))
   table.insert(state.characterConnections,humanoid:GetPropertyChangedSignal("Sit"):Connect(queueRefresh))
   queueRefresh()
  end)
 end
 table.insert(state.connections,player.CharacterAdded:Connect(characterAdded))
 table.insert(state.connections,player:GetAttributeChangedSignal("CarryingCucumber"):Connect(queueRefresh))
 table.insert(state.connections,player:GetAttributeChangedSignal("CarryingCucumberKg"):Connect(queueRefresh))
 table.insert(state.connections,player:GetAttributeChangedSignal("SlowMode"):Connect(queueRefresh))
 -- the boost: re-derive now, and again the moment it runs out (a stale delay just re-derives the same speed)
 table.insert(state.connections,player:GetAttributeChangedSignal("SpeedBoostUntil"):Connect(function()
  queueRefresh()
  local untilTime=tonumber(player:GetAttribute("SpeedBoostUntil"))
  if untilTime then task.delay(math.max(0,untilTime-workspace:GetServerTimeNow())+0.05,queueRefresh) end
 end))
 if player.Character then characterAdded(player.Character) end
 task.spawn(function()
  local data=player:WaitForChild("Data",60)
  local strength=data and data:WaitForChild("Strength",60)
  if not strength or sessions[player]~=state then return end
  state.strength=strength
  table.insert(state.connections,strength.Changed:Connect(queueRefresh))
  queueRefresh()
 end)
end
Players.PlayerRemoving:Connect(function(player)
 local state=sessions[player]
 if state then
  sessions[player]=nil
  disconnect(state.connections)
  disconnect(state.characterConnections)
 end
end)
Players.PlayerAdded:Connect(onPlayer)
for _,player in Players:GetPlayers() do onPlayer(player) end
print("[StrengthProgression] Six physique upgrades, 5.5-8 stud bodies, WalkSpeed 25-120")
