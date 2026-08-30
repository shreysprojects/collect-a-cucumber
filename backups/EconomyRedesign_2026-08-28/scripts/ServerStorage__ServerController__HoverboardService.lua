--[[
	HoverboardService
	Mounts/dismounts ReplicatedStorage.Hoverboard on a player.

	Mounted: the board is welded just under the rider's feet, the rider floats
	HOVER_HEIGHT studs via Humanoid.HipHeight, and walkspeed is multiplied.
	The speed multiplier is NOT written here -- Dictionaries.Upgrades.SetWalkSpeed
	owns walkspeed (base + upgrade + Sprint gamepass), and reads the
	"Hoverboarding" attribute we set. That way any later recompute (buying an
	upgrade, the Sprint pass) keeps the board bonus instead of clobbering it.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Template = ReplicatedStorage:WaitForChild("Hoverboard")

local HOVER_HEIGHT = 3        -- studs the rider floats above the ground

local module = {}

local Boards = {}   -- [Player] = board MeshPart
local BaseHip = {}  -- [Player] = HipHeight before mounting

--.. The board is disabled inside private minigames: you cannot mount while in one,
--.. and entering one force-dismounts mid-ride. The portal Services own these
--.. attributes (set server-side), so this stays authoritative.
local MINIGAME_ATTRS = {
	"InStarterObby", "InSnowAvalanche", "InLavaRun", "InDesertHunt", "InVoidBloxout",
}

local function isInMinigame(Player)
	for _, attr in ipairs(MINIGAME_ATTRS) do
		if Player:GetAttribute(attr) then
			return true
		end
	end
	return false
end

local function refreshWalkSpeed(Player)
	pcall(function()
		require(script.Parent.Dictionaries.Upgrades).SetWalkSpeed(Player)
	end)
end

local function clear(Player)
	Boards[Player] = nil
	BaseHip[Player] = nil
	if Player.Parent then
		Player:SetAttribute("Hoverboarding", false)
	end
end

function module.IsRiding(Player)
	local board = Boards[Player]
	return board ~= nil and board.Parent ~= nil
end

function module.Dismount(Player)
	local board = Boards[Player]
	if board then
		board:Destroy()
	end

	local character = Player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and BaseHip[Player] then
		humanoid.HipHeight = BaseHip[Player]
	end

	clear(Player)
	refreshWalkSpeed(Player)
end

function module.Mount(Player)
	if module.IsRiding(Player) then return end
	if isInMinigame(Player) then return end   -- no board inside a minigame

	local character = Player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (humanoid and root) then return end
	if humanoid.Health <= 0 then return end

	local board = Template:Clone()
	board.Name = "Hoverboard"
	board.Anchored = false
	board.CanCollide = false
	board.CanQuery = false
	board.CanTouch = false
	board.Massless = true

	--.. Drop the board to the rider's foot plane. HipHeight is measured from the
	--.. bottom of the root part to the ground, so the feet sit that far below the
	--.. root centre. Raising HipHeight afterwards lifts the welded board with the
	--.. character, so it stays under the feet and both float together.
	local footDrop = humanoid.HipHeight + root.Size.Y / 2 + board.Size.Y / 2

	--.. The mesh's "Back" attachment is at +X, so the board's nose is -X. Rotate
	--.. -90 degrees about Y so that nose lines up with the character's LookVector.
	local weld = Instance.new("Weld")
	weld.Name = "HoverboardWeld"
	weld.Part0 = root
	weld.Part1 = board
	weld.C0 = CFrame.new(0, -footDrop, 0) * CFrame.Angles(0, math.rad(-90), 0)
	weld.Parent = board

	board.Parent = character
	Boards[Player] = board

	BaseHip[Player] = humanoid.HipHeight
	humanoid.HipHeight = humanoid.HipHeight + HOVER_HEIGHT

	Player:SetAttribute("Hoverboarding", true)
	refreshWalkSpeed(Player)
end

function module.Toggle(Player)
	if module.IsRiding(Player) then
		module.Dismount(Player)
	else
		module.Mount(Player)
	end
end

--.. The board is parented to the character, so death/respawn destroys it for us;
--.. we only need to drop the stale bookkeeping (and the attribute, so the next
--.. SetWalkSpeed doesn't keep granting the bonus).
local function watch(Player)
	Player.CharacterAdded:Connect(function()
		clear(Player)
	end)
	--.. entering any minigame force-dismounts the board mid-ride
	for _, attr in ipairs(MINIGAME_ATTRS) do
		Player:GetAttributeChangedSignal(attr):Connect(function()
			if Player:GetAttribute(attr) and module.IsRiding(Player) then
				module.Dismount(Player)
			end
		end)
	end
end
for _, p in ipairs(Players:GetPlayers()) do watch(p) end
Players.PlayerAdded:Connect(watch)
Players.PlayerRemoving:Connect(function(Player)
	Boards[Player] = nil
	BaseHip[Player] = nil
end)

-- ServerController automatically calls Initialize() on every non-blacklisted
-- service. HoverboardService wires itself when required, so this contract method
-- intentionally does nothing and prevents the loader from calling nil.
function module.Initialize()
	return
end

return module
