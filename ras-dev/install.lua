-- RAS - Dev installer. Run from execute_luau (edit mode) while
--   pets-remake/serve.ps1 -Port 8771 -Root <repo>/ras-dev/src
-- is serving the sources. Every file is compile-checked before anything is written.

local HS = game:GetService("HttpService")
local BASE = "http://127.0.0.1:8771/"

local function fetch(name)
	local src = HS:GetAsync(BASE .. name)
	src = src:gsub("\r\n", "\n")
	local fn, err = loadstring(src)
	if not fn then
		error(name .. " compile error: " .. tostring(err))
	end
	return src
end

local RS = game.ReplicatedStorage
local SS = game.ServerStorage
local clientModules = RS.Assets.Modules.Client.Functions.ClientFunctions.Modules

local fx = clientModules:FindFirstChild("CLIENT_SnowballFX")
if not fx then
	fx = Instance.new("ModuleScript")
	fx.Name = "CLIENT_SnowballFX"
	fx.Parent = clientModules
end

local targets = {
	{ "MountainConfig.lua", RS.Assets.Modules.Shared.MountainConfig },
	{ "PlaceMountainProps.lua", SS.Modules.PlaceMountainProps },
	{ "CLIENT_Snowball.lua", clientModules.CLIENT_Snowball },
	{ "CLIENT_SnowballFX.lua", fx },
	{ "SERV_Snowball.lua", SS.Modules.ServerFunctions.Modules.SERV_Snowball },
	{ "SERV_MountainGeneration.lua", SS.Modules.ServerFunctions.Modules.SERV_MountainGeneration },
	{ "ClientMain.lua", game.StarterPlayer.StarterPlayerScripts.ClientMain },
}

local sources = {}
for _, t in targets do
	sources[t[1]] = fetch(t[1])
end

local report = {}
for _, t in targets do
	t[2].Source = sources[t[1]]
	table.insert(report, string.format("%s -> %s (%d bytes)", t[1], t[2]:GetFullName(), #sources[t[1]]))
end

-- The run drops ~2,600 studs; the default -500 destroy height deleted the ball mid-ride.
workspace.FallenPartsDestroyHeight = -10000

-- Lobby overhead labels: size in studs so they scale with the world instead of staying
-- a fixed pixel size (which looks bigger the further away you stand).
local circles = SS.Assets.Storage.Maps.Attachments.StartPlatform.Circles
local resized = 0
for _, d in circles:GetDescendants() do
	if d:IsA("BillboardGui") then
		d.Size = UDim2.new(14, 0, 3.5, 0)
		for _, g in d:GetDescendants() do
			if g:IsA("TextLabel") then
				g.TextScaled = true
			end
		end
		resized += 1
	end
end
table.insert(report, "billboards resized: " .. resized)
table.insert(report, "FallenPartsDestroyHeight = " .. workspace.FallenPartsDestroyHeight)
return table.concat(report, "\n")
