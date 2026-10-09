-- build_bat.lua  (edit mode, via install.lua; idempotent). Called with the BatServer source as its one
-- argument. Builds StarterPack.Bat: a part-built baseball bat (cylinders welded to a cylinder Handle
-- whose length runs along its local X) held with the classic sword grip turned onto that axis, plus
-- the BatServer script that swings it (toolanim "Slash" for the default Animate script) and hits
-- zombies through ServerStorage.ZombieAPI.
local batSource = ...
local StarterPack = game:GetService("StarterPack")

local old = StarterPack:FindFirstChild("Bat")
if old then old:Destroy() end

local WOOD = Color3.fromRGB(205, 165, 105)
local DARK_WOOD = Color3.fromRGB(120, 82, 46)
local TAPE = Color3.fromRGB(30, 30, 34)
local STRIPE = Color3.fromRGB(220, 50, 50)

local tool = Instance.new("Tool")
tool.Name = "Bat"
tool.ToolTip = "Smash zombies!"
tool.CanBeDropped = false
tool.RequiresHandle = true
--.. the handle's +X (its length) maps to the grip frame's Up = the hand's forward, like a sword blade;
--.. GripPos -1.35 = the fist holds the bat 1.35 studs toward the knob end
tool.Grip = CFrame.fromMatrix(Vector3.new(-1.35, 0, 0), Vector3.new(0, 1, 0), Vector3.new(1, 0, 0))

local handle = Instance.new("Part")
handle.Name = "Handle"
handle.Shape = Enum.PartType.Cylinder
handle.Size = Vector3.new(4.4, 0.42, 0.42)
handle.Color = WOOD
handle.Material = Enum.Material.Wood
handle.CanCollide = false
handle.CanQuery = false
handle.CanTouch = false
handle.CFrame = CFrame.new(0, 10, 0)
handle.Parent = tool

local function piece(name, size, offset, color, material)
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = Enum.PartType.Cylinder
	p.Size = size
	p.CFrame = handle.CFrame * offset
	p.Color = color
	p.Material = material
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = handle
	weld.Part1 = p
	weld.Parent = p
	p.Parent = tool
	return p
end
piece("Barrel", Vector3.new(2.1, 0.72, 0.72), CFrame.new(1.15, 0, 0), WOOD, Enum.Material.Wood)
piece("Taper", Vector3.new(1.1, 0.56, 0.56), CFrame.new(-0.3, 0, 0), WOOD, Enum.Material.Wood)
piece("Tape", Vector3.new(1.3, 0.47, 0.47), CFrame.new(-1.35, 0, 0), TAPE, Enum.Material.Fabric)
piece("Knob", Vector3.new(0.22, 0.64, 0.64), CFrame.new(-2.15, 0, 0), DARK_WOOD, Enum.Material.Wood)
piece("Stripe", Vector3.new(0.16, 0.76, 0.76), CFrame.new(0.3, 0, 0), STRIPE, Enum.Material.SmoothPlastic)
piece("Stripe2", Vector3.new(0.1, 0.76, 0.76), CFrame.new(0.55, 0, 0), STRIPE, Enum.Material.SmoothPlastic)
piece("Cap", Vector3.new(0.12, 0.62, 0.62), CFrame.new(2.22, 0, 0), DARK_WOOD, Enum.Material.Wood)

local server = Instance.new("Script")
server.Name = "BatServer"
server.Source = batSource
server.Parent = tool

tool.Parent = StarterPack
return ("Bat: %d parts, grip %s"):format(#tool:GetChildren() - 1, tostring(tool.Grip.Position))
