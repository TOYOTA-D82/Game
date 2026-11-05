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
	pad = true, vanish = true, spinner = true, pivot = true, current = true, mover = true, floor = true, rock = true,
	wall = true, roof = true, building = true,
}

local DAYS = 60 -- simulate two months of daily layouts
local total, walls, movers = 0, 0, 0
local usage = {}
local thinnest = { solo = math.huge, team = math.huge }

local function verify(theme, course, label)
	total += 1
	local info = Themes.Worlds[theme.world]
	check((Course.reachable(course)), label .. " not beatable (" .. table.concat(course.builders, ",") .. ")")
	check(#course.checkpoints == #course.builders + 1, label .. " checkpoint count")
	-- not too thin: solo >= 3 studs, team >= 4 (two chained players)
	local need = if theme.world == "team" then 4 else 3
	check(course.minWidth >= need - 0.01, ("%s: platform only %.2f wide"):format(label, course.minWidth))
	thinnest[theme.world] = math.min(thinnest[theme.world], course.minWidth)
	-- smashable walls must be too tall to just jump over (even in low gravity)
	local jump = 7.2 * 196.2 / (theme.gravity or 196.2)
	for _, h in course.walls do
		check(h >= jump + 2, ("%s: wall %.1f is jumpable (jump %.1f)"):format(label, h, jump))
	end
	walls += #course.walls
	for _, m in course.movers do
		check(m.gapBefore <= 2 and m.gapAfter <= 2, label .. " mover too far from the platforms")
		check(m.size >= 6, label .. " mover too small")
	end
	movers += #course.movers
	for _, p in course.pieces do
		check(KNOWN[p.kind] == true, label .. " unknown piece kind " .. p.kind)
		check(p.sx > 0 and p.sy > 0 and p.sz > 0, label .. " zero-size piece")
		if p.kind == "platform" or p.kind == "vanish" or p.kind == "checkpoint" then
			check(p.sy >= 1.99, ("%s platform thinner than 2 studs (%s s%d sy=%.2f)"):format(label, p.kind, p.section, p.sy))
		end
	end
	if course.mode == "journey" then
		-- the route never crosses or hugs itself
		local seen = {}
		for i, n in course.nodes do
			local key = n[1] .. "," .. n[2]
			check(not seen[key], label .. " route visits a cell twice")
			seen[key] = i
		end
		for i, n in course.nodes do
			for j, m in course.nodes do
				if math.abs(i - j) >= 2 then
					local d = math.abs(n[1] - m[1]) + math.abs(n[2] - m[2])
					check(d >= 2, label .. " route runs right next to an older part")
				end
			end
		end
		-- sections that aren't neighbours never overlap
		for _, a in course.pieces do
			for _, b in course.pieces do
				if b.section >= a.section + 2 and a.section >= 0 then
					local ox = math.min(a.cx + a.sx / 2, b.cx + b.sx / 2) - math.max(a.cx - a.sx / 2, b.cx - b.sx / 2)
					local oz = math.min(a.cz + a.sz / 2, b.cz + b.sz / 2) - math.max(a.cz - a.sz / 2, b.cz - b.sz / 2)
					check(not (ox > -2 and oz > -2), ("%s: %s(s%d) and %s(s%d) are on top of each other"):format(label, a.kind, a.section, b.kind, b.section))
				end
			end
		end
	else
		-- tower: laps stacked above each other leave room to jump,
		-- and nothing pokes into the landmark in the middle
		for _, a in course.pieces do
			local inside = (math.abs(a.cx - course.center[1]) - a.sx / 2) < course.coreHalf - 0.01
				and (math.abs(a.cz - course.center[2]) - a.sz / 2) < course.coreHalf - 0.01
			check(not inside, ("%s: %s(s%d) pokes into the landmark"):format(label, a.kind, a.section))
			for _, b in course.pieces do
				if b.section >= a.section + 3 then
					local ox = math.min(a.cx + a.sx / 2, b.cx + b.sx / 2) - math.max(a.cx - a.sx / 2, b.cx - b.sx / 2)
					local oz = math.min(a.cz + a.sz / 2, b.cz + b.sz / 2) - math.max(a.cz - a.sz / 2, b.cz - b.sz / 2)
					if ox > 0.01 and oz > 0.01 then
						local standable = a.kind ~= "breakable" and a.kind ~= "truss" and a.kind ~= "pivot" and a.kind ~= "spinner" and a.kind ~= "kill" and a.kind ~= "wall" and a.kind ~= "roof"
						local need = if standable then 10 else 5.5
						local gap = (b.cy - b.sy / 2) - (a.cy + a.sy / 2)
						check(gap >= need or (a.cy - a.sy / 2) >= (b.cy + b.sy / 2), ("%s: headroom %.1f between %s(s%d) and %s(s%d)"):format(label, gap, a.kind, a.section, b.kind, b.section))
					end
				end
			end
		end
	end
	-- ceilings (tunnels, shafts, arches) leave room to jump underneath
	for _, r in course.roofs do
		for _, sf in course.surfaces do
			if math.abs(sf.section - r.section) <= 1 then
				local ox = math.min(sf.maxX, r.maxX) - math.max(sf.minX, r.minX)
				local oz = math.min(sf.maxZ, r.maxZ) - math.max(sf.minZ, r.minZ)
				if ox > 0.01 and oz > 0.01 and sf.top < r.bottom then
					check(r.bottom - sf.top >= 9, ("%s: only %.1f headroom under a ceiling"):format(label, r.bottom - sf.top))
				end
			end
		end
	end
	for _, name in course.builders do
		usage[name] = (usage[name] or 0) + 1
	end
end

local FIRST_DAY = 20400 -- some day in 2025; any day works
for _, theme in Themes.List do
	local origin = Themes.Worlds[theme.world].origin
	-- exactly the layouts the game builds, day after day
	for day = FIRST_DAY, FIRST_DAY + DAYS - 1 do
		local seed = Course.dailySeed(theme, day)
		local seq = Course.sequenceFor(theme, day)
		verify(theme, Course.generate(theme, origin, makeRng(seed), seed, seq), ("%s day %d"):format(theme.id, day))
	end
end

-- Daily section lists: real types, right difficulty, no back-to-back repeats,
-- varied, the right length — and they really change from day to day.
for _, theme in Themes.List do
	local seen = {}
	for day = FIRST_DAY, FIRST_DAY + DAYS - 1 do
		local seq = Course.sequenceFor(theme, day)
		check(#seq == Themes.sectionCount(theme.level), theme.id .. " wrong section count")
		local distinct, n = {}, 0
		for i, name in seq do
			check(Course.Builders[name] ~= nil, theme.id .. " uses unknown section type " .. name)
			check(i == 1 or seq[i - 1] ~= name, theme.id .. " repeats " .. name .. " back to back")
			local diff = theme.diff[if i <= math.ceil(#seq / 2) then 1 else 2]
			check(Course.Builders[name] == nil or Course.Builders[name].minDiff <= diff, theme.id .. ": " .. name .. " too hard here")
			if not distinct[name] then
				distinct[name] = true
				n += 1
			end
		end
		check(n >= #seq - 1, theme.id .. " not varied enough on day " .. day)
		seen[table.concat(seq, ",")] = true
	end
	local layouts = 0
	for _ in seen do
		layouts += 1
	end
	check(layouts >= 10, theme.id .. " only has " .. layouts .. " different daily layouts in " .. DAYS .. " days")
end
check(Themes.levelCount("solo") == 8 and Themes.levelCount("team") == 8, "8 levels per world")

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

-- Points and rewards maths
local Ranking = require("./Ranking")
do
	local P = Config.Points
	-- harder levels are worth more
	check(Ranking.clearPoints(8, "solo", 999, 6, false) > Ranking.clearPoints(1, "solo", 999, 4, false), "level 8 worth more than level 1")
	-- first clear of the day doubles
	local normal = Ranking.clearPoints(3, "solo", 999, 5, false)
	local first = Ranking.clearPoints(3, "solo", 999, 5, true)
	check(first == normal * P.firstClearMultiplier, "first clear doubles")
	-- beating par adds the fast bonus
	local slow, slowFast = Ranking.clearPoints(3, "solo", 999, 5, false)
	local fast, isFast = Ranking.clearPoints(3, "solo", 10, 5, false)
	check(isFast and not slowFast and fast > slow, "fast bonus")
	-- teams earn a bit more
	check(Ranking.clearPoints(2, "squad", 999, 4, false) > Ranking.clearPoints(2, "duo", 999, 4, false), "squad > duo")
	check(Ranking.clearPoints(2, "duo", 999, 4, false) > Ranking.clearPoints(2, "solo", 999, 4, false), "duo > solo")
	check(Ranking.checkpointPoints("solo") == P.checkpoint, "checkpoint points")
	-- rewards
	check(Ranking.dailyReward(1) ~= nil and Ranking.dailyReward(3) ~= nil and Ranking.dailyReward(4) == nil, "daily top 3")
	check((Ranking.weeklyReward(1) :: any).wings == "Angel", "weekly #1 angel wings")
	check((Ranking.weeklyReward(7) :: any).wings == "Fairy", "weekly #7 fairy wings")
	check(Ranking.weeklyReward(11) == nil and Ranking.weeklyReward(nil) == nil, "no wings after 10")
	for _, r in Config.WeeklyRewards do
		check(Config.Wings[r.wings] ~= nil, "wing look exists: " .. r.wings)
	end
	for _, r in Config.DailyRewards do
		local found = false
		for _, t in Config.Trails do
			if t.id == r.trail and t.source == "reward" then
				found = true
			end
		end
		check(found, "daily reward trail exists and can't be bought: " .. r.trail)
	end
	check(Ranking.formatTime(83.4) == "1:23.4", "time format " .. Ranking.formatTime(83.4))
	check(Ranking.formatLeft(3 * 3600 + 20 * 60) == "3h 20m", "left format " .. Ranking.formatLeft(12000))
	check(Ranking.formatLeft(5 * 86400 + 4 * 3600) == "5d 4h", "left days")
end

local names = {}
for name, n in usage do
	table.insert(names, ("%s=%d"):format(name, n))
end
table.sort(names)
print(("courses checked: %d (16 levels x %d days of daily layouts)"):format(total, DAYS))
print("section types used: " .. table.concat(names, ", "))
print(("smashable walls: %d, moving platforms: %d"):format(walls, movers))
print(("narrowest platform: solo %.1f studs, team %.1f studs"):format(thinnest.solo, thinnest.team))
if failures > 0 then
	print(("%d check(s) failed"):format(failures))
	error("tests failed")
end
print("all checks passed")
