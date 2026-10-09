--[[
	BenchServer (Script, ServerScriptService)
	1. Seats: every Seat tagged "LieSeat" (one per plot bench, PlotUpgradeService stands a copy of the
	   template bench by each plot). The seat itself stays untouchable (CanTouch false, no proximity
	   prompt any more); an invisible SeatTrigger box over the pad seats whoever walks onto the bench
	   -- but ONLY the owner of the bench's plot (bench attribute Plot -> plot attribute Owner), via
	   seat:Sit, so nobody else ever gets seated (no ejecting needed). A bench with no plot (the
	   template, or no plot service) is open to everyone. Jump to get up; RESIT_COOLDOWN seconds
	   before the trigger seats the same player again (they are still standing in it).
	   BenchLieClient stops the sit animation and plays the bench-press clip (seat attribute AnimationId).
	2. The barbell: the bench holds a "Barbell" Model (PrimaryPart = Bar). EVERY barbell part is
	   ANCHORED, never welded, never simulated: the server keeps the rest pose (bar at RackCFrame,
	   every other part at its BarOffset attribute = its CFrame relative to the bar), so plates and
	   collars can never fall off, whatever the load order or streaming does. While someone lies on
	   the seat the server watches their hands; when they come up to bar height the barbell is marked
	   Held with the holder's name. BarbellClient then moves the WHOLE set (bar + BarOffset parts)
	   rigidly between the holder's hands every frame on every client, and slides it back to
	   RackCFrame when Held clears.
	   Avatar size: the rack height suits the default R15 arms (fingertips end up ~0.35 under the bar
	   at the top of the clip); shorter arms never get that close, so the grab also accepts hands at
	   the top of the occupant's OWN reach (shoulder height + REACH_TOP x straight-arm length, measured
	   from the rig attachments, plus the highest point the hands have actually been seen at), and the
	   occupant is scooted along the bench (seat weld) so their shoulders lie where the default
	   avatar's do relative to the bar. The rep range threshold scales with the arm length too.
	3. Reps: while the bar is held, one rep is counted per loop of the bench-press clip, paced by the
	   SERVER (clip length / the player's RepSpeed attribute, GymService) rather than by watching the
	   hands. Small bundle avatars (2026-09-06: upper arms half the default length) press the hands
	   only ~0.2 studs, which the old hand-travel counter never saw, so their Strength stayed at 0.
	   The rep timer starts in step with the replicated clip when the server can see it, so the "+N"
	   popup lands near the top of each press. + GymService.StrengthPerRep to the player's Strength
	   and a StrengthPopup remote for the "+N" popup (StrengthPopupClient).
	4. Size: each bench grows with its owner's bench level (plot attribute BenchLevel, GymService):
	   ReplicatedStorage.Modules.BenchScale, 10% per level in the footprint about the bar's x, heights
	   unchanged, barbell uniform about the bar. Re-applied when the level changes and after
	   PlotUpgradeService moves the bench (it refreshes the Barbell's RackCFrame). The seat and the
	   trigger are left alone so the lying pose and the bar stay aligned. Bench attribute BenchScale.
	Engine notes: a player character is simulated by its client, so Humanoid.Jump / Humanoid.Sit set
	on the server do not reliably un-seat it (Sit = false even leaves SeatPart stuck); seat:Sit()
	from the server does work, and players get up by jumping themselves.
]]
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local GymService = require(ServerStorage:WaitForChild("GymService"))
local BenchScale = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("BenchScale"))

--.. grab tolerances, measured from the fingertips' midpoint to the bar centre:
local GRAB_VERTICAL = 0.35 -- studs: the hands may be this far above the bar, or below it (default arms)
local GRAB_BELOW_PEAK = 0.2 -- studs under the occupant's own top-of-reach that still counts as "up" (short arms)
local GRAB_ALONG_BAR = 0.6 -- studs sideways along the bar
local GRAB_FORWARD = 1.6 -- studs along the bench: you lie with your eyes under the bar and unrack it forward
local GRIP_OFFSET = 0.15 -- studs from the hand centres toward the fingertips (hand -Y); keep in step with BarbellClient
--.. avatar size (measured with the v3 clip: 1.0-scale R15 reach 1.84, shoulders 2.0 under the bar and
--.. 1.47 tail-ward of it, fingertips peak 0.34 under the bar; a 0.65-scale avatar: reach 1.21, peak
--.. 0.88 under the bar, shoulders 1.67 tail-ward -> both peak at 0.91 x reach above the shoulders)
local REACH_TOP = 0.9 -- fingertip height above the shoulders at the top of the clip, as a fraction of the straight arm
local REACH_DEFAULT = 1.84 -- straight-arm reach (shoulder rig attachment -> fingertips) of the default R15
local SHOULDER_FORWARD_REF = 1.47 -- studs the default avatar's shoulders lie tail-ward of the bar: every occupant is scooted to this
local SCOOT_DELAY = 0.6 -- seconds after seating before the shoulders are measured (the lying clip has faded in)
local SCOOT_MAX = 1.5 -- studs: clamp for the scoot
--.. rep pacing: one rep per loop of the clip on the seat (attribute AnimationId; BenchLieClient plays it at
--.. the player's RepSpeed). CLIP_LENGTH is the fallback when the replicated track cannot be read.
local CLIP_LENGTH = 2 -- seconds: the bench-press clip at 1x
local REP_MAX_PER_STEP = 8 -- reps awarded in one frame at most (a long hitch cannot dump hundreds)
--.. walk-on seating: bench-space size (along the bench, up, across) of the trigger box over the pad
local TRIGGER_SIZE = Vector3.new(3.4, 1.6, 1.2)
local TRIGGER_LIFT = 0.4 -- studs: trigger centre above the seat centre (covers the legs of someone standing on the pad)
local RESIT_COOLDOWN = 3 -- seconds after getting up before the trigger seats the same player again

local Plots = workspace:WaitForChild("Map"):WaitForChild("Lobby"):WaitForChild("Plots")

--..Remotes..--
local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
if not Remotes then
	Remotes = Instance.new("Folder")
	Remotes.Name = "Remotes"
	Remotes.Parent = ReplicatedStorage
end
local StrengthPopup = Remotes:FindFirstChild("StrengthPopup")
if not StrengthPopup then
	StrengthPopup = Instance.new("RemoteEvent")
	StrengthPopup.Name = "StrengthPopup"
	StrengthPopup.Parent = Remotes
end

--..Ownership..--
local function PlotOfBench(bench)
	local name = bench and bench:GetAttribute("Plot")
	return name and Plots:FindFirstChild(name) or nil
end

local function Allowed(bench, player)
	local plot = PlotOfBench(bench)
	if not plot then return true end
	return plot:GetAttribute("Owner") == player.UserId
end

-- Server-owned, single-use bonus offers. The client never supplies a reward amount.
local BonusPopup = Remotes:FindFirstChild("BenchBonusPopup")
if not BonusPopup then
	BonusPopup = Instance.new("RemoteEvent")
	BonusPopup.Name = "BenchBonusPopup"
	BonusPopup.Parent = Remotes
end
local BONUS_MIN_INTERVAL, BONUS_MAX_INTERVAL = 4, 8
local BONUS_LIFETIME = 6
-- Percent chances: common 3x/5x; rare 10x; very rare 20x.
local function BonusMultiplierForRoll(roll)
	if roll <= 60 then return 3 end
	if roll <= 90 then return 5 end
	if roll <= 98 then return 10 end
	return 20
end
local bonusRandom = Random.new()
local bonusSessions = {}

local function ClearBonus(player, session)
	if bonusSessions[player] ~= session then return end
	bonusSessions[player] = nil
	if player.Parent == Players then BonusPopup:FireClient(player, "Hide", session.Token) end
end

BonusPopup.OnServerEvent:Connect(function(player, token)
	local session = bonusSessions[player]
	if not session or typeof(token) ~= "string" or token ~= session.Token then return end
	local humanoid, seat = session.Humanoid, session.Seat
	if os.clock() >= session.ExpiresAt then
		-- A late packet expires only this offer, not the player's recurring schedule.
		session.Token = nil
		BonusPopup:FireClient(player, "Hide", token)
		return
	end
	if player.Character ~= humanoid.Parent
		or humanoid.Health <= 0 or not seat:IsDescendantOf(workspace)
		or seat.Occupant ~= humanoid or humanoid.SeatPart ~= seat
		or not Allowed(seat.Parent, player) then
		ClearBonus(player, session)
		return
	end
	-- Consume before awarding, so repeated clicks/remote replays cannot pay twice.
	session.Token = nil
	BonusPopup:FireClient(player, "Hide", token)
	local gain = GymService.AwardRep(player, session.Multiplier)
	session.Multiplier = nil
	if gain then
		-- Only a confirmed circle claim starts the local HUD flight.
		BonusPopup:FireClient(player, "Claimed", token, gain)
		StrengthPopup:FireAllClients(humanoid.Parent, gain, "BenchBonus")
	end
end)

Players.PlayerRemoving:Connect(function(player)
	bonusSessions[player] = nil
end)

--..Barbell..--
--.. anchor every part (no welds, no physics) and stamp each non-root part with BarOffset = its CFrame
--.. relative to the bar; BarbellClient / BenchTierClient move the set rigidly from those offsets
local function AnchorBarbell(state)
	local rootCF = state.Root.CFrame
	for _, p in ipairs(state.Barbell:GetDescendants()) do
		if p:IsA("BasePart") then
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			for _, c in ipairs(p:GetChildren()) do
				if c:IsA("WeldConstraint") or c:IsA("JointInstance") then c:Destroy() end -- leftovers from the old welded barbell
			end
			if p ~= state.Root then p:SetAttribute("BarOffset", rootCF:ToObjectSpace(p.CFrame)) end
		end
	end
end

local function SetupBarbell(seat)
	local bench = seat.Parent
	local barbell = bench and bench:FindFirstChild("Barbell")
	if not barbell then return nil end
	local root = barbell.PrimaryPart or barbell:FindFirstChild("Bar")
	if not root then return nil end
	barbell.PrimaryPart = root
	local state = {Barbell = barbell, Root = root, Holder = nil}
	AnchorBarbell(state)
	barbell:SetAttribute("RackCFrame", root.CFrame)
	barbell:SetAttribute("Held", false)
	barbell:SetAttribute("Holder", "")
	CollectionService:AddTag(barbell, "Barbell")
	return state
end

local function Grab(state, character)
	state.Holder = character
	state.Barbell:SetAttribute("Holder", character.Name)
	state.Barbell:SetAttribute("Held", true)
end

local function Release(state)
	state.Holder = nil
	state.Barbell:SetAttribute("Held", false)
	state.Barbell:SetAttribute("Holder", "")
end

--..Size per level..--
local function RackOf(state)
	local rack = state.Barbell:GetAttribute("RackCFrame")
	return typeof(rack) == "CFrame" and rack or state.Root.CFrame
end

--.. remember the unscaled layout (copies arrive from the template unscaled, before any level is applied)
local function CaptureLayout(bench, seat, state)
	local benchCF = BenchScale.BenchCFrame(RackOf(state))
	local layout = {Frame = {}, Bar = {}}
	for _, p in ipairs(bench:GetDescendants()) do
		if p:IsA("BasePart") and p ~= seat and p.Name ~= "SeatTrigger" then
			if p:IsDescendantOf(state.Barbell) then
				layout.Bar[p] = {Offset = state.Root.CFrame:ToObjectSpace(p.CFrame), Size = p.Size}
			else
				layout.Frame[p] = {Offset = benchCF:ToObjectSpace(p.CFrame), Size = p.Size}
			end
		end
	end
	return layout
end

local function ApplyLevel(bench, state, layout)
	local plot = PlotOfBench(bench)
	local level = plot and plot:GetAttribute("BenchLevel") or 1
	local s = BenchScale.Factor(level)
	local rackCF = RackOf(state)
	local benchCF = BenchScale.BenchCFrame(rackCF)
	for part, base in pairs(layout.Frame) do
		if part.Parent then
			local cf, size = BenchScale.FrameTransform(base.Offset, base.Size, s)
			part.Size = size
			part.CFrame = benchCF * cf
		end
	end
	--.. barbell: the rest pose is the rack; every part re-placed about the bar, then the offsets re-stamped
	state.Root.CFrame = rackCF
	for part, base in pairs(layout.Bar) do
		if part.Parent then
			local cf, size = BenchScale.BarbellTransform(base.Offset, base.Size, s)
			part.Size = size
			part.CFrame = rackCF * cf
		end
	end
	AnchorBarbell(state)
	bench:SetAttribute("BenchScale", s)
end

--..Walk-on trigger..--
local function BuildTrigger(bench, seat, state)
	local old = bench:FindFirstChild("SeatTrigger")
	if old then old:Destroy() end
	local trigger = Instance.new("Part")
	trigger.Name = "SeatTrigger"
	trigger.Size = TRIGGER_SIZE
	trigger.Transparency = 1
	trigger.Anchored = true
	trigger.CanCollide = false
	trigger.CanQuery = false
	trigger.CanTouch = true
	trigger.CastShadow = false
	local benchCF = state and BenchScale.BenchCFrame(RackOf(state)) or seat.CFrame
	local rel = benchCF:PointToObjectSpace(seat.Position)
	trigger.CFrame = benchCF * CFrame.new(rel.X, rel.Y + TRIGGER_LIFT, rel.Z)
	trigger.Parent = bench
	return trigger
end

--..Avatar size..--
--.. straight-arm reach: shoulder rig attachment -> elbow -> wrist -> hand centre -> fingertips (rigid
--.. segments, so the pose does not matter); nil when the rig has no R15 attachments
local function ArmReach(character)
	local torso = character:FindFirstChild("UpperTorso")
	local upper = character:FindFirstChild("RightUpperArm")
	local lower = character:FindFirstChild("RightLowerArm")
	local hand = character:FindFirstChild("RightHand")
	local s = torso and torso:FindFirstChild("RightShoulderRigAttachment")
	local e = upper and upper:FindFirstChild("RightElbowRigAttachment")
	local w = lower and lower:FindFirstChild("RightWristRigAttachment")
	if not (s and e and w and hand) then return nil end
	return (s.WorldPosition - e.WorldPosition).Magnitude + (e.WorldPosition - w.WorldPosition).Magnitude
		+ (w.WorldPosition - hand.Position).Magnitude + GRIP_OFFSET
end

--.. midpoint of the two shoulder rig attachments (falls back to the upper torso)
local function ShoulderMid(character)
	local torso = character:FindFirstChild("UpperTorso")
	if not torso then return nil end
	local r, l = torso:FindFirstChild("RightShoulderRigAttachment"), torso:FindFirstChild("LeftShoulderRigAttachment")
	if r and l then return (r.WorldPosition + l.WorldPosition) * 0.5 end
	return torso.Position
end

--.. scoot the occupant along the bench so their shoulders lie SHOULDER_FORWARD_REF studs tail-ward of
--.. the bar like the default avatar's (short torsos end up further from the rack): shifts the seat
--.. weld the engine made for this sitting (a new weld is made every time someone sits)
local function Scoot(seat, state, humanoid)
	local character = humanoid.Parent
	task.wait(SCOOT_DELAY)
	if seat.Occupant ~= humanoid or not character.Parent then return end
	local benchCF = BenchScale.BenchCFrame(RackOf(state))
	local fwd = benchCF.RightVector -- bench x: toward the rack
	local rackPos = RackOf(state).Position
	local sum, n = 0, 0
	for _ = 1, 6 do
		RunService.Heartbeat:Wait()
		if seat.Occupant ~= humanoid then return end
		local sh = ShoulderMid(character)
		if sh then
			sum += (rackPos - sh):Dot(fwd)
			n += 1
		end
	end
	if n == 0 then return end
	local shift = math.clamp(sum / n - SHOULDER_FORWARD_REF, -SCOOT_MAX, SCOOT_MAX)
	local weld = seat:FindFirstChild("SeatWeld")
	if math.abs(shift) < 0.05 or not (weld and weld:IsA("Weld")) then return end
	weld.C0 = CFrame.new(seat.CFrame:VectorToObjectSpace(fwd * shift)) * weld.C0
	seat:SetAttribute("Scoot", shift)
end

--..Reps..--
local function AwardRep(character)
	local player = Players:GetPlayerFromCharacter(character)
	if not player then return end
	local gain = GymService.AwardRep(player) -- strength per rep from the bench level
	if gain then
		StrengthPopup:FireAllClients(character, gain)
	end
end

--.. the bench-press track on the occupant's Animator: the client plays it, the server sees a mirror
local function ClipTrack(humanoid, clipId)
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator or type(clipId) ~= "string" then return nil end
	for _, t in ipairs(animator:GetPlayingAnimationTracks()) do
		local anim = t.Animation
		if anim and anim.AnimationId == clipId then return t end
	end
	return nil
end

local function WatchOccupant(seat, state, humanoid)
	local character = humanoid.Parent
	local player = Players:GetPlayerFromCharacter(character)
	local bonusSession
	if player and Allowed(seat.Parent, player) then
		local previous = bonusSessions[player]
		if previous then ClearBonus(player, previous) end
		bonusSession = {Seat = seat, Humanoid = humanoid,
			NextAt = os.clock() + bonusRandom:NextNumber(BONUS_MIN_INTERVAL, BONUS_MAX_INTERVAL)}
		bonusSessions[player] = bonusSession
	end
	local reach = ArmReach(character) or REACH_DEFAULT
	local clipId = seat:GetAttribute("AnimationId")
	local progress = nil -- fraction of the current rep; nil until the bar is held
	local track, trackCheck = nil, 0
	local last = os.clock()
	local peakSeen, peakConfirmed = -math.huge, nil -- highest fingertips so far; confirmed once they come back down
	task.spawn(Scoot, seat, state, humanoid)
	local conn
	conn = RunService.Heartbeat:Connect(function()
		if seat.Occupant ~= humanoid or not character.Parent or humanoid.Health <= 0
			or not seat:IsDescendantOf(workspace) or (player and not Allowed(seat.Parent, player)) then
			conn:Disconnect()
			if bonusSession then ClearBonus(player, bonusSession) end
			if state.Holder == character then Release(state) end
			return
		end
		local now = os.clock()
		if bonusSession and bonusSessions[player] == bonusSession then
			if bonusSession.Token and now >= bonusSession.ExpiresAt then
				BonusPopup:FireClient(player, "Hide", bonusSession.Token)
				bonusSession.Token, bonusSession.Multiplier = nil, nil
			end
			if now >= bonusSession.NextAt then
				local interval = bonusRandom:NextNumber(BONUS_MIN_INTERVAL, BONUS_MAX_INTERVAL)
				local lifetime = math.min(BONUS_LIFETIME, interval)
				bonusSession.NextAt = now + interval
				bonusSession.ExpiresAt = now + lifetime
				bonusSession.Token = game:GetService("HttpService"):GenerateGUID(false)
				bonusSession.Multiplier = BonusMultiplierForRoll(bonusRandom:NextInteger(1, 100))
				BonusPopup:FireClient(player, "Show", bonusSession.Token, seat,
					workspace:GetServerTimeNow() + lifetime, bonusSession.Multiplier)
			end
		end
		local dt = now - last
		last = now
		if state.Holder == character then
			--.. one rep per clip loop, paced by the server's RepSpeed (the clip itself is only cosmetic)
			if now >= trackCheck then
				trackCheck = now + 0.5
				track = ClipTrack(humanoid, clipId)
			end
			local length = track and track.Length > 0 and track.Length or CLIP_LENGTH
			if not progress then
				--.. start in step with the clip so the popup lands near the top of the press
				progress = track and (track.TimePosition / length) % 1 or 0
				return
			end
			local speed = math.max(0, tonumber(player and player:GetAttribute("RepSpeed")) or 1)
			progress += dt * speed / length
			local reps = 0
			while progress >= 1 and reps < REP_MAX_PER_STEP do
				progress -= 1
				reps += 1
				AwardRep(character)
			end
			if progress >= 1 then progress %= 1 end
			return
		end
		progress = nil
		if state.Holder then return end
		local rh, lh = character:FindFirstChild("RightHand"), character:FindFirstChild("LeftHand")
		if not (rh and lh) then return end
		local tips = (rh.Position + lh.Position) * 0.5 - rh.CFrame.UpVector * GRIP_OFFSET
		--.. not holding yet: grab when the hands come up to the bar -- or, for arms too short to get
		--.. there, to the top of their own reach (predicted from the rig, and as actually observed)
		if tips.Y > peakSeen then
			peakSeen = tips.Y
		elseif tips.Y < peakSeen - 0.1 then
			peakConfirmed = peakSeen
		end
		local rootPos = RackOf(state).Position
		local d = tips - rootPos
		local axis = RackOf(state).RightVector -- the bar runs along its cylinder axis
		local along = d:Dot(axis)
		local forward = (d - axis * along - Vector3.new(0, d.Y, 0)).Magnitude
		local lowest = rootPos.Y - GRAB_VERTICAL
		local shoulder = ShoulderMid(character)
		if shoulder then lowest = math.min(lowest, shoulder.Y + reach * REACH_TOP - GRAB_BELOW_PEAK) end
		if peakConfirmed then lowest = math.min(lowest, peakConfirmed - GRAB_BELOW_PEAK) end
		if tips.Y >= lowest and d.Y <= GRAB_VERTICAL and math.abs(along) <= GRAB_ALONG_BAR and forward <= GRAB_FORWARD then
			Grab(state, character)
			progress = nil
		end
	end)
end

--..Seats..--
local function Hook(seat)
	if not seat:IsA("Seat") then return end
	local bench = seat.Parent
	local prompt = seat:FindFirstChildOfClass("ProximityPrompt")
	if prompt then prompt:Destroy() end -- walk onto the bench instead
	seat.CanTouch = false -- the engine never seats anyone by itself; the trigger below does, owner only
	seat.CanCollide = false
	seat.CanQuery = false
	local state = SetupBarbell(seat)
	local layout = state and CaptureLayout(bench, seat, state)
	if state then
		ApplyLevel(bench, state, layout)
		local plot = PlotOfBench(bench)
		if plot then
			plot:GetAttributeChangedSignal("BenchLevel"):Connect(function() ApplyLevel(bench, state, layout) end)
		end
		--.. PlotUpgradeService refreshes RackCFrame after moving the bench (plot resized)
		state.Barbell:GetAttributeChangedSignal("RackCFrame"):Connect(function()
			task.defer(ApplyLevel, bench, state, layout)
		end)
	end
	local trigger = BuildTrigger(bench, seat, state)
	local lastLeft = {} -- [player] = os.clock() when they got up from this seat
	trigger.Touched:Connect(function(hit)
		local character = hit.Parent
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local player = humanoid and Players:GetPlayerFromCharacter(character)
		if not player or not Allowed(bench, player) then return end
		if seat.Occupant ~= nil or humanoid.Sit or humanoid.SeatPart or humanoid.Health <= 0 then return end
		if lastLeft[player] and os.clock() - lastLeft[player] < RESIT_COOLDOWN then return end
		seat:Sit(humanoid)
	end)
	local current
	seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		local occupant = seat.Occupant
		if occupant then
			current = Players:GetPlayerFromCharacter(occupant.Parent)
			if state then WatchOccupant(seat, state, occupant) end
		else
			if current then lastLeft[current] = os.clock() end
			current = nil
			seat:SetAttribute("Scoot", nil)
			if state and state.Holder then Release(state) end
		end
	end)
	Players.PlayerRemoving:Connect(function(player) lastLeft[player] = nil end)
end

for _, seat in ipairs(CollectionService:GetTagged("LieSeat")) do Hook(seat) end
CollectionService:GetInstanceAddedSignal("LieSeat"):Connect(Hook)