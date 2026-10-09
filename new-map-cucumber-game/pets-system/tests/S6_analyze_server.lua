--[[
	S6_analyze_server.lua  (pets-system/tests, S6 integration agent, 2026-09-22)
	Summarises _G.S6 (S6_recorder_server.lua) for a time window. PASTE into eval_server_runtime with one line in
	front:  local S6_OPTS = {From = <s>, To = <s>, Detail = true|nil}   (times = the recorder's S.Now() clock)
	Returns one summary string: shot validity (tag / folder / owner / shaded / underground), priority invariant
	(the target's priority equals the best same-owner priority in the pet's range), per-pet cadence vs the
	nominal ShotInterval, health drops per kind and per zombie (pet part = the shots' Damage on that model in
	the window; the rest came from somewhere else), turret tracers and the 12-damage hits that share their
	frame, and the PetCombatService diagnostics delta.
]]
local opts = S6_OPTS or {}
local S = _G.S6
if not S then return "no recorder" end
local SS = game:GetService("ServerStorage")
local PetService = require(SS.PetService)
local Combat = require(SS.PetCombatService)
local from, to = opts.From or -math.huge, opts.To or math.huge
local function inW(t) return t >= from and t <= to end
local out = {}
local function add(s) table.insert(out, s) end
local function f(x) return type(x) == "number" and ("%.3f"):format(x) or tostring(x) end

local nominal, rarity = {}, {}
for _, p in ipairs(PetService.GetActivePets()) do
	nominal[p.PetId] = p.Stats and p.Stats.ShotInterval
	rarity[p.PetId] = (p.Model and p.Model.Name or "?") .. "/" .. tostring(p.Stats and p.Stats.Rarity)
end

local shots, byUid, byVar, bad, mism, sh, ug, viol, gone, near, prio = {}, {}, {}, 0, 0, 0, 0, 0, 0, 0, {0, 0, 0}
local violList = {}
for _, r in ipairs(S.Shots) do
	if inW(r.t) then
		table.insert(shots, r)
		byUid[tostring(r.uid)] = (byUid[tostring(r.uid)] or 0) + 1
		byVar[tostring(r.var)] = (byVar[tostring(r.var)] or 0) + 1
		if not (r.tag and r.inFolder) then bad += 1 end
		if r.zo ~= r.uid then mism += 1 end
		if r.sh then sh += 1 end
		if r.ug then ug += 1 end
		if r.tp == nil then gone += 1 else
			prio[r.tp] += 1
			if r.tp < r.maxP then
				viol += 1
				if #violList < 5 then table.insert(violList, ("t%.2f %s tp%d max%d d%s range%s"):format(r.t, tostring(r.id):sub(1, 8), r.tp, r.maxP, f(r.d), tostring(r.range))) end
			end
			if r.nearest then near += 1 end
		end
	end
end
local function kv(t) local l = {} for k, v in pairs(t) do table.insert(l, k .. "=" .. v) end table.sort(l) return table.concat(l, " ") end
add(("window %s..%s: %d shots [uid %s] [targets %s]"):format(f(from), f(to), #shots, kv(byUid), kv(byVar)))
add(("  not-a-raid-zombie %d, owner mismatch %d, shaded %d, underground %d, target gone after the hit %d"):format(bad, mism, sh, ug, gone))
add(("  target priority: carry %d / grapple %d / plain %d; priority violations %d %s; nearest in range %d of %d"):format(prio[3], prio[2], prio[1], viol, table.concat(violList, "; "), near, #shots - gone))

-- per pet cadence
local per = {}
for _, r in ipairs(shots) do
	per[r.id] = per[r.id] or {}
	table.insert(per[r.id], r)
end
local rows = {}
for id, list in pairs(per) do
	table.sort(list, function(a, b) return a.t < b.t end)
	local minG, maxG = math.huge, 0
	for i = 2, #list do
		local g = list[i].t - list[i - 1].t
		minG, maxG = math.min(minG, g), math.max(maxG, g)
	end
	local mean = #list > 1 and (list[#list].t - list[1].t) / (#list - 1) or nil
	local dmgs = {}
	for _, r in ipairs(list) do dmgs[f(r.dmg)] = true end
	local dl = {} for k in pairs(dmgs) do table.insert(dl, k) end
	table.insert(rows, ("  %s %s n%d mean %s (nominal %s, %+.2f%%) min %s max %s dmg {%s} rar %s"):format(id:sub(1, 8), tostring(rarity[id]), #list, f(mean),
		tostring(nominal[id]), (mean and nominal[id]) and (mean / nominal[id] - 1) * 100 or 0, f(minG), f(maxG), table.concat(dl, ","), tostring(list[1].rar)))
end
table.sort(rows)
for _, r in ipairs(rows) do add(r) end

-- health drops
local kinds, perZ = {}, {}
for _, h in ipairs(S.HP) do
	if inW(h.t) then
		local k = kinds[h.k] or {n = 0, sum = 0}
		kinds[h.k] = k
		k.n += 1
		k.sum += h.dmg
		if h.k == "zombie" or h.k == "dummy" then
			local z = perZ[h.m] or {n = h.n, o = h.o, v = h.v, total = 0, hits = 0, pet = 0, petHits = 0}
			perZ[h.m] = z
			z.total += h.dmg
			z.hits += 1
		end
	end
end
for _, r in ipairs(shots) do
	if r.z and perZ[r.z] then perZ[r.z].pet += r.dmg perZ[r.z].petHits += 1 end
end
local kl = {}
for k, v in pairs(kinds) do table.insert(kl, ("%s %d drops / %s"):format(k, v.n, f(v.sum))) end
add("  health drops: " .. (#kl > 0 and table.concat(kl, ", ") or "none"))
if opts.Detail then
	for m, z in pairs(perZ) do
		add(("    %s [%s owner %s] drops %d total %s, pet shots %d = %s, other %s"):format(tostring(z.v or z.n), tostring(m.Parent and "live" or "gone"), tostring(z.o), z.hits, f(z.total), z.petHits, f(z.pet), f(z.total - z.pet)))
	end
end

-- turret tracers
local tr = {}
for _, t in ipairs(S.Tracers) do if inW(t.t) then table.insert(tr, t) end end
if #tr > 0 then
	local gaps = {}
	for i = 2, #tr do table.insert(gaps, tr[i].t - tr[i - 1].t) end
	table.sort(gaps)
	local frames = {}
	for _, t in ipairs(tr) do frames[t.f] = (frames[t.f] or 0) + 1 end
	local twelve, other = 0, {}
	for _, h in ipairs(S.HP) do
		if inW(h.t) and frames[h.f] then
			if math.abs(h.dmg - 12) < 1e-6 then twelve += 1 else other[f(h.dmg)] = (other[f(h.dmg)] or 0) + 1 end
		end
	end
	add(("  turret tracers %d: gap median %s min %s max %s; drops in tracer frames: 12 x%d, other {%s}"):format(#tr, f(gaps[math.max(1, math.ceil(#gaps / 2))]),
		f(gaps[1]), f(gaps[#gaps]), twelve, kv(other)))
end

local d = Combat.GetDiagnostics()
local d0 = S.Diag0 or {}
local dl = {}
for k, v in pairs(d) do if v ~= (d0[k] or 0) then table.insert(dl, ("%s %s->%s"):format(k, tostring(d0[k] or 0), tostring(v))) end end
table.sort(dl)
add("  combat diag since recorder start: " .. table.concat(dl, ", ") .. (S.Err and ("  RECORDER ERR " .. S.Err) or ""))
return table.concat(out, "\n")
