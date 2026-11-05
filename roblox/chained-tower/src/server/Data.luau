--!strict
-- Player save data. Safe by default:
--  * If loading fails we never save (so we can't wipe someone's progress).
--  * Unpublished places / Studio without API access run in memory-only mode.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Calendar = require(game:GetService("ReplicatedStorage").Shared.Calendar)
local Config = require(game:GetService("ReplicatedStorage").Shared.Config)

local Data = {}

export type Profile = {
	coins: number,
	wins: number,
	bestSection: number,
	unchain: number, -- bought / earned stock (never expires)
	smash: number,
	skip: number,
	day: number, -- UTC day the daily values below belong to
	freeUnchain: number,
	freeSmash: number,
	stats: { [string]: number }, -- today's counters for challenges
	claimed: { [string]: boolean }, -- today's claimed challenges
	trails: { [string]: boolean },
	equipped: string,
	passes: { [string]: boolean }, -- remembered in case the ownership check fails later
	starterBought: boolean,
	receipts: { string },
	-- today's daily challenge (reset every UTC day)
	today: { day: number, solo: WorldDay, team: WorldDay },
	points: number, -- daily points earned from rankings, all time
	pending: { { day: number, world: string } }, -- days waiting to be ranked
	rewardRank: number, -- 1..3 while a daily top-3 reward is active
	rewardUntil: number, -- os.time() when it ends
}

-- cleared: levels cleared in order today; times: best time (seconds) per level
export type WorldDay = { cleared: number, times: { [string]: number } }

local function freshDay(day: number)
	return {
		day = day,
		solo = { cleared = 0, times = {} },
		team = { cleared = 0, times = {} },
	}
end
Data.freshDay = freshDay

local function defaults(): Profile
	return {
		coins = 0,
		wins = 0,
		bestSection = 0,
		unchain = 0,
		smash = 0,
		skip = 0,
		day = -1,
		freeUnchain = 0,
		freeSmash = 0,
		stats = {},
		claimed = {},
		trails = { Basic = true },
		equipped = "Basic",
		passes = {},
		starterBought = false,
		receipts = {},
		today = freshDay(-1),
		points = 0,
		pending = {},
		rewardRank = 0,
		rewardUntil = 0,
	}
end

local store: DataStore? = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore("ChainedTower_v1")
	end)
	if ok then
		store = result
	else
		warn("[Data] DataStore unavailable, running without saving:", result)
	end
end

type Session = { profile: Profile, canSave: boolean, dirty: boolean }
local sessions: { [Player]: Session } = {}

local changed = Instance.new("BindableEvent")
Data.Changed = changed.Event -- (player)

local function key(player: Player): string
	return "u_" .. player.UserId
end

local function retry<T>(attempts: number, fn: () -> T): (boolean, T | string)
	local lastErr: any = nil
	for attempt = 1, attempts do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		lastErr = result
		if attempt < attempts then
			task.wait(attempt * 1.5)
		end
	end
	return false, tostring(lastErr)
end

local function reconcile(saved: any): Profile
	local profile = defaults()
	if type(saved) == "table" then
		for k, v in saved do
			if (profile :: any)[k] ~= nil and type(v) == type((profile :: any)[k]) then
				(profile :: any)[k] = v
			end
		end
	end
	profile.trails.Basic = true
	return profile
end

function Data.load(player: Player): Profile?
	local session: Session
	if store == nil then
		session = { profile = defaults(), canSave = false, dirty = false }
	else
		-- unpublished Studio places can't use DataStores: fail fast there
		local attempts = if RunService:IsStudio() then 1 else 3
		local ok, result = retry(attempts, function()
			return (store :: DataStore):GetAsync(key(player))
		end)
		if not ok then
			if RunService:IsStudio() then
				warn("[Data] Load failed in Studio (turn on API access to test saving):", result)
				session = { profile = defaults(), canSave = false, dirty = false }
			else
				player:Kick("Could not load your save. Please rejoin in a minute.")
				return nil
			end
		else
			session = { profile = reconcile(result), canSave = true, dirty = false }
		end
	end
	if player.Parent ~= Players then
		return nil
	end
	sessions[player] = session
	Data.refreshDaily(player)
	return session.profile
end

function Data.get(player: Player): Profile?
	local s = sessions[player]
	return s and s.profile
end

function Data.isVip(player: Player): boolean
	local p = Data.get(player)
	return p ~= nil and p.passes.VIP == true
end

-- Resets free items and challenges when a new UTC day starts.
function Data.refreshDaily(player: Player)
	local p = Data.get(player)
	if not p then
		return
	end
	local today = Calendar.dayNumber(os.time())
	if p.day ~= today then
		p.day = today
		p.freeUnchain = Config.Daily.unchain
		p.freeSmash = Config.Daily.smash
		if p.passes.VIP then
			p.freeUnchain += Config.Daily.vipBonusUnchain
			p.freeSmash += Config.Daily.vipBonusSmash
		end
		if player.MembershipType == Enum.MembershipType.Premium then
			p.freeUnchain += Config.Daily.premiumBonusUnchain
		end
		p.stats = {}
		p.claimed = {}
		p.today = freshDay(today)
		Data.markDirty(player)
	end
end

function Data.markDirty(player: Player)
	local s = sessions[player]
	if s then
		s.dirty = true
		changed:Fire(player)
	end
end

-- Returns true when the data is safely stored (or saving is off in Studio).
function Data.save(player: Player): boolean
	local s = sessions[player]
	if not s then
		return false
	end
	if not s.canSave then
		return store == nil or RunService:IsStudio()
	end
	local snapshot = table.clone(s.profile)
	local ok = retry(3, function()
		return (store :: DataStore):UpdateAsync(key(player), function()
			return snapshot
		end)
	end)
	if ok then
		s.dirty = false
	else
		warn("[Data] Save failed for", player.Name)
	end
	return ok
end

function Data.release(player: Player)
	if sessions[player] then
		Data.save(player)
		sessions[player] = nil
	end
end

function Data.start()
	task.spawn(function()
		while true do
			task.wait(90)
			for player, s in sessions do
				if s.dirty then
					task.spawn(Data.save, player)
				end
			end
		end
	end)
	-- new day while playing
	task.spawn(function()
		while true do
			task.wait(60)
			for player in sessions do
				Data.refreshDaily(player)
			end
		end
	end)
	game:BindToClose(function()
		local pending = 0
		for player in sessions do
			pending += 1
			task.spawn(function()
				Data.save(player)
				pending -= 1
			end)
		end
		local started = os.clock()
		while pending > 0 and os.clock() - started < 25 do
			task.wait(0.1)
		end
	end)
end

return Data
