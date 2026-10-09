--[[
	PlotUpgrades  (ModuleScript, ReplicatedStorage.Modules)
	Shared config for the plot size upgrade system.
	  server: ServerScriptService.PlotUpgradeService  (resizes plots, sells levels, stands the boards)
	  client: StarterPlayerScripts.PlotUpgradeClient  (fills the PlotUpgrade boards, sends BUY)

	Level 0 is the starting plot, level MAX the biggest. Width is the plot's Size.X (along the
	row of plots), Depth its Size.Z (front edge -> back wall). Cost = Cash to buy the NEXT level.
]]
local PlotUpgrades = {}

PlotUpgrades.LEVELS = {
	--.. 2026-09-23 economy: Cost = Cash to reach the NEXT level: 400 / 4K / 60K / 1M / 15M / 250M (was 250 .. 8000)
	[0] = {Width = 50, Depth = 60, Cost = 400},
	[1] = {Width = 54, Depth = 64, Cost = 4000},
	[2] = {Width = 58, Depth = 68, Cost = 60000},
	[3] = {Width = 62, Depth = 72, Cost = 1000000},
	[4] = {Width = 65, Depth = 76, Cost = 15000000},
	[5] = {Width = 68, Depth = 80, Cost = 250000000},
	[6] = {Width = 70, Depth = 85, Cost = nil}, -- max: nothing left to buy
}
PlotUpgrades.MAX = 6

function PlotUpgrades.Clamp(level)
	level = math.floor(tonumber(level) or 0)
	return math.clamp(level, 0, PlotUpgrades.MAX)
end

--.. width, depth in studs for a level
function PlotUpgrades.Size(level)
	local def = PlotUpgrades.LEVELS[PlotUpgrades.Clamp(level)]
	return def.Width, def.Depth
end

--.. Cash to go from this level to the next, nil at max
function PlotUpgrades.Cost(level)
	return PlotUpgrades.LEVELS[PlotUpgrades.Clamp(level)].Cost
end

--.. 15750 -> "15,750"
function PlotUpgrades.Format(n)
	local s = tostring(math.floor(tonumber(n) or 0))
	local formatted = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (formatted:gsub("^,", ""))
end

--.. 250 -> "250", 1000 -> "1K", 1500 -> "1.5K", 2000000 -> "2M", 500000000000 -> "500B"
function PlotUpgrades.Abbrev(n)
	n = tonumber(n) or 0
	local units = {{1e12, "T"}, {1e9, "B"}, {1e6, "M"}, {1e3, "K"}}
	for _, u in ipairs(units) do
		if n >= u[1] then
			local v = n / u[1]
			local s = (v >= 100 or v == math.floor(v)) and tostring(math.floor(v + 0.5)) or string.format("%.1f", v):gsub("%.0$", "")
			return s .. u[2]
		end
	end
	return tostring(math.floor(n + 0.5))
end

return PlotUpgrades
