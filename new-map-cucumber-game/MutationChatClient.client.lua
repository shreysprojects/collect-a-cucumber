--[[
	MutationChatClient  (LocalScript, StarterPlayerScripts)
	Chat line for every mutated cucumber the server spawns (Remotes.MutationAnnounce,
	fired by CucumberSpawner):
	    [NEON + FROZEN] Golden Vined Cucumber spawned in Desert!
	Mutation words are coloured with their mutation colour, the material with its material
	colour, the biome with CucumberValues' zone colour (TextChatService RichText on the
	RBXGeneral channel). 2026-09-06.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Mutations = require(Modules:WaitForChild("CucumberMutations"))
local CucumberValues = require(Modules:WaitForChild("CucumberValues"))
local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("MutationAnnounce")

local function channel()
	local channels = TextChatService:FindFirstChild("TextChannels") or TextChatService:WaitForChild("TextChannels", 10)
	return channels and (channels:FindFirstChild("RBXGeneral") or channels:WaitForChild("RBXGeneral", 10))
end

remote.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then return end
	local list = Mutations.Parse(payload.Mutations)
	if #list == 0 then return end
	local zone = tostring(payload.Zone or "?")
	local text = Mutations.AnnouncementRichText(tostring(payload.TypeName or "Cucumber"), payload.Material, list, zone, CucumberValues.ZoneColor(zone))
	local general = channel()
	if general then
		general:DisplaySystemMessage(text)
	end
end)
