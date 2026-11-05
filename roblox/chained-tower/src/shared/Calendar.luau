--!strict
-- Date helpers (UTC). Pure functions so they can be tested outside Roblox.

local Config = require(script.Parent.Config)

local Calendar = {}

local SECONDS_PER_DAY = 86400

-- Whole days since 1970-01-01 UTC. Free items and challenges reset when this changes.
function Calendar.dayNumber(now: number): number
	return math.floor(now / SECONDS_PER_DAY)
end

-- Weeks start on Monday. 1970-01-01 was a Thursday, so shift by 3 days.
function Calendar.weekNumber(now: number): number
	return math.floor((Calendar.dayNumber(now) + 3) / 7)
end

local function dayOfYear(year: number, month: number, day: number): number
	return os.time({ year = year, month = month, day = day, hour = 12 })
end

-- Returns the active event (or nil) for a UTC timestamp.
function Calendar.activeEvent(now: number): Config.GameEvent?
	local date = os.date("!*t", now) :: any
	local year, month, day = date.year, date.month, date.day
	local today = dayOfYear(year, month, day)

	for _, event in Config.Events do
		if event.from and event.to then
			local fromM, fromD = event.from[1], event.from[2]
			local toM, toD = event.to[1], event.to[2]
			local startT = dayOfYear(year, fromM, fromD)
			local endT = dayOfYear(year, toM, toD)
			if endT >= startT then
				if today >= startT and today <= endT then
					return event
				end
			else
				-- wraps over new year (e.g. Dec 28 -> Jan 3)
				if today >= startT or today <= endT then
					return event
				end
			end
		elseif event.lunarStarts then
			for _, y in { year, year - 1 } do
				local start = event.lunarStarts[y]
				if start then
					local startT = dayOfYear(y, start[1], start[2])
					local endT = startT + ((event.lunarLength or 14) - 1) * SECONDS_PER_DAY
					if today >= startT and today <= endT then
						return event
					end
				end
			end
		end
	end
	return nil
end

-- Deterministic pick of today's challenges, the same on every server.
function Calendar.challengesForDay(day: number): { typeof(Config.Challenges[1]) }
	local pool = table.clone(Config.Challenges)
	-- small LCG so every server (and the tests) pick the same list
	local state = (day * 7919 + 17) % 2147483647
	local picked = {}
	for _ = 1, math.min(Config.ChallengesPerDay, #pool) do
		state = (state * 48271) % 2147483647
		local index = state % #pool + 1
		table.insert(picked, pool[index])
		table.remove(pool, index)
	end
	return picked
end

return Calendar
