--[[
	GymBoardsClient  (LocalScript, StarterPlayerScripts)
	Fills gym boards tagged "GymBoard" (attribute Board = "Upgrades", SurfaceGui "BoardGui" on their
	Face part, rows Rows/<UpgradeId>/{Sub, Button}) with this player's state from the GymBoardState
	remote and sends BUY presses through GymBoardAction. The SurfaceGuis live in the workspace; the
	edits here are local, so every player sees their own levels on the same board.
	(The QUESTS board and its CLAIM handling were removed on 2026-09-06. The bench upgrade is
	currently sold on the separate BenchUpgrade board, so this script only matters for boards that
	still carry the GymBoard tag.)
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local StateEvent = Remotes:WaitForChild("GymBoardState")
local ActionFunction = Remotes:WaitForChild("GymBoardAction")

local GREEN = Color3.fromRGB(78, 190, 78)
local GREY = Color3.fromRGB(95, 95, 100)

local state = nil
local boards = {} -- [model] = {Rows = {[id] = rowFrame}}

--..Toast: the game-wide notification style (ReplicatedStorage.Modules.Notify, user 2026-09-07)..--
local Notify = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Notify"))
local function Toast(text, color)
	Notify.Show(text, color)
end

--..Rendering..--
local function Render(model)
	local info = boards[model]
	if not (info and state) then return end
	for id, row in pairs(info.Rows) do
		local sub, button = row:FindFirstChild("Sub"), row:FindFirstChild("Button")
		local u = state.Upgrades and state.Upgrades[id]
		if u and sub and button then
			local effect = u.Effect and ("  ·  " .. u.Effect) or ""
			sub.Text = u.Cost and ("Lv. %d%s"):format(u.Level, effect) or ("Lv. %d  MAX%s"):format(u.Level, effect)
			button.Text = u.Cost and "BUY" or "MAX"
			button.BackgroundColor3 = (u.Cost and state.Cash >= u.Cost) and GREEN or GREY
			button.Active = u.Cost ~= nil
		end
	end
end

local function Press(model, id)
	if not boards[model] then return end
	local ok, message = ActionFunction:InvokeServer("Buy", id)
	Toast(tostring(message or (ok and "Done" or "Failed")), ok and Notify.COLORS.Success or Notify.COLORS.Error)
end

local function Watch(model)
	if boards[model] then return end
	task.spawn(function()
		--.. with StreamingEnabled the model can arrive before its GUI, so wait for the pieces
		if model:GetAttribute("Board") ~= "Upgrades" then return end
		local face = model:WaitForChild("Face", 30)
		local gui = face and face:WaitForChild("BoardGui", 30)
		local rows = gui and gui:WaitForChild("Rows", 30)
		if not rows then return end
		local info = {Rows = {}}
		boards[model] = info
		local function addRow(row)
			if not row:IsA("Frame") or info.Rows[row.Name] then return end
			info.Rows[row.Name] = row
			local button = row:WaitForChild("Button", 10)
			if button then
				button.Activated:Connect(function() Press(model, row.Name) end)
			end
			Render(model)
		end
		for _, row in ipairs(rows:GetChildren()) do addRow(row) end
		rows.ChildAdded:Connect(addRow)
		Render(model)
	end)
end

for _, m in ipairs(CollectionService:GetTagged("GymBoard")) do Watch(m) end
CollectionService:GetInstanceAddedSignal("GymBoard"):Connect(Watch)

StateEvent.OnClientEvent:Connect(function(newState)
	state = newState
	for model in pairs(boards) do Render(model) end
end)
-- ask for the state in case the profile loaded before this script
task.defer(function() pcall(function() ActionFunction:InvokeServer("State", "") end) end)
