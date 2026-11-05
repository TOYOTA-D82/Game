-- Points-per-minute by yesterday's place, and the leaderboard tie-breaker.
local Ranking = require("./Ranking")
local Calendar = require("./Calendar")

local expect = { [1] = 10, [2] = 9, [3] = 8, [4] = 7, [10] = 7, [11] = 6, [50] = 6, [51] = 5, [100] = 5, [101] = 4 }
for place, rate in expect do
	assert(Ranking.minuteRate(place) == rate, ("place %d should earn %d/min, got %d"):format(place, rate, Ranking.minuteRate(place)))
end
assert(Ranking.minuteRate(nil) == 4 and Ranking.minuteRate(0) == 4, "not placed = default rate")
for place = 2, 120 do
	assert(Ranking.minuteRate(place) <= Ranking.minuteRate(place - 1), "a better place never earns less")
end

-- period starts line up with Calendar
local now = 1_780_000_000
local day, week = Calendar.dayNumber(now), Calendar.weekNumber(now)
assert(Calendar.dayNumber(Ranking.dayStart(day)) == day and Calendar.dayNumber(Ranking.dayStart(day) - 1) == day - 1, "day start")
assert(Calendar.weekNumber(Ranking.weekStart(week)) == week and Calendar.weekNumber(Ranking.weekStart(week) - 1) == week - 1, "week start")

-- tie-breaker: more points always wins; same points -> reached earlier wins
local start = Ranking.dayStart(day)
local early = Ranking.encodeScore(500, start + 3600, start)
local late = Ranking.encodeScore(500, start + 7200, start)
local more = Ranking.encodeScore(501, start + 86399, start)
assert(early > late, "same score: whoever reached it first ranks higher")
assert(more > early, "more points always rank higher")
assert(Ranking.decodeScore(early) == 500 and Ranking.decodeScore(more) == 501, "boards show the real points")
local wstart = Ranking.weekStart(week)
local endOfWeek = Ranking.encodeScore(40000, wstart + 7 * 86400 - 1, wstart)
assert(Ranking.decodeScore(endOfWeek) == 40000, "week-long periods still decode")
assert(Ranking.encodeScore(1, wstart + 7 * 86400 - 1, wstart) > Ranking.encodeScore(0, wstart, wstart), "1 point beats 0 even at the end of the week")
print("ranking: per-place rates and tie-breaker ok")
