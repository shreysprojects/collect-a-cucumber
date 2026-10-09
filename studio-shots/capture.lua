-- Studio viewport screenshot -> PNG file on disk, without any desktop tools.
-- Run through the chrrxs execute_luau (edit DM of the place you want to shoot) while
-- studio-shots/receive-b64.ps1 listens on 127.0.0.1:8768; afterwards run
-- studio-shots/decode.ps1 (turns <name>_<w>x<h>.rgba.b64 into <name>.png via System.Drawing).
-- ~1 s per shot at 1301x611. Frame the camera (CFrame/Focus only, never CameraType) and
-- task.wait(0.5) before calling capture(name) so the new frame has rendered.
-- StudioCaptureService (PNG output) reports CanCaptureScreenshot()=false in a second,
-- non-active place, so this uses the CaptureService + EditableImage path the MCP plugin
-- itself falls back to.
local HttpService = game:GetService("HttpService")
local CaptureService = game:GetService("CaptureService")
local AssetService = game:GetService("AssetService")

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local lut = {}
for i = 1, 64 do lut[i - 1] = string.byte(B64, i) end
local function b64(buf)
	local len = buffer.len(buf)
	local out = buffer.create(math.ceil(len / 3) * 4)
	local si, di = 0, 0
	local full = len - len % 3
	while si < full do
		local b0, b1, b2 = buffer.readu8(buf, si), buffer.readu8(buf, si + 1), buffer.readu8(buf, si + 2)
		buffer.writeu8(out, di, lut[bit32.rshift(b0, 2)])
		buffer.writeu8(out, di + 1, lut[bit32.bor(bit32.lshift(bit32.band(b0, 3), 4), bit32.rshift(b1, 4))])
		buffer.writeu8(out, di + 2, lut[bit32.bor(bit32.lshift(bit32.band(b1, 15), 2), bit32.rshift(b2, 6))])
		buffer.writeu8(out, di + 3, lut[bit32.band(b2, 63)])
		si += 3; di += 4
	end
	local rem = len - full
	if rem == 2 then
		local b0, b1 = buffer.readu8(buf, si), buffer.readu8(buf, si + 1)
		buffer.writeu8(out, di, lut[bit32.rshift(b0, 2)])
		buffer.writeu8(out, di + 1, lut[bit32.bor(bit32.lshift(bit32.band(b0, 3), 4), bit32.rshift(b1, 4))])
		buffer.writeu8(out, di + 2, lut[bit32.lshift(bit32.band(b1, 15), 2)])
		buffer.writeu8(out, di + 3, 61)
	elseif rem == 1 then
		local b0 = buffer.readu8(buf, si)
		buffer.writeu8(out, di, lut[bit32.rshift(b0, 2)])
		buffer.writeu8(out, di + 1, lut[bit32.lshift(bit32.band(b0, 3), 4)])
		buffer.writeu8(out, di + 2, 61); buffer.writeu8(out, di + 3, 61)
	end
	return buffer.tostring(out)
end

-- Captures the current viewport and POSTs it as <name>_<w>x<h>.rgba.b64 (chunked).
local function capture(name)
	local contentId
	CaptureService:CaptureScreenshot(function(id) contentId = id end)
	local t1 = os.clock()
	while contentId == nil do
		if os.clock() - t1 > 8 then return "callback never fired (window minimized / not rendering?)" end
		task.wait(0.05)
	end
	local okImg, img = pcall(function() return AssetService:CreateEditableImageAsync(Content.fromUri(contentId)) end)
	if not okImg then return "CreateEditableImageAsync failed: " .. tostring(img) end
	local W, H = math.floor(img.Size.X), math.floor(img.Size.Y)
	local TILE = 1024
	local full = buffer.create(W * H * 4)
	local rowBytes = W * 4
	for ty = 0, H - 1, TILE do
		local th = math.min(TILE, H - ty)
		for tx = 0, W - 1, TILE do
			local tw = math.min(TILE, W - tx)
			local tile = img:ReadPixelsBuffer(Vector2.new(tx, ty), Vector2.new(tw, th))
			local trb = tw * 4
			for row = 0, th - 1 do buffer.copy(full, (ty + row) * rowBytes + tx * 4, tile, row * trb, trb) end
		end
	end
	img:Destroy()
	local enc = b64(full)
	local CH = 700000
	local file = ("%s_%dx%d.rgba.b64"):format(name, W, H)
	local i, first, total = 1, true, 0
	while i <= #enc do
		local chunk = string.sub(enc, i, i + CH - 1)
		local url = "http://127.0.0.1:8768/" .. file .. (first and "" or "?append=1")
		local ok, r = pcall(HttpService.PostAsync, HttpService, url, chunk, Enum.HttpContentType.TextPlain)
		if not ok then return "POST failed: " .. tostring(r) end
		total += #chunk
		first = false
		i += CH
	end
	return ("%dx%d posted %d chars"):format(W, H, total)
end

return capture
