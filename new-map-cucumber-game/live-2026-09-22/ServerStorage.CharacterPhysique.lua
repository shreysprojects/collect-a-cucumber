-- R15 physique shaping. Native scaling moves rig joints and accessories;
-- local X/Z thickness changes emphasize chest and upper limbs without moving joints.
-- Height is measured in a neutral rig pose, excluding hats, tools and carried items.
local Progression=require(game.ReplicatedStorage.Modules.StrengthProgression)
local Physique={}
local BodyNames={
 Head=true,UpperTorso=true,LowerTorso=true,
 LeftUpperArm=true,LeftLowerArm=true,LeftHand=true,
 RightUpperArm=true,RightLowerArm=true,RightHand=true,
 LeftUpperLeg=true,LeftLowerLeg=true,LeftFoot=true,
 RightUpperLeg=true,RightLowerLeg=true,RightFoot=true,
}
local function jointParts(joint)
 if joint:IsA("AnimationConstraint") then
  local a,b=joint.Attachment0,joint.Attachment1
  if a and b then return a.Parent,b.Parent,a.CFrame,b.CFrame end
 elseif joint:IsA("Motor6D") then
  return joint.Part0,joint.Part1,joint.C0,joint.C1
 end
end
function Physique.Measure(character)
 local root=character:FindFirstChild("HumanoidRootPart")
 assert(root,"Missing root")
 local poses={[root]=CFrame.identity}
 local joints={}
 for _,v in character:GetDescendants() do
  if v:IsA("AnimationConstraint") or v:IsA("Motor6D") then
   local a,b,c0,c1=jointParts(v)
   if a and b and a.Parent==character and b.Parent==character then
    table.insert(joints,{a,b,c0,c1})
   end
  end
 end
 for _=1,16 do
  local changed=false
  for _,j in joints do
   local a,b,c0,c1=table.unpack(j)
   if poses[a] and not poses[b] then
    poses[b]=poses[a]*c0*c1:Inverse()
    changed=true
   elseif poses[b] and not poses[a] then
    poses[a]=poses[b]*c1*c0:Inverse()
    changed=true
   end
  end
  if not changed then break end
 end
 local minY,maxY=math.huge,-math.huge
 local minX,maxX=math.huge,-math.huge
 local measured=0
 for name in pairs(BodyNames) do
  local part=character:FindFirstChild(name)
  local cf=part and poses[part]
  if part and cf then
   local half=part.Size*.5
   local ey=math.abs(cf.XVector.Y)*half.X+math.abs(cf.YVector.Y)*half.Y+math.abs(cf.ZVector.Y)*half.Z
   local ex=math.abs(cf.XVector.X)*half.X+math.abs(cf.YVector.X)*half.Y+math.abs(cf.ZVector.X)*half.Z
   minY=math.min(minY,cf.Y-ey)
   maxY=math.max(maxY,cf.Y+ey)
   minX=math.min(minX,cf.X-ex)
   maxX=math.max(maxX,cf.X+ex)
   measured+=1
  end
 end
 assert(measured==15,"Expected all 15 R15 body parts in the rig")
 return maxY-minY,minY,maxX-minX
end
local function setScale(humanoid,name,value)
 local number=humanoid:FindFirstChild(name)
 assert(number and number:IsA("NumberValue"),"Missing R15 scale "..name)
 number.Value=value
end
local function shape(character,bulk)
 for name in pairs(BodyNames) do
  local part=character:FindFirstChild(name)
  if part then
   local x,z=1,1
   if name=="UpperTorso" then x,z=1+.12*bulk,1+.14*bulk
   elseif name=="LowerTorso" then x,z=1-.06*bulk,1
   elseif name:find("UpperArm") then x,z=1+.40*bulk,1+.40*bulk
   elseif name:find("LowerArm") then x,z=1+.14*bulk,1+.14*bulk
   elseif name:find("UpperLeg") then x,z=1+.18*bulk,1+.20*bulk
   elseif name:find("LowerLeg") then x,z=1+.08*bulk,1+.10*bulk end
   -- Lengths and RigAttachments are untouched: elbows/knees keep their animation pivots.
   part.Size=part.Size*Vector3.new(x,1,z)
  end
 end
end
function Physique.Apply(character,strength)
 local humanoid=character:FindFirstChildOfClass("Humanoid")
 assert(humanoid and humanoid.RigType==Enum.HumanoidRigType.R15,"Strength physique requires the game's R15 rig")
 local root=character:FindFirstChild("HumanoidRootPart")
 if not root or humanoid.Health<=0 then return end
 local index,stage=Progression.GetStage(strength)
 local previousGroundDistance=humanoid.HipHeight+root.Size.Y*.5
 humanoid.AutomaticScalingEnabled=true
 setScale(humanoid,"BodyTypeScale",0)
 setScale(humanoid,"BodyProportionScale",0)
 setScale(humanoid,"BodyWidthScale",stage.Width)
 setScale(humanoid,"BodyDepthScale",stage.Depth)
 -- Changing height forces Roblox to rebuild sizes from its OriginalSize values.
 -- This prevents our additional muscle thickness from accumulating on repeat upgrades.
 setScale(humanoid,"BodyHeightScale",.5)
 setScale(humanoid,"HeadScale",1)
 local head=character:FindFirstChild("Head")
 setScale(humanoid,"HeadScale",(1.1+.1*stage.Bulk)/math.max(.1,head.Size.Y))
 local lowHeight=Physique.Measure(character)
 setScale(humanoid,"BodyHeightScale",1.5)
 local highHeight=Physique.Measure(character)
 local slope=highHeight-lowHeight
 assert(slope>.1,"Cannot calibrate R15 body height")
 local scale=.5+(stage.Height-lowHeight)/slope
 setScale(humanoid,"BodyHeightScale",math.clamp(scale,.05,5))
 shape(character,stage.Bulk)
 local actualHeight,minimumY=Physique.Measure(character)
 -- Custom bodies may contain rotated limbs; correct their bounding height too.
 for _=1,3 do
  if math.abs(actualHeight-stage.Height)<.005 then break end
  scale=scale+(stage.Height-actualHeight)/slope
  setScale(humanoid,"BodyHeightScale",math.clamp(scale,.05,5))
  shape(character,stage.Bulk)
  actualHeight,minimumY=Physique.Measure(character)
 end
 humanoid.HipHeight=math.max(.1,-minimumY-root.Size.Y*.5)
 local lift=humanoid.HipHeight+root.Size.Y*.5-previousGroundDistance
 if not humanoid.SeatPart and math.abs(lift)>.001 then
  character:PivotTo(character:GetPivot()+Vector3.new(0,lift,0))
 end
 humanoid.WalkSpeed=Progression.GetWalkSpeed(strength)
 character:SetAttribute("PhysiqueStage",index)
 character:SetAttribute("PhysiqueName",stage.Name)
 character:SetAttribute("PhysiqueHeight",actualHeight)
 character:SetAttribute("PhysiqueTargetHeight",stage.Height)
 character:SetAttribute("PhysiqueBulk",stage.Bulk)
 return index,actualHeight
end
return Physique
