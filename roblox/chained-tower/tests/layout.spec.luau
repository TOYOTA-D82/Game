-- Builds every level (and many random variants) and checks they are fair.
local Course = require("./Course")
local Themes = require("./Themes")
local Calendar = require("./Calendar")
local Config = require("./Config")

local makeRng = Course.rng

local failures = 0
local function check(cond: boolean, msg: string)
	if not cond then
		failures += 1
		if failures <= 25 then
			print("FAIL: " .. msg)
		end
	end
end

local KNOWN = {
	platform = true, checkpoint = true, win = true, kill = true, breakable = true, truss = true,
	pad = true, vanish = true, spinner = true, pivot = true, current = true, mover = true, floor = true,
}

local VARIANTS = 150
local total, hurdles, movers = 0, 0, 0
local usage = {}
local thinnest = { solo = math.huge, team = math.huge }

local function verify(theme, course, label)
	total += 1
	local info = Themes.Worlds[theme.world]
	check((Course.reachable(course)), label .. " not beatable (" .. table.concat(course.builders, ",") .. ")")
	check(#course.checkpoints == #theme.sections + 1, label .. " checkpoint count")
	-- not too thin: solo >= 3 studs, team >= 4 (two chained players)
	local need = if theme.world == "team" then 4 else 3
	check(course.minWidth >= need - 0.01, ("%s: platform only %.2f wide"):format(label, course.minWidth))
	thinnest[theme.world] = math.min(thinnest[theme.world], course.minWidth)
	for _, h in course.hurdles do
		check(h.height <= 5, label .. " hurdle too tall")
		check(h.before >= 2.5 and h.after >= 2.5, label .. " no room around hurdle")
	end
	hurdles += #course.hurdles
	for _, m in course.movers do
		check(m.gapBefore <= 2 and m.gapAfter <= 2, label .. " mover too far from the platforms")
		check(m.size >= 6, label .. " mover too small")
	end
	movers += #course.movers
	for _, p in course.pieces do
		check(KNOWN[p.kind] == true, label .. " unknown piece kind " .. p.kind)
		check(p.sx > 0 and p.sy > 0 and p.sz > 0, label .. " zero-size piece")
		check(math.abs(p.cx - info.origin[1]) + p.sx / 2 <= info.lane + 7, label .. " piece too far to the side")
		if p.kind == "platform" or p.kind == "vanish" or p.kind == "checkpoint" then
			check(p.sy >= 2, label .. " platform thinner than 2 studs")
		end
	end
	for _, name in course.builders do
		usage[name] = (usage[name] or 0) + 1
	end
end

for _, theme in Themes.List do
	local origin = Themes.Worlds[theme.world].origin
	-- the real level, exactly as the game builds it
	verify(theme, Course.generate(theme, origin, makeRng(theme.seed)), theme.id)
	-- plus random variants of the same theme to make sure the rules always hold
	for v = 1, VARIANTS do
		local seed = theme.seed * 1000 + v
		verify(theme, Course.generate(theme, origin, makeRng(seed), seed), theme.id .. "#" .. v)
	end
end

-- Every level uses real section types, and never the same one twice in a row
for _, theme in Themes.List do
	for i, name in theme.sections do
		check(Course.Builders[name] ~= nil, theme.id .. " uses unknown section type " .. name)
		check(i == 1 or theme.sections[i - 1] ~= name, theme.id .. " repeats " .. name .. " back to back")
		check(Course.Builders[name] == nil or Course.Builders[name].minDiff <= theme.diff[if i <= 3 then 1 else 2], theme.id .. ": " .. name .. " is too hard for this level")
	end
	local distinct = {}
	for _, name in theme.sections do
		distinct[name] = true
	end
	local n = 0
	for _ in distinct do
		n += 1
	end
	check(n >= 5, theme.id .. " needs at least 5 different section types (has " .. n .. ")")
end
check(Themes.levelCount("solo") == 5 and Themes.levelCount("team") == 5, "5 levels per world")

-- Sanity: removing a section's platforms must make the course unbeatable
do
	local theme = Themes.List[1]
	local c = Course.generate(theme, Themes.Worlds.solo.origin, makeRng(42))
	local kept, remap = {}, {}
	for _, s in c.surfaces do
		if not (s.section == 3 and s.kind ~= "checkpoint") then
			table.insert(kept, s)
		end
	end
	for i, s in kept do
		remap[s.id] = i
		s.id = i
	end
	local links = {}
	for _, l in c.links do
		if remap[l[1]] and remap[l[2]] then
			table.insert(links, { remap[l[1]], remap[l[2]] })
		end
	end
	c.surfaces, c.links = kept, links
	c.startSurface, c.winSurface = remap[c.startSurface], remap[c.winSurface]
	check(not Course.reachable(c), "sanity: a course with a missing section should not be beatable")
end

-- Calendar: events and daily challenges
local function at(y, m, d)
	return os.time({ year = y, month = m, day = d, hour = 12 })
end
check((Calendar.activeEvent(at(2027, 10, 31)) or {}).id == "Halloween", "halloween")
check((Calendar.activeEvent(at(2027, 12, 20)) or {}).id == "Winter", "winter")
check((Calendar.activeEvent(at(2027, 2, 8)) or {}).id == "LunarNewYear", "lunar 2027")
check((Calendar.activeEvent(at(2028, 1, 30)) or {}).id == "LunarNewYear", "lunar 2028")
check(Calendar.activeEvent(at(2027, 6, 1)) == nil, "no event in June")
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
print(("courses checked: %d (10 real levels + %d variants each)"):format(total, VARIANTS))
print("section types used: " .. table.concat(names, ", "))
print(("jumpable breakable obstacles: %d, moving platforms: %d"):format(hurdles, movers))
print(("narrowest platform: solo %.1f studs, team %.1f studs"):format(thinnest.solo, thinnest.team))
if failures > 0 then
	print(("%d check(s) failed"):format(failures))
	error("tests failed")
end
print("all checks passed")
