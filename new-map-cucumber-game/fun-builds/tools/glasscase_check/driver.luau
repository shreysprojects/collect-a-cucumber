local out = {}
table.insert(out, '{"trophies": [')
for d = 1, GC.DESIGN_COUNT do
	local specs = GC.TrophySpecs(d)
	local parts = {}
	for _, s in ipairs(specs) do
		local look = GC.LOOKS[s.Look]
		table.insert(parts, string.format('{"shape":"%s","size":%s,"cf":%s,"color":"%s","material":"%s","transparency":%s,"reflectance":%s,"look":"%s"}',
			s.Shape, VJSON(s.Size), CFJSON(s.CF), HEX(look.Color), look.Material, tostring(look.Transparency or 0), tostring(look.Reflectance or 0), s.Look))
	end
	table.insert(out, (d > 1 and "," or "") .. "[" .. table.concat(parts, ",") .. "]")
end
table.insert(out, '], "neon": {')
for i, letter in ipairs({"B", "C"}) do
	local L = NS.Layout(letter)
	local balls = {}
	for _, b in ipairs(L.Balls) do
		table.insert(balls, string.format('{"pos":%s,"d":%.3f,"group":%d}', VJSON(b.Pos), b.D, b.Group))
	end
	local chev = {}
	for _, c in ipairs(L.Chevrons) do
		local arms = {}
		for _, a in ipairs(c.Arms) do
			table.insert(arms, string.format('{"cf":%s,"size":%s}', CFJSON(a.CF), VJSON(a.Size)))
		end
		table.insert(chev, "[" .. table.concat(arms, ",") .. "]")
	end
	table.insert(out, (i > 1 and "," or "") .. string.format('"%s":{"balls":[%s],"chevrons":[%s]}', letter, table.concat(balls, ","), table.concat(chev, ",")))
end
table.insert(out, "}}")
print(table.concat(out))
