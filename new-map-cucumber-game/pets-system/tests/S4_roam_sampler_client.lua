-- S4 (2026-09-22) roam agreement sampler, CLIENT VM (paste into eval_client_runtime). Starts a Heartbeat
-- sampler for DURATION s that records, per pet, every RoamSeq segment as this client first saw it (with the
-- client's GetServerTimeNow at that frame), the rendered pivot vs PetMotion.Sample of the same segment
-- (at this frame's and the previous frame's server time: the Heartbeat order vs PetRoamClient is not
-- fixed), and the per-frame XZ displacement of the rendered pivot. Also records the server clock stamps
-- (workspace attribute S4Clock, set by the server sampler) against this client's server time.
local DURATION = 30
local CS = game:GetService("CollectionService")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local PetMotion = require(RS.Modules.PetMotion)
local S = {Segs = {}, Frames = 0, DevNow = {}, DevBest = {}, MaxSpeed = 0, MaxDisp = 0, MaxDispAt = nil, Clock = {}, Walking = 0, Idle = 0}
_G.S4Roam = S
local last = {}
local prevNow = nil
local t0 = os.clock()
local clockConn = workspace:GetAttributeChangedSignal("S4Clock"):Connect(function()
	local v = workspace:GetAttribute("S4Clock")
	if type(v) == "number" then table.insert(S.Clock, workspace:GetServerTimeNow() - v) end
end)
local conn
conn = RunService.Heartbeat:Connect(function(dt)
	if os.clock() - t0 > DURATION then
		conn:Disconnect()
		clockConn:Disconnect()
		S.Done = true
		return
	end
	local now = workspace:GetServerTimeNow()
	S.Frames += 1
	for _, m in ipairs(CS:GetTagged("PlotPet")) do
		local id, seq = m:GetAttribute("PetId"), m:GetAttribute("RoamSeq")
		if type(id) == "string" and type(seq) == "number" then
			local key = id .. "#" .. seq
			local seg = PetMotion.ReadSegment(m)
			if seg and not S.Segs[key] then
				S.Segs[key] = {Id = id, Seq = seq, From = {seg.From.X, seg.From.Z}, To = {seg.To.X, seg.To.Z}, Start = seg.Start, End = seg.End, GroundY = seg.GroundY, Recv = now}
			end
			local root = m.PrimaryPart
			if seg and root and root.Parent then
				local piv = m:GetPivot().Position
				local e1 = PetMotion.Sample(seg, now)
				local e0 = prevNow and PetMotion.Sample(seg, prevNow) or e1
				local d1 = Vector3.new(piv.X - e1.X, 0, piv.Z - e1.Z).Magnitude
				local d0 = Vector3.new(piv.X - e0.X, 0, piv.Z - e0.Z).Magnitude
				table.insert(S.DevNow, d1)
				table.insert(S.DevBest, math.min(d0, d1))
				local _, walking = PetMotion.Sample(seg, now)
				if walking then S.Walking += 1 else S.Idle += 1 end
				local l = last[m]
				if l and dt > 0 then
					local disp = Vector3.new(piv.X - l.X, 0, piv.Z - l.Z).Magnitude
					if disp > S.MaxDisp then S.MaxDisp = disp S.MaxDispAt = {id, seq, now, dt} end
					local speed = disp / dt
					if speed > S.MaxSpeed then S.MaxSpeed = speed end
				end
				last[m] = piv
			else
				last[m] = nil
			end
		end
	end
	prevNow = now
end)
return "client sampler started for " .. DURATION .. " s"
