--[[
	timeskip/stage/install_timeskip_cards.lua (v2, user 2026-09-23: "put the values in here replacing +x labels, do
	not mention duration, do not mention timeskips. there were already existing templates, so delete the new ones")
	ONE execute_luau (edit mode). The EXISTING pack cards of StarterGui.CucumberMenus.ShopPanel (StrengthSection /
	CashSection, six each) become the time-skip products: card N sells the N-th duration of the ladder (1 min,
	5 min, 30 min, 5 h, 1 day, 1 week) and its Amount label shows ONLY the value the buyer would get ("+1.6M" /
	"+$2.93M", filled live by ShopController from Remotes.TimeSkipQuote) - no duration, no "time skip" wording.
	Attributes: TimeSkipSeconds + TimeSkipCurrency ("Strength" | "Cash"), the old StrengthAmount / CashAmount
	removed, ProductId kept (0 = "SOON"). The StrengthSkips* / CashSkips* sections of v1 are deleted.
	Idempotent. Returns a report.
]]
return function()
	local catalog = game.StarterGui.CucumberMenus.ShopPanel.Content.ContentPanel.Catalog
	local LADDER = {60, 300, 1800, 18000, 86400, 604800}
	local report = {}
	for _, name in ipairs({"StrengthSkipsHeader", "StrengthSkipsSection", "CashSkipsHeader", "CashSkipsSection"}) do
		local old = catalog:FindFirstChild(name)
		if old then
			old:Destroy()
			table.insert(report, name .. " deleted")
		end
	end
	local function convert(currency, amountAttr)
		local section = catalog[currency .. "Section"]
		local cards = {}
		for _, card in ipairs(section:GetChildren()) do
			if card:IsA("Frame") and (card:GetAttribute(amountAttr) or card:GetAttribute("TimeSkipSeconds")) then table.insert(cards, card) end
		end
		table.sort(cards, function(a, b) return a.LayoutOrder < b.LayoutOrder end)
		local converted = 0
		for i, card in ipairs(cards) do
			local seconds = LADDER[i]
			if not seconds then break end
			card:SetAttribute(amountAttr, nil)
			card:SetAttribute("TimeSkipSeconds", seconds)
			card:SetAttribute("TimeSkipCurrency", currency)
			if card:GetAttribute("ProductId") == nil then card:SetAttribute("ProductId", 0) end
			local amount = card:FindFirstChild("Amount")
			if amount then amount.Text = "..." end -- the live quote replaces it
			local stale = card:FindFirstChild("Quote")
			if stale then stale:Destroy() end
			converted += 1
		end
		table.insert(report, ("%s: %d cards -> time-skip values"):format(currency .. "Section", converted))
	end
	convert("Strength", "StrengthAmount")
	convert("Cash", "CashAmount")
	print("[install_timeskip_cards v2] " .. table.concat(report, " | "))
	return table.concat(report, "\n")
end
