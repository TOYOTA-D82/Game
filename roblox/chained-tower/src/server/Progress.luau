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
-- Trails and VIP tag
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
		if p.passes.VIP then
			local bb = Instance.new("BillboardGui")
			bb.Name = "CT_Vip"
			bb.Size = UDim2.fromOffset(70, 24)
			bb.StudsOffset = Vector3.new(0, 2.6, 0)
			bb.MaxDistance = 60
			local l = Instance.new("TextLabel")
			l.BackgroundTransparency = 1
			l.Size = UDim2.fromScale(1, 1)
			l.Font = Enum.Font.FredokaOne
			l.TextScaled = true
			l.Text = "👑 VIP"
			l.TextColor3 = Color3.fromRGB(255, 215, 60)
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
-- Weekly leaderboard (resets itself every Monday because the key changes)
----------------------------------------------------------------------
local function weeklyStore(): OrderedDataStore?
	local ok, store = pcall(function()
		return DataStoreService:GetOrderedDataStore("WeeklyWins_" .. Calendar.weekNumber(os.time()))
	end)
	return if ok then store else nil
end

function Progress.recordWin(player: Player)
	task.spawn(function()
		local store = weeklyStore()
		if store then
			pcall(function()
				store:IncrementAsync(tostring(player.UserId), 1)
			end)
		end
	end)
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

function Progress.startLeaderboard(board: SurfaceGui)
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

	local header = row(0, "🏆 WEEKLY TOP CLIMBERS 🏆\n本週通關排行榜", Color3.fromRGB(255, 215, 80), 0.16)
	header.TextWrapped = true
	local rows = {}
	for i = 1, 10 do
		rows[i] = row(i, "", Color3.new(1, 1, 1), 0.08)
	end

	task.spawn(function()
		while true do
			local store = weeklyStore()
			if store then
				local ok, pages = pcall(function()
					return store:GetSortedAsync(false, 10)
				end)
				if ok and pages then
					local entries = (pages :: DataStorePages):GetCurrentPage()
					for i = 1, 10 do
						local e = entries[i]
						rows[i].Text = if e then ("%d. %s — %d"):format(i, nameOf(tonumber(e.key) or 0), e.value) else ""
					end
				end
			else
				rows[1].Text = "(publish the game to see the leaderboard)"
			end
			task.wait(120)
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
