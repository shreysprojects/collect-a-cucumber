--[[
	S7_phone_measure_client.lua  (S7 integration, 2026-09-22) - paste into eval_client_runtime (client-1) while
	the Pets panel is open. Read-only: measures what the player really sees.
	  * every visible text in PetsPanel.Content (the label and all its ancestors visible, non-empty text): its
	    rendered text size in real GUI px, found the way TextScaled picks it - the largest size (0.25 px steps,
	    capped by the UITextSizeConstraint x the panel's scale) whose TextService bounds, in the label's own font,
	    fit the label's AbsoluteSize (wrapped labels wrap at their width); rich-text tags are stripped;
	  * every visible button's short side in real GUI px (the touch target), ClickShield excluded;
	  * a few layout facts (Compact, scale, which pages / rows show).
	Returns one summary string; the smallest texts / targets come first.
]]
local TextService = game:GetService("TextService")
local pg = game:GetService("Players").LocalPlayer.PlayerGui
local panel = pg.CucumberMenus.PetsPanel
local content = panel.Content
local scale = panel.ResponsiveScale.Scale

local function shown(g)
	local a = g
	while a and a ~= content do
		if a:IsA("GuiObject") and not a.Visible then return false end
		a = a.Parent
	end
	return content.Visible
end
local function plain(text) return (text:gsub("<[^>]->", "")) end
local function fontEnum(label)
	local family = label.FontFace.Family
	if family:find("Fredoka") then return Enum.Font.FredokaOne end
	if family:find("BuilderSans") then return Enum.Font.BuilderSansExtraBold end
	return label.Font
end
local function rendered(label)
	local text = label.RichText and plain(label.Text) or label.Text
	local w, h = label.AbsoluteSize.X, label.AbsoluteSize.Y
	local font = fontEnum(label)
	local cap = label:FindFirstChildOfClass("UITextSizeConstraint")
	local maxSize = label.TextScaled and (cap and cap.MaxTextSize * scale or 100) or label.TextSize * scale
	if not label.TextScaled then return maxSize end
	local best = 0
	local s = math.min(maxSize, h)
	while s >= 1 do
		local bounds = TextService:GetTextSize(text, s, font, Vector2.new(label.TextWrapped and w or 1e6, 1e6))
		if bounds.X <= w + 0.5 and bounds.Y <= h + 0.5 then best = s break end
		s -= 0.25
	end
	if cap and best < cap.MinTextSize * scale then best = cap.MinTextSize * scale end
	return best
end

local texts, buttons = {}, {}
for _, d in ipairs(content:GetDescendants()) do
	if (d:IsA("TextLabel") or d:IsA("TextButton")) and d.Text ~= "" and shown(d) and d.AbsoluteSize.X > 1 then
		table.insert(texts, {Name = d.Name .. (d.Parent and d.Parent ~= content and ("<" .. d.Parent.Name) or ""), Size = rendered(d), Text = (d.RichText and plain(d.Text) or d.Text):sub(1, 28)})
	end
	if d:IsA("GuiButton") and d.Name ~= "ClickShield" and shown(d) then
		table.insert(buttons, {Name = d.Name, Short = math.min(d.AbsoluteSize.X, d.AbsoluteSize.Y), W = d.AbsoluteSize.X, H = d.AbsoluteSize.Y})
	end
end
table.sort(texts, function(a, b) return a.Size < b.Size end)
table.sort(buttons, function(a, b) return a.Short < b.Short end)
local tOut, bOut = {}, {}
for i = 1, math.min(#texts, 14) do table.insert(tOut, string.format("%.2f %s [%s]", texts[i].Size, texts[i].Name, texts[i].Text)) end
local seen = {}
for _, b in ipairs(buttons) do
	local key = b.Name:match("^Pet_") and "PetCard" or b.Name
	if not seen[key] then seen[key] = true table.insert(bOut, string.format("%s %.1fx%.1f", key, b.W, b.H)) end
end
local c = content
return string.format("scale %.4f Compact %s | slotRow %s tabs(SortIncome) %s SortCycle %s grid %s details %s back %s | %d texts, smallest: %s || %d buttons by short side: %s",
	scale, tostring(panel:GetAttribute("Compact")), tostring(shown(c.SlotRow)), tostring(shown(c.Toolbar.SortIncome)), tostring(shown(c.Toolbar.SortCycle)),
	tostring(shown(c.PetGrid)), tostring(shown(c.Details)), tostring(shown(c.Details.BackButton)), #texts, table.concat(tOut, "; "), #buttons, table.concat(bOut, "; "))
