--[[
	Bookshelf  (ModuleScript, ServerStorage.FunBehaviours)  2026-09-24
	Server half of the BOOKSHELF (fun-builds/CONTRACT.md, package HomeDining). One "Read a book" prompt sits at
	the front of the shelf (Pivot_Read, chest height). Triggering it picks a random upright book (the parts named
	Book_NN - never the same one twice in a row) and tells every client with ctx:Fire("Read", {Book, T, Reader}):
	  * every client slides that book (and its spine band Band_NN) out 0.5 stud toward the front and back,
	    timed from T (server time) so everyone sees the same book move at the same moment
	  * the reader's client (Reader = UserId) pops a small toast card with a random silly cucumber fact / joke
	Anyone may read (nothing here can grief the owner). A short per-player cooldown stops prompt spam.
]]

--..Services..--
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--..Modules..--
local Kit = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("FunBuildKit"))

--..Config..--
local COOLDOWN = 1.5        -- seconds between reads for one player
local PROMPT_DISTANCE = 10
local BOOK_PREFIX = "Book_"

local B = {}
B.Keys = {"Bookshelf"}

function B.Server(model, ctx)
	local books = {}
	for _, part in ipairs(Kit.Parts(model, BOOK_PREFIX)) do table.insert(books, part.Name) end
	if #books == 0 then
		warn("[Bookshelf] no " .. BOOK_PREFIX .. "* parts on " .. model:GetFullName())
		return
	end

	--..Prompt on an invisible helper at the front of the shelf..--
	local hitbox = Kit.Hitbox(model)
	local spot = Kit.Pivot(model, "Read") or hitbox.Position
	local anchor = ctx:Part({
		Name = "BookshelfReadSpot",
		Size = Vector3.new(1, 1, 1),
		Transparency = 1,
		CFrame = CFrame.new(spot) * hitbox.CFrame.Rotation,
	})
	local prompt = ctx:Prompt(anchor, {
		Action = "Read a book",
		Object = "Bookshelf",
		Distance = PROMPT_DISTANCE,
		Name = "ReadPrompt",
	})

	--..Reading..--
	local lastRead = {} -- [player] = os.clock()
	local lastBook
	ctx:Connect(prompt.Triggered, function(player)
		if not ctx:Alive() then return end
		local t = os.clock()
		if lastRead[player] and t - lastRead[player] < COOLDOWN then return end
		lastRead[player] = t
		local name = books[math.random(1, #books)]
		if #books > 1 then
			while name == lastBook do name = books[math.random(1, #books)] end
		end
		lastBook = name
		ctx:Fire("Read", {Book = name, T = Kit.Now(), Reader = player.UserId})
	end)
	ctx:Connect(Players.PlayerRemoving, function(player) lastRead[player] = nil end)
end

return B
