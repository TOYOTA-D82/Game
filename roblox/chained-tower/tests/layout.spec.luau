-- Generates many towers and checks they are fair and well built.
local Layout = require("./TowerLayout")
local Config = require("./Config")
local Calendar = require("./Calendar")

-- Stand-in for Roblox's Random (same interface).
local function makeRng(seed: number)
	local state = seed % 2147483647
	if state <= 0 then
		state += 2147483646
	end
	local function nextFloat()
		state = (state * 48271) % 2147483647
		return state / 2147483647
	end
	return {
		NextInteger = function(_, a, b)
			return a + math.floor(nextFloat() * (b - a + 1))
		end,
		NextNumber = function(_, a, b)
			return a + nextFloat() * (b - a)
		end,
	}
end

local failures = 0
local function check(cond: boolean, msg: string)
	if not cond then
		failures += 1
		if failures <= 20 then
			print("FAIL: " .. msg)
		end
	end
end

local usage = {}
local hurdleCount = 0
local SEEDS = 600
local minH, maxH = math.huge, 0
for seed = 1, SEEDS do
	local t = Layout.generate(seed, makeRng(seed))
	for _, name in t.builders do
		usage[name] = (usage[name] or 0) + 1
	end
	minH, maxH = math.min(minH, t.height), math.max(maxH, t.height)

	-- 1. Beatable with no items: start -> win without smashing anything
	local ok = Layout.reachable(t)
	check(ok, ("seed %d not beatable (%s)"):format(seed, table.concat(t.builders, ",")))

	-- 1b. Every breakable obstacle on the route can be jumped by a normal player:
	--     at most 5 studs tall (jump height is 7.2) with run-up and landing room.
	for _, h in t.hurdles do
		check(h.height <= 5, ("seed %d: hurdle too tall (%.1f)"):format(seed, h.height))
		check(h.before >= 2.5 and h.after >= 2.5, ("seed %d: no room around hurdle"):format(seed))
	end
	hurdleCount += #t.hurdles

	-- 2. Checkpoint count
	check(#t.checkpoints == Config.SectionsPerTower + 1, "checkpoint count seed " .. seed)

	-- 3. Nothing pokes into the core, and nothing goes past the outer edge
	local coreHalf = Config.TowerHalfSize - 6
	for _, p in t.pieces do
		if p.kind ~= "core" then
			local minX, maxX = p.cx - p.sx / 2, p.cx + p.sx / 2
			local minZ, maxZ = p.cz - p.sz / 2, p.cz + p.sz / 2
			local inside = maxX > -coreHalf + 0.01 and minX < coreHalf - 0.01 and maxZ > -coreHalf + 0.01 and minZ < coreHalf - 0.01
			check(not inside, ("seed %d: %s in section %d overlaps the core"):format(seed, p.kind, p.section))
			local limit = Config.TowerHalfSize + 12
			check(math.abs(p.cx) + p.sx / 2 <= limit and math.abs(p.cz) + p.sz / 2 <= limit, "piece too far out")
			check(p.sx > 0 and p.sy > 0 and p.sz > 0, "piece with zero size")
		end
	end

	-- 4. Headroom: a surface from a later lap above an earlier one leaves room
	--    for a character (5 studs) on top of the tallest obstacle below.
	local tallest = {} -- per section: highest point of any piece
	for _, p in t.pieces do
		if p.kind ~= "core" then
			local top = p.cy + p.sy / 2
			tallest[p.section] = math.max(tallest[p.section] or -math.huge, top)
		end
	end
	for _, a in t.pieces do
		for _, b in t.pieces do
			if a.kind ~= "core" and b.kind ~= "core" and b.section >= a.section + 3 then
				local ox = math.min(a.cx + a.sx / 2, b.cx + b.sx / 2) - math.max(a.cx - a.sx / 2, b.cx - b.sx / 2)
				local oz = math.min(a.cz + a.sz / 2, b.cz + b.sz / 2) - math.max(a.cz - a.sz / 2, b.cz - b.sz / 2)
				if ox > 0.01 and oz > 0.01 then
					local aTop = a.cy + a.sy / 2
					local bBottom = b.cy - b.sy / 2
					local standable = a.kind ~= "breakable" and a.kind ~= "truss" and a.kind ~= "pivot" and a.kind ~= "spinner" and a.kind ~= "kill"
					local need = if standable then 10 else 5.5
					check(bBottom - aTop >= need, ("seed %d: headroom %.1f between %s(s%d) and %s(s%d)"):format(
						seed, bBottom - aTop, a.kind, a.section, b.kind, b.section))
				end
			end
		end
	end
end

-- 5. Removing the main route must break the tower (proves the test can fail):
--    deleting every platform of section 5 should make it unbeatable.
do
	local t = Layout.generate(42, makeRng(42))
	local kept = {}
	for _, s in t.surfaces do
		if not (s.section == 5 and s.kind ~= "checkpoint") then
			table.insert(kept, s)
		end
	end
	-- re-number ids
	local remap = {}
	for i, s in kept do
		remap[s.id] = i
		s.id = i
	end
	local links = {}
	for _, l in t.links do
		if remap[l[1]] and remap[l[2]] then
			table.insert(links, { remap[l[1]], remap[l[2]] })
		end
	end
	t.surfaces = kept
	t.links = links
	t.startSurface = remap[t.startSurface]
	t.winSurface = remap[t.winSurface]
	check(not Layout.reachable(t), "sanity: tower with a missing section should not be beatable")
end

-- 6. Calendar: events and daily challenges
local function at(y, m, d)
	return os.time({ year = y, month = m, day = d, hour = 12 })
end
check((Calendar.activeEvent(at(2027, 10, 31)) or {}).id == "Halloween", "halloween")
check((Calendar.activeEvent(at(2027, 12, 20)) or {}).id == "Winter", "winter")
check((Calendar.activeEvent(at(2027, 2, 8)) or {}).id == "LunarNewYear", "lunar 2027")
check((Calendar.activeEvent(at(2028, 1, 30)) or {}).id == "LunarNewYear", "lunar 2028")
check(Calendar.activeEvent(at(2027, 6, 1)) == nil, "no event in June")
check((Calendar.activeEvent(at(2027, 2, 14)) or {}).id ~= nil, "valentine/lunar overlap gives an event")
for day = 20000, 20400 do
	local list = Calendar.challengesForDay(day)
	check(#list == Config.ChallengesPerDay, "3 challenges")
	local ids = {}
	for _, c in list do
		check(not ids[c.id], "duplicate challenge")
		ids[c.id] = true
	end
end
check(Calendar.weekNumber(at(2027, 3, 1)) == Calendar.weekNumber(at(2027, 3, 7)), "Mon..Sun same week")
check(Calendar.weekNumber(at(2027, 3, 7)) ~= Calendar.weekNumber(at(2027, 3, 8)), "new week on Monday")

local names = {}
for name, n in usage do
	table.insert(names, ("%s=%d"):format(name, n))
end
table.sort(names)
print(("towers: %d, height %d..%d studs"):format(SEEDS, minH, maxH))
print("section types used: " .. table.concat(names, ", "))
print(("jumpable breakable obstacles: %d (%.1f per tower)"):format(hurdleCount, hurdleCount / SEEDS))
check(hurdleCount > SEEDS, "towers should have breakable obstacles on the route")
if failures > 0 then
	print(("%d check(s) failed"):format(failures))
	error("tests failed")
end
print("all checks passed")
