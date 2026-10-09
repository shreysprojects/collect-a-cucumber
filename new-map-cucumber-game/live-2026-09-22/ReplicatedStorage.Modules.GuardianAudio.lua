-- Spatial guardian audio. Sound instances live under each guardian's HumanoidRootPart.
-- Edit Sleep / TheftReaction in the guardian template to change its voice or hearing range.
local Audio = {}
local bound = {}
local sleeping = {Asleep = true, Resting = true}

function Audio.Bind(model)
    if bound[model] then return bound[model] end
    local root = model:FindFirstChild("HumanoidRootPart")
    local emitter = root and root:FindFirstChild("GuardianAudio")
    if not emitter then return nil end
    local snore = emitter:FindFirstChild("Sleep")
    local reaction = emitter:FindFirstChild("TheftReaction")
    if not (snore and reaction) then return nil end
    local entry = {Sleep = snore, Reaction = reaction, LastTheft = -math.huge}
    bound[model] = entry
    local function refresh()
        local state = model:GetAttribute("State")
        if sleeping[state] then
            reaction:Stop()
            if not snore.IsPlaying then snore:Play() end
        else
            snore:Stop()
            if state == "Stunned" then reaction:Stop() end
        end
    end
    entry.StateConnection = model:GetAttributeChangedSignal("State"):Connect(refresh)
    entry.DestroyConnection = model.Destroying:Connect(function()
        snore:Stop()
        reaction:Stop()
        entry.StateConnection:Disconnect()
        entry.DestroyConnection:Disconnect()
        bound[model] = nil
    end)
    refresh()
    return entry
end

function Audio.StolenFrom(model)
    local entry = Audio.Bind(model)
    if not entry or model:GetAttribute("State") == "Stunned" then return false end
    local clock = os.clock()
    if clock - entry.LastTheft < 2.5 then return false end
    entry.LastTheft = clock
    entry.Sleep:Stop()
    entry.Reaction:Stop()
    entry.Reaction.TimePosition = 0
    entry.Reaction:Play()
    return true
end

return Audio
