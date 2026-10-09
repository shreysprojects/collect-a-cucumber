--[[
	BenchLieClient  (LocalScript, StarterPlayerScripts)
	When the local character sits on a Seat carrying the attribute LiePose=true
	(the bench press seat), the default sit animation is stopped. If the seat also
	carries an AnimationId attribute (the bench-press clip), that animation is
	played looped instead; otherwise the neutral pose is held. Either way the seat
	is rotated onto its back, so the pose reads as lying on the bench with the head
	toward the rack. Standing up (jump) hands control back to the normal animations.
]]
local Players = game:GetService("Players")
local player = Players.LocalPlayer

local function WatchHumanoid(humanoid)
	local playedConn, speedConn, myTrack
	humanoid.Seated:Connect(function(active, seat)
		if playedConn then playedConn:Disconnect() playedConn = nil end
		if speedConn then speedConn:Disconnect() speedConn = nil end
		if myTrack then myTrack:Stop(0.2) myTrack = nil end
		if not active or not seat or seat:GetAttribute("LiePose") ~= true then return end
		local animator = humanoid:FindFirstChildOfClass("Animator")
		if not animator then return end
		local function stopOthers()
			for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
				if track ~= myTrack then track:Stop(0.1) end
			end
		end
		local animId = seat:GetAttribute("AnimationId")
		task.defer(function() -- the Animate script starts "sit" right after Seated fires
			stopOthers()
			if type(animId) == "string" and animId ~= "" then
				local animation = Instance.new("Animation")
				animation.AnimationId = animId
				local ok, track = pcall(function() return animator:LoadAnimation(animation) end)
				if ok and track then
					track.Looped = true
					track.Priority = Enum.AnimationPriority.Action
					track:Play(0.2)
					myTrack = track
					--.. bench upgrade: the server sets the RepSpeed attribute (per-tier multipliers from GymService.REP_SPEEDS)
					local function applySpeed()
						if myTrack == track then track:AdjustSpeed(tonumber(player:GetAttribute("RepSpeed")) or 1) end
					end
					applySpeed()
					speedConn = player:GetAttributeChangedSignal("RepSpeed"):Connect(applySpeed)
				else
					warn("[BenchLieClient] could not load " .. tostring(animId) .. ": " .. tostring(track))
				end
			end
		end)
		task.delay(0.2, stopOthers)
		playedConn = animator.AnimationPlayed:Connect(function(track)
			if track ~= myTrack and humanoid.Sit and humanoid.SeatPart == seat then track:Stop(0) end
		end)
	end)
end

local function WatchCharacter(character)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid then WatchHumanoid(humanoid) end
end

player.CharacterAdded:Connect(WatchCharacter)
if player.Character then WatchCharacter(player.Character) end
