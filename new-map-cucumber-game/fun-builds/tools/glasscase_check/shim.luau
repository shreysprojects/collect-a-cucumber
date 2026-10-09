-- Minimal Roblox datatype shim for running the behaviour modules' pure-geometry functions in the Luau CLI.
local VecMT = {}
local function vnew(x, y, z)
	return setmetatable({X = x or 0, Y = y or 0, Z = z or 0}, VecMT)
end
local function isvec(v) return getmetatable(v) == VecMT end
VecMT.__index = function(v, k)
	if k == "Magnitude" then
		return math.sqrt(rawget(v, "X") ^ 2 + rawget(v, "Y") ^ 2 + rawget(v, "Z") ^ 2)
	elseif k == "Unit" then
		local m = math.sqrt(rawget(v, "X") ^ 2 + rawget(v, "Y") ^ 2 + rawget(v, "Z") ^ 2)
		return vnew(rawget(v, "X") / m, rawget(v, "Y") / m, rawget(v, "Z") / m)
	elseif k == "Dot" then
		return function(a, b) return a.X * b.X + a.Y * b.Y + a.Z * b.Z end
	elseif k == "Cross" then
		return function(a, b) return vnew(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X) end
	end
	return nil
end
VecMT.__add = function(a, b) return vnew(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
VecMT.__sub = function(a, b) return vnew(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
VecMT.__unm = function(a) return vnew(-a.X, -a.Y, -a.Z) end
VecMT.__mul = function(a, b)
	if type(a) == "number" then return vnew(a * b.X, a * b.Y, a * b.Z) end
	if type(b) == "number" then return vnew(a.X * b, a.Y * b, a.Z * b) end
	return vnew(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
VecMT.__div = function(a, b)
	if type(b) == "number" then return vnew(a.X / b, a.Y / b, a.Z / b) end
	return vnew(a.X / b.X, a.Y / b.Y, a.Z / b.Z)
end
Vector3 = {new = vnew, zero = vnew(0, 0, 0), one = vnew(1, 1, 1), xAxis = vnew(1, 0, 0), yAxis = vnew(0, 1, 0), zAxis = vnew(0, 0, 1)}

local CFMT = {}
local I = {{1, 0, 0}, {0, 1, 0}, {0, 0, 1}}
local function cfnew(p, r) return setmetatable({p = p, r = r}, CFMT) end
local function matmul(A, B)
	local C = {}
	for i = 1, 3 do
		C[i] = {}
		for j = 1, 3 do
			C[i][j] = A[i][1] * B[1][j] + A[i][2] * B[2][j] + A[i][3] * B[3][j]
		end
	end
	return C
end
local function rot(R, v)
	return vnew(R[1][1] * v.X + R[1][2] * v.Y + R[1][3] * v.Z, R[2][1] * v.X + R[2][2] * v.Y + R[2][3] * v.Z, R[3][1] * v.X + R[3][2] * v.Y + R[3][3] * v.Z)
end
CFMT.__index = function(cf, k)
	if k == "Position" then return rawget(cf, "p") end
	if k == "Rotation" then return cfnew(vnew(0, 0, 0), rawget(cf, "r")) end
	return nil
end
CFMT.__mul = function(a, b)
	if getmetatable(b) == CFMT then return cfnew(a.p + rot(a.r, b.p), matmul(a.r, b.r)) end
	return a.p + rot(a.r, b)
end
CFMT.__add = function(a, v) return cfnew(a.p + v, a.r) end
CFrame = {}
CFrame.new = function(a, b, c)
	if a == nil then return cfnew(vnew(0, 0, 0), I) end
	if type(a) == "number" then return cfnew(vnew(a, b, c), I) end
	return cfnew(a, I)
end
CFrame.identity = CFrame.new()
CFrame.Angles = function(x, y, z)
	local cx, sx, cy, sy, cz, sz = math.cos(x), math.sin(x), math.cos(y), math.sin(y), math.cos(z), math.sin(z)
	local Rx = {{1, 0, 0}, {0, cx, -sx}, {0, sx, cx}}
	local Ry = {{cy, 0, sy}, {0, 1, 0}, {-sy, 0, cy}}
	local Rz = {{cz, -sz, 0}, {sz, cz, 0}, {0, 0, 1}}
	return cfnew(vnew(0, 0, 0), matmul(matmul(Rx, Ry), Rz))
end
CFrame.fromMatrix = function(pos, vx, vy, vz)
	vz = vz or vx:Cross(vy).Unit
	return cfnew(pos, {{vx.X, vy.X, vz.X}, {vx.Y, vy.Y, vz.Y}, {vx.Z, vy.Z, vz.Z}})
end

local C3MT = {}
C3MT.__index = function(c, k)
	if k == "Lerp" then
		return function(a, b, t) return setmetatable({R = a.R + (b.R - a.R) * t, G = a.G + (b.G - a.G) * t, B = a.B + (b.B - a.B) * t}, C3MT) end
	end
	return nil
end
Color3 = {
	new = function(r, g, b) return setmetatable({R = r, G = g, B = b}, C3MT) end,
	fromRGB = function(r, g, b) return setmetatable({R = r / 255, G = g / 255, B = b / 255}, C3MT) end,
}

function HEX(c)
	local function h(x) return string.format("%02x", math.clamp(math.floor(x * 255 + 0.5), 0, 255)) end
	return h(c.R) .. h(c.G) .. h(c.B)
end
function CFJSON(cf)
	local p, r = cf.p, cf.r
	local t = {p.X, p.Y, p.Z, r[1][1], r[1][2], r[1][3], r[2][1], r[2][2], r[2][3], r[3][1], r[3][2], r[3][3]}
	for i, v in ipairs(t) do t[i] = string.format("%.5f", v) end
	return "[" .. table.concat(t, ",") .. "]"
end
function VJSON(v) return string.format("[%.5f,%.5f,%.5f]", v.X, v.Y, v.Z) end

-- Roblox globals the module top-levels touch
local stub = {}
stub.WaitForChild = function() return stub end
stub.FindFirstChild = function() return stub end
game = {GetService = function() return stub end}
workspace = stub
STUB_REQUIRE = function() return {Sfx = {}} end
