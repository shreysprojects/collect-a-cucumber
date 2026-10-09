--[[
	ShopVendorServer
	The Shopkeeper NPC at the new shop (Workspace.ShopNew.Vendor). Replaces
	the old walk-over Shop pad (Workspace.Points.Shop). Walk up -> "Talk"
	prompt -> dialog (ShopVendorClient); "Show me what you've got!" opens
	the Shop frame (pickaxes / ranks / upgrades).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

----------------------------------------------------------------------
-- Remotes
----------------------------------------------------------------------
local Remotes = ReplicatedStorage:FindFirstChild("VendorRemotes")
if not Remotes then
	Remotes = Instance.new("Folder")
	Remotes.Name = "VendorRemotes"
	Remotes.Parent = ReplicatedStorage
end
local OpenBuyShop = Remotes:FindFirstChild("OpenBuyShop")
if not OpenBuyShop then
	OpenBuyShop = Instance.new("RemoteEvent")
	OpenBuyShop.Name = "OpenBuyShop"
	OpenBuyShop.Parent = Remotes
end

----------------------------------------------------------------------
-- The vendor NPC
----------------------------------------------------------------------
local vendor = Workspace:WaitForChild("ShopNew"):WaitForChild("Vendor")
local promptPart = vendor:WaitForChild("HumanoidRootPart")

local prompt = promptPart:FindFirstChild("ShopVendorPrompt")
if not prompt then
	prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ShopVendorPrompt"
	prompt.Parent = promptPart
end
prompt.ActionText = "Talk"
prompt.ObjectText = "Shopkeeper"
prompt.MaxActivationDistance = 14
prompt.RequiresLineOfSight = false
prompt.Enabled = true
pcall(function()
	prompt.ClickablePrompt = true
end)
prompt.Triggered:Connect(function(player)
	OpenBuyShop:FireClient(player)
end)

----------------------------------------------------------------------
-- Idle animation (server-side so every client sees it)
----------------------------------------------------------------------
local ANIM_ID = "rbxassetid://507766388" -- default R15 idle (Roblox-owned)

local humanoid = vendor:FindFirstChildOfClass("Humanoid")
if humanoid then
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
		track:Stop(0)
	end
	local anim = Instance.new("Animation")
	anim.AnimationId = ANIM_ID
	local ok, track = pcall(function()
		return animator:LoadAnimation(anim)
	end)
	if ok and track then
		track.Looped = true
		track.Priority = Enum.AnimationPriority.Idle
		track:Play()
	end
end

print("[ShopVendorServer] Shopkeeper ready.")
