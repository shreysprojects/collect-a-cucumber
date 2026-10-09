--[[
	build_kfs.lua -- run through the Studio MCP (edit mode) while pets-remake/serve.ps1 serves
	assets/anims on http://127.0.0.1:8765. Fetches <NAME>.json (r15animlib.export_json: 15 fps
	pose samples, per bone quaternion w,x,y,z + optional translation in the Roblox joint frame),
	builds ReplicatedStorage.Assets.Animations.<NAME>Sequence (KeyframeSequence, Pose hierarchy
	rooted at HumanoidRootPart, Linear easing like the earlier cucumber clips) and makes sure an
	Animation named <NAME> sits next to it (AnimationId filled in after the Open Cloud upload).
]]
local NAME = "CucumberFall"
local HttpService = game:GetService("HttpService")
local RS = game:GetService("ReplicatedStorage")
local url = "http://127.0.0.1:8765/" .. NAME .. ".json"
local text
for _ = 1, 20 do
	local ok, res = pcall(HttpService.GetAsync, HttpService, url)
	if ok then text = res break end
	task.wait(1)
end
assert(text, "could not fetch " .. url)
local data = HttpService:JSONDecode(text)
local PARENT = {
	LowerTorso = "HumanoidRootPart", UpperTorso = "LowerTorso", Head = "UpperTorso",
	LeftUpperArm = "UpperTorso", LeftLowerArm = "LeftUpperArm", LeftHand = "LeftLowerArm",
	RightUpperArm = "UpperTorso", RightLowerArm = "RightUpperArm", RightHand = "RightLowerArm",
	LeftUpperLeg = "LowerTorso", LeftLowerLeg = "LeftUpperLeg", LeftFoot = "LeftLowerLeg",
	RightUpperLeg = "LowerTorso", RightLowerLeg = "RightUpperLeg", RightFoot = "RightLowerLeg",
}
local ORDER = {"HumanoidRootPart", "LowerTorso", "UpperTorso", "Head", "LeftUpperArm", "LeftLowerArm", "LeftHand",
	"RightUpperArm", "RightLowerArm", "RightHand", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg", "RightLowerLeg", "RightFoot"}
local folder = RS:WaitForChild("Assets"):WaitForChild("Animations")
local old = folder:FindFirstChild(NAME .. "Sequence")
if old then old:Destroy() end
local kfs = Instance.new("KeyframeSequence")
kfs.Name = NAME .. "Sequence"
kfs.Loop = data.loop == true
kfs.Priority = Enum.AnimationPriority[data.priority or "Action"]
for _, fr in ipairs(data.frames) do
	local kf = Instance.new("Keyframe")
	kf.Time = fr.t
	local poses = {}
	for _, name in ipairs(ORDER) do
		local e = fr.poses[name]
		local p = Instance.new("Pose")
		p.Name = name
		p.Weight = 1
		p.EasingStyle = Enum.PoseEasingStyle.Linear
		p.EasingDirection = Enum.PoseEasingDirection.In
		if e then
			local q, pos = e.q, e.p or {0, 0, 0}
			p.CFrame = CFrame.new(pos[1], pos[2], pos[3], q[2], q[3], q[4], q[1])
		end
		poses[name] = p
		p.Parent = PARENT[name] and poses[PARENT[name]] or kf
	end
	kf.Parent = kfs
end
kfs.Parent = folder
local anim = folder:FindFirstChild(NAME)
if not anim then
	anim = Instance.new("Animation")
	anim.Name = NAME
	anim.Parent = folder
end
local frames = kfs:GetKeyframes()
print(("%s: %d keyframes, last t %.3f, loop %s, priority %s; Animation %s id '%s'"):format(
	kfs.Name, #frames, frames[#frames].Time, tostring(kfs.Loop), tostring(kfs.Priority), anim.Name, anim.AnimationId))
