--!strict
-- Points and reward maths (pure, so it can be tested outside Roblox).

local Config = require(script.Parent.Config)

local Ranking = {}

-- Points for clearing a level.
--   level: 1..8, mode: "solo"|"duo"|"squad", sections: how many sections the
--   level had, firstToday: first clear of this level today.
function Ranking.clearPoints(level: number, mode: string, seconds: number, sections: number, firstToday: boolean): (number, boolean)
	local P = Config.Points
	local points = P.clearBase + P.clearPerLevel * level
	if firstToday then
		points *= P.firstClearMultiplier
	end
	local world = if mode == "solo" then "solo" else "team"
	local par = sections * P.parSecondsPerSection[world]
	local fast = seconds <= par
	if fast then
		points *= 1 + P.fastBonus
	end
	points *= P.modeMultiplier[mode] or 1
	return math.floor(points + 0.5), fast
end

function Ranking.checkpointPoints(mode: string): number
	return math.floor(Config.Points.checkpoint * (Config.Points.modeMultiplier[mode] or 1) + 0.5)
end

-- Points per minute for yesterday's final place (nil / 0 = not placed).
function Ranking.minuteRate(place: number?): number
	if place and place > 0 then
		for _, tier in Config.Points.perMinuteByPlace do
			if place <= tier.upTo then
				return tier.points
			end
		end
	end
	return Config.Points.perMinuteDefault
end

-- Leaderboard values carry a tie-breaker: same points -> whoever reached
-- that score earlier in the day/week ranks higher, so there are no ties.
--   value = points * SCALE + (SCALE - 1 - seconds since the period started)
local SCALE = 1000000
function Ranking.encodeScore(points: number, reachedAt: number, periodStart: number): number
	local elapsed = math.clamp(math.floor(reachedAt - periodStart), 0, SCALE - 1)
	return math.floor(points) * SCALE + (SCALE - 1 - elapsed)
end

function Ranking.decodeScore(value: number): number
	return value // SCALE
end

-- When a day / week starts (UTC seconds). Matches Calendar.dayNumber/weekNumber.
function Ranking.dayStart(day: number): number
	return day * 86400
end

function Ranking.weekStart(week: number): number
	return (week * 7 - 3) * 86400
end

-- Reward for a finishing rank, or nil.
function Ranking.dailyReward(rank: number?): typeof(Config.DailyRewards[1])?
	if not rank then
		return nil
	end
	return Config.DailyRewards[rank]
end

function Ranking.weeklyReward(rank: number?): typeof(Config.WeeklyRewards[1])?
	if not rank then
		return nil
	end
	for _, r in Config.WeeklyRewards do
		if rank <= r.upTo then
			return r
		end
	end
	return nil
end

function Ranking.formatTime(seconds: number): string
	return ("%d:%04.1f"):format(seconds // 60, seconds % 60)
end

-- "3h 20m" / "5d 4h"
function Ranking.formatLeft(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local d, h, m = seconds // 86400, (seconds % 86400) // 3600, (seconds % 3600) // 60
	if d > 0 then
		return ("%dd %dh"):format(d, h)
	end
	return ("%dh %02dm"):format(h, m)
end

return Ranking
