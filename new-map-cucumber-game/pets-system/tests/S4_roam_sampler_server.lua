-- S4 (2026-09-22) roam agreement sampler, SERVER VM (paste into eval_server_runtime). For DURATION s:
-- every published segment of every PlotPet as the server first sees it (Pub = server time of that
-- Heartbeat), PetService.GetLogicalPosition(id, now) vs PetMotion.Sample(ReadSegment(model), now) (the
-- server's logical sample must equal the published attributes), and a workspace S4Clock stamp once a
-- second for the clients' clock-offset check (play VM only; cleared at the end).
local DURATION = 30
local CS = game:GetService("CollectionService")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local PetService = require(game:GetService("ServerStorage").PetService)
local PetMotion = require(RS.Modules.PetMotion)
local S = {Segs = {}, Frames = 0, MaxLogicalDev = 0, LogicalSamples = 0, LogicalNil = 0}
_G.S4Roam = S
local t0 = os.clock()
local stampAt = 0
local conn
conn = RunService.Heartbeat:Connect(function()
	local el = os.clock() - t0
	if el > DURATION then
		conn:Disconnect()
		workspace:SetAttribute("S4Clock", nil)
		S.Done = true
		return
	end
	local now = workspace:GetServerTimeNow()
	if el >= stampAt then
		stampAt += 1
		workspace:SetAttribute("S4Clock", now)
	end
	S.Frames += 1
	for _, m in ipairs(CS:GetTagged("PlotPet")) do
		local id, seq = m:GetAttribute("PetId"), m:GetAttribute("RoamSeq")
		if type(id) == "string" and type(seq) == "number" then
			local key = id .. "#" .. seq
			local seg = PetMotion.ReadSegment(m)
			if seg and not S.Segs[key] then
				S.Segs[key] = {Id = id, Seq = seq, From = {seg.From.X, seg.From.Z}, To = {seg.To.X, seg.To.Z}, Start = seg.Start, End = seg.End, GroundY = seg.GroundY, Recv = now}
			end
			local logical = PetService.GetLogicalPosition(id, now)
			local attr = seg and PetMotion.Sample(seg, now)
			if logical and attr then
				S.LogicalSamples += 1
				local d = (logical - attr).Magnitude
				if d > S.MaxLogicalDev then S.MaxLogicalDev = d end
			else
				S.LogicalNil += 1
			end
		end
	end
end)
return "server sampler started for " .. DURATION .. " s"
