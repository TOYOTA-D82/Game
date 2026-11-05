--!strict
-- Daily ranking maths (pure, so it can be tested outside Roblox).
-- Score = levels cleared today x 10,000,000 - total time in tenths of a second:
-- more levels always wins; with the same number of levels the faster time wins.

local Config = require(script.Parent.Config)

local Ranking = {}

local SCORE_LEVEL = 10000000

function Ranking.encode(cleared: number, totalSeconds: number): number
	if cleared <= 0 then
		return 0
	end
	local tenths = math.clamp(math.floor(totalSeconds * 10 + 0.5), 0, SCORE_LEVEL - 1)
	return cleared * SCORE_LEVEL - tenths
end

function Ranking.decode(score: number): (number, number)
	if score <= 0 then
		return 0, 0
	end
	local cleared = math.floor((score + SCORE_LEVEL - 1) / SCORE_LEVEL)
	local tenths = cleared * SCORE_LEVEL - score
	return cleared, tenths / 10
end

-- Daily points for a finishing rank (nil = not in the top 100 but took part).
function Ranking.pointsFor(rank: number?): number
	if not rank then
		return Config.DailyParticipationPoints
	end
	if Config.DailyRankPoints[rank] then
		return Config.DailyRankPoints[rank]
	end
	for _, band in Config.DailyRankBands do
		if rank <= band.upTo then
			return band.points
		end
	end
	return Config.DailyParticipationPoints
end

function Ranking.formatTime(seconds: number): string
	return ("%d:%04.1f"):format(seconds // 60, seconds % 60)
end

return Ranking
