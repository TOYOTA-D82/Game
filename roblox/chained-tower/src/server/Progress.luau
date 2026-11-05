--!strict
-- Coins, stats, daily challenges, trails, VIP tag, weekly leaderboard, events.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Calendar = require(Shared.Calendar)
local Config = require(Shared.Config)
local Data = require(script.Parent.Data)
local Net = require(script.Parent.Net)

local Progress = {}

local trailById: { [string]: Config.Trail } = {}
for _, t in Config.Trails do
	trailById[t.id] = t
end
Progress.TrailById = trailById

----------------------------------------------------------------------
-- Events
----------------------------------------------------------------------
function Progress.currentEvent(): Config.GameEvent?
	return Calendar.activeEvent(os.time())
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
		points = p.points,
		rewardRank = if p.rewardUntil > os.time() then p.rewardRank else 0,
		rewardLeft = math.max(0, p.rewardUntil - os.time()), -- seconds
		studioUnlockAll = game:GetService("RunService"):IsStudio() and Config.StudioUnlockAll,
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
			(stats:FindFirstChild("Coins") :: IntValue).Value = p.coins;
			(stats:FindFirstChild("Wins") :: IntValue).Value = p.wins
		end
	end)
end

Data.Changed:Connect(Progress.sync)

----------------------------------------------------------------------
-- Coins and stats
----------------------------------------------------------------------
function Progress.addCoins(player: Player, amount: number, applyVip: boolean?)
	local p = Data.get(player)
	if not p then
		return 0
	end
	local total = amount
	if applyVip and p.passes.VIP then
		total *= Config.VipCoinMultiplier
	end
	local reward = Progress.activeReward(player)
	if applyVip and reward then
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
-- Trails, VIP tag and daily top-3 rewards
----------------------------------------------------------------------
-- The reward a player won in yesterday's ranking, if it's still running.
function Progress.activeReward(player: Player): typeof(Config.DailyRewards[1])?
	local p = Data.get(player)
	if not p or p.rewardRank < 1 or p.rewardUntil <= os.time() then
		return nil
	end
	return Config.DailyRewards[p.rewardRank]
end

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
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	for _, child in root:GetChildren() do
		if child.Name == "CT_Trail" or child.Name == "CT_A0" or child.Name == "CT_A1" or child.Name == "CT_Sparkle" then
			child:Destroy()
		end
	end

	local id = if Progress.ownsTrail(player, p.equipped) then p.equipped else "Basic"
	local trail = trailById[id]
	if trail then
		local a0 = Instance.new("Attachment")
		a0.Name = "CT_A0"
		a0.Position = Vector3.new(0, 0.7, 0.4)
		a0.Parent = root
		local a1 = Instance.new("Attachment")
		a1.Name = "CT_A1"
		a1.Position = Vector3.new(0, -1.1, 0.4)
		a1.Parent = root

		local keypoints = {}
		for i, c in trail.colors do
			table.insert(keypoints, ColorSequenceKeypoint.new((i - 1) / math.max(1, #trail.colors - 1), c))
		end
		if #keypoints == 1 then
			table.insert(keypoints, ColorSequenceKeypoint.new(1, trail.colors[1]))
		end
		local t = Instance.new("Trail")
		t.Name = "CT_Trail"
		t.Attachment0 = a0
		t.Attachment1 = a1
		t.Color = ColorSequence.new(keypoints)
		t.Lifetime = 0.55
		t.LightEmission = 0.7
		t.FaceCamera = true
		t.WidthScale = NumberSequence.new((trail.width or 1), 0.1)
		t.Transparency = NumberSequence.new(0.1, 1)
		t.Parent = root

		if trail.sparkles then
			local e = Instance.new("ParticleEmitter")
			e.Name = "CT_Sparkle"
			e.Color = ColorSequence.new(keypoints)
			e.Rate = 18
			e.Lifetime = NumberRange.new(0.4, 0.8)
			e.Speed = NumberRange.new(1, 3)
			e.SpreadAngle = Vector2.new(180, 180)
			e.Size = NumberSequence.new(0.35, 0)
			e.LightEmission = 0.8
			e.Parent = a1
		end
	end

	local head = character:FindFirstChild("Head")
	if head then
		local old = head:FindFirstChild("CT_Vip")
		if old then
			old:Destroy()
		end
		local reward = Progress.activeReward(player)
		local tags = {}
		if reward then
			table.insert(tags, ({ "👑 #1", "🥈 #2", "🥉 #3" })[p.rewardRank])
		end
		if p.passes.VIP then
			table.insert(tags, "VIP")
		end
		if #tags > 0 then
			local bb = Instance.new("BillboardGui")
			bb.Name = "CT_Vip"
			bb.Size = UDim2.fromOffset(110, 26)
			bb.StudsOffset = Vector3.new(0, 2.6, 0)
			bb.MaxDistance = 60
			local l = Instance.new("TextLabel")
			l.BackgroundTransparency = 1
			l.Size = UDim2.fromScale(1, 1)
			l.Font = Enum.Font.FredokaOne
			l.TextScaled = true
			l.Text = table.concat(tags, "  ")
			l.TextColor3 = if reward then Color3.fromRGB(255, 235, 120) else Color3.fromRGB(255, 215, 60)
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
-- Daily ranking
-- Score = levels cleared today x 10,000,000 - total time in tenths of a second,
-- so more levels always wins, and with the same levels the faster time wins.
----------------------------------------------------------------------
local Ranking = require(ReplicatedStorage.Shared.Ranking)

local function store(name: string, ordered: boolean): any
	local ok, result = pcall(function()
		return if ordered then DataStoreService:GetOrderedDataStore(name) else DataStoreService:GetDataStore(name)
	end)
	return if ok then result else nil
end

local function dailyStore(world: string, day: number): OrderedDataStore?
	return store(("Daily_%s_%d"):format(world, day), true)
end

local function pointsStore(): OrderedDataStore?
	return store("Points_All", true)
end

local function totalTime(day: Data.WorldDay): number
	local total = 0
	for level = 1, day.cleared do
		total += day.times[tostring(level)] or 0
	end
	return total
end

-- Called when a player finishes a level. Returns (newLevelToday, bestTime).
function Progress.recordClear(player: Player, world: string, level: number, seconds: number): (boolean, number)
	local p = Data.get(player)
	if not p then
		return false, seconds
	end
	Data.refreshDaily(player)
	local today = p.today
	local wd: Data.WorldDay = (today :: any)[world]
	local key = tostring(level)
	local isNew = false
	if level == wd.cleared + 1 then
		wd.cleared = level
		isNew = true
	end
	local best = wd.times[key]
	if best == nil or seconds < best then
		wd.times[key] = math.floor(seconds * 10 + 0.5) / 10
	end
	-- remember to settle this day's ranking tomorrow
	local listed = false
	for _, entry in p.pending do
		if entry.day == today.day and entry.world == world then
			listed = true
		end
	end
	if not listed then
		table.insert(p.pending, { day = today.day, world = world })
	end
	Data.markDirty(player)

	if wd.cleared > 0 then
		local score = Ranking.encode(wd.cleared, totalTime(wd))
		task.spawn(function()
			local board = dailyStore(world, today.day)
			if board then
				pcall(function()
					board:UpdateAsync(tostring(player.UserId), function(old)
						return math.max(old or 0, score)
					end)
				end)
			end
		end)
	end
	return isNew, wd.times[key]
end

-- Top 100 of a finished day, cached for 10 minutes per server.
local rankCache: { [string]: { at: number, ids: { [number]: number } } } = {}
local function rankOf(world: string, day: number, userId: number): number?
	local cacheKey = world .. day
	local cached = rankCache[cacheKey]
	if not cached or os.clock() - cached.at > 600 then
		local board = dailyStore(world, day)
		if not board then
			return nil
		end
		local ok, pages = pcall(function()
			return board:GetSortedAsync(false, 100)
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

-- Gives points (and top-3 rewards) for days that have ended. Runs when a
-- player joins and every few minutes, so no server needs to be online at midnight.
function Progress.settle(player: Player)
	local p = Data.get(player)
	if not p or #p.pending == 0 then
		return
	end
	local today = Calendar.dayNumber(os.time())
	local remaining = {}
	local gained = 0
	for _, entry in p.pending do
		if entry.day >= today then
			table.insert(remaining, entry)
			continue
		end
		local board = dailyStore(entry.world, entry.day)
		local rank: number? = nil
		if board then
			rank = rankOf(entry.world, entry.day, player.UserId)
		end
		local points = Ranking.pointsFor(rank)
		gained += points
		p.points += points
		Net.send(player, "dailyResult", { world = entry.world, rank = rank, points = points })
		if rank and rank <= #Config.DailyRewards then
			local reward = Config.DailyRewards[rank]
			if p.rewardUntil <= os.time() or rank < p.rewardRank then
				p.rewardRank = rank
			end
			p.rewardUntil = math.max(p.rewardUntil, os.time() + reward.hours * 3600)
			p.equipped = Config.DailyRewards[p.rewardRank].trail
		end
	end
	p.pending = remaining
	Data.markDirty(player)
	Progress.applyCosmetics(player)
	if gained > 0 then
		task.spawn(function()
			local board = pointsStore()
			if board then
				pcall(function()
					board:SetAsync(tostring(player.UserId), p.points)
				end)
			end
		end)
	end
end

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

local formatTime = Ranking.formatTime

-- kind: "solo" / "team" (today's ranking) or "points" (all-time daily points)
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
		solo = "🧍 TODAY · SOLO 🧍\n今日單人排行（關數→時間）",
		team = "🔗 TODAY · TEAM 🔗\n今日組隊排行（關數→時間）",
		points = "⭐ DAILY POINTS · ALL TIME ⭐\n積分總榜",
	}
	local header = row(0, titles[kind] or kind, Color3.fromRGB(255, 215, 80), 0.16)
	header.TextWrapped = true
	local rows = {}
	local medal = { "🥇", "🥈", "🥉" }
	for i = 1, 10 do
		rows[i] = row(i, "", if i <= 3 then Color3.fromRGB(255, 235, 150) else Color3.new(1, 1, 1), 0.08)
	end

	task.spawn(function()
		while true do
			local boardStore = if kind == "points" then pointsStore() else dailyStore(kind, Calendar.dayNumber(os.time()))
			local ok, pages = false, nil
			if boardStore then
				ok, pages = pcall(function()
					return boardStore:GetSortedAsync(false, 10)
				end)
			end
			if ok and pages then
				local entries = (pages :: DataStorePages):GetCurrentPage()
				for i = 1, 10 do
					local e = entries[i]
					if not e then
						rows[i].Text = ""
					elseif kind == "points" then
						rows[i].Text = ("%s %d. %s — %d ⭐"):format(medal[i] or "", i, nameOf(tonumber(e.key) or 0), e.value)
					else
						local cleared, seconds = Ranking.decode(e.value)
						rows[i].Text = ("%s %d. %s — %d/8 · %s"):format(medal[i] or "", i, nameOf(tonumber(e.key) or 0), cleared, formatTime(seconds))
					end
				end
				if #entries == 0 then
					rows[1].Text = "No one yet today — be the first! 今天還沒有人上榜"
				end
			else
				rows[1].Text = "(publish the game to see the leaderboard)"
			end
			task.wait(60)
		end
	end)
end

----------------------------------------------------------------------
-- Player setup
----------------------------------------------------------------------
function Progress.setupLeaderstats(player: Player)
	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	local coins = Instance.new("IntValue")
	coins.Name = "Coins"
	coins.Parent = stats
	local wins = Instance.new("IntValue")
	wins.Name = "Wins"
	wins.Parent = stats
	stats.Parent = player
end

return Progress
