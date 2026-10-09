--[[
	install_headbands.lua  (run once from execute_luau in edit mode)
	Loads the 12 group-owned headband Model assets, colours every MeshPart from the Blender
	manifest, corrects the FBX import's 180 deg yaw, and parks them in
	ReplicatedStorage.Assets.Headbands/<Name> for HeadbandService and the shop viewports.
]]
local InsertService = game:GetService("InsertService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SPEC = {
	{ name="Sweatband", display="Sweatband", tier=1, asset=135406941495201, parts={
		["Sweatband.Hem"]={"e2e2df","Fabric",0},
		["Sweatband.Stripe"]={"2f7fd4","Fabric",0},
		["Sweatband.Terry"]={"f2f2f0","Fabric",0},
	}},
	{ name="RedBandana", display="Red Bandana", tier=2, asset=109337279641130, parts={
		["RedBandana.Band"]={"c0322b","Fabric",0},
		["RedBandana.BandFolds"]={"d94a3d","Fabric",0},
		["RedBandana.Knot"]={"d94a3d","Fabric",0},
		["RedBandana.KnotShadow"]={"8f231d","Fabric",0},
		["RedBandana.LowerHem"]={"8f231d","Fabric",0},
	}},
	{ name="CamoBand", display="Camo Band", tier=3, asset=95267371351118, parts={
		["CamoBand.Band"]={"4a5d32","Fabric",0},
		["CamoBand.PatchesDark"]={"2f3a22","Fabric",0},
		["CamoBand.PatchesSage"]={"6b7a44","Fabric",0},
		["CamoBand.PatchesTan"]={"7a6a45","Fabric",0},
	}},
	{ name="CucumberBand", display="Cucumber Band", tier=4, asset=123363857042829, parts={
		["CucumberBand.Band"]={"5aa832","Plastic",0},
		["CucumberBand.Flesh"]={"d8f0b0","SmoothPlastic",0},
		["CucumberBand.Rinds"]={"2f7d2a","Plastic",0},
		["CucumberBand.Seeds"]={"9ec96a","SmoothPlastic",0},
	}},
	{ name="StrawBand", display="Straw Band", tier=5, asset=95619441328410, parts={
		["StrawBand.Spikes"]={"e8c87a","Sand",0},
		["StrawBand.Strands"]={"d9b063","Sand",0},
		["StrawBand.Weave"]={"b8873c","Sand",0},
	}},
	{ name="LeafCrown", display="Leaf Crown", tier=6, asset=125265700439885, parts={
		["LeafCrown.Buds"]={"e8c34a","Metal",0},
		["LeafCrown.LeavesDark"]={"2d7a28","Grass",0},
		["LeafCrown.LeavesMid"]={"3f9b3a","Grass",0},
		["LeafCrown.Vines"]={"4a5c2a","Wood",0},
	}},
	{ name="SteelBand", display="Steel Band", tier=7, asset=88912532867398, parts={
		["SteelBand.Band"]={"b8bec6","Metal",0},
		["SteelBand.EdgeRims"]={"d5dbe4","Metal",0},
		["SteelBand.Rivets"]={"8a9199","Metal",0},
	}},
	{ name="CactusBand", display="Cactus Band", tier=8, asset=83926581065449, parts={
		["CactusBand.Band"]={"5f9e3f","Fabric",0},
		["CactusBand.CactusHighlight"]={"6fb54d","SmoothPlastic",0},
		["CactusBand.CactusPads"]={"4a8c3a","Plastic",0},
		["CactusBand.FlowerCentres"]={"f5c542","SmoothPlastic",0},
		["CactusBand.Petals"]={"ffffff","SmoothPlastic",0},
		["CactusBand.Spines"]={"e8e0b0","SmoothPlastic",0},
	}},
	{ name="FrostBand", display="Frost Band", tier=9, asset=103647120567398, parts={
		["FrostBand.Band"]={"4a9fd8","Ice",0},
		["FrostBand.Crystals"]={"a8dcf5","Ice",0},
		["FrostBand.Frost"]={"dcf1ff","Ice",0},
		["FrostBand.Rim"]={"2f6fa8","Ice",0},
		["FrostBand.Snowflake"]={"e8f7ff","Neon",0},
	}},
	{ name="GoldBand", display="Gold Band", tier=10, asset=121759820382546, parts={
		["GoldBand.BandBody"]={"f0b429","Metal",0},
		["GoldBand.Boss"]={"ffd966","Foil",0},
		["GoldBand.BrightTrim"]={"ffd966","Foil",0},
		["GoldBand.DarkTrim"]={"d99a1a","Metal",0},
	}},
	{ name="LavaBand", display="Lava Band", tier=11, asset=140076870700761, parts={
		["LavaBand.Emblem"]={"1a1518","Slate",0},
		["LavaBand.HotCore"]={"ffb347","Neon",0},
		["LavaBand.Lava"]={"ff5a1a","Neon",0},
		["LavaBand.RockChips"]={"4a4045","Slate",0},
		["LavaBand.Rocks"]={"2a2529","Slate",0},
	}},
	{ name="ChampionBand", display="Champion Band", tier=12, asset=102910948083894, parts={
		["ChampionBand.Band"]={"f5c542","Foil",0},
		["ChampionBand.Cup"]={"f5c542","Foil",0},
		["ChampionBand.GoldTrim"]={"d99a1a","Metal",0},
		["ChampionBand.RedAccents"]={"c0322b","Fabric",0},
		["ChampionBand.Star"]={"ffffff","SmoothPlastic",0},
		["ChampionBand.Wings"]={"ffe08a","Foil",0},
	}},
}

local function hexColor(h)
	return Color3.fromRGB(tonumber(h:sub(1, 2), 16), tonumber(h:sub(3, 4), 16), tonumber(h:sub(5, 6), 16))
end

local assets = ReplicatedStorage:FindFirstChild("Assets") or Instance.new("Folder")
assets.Name = "Assets"
assets.Parent = ReplicatedStorage
local root = assets:FindFirstChild("Headbands")
if root then root:Destroy() end
root = Instance.new("Folder")
root.Name = "Headbands"
root.Parent = assets

local report = {}
for _, entry in ipairs(SPEC) do
	local ok, container = pcall(function() return InsertService:LoadAsset(entry.asset) end)
	if not ok then
		table.insert(report, entry.name .. " LOADFAIL " .. tostring(container))
	else
		local model
		for _, ch in ipairs(container:GetChildren()) do
			if ch:IsA("Model") then model = ch break end
		end
		if not model then
			table.insert(report, entry.name .. " NO MODEL")
			container:Destroy()
		else
			model.Name = entry.name
			--.. Blender exports -Z forward / Y up; Roblox's FBX importer lands it yawed 180 deg,
			--.. which puts the band's FRONT on +Z. Rotate about the origin to bring it to -Z,
			--.. the direction an R15 character faces.
			model:PivotTo(CFrame.Angles(0, math.pi, 0))
			--.. PivotTo leaves that 180 deg in the model PIVOT. HeadbandService places the clone
			--.. with band:PivotTo(CFrame.new(at)) - an UNROTATED CFrame - which would rotate the
			--.. geometry straight back and put the front on +Z again. Re-declare the pivot as
			--.. identity WITHOUT moving any part, so authored space == handle space.
			model.WorldPivot = CFrame.new()
			local missing, painted = {}, 0
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") then
					local spec = entry.parts[d.Name]
					if spec then
						d.Color = hexColor(spec[1])
						d.Material = Enum.Material[spec[2]] or Enum.Material.SmoothPlastic
						d.Transparency = spec[3]
						painted += 1
					else
						table.insert(missing, d.Name)
					end
					d.Anchored = true
					d.CanCollide = false
					d.CanQuery = false
					d.CanTouch = false
					d.Massless = true
				end
			end
			model:SetAttribute("Tier", entry.tier)
			model:SetAttribute("DisplayName", entry.display)
			model:SetAttribute("AssetId", entry.asset)
			model.Parent = root
			container:Destroy()
			local _, size = model:GetBoundingBox()
			table.insert(report, ("%-14s tier %-2d painted %d/%d  bbox %.2f x %.2f x %.2f%s")
				:format(entry.name, entry.tier, painted, painted + #missing, size.X, size.Y, size.Z,
					#missing > 0 and ("  MISSING: " .. table.concat(missing, ",")) or ""))
		end
	end
end
return report
