--..Services..--


--..Modules..--
local Data = require(script.Data)

--..Variables..--
local Suffixes = Data.Suffixes

local module = {}

--..Functions..--

--.. Rounds Number -> Returns Number
function module.RoundNumber(x, mult)
    if typeof(mult) == "number" then else
        mult = 1
    end
    return math.round(x / mult) * mult
end

--.. Suffix Number -> Returns String
function module.SuffixNumber(Number)
    local Number = tonumber(Number)
    for i = 1, #Suffixes do
        if Number < 10^(i * 3) then
            return math.floor(Number/((10^((i - 1)*3))/100))/(100)..Suffixes[i]
        end
    end
end

--.. Number Into {Hours Minutes Seconds} -> Returns String
function module.ToHMS(Seconds)
    return string.format("%2ih %2im %2is", Seconds/60^2, Seconds/60%60, Seconds%60)
end

--.. Number Into {Minutes Seconds} -> Returns String
function module.ToMS(Seconds)
    return string.format("%2im %2is", Seconds/60%60, Seconds%60)
end

--.. Adds a comma -> Returns String
function module.Comma(Number)
    local left,num,right = string.match(Number,'^([^%d]*%d)(%d*)(.-)$')
    return left..(num:reverse():gsub('(%d%d%d)','%1,'):reverse())..right
end

--.. Expands Number -> Returns Number
function module.ConvertOrderedDataToNumber(OrderedData)
    return math.floor(OrderedData ~= 0 and (1.0000001^OrderedData) or 0)
end

--.. Condenses Number -> Returns Number
function module.ConvertNumberToOrderedData(Number)
    return Number ~= 0 and math.floor(math.log(Number) / math.log(1.0000001)) or 0
end

--.. Number To 1st, 2nd, 3rd -> Returns String
function module.AddIdentifier(Number)
    local FormattedNumber = ""
    if (Number % 10 == 1 and Number ~= 11) then 
        FormattedNumber = Number .. "st" 
    elseif (Number % 10 == 2 and Number ~= 12) then 
        FormattedNumber = Number .. "nd" 
    elseif (Number % 10 == 3 and Number ~= 13) then
        FormattedNumber = Number .. "rd" 
    else 
        FormattedNumber = Number .."th" 
    end 

    return tostring(FormattedNumber)
end

--.. Gets Time -> Returns {year, month, day, hour, minute}
function module.GetTime()
    local date = os.date("*t", os.time())
    return {month = date["month"], day = date["day"], year = date["year"], hour = date["hour"], minute = date["min"]}
end

--.. Hour and Minute -> Returns String
function module.ConvertToTwelve(Hour, Min)
    local Difference = 0;
    local _m = ""

    if Hour > 12 then
        Difference = Hour - 12
        _m = "pm"
    else
        Difference = Hour
        _m = "am"
    end

    return string.format("%s:%s %s", Difference, Min, _m)
end

--.. Hour -> Returns Number, String
local function CovertToTwelve(Hour)
    if Hour > 12 then
        local Difference = Hour - 12
        return Difference, "pm"
    else
        return Hour, "am"
    end
end

return module
