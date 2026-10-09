local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local RunService=game:GetService("RunService")
local player=Players.LocalPlayer
local Notify=require(RS.Modules.Notify)
local remotes=RS:WaitForChild("Remotes")
local event=remotes:WaitForChild("CucumberAdventure")
local queue,working,priorityUntil={},false,0
local function enqueue(message,color)
 if #queue>=8 then table.remove(queue,1) end
 table.insert(queue,{message,color or Notify.COLORS.Success})
 if working then return end
 working=true
 task.spawn(function()
  while #queue>0 do
   while os.clock()<priorityUntil do task.wait(.2) end
   local item=table.remove(queue,1)
   Notify.Show(item[1],item[2],2.4)
   task.wait(2.8)
  end
  working=false
 end)
end
-- Collection UI now lives in StarterGui.CucumberMenus; server records and rewards are unchanged.
event.OnClientEvent:Connect(function(payload)
 if type(payload)~="table" then return end
 if payload.Kind=="Records" then
  task.delay(2.3,function() for _,message in payload.Messages or {} do enqueue(message) end end)
 elseif payload.Kind=="Announcement" then enqueue(payload.Text,Notify.COLORS.Info)
 elseif payload.Kind=="Rescue" then task.delay(.7,function() enqueue(payload.Text,Notify.COLORS.Info) end)
 end
end)
local lastCountdown,phaseEnd,elapsed=nil,nil,0
RunService.Heartbeat:Connect(function(dt)
 elapsed+=dt
 if elapsed<.1 then return end
 elapsed=0
 local endTime=workspace:GetAttribute("PhaseEndsAt")
 if endTime~=phaseEnd then phaseEnd,lastCountdown=endTime,nil end
 if workspace:GetAttribute("CyclePhase")~="Day" or type(endTime)~="number" then return end
 if not player:GetAttribute("CarryingCucumber") or player:GetAttribute("CucumberCarrySafe") then return end
 local left=math.ceil(endTime-workspace:GetServerTimeNow())
 if left>0 and (left==10 or left<=5) and left~=lastCountdown then
  lastCountdown=left
  priorityUntil=os.clock()+1.1
  Notify.Warn("Night in "..left.."! Get your cucumber to the lobby!",1.05)
 end
end)
