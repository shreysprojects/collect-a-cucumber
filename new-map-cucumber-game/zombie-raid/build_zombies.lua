-- build_zombies.lua  (run ONCE in edit mode through install.lua; idempotent)
-- Builds the three zombie rigs into ServerStorage.Assets.Zombies/{Shambler, Runner, Brute}.
-- Each is a default R15 block body from Players:CreateHumanoidModelFromDescription (in edit mode it
-- arrives with AnimationConstraints instead of Motor6Ds, so the fifteen Motor6Ds are built here from
-- the *RigAttachment pairs, exactly what BuildRigFromAttachments does at runtime), stripped of its
-- Animate script / BodyColors / FaceControls, and dressed with welded Parts: eyes, jaws, ribs, rags,
-- claws, horns, cracks, chains. Every part carries a Role attribute (Skin / Cloth / Glow / Bone /
-- Dark / Metal) so ZombieRaidService can retint a rig into any variety of ZombieCatalog.
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

local assets = ServerStorage:WaitForChild("Assets")
local folder = assets:FindFirstChild("Zombies")
if folder then folder:Destroy() end
folder = Instance.new("Folder")
folder.Name = "Zombies"

local JOINTS = { -- child part = {parent part, rig attachment prefix}
	LowerTorso = {"HumanoidRootPart", "Root"},
	UpperTorso = {"LowerTorso", "Waist"},
	Head = {"UpperTorso", "Neck"},
	LeftUpperArm = {"UpperTorso", "LeftShoulder"},
	LeftLowerArm = {"LeftUpperArm", "LeftElbow"},
	LeftHand = {"LeftLowerArm", "LeftWrist"},
	RightUpperArm = {"UpperTorso", "RightShoulder"},
	RightLowerArm = {"RightUpperArm", "RightElbow"},
	RightHand = {"RightLowerArm", "RightWrist"},
	LeftUpperLeg = {"LowerTorso", "LeftHip"},
	LeftLowerLeg = {"LeftUpperLeg", "LeftKnee"},
	LeftFoot = {"LeftLowerLeg", "LeftAnkle"},
	RightUpperLeg = {"LowerTorso", "RightHip"},
	RightLowerLeg = {"RightUpperLeg", "RightKnee"},
	RightFoot = {"RightLowerLeg", "RightAnkle"},
}
local SKIN = {Head = true, LeftUpperArm = true, LeftLowerArm = true, LeftHand = true, RightUpperArm = true, RightLowerArm = true, RightHand = true}
local CLOTH = {UpperTorso = true, LowerTorso = true, LeftUpperLeg = true, LeftLowerLeg = true, LeftFoot = true, RightUpperLeg = true, RightLowerLeg = true, RightFoot = true}

local BONE = Color3.fromRGB(235, 228, 205)
local DARK = Color3.fromRGB(28, 24, 26)
local METAL = Color3.fromRGB(120, 124, 132)

local function baseRig(name)
	local model = Players:CreateHumanoidModelFromDescription(Instance.new("HumanoidDescription"), Enum.HumanoidRigType.R15)
	model.Name = name
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("AnimationConstraint") or d:IsA("BallSocketConstraint") or d:IsA("FaceControls") or d:IsA("LuaSourceContainer")
			or d:IsA("BodyColors") or d:IsA("HumanoidDescription") or d:IsA("WrapTarget") or d:IsA("Decal") or d:IsA("Sound") then
			d:Destroy()
		end
	end
	for child, info in pairs(JOINTS) do
		local p1 = model:FindFirstChild(child)
		local p0 = model:FindFirstChild(info[1])
		local a0 = p0 and p0:FindFirstChild(info[2] .. "RigAttachment")
		local a1 = p1 and p1:FindFirstChild(info[2] .. "RigAttachment")
		assert(a0 and a1, name .. ": missing rig attachments for " .. child)
		local motor = Instance.new("Motor6D")
		motor.Name = info[2]
		motor.Part0 = p0
		motor.Part1 = p1
		motor.C0 = a0.CFrame
		motor.C1 = a1.CFrame
		motor.Parent = p1
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.NameDisplayDistance = 0
	humanoid.HealthDisplayDistance = 0
	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false
	humanoid.AutoRotate = true
	local root = model:FindFirstChild("HumanoidRootPart")
	root.Transparency = 1
	model.PrimaryPart = root
	for _, p in ipairs(model:GetChildren()) do
		if p:IsA("BasePart") then
			p.Anchored = false
			p.CanQuery = true
			p.CastShadow = true
			p.Material = Enum.Material.SmoothPlastic
			if SKIN[p.Name] then p:SetAttribute("Role", "Skin") elseif CLOTH[p.Name] then p:SetAttribute("Role", "Cloth") end
		end
	end
	model:SetAttribute("Design", name)
	model:SetAttribute("BaseHip", humanoid.HipHeight)
	return model, humanoid
end

--.. a welded detail part in the parent part's local frame (front = -Z)
local function extra(model, parent, name, size, cf, color, role, material, shape)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = parent.CFrame * cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	if shape then p.Shape = shape end
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = true
	p:SetAttribute("Role", role)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = parent
	weld.Part1 = p
	weld.Parent = p
	p.Parent = model
	return p
end

local function eyeLight(head, color)
	local light = Instance.new("PointLight")
	light.Name = "EyeLight"
	light.Color = color
	light.Range = 6
	light.Brightness = 0.9
	light.Shadows = false
	light.Parent = head
end

local function tiltNeck(model, x, z)
	local neck = model.Head:FindFirstChild("Neck")
	neck.C0 = neck.C0 * CFrame.Angles(x, 0, z)
end

local function V(x, y, z) return Vector3.new(x, y, z) end
local function P(x, y, z) return CFrame.new(x, y, z) end
local function R(x, y, z) return CFrame.Angles(math.rad(x), math.rad(y), math.rad(z)) end
local GLOW = Enum.Material.Neon

--..Shambler: the classic. One glowing eye, one empty socket, jaw hanging open, ribs through a torn shirt,
--..rags off the waist, head lolling to one side.
local function buildShambler()
	local model = baseRig("Shambler")
	local head, upper, lower = model.Head, model.UpperTorso, model.LowerTorso
	local skin, cloth, glow = Color3.fromRGB(96, 150, 70), Color3.fromRGB(70, 52, 40), Color3.fromRGB(190, 255, 90)
	extra(model, head, "EyeL", V(0.26, 0.22, 0.12), P(-0.24, 0.1, -0.56), glow, "Glow", GLOW)
	extra(model, head, "SocketR", V(0.32, 0.3, 0.1), P(0.24, 0.1, -0.57), DARK, "Dark")
	extra(model, head, "EyeR", V(0.1, 0.1, 0.08), P(0.28, 0.06, -0.6), glow, "Glow", GLOW)
	extra(model, head, "Jaw", V(0.7, 0.24, 0.5), P(0, -0.52, -0.3) * R(28, 0, 0), skin, "Skin")
	extra(model, head, "Mouth", V(0.6, 0.12, 0.08), P(0, -0.34, -0.58), DARK, "Dark")
	for i, x in ipairs({-0.2, 0, 0.2}) do
		extra(model, head, "Tooth" .. i, V(0.09, 0.12, 0.06), P(x, -0.42, -0.6), BONE, "Bone")
	end
	extra(model, head, "Scar", V(0.06, 0.5, 0.06), P(0.42, 0.25, -0.5) * R(0, 0, 20), Color3.fromRGB(60, 90, 40), "Dark")
	eyeLight(head, glow)
	tiltNeck(model, 0, math.rad(-18))
	for i, y in ipairs({0.42, 0.16, -0.1}) do
		extra(model, upper, "Rib" .. i, V(1.2, 0.09, 0.08), P(0, y, -0.53), BONE, "Bone")
	end
	extra(model, upper, "Gash", V(0.5, 0.95, 0.06), P(0.4, 0.05, -0.53) * R(0, 0, -8), DARK, "Dark")
	extra(model, upper, "ShoulderRag", V(0.55, 0.3, 1.1), P(0.75, 0.75, 0), cloth, "Cloth")
	extra(model, lower, "RagFL", V(0.36, 0.55, 0.1), P(-0.55, -0.42, -0.5) * R(0, 0, 12), cloth, "Cloth")
	extra(model, lower, "RagFR", V(0.3, 0.45, 0.1), P(0.6, -0.38, -0.5) * R(0, 0, -15), cloth, "Cloth")
	extra(model, lower, "RagBL", V(0.34, 0.5, 0.1), P(-0.4, -0.4, 0.5) * R(0, 0, -10), cloth, "Cloth")
	extra(model, lower, "RagBR", V(0.3, 0.4, 0.1), P(0.5, -0.36, 0.5) * R(0, 0, 14), cloth, "Cloth")
	extra(model, model.LeftLowerLeg, "KneeBone", V(0.5, 0.22, 0.2), P(0, 0.4, -0.5), BONE, "Bone")
	model.Parent = folder
	return model
end

--..Runner: lean and quick. Twin red eyes under a furrowed brow, fangs, a neon mohawk, claws, spine spikes.
local function buildRunner()
	local model = baseRig("Runner")
	local head, upper = model.Head, model.UpperTorso
	local cloth, glow = Color3.fromRGB(60, 60, 68), Color3.fromRGB(255, 90, 60)
	for _, s in ipairs({-1, 1}) do
		extra(model, head, "Eye", V(0.18, 0.14, 0.1), P(s * 0.22, 0.12, -0.57), glow, "Glow", GLOW)
		extra(model, head, "Brow", V(0.34, 0.08, 0.1), P(s * 0.22, 0.27, -0.57) * R(0, 0, s * -20), DARK, "Dark")
		extra(model, head, "Fang", V(0.06, 0.16, 0.05), P(s * 0.14, -0.32, -0.6), BONE, "Bone")
	end
	extra(model, head, "Mouth", V(0.5, 0.08, 0.06), P(0, -0.26, -0.58), DARK, "Dark")
	for i = 0, 3 do
		extra(model, head, "Mohawk" .. i, V(0.14, 0.55, 0.22), P(0, 0.72, -0.3 + i * 0.2) * R(-15 + i * 10, 0, 0), glow, "Glow", GLOW)
	end
	eyeLight(head, glow)
	for _, handName in ipairs({"LeftHand", "RightHand"}) do
		local hand = model[handName]
		for i, x in ipairs({-0.25, 0, 0.25}) do
			extra(model, hand, "Claw" .. i, V(0.07, 0.07, 0.45), P(x, -0.06, -0.66), BONE, "Bone")
		end
	end
	for _, s in ipairs({-1, 1}) do
		extra(model, upper, "Collar", V(0.5, 0.22, 0.16), P(s * 0.6, 0.76, -0.3) * R(0, 0, s * 25), cloth, "Cloth")
	end
	for i, y in ipairs({0.5, 0.2, -0.1}) do
		extra(model, upper, "Spike" .. i, V(0.12, 0.2, 0.14), P(0, y, 0.56), BONE, "Bone")
	end
	extra(model, upper, "Tear", V(0.35, 0.7, 0.06), P(-0.45, 0.1, -0.53) * R(0, 0, 12), DARK, "Dark")
	tiltNeck(model, math.rad(10), 0)
	model.Parent = folder
	return model
end

--..Brute: big and slow. Horns, a heavy brow, a row of teeth, stone shoulder pads with spikes, glowing
--..cracks across a bloated chest, a chain slung over one shoulder.
local function buildBrute()
	local model = baseRig("Brute")
	local head, upper = model.Head, model.UpperTorso
	local skin, glow = Color3.fromRGB(140, 175, 120), Color3.fromRGB(170, 255, 120)
	for _, s in ipairs({-1, 1}) do
		extra(model, head, "Eye", V(0.2, 0.16, 0.1), P(s * 0.24, 0.08, -0.57), glow, "Glow", GLOW)
		extra(model, head, "Horn", V(0.2, 0.62, 0.2), P(s * 0.42, 0.72, 0) * R(0, 0, s * -28), BONE, "Bone")
	end
	extra(model, head, "Brow", V(0.95, 0.14, 0.12), P(0, 0.3, -0.56), DARK, "Dark")
	extra(model, head, "Jaw", V(0.9, 0.3, 0.55), P(0, -0.5, -0.24), skin, "Skin")
	for i, x in ipairs({-0.3, -0.1, 0.1, 0.3}) do
		extra(model, head, "Tooth" .. i, V(0.12, 0.14, 0.06), P(x, -0.36, -0.58), BONE, "Bone")
	end
	eyeLight(head, glow)
	tiltNeck(model, math.rad(12), 0)
	for _, armName in ipairs({"LeftUpperArm", "RightUpperArm"}) do
		local arm = model[armName]
		extra(model, arm, "Pad", V(1.35, 0.55, 1.35), P(0, 0.7, 0), Color3.fromRGB(70, 74, 82), "Dark", Enum.Material.Slate)
		for _, s in ipairs({-1, 1}) do
			extra(model, arm, "PadSpike", V(0.15, 0.4, 0.15), P(s * 0.35, 1.05, 0), BONE, "Bone")
		end
	end
	extra(model, upper, "Belly", V(1.6, 0.9, 0.5), P(0, -0.5, -0.4), skin, "Skin")
	extra(model, upper, "Crack1", V(0.08, 0.55, 0.06), P(-0.35, 0.15, -0.53) * R(0, 0, 20), glow, "Glow", GLOW)
	extra(model, upper, "Crack2", V(0.08, 0.4, 0.06), P(0.1, -0.15, -0.66) * R(0, 0, -30), glow, "Glow", GLOW)
	extra(model, upper, "Crack3", V(0.08, 0.45, 0.06), P(0.45, 0.3, -0.53) * R(0, 0, 10), glow, "Glow", GLOW)
	for i = 0, 4 do
		local t = i / 4
		extra(model, upper, "Link" .. i, V(0.22, 0.22, 0.12), P(-0.8 + 1.6 * t, 0.75 - 1.3 * t, -0.52) * R(0, 0, 40), METAL, "Metal", Enum.Material.Metal)
	end
	model.Parent = folder
	return model
end

local shambler = buildShambler()
local runner = buildRunner()
local brute = buildBrute()
folder.Parent = assets

--.. does Model:ScaleTo scale HipHeight? measured here so the service knows
local probe = brute:Clone()
local ph = probe:FindFirstChildOfClass("Humanoid")
local before = ph.HipHeight
probe:ScaleTo(1.4)
folder:SetAttribute("ScaleToScalesHip", math.abs(ph.HipHeight - before * 1.4) < 1e-3)
probe:Destroy()

local function report(model)
	local motors, parts = 0, 0
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Motor6D") then motors += 1 elseif d:IsA("BasePart") then parts += 1 end
	end
	return ("%s: %d motors, %d parts, hip %.2f"):format(model.Name, motors, parts, model:FindFirstChildOfClass("Humanoid").HipHeight)
end
return table.concat({report(shambler), report(runner), report(brute), "ScaleToScalesHip=" .. tostring(folder:GetAttribute("ScaleToScalesHip"))}, "; ")
