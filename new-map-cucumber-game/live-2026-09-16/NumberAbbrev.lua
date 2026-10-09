--[[
	NumberAbbrev  (ModuleScript, ReplicatedStorage.Modules)
	Short number strings for the playerlist (LeaderstatsService) and the plot cucumber cards
	(PlacedCucumberCardClient):  1200000 -> "1.2M", 6300000 -> "6.3M", 5.4e12 -> "5.4T".
	One suffix per power of 1000 (short scale) all the way to centillion (10^303): vigintillion
	(10^63) prints "Vg", so nothing ever renders as a digit wall, "inf" or "nil".
	  NumberAbbrev.Abbrev(n)  -> string   3 significant digits at most: 1.23K / 12.3K / 123K;
	                                      below 1000 the number itself (999 / 12.5 / 0.54), never
	                                      more than 2 decimals; negatives keep their sign
	  NumberAbbrev.SUFFIXES   -> {[1] = "K" (10^3), [2] = "M", ... [21] = "Vg" (10^63), ... [101] = "Ce"}
]]
local NumberAbbrev = {}

--.. index = power of 1000
NumberAbbrev.SUFFIXES = {
	"K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", -- 10^3 .. 10^30
	"Dc", "UDc", "DDc", "TDc", "QaDc", "QiDc", "SxDc", "SpDc", "OcDc", "NoDc", -- decillion 10^33 .. 10^60
	"Vg", "UVg", "DVg", "TVg", "QaVg", "QiVg", "SxVg", "SpVg", "OcVg", "NoVg", -- vigintillion 10^63 .. 10^90
	"Tg", "UTg", "DTg", "TTg", "QaTg", "QiTg", "SxTg", "SpTg", "OcTg", "NoTg", -- trigintillion 10^93 .. 10^120
	"Qd", "UQd", "DQd", "TQd", "QaQd", "QiQd", "SxQd", "SpQd", "OcQd", "NoQd", -- quadragintillion 10^123 .. 10^150
	"Qq", "UQq", "DQq", "TQq", "QaQq", "QiQq", "SxQq", "SpQq", "OcQq", "NoQq", -- quinquagintillion 10^153 .. 10^180
	"Sg", "USg", "DSg", "TSg", "QaSg", "QiSg", "SxSg", "SpSg", "OcSg", "NoSg", -- sexagintillion 10^183 .. 10^210
	"St", "USt", "DSt", "TSt", "QaSt", "QiSt", "SxSt", "SpSt", "OcSt", "NoSt", -- septuagintillion 10^213 .. 10^240
	"Og", "UOg", "DOg", "TOg", "QaOg", "QiOg", "SxOg", "SpOg", "OcOg", "NoOg", -- octogintillion 10^243 .. 10^270
	"Ng", "UNg", "DNg", "TNg", "QaNg", "QiNg", "SxNg", "SpNg", "OcNg", "NoNg", -- nonagintillion 10^273 .. 10^300
	"Ce", -- centillion 10^303: a double tops out near 1.8e308, so this is the last stop
}
local SUFFIXES = NumberAbbrev.SUFFIXES

--.. "1.50" -> "1.5", "2.00" -> "2"
local function Trim(s)
	if s:find(".", 1, true) then
		s = s:gsub("0+$", "")
		s = s:gsub("%.$", "")
	end
	return s
end

--.. up to 3 significant digits
local function Mantissa(v)
	if v >= 100 then return tostring(math.floor(v + 0.5)) end
	if v >= 10 then return Trim(string.format("%.1f", v)) end
	return Trim(string.format("%.2f", v))
end

function NumberAbbrev.Abbrev(n)
	n = tonumber(n)
	if n == nil or n ~= n then return "0" end
	if n < 0 then return "-" .. NumberAbbrev.Abbrev(-n) end
	if n == math.huge then return "inf" end
	if n < 999.5 then return Mantissa(n) end
	local index = math.clamp(math.floor(math.log10(n) / 3), 1, #SUFFIXES)
	local v = n / 10 ^ (index * 3)
	if v >= 999.5 and index < #SUFFIXES then -- 999999 reads "1M", not "1000K"
		index += 1
		v = n / 10 ^ (index * 3)
	end
	return Mantissa(v) .. SUFFIXES[index]
end

return NumberAbbrev
