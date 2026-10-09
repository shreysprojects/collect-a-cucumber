--[[
	S7_clickshield_check.lua  (S7 integration fix, 2026-09-22) - read-only for the DataModel.
	The builder's Content.ClickShield (a transparent, non-selectable TextButton on the body's rect, ZIndex 1)
	keeps clicks on the panel's art / text from falling through to MenuController's Dimmer. Checks, on an
	UNPARENTED clone built with the current builder (WP-MENU_builder_embed.lua, module mode) and on the live
	StarterGui panel when it has been built: class and props, rect = Body rect, below every other Content
	child, not a PetView / MenuController target (no Compact_ attributes, no Label), and a second build
	leaves exactly one. The live click behaviour is checked in the S7 playtest.
	Run from an edit-peer execute_luau:
	  return loadstring(game:GetService("HttpService"):GetAsync("http://127.0.0.1:8795/S7_clickshield_check.lua"))()
]]
local HttpService = game:GetService("HttpService")
local StarterGui = game:GetService("StarterGui")

local pass, fail, failures = 0, 0, {}
local function check(name, condition, detail)
	if condition then
		pass += 1
	else
		fail += 1
		table.insert(failures, name .. (detail ~= nil and (" [" .. tostring(detail) .. "]") or ""))
	end
end

local function inspect(label, content)
	local shield = content:FindFirstChild("ClickShield")
	check(label .. ": ClickShield exists", shield ~= nil)
	if not shield then return end
	local count = 0
	for _, child in ipairs(content:GetChildren()) do if child.Name == "ClickShield" then count += 1 end end
	check(label .. ": exactly one", count == 1, count)
	check(label .. ": TextButton", shield:IsA("TextButton"), shield.ClassName)
	check(label .. ": transparent, no text", shield.BackgroundTransparency == 1 and shield.Text == "" and shield.AutoButtonColor == false)
	check(label .. ": not selectable (gamepad never lands on it)", shield.Selectable == false)
	check(label .. ": Active + Visible", shield.Active == true and shield.Visible == true)
	local body = content:FindFirstChild("Body")
	check(label .. ": rect = Body rect", body ~= nil and shield.Size == body.Size and shield.Position == body.Position and shield.AnchorPoint == body.AnchorPoint,
		body and (tostring(shield.Size) .. " vs " .. tostring(body.Size)))
	local lowest = true
	for _, child in ipairs(content:GetChildren()) do
		if child ~= shield and child:IsA("GuiObject") and child.ZIndex <= shield.ZIndex then lowest = false end
	end
	check(label .. ": below every other Content child", lowest and shield.ZIndex == 1)
	local attrs = 0
	for name in pairs(shield:GetAttributes()) do attrs += 1 end
	check(label .. ": no attributes / children", attrs == 0 and #shield:GetChildren() == 0)
end

local Builder = loadstring(loadstring(HttpService:GetAsync("http://127.0.0.1:8795/WP-MENU_builder_embed.lua"))())({Mode = "module"})
local menus = StarterGui.CucumberMenus:Clone()
local ok, err = pcall(function()
	local existing = menus:FindFirstChild("PetsPanel")
	if existing then existing:Destroy() end
	Builder.BuildPanel(menus, menus.IndexPanel.Content)
	inspect("fresh build", menus.PetsPanel.Content)
	Builder.BuildPanel(menus, menus.IndexPanel.Content)
	inspect("rebuild", menus.PetsPanel.Content)
	local live = StarterGui.CucumberMenus:FindFirstChild("PetsPanel")
	if live and live.Content:FindFirstChild("ClickShield") then inspect("live StarterGui", live.Content) end
end)
menus:Destroy()
if not ok then fail += 1 table.insert(failures, "error: " .. tostring(err)) end
return ("S7 clickshield check: PASS %d / FAIL %d%s"):format(pass, fail, #failures > 0 and (": " .. table.concat(failures, "; ")) or "")
