-- guardians/build_anims.lua - turn clips.json into KeyframeSequences in Studio.
--
--   local a = loadstring(game:GetService("HttpService"):GetAsync("http://127.0.0.1:8771/build_anims.lua"))()
--   a.build({"Strawman"})     -- KeyframeSequences into ServerStorage.Assets.GuardianAnims
--   a.preview("Strawman", "Wake")   -- register + play it on a Workspace copy (edit mode)
--   a.report()
--
-- A KeyframeSequence's Pose tree has to MIRROR THE MOTOR6D TREE: one Pose per part,
-- nested exactly as the joints are, rooted at HumanoidRootPart.  Each Pose.CFrame is the
-- Transform that joint applies - which is what clips.json already holds, as a quaternion
-- in Roblox space, because install.lua builds every joint world-aligned.
local HttpService = game:GetService("HttpService")
local ServerStorage = game:GetService("ServerStorage")

local BASE = "http://127.0.0.1:8771"
local API = {}
local _clips, _payload = nil, nil

local function clips()
	if not _clips then
		_clips = HttpService:JSONDecode(HttpService:GetAsync(BASE .. "/clips.json"))
	end
	return _clips
end

local function payload()
	if not _payload then
		_payload = HttpService:JSONDecode(HttpService:GetAsync(BASE .. "/install-payload.json"))
	end
	return _payload
end

local function guardians()
	return ServerStorage:FindFirstChild("Assets") and ServerStorage.Assets:FindFirstChild("Guardians")
end

local function animFolder()
	local a = ServerStorage:FindFirstChild("Assets")
	local f = a:FindFirstChild("GuardianAnims")
	if not f then
		f = Instance.new("Folder")
		f.Name = "GuardianAnims"
		f.Parent = a
	end
	return f
end

--.. children of each part in the rig, so Poses can be nested the way the motors are
local function childMap(rig)
	local kids, root = {}, nil
	for part, d in pairs(rig) do
		if d.parent then
			kids[d.parent] = kids[d.parent] or {}
			table.insert(kids[d.parent], part)
		else
			root = part
		end
	end
	for _, list in pairs(kids) do table.sort(list) end
	return kids, root
end

local function buildKeyframe(kids, rootName, rotByPart, locByPart, time)
	local kf = Instance.new("Keyframe")
	kf.Name = "kf_" .. tostring(time)
	kf.Time = time

	local function pose(partName, parentPose)
		local p = Instance.new("Pose")
		-- the rig root is called Root in the payload but HumanoidRootPart on the model
		p.Name = (partName == rootName) and "HumanoidRootPart" or partName
		local q = rotByPart[partName]
		local l = locByPart and locByPart[partName]
		local cf = CFrame.identity
		if q then
			cf = CFrame.new(0, 0, 0, q[1], q[2], q[3], q[4])
		end
		if l then
			cf = CFrame.new(l[1], l[2], l[3]) * cf
		end
		p.CFrame = cf
		p.EasingStyle = Enum.PoseEasingStyle.Cubic
		p.EasingDirection = Enum.PoseEasingDirection.InOut
		if parentPose then
			p.Parent = parentPose
		else
			p.Parent = kf
		end
		for _, child in ipairs(kids[partName] or {}) do
			pose(child, p)
		end
		return p
	end

	pose(rootName, nil)
	return kf
end

function API.build(names)
	local cl = clips().models
	local pay = payload().models
	local out = animFolder()
	local lines = {}
	for _, g in ipairs(names or {}) do
		local gclips, gdata = cl[g], pay[g]
		if not gclips or not gdata then
			table.insert(lines, g .. ": no clips or no payload")
		else
			local kids, rootName = childMap(gdata.rig)
			local folder = out:FindFirstChild(g)
			if folder then folder:Destroy() end
			folder = Instance.new("Folder")
			folder.Name = g
			local made = {}
			for cname, c in pairs(gclips) do
				local ks = Instance.new("KeyframeSequence")
				ks.Name = cname
				ks.Loop = c.loop
				ks.Priority = Enum.AnimationPriority[c.priority] or Enum.AnimationPriority.Action
				for _, k in ipairs(c.keys) do
					local kf = buildKeyframe(kids, rootName, k.rot, k.loc, k.t)
					kf.Parent = ks
				end
				ks:SetAttribute("Length", c.length)
				ks:SetAttribute("Guardian", g)
				ks.Parent = folder
				table.insert(made, ("%s(%d kf)"):format(cname, #c.keys))
			end
			table.sort(made)
			folder.Parent = out
			table.insert(lines, ("%-10s %d clips: %s"):format(g, #made, table.concat(made, " ")))
		end
	end
	return table.concat(lines, "\n")
end

--.. drop a copy in Workspace and actually play a clip on it, in edit mode
function API.preview(g, clipName, at)
	local src = guardians() and guardians():FindFirstChild(g)
	if not src then return g .. ": not installed" end
	local ks = animFolder():FindFirstChild(g) and animFolder()[g]:FindFirstChild(clipName)
	if not ks then return g .. "/" .. clipName .. ": no KeyframeSequence" end

	local old = workspace:FindFirstChild("__AnimPreview")
	if old then old:Destroy() end
	local model = src:Clone()
	model.Name = "__AnimPreview"
	local props = model:FindFirstChild("Props")
	if props then props:Destroy() end
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then p.Anchored = false end
	end
	local hrp = model:FindFirstChild("HumanoidRootPart")
	hrp.Anchored = true
	local hum = model:FindFirstChildOfClass("Humanoid")
	local pos = at or Vector3.new(0, (model:GetAttribute("BaseHipHeight") or 3) + 0.2, -70)
	model:PivotTo(CFrame.new(pos))
	model.Parent = workspace

	local animator = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator")
	animator.Parent = hum
	local id = game:GetService("KeyframeSequenceProvider"):RegisterKeyframeSequence(ks)
	local anim = Instance.new("Animation")
	anim.AnimationId = id
	local track = animator:LoadAnimation(anim)
	track.Looped = ks.Loop
	track:Play(0.1)
	return ("playing %s/%s  length %.2f  tempId %s"):format(g, clipName, track.Length, id)
end

function API.stopPreview()
	local old = workspace:FindFirstChild("__AnimPreview")
	if old then old:Destroy() end
	return "preview cleared"
end

function API.report()
	local out = animFolder()
	local lines, total = {}, 0
	for _, folder in ipairs(out:GetChildren()) do
		local names = {}
		for _, ks in ipairs(folder:GetChildren()) do
			local kfs = #ks:GetChildren()
			local poses = 0
			for _, d in ipairs(ks:GetDescendants()) do
				if d:IsA("Pose") then poses += 1 end
			end
			table.insert(names, ("%s[%dkf/%dposes]"):format(ks.Name, kfs, poses))
			total += 1
		end
		table.sort(names)
		table.insert(lines, ("%-10s %s"):format(folder.Name, table.concat(names, " ")))
	end
	table.sort(lines)
	table.insert(lines, total .. " KeyframeSequences")
	return table.concat(lines, "\n")
end

return API
