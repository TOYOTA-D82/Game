--!strict
-- The two worlds and their 8 levels each. A level keeps its look (sky, colours,
-- scenery) forever, but its route is rebuilt EVERY DAY from its pool of section
-- types — same on every server, so it's a fair daily challenge with no updates.
--
--   solo world "Sky Isles"   : Meadow, Desert, Ice, Candy, Space, Beach, Cave, Clouds
--   team world "Chain Isles" : Jungle, Volcano, Harbor, Factory, Castle, Snow, Pirate, Neon

local Themes = {}

export type Sky = {
	clock: number, -- time of day
	brightness: number,
	ambient: Color3,
	atmosphere: Color3,
	density: number,
	haze: number,
}

export type Theme = {
	id: string,
	world: string, -- "solo" | "team"
	level: number,
	seed: number,
	pool: { string }, -- section types this level picks from each day
	diff: { number }, -- difficulty for the first and second half of the course
	lava: boolean, -- lava under hazards (otherwise it's an open drop)
	slippery: boolean?, -- icy floors
	gravity: number?, -- default 196.2
	colors: { Color3 }, -- platform colours, cycled per section
	material: Enum.Material,
	checkpoint: Color3,
	pad: Color3, -- jump pads / mushrooms
	sky: Sky,
	floor: { color: Color3, material: Enum.Material, transparency: number? }?,
	decor: string,
	-- the big thing in the middle you climb around, and what waits at the top
	landmark: {
		shape: string, -- "taper" (mountain, pyramid, cake) or "column" (tower, lighthouse, station)
		round: boolean,
		colors: { Color3 },
		material: Enum.Material,
		cap: Color3?, -- snow cap / icing / lava glow on top of a taper
		goal: string, -- "flag" | "station" | "beacon" | "crown"
	},
}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

Themes.Worlds = {
	solo = {
		lane = 5, -- half width of the path
		checkpoint = 5, -- half size of a checkpoint pad
		section = 48, -- length of one section (pad centre to pad centre)
		widthScale = 1,
		origin = { 3000, 150, 0 }, -- world hub
	},
	team = {
		lane = 7, -- wider: two or four chained players need room
		checkpoint = 7,
		section = 52, -- a bit longer so the bigger pads don't squeeze the obstacles
		widthScale = 1.4,
		origin = { -3000, 150, 0 },
	},
}

local list: { Theme } = {
	----------------------------------------------------------------
	-- SOLO
	----------------------------------------------------------------
	{
		id = "Meadow",
		world = "solo",
		level = 1,
		seed = 1101,
		diff = { 1, 1 },
		pool = { "Stones", "JumpPads", "Beams", "Mover", "Climb", "Truss" },
		lava = false,
		colors = { rgb(120, 200, 90), rgb(150, 215, 100), rgb(240, 220, 120), rgb(110, 185, 120) },
		material = Enum.Material.Grass,
		checkpoint = rgb(255, 255, 255),
		pad = rgb(255, 90, 90),
		sky = { clock = 14, brightness = 2.4, ambient = rgb(150, 160, 170), atmosphere = rgb(200, 230, 255), density = 0.22, haze = 1 },
		floor = { color = rgb(90, 170, 80), material = Enum.Material.Grass },
		decor = "trees",
		landmark = { shape = "taper", round = true, colors = { rgb(120, 110, 100), rgb(150, 140, 125) }, material = Enum.Material.Rock, cap = rgb(250, 250, 255), goal = "flag" },
	},
	{
		id = "Desert",
		world = "solo",
		level = 2,
		seed = 2202,
		diff = { 1, 2 },
		pool = { "Stones", "Conveyor", "Mover", "Pillars", "Climb", "Spinner" },
		lava = false,
		colors = { rgb(235, 200, 140), rgb(220, 175, 115), rgb(245, 215, 160) },
		material = Enum.Material.Sandstone,
		checkpoint = rgb(255, 240, 200),
		pad = rgb(80, 200, 120),
		sky = { clock = 16.8, brightness = 2.6, ambient = rgb(170, 140, 110), atmosphere = rgb(255, 205, 150), density = 0.3, haze = 2 },
		floor = { color = rgb(230, 195, 130), material = Enum.Material.Sand },
		decor = "cacti",
		landmark = { shape = "taper", round = false, colors = { rgb(225, 190, 130), rgb(240, 210, 150) }, material = Enum.Material.Sandstone, goal = "flag" },
	},
	{
		id = "Ice",
		world = "solo",
		level = 3,
		seed = 3303,
		diff = { 2, 2 },
		pool = { "Stones", "Mover", "Vanish", "Climb", "Barricade", "Beams" },
		lava = false,
		slippery = true,
		colors = { rgb(190, 230, 255), rgb(160, 210, 245), rgb(225, 245, 255) },
		material = Enum.Material.Ice,
		checkpoint = rgb(255, 255, 255),
		pad = rgb(120, 220, 255),
		sky = { clock = 12, brightness = 2.2, ambient = rgb(170, 190, 210), atmosphere = rgb(225, 240, 255), density = 0.38, haze = 2.5 },
		floor = { color = rgb(245, 250, 255), material = Enum.Material.Snow },
		decor = "crystals",
		landmark = { shape = "taper", round = true, colors = { rgb(160, 210, 240), rgb(210, 235, 255) }, material = Enum.Material.Glacier, cap = rgb(255, 255, 255), goal = "flag" },
	},
	{
		id = "Candy",
		world = "solo",
		level = 4,
		seed = 4404,
		diff = { 2, 3 },
		pool = { "JumpPads", "Spinner", "Vanish", "Mover", "Beams", "Barricade" },
		lava = false,
		colors = { rgb(255, 150, 200), rgb(150, 235, 210), rgb(255, 230, 120), rgb(200, 160, 255) },
		material = Enum.Material.SmoothPlastic,
		checkpoint = rgb(255, 255, 255),
		pad = rgb(255, 80, 160),
		sky = { clock = 15, brightness = 2.5, ambient = rgb(200, 160, 190), atmosphere = rgb(255, 200, 230), density = 0.3, haze = 1.5 },
		floor = { color = rgb(255, 190, 220), material = Enum.Material.SmoothPlastic },
		decor = "candy",
		landmark = { shape = "taper", round = true, colors = { rgb(255, 170, 210), rgb(255, 240, 200) }, material = Enum.Material.SmoothPlastic, cap = rgb(255, 80, 120), goal = "flag" },
	},
	{
		id = "Space",
		world = "solo",
		level = 5,
		seed = 5505,
		diff = { 2, 3 },
		pool = { "Asteroids", "Mover", "Spinner", "Vanish", "JumpPads", "Detour" },
		lava = false,
		gravity = 110, -- floaty jumps
		colors = { rgb(90, 80, 160), rgb(60, 60, 120), rgb(120, 90, 200) },
		material = Enum.Material.Metal,
		checkpoint = rgb(120, 255, 220),
		pad = rgb(80, 255, 200),
		sky = { clock = 0, brightness = 1, ambient = rgb(110, 90, 160), atmosphere = rgb(40, 30, 80), density = 0.18, haze = 0 },
		floor = nil,
		decor = "planets",
		landmark = { shape = "column", round = true, colors = { rgb(170, 175, 190), rgb(90, 220, 255) }, material = Enum.Material.Metal, goal = "station" },
	},
	----------------------------------------------------------------
	-- TEAM
	----------------------------------------------------------------
	{
		id = "Jungle",
		world = "team",
		level = 1,
		seed = 1111,
		diff = { 1, 1 },
		pool = { "Stones", "Rapids", "JumpPads", "Climb", "Truss", "Mover" },
		lava = false,
		colors = { rgb(110, 160, 70), rgb(140, 110, 70), rgb(90, 140, 80) },
		material = Enum.Material.WoodPlanks,
		checkpoint = rgb(255, 230, 120),
		pad = rgb(230, 70, 70),
		sky = { clock = 10, brightness = 2, ambient = rgb(120, 150, 110), atmosphere = rgb(190, 230, 180), density = 0.35, haze = 2 },
		floor = { color = rgb(60, 140, 120), material = Enum.Material.Glass, transparency = 0.2 },
		decor = "jungle",
		landmark = { shape = "column", round = true, colors = { rgb(110, 80, 55), rgb(70, 150, 70) }, material = Enum.Material.Wood, goal = "flag" },
	},
	{
		id = "Volcano",
		world = "team",
		level = 2,
		seed = 2222,
		diff = { 1, 2 },
		pool = { "LavaPlanks", "Stones", "Mover", "Pillars", "Climb", "Vanish" },
		lava = true,
		colors = { rgb(80, 70, 70), rgb(110, 90, 80), rgb(60, 55, 60) },
		material = Enum.Material.Basalt,
		checkpoint = rgb(255, 210, 120),
		pad = rgb(255, 140, 40),
		sky = { clock = 18.6, brightness = 1.8, ambient = rgb(170, 90, 70), atmosphere = rgb(255, 120, 80), density = 0.4, haze = 2 },
		floor = { color = rgb(255, 90, 20), material = Enum.Material.CrackedLava },
		decor = "rocks",
		landmark = { shape = "taper", round = true, colors = { rgb(70, 55, 55), rgb(100, 75, 65) }, material = Enum.Material.Basalt, cap = rgb(255, 100, 20), goal = "flag" },
	},
	{
		id = "Harbor",
		world = "team",
		level = 3,
		seed = 3333,
		diff = { 2, 2 },
		pool = { "Rapids", "Mover", "Detour", "Conveyor", "Beams", "Climb" },
		lava = false,
		colors = { rgb(170, 120, 80), rgb(150, 100, 65), rgb(190, 140, 95) },
		material = Enum.Material.WoodPlanks,
		checkpoint = rgb(255, 255, 255),
		pad = rgb(255, 200, 60),
		sky = { clock = 13, brightness = 2.4, ambient = rgb(140, 160, 190), atmosphere = rgb(180, 215, 255), density = 0.25, haze = 1 },
		floor = { color = rgb(40, 110, 200), material = Enum.Material.Glass, transparency = 0.1 },
		decor = "harbor",
		landmark = { shape = "column", round = true, colors = { rgb(245, 245, 245), rgb(40, 90, 200) }, material = Enum.Material.SmoothPlastic, goal = "beacon" },
	},
	{
		id = "Factory",
		world = "team",
		level = 4,
		seed = 4444,
		diff = { 2, 3 },
		pool = { "Conveyor", "Spinner", "Mover", "Detour", "Barricade", "Vanish" },
		lava = false,
		colors = { rgb(120, 125, 135), rgb(95, 100, 110), rgb(150, 150, 160) },
		material = Enum.Material.DiamondPlate,
		checkpoint = rgb(255, 210, 60),
		pad = rgb(255, 210, 60),
		sky = { clock = 18, brightness = 1.6, ambient = rgb(120, 115, 110), atmosphere = rgb(170, 160, 150), density = 0.42, haze = 2.5 },
		floor = { color = rgb(50, 50, 55), material = Enum.Material.Metal },
		decor = "factory",
		landmark = { shape = "column", round = true, colors = { rgb(120, 70, 55), rgb(90, 90, 95) }, material = Enum.Material.Brick, goal = "beacon" },
	},
	{
		id = "Castle",
		world = "team",
		level = 5,
		seed = 5555,
		diff = { 2, 3 },
		pool = { "Spinner", "Detour", "Rapids", "Barricade", "Mover", "LavaPlanks", "Climb" },
		lava = true,
		colors = { rgb(120, 115, 130), rgb(100, 95, 115), rgb(140, 130, 150) },
		material = Enum.Material.Cobblestone,
		checkpoint = rgb(200, 160, 255),
		pad = rgb(180, 100, 255),
		sky = { clock = 21, brightness = 1.2, ambient = rgb(110, 90, 150), atmosphere = rgb(90, 70, 140), density = 0.35, haze = 1.5 },
		floor = { color = rgb(70, 60, 90), material = Enum.Material.Slate },
		decor = "castle",
		landmark = { shape = "column", round = true, colors = { rgb(130, 125, 140), rgb(110, 60, 160) }, material = Enum.Material.Cobblestone, goal = "flag" },
	},
	----------------------------------------------------------------
	-- SOLO 6-8
	----------------------------------------------------------------
	{
		id = "Beach",
		world = "solo",
		level = 6,
		seed = 6606,
		diff = { 3, 3 },
		pool = { "Stones", "Rapids", "Mover", "JumpPads", "Barricade", "Beams", "Climb" },
		lava = false,
		colors = { rgb(245, 225, 170), rgb(120, 220, 230), rgb(255, 190, 150) },
		material = Enum.Material.Sand,
		checkpoint = rgb(255, 255, 255),
		pad = rgb(255, 120, 90),
		sky = { clock = 15.5, brightness = 2.8, ambient = rgb(170, 180, 190), atmosphere = rgb(190, 235, 255), density = 0.2, haze = 1 },
		floor = { color = rgb(40, 170, 220), material = Enum.Material.Glass, transparency = 0.1 },
		decor = "palms",
		landmark = { shape = "column", round = true, colors = { rgb(245, 245, 245), rgb(220, 60, 60) }, material = Enum.Material.SmoothPlastic, goal = "beacon" },
	},
	{
		id = "Cave",
		world = "solo",
		level = 7,
		seed = 7707,
		diff = { 3, 3 },
		pool = { "Pillars", "Vanish", "Truss", "Spinner", "Climb", "Detour" },
		lava = false,
		colors = { rgb(110, 90, 150), rgb(70, 130, 140), rgb(130, 110, 170) },
		material = Enum.Material.Slate,
		checkpoint = rgb(140, 255, 230),
		pad = rgb(120, 255, 220),
		sky = { clock = 3, brightness = 1, ambient = rgb(120, 90, 160), atmosphere = rgb(60, 40, 90), density = 0.45, haze = 1 },
		floor = { color = rgb(40, 30, 55), material = Enum.Material.Slate },
		decor = "crystals",
		landmark = { shape = "column", round = false, colors = { rgb(90, 70, 130), rgb(140, 255, 230) }, material = Enum.Material.Slate, goal = "beacon" },
	},
	{
		id = "Clouds",
		world = "solo",
		level = 8,
		seed = 8808,
		diff = { 3, 3 },
		pool = { "JumpPads", "Mover", "Vanish", "Spinner", "Asteroids", "Barricade" },
		lava = false,
		colors = { rgb(255, 255, 255), rgb(255, 230, 150), rgb(230, 235, 255) },
		material = Enum.Material.SmoothPlastic,
		checkpoint = rgb(255, 215, 90),
		pad = rgb(255, 200, 60),
		sky = { clock = 6.8, brightness = 2.4, ambient = rgb(200, 170, 170), atmosphere = rgb(255, 210, 200), density = 0.3, haze = 2 },
		floor = nil,
		decor = "clouds",
		landmark = { shape = "column", round = true, colors = { rgb(250, 245, 235), rgb(255, 210, 110) }, material = Enum.Material.Marble, goal = "crown" },
	},
	----------------------------------------------------------------
	-- TEAM 6-8
	----------------------------------------------------------------
	{
		id = "Snow",
		world = "team",
		level = 6,
		seed = 6666,
		diff = { 3, 3 },
		pool = { "Stones", "Mover", "Vanish", "Truss", "Barricade", "Conveyor", "Climb" },
		lava = false,
		slippery = true,
		colors = { rgb(235, 245, 255), rgb(200, 225, 245), rgb(170, 200, 230) },
		material = Enum.Material.Snow,
		checkpoint = rgb(255, 120, 120),
		pad = rgb(255, 120, 120),
		sky = { clock = 11, brightness = 2.3, ambient = rgb(180, 190, 210), atmosphere = rgb(235, 240, 255), density = 0.42, haze = 2.5 },
		floor = { color = rgb(250, 252, 255), material = Enum.Material.Snow },
		decor = "pines",
		landmark = { shape = "taper", round = true, colors = { rgb(130, 135, 150), rgb(170, 175, 190) }, material = Enum.Material.Rock, cap = rgb(255, 255, 255), goal = "flag" },
	},
	{
		id = "Pirate",
		world = "team",
		level = 7,
		seed = 7777,
		diff = { 3, 3 },
		pool = { "Rapids", "Mover", "Detour", "Spinner", "Barricade", "Beams" },
		lava = false,
		colors = { rgb(110, 75, 50), rgb(140, 95, 60), rgb(90, 60, 40) },
		material = Enum.Material.WoodPlanks,
		checkpoint = rgb(255, 215, 90),
		pad = rgb(255, 80, 80),
		sky = { clock = 18.2, brightness = 1.9, ambient = rgb(170, 120, 100), atmosphere = rgb(255, 170, 120), density = 0.3, haze = 1.5 },
		floor = { color = rgb(30, 90, 160), material = Enum.Material.Glass, transparency = 0.1 },
		decor = "harbor",
		landmark = { shape = "column", round = true, colors = { rgb(120, 85, 55), rgb(245, 240, 225) }, material = Enum.Material.WoodPlanks, goal = "flag" },
	},
	{
		id = "Neon",
		world = "team",
		level = 8,
		seed = 8888,
		diff = { 3, 3 },
		pool = { "Conveyor", "Spinner", "Mover", "LavaPlanks", "Vanish", "Detour", "Barricade" },
		lava = true,
		colors = { rgb(40, 40, 60), rgb(55, 45, 80), rgb(30, 50, 70) },
		material = Enum.Material.SmoothPlastic,
		checkpoint = rgb(80, 255, 255),
		pad = rgb(255, 80, 220),
		sky = { clock = 22, brightness = 1.1, ambient = rgb(120, 90, 170), atmosphere = rgb(70, 40, 120), density = 0.3, haze = 1 },
		floor = { color = rgb(20, 15, 35), material = Enum.Material.SmoothPlastic },
		decor = "neon",
		landmark = { shape = "column", round = false, colors = { rgb(30, 30, 50), rgb(255, 60, 200) }, material = Enum.Material.Glass, goal = "beacon" },
	},
}

Themes.List = list

local byId: { [string]: Theme } = {}
for _, t in list do
	byId[t.id] = t
end
Themes.ById = byId

function Themes.forLevel(world: string, level: number): Theme?
	for _, t in list do
		if t.world == world and t.level == level then
			return t
		end
	end
	return nil
end

-- Later levels are longer: 4 sections at level 1-2, 5 at 3-5, 6 at 6+.
function Themes.sectionCount(level: number): number
	return if level <= 2 then 4 elseif level <= 5 then 5 else 6
end

function Themes.levelCount(world: string): number
	local n = 0
	for _, t in list do
		if t.world == world then
			n += 1
		end
	end
	return n
end

-- Sky used in the hubs between levels
Themes.HubSky = {
	main = { clock = 14.5, brightness = 2.2, ambient = rgb(150, 150, 170), atmosphere = rgb(200, 220, 255), density = 0.25, haze = 1 },
	solo = { clock = 9, brightness = 2.4, ambient = rgb(160, 180, 210), atmosphere = rgb(190, 225, 255), density = 0.3, haze = 1.5 },
	team = { clock = 17.5, brightness = 2, ambient = rgb(170, 130, 180), atmosphere = rgb(230, 180, 230), density = 0.3, haze = 1.5 },
} :: { [string]: Sky }

return Themes
