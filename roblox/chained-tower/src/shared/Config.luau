--!strict
-- 綁腳塔 Chained Tower — all tunable numbers live here.
-- After publishing, fill in the Game Pass / Developer Product IDs below.
-- An ID of 0 means "not created yet": in Studio the purchase is granted for free
-- so you can test; in a live server the button shows "Coming soon".

local Config = {}

Config.GameName = "Chained Tower"

----------------------------------------------------------------------
-- Round / tower
----------------------------------------------------------------------
Config.RoundSeconds = 10 * 60 -- the tower rebuilds itself every 10 minutes
Config.SectionsPerTower = 10 -- 2.5 laps around the core
Config.TowerHalfSize = 24 -- corners of the spiral are at (±24, ±24)
Config.TowerBaseY = 4 -- top of the first checkpoint
Config.FallDepth = 18 -- fall this far below your checkpoint = reset
Config.SecondsBetweenResets = 1.5 -- debounce for team resets

----------------------------------------------------------------------
-- Teams and chains
----------------------------------------------------------------------
Config.Modes = {
	solo = { maxPlayers = 1, coinMultiplier = 1.0 },
	duo = { maxPlayers = 2, coinMultiplier = 1.5, chainLength = 12 },
	squad = { maxPlayers = 4, coinMultiplier = 2.0, zoneRadius = 14 },
}
Config.ChainPullStrength = 9 -- how hard a tight chain pulls you back
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

-- Free items every day (UTC). VIP gets the bonus on top.
Config.Daily = {
	unchain = 3,
	smash = 2,
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
Config.OfferSkipAfterFails = 3 -- fail the same section 3 times = offer a skip

----------------------------------------------------------------------
-- Monetization. Prices here are only shown as a fallback; the real price
-- is the one you set on the Creator Dashboard.
----------------------------------------------------------------------
Config.GamePasses = {
	VIP = { id = 0, price = 299 },
	FireTrail = { id = 0, price = 99 },
	LightningTrail = { id = 0, price = 129 },
	GalaxyTrail = { id = 0, price = 199 },
}

-- Developer Products (can be bought again and again)
Config.Products = {
	StarterPack = { id = 0, price = 25, grant = { unchain = 10, smash = 5, trail = "Rainbow" }, oncePerPlayer = true },
	Skip = { id = 0, price = 15, grant = { skip = 1 } },
	Unchain5 = { id = 0, price = 19, grant = { unchain = 5 } },
	Unchain20 = { id = 0, price = 59, grant = { unchain = 20 } },
	Smash3 = { id = 0, price = 25, grant = { smash = 3 } },
	Smash12 = { id = 0, price = 79, grant = { smash = 12 } },
	Coins1000 = { id = 0, price = 49, grant = { coins = 1000 } },
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
