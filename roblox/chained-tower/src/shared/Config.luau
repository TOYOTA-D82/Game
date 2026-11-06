--!strict
-- 綁腳塔 Chained Tower — all tunable numbers live here.
-- After publishing, fill in the Game Pass / Developer Product IDs below.
-- An ID of 0 means "not created yet": in Studio the purchase is granted for free
-- so you can test; in a live server the button shows "Coming soon".

local Config = {}

Config.GameName = "Chained Tower"

----------------------------------------------------------------------
-- Levels (the worlds and their levels live in Themes.luau)
----------------------------------------------------------------------
Config.FallBelowCheckpoint = 25 -- this far below your checkpoint = you fell (chain can't hold you)
Config.SecondsBetweenResets = 1.5 -- debounce for team resets
Config.FirstClearBonus = 20 -- extra coins the first time each day you clear a level (x level number)
-- Testing helper: in Roblox Studio every level is unlocked so you can try them
-- all. Has no effect in the real (published) game.
Config.StudioUnlockAll = true

----------------------------------------------------------------------
-- Daily & weekly points
-- Every day (UTC 00:00 = 08:00 in Taiwan) the routes change and everyone starts
-- again from level 1. You EARN POINTS while you play: checkpoints, level clears
-- (more for harder levels, double for the first clear of the day, extra for a
-- fast time) and every active minute. Daily points reset every day and also
-- add up into weekly points, which reset every Monday. The best players of each
-- day and each week get rewards that only last a day / a week. Rewards are
-- separate from the shop: they can't be bought.
----------------------------------------------------------------------
Config.Points = {
	-- Main source: time. Once you've cleared at least 1 level today, every
	-- minute gives you points - anywhere in the game, even standing still.
	-- How many depends on your FINAL PLACE ON YESTERDAY'S daily board
	-- (first row that fits; not in yesterday's top 100 = perMinuteDefault).
	interval = 60,
	perMinuteByPlace = {
		{ upTo = 1, points = 10 },
		{ upTo = 2, points = 9 },
		{ upTo = 3, points = 8 },
		{ upTo = 10, points = 7 },
		{ upTo = 50, points = 6 },
		{ upTo = 100, points = 5 },
	},
	perMinuteDefault = 4,
	-- Time away also counts: when you come back you get your rank's points
	-- for every minute you were gone, up to offlineMaxMinutes per day (so the
	-- daily ranking isn't just "who left the game open longest").
	offlineMaxMinutes = 8 * 60,
	-- Bonuses on top:
	checkpoint = 5, -- each checkpoint you reach
	clearBase = 20, -- clearing a level: clearBase + clearPerLevel x level
	clearPerLevel = 10,
	firstClearMultiplier = 2, -- first time you clear that level today
	fastBonus = 0.5, -- +50% when you beat the par time
	parSecondsPerSection = { solo = 25, team = 35 },
	modeMultiplier = { solo = 1, duo = 1.2, squad = 1.4 }, -- playing together pays a bit more
}

-- Daily top 3: 24 hours
Config.DailyRewards = {
	{ tag = "👑", trail = "Champion", coinMultiplier = 2, crown = true, hours = 24 }, -- 1st
	{ tag = "🥈", trail = "Silver", coinMultiplier = 1.5, hours = 24 }, -- 2nd
	{ tag = "🥉", trail = "Bronze", coinMultiplier = 1.25, hours = 24 }, -- 3rd
}

-- Weekly top 10: wings for a whole week (rank <= upTo)
-- Daily challenge (每日挑戰): one long, hardest level that changes every day.
-- Points are worked out like a level with this number (much higher than 8),
-- and the 3 fastest times of the day get a title for `titleHours`.
Config.Challenge = {
	pointsLevel = 16,
	coins = 150, -- coins for every clear (x2 the first time today)
	titleHours = 24,
}
Config.ChallengeTitles = {
	{ text = "⚡ 挑戰王 Challenge King ⚡", color = Color3.fromRGB(255, 215, 60) },
	{ text = "⚡ 挑戰亞軍 Challenge #2", color = Color3.fromRGB(215, 225, 240) },
	{ text = "⚡ 挑戰季軍 Challenge #3", color = Color3.fromRGB(230, 150, 90) },
}

Config.WeeklyRewards = {
	{ upTo = 1, wings = "Angel", halo = true, tag = "🏆", hours = 168 },
	{ upTo = 2, wings = "Silver", tag = "🏆", hours = 168 },
	{ upTo = 3, wings = "Bronze", tag = "🏆", hours = 168 },
	{ upTo = 10, wings = "Fairy", tag = "✨", hours = 168 },
}

-- Wing looks (colours of the feathers and of the sparkles)
Config.Wings = {
	Angel = { colors = { Color3.fromRGB(255, 255, 255), Color3.fromRGB(255, 225, 120) }, size = 1.25 },
	Silver = { colors = { Color3.fromRGB(235, 240, 250), Color3.fromRGB(170, 185, 210) }, size = 1.1 },
	Bronze = { colors = { Color3.fromRGB(255, 215, 170), Color3.fromRGB(205, 130, 70) }, size = 1.05 },
	Fairy = { colors = { Color3.fromRGB(170, 255, 245), Color3.fromRGB(200, 150, 255) }, size = 0.8 },
}

----------------------------------------------------------------------
-- Teams and chains
----------------------------------------------------------------------
Config.Modes = {
	solo = { maxPlayers = 1, coinMultiplier = 1.0 },
	duo = { maxPlayers = 2, coinMultiplier = 1.5, chainLength = 12 },
	squad = { maxPlayers = 4, coinMultiplier = 2.0, zoneRadius = 14 },
}
Config.ChainPullStrength = 9 -- how hard a tight chain pulls you back
-- When a teammate hangs off an edge, players still standing get dragged toward
-- the edge at this speed (studs/s). Walking the other way (16 studs/s) beats it
-- and hauls the hanging player back up.
Config.ChainDragSpeed = 3.5
Config.ClimbSpeed = 16 -- hold Jump (or the Climb button) while hanging to climb up the chain
Config.AutoClimbSpeed = 3 -- a hanging player always creeps up slowly, even without pressing anything
Config.ClimbOverBoost = 32 -- when you reach the edge you hop up onto the platform
Config.AllFallSeconds = 2.5 -- the team only resets when NOBODY is standing for this long
-- Lava: one touch sets the chain on fire. It runs to each teammate in turn,
-- then the whole team goes back to the checkpoint.
Config.BurnHopSeconds = 0.3
Config.HardLimitFactor = 2.6 -- stretch past chainLength * this = server reset
Config.SquadMinPlayers = 2 -- squad pad starts with 2+ players after the countdown
Config.SquadCountdown = 10
Config.FullPadCountdown = 3

----------------------------------------------------------------------
-- Items
----------------------------------------------------------------------
Config.UnchainSeconds = 12 -- 解除束縛: the whole team is free for this long
Config.SmashRange = 18 -- 破壞錘: how far in front of you it reaches
Config.SmashMaxParts = 3
Config.SmashRespawnSeconds = 12 -- smashed parts grow back after this long
Config.SpinnerFling = 70 -- how hard a spinner bar knocks you away (sideways speed; up is 70% of it)

-- Free items every day (UTC). VIP gets the bonus on top.
Config.Daily = {
	unchain = 2,
	smash = 1,
	vipBonusUnchain = 2,
	vipBonusSmash = 1,
	premiumBonusUnchain = 1, -- Roblox Premium members also earn you Premium Payouts
}

----------------------------------------------------------------------
-- Coins
----------------------------------------------------------------------
Config.CoinsPerSection = 5
Config.CoinsForFinish = 50
Config.VipCoinMultiplier = 2
Config.OfferSkipAfterFails = 5 -- fail the same section 5 times = a small skip offer slides in at the side

----------------------------------------------------------------------
-- Monetization. Prices here are only shown as a fallback; the real price
-- is the one you set on the Creator Dashboard.
----------------------------------------------------------------------
Config.GamePasses = {
	VIP = { id = 2075960340, price = 299 },
	FireTrail = { id = 2076212318, price = 99 },
	LightningTrail = { id = 2075150326, price = 129 },
	GalaxyTrail = { id = 2075708337, price = 199 },
}

-- Developer Products (can be bought again and again)
Config.Products = {
	StarterPack = { id = 3728715985, price = 25, grant = { unchain = 10, smash = 5, trail = "Rainbow" }, oncePerPlayer = true },
	Skip = { id = 3728716247, price = 15, grant = { skip = 1 } },
	Unchain5 = { id = 3728716467, price = 19, grant = { unchain = 5 } },
	Unchain20 = { id = 3728716620, price = 59, grant = { unchain = 20 } },
	Smash3 = { id = 3728716811, price = 25, grant = { smash = 3 } },
	Smash12 = { id = 3728716951, price = 79, grant = { smash = 12 } },
	Coins1000 = { id = 3728718108, price = 49, grant = { coins = 1000 } },
}

-- The order products appear in the shop
Config.ShopOrder = {
	{ kind = "product", key = "StarterPack" },
	{ kind = "pass", key = "VIP" },
	{ kind = "product", key = "Unchain5" },
	{ kind = "product", key = "Smash3" },
	{ kind = "product", key = "Unchain20" },
	{ kind = "product", key = "Smash12" },
	{ kind = "product", key = "Skip" },
	{ kind = "product", key = "Coins1000" },
}

----------------------------------------------------------------------
-- Trails (跑步特效). source: "free" | "coins" | "pass" | "starter" | "event"
----------------------------------------------------------------------
export type Trail = {
	id: string,
	source: string,
	price: number?,
	pass: string?,
	colors: { Color3 },
	sparkles: boolean?,
	width: number?,
}

Config.Trails = {
	{ id = "Basic", source = "free", colors = { Color3.fromRGB(255, 255, 255), Color3.fromRGB(180, 200, 255) } },
	{ id = "Leaf", source = "coins", price = 250, colors = { Color3.fromRGB(120, 220, 90), Color3.fromRGB(30, 130, 60) } },
	{ id = "Bubble", source = "coins", price = 600, colors = { Color3.fromRGB(150, 230, 255), Color3.fromRGB(255, 150, 230) } },
	{ id = "Gold", source = "coins", price = 2000, colors = { Color3.fromRGB(255, 220, 80), Color3.fromRGB(255, 160, 20) }, sparkles = true },
	{ id = "Rainbow", source = "starter", colors = {
		Color3.fromRGB(255, 70, 70),
		Color3.fromRGB(255, 200, 60),
		Color3.fromRGB(80, 220, 100),
		Color3.fromRGB(70, 160, 255),
		Color3.fromRGB(180, 90, 255),
	} },
	{ id = "Fire", source = "pass", pass = "FireTrail", colors = { Color3.fromRGB(255, 230, 90), Color3.fromRGB(255, 90, 20), Color3.fromRGB(150, 20, 10) }, sparkles = true, width = 1.6 },
	{ id = "Lightning", source = "pass", pass = "LightningTrail", colors = { Color3.fromRGB(255, 255, 255), Color3.fromRGB(110, 200, 255), Color3.fromRGB(40, 70, 255) }, sparkles = true, width = 1.4 },
	{ id = "Galaxy", source = "pass", pass = "GalaxyTrail", colors = { Color3.fromRGB(255, 120, 255), Color3.fromRGB(110, 60, 255), Color3.fromRGB(10, 10, 60) }, sparkles = true, width = 1.8 },
	{ id = "Pumpkin", source = "event", colors = { Color3.fromRGB(255, 140, 20), Color3.fromRGB(90, 30, 120) } },
	{ id = "Snowflake", source = "event", colors = { Color3.fromRGB(255, 255, 255), Color3.fromRGB(150, 220, 255) }, sparkles = true },
	{ id = "Lantern", source = "event", colors = { Color3.fromRGB(255, 60, 40), Color3.fromRGB(255, 210, 60) }, sparkles = true },
	-- daily top-3 rewards: only usable while the 24h reward lasts
	{ id = "Champion", source = "reward", colors = { Color3.fromRGB(255, 240, 120), Color3.fromRGB(255, 120, 200), Color3.fromRGB(120, 220, 255) }, sparkles = true, width = 2 },
	{ id = "Silver", source = "reward", colors = { Color3.fromRGB(255, 255, 255), Color3.fromRGB(170, 185, 210) }, sparkles = true, width = 1.6 },
	{ id = "Bronze", source = "reward", colors = { Color3.fromRGB(255, 200, 150), Color3.fromRGB(200, 120, 60) }, sparkles = true, width = 1.5 },
	{ id = "Heart", source = "event", colors = { Color3.fromRGB(255, 120, 170), Color3.fromRGB(255, 40, 90) } },
} :: { Trail }

----------------------------------------------------------------------
-- Events switch on by themselves on these dates (UTC). No updates needed.
-- dates: fixed month/day every year. lunar: explicit start dates per year.
----------------------------------------------------------------------
export type GameEvent = {
	id: string,
	trail: string,
	accent: Color3,
	from: { number }?, -- { month, day }
	to: { number }?,
	lunarStarts: { [number]: { number } }?, -- year -> { month, day }
	lunarLength: number?,
}

Config.Events = {
	{ id = "Valentine", trail = "Heart", accent = Color3.fromRGB(255, 110, 160), from = { 2, 10 }, to = { 2, 16 } },
	{ id = "Halloween", trail = "Pumpkin", accent = Color3.fromRGB(255, 130, 20), from = { 10, 20 }, to = { 11, 3 } },
	{ id = "Winter", trail = "Snowflake", accent = Color3.fromRGB(140, 210, 255), from = { 12, 15 }, to = { 12, 31 } },
	{
		id = "LunarNewYear",
		trail = "Lantern",
		accent = Color3.fromRGB(230, 40, 40),
		lunarLength = 15,
		lunarStarts = {
			[2027] = { 2, 3 },
			[2028] = { 1, 23 },
			[2029] = { 2, 10 },
			[2030] = { 1, 31 },
			[2031] = { 1, 20 },
			[2032] = { 2, 8 },
			[2033] = { 1, 28 },
			[2034] = { 2, 16 },
			[2035] = { 2, 5 },
			[2036] = { 1, 25 },
		},
	},
} :: { GameEvent }

----------------------------------------------------------------------
-- Daily challenges: 3 are picked automatically each day.
----------------------------------------------------------------------
Config.Challenges = {
	{ id = "sections10", stat = "sections", goal = 10, reward = 60 },
	{ id = "sections25", stat = "sections", goal = 25, reward = 140 },
	{ id = "finish1", stat = "finishes", goal = 1, reward = 80 },
	{ id = "finish3", stat = "finishes", goal = 3, reward = 220 },
	{ id = "teamSections8", stat = "teamSections", goal = 8, reward = 100 },
	{ id = "teamFinish1", stat = "teamFinishes", goal = 1, reward = 150 },
	{ id = "smash2", stat = "smashes", goal = 2, reward = 50 },
	{ id = "unchain2", stat = "unchains", goal = 2, reward = 50 },
}
Config.ChallengesPerDay = 3

return Config
