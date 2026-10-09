local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Input = game:GetService("UserInputService")
local Actions = game:GetService("ContextActionService")
local player = Players.LocalPlayer
local rules = require(ReplicatedStorage.Modules.CucumberStrength)
local Notify = require(ReplicatedStorage.Modules.Notify)
local steady = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("SteadyCucumber")
local INK = Color3.fromRGB(18, 40, 30)
local WHITE = Color3.new(1, 1, 1)
local gui = Instance.new("ScreenGui")
gui.Name, gui.ResetOnSpawn, gui.DisplayOrder = "CucumberGrip", false, 20
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")

local function round(parent, radius)
 local c = Instance.new("UICorner")
 c.CornerRadius, c.Parent = UDim.new(0, radius), parent
end
local function outline(parent, thickness, color)
 local s = Instance.new("UIStroke")
 s.Color, s.Thickness, s.Parent = color or INK, thickness, parent
 return s
end
local function gradient(parent, top, bottom)
 local g = Instance.new("UIGradient")
 g.Color = ColorSequence.new(top, bottom)
 g.Rotation, g.Parent = 90, parent
 return g
end
local function frame(name, parent, position, size, color, z)
 local f = Instance.new("Frame")
 f.Name, f.Position, f.Size = name, position, size
 f.BackgroundColor3, f.BorderSizePixel, f.ZIndex = color, 0, z or 1
 f.Parent = parent
 return f
end
local function label(name, parent, position, size, value, textSize, z)
 local t = Instance.new("TextLabel")
 t.Name, t.Position, t.Size = name, position, size
 t.BackgroundTransparency, t.Font = 1, Enum.Font.FredokaOne
 t.Text, t.TextColor3, t.TextSize = value, WHITE, textSize
 t.ZIndex, t.Parent = z or 3, parent
 outline(t, 2)
 return t
end

local root = frame("GripPanel", gui, UDim2.fromScale(.5, .87), UDim2.new(.36, 0, 0, 182), WHITE)
root.AnchorPoint, root.BackgroundTransparency = Vector2.new(.5, 1), 1
local constraint = Instance.new("UISizeConstraint")
constraint.MinSize, constraint.MaxSize, constraint.Parent = Vector2.new(270, 182), Vector2.new(410, 182), root
local scale = Instance.new("UIScale")
scale.Parent = root
local shadow = frame("Shadow", root, UDim2.fromOffset(0, 6), UDim2.fromScale(1, 1), INK)
round(shadow, 20)
local card = frame("Card", root, UDim2.fromOffset(0, 0), UDim2.fromScale(1, 1), WHITE, 2)
round(card, 20)
outline(card, 4)
gradient(card, Color3.fromRGB(87, 231, 152), Color3.fromRGB(17, 156, 121))
local inner = frame("Inset", card, UDim2.fromOffset(7, 7), UDim2.new(1, -14, 1, -14), WHITE)
inner.BackgroundTransparency = 1
round(inner, 15)
local innerStroke = outline(inner, 2, Color3.fromRGB(184, 255, 188))
innerStroke.Transparency = .45
local title = label("Title", card, UDim2.fromOffset(15, 8), UDim2.new(.42, 0, 0, 31), "GRIP!", 27)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Rotation = -3
local tier = frame("TierBadge", card, UDim2.new(.45, 0, 0, 10), UDim2.new(.55, -15, 0, 29), WHITE, 3)
round(tier, 9)
outline(tier, 3)
local tierText = label("Tier", tier, UDim2.fromOffset(5, 0), UDim2.new(1, -10, 1, 0), "HARD", 20)
tierText.TextScaled = true
local tierSize = Instance.new("UITextSizeConstraint")
tierSize.MinTextSize, tierSize.MaxTextSize, tierSize.Parent = 12, 20, tierText

local track = frame("Track", card, UDim2.fromOffset(15, 49), UDim2.new(1, -30, 0, 34), Color3.fromRGB(28, 70, 57), 3)
round(track, 11)
outline(track, 3)
local clip = frame("Clip", track, UDim2.fromOffset(3, 3), UDim2.new(1, -6, 1, -6), WHITE)
clip.BackgroundTransparency, clip.ClipsDescendants = 1, true
local fill = frame("Fill", clip, UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), WHITE)
round(fill, 8)
local fillGradient = gradient(fill, Color3.fromRGB(217, 255, 112), Color3.fromRGB(104, 229, 45))
local shine = frame("Shine", fill, UDim2.new(0, 3, 0, 2), UDim2.new(1, -6, .35, 0), WHITE, 2)
shine.BackgroundTransparency = .55
round(shine, 5)
-- A visible boundary marks the final 30% where recovery becomes available.
local marker = frame("RecoveryMark", track, UDim2.fromScale(rules.RECOVERY_WINDOW, 0), UDim2.new(0, 2, 1, 0), INK, 3)
marker.BackgroundTransparency = .45
local perfectZone=frame("PerfectZone",track,UDim2.fromScale(rules.PERFECT_MIN,0),UDim2.fromScale(rules.PERFECT_MAX-rules.PERFECT_MIN,1),Color3.fromRGB(255,244,91),3)
perfectZone.BackgroundTransparency=.2
outline(perfectZone,2,Color3.new(1,1,1))
local time = label("Time", track, UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), "", 23, 4)
local button = Instance.new("TextButton")
button.Name, button.Position, button.Size = "Steady", UDim2.fromOffset(15, 95), UDim2.new(1, -30, 0, 34)
button.BackgroundColor3, button.BorderSizePixel, button.AutoButtonColor = WHITE, 0, false
button.Font, button.TextSize, button.TextColor3 = Enum.Font.FredokaOne, 22, WHITE
button.ZIndex, button.Parent = 3, card
round(button, 10)
local buttonBorder = outline(button, 3)
buttonBorder.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
button.TextStrokeColor3, button.TextStrokeTransparency = INK, 0
gradient(button, Color3.fromRGB(255, 240, 111), Color3.fromRGB(255, 171, 40))
local buttonScale = Instance.new("UIScale")
buttonScale.Parent = button
local hint = label("State", card, UDim2.fromOffset(12, 94), UDim2.new(1, -24, 0, 35), "Reach the lobby!", 18)
hint.TextScaled = true
local hintSize = Instance.new("UITextSizeConstraint")
hintSize.MinTextSize, hintSize.MaxTextSize, hintSize.Parent = 12, 18, hint

local modeButton=Instance.new("TextButton")
modeButton.Name,modeButton.Position,modeButton.Size="CarryMode",UDim2.fromOffset(15,141),UDim2.new(1,-30,0,30)
modeButton.BackgroundColor3,modeButton.Font,modeButton.TextSize=Color3.fromRGB(26,103,84),Enum.Font.FredokaOne,16
modeButton.TextColor3,modeButton.TextStrokeTransparency=Color3.new(1,1,1),0
modeButton.TextScaled=true
local modeLimit=Instance.new("UITextSizeConstraint") modeLimit.MinTextSize=11 modeLimit.MaxTextSize=16 modeLimit.Parent=modeButton
modeButton.ZIndex,modeButton.Parent=3,card
round(modeButton,8)
local modeStroke=outline(modeButton,2)
modeStroke.ApplyStrokeMode=Enum.ApplyStrokeMode.Border
local modeRemote=ReplicatedStorage.Remotes:WaitForChild("CucumberCarryMode")
local modes={"Normal","Careful","Sprint"}
local modeAfter=0
local function changeMode()
 if os.clock()<modeAfter or Input:GetFocusedTextBox() then return end
 modeAfter=os.clock()+.25
 local current=player:GetAttribute("CucumberCarryMode") or "Normal"
 local i=table.find(modes,current) or 1
 modeRemote:FireServer(modes[i%#modes+1])
end
modeButton.Activated:Connect(changeMode)
local bound, ready, warned, requestAfter = false, false, false, 0
local shown, lastUrgent, lastBand, lastTime, lastUsed = false, nil, nil, nil, nil
local pop
local function recover()
 if not ready or Input:GetFocusedTextBox() or os.clock() < requestAfter then return end
 requestAfter = os.clock() + .25
 steady:FireServer()
end
button.Activated:Connect(recover)
local function update()
 local active = player:GetAttribute("CarryingCucumberHeavy") == true and player:GetAttribute("CarryingCucumber") ~= nil
 local deadline = player:GetAttribute("CucumberGripEnd")
 local enabled = active and type(deadline) == "number"
 gui.Enabled = enabled
 if not enabled then
  ready, warned, shown = false, false, false
  lastUrgent, lastBand, lastTime, lastUsed = nil, nil, nil, nil
  if bound then Actions:UnbindAction("SteadyCucumber") Actions:UnbindAction("CycleCarryMode") bound = false end
  return
 end
 if not shown then
  shown = true
  if pop then pop:Cancel() end
  scale.Scale = .82
  pop = TweenService:Create(scale, TweenInfo.new(.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1})
  pop:Play()
 end
 if not bound then
  Actions:BindAction("SteadyCucumber", function(_, state)
   if Input:GetFocusedTextBox() then return Enum.ContextActionResult.Pass end
   if state == Enum.UserInputState.Begin then recover() end
   return Enum.ContextActionResult.Sink
  end, false, Enum.KeyCode.F, Enum.KeyCode.ButtonX)
  Actions:BindAction("CycleCarryMode",function(_,state) if Input:GetFocusedTextBox() then return Enum.ContextActionResult.Pass end if state==Enum.UserInputState.Begin then changeMode() end return Enum.ContextActionResult.Sink end,false,Enum.KeyCode.C,Enum.KeyCode.ButtonL1)
  bound = true
 end
 local band = player:GetAttribute("CarryingCucumberBand") or "shaky"
 if band ~= lastBand then
  local display = rules.BAND_LABELS[band] or rules.BAND_LABELS.shaky
  tierText.Text, tier.BackgroundColor3 = string.upper(display.Text), display.Color
  lastBand = band
 end
 local duration = math.max(.001, player:GetAttribute("CucumberGripDuration") or 1)
 local remaining = math.max(0, deadline - workspace:GetServerTimeNow())
 local fraction = math.clamp(remaining / duration, 0, 1)
 local used = player:GetAttribute("CucumberRecoveryUsed") == true
 local urgent = fraction <= rules.RECOVERY_WINDOW
 ready = not used and remaining > 0 and urgent
 fill.Size = UDim2.fromScale(fraction, 1)
 if urgent ~= lastUrgent then
  fillGradient.Color = urgent
   and ColorSequence.new(Color3.fromRGB(255, 196, 79), Color3.fromRGB(255, 72, 66))
   or ColorSequence.new(Color3.fromRGB(217, 255, 112), Color3.fromRGB(104, 229, 45))
  time.TextColor3 = urgent and Color3.fromRGB(255, 243, 185) or WHITE
  lastUrgent = urgent
 end
 local clockText = string.format("%.1fs", math.min(duration, remaining))
 if clockText ~= lastTime then time.Text = clockText lastTime = clockText end
 perfectZone.Visible=not used
 local mode=player:GetAttribute("CucumberCarryMode") or "Normal"
 local trait=player:GetAttribute("CarryingCucumberTrait") or "Normal"
 local modeHint=mode=="Careful" and "Careful: slower / less drain" or (mode=="Sprint" and "Sprint: faster / more drain" or "Normal pace")
 modeButton.Text=modeHint..(Input.TouchEnabled and " · TAP" or (Input.GamepadEnabled and not Input.MouseEnabled and " [LB]" or " [C]"))
 title.Text=trait=="Slippery" and "SLIPPERY!" or (trait=="Bouncy" and "BOUNCY!" or "GRIP!")
 title.TextSize=trait=="Slippery" and 20 or 27
 button.Visible, hint.Visible = ready, not ready
 local perfect=fraction>=rules.PERFECT_MIN and fraction<=rules.PERFECT_MAX
 local action=perfect and "PERFECT!" or "STEADY!"
 button.Text=action..(Input.TouchEnabled and "" or (Input.GamepadEnabled and not Input.MouseEnabled and " [X]" or " [F]"))
 buttonScale.Scale = ready and (1 + .025 * math.sin(os.clock() * 9)) or 1
 hint.Text = used and "Nice save! Get to the lobby!" or (remaining <= 0 and "Grip lost!" or "Reach the lobby!  1 save left")
 if used and lastUsed == false then
  if pop then pop:Cancel() end
  scale.Scale = 1.06
  pop = TweenService:Create(scale, TweenInfo.new(.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1})
  pop:Play()
 end
 lastUsed = used
 if ready and not warned then
  warned = true
  Notify.Show("Steady it now!", Notify.COLORS.Warn, 1.5)
 end
end
RunService.Heartbeat:Connect(update)
update()

