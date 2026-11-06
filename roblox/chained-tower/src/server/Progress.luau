--!strict
-- Coins, stats, daily challenges, trails, tags, daily/weekly points,
-- leaderboards, rewards (daily crown + trail, weekly wings) and events.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Calendar = require(Shared.Calendar)
local Config = require(Shared.Config)
local Ranking = require(Shared.Ranking)
local Cosmetics = require(script.Parent.Cosmetics)
local TrailFx = require(script.Parent.TrailFx)
local Data = require(script.Parent.Data)
local Net = require(script.Parent.Net)

local Progress = {}

local trailById: { [string]: Config.Trail } = {}
for _, t in Config.Trails do
	trailById[t.id] = t
end
Progress.TrailById = trailById

local function today(): number
	return Calendar.dayNumber(os.time())
end

local function thisWeek(): number
	return Calendar.weekNumber(os.time())
end

----------------------------------------------------------------------
-- Events
----------------------------------------------------------------------
function Progress.currentEvent(): Config.GameEvent?
	return Calendar.activeEvent(os.time())
end

----------------------------------------------------------------------
-- Rewards that are running
----------------------------------------------------------------------
function Progress.activeReward(player: Player): typeof(Config.DailyRewards[1])?
	local p = Data.get(player)
	if not p or p.rewardRank < 1 or p.rewardUntil <= os.time() then
		return nil
	end
	return Ranking.dailyReward(p.rewardRank)
end

function Progress.activeWeekly(player: Player): typeof(Config.WeeklyRewards[1])?
	local p = Data.get(player)
	if not p or p.weekRewardRank < 1 or p.weekRewardUntil <= os.time() then
		return nil
	end
	return Ranking.weeklyReward(p.weekRewardRank)
end

----------------------------------------------------------------------
-- Points this day / week (resets when the id changes)
----------------------------------------------------------------------
local function currentPoints(p: Data.Profile): (number, number)
	local d = if p.dayPoints.id == today() then p.dayPoints.points else 0
	local w = if p.weekPoints.id == thisWeek() then p.weekPoints.points else 0
	return d, w
end

----------------------------------------------------------------------
-- Sync to client (throttled)
----------------------------------------------------------------------
local pendingSync: { [Player]: boolean } = {}

local function buildPayload(player: Player): { [string]: any }?
	local p = Data.get(player)
	if not p then
		return nil
	end
	local challenges = {}
	for _, c in Calendar.challengesForDay(p.day) do
		table.insert(challenges, {
			id = c.id,
			stat = c.stat,
			goal = c.goal,
			reward = c.reward,
			progress = math.min(p.stats[c.stat] or 0, c.goal),
			claimed = p.claimed[c.id] == true,
		})
	end
	local event = Progress.currentEvent()
	local dayPts, weekPts = currentPoints(p)
	local now = os.time()
	return {
		coins = p.coins,
		wins = p.wins,
		unchain = p.unchain + p.freeUnchain,
		freeUnchain = p.freeUnchain,
		smash = p.smash + p.freeSmash,
		freeSmash = p.freeSmash,
		skip = p.skip,
		trails = p.trails,
		equipped = p.equipped,
		passes = p.passes,
		starterBought = p.starterBought,
		today = p.today,
		challengeBest = if p.challenge.id == today() then p.challenge.best else 0,
		dayPoints = dayPts,
		weekPoints = weekPts,
		points = p.points,
		dayLeft = (today() + 1) * 86400 - now,
		weekLeft = ((thisWeek() + 1) * 7 - 3) * 86400 - now,
		rewardRank = if Progress.activeReward(player) then p.rewardRank else 0,
		rewardLeft = math.max(0, p.rewardUntil - now),
		weekRewardRank = if Progress.activeWeekly(player) then p.weekRewardRank else 0,
		weekRewardLeft = math.max(0, p.weekRewardUntil - now),
		studioUnlockAll = RunService:IsStudio() and Config.StudioUnlockAll,
		challenges = challenges,
		event = event and { id = event.id, trail = event.trail, owned = p.trails[event.trail] == true } or nil,
	}
end

function Progress.sync(player: Player)
	if pendingSync[player] then
		return
	end
	pendingSync[player] = true
	task.defer(function()
		pendingSync[player] = nil
		local payload = buildPayload(player)
		if payload then
			Net.send(player, "profile", payload)
		end
		local p = Data.get(player)
		local stats = player:FindFirstChild("leaderstats")
		if p and stats then
			local dayPts = currentPoints(p);
			(stats:FindFirstChild("Today") :: IntValue).Value = dayPts;
			(stats:FindFirstChild("Coins") :: IntValue).Value = p.coins
		end
	end)
end

Data.Changed:Connect(Progress.sync)

----------------------------------------------------------------------
-- Coins and stats
----------------------------------------------------------------------
function Progress.addCoins(player: Player, amount: number, boosts: boolean?)
	local p = Data.get(player)
	if not p then
		return 0
	end
	local total = amount
	if boosts and p.passes.VIP then
		total *= Config.VipCoinMultiplier
	end
	local reward = Progress.activeReward(player)
	if boosts and reward then
		total *= reward.coinMultiplier -- daily top-3 reward
	end
	total = math.floor(total + 0.5)
	p.coins += total
	Data.markDirty(player)
	return total
end

function Progress.addStat(player: Player, stat: string, amount: number?)
	local p = Data.get(player)
	if not p then
		return
	end
	Data.refreshDaily(player)
	p.stats[stat] = (p.stats[stat] or 0) + (amount or 1)
	for _, c in Calendar.challengesForDay(p.day) do
		if c.stat == stat and not p.claimed[c.id] and (p.stats[stat] or 0) >= c.goal then
			p.claimed[c.id] = true
			p.coins += c.reward
			Net.send(player, "toast", { key = "challengeDone", args = { c.reward }, good = true })
		end
	end
	Data.markDirty(player)
end

----------------------------------------------------------------------
-- Points (daily + weekly)
----------------------------------------------------------------------
local postDirty: { [Player]: boolean } = {}

local function addPending(p: Data.Profile, kind: string, id: number)
	for _, entry in p.pending do
		if entry.kind == kind and entry.id == id then
			return
		end
	end
	table.insert(p.pending, { kind = kind, id = id })
end

function Progress.addPoints(player: Player, amount: number, reason: string?)
	local p = Data.get(player)
	if not p or amount <= 0 then
		return
	end
	local d, w = today(), thisWeek()
	if p.dayPoints.id ~= d then
		p.dayPoints = { id = d, points = 0 }
	end
	if p.weekPoints.id ~= w then
		p.weekPoints = { id = w, points = 0 }
	end
	p.dayPoints.points += amount
	p.weekPoints.points += amount
	p.dayPoints.at = os.time()
	p.weekPoints.at = os.time()
	p.points += amount
	addPending(p, "day", d)
	addPending(p, "week", w)
	postDirty[player] = true
	Data.markDirty(player)
	Net.send(player, "points", { amount = amount, reason = reason })
end

local function store(name: string): OrderedDataStore?
	local ok, result = pcall(function()
		return DataStoreService:GetOrderedDataStore(name)
	end)
	return if ok then result else nil
end

local function boardName(kind: string, id: number): string
	if kind == "challenge" then
		return ("ChallengeV1_Day_%d"):format(id) -- best times, lowest first
	end
	-- V2: values carry a tie-breaker (see Ranking.encodeScore)
	return (if kind == "day" then "PointsV2_Day_%d" else "PointsV2_Week_%d"):format(id)
end

-- Upload changed points to the leaderboards every 30 seconds (kind to the limits).
local function postPoints(player: Player)
	local p = Data.get(player)
	if not p then
		return
	end
	for _, entry in { { "day", p.dayPoints }, { "week", p.weekPoints } } do
		local kind, rec = entry[1] :: string, entry[2] :: Data.PeriodPoints
		local board = store(boardName(kind, rec.id))
		if board and rec.points > 0 then
			local start = if kind == "day" then Ranking.dayStart(rec.id) else Ranking.weekStart(rec.id)
			local value = Ranking.encodeScore(rec.points, rec.at or os.time(), start)
			pcall(function()
				board:UpdateAsync(tostring(player.UserId), function(old)
					return math.max(old or 0, value)
				end)
			end)
		end
	end
end

----------------------------------------------------------------------
-- Today's challenge progress (which levels are open, best times)
----------------------------------------------------------------------
-- Called when a player finishes a level. Returns (firstClearToday, bestTime).
function Progress.recordClear(player: Player, world: string, level: number, seconds: number): (boolean, number)
	local p = Data.get(player)
	if not p then
		return false, seconds
	end
	Data.refreshDaily(player)
	local wd: Data.WorldDay = (p.today :: any)[world]
	local key = tostring(level)
	local isNew = wd.times[key] == nil
	if level == wd.cleared + 1 then
		wd.cleared = level
	end
	local best = wd.times[key]
	if best == nil or seconds < best then
		wd.times[key] = math.floor(seconds * 10 + 0.5) / 10
	end
	Data.markDirty(player)
	return isNew, wd.times[key]
end

----------------------------------------------------------------------
-- Settling finished days and weeks: rank -> reward
-- Runs when a player joins and every few minutes, so no server needs to be
-- online at midnight.
----------------------------------------------------------------------
local rankCache: { [string]: { at: number, ids: { [number]: number } } } = {}
local function rankOf(kind: string, id: number, userId: number): number?
	local cacheKey = kind .. id
	local cached = rankCache[cacheKey]
	if not cached or os.clock() - cached.at > 600 then
		local board = store(boardName(kind, id))
		if not board then
			return nil
		end
		local ok, pages = pcall(function()
			return board:GetSortedAsync(kind == "challenge", 100)
		end)
		if not ok then
			return nil
		end
		local ids = {}
		for i, entry in (pages :: DataStorePages):GetCurrentPage() do
			ids[tonumber(entry.key) or 0] = i
		end
		cached = { at = os.clock(), ids = ids }
		rankCache[cacheKey] = cached
	end
	return (cached :: any).ids[userId]
end

function Progress.settle(player: Player)
	local p = Data.get(player)
	if not p or #p.pending == 0 then
		return
	end
	local remaining = {}
	local changed = false
	for _, entry in p.pending do
		local current = if entry.kind == "week" then thisWeek() else today()
		if entry.id >= current then
			table.insert(remaining, entry)
			continue
		end
		local rank = rankOf(entry.kind, entry.id, player.UserId)
		changed = true
		local now = os.time()
		if entry.kind == "day" and entry.id > p.prevDay.id then
			p.prevDay = { id = entry.id, place = rank or 0 }
		end
		if entry.kind == "challenge" then
			local title = rank and Config.ChallengeTitles[rank]
			if title and rank then
				if p.titleUntil <= now or rank < p.titleRank then
					p.titleRank = rank
				end
				p.titleUntil = math.max(p.titleUntil, now + Config.Challenge.titleHours * 3600)
			end
			Net.send(player, "challengeResult", { rank = rank })
			continue
		end
		if entry.kind == "day" then
			local reward = Ranking.dailyReward(rank)
			if reward and rank then
				if p.rewardUntil <= now or rank < p.rewardRank then
					p.rewardRank = rank
				end
				p.rewardUntil = math.max(p.rewardUntil, now + reward.hours * 3600)
				p.equipped = (Ranking.dailyReward(p.rewardRank) :: any).trail
			end
		else
			local reward = Ranking.weeklyReward(rank)
			if reward and rank then
				if p.weekRewardUntil <= now or rank < p.weekRewardRank then
					p.weekRewardRank = rank
				end
				p.weekRewardUntil = math.max(p.weekRewardUntil, now + reward.hours * 3600)
			end
		end
		Net.send(player, "rankResult", { kind = entry.kind, rank = rank })
	end
	p.pending = remaining
	if changed then
		Progress.timeTick(player, false) -- yesterday's place sets today's points per minute
		Data.markDirty(player)
		Progress.applyCosmetics(player)
	end
end

----------------------------------------------------------------------
-- Trails, tags, crown, wings
----------------------------------------------------------------------
function Progress.ownsTrail(player: Player, id: string): boolean
	local p = Data.get(player)
	local trail = trailById[id]
	if not p or not trail then
		return false
	end
	if trail.source == "free" or p.trails[id] then
		return true
	end
	if trail.source == "reward" then
		local reward = Progress.activeReward(player)
		return reward ~= nil and reward.trail == id
	end
	return trail.pass ~= nil and p.passes[trail.pass :: string] == true
end

function Progress.applyCosmetics(player: Player)
	local p = Data.get(player)
	local character = player.Character
	if not p or not character then
		return
	end
	local id = if Progress.ownsTrail(player, p.equipped) then p.equipped else "Basic"
	TrailFx.apply(character, id)

	local daily = Progress.activeReward(player)
	local weekly = Progress.activeWeekly(player)
	Cosmetics.apply(character, weekly and weekly.wings or nil, weekly ~= nil and weekly.halo == true, daily ~= nil and daily.crown == true)

	local head = character:FindFirstChild("Head")
	if head then
		local old = head:FindFirstChild("CT_Vip")
		if old then
			old:Destroy()
		end
		local oldTitle = head:FindFirstChild("CT_Title")
		if oldTitle then
			oldTitle:Destroy()
		end
		-- daily challenge top 3: a glowing title above everything else
		local title = Progress.activeTitle(player)
		if title then
			local bb = Instance.new("BillboardGui")
			bb.Name = "CT_Title"
			bb.Size = UDim2.fromOffset(220, 30)
			bb.StudsOffset = Vector3.new(0, if weekly and weekly.halo then 4.8 else 3.8, 0)
			bb.MaxDistance = 90
			bb.LightInfluence = 0
			local l = Instance.new("TextLabel")
			l.BackgroundTransparency = 1
			l.Size = UDim2.fromScale(1, 1)
			l.Font = Enum.Font.FredokaOne
			l.TextScaled = true
			l.Text = title.text
			l.TextColor3 = title.color
			l.TextStrokeColor3 = Color3.fromRGB(60, 30, 0)
			l.TextStrokeTransparency = 0
			l.Parent = bb
			local shine = Instance.new("UIGradient")
			shine.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
				ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 250, 220)),
				ColorSequenceKeypoint.new(1, Color3.new(1, 1, 1)),
			})
			shine.Parent = l
			bb.Parent = head
		end
		local tags = {}
		if weekly then
			table.insert(tags, ("%s W#%d"):format(weekly.tag, p.weekRewardRank))
		end
		if daily then
			table.insert(tags, ("%s D#%d"):format(daily.tag, p.rewardRank))
		end
		if p.passes.VIP then
			table.insert(tags, "VIP")
		end
		if #tags > 0 then
			local bb = Instance.new("BillboardGui")
			bb.Name = "CT_Vip"
			bb.Size = UDim2.fromOffset(150, 26)
			bb.StudsOffset = Vector3.new(0, if weekly and weekly.halo then 3.6 else 2.6, 0)
			bb.MaxDistance = 70
			local l = Instance.new("TextLabel")
			l.BackgroundTransparency = 1
			l.Size = UDim2.fromScale(1, 1)
			l.Font = Enum.Font.FredokaOne
			l.TextScaled = true
			l.Text = table.concat(tags, "  ")
			l.TextColor3 = if weekly or daily then Color3.fromRGB(255, 235, 120) else Color3.fromRGB(255, 215, 60)
			l.TextStrokeTransparency = 0.2
			l.Parent = bb
			bb.Parent = head
		end
	end
end

Net.on("equipTrail", function(player, id)
	if type(id) ~= "string" or not Progress.ownsTrail(player, id) then
		return
	end
	local p = Data.get(player) :: Data.Profile
	p.equipped = id
	Data.markDirty(player)
	Progress.applyCosmetics(player)
end)

Net.on("buyTrail", function(player, id)
	local p = Data.get(player)
	local trail = if type(id) == "string" then trailById[id] else nil
	if not p or not trail or trail.source ~= "coins" or p.trails[trail.id] then
		return
	end
	local price = trail.price or 0
	if p.coins < price then
		return
	end
	p.coins -= price
	p.trails[trail.id] = true
	p.equipped = trail.id
	Data.markDirty(player)
	Progress.applyCosmetics(player)
end)

Net.on("claimEvent", function(player)
	local p = Data.get(player)
	local event = Progress.currentEvent()
	if not p or not event or p.trails[event.trail] then
		return
	end
	p.trails[event.trail] = true
	p.equipped = event.trail
	Data.markDirty(player)
	Progress.applyCosmetics(player)
end)

----------------------------------------------------------------------
-- Leaderboards
----------------------------------------------------------------------
local nameCache: { [number]: string } = {}
local function nameOf(userId: number): string
	if nameCache[userId] then
		return nameCache[userId]
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	nameCache[userId] = if ok then name else "Player"
	return nameCache[userId]
end

local function topOf(kind: string, id: number, count: number): { { name: string, value: number } }?
	local board = store(boardName(kind, id))
	if not board then
		return nil
	end
	local challenge = kind == "challenge"
	local ok, pages = pcall(function()
		return board:GetSortedAsync(challenge, count)
	end)
	if not ok or not pages then
		return nil
	end
	local list = {}
	for _, e in (pages :: DataStorePages):GetCurrentPage() do
		local value = if challenge then Ranking.decodeTime(e.value) else Ranking.decodeScore(e.value)
		table.insert(list, { name = nameOf(tonumber(e.key) or 0), value = value })
	end
	return list
end

----------------------------------------------------------------------
-- Daily challenge: best time of the day, its board and top-3 titles
----------------------------------------------------------------------
local function postChallenge(player: Player)
	local p = Data.get(player)
	if not p or p.challenge.best <= 0 then
		return
	end
	local board = store(boardName("challenge", p.challenge.id))
	if board then
		local value = Ranking.encodeTime(p.challenge.best, p.challenge.at, Ranking.dayStart(p.challenge.id))
		pcall(function()
			board:UpdateAsync(tostring(player.UserId), function(old)
				return if old == nil or value < old then value else old
			end)
		end)
	end
end

-- A finished challenge run on the route of `day`. Returns (firstClearToday, best, newBest).
function Progress.recordChallenge(player: Player, seconds: number, day: number): (boolean, number, boolean)
	local p = Data.get(player)
	if not p then
		return false, seconds, false
	end
	seconds = math.floor(seconds * 100 + 0.5) / 100
	local first = p.challenge.id ~= day or p.challenge.best <= 0
	local improved = first or seconds < p.challenge.best
	if improved then
		p.challenge = { id = day, best = seconds, at = os.time() }
		addPending(p, "challenge", day)
		task.spawn(postChallenge, player)
		Data.markDirty(player)
	end
	return first, p.challenge.best, improved
end

function Progress.activeTitle(player: Player): typeof(Config.ChallengeTitles[1])?
	local p = Data.get(player)
	if not p or p.titleRank <= 0 or p.titleUntil <= os.time() then
		return nil
	end
	return Config.ChallengeTitles[p.titleRank]
end

-- The board on the challenge island (today's 10 fastest), and today's leader
-- for the lobby route board (as a Workspace attribute the clients read).
function Progress.startChallengeBoard(board: SurfaceGui)
	local list = Instance.new("Frame")
	list.BackgroundTransparency = 1
	list.Size = UDim2.fromScale(1, 1)
	list.Parent = board
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list
	local function row(order: number, text: string, color: Color3, height: number): TextLabel
		local l = Instance.new("TextLabel")
		l.LayoutOrder = order
		l.BackgroundTransparency = 1
		l.Size = UDim2.fromScale(1, height)
		l.Font = Enum.Font.FredokaOne
		l.TextScaled = true
		l.TextColor3 = color
		l.Text = text
		l.Parent = list
		return l
	end
	local header = row(0, "⚡ TODAY'S FASTEST ⚡\n今日挑戰最快紀錄\nTop 3: title for 24h 前三名拿稱號", Color3.fromRGB(255, 215, 80), 0.2)
	header.TextWrapped = true
	local medal = { "🥇", "🥈", "🥉" }
	local rows = {}
	for i = 1, 10 do
		rows[i] = row(i, "", if i <= 3 then Color3.fromRGB(255, 235, 150) else Color3.new(1, 1, 1), 0.075)
	end
	task.spawn(function()
		while true do
			local top = topOf("challenge", today(), 10)
			if top then
				for i = 1, 10 do
					local e = top[i]
					rows[i].Text = if e then ("%s %d. %s — %s"):format(medal[i] or "", i, e.name, Ranking.formatTime(e.value)) else ""
				end
				if #top == 0 then
					rows[1].Text = "No one yet — be the first! 還沒有人上榜"
				end
				local lead = top[1]
				Workspace:SetAttribute("ChallengeLeader", if lead then ("%s|%s"):format(lead.name, Ranking.formatTime(lead.value)) else "")
			else
				rows[1].Text = "(publish the game to see the leaderboard)"
			end
			task.wait(60)
		end
	end)
end

-- kind: "day" (today's points) or "week" (this week's points)
function Progress.startLeaderboard(board: SurfaceGui, kind: string)
	local list = Instance.new("Frame")
	list.BackgroundTransparency = 1
	list.Size = UDim2.fromScale(1, 1)
	list.Parent = board
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list

	local function row(order: number, text: string, color: Color3, height: number)
		local l = Instance.new("TextLabel")
		l.LayoutOrder = order
		l.BackgroundTransparency = 1
		l.Size = UDim2.fromScale(1, height)
		l.Font = Enum.Font.FredokaOne
		l.TextScaled = true
		l.TextColor3 = color
		l.Text = text
		l.Parent = list
		return l
	end

	local titles = {
		day = "⭐ TODAY'S POINTS ⭐\n今日積分（每天 08:00 歸零）\nTop 3: crown & trail for a day",
		week = "🏆 THIS WEEK'S POINTS 🏆\n本週積分（每週一 08:00 歸零）\nTop 10: wings for a week",
	}
	local header = row(0, titles[kind] or kind, Color3.fromRGB(255, 215, 80), 0.22)
	header.TextWrapped = true
	local rows = {}
	local medal = { "🥇", "🥈", "🥉" }
	for i = 1, 10 do
		rows[i] = row(i, "", if i <= 3 then Color3.fromRGB(255, 235, 150) else Color3.new(1, 1, 1), 0.075)
	end

	task.spawn(function()
		while true do
			local id = if kind == "day" then today() else thisWeek()
			local top = topOf(kind, id, 10)
			if top then
				for i = 1, 10 do
					local e = top[i]
					rows[i].Text = if e then ("%s %d. %s — %d ⭐"):format(medal[i] or "", i, e.name, e.value) else ""
				end
				if #top == 0 then
					rows[1].Text = "No one yet — be the first! 還沒有人上榜"
				end
			else
				rows[1].Text = "(publish the game to see the leaderboard)"
			end
			task.wait(60)
		end
	end)
end

-- Hall of fame podium in the lobby: last week's top 3 (or this week's so far).
function Progress.startPodium(labels: { TextLabel })
	task.spawn(function()
		while true do
			local top = topOf("week", thisWeek() - 1, 3)
			local caption = "LAST WEEK"
			if not top or #top == 0 then
				top = topOf("week", thisWeek(), 3)
				caption = "THIS WEEK"
			end
			for i = 1, 3 do
				local e = top and top[i]
				labels[i].Text = if e then ("%s\n%d ⭐"):format(e.name, e.value) else ("%s\n—"):format(caption)
			end
			task.wait(300)
		end
	end)
end

----------------------------------------------------------------------
-- Player setup and background loops
----------------------------------------------------------------------
function Progress.setupLeaderstats(player: Player)
	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	local todayPts = Instance.new("IntValue")
	todayPts.Name = "Today"
	todayPts.Parent = stats
	local coins = Instance.new("IntValue")
	coins.Name = "Coins"
	coins.Parent = stats
	stats.Parent = player
end

function Progress.start()
	-- upload points
	task.spawn(function()
		while true do
			task.wait(30)
			for player in postDirty do
				postDirty[player] = nil
				task.spawn(postPoints, player)
			end
		end
	end)
	-- settle finished days/weeks, and drop expired rewards
	task.spawn(function()
		while true do
			task.wait(120)
			for _, player in Players:GetPlayers() do
				task.spawn(Progress.settle, player)
				local p = Data.get(player)
				local now = os.time()
				local expired = p
					and ((p.rewardRank > 0 and p.rewardUntil <= now) or (p.weekRewardRank > 0 and p.weekRewardUntil <= now) or (p.titleRank > 0 and p.titleUntil <= now))
				if p and expired then
					if p.rewardUntil <= now then
						p.rewardRank = 0
					end
					if p.titleUntil <= now then
						p.titleRank = 0
					end
					if p.weekRewardUntil <= now then
						p.weekRewardRank = 0
					end
					Data.markDirty(player)
					Progress.applyCosmetics(player)
				end
			end
		end
	end)
end

-- Upload any unsent points right away (called before a player's data is released).
----------------------------------------------------------------------
-- Time points: rank-based points per minute, also for time away
----------------------------------------------------------------------
-- Points per minute right now (0 until you clear a level today), set by
-- yesterday's final place.
function Progress.timeRate(player: Player): number
	local p = Data.get(player)
	if not p then
		return 0
	end
	Data.refreshDaily(player)
	local challengeToday = p.challenge.id == today() and p.challenge.best > 0
	if p.today.solo.cleared + p.today.team.cleared <= 0 and not challengeToday then
		return 0
	end
	return Ranking.minuteRate(Progress.yesterdayPlace(player))
end

-- Final place on yesterday's daily board (0 = not in the top 100 / didn't play).
function Progress.yesterdayPlace(player: Player): number
	local p = Data.get(player)
	if p and p.prevDay.id == today() - 1 then
		return p.prevDay.place
	end
	return 0
end

-- Shows the rate on the HUD and remembers it for time away.
function Progress.timeTick(player: Player, award: boolean)
	local p = Data.get(player)
	if not p then
		return
	end
	local rate = Progress.timeRate(player)
	if award and rate > 0 then
		Progress.addPoints(player, rate, "time")
	end
	p.lastSeen = os.time()
	p.lastRate = rate
	player:SetAttribute("PointsRate", rate)
	player:SetAttribute("PointsPlace", Progress.yesterdayPlace(player))
	Data.markDirty(player)
end

-- On join: points for the minutes you were away, at the rate you had when
-- you left, capped at Config.Points.offlineMaxMinutes per day.
function Progress.creditTimeAway(player: Player)
	local p = Data.get(player)
	if not p then
		return
	end
	local away = if p.lastSeen > 0 then math.floor((os.time() - p.lastSeen) / 60) else 0
	if away >= 1 and p.lastRate > 0 then
		local d = today()
		if p.offline.id ~= d then
			p.offline = { id = d, minutes = 0 }
		end
		local minutes = math.min(away, Config.Points.offlineMaxMinutes - p.offline.minutes)
		if minutes > 0 then
			p.offline.minutes += minutes
			Progress.addPoints(player, minutes * p.lastRate, "away")
			Net.send(player, "awayPoints", { minutes = minutes, points = minutes * p.lastRate, rate = p.lastRate })
		end
	end
	Progress.timeTick(player, false)
end

function Progress.flush(player: Player)
	if postDirty[player] then
		postDirty[player] = nil
		postPoints(player)
	end
end

return Progress
