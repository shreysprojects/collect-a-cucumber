-- Server-owned day / night cycle on the SHARED REAL-TIME CLOCK (2026-09-06).
-- Every server derives the day number and the phase from workspace:GetServerTimeNow() measured
-- from CYCLE_EPOCH, so all servers turn to night, clear and reseed at the same moment, and
-- CucumberSpawner seeds its rolls with that day number, so every server spawns the same cucumbers
-- with the same mutations. Days last DayDurationSeconds (180), nights NightDurationSeconds (10);
-- both are attributes on this script (changing them renumbers the days everywhere at once).
-- A server that starts mid-day spawns that day's set at once; one that starts mid-night waits
-- out the rest of the night.
-- Night includes the rise, hold, and retreat of the existing NightBarrier. Only players standing
-- in the biome lane when night falls (or found inside it during the night) are returned to the
-- lobby; players already in the lobby stay where they are.
-- The barrier's parts are in the "NightBarrier" collision group and never collide with the biome
-- guardians ("Guardians" group, set by GuardianService); see the block below (2026-09-18).
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local map = workspace:WaitForChild("Map")
local lobby = map:WaitForChild("Lobby")
local barrier = map:WaitForChild("Borders"):WaitForChild("NightBarrier")
local fields = workspace:WaitForChild("SpawnArea")
local api = ServerStorage:WaitForChild("CucumberSpawnerAPI")
local beginDay = api:WaitForChild("BeginDay")
local beginNight = api:WaitForChild("BeginNight")
local dropForNight = ServerStorage:WaitForChild("CucumberCarryAPI"):WaitForChild("DropForNight")

-- Admin panel (2026-09-12): ServerStorage.DayNightAPI.Force("Night" | "Day") ends the current phase now.
-- A forced night runs NightDurationSeconds from now; a forced day runs a full day from now; then the
-- shared clock takes over again (the next schedule() call).
local forced
do
 local api=ServerStorage:FindFirstChild("DayNightAPI") or Instance.new("Folder")
 api.Name="DayNightAPI"
 api.Parent=ServerStorage
 local force=api:FindFirstChild("Force") or Instance.new("BindableEvent")
 force.Name="Force"
 force.Parent=api
 force.Event:Connect(function(phase)
  local current=workspace:GetAttribute("CyclePhase")
  if phase=="Night" and current~="Night" then forced="Night"
  elseif phase=="Day" and current=="Night" then forced="Day" end
 end)
end

local CYCLE_EPOCH = 1788652800 -- 2026-09-06 00:00:00 UTC: day 1 of the shared calendar on every server

while not lobby:GetAttribute("LayoutReady") do task.wait(.05) end

local function seconds(attribute, default)
 local value = script:GetAttribute(attribute)
 return typeof(value) == "number" and math.max(1, value) or default
end

-- Where every server is in the shared cycle at `now` (GetServerTimeNow, seconds since the epoch).
local function schedule(now)
 local daySeconds = seconds("DayDurationSeconds", 180)
 local nightSeconds = seconds("NightDurationSeconds", 10)
 local cycle = daySeconds + nightSeconds
 local index = math.floor((now - CYCLE_EPOCH) / cycle)
 local dayStart = CYCLE_EPOCH + index * cycle
 return {
  Day = index + 1,
  DayStart = dayStart,
  NightStart = dayStart + daySeconds,
  NextDayStart = dayStart + cycle,
  DaySeconds = daySeconds,
  NightSeconds = nightSeconds,
 }
end

-- Bounds use world axes, including rotated floor and plot parts.
local function halfExtent(part)
 local cf, half = part.CFrame, part.Size * .5
 return Vector3.new(
  math.abs(cf.XVector.X)*half.X + math.abs(cf.YVector.X)*half.Y + math.abs(cf.ZVector.X)*half.Z,
  math.abs(cf.XVector.Y)*half.X + math.abs(cf.YVector.Y)*half.Y + math.abs(cf.ZVector.Y)*half.Z,
  math.abs(cf.XVector.Z)*half.X + math.abs(cf.YVector.Z)*half.Y + math.abs(cf.ZVector.Z)*half.Z)
end
local floor
for _,part in lobby:WaitForChild("Floor"):GetDescendants() do
 if part:IsA("BasePart") and (not floor or part.Size.X*part.Size.Z > floor.Size.X*floor.Size.Z) then
  floor = part
 end
end
assert(floor, "DayNightCycle needs a lobby floor")
local floorTop = floor.Position.Y + halfExtent(floor).Y

-- 2026-09-18: the wall must never touch the biome guardians. Every barrier part is in the
-- "NightBarrier" collision group and GuardianService puts every guardian part in "Guardians";
-- the two groups are set not to collide (here and there, whichever script runs first), so the
-- rising wall passes through a seated guardian instead of carrying it up on its top for the
-- night, and a server started mid-night no longer spawns them inside the solid wall (physics
-- ejected them downward past seat Y - 40 and GuardianService re-seated them inside the wall
-- again, twice a second, all night). Players stay in Default, which the wall still blocks.
local PhysicsService = game:GetService("PhysicsService")
local BARRIER_GROUP, GUARDIAN_GROUP = "NightBarrier", "Guardians"
for _,group in {BARRIER_GROUP, GUARDIAN_GROUP} do
 if not PhysicsService:IsCollisionGroupRegistered(group) then
  pcall(PhysicsService.RegisterCollisionGroup, PhysicsService, group)
 end
end
pcall(PhysicsService.CollisionGroupSetCollidable, PhysicsService, BARRIER_GROUP, GUARDIAN_GROUP, false)

-- Largest barrier part is the authored volume that already spans all ten biomes.
local fill
for _,part in barrier:GetDescendants() do
 if part:IsA("BasePart") then
  part.Anchored = true
  part.CollisionGroup = BARRIER_GROUP
  if not fill or part.Size.X*part.Size.Y*part.Size.Z > fill.Size.X*fill.Size.Y*fill.Size.Z then fill=part end
 end
end
assert(fill, "NightBarrier needs a BasePart")
local lowered = barrier:GetPivot()
local rise = floorTop - 1 - (fill.Position.Y - halfExtent(fill).Y)
local raised = lowered + Vector3.new(0, math.max(0,rise), 0)
barrier:SetAttribute("LoweredPivot", lowered)
barrier:SetAttribute("RaisedPivot", raised)

-- The biome lane = the barrier volume's footprint; the lobby lies outside it.
local fillHalf=halfExtent(fill)
local function inBiomeLane(position)
 return math.abs(position.X-fill.Position.X)<=fillHalf.X
  and math.abs(position.Z-fill.Position.Z)<=fillHalf.Z
end

local returnPoint = lobby:FindFirstChild("NightReturnPoint")
if not returnPoint then
 returnPoint = Instance.new("Part")
 returnPoint.Name = "NightReturnPoint"
 returnPoint.Size = Vector3.new(2,1,2)
 returnPoint.Anchored = true
 returnPoint.CanCollide = false
 returnPoint.CanTouch = false
 returnPoint.CanQuery = false
 returnPoint.Transparency = 1
 returnPoint.Parent = lobby
end
local function refreshLobbyReturn()
 local west = floor.Position.X-halfExtent(floor).X
 local east = floor.Position.X+halfExtent(floor).X
 local plotFront = east
 for _,plot in lobby.Plots:GetChildren() do
  if plot:IsA("BasePart") then
   plotFront = math.min(plotFront,plot.Position.X-halfExtent(plot).X)
  end
 end
 -- Center of the open lobby walkway, west of every plot, aligned with the entrance.
 local z=fields:WaitForChild("1").Position.Z
 local position=Vector3.new((west+plotFront)*.5,floorTop+3,z)
 returnPoint.CFrame=CFrame.lookAt(position,position+Vector3.new(-1,0,0))
 workspace:SetAttribute("LobbyReturnCFrame",returnPoint.CFrame)
end
refreshLobbyReturn()

local function returnPlayer(player, slot, count)
 local character=player.Character
 local root=character and character:FindFirstChild("HumanoidRootPart")
 local humanoid=character and character:FindFirstChildOfClass("Humanoid")
 if not root or not humanoid or humanoid.Health<=0 then return end
 -- Drop at the current biome position before moving the character to the lobby.
 local dropOK, dropError = pcall(dropForNight.Invoke, dropForNight, player)
 if not dropOK then warn("[DayNightCycle] Night carry drop failed: " .. tostring(dropError)) end
 -- Release seats before moving so benches are not carried into the lobby.
 humanoid.Sit=false
 local seat=humanoid.SeatPart
 local seatWeld=seat and seat:FindFirstChild("SeatWeld")
 if seatWeld then seatWeld:Destroy() end
 local offset=Vector3.zero
 if count and count>1 then
  local angle=((slot or 1)-1)*2*math.pi/count
  offset=Vector3.new(math.cos(angle)*5,0,math.sin(angle)*5)
 end
 local clearance=humanoid.HipHeight+root.Size.Y*.5+.15
 character:PivotTo(returnPoint.CFrame+offset+Vector3.new(0,clearance-3,0))
 for _,part in character:GetDescendants() do
  if part:IsA("BasePart") then
   part.AssemblyLinearVelocity=Vector3.zero
   part.AssemblyAngularVelocity=Vector3.zero
  end
 end
 player:SetAttribute("BiomeIndex",1)
end

-- A character that appears inside the lane during the night (a respawn there) is returned too;
-- a respawn at the plot is in the lobby already and is left alone.
local function onPlayer(player)
 player.CharacterAdded:Connect(function(character)
  local root=character:WaitForChild("HumanoidRootPart",10)
  if not root then return end
  task.wait(.15) -- after normal engine/plot spawn placement
  if workspace:GetAttribute("CyclePhase")=="Night" and character==player.Character and inBiomeLane(root.Position) then
   returnPlayer(player)
  end
 end)
end
Players.PlayerAdded:Connect(onPlayer)
for _,player in Players:GetPlayers() do onPlayer(player) end

local driver=Instance.new("CFrameValue")
driver.Value=lowered
driver:GetPropertyChangedSignal("Value"):Connect(function() barrier:PivotTo(driver.Value) end)
local barrierTween
local function moveBarrier(target,duration)
 if barrierTween then barrierTween:Cancel() end
 barrierTween=TweenService:Create(driver,TweenInfo.new(duration,Enum.EasingStyle.Quad,Enum.EasingDirection.InOut),{Value=target})
 barrierTween:Play()
end
local nightLightingTween
local originalBrightness=Lighting.Brightness
local originalAmbient=Lighting.Ambient
local originalOutdoorAmbient=Lighting.OutdoorAmbient

-- BRIGHT NIGHT (2026-09-23, user: "night as bright as day, no darkness, only the sky looks like
-- night"). The sun, Brightness and both ambients keep their DAY values through the night; the
-- night look is only the starry skybox swapped onto Lighting.Sky, a navy Atmosphere haze and no
-- sun rays. Attributes on this script (all optional):
--  NightSkyboxBk/Dn/Ft/Lf/Rt/Up (asset id number or content string) - default = the store set
--   "Starry night sky (Skybox)" 3451179493, a black sky full of small stars on all six faces.
--  NightAtmosphereColor / NightAtmosphereDecay (Color3) - default navy 40,45,70 / 20,24,44.
--  NightClockTime / NightBrightness / NightAmbient / NightOutdoorAmbient - unset = day values
--   (the old dark night was ClockTime 0 / Brightness 1 / 60,66,98 / 78,85,122).
local sky=Lighting:FindFirstChildOfClass("Sky")
local atmosphere=Lighting:FindFirstChildOfClass("Atmosphere")
local sunRays=Lighting:FindFirstChildOfClass("SunRaysEffect")
local SKY_FACES={"Bk","Dn","Ft","Lf","Rt","Up"}
local NIGHT_SKY_DEFAULT={Bk=3451163360,Dn=3451162694,Ft=3451161099,Lf=3451175494,Rt=3451160296,Up=3451161536}
local daySky={}
if sky then for _,face in SKY_FACES do daySky[face]=sky["Skybox"..face] end end
local dayAtmosphere=atmosphere and {Color=atmosphere.Color,Decay=atmosphere.Decay} or nil
local daySunRays=sunRays and sunRays.Enabled
local function nightTextureId(face)
 local value=script:GetAttribute("NightSkybox"..face)
 if typeof(value)=="number" and value>0 then return "rbxassetid://"..math.floor(value) end
 if typeof(value)=="string" and value~="" then return value end
 return "rbxassetid://"..NIGHT_SKY_DEFAULT[face]
end
local function applyNightSky()
 if sky then for _,face in SKY_FACES do sky["Skybox"..face]=nightTextureId(face) end end
 if atmosphere then
  local color=script:GetAttribute("NightAtmosphereColor")
  local decay=script:GetAttribute("NightAtmosphereDecay")
  atmosphere.Color=typeof(color)=="Color3" and color or Color3.fromRGB(40,45,70)
  atmosphere.Decay=typeof(decay)=="Color3" and decay or Color3.fromRGB(20,24,44)
 end
 if sunRays then sunRays.Enabled=false end
end
local function applyDaySky()
 if sky then for _,face in SKY_FACES do sky["Skybox"..face]=daySky[face] end end
 if atmosphere and dayAtmosphere then
  atmosphere.Color=dayAtmosphere.Color
  atmosphere.Decay=dayAtmosphere.Decay
 end
 if sunRays then sunRays.Enabled=daySunRays end
end

-- Phase attributes carry the SHARED start / end times, so a server that joined mid-phase reports
-- the same clock as every other server.
local function setPhase(phase,startedAt,endsAt)
 workspace:SetAttribute("CyclePhase",phase)
 workspace:SetAttribute("IsNight",phase=="Night")
 workspace:SetAttribute("PhaseStartedAt",startedAt)
 workspace:SetAttribute("PhaseEndsAt",endsAt)
end

-- Anyone found inside the lane while the volume rises or retreats is sent back.
local function nightWait(deadline)
 while workspace:GetServerTimeNow()<deadline do
  if forced=="Day" then return false end -- the admin panel ends the night
  for _,player in Players:GetPlayers() do
   local root=player.Character and player.Character:FindFirstChild("HumanoidRootPart")
   if root and inBiomeLane(root.Position) then returnPlayer(player) end
  end
  task.wait(math.min(.1,math.max(0,deadline-workspace:GetServerTimeNow())))
 end
end

-- The sun stays high all day (DayClockStart .. DayClockEnd, attributes on this script, default
-- 11 -> 16). The old 8 -> 18 sweep sank the sun into a dusk over the last minute of every day,
-- which read as "night is too dark / too long" (2026-09-07, user): darkness is now only the
-- NightDurationSeconds (10 s) night itself.
local function dayClock(s,now)
 local startClock=script:GetAttribute("DayClockStart")
 local endClock=script:GetAttribute("DayClockEnd")
 if typeof(startClock)~="number" then startClock=11 end
 if typeof(endClock)~="number" then endClock=16 end
 return startClock+(endClock-startClock)*math.clamp((now-s.DayStart)/s.DaySeconds,0,1)
end

-- The day (or what is left of it when the server started mid-day).
local function runDay(s)
 workspace:SetAttribute("CyclePhase","PreparingDay")
 workspace:SetAttribute("IsNight",false)
 driver.Value=lowered
 if nightLightingTween then nightLightingTween:Cancel() end
 Lighting.ClockTime=dayClock(s,workspace:GetServerTimeNow())
 Lighting.Brightness=originalBrightness
 Lighting.Ambient=originalAmbient
 Lighting.OutdoorAmbient=originalOutdoorAmbient
 applyDaySky()
 local okDay, dayErr = pcall(beginDay.Invoke, beginDay, s.Day) -- 2026-09-06: a spawner error used to kill this loop
 if not okDay then warn("[DayNightCycle] BeginDay failed: " .. tostring(dayErr)) end
 workspace:SetAttribute("DayNumber",s.Day)
 workspace:SetAttribute("DayDurationSeconds",s.DaySeconds)
 workspace:SetAttribute("NightDurationSeconds",s.NightSeconds)
 setPhase("Day",s.DayStart,s.NightStart)
 print(("[DayNightCycle] Day %d started (%gs day, %.0fs of it left on this server)"):format(s.Day,s.DaySeconds,s.NightStart-workspace:GetServerTimeNow()))
 while true do
  local now=workspace:GetServerTimeNow()
  if forced=="Night" then -- the admin panel ends the day: a full night starts now
   forced=nil
   s.NightStart=now
   s.NextDayStart=now+s.NightSeconds
   workspace:SetAttribute("PhaseEndsAt",now)
   print("[DayNightCycle] night forced by the admin panel")
   break
  end
  if now>=s.NightStart then break end
  Lighting.ClockTime=dayClock(s,now)
  task.wait(math.min(.1,math.max(0,s.NightStart-now)))
 end
end

-- The night (or what is left of it): only players in the biome lane are returned to the lobby.
local function runNight(s)
 local now=workspace:GetServerTimeNow()
 setPhase("Night",s.NightStart,s.NextDayStart)
 refreshLobbyReturn()
 local caught={}
 for _,player in Players:GetPlayers() do
  local root=player.Character and player.Character:FindFirstChild("HumanoidRootPart")
  if root and inBiomeLane(root.Position) then caught[#caught+1]=player end
 end
 for i,player in caught do returnPlayer(player,i,#caught) end
 beginNight:Invoke()
 -- Night look (2026-09-23, user: "bright night"): the light stays exactly as by day (the sun
 -- keeps its clock, Brightness and both ambients keep the day values) unless the optional
 -- NightClockTime / NightBrightness / NightAmbient / NightOutdoorAmbient attributes override
 -- them; the starry skybox + navy haze come from applyNightSky (see the block at the top).
 local nightClock=script:GetAttribute("NightClockTime")
 local nightBrightness=script:GetAttribute("NightBrightness")
 local nightAmbient=script:GetAttribute("NightAmbient")
 local nightOutdoor=script:GetAttribute("NightOutdoorAmbient")
 nightLightingTween=TweenService:Create(Lighting,TweenInfo.new(.5),{
  ClockTime=typeof(nightClock)=="number" and nightClock or Lighting.ClockTime,
  Brightness=typeof(nightBrightness)=="number" and nightBrightness or originalBrightness,
  Ambient=typeof(nightAmbient)=="Color3" and nightAmbient or originalAmbient,
  OutdoorAmbient=typeof(nightOutdoor)=="Color3" and nightOutdoor or originalOutdoorAmbient})
 nightLightingTween:Play()
 applyNightSky()
 local travel=math.min(1,s.NightSeconds*.25)
 if now-s.NightStart>=travel then
  driver.Value=raised -- joined mid-night: the wall is already up everywhere else
 else
  moveBarrier(raised,travel)
 end
 print(("[DayNightCycle] Night after day %d (%gs); %d player(s) returned from the biomes to the lobby"):format(s.Day,s.NightSeconds,#caught))
 nightWait(s.NextDayStart-travel)
 local endedEarly=false
 if forced=="Day" then -- the admin panel ends the night: lower the wall and start a full day
  forced=nil
  endedEarly=true
  s.NextDayStart=workspace:GetServerTimeNow()+travel
  print("[DayNightCycle] day forced by the admin panel")
 end
 moveBarrier(lowered,travel)
 nightWait(s.NextDayStart)
 if barrierTween then barrierTween:Cancel() end
 driver.Value=lowered
 return endedEarly
end

local pending -- a schedule the admin panel asked for: a forced day is a full day from now, off the shared clock
while true do
 local s=pending or schedule(workspace:GetServerTimeNow())
 pending=nil
 if workspace:GetServerTimeNow()<s.NightStart then runDay(s) end
 if runNight(s) then
  local now=workspace:GetServerTimeNow()
  pending={Day=s.Day+1,DayStart=now,NightStart=now+s.DaySeconds,NextDayStart=now+s.DaySeconds+s.NightSeconds,DaySeconds=s.DaySeconds,NightSeconds=s.NightSeconds}
 end
end
