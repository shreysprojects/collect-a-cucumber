-- Slow Mode uses the server-confirmed setting and the normal movement controller.
local player=game:GetService("Players").LocalPlayer
local TweenService=game:GetService("TweenService")
local hud=script.Parent
local row=hud:WaitForChild("LeftMenu"):WaitForChild("SlowMode")
local toggle=row:WaitForChild("Toggle")
local track=row:WaitForChild("Track")
local thumb=track:WaitForChild("Thumb")
local remote=game:GetService("ReplicatedStorage"):WaitForChild("Remotes"):WaitForChild("SetSlowMode")
local slide,fill
local function Refresh(instant)
 local enabled=player:GetAttribute("SlowMode")==true
 row:SetAttribute("Enabled",enabled)
 local destination=UDim2.fromScale(enabled and 0.62 or 0.05,0.5)
 local color=enabled and Color3.fromRGB(84,237,18) or Color3.fromRGB(65,84,49)
 local transparency=enabled and 0.28 or 0.4
 if slide then slide:Cancel() end
 if fill then fill:Cancel() end
 if instant then
  thumb.Position=destination
  track.BackgroundColor3=color
  track.BackgroundTransparency=transparency
 else
  local info=TweenInfo.new(0.18,Enum.EasingStyle.Quad,Enum.EasingDirection.Out)
  slide=TweenService:Create(thumb,info,{Position=destination})
  fill=TweenService:Create(track,info,{BackgroundColor3=color,BackgroundTransparency=transparency})
  slide:Play()
  fill:Play()
 end
end
local lastClick=0
toggle.Activated:Connect(function()
 local now=os.clock()
 if now-lastClick<0.2 then return end
 lastClick=now
 remote:FireServer(player:GetAttribute("SlowMode")~=true)
end)
player:GetAttributeChangedSignal("SlowMode"):Connect(function() Refresh(false) end)
-- 2026-09-19 (user): also hidden while lying on a plot's bench press (Humanoid.SeatPart = its
-- LieSeat, inside the model tagged PlotBench); back as soon as the player gets up
local CollectionService=game:GetService("CollectionService")
local onBench=false
local function IsBenchSeat(seat)
 if not seat then return false end
 if seat.Name=="LieSeat" then return true end
 local a=seat.Parent
 while a and a~=workspace do
  if CollectionService:HasTag(a,"PlotBench") then return true end
  a=a.Parent
 end
 return false
end
local function Visibility()
 row.Visible=hud:GetAttribute("BuildMode")~=true and not onBench
end
local seatConn
local function WatchCharacter(character)
 if seatConn then seatConn:Disconnect() seatConn=nil end
 onBench=false
 Visibility()
 local humanoid=character:WaitForChild("Humanoid",10)
 if not humanoid or player.Character~=character then return end
 local function update()
  onBench=IsBenchSeat(humanoid.SeatPart)
  Visibility()
 end
 seatConn=humanoid:GetPropertyChangedSignal("SeatPart"):Connect(update)
 update()
end
hud:GetAttributeChangedSignal("BuildMode"):Connect(Visibility)
player.CharacterAdded:Connect(WatchCharacter)
if player.Character then task.spawn(WatchCharacter,player.Character) end
Refresh(true)
Visibility()
