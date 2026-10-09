--[[
	ras-dev/lobby-models/tools/fetch_meshids.lua (2026-09-24) -- READ-ONLY, run in the edit DM of a place where
	InsertService:LoadAsset of Group Frenzy models works (the user-owned New Map Cucumber Game), while
	studio-shots/receive-b64.ps1 listens on 127.0.0.1:8768 (-Root = any folder; move the files into out/ after):
	  local f = loadstring(game:GetService("HttpService"):GetAsync("http://127.0.0.1:18781/fetch_meshids.lua"))()
	  return f({ Shop = <id>, Ascend = <id>, Gift = <id> })
	Loads each uploaded lobby Model (never parented), records every MeshPart {name, meshId, size, cf (raw, with
	the importer's 180-degree yaw still in it)} and POSTs <Key>.meshids.json. install_lobby.lua rebuilds the
	MeshParts from these ids in RAS - Dev, whose owner group cannot LoadAsset Group Frenzy models.
	Can outlast the MCP call timeout (~20 s); the files still arrive.
]]
return function(ids)
	local HttpService = game:GetService("HttpService")
	local InsertService = game:GetService("InsertService")
	local report = {}
	for key, id in pairs(ids) do
		local ok, a = pcall(InsertService.LoadAsset, InsertService, id)
		if not ok then
			table.insert(report, key .. " LoadAsset failed " .. tostring(a))
			continue
		end
		local parts = {}
		for _, d in ipairs(a:GetDescendants()) do
			if d:IsA("MeshPart") then
				local c = { d.CFrame:GetComponents() }
				for i, v in ipairs(c) do
					c[i] = math.round(v * 1e5) / 1e5
				end
				table.insert(parts, { name = d.Name:match("([^%.]+)$") or d.Name, meshId = d.MeshId,
					size = { d.Size.X, d.Size.Y, d.Size.Z }, cf = c })
			end
		end
		a:Destroy()
		local body = HttpService:JSONEncode({ key = key, assetId = id, parts = parts })
		local okp, r = pcall(HttpService.PostAsync, HttpService, "http://127.0.0.1:8768/" .. key .. ".meshids.json", body,
			Enum.HttpContentType.TextPlain)
		table.insert(report, key .. ": " .. #parts .. " meshparts, post " .. tostring(okp) .. " " .. tostring(r))
	end
	return table.concat(report, "\n")
end
