--[[
	WP-HATCH EggPlacement id test (2026-09-22, read-only).
	Runs the PATCHED ServerScriptService.EggPlacement source (loopback :8794) in a setfenv sandbox with
	plain-table fakes (no DataModel instance is created or changed; CucumberMutations Parse/Join are the
	live module's, ApplyLook is stubbed). Checks CONTRACTS 4.3: Place stamps a fresh GUID EggId before the
	PlacedEgg tag and before parenting; RestoreEgg reuses a valid record.Id (1..64 chars) and mints a
	fresh GUID otherwise; the other restored attributes and the EggPlacementAPI names are unchanged.
	Returns "WP-HATCH eggplacement_ids: PASS n / FAIL m: <first failures>".
]]
local HttpService = game:GetService("HttpService")
local RealMutations = require(game:GetService("ReplicatedStorage").Modules.CucumberMutations)
local src = HttpService:GetAsync("http://127.0.0.1:8794/ServerScriptService.EggPlacement.server.lua")

local pass, fail, failures = 0, 0, {}
local function check(name, cond, detail)
	if cond then pass += 1 else
		fail += 1
		if #failures < 12 then table.insert(failures, name .. (detail and (" [" .. tostring(detail) .. "]") or "")) end
	end
end

local function Signal()
	local s = {Fns = {}}
	function s:Connect(fn) table.insert(self.Fns, fn) return {Disconnect = function() end} end
	function s:Fire(...) for _, fn in ipairs(self.Fns) do fn(...) end end
	return s
end

local Tags, TagLog = {}, {}
local Fake
Fake = function(name, class, props)
	local o = {__fake = true, Name = name, ClassName = class, Attrs = {}, Children = {}, Scale = 1}
	for k, v in pairs(props or {}) do o[k] = v end
	function o:GetAttribute(k) return self.Attrs[k] end
	function o:SetAttribute(k, v) self.Attrs[k] = v end
	function o:GetAttributeChangedSignal() return Signal() end
	function o:FindFirstChild(n) return self.Children[n] end
	function o:WaitForChild(n) return self.Children[n] end
	function o:GetChildren() local t = {} for _, c in pairs(self.Children) do table.insert(t, c) end return t end
	function o:GetDescendants() return self:GetChildren() end
	function o:IsA(c) return self.ClassName == c or (c == "BasePart" and self.ClassName == "Part") end
	function o:ScaleTo(s) self.Scale = s end
	function o:GetScale() return self.Scale end
	function o:PivotTo(cf) self.Pivot = cf end
	function o:GetPivot() return self.Pivot or CFrame.new() end
	function o:Destroy() self.Parent = nil self.Destroyed = true end
	function o:ClearAllChildren() self.Children = {} end
	function o:Clone()
		local c = Fake(self.Name, self.ClassName)
		for k, v in pairs(self.Attrs) do c.Attrs[k] = v end
		c.PrimaryPart = self.PrimaryPart and Fake("Hitbox", "Part", {Size = self.PrimaryPart.Size}) or nil
		return c
	end
	return o
end
local function Add(parent, child) parent.Children[child.Name] = child child.Parent = parent return child end

local Players = Fake("Players", "Players")
Players.PlayerRemoving = Signal()
local ReplicatedStorage = Fake("ReplicatedStorage", "ReplicatedStorage")
local Modules = Add(ReplicatedStorage, Fake("Modules", "Folder"))
local LookCalls = 0
local FakeMutations = {Parse = RealMutations.Parse, Join = RealMutations.Join, ApplyLook = function() LookCalls += 1 end}
Add(Modules, Fake("CucumberMutations", "ModuleScript", {Module = FakeMutations}))
local Remotes = Add(ReplicatedStorage, Fake("Remotes", "Folder"))
local requestPlacement = Add(Remotes, Fake("requestPlacement", "RemoteFunction"))
local Models = Add(ReplicatedStorage, Fake("PlaceableModels", "Folder"))
local template = Add(Models, Fake("Basic Egg", "Model"))
template.PrimaryPart = Fake("Hitbox", "Part", {Size = Vector3.new(4, 5, 4)})
template.Attrs = {EggName = "Basic", BiomeIndex = 1}

local ServerStorage = Fake("ServerStorage", "ServerStorage")
local api = Add(ServerStorage, Fake("EggPlacementAPI", "Folder"))
local restoreB = Add(api, Fake("RestoreEgg", "BindableFunction"))
local clearB = Add(api, Fake("ClearEggs", "BindableFunction"))

local CollectionService = {}
function CollectionService:AddTag(inst, tag)
	Tags[inst] = Tags[inst] or {}
	Tags[inst][tag] = true
	table.insert(TagLog, {Inst = inst, Tag = tag, EggId = inst.Attrs.EggId, Parent = inst.Parent})
end
function CollectionService:HasTag(inst, tag) return Tags[inst] ~= nil and Tags[inst][tag] == true end

local guidN = 0
local FakeHttp = {}
function FakeHttp:GenerateGUID(braces)
	guidN += 1
	return ("%08X-0000-4000-8000-%012X"):format(guidN, guidN) .. (braces and "}" or "")
end

local Workspace = Fake("Workspace", "Workspace")
function Workspace:GetServerTimeNow() return 5000 end
function Workspace:GetPartBoundsInBox() return {} end
local Map = Add(Workspace, Fake("Map", "Model"))
local Lobby = Add(Map, Fake("Lobby", "Model"))
local Plots = Add(Lobby, Fake("Plots", "Folder"))
Add(Map, Fake("Biomes", "Folder"))
local plot = Add(Plots, Fake("Plot1", "Part", {Position = Vector3.new(), Size = Vector3.new(40, 1, 40), CFrame = CFrame.new()}))
local holder = Add(plot, Fake("Placed", "Folder"))
plot.Attrs.Owner = 101

local player = Fake("Alice", "Player", {UserId = 101})
local character = Fake("Character", "Model")
Add(character, Fake("HumanoidRootPart", "Part", {Position = Vector3.new(0, 3, 0)}))
player.Character = character
local backpack = Add(player, Fake("Backpack", "Folder"))

local fakeGame = {}
function fakeGame:GetService(name)
	return ({Players = Players, ReplicatedStorage = ReplicatedStorage, CollectionService = CollectionService,
		HttpService = FakeHttp, ServerStorage = ServerStorage})[name] or error("no fake service " .. name)
end
local InstanceNew = 0
local env = {
	game = fakeGame, workspace = Workspace, Vector3 = Vector3, CFrame = CFrame, OverlapParams = OverlapParams, Enum = Enum,
	math = math, string = string, table = table, type = type, tostring = tostring, tonumber = tonumber, pairs = pairs,
	ipairs = ipairs, pcall = pcall, error = error, select = select, os = os, next = next, warn = function() end, print = function() end,
	typeof = function(v) if type(v) == "table" and v.__fake then return "Instance" end return typeof(v) end,
	Instance = {new = function() InstanceNew += 1 error("Instance.new in the sandbox") end},
	require = function(m) if type(m) == "table" and m.Module ~= nil then return m.Module end error("unknown module") end,
}
local chunk, err = loadstring(src, "=EggPlacement(patched)")
if not chunk then return "WP-HATCH eggplacement_ids: COMPILE FAIL " .. tostring(err) end
setfenv(chunk, env)
local okLoad, loadErr = pcall(chunk)
check("script loads in the sandbox", okLoad, loadErr)
if not okLoad then return ("WP-HATCH eggplacement_ids: PASS %d / FAIL %d: %s"):format(pass, fail, table.concat(failures, "; ")) end
check("no Instance.new (API + remote found)", InstanceNew == 0)
check("EggPlacementAPI.RestoreEgg / ClearEggs wired", type(restoreB.OnInvoke) == "function" and type(clearB.OnInvoke) == "function")
check("requestPlacement wired", type(requestPlacement.OnServerInvoke) == "function")

--..Place..--
local function MakeTool()
	local tool = Add(backpack, Fake("Basic Egg (12 kg)", "Tool"))
	tool.Attrs = {EggName = "Basic", Scale = 1, Kg = 12, Material = "", Mutations = "NEON", DisplayName = "Basic Egg"}
	Tags[tool] = {EggTool = true}
	return tool
end
local tool = MakeTool()
local ok, reason = requestPlacement.OnServerInvoke(player, tool, CFrame.new(5, 0, 5))
check("Place succeeds", ok == true, reason)
local rec = TagLog[#TagLog]
check("Place: PlacedEgg tag added", rec and rec.Tag == "PlacedEgg")
local placedEgg = rec and rec.Inst
check("Place: EggId is a 36-char GUID, set before the tag", rec and type(rec.EggId) == "string" and #rec.EggId == 36 and not rec.EggId:find("[{}]"), rec and rec.EggId)
check("Place: EggId set before parenting (Parent nil at AddTag)", rec and rec.Parent == nil)
check("Place: parented to plot.Placed, tool consumed", placedEgg and placedEgg.Parent == holder and tool.Destroyed == true)
check("Place: look / timer attributes unchanged", placedEgg and placedEgg.Attrs.Owner == 101 and placedEgg.Attrs.EggName == "Basic"
	and placedEgg.Attrs.Kg == 12 and placedEgg.Attrs.Material == nil and placedEgg.Attrs.Mutations == "NEON"
	and placedEgg.Attrs.HatchAt == 5000 + placedEgg.Attrs.HatchSeconds and LookCalls == 1)
task.wait(0.25) -- PLACE_COOLDOWN (0.2 s, os.clock)
local tool2 = MakeTool()
local ok2 = requestPlacement.OnServerInvoke(player, tool2, CFrame.new(-10, 0, -10))
local rec2 = TagLog[#TagLog]
check("Place: every egg gets its own id", ok2 == true and rec2.Inst ~= placedEgg and rec2.EggId ~= rec.EggId, tostring(ok2))

--..RestoreEgg..--
local function Restore(id)
	local record = {Id = id, EggName = "Basic", Kg = 5, Scale = 1.2, Material = "Golden", Mutations = "NEON", DisplayName = "Golden Basic Egg",
		HatchSeconds = 300, PlacedAt = 100, HatchAt = 400}
	local before = guidN
	local model, why = restoreB.OnInvoke(player, plot, record, CFrame.new(1, 2, 3))
	local tagRec = TagLog[#TagLog]
	return model, why, tagRec, guidN - before
end
local m1, why1, t1, minted1 = Restore("11111111-2222-3333-4444-555555555555")
check("Restore: valid saved Id reused", m1 and m1.Attrs.EggId == "11111111-2222-3333-4444-555555555555" and minted1 == 0, why1)
check("Restore: EggId before the tag and before parenting", t1 and t1.Inst == m1 and t1.EggId == m1.Attrs.EggId and t1.Parent == nil)
check("Restore: other attributes unchanged", m1 and m1.Attrs.HatchAt == 400 and m1.Attrs.PlacedAt == 100 and m1.Attrs.HatchSeconds == 300
	and m1.Attrs.Material == "Golden" and m1.Attrs.Mutations == "NEON" and m1.Attrs.Kg == 5 and m1.Parent == holder)
local m64 = Restore(string.rep("a", 64))
check("Restore: a 64-char Id is valid", m64 and m64.Attrs.EggId == string.rep("a", 64))
local seen = {}
for _, bad in ipairs({"", string.rep("b", 65), 12345, false}) do
	local m, _, _, minted = Restore(bad)
	check("Restore: invalid Id " .. tostring(bad):sub(1, 8) .. " -> fresh GUID", m and type(m.Attrs.EggId) == "string" and #m.Attrs.EggId == 36
		and m.Attrs.EggId ~= bad and minted == 1 and not seen[m.Attrs.EggId], m and m.Attrs.EggId)
	if m then seen[m.Attrs.EggId] = true end
end
local mNil, _, _, mintedNil = Restore(nil)
check("Restore: missing Id -> fresh GUID", mNil and #mNil.Attrs.EggId == 36 and mintedNil == 1)
check("no Instance.new during the run", InstanceNew == 0)

return ("WP-HATCH eggplacement_ids: PASS %d / FAIL %d%s"):format(pass, fail, #failures > 0 and (": " .. table.concat(failures, "; ")) or "")
