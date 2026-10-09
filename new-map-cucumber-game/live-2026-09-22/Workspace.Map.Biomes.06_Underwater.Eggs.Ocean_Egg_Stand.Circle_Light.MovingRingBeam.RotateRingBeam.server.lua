local RunService = game:GetService("RunService")
local model = script.Parent
local speed = math.rad(32)
local center = select(1, model:GetBoundingBox()).Position
local initialRelativePivot = CFrame.new(center):ToObjectSpace(model:GetPivot())
local angle = 0

RunService.Heartbeat:Connect(function(dt)
    if not model.Parent then return end
    angle += speed * dt
    model:PivotTo(CFrame.new(center) * CFrame.Angles(0, angle, 0) * initialRelativePivot)
end)
