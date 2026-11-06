--!strict
-- Pure course layout: turns a theme (+ seed) into a list of boxes. No Roblox
-- instances, so the tests can build thousands of courses and prove each one is
-- beatable WITHOUT buying anything.
--
-- A course is a journey to a goal (a mountain top, a space station...). The
-- route wanders across a grid: each section goes from one checkpoint to the
-- next, going straight or turning left/right, up or down, and passes through
-- set pieces (tunnels, rooftops, shafts, arches...). The route never crosses
-- itself. Inside a section we use local coordinates:
--   z: forward, 0 = start checkpoint, SECTION = end checkpoint
--   x: sideways, -lane..lane is the path (+ = right-hand side)
--   y: height above the start pad

local Themes = require(script.Parent.Themes)

local Course = {}

export type Rng = {
	NextInteger: (self: any, min: number, max: number) -> number,
	NextNumber: (self: any, min: number, max: number) -> number,
}

-- Our own small random generator, so the game and the tests build exactly the
-- same levels from the same seed (Roblox's Random isn't available outside Roblox).
function Course.rng(seed: number): Rng
	local state = math.floor(seed) % 2147483647
	if state <= 0 then
		state += 2147483646
	end
	local function nextFloat(): number
		state = (state * 48271) % 2147483647
		return state / 2147483647
	end
	return {
		NextInteger = function(_, a: number, b: number): number
			return a + math.floor(nextFloat() * (b - a + 1))
		end,
		NextNumber = function(_, a: number, b: number): number
			return a + nextFloat() * (b - a)
		end,
	}
end

export type Piece = {
	kind: string, -- platform | checkpoint | win | kill | breakable | truss | pad | vanish | spinner | pivot | current | mover | floor
	section: number,
	cx: number,
	cy: number,
	cz: number,
	sx: number,
	sy: number,
	sz: number,
	index: number?, -- checkpoint number
	boost: number?, -- jump pad upward speed
	spinSpeed: number?, -- spinner angular speed (rad/s)
	flowX: number?, -- water current / conveyor: push direction and speed
	flowZ: number?,
	flowSpeed: number?,
	style: string?, -- "water" | "belt"
	travel: number?, -- mover: distance it slides back and forth
	period: number?, -- mover: seconds for a full back-and-forth
	moveX: number?, -- mover / sweeper: direction it slides (world)
	moveZ: number?,
}

export type Surface = {
	id: number,
	minX: number,
	maxX: number,
	minZ: number,
	maxZ: number,
	top: number,
	section: number,
	kind: string,
}

export type Box = { minX: number, maxX: number, minY: number, maxY: number, minZ: number, maxZ: number }

export type Result = {
	theme: Themes.Theme,
	seed: number,
	pieces: { Piece },
	surfaces: { Surface },
	links: { { number } },
	blockers: { Box },
	checkpoints: { { number } }, -- [index + 1] = { x, topY, z }
	startSurface: number,
	winSurface: number,
	builders: { string },
	walls: { number }, -- heights of the smashable walls (tests check you can't just jump them)
	roofs: { { minX: number, maxX: number, minZ: number, maxZ: number, bottom: number, section: number } }, -- ceilings (tests check headroom)
	movers: { { gapBefore: number, gapAfter: number, size: number } },
	sweepers: { { height: number, low: boolean } }, -- walls that slide at you (low = jump over)
	detours: { number }, -- how many extra hops the long way round a smashable wall takes
	minWidth: number, -- narrowest standable thing (tests check it's not too thin)
	bottom: number, -- lowest point of the course
	top: number, -- highest point of the course
	finishDir: { number }, -- direction of the last section (the goal landmark sits beyond it)
	nodes: { { number } }, -- grid cell of every checkpoint (tests check the route never crosses itself)
	mode: string, -- "journey" (wander across the map) or "tower" (spiral up around a landmark)
	center: { number }, -- tower mode: x, z of the landmark in the middle
	coreHalf: number, -- tower mode: half size of the landmark's square
}

Course.Thickness = 2 -- platforms are chunky, not thin slabs

-- Jump rules used by the builders AND the tests (Roblox default character:
-- JumpHeight 7.2, WalkSpeed 16 -> ~8 stud jumps; we stay well inside that).
Course.MaxGap = 5
Course.MaxRise = 3
Course.MaxDropGap = 6

----------------------------------------------------------------------
-- Section builder context
----------------------------------------------------------------------
type Ctx = {
	rng: Rng,
	diff: number,
	section: number,
	cx: number, -- world position of this section's start corner
	cz: number,
	dx: number, -- world direction of local +z (along the side)
	dz: number,
	ux: number, -- world direction of local +x (away from the landmark)
	uz: number,
	oy: number,
	minRise: number,
	freeSide: number, -- which side (+1 right / -1 left) has room for a detour loop
	lane: number,
	widthScale: number,
	z0: number, -- where section content starts / ends (pads take the rest)
	z1: number,
	theme: Themes.Theme,
	out: Result,
	rise: number,
}

local function toWorld(ctx: Ctx, x: number, z: number): (number, number)
	return ctx.cx + ctx.dx * z + ctx.ux * x, ctx.cz + ctx.dz * z + ctx.uz * x
end

local function add(ctx: Ctx, kind: string, minX: number, maxX: number, minY: number, maxY: number, minZ: number, maxZ: number): Piece
	local ax, az = toWorld(ctx, minX, minZ)
	local bx, bz = toWorld(ctx, maxX, maxZ)
	local piece: Piece = {
		kind = kind,
		section = ctx.section,
		cx = (ax + bx) / 2,
		cy = ctx.oy + (minY + maxY) / 2,
		cz = (az + bz) / 2,
		sx = math.abs(bx - ax),
		sy = maxY - minY,
		sz = math.abs(bz - az),
	}
	table.insert(ctx.out.pieces, piece)
	return piece
end

local function addSurface(out: Result, piece: Piece, kind: string): number
	local id = #out.surfaces + 1
	table.insert(out.surfaces, {
		id = id,
		minX = piece.cx - piece.sx / 2,
		maxX = piece.cx + piece.sx / 2,
		minZ = piece.cz - piece.sz / 2,
		maxZ = piece.cz + piece.sz / 2,
		top = piece.cy + piece.sy / 2,
		section = piece.section,
		kind = kind,
	})
	out.minWidth = math.min(out.minWidth, piece.sx, piece.sz)
	return id
end

local function platform(ctx: Ctx, minX: number, maxX: number, minZ: number, maxZ: number, top: number, kind: string?): (number, Piece)
	local k = kind or "platform"
	local piece = add(ctx, k, minX, maxX, top - Course.Thickness, top, minZ, maxZ)
	return addSurface(ctx.out, piece, k), piece
end

local function blocker(ctx: Ctx, piece: Piece)
	table.insert(ctx.out.blockers, {
		minX = piece.cx - piece.sx / 2,
		maxX = piece.cx + piece.sx / 2,
		minY = piece.cy - piece.sy / 2,
		maxY = piece.cy + piece.sy / 2,
		minZ = piece.cz - piece.sz / 2,
		maxZ = piece.cz + piece.sz / 2,
	})
end

local function link(ctx: Ctx, from: number, to: number)
	table.insert(ctx.out.links, { from, to })
end

local function pickRise(ctx: Ctx, low: number, high: number): number
	return math.max(ctx.rng:NextInteger(low, high), ctx.minRise)
end

-- Smashable walls are taller than anyone can jump (even in low gravity).
local function wallHeight(ctx: Ctx): number
	local jump = 7.2 * 196.2 / (ctx.theme.gravity or 196.2)
	return math.ceil(jump + 3.5)
end

local function w(ctx: Ctx, base: number): number
	return math.min(base * ctx.widthScale, ctx.lane * 2)
end

type RunOpts = {
	size: number?, -- length along z
	width: number?, -- width along x
	maxGap: number?,
	maxRise: number?,
	zigzag: number?, -- alternate x = ±zigzag instead of random jitter
	kind: string?,
	pillar: boolean?, -- extend platforms down into tall pillars
	depth: number?, -- how far pillars go down (default 6)
	extra: number?, -- add up to this many extra hops
}

type Hop = { x: number, near: number, far: number, top: number, width: number }

-- Fill the space between zFrom (far edge of what came before) and zTo (near edge
-- of what comes next) with hops climbing from yFrom to yTo. Built so every gap
-- is <= maxGap and every rise <= maxRise, which keeps it beatable by design.
local function run(ctx: Ctx, zFrom: number, zTo: number, yFrom: number, yTo: number, opts: RunOpts?): { Hop }
	local hops: { Hop } = {}
	local o: RunOpts = opts or {}
	local size = o.size or 5
	local width = math.min(o.width or size, ctx.lane * 2)
	local maxGap = math.min(o.maxGap or 4, Course.MaxGap)
	local maxRise = math.min(o.maxRise or 2.5, Course.MaxRise - 0.5)
	local length = zTo - zFrom
	local dy = yTo - yFrom
	if length <= 0 then
		return hops
	end

	local n = math.max(0, math.ceil((length - maxGap) / (size + maxGap)))
	if dy > 0 then
		n = math.max(n, math.ceil(dy / maxRise) - 1)
	end
	if n > 0 and o.extra and o.extra > 0 then
		local spare = math.floor((length - n * size) / (size + 1.5)) - n
		if spare > 0 then
			n += ctx.rng:NextInteger(0, math.min(o.extra, spare))
		end
	end
	if n == 0 then
		return hops
	end

	local s = size
	if n * s > length - (n + 1) * 1 then
		s = math.max(2.5, (length - (n + 1)) / n)
	end
	local gap = (length - n * s) / (n + 1)
	local jitter = math.max(0, math.min(ctx.lane - width / 2, width * 0.4))
	for i = 1, n do
		local near = zFrom + gap * i + s * (i - 1)
		local top = yFrom + dy * i / (n + 1)
		local x
		if o.zigzag then
			local zig = math.min(o.zigzag, ctx.lane - width / 2)
			x = if i % 2 == 0 then zig else -zig
		else
			x = ctx.rng:NextNumber(-jitter, jitter)
		end
		local k = o.kind or "platform"
		table.insert(hops, { x = x, near = near, far = near + s, top = top, width = width })
		if o.pillar then
			local piece = add(ctx, k, x - width / 2, x + width / 2, top - (o.depth or (6 + top)), top, near, near + s)
			addSurface(ctx.out, piece, k)
		else
			platform(ctx, x - width / 2, x + width / 2, near, near + s, top, k)
		end
	end
	return hops
end

-- Water (or a conveyor belt) that pushes you along (fx, fz).
local function stream(ctx: Ctx, minZ: number, maxZ: number, top: number, speed: number, fx: number, fz: number, style: string)
	local id, piece = platform(ctx, -ctx.lane, ctx.lane, minZ, maxZ, top, "current")
	-- local (sideways fx, forward fz) -> world direction
	piece.flowX = ctx.dx * fz + ctx.ux * fx
	piece.flowZ = ctx.dz * fz + ctx.uz * fx
	piece.flowSpeed = speed
	piece.style = style
	return id
end

-- Lava under a stretch of the course (only in lava themes; elsewhere a fall is a fall).
local function lava(ctx: Ctx, zFrom: number, zTo: number)
	if ctx.theme.lava then
		add(ctx, "kill", -ctx.lane, ctx.lane + 2, -4, -3, zFrom, zTo) -- not under the landmark
	end
end

----------------------------------------------------------------------
-- Section types. Each sets ctx.rise and ends with a hop reachable from the
-- end pad (z = z1, top = ctx.rise).
----------------------------------------------------------------------
-- maxRise: the most a section type can climb (used to keep laps tall enough)
type Builder = { name: string, minDiff: number, maxRise: number, build: (ctx: Ctx) -> () }

local builders: { [string]: Builder } = {}
local function builder(name: string, minDiff: number, maxRise: number, build: (ctx: Ctx) -> ())
	builders[name] = { name = name, minDiff = minDiff, maxRise = maxRise, build = build }
end

builder("Stones", 1, 20, function(ctx)
	ctx.rise = pickRise(ctx, 6, 8)
	local size = w(ctx, ({ 6, 5.5, 5 })[ctx.diff])
	run(ctx, ctx.z0, ctx.z1, 0, ctx.rise, { size = size, maxGap = 3.5 + ctx.diff * 0.5, extra = 1 })
end)

builder("LavaPlanks", 1, 16, function(ctx)
	ctx.rise = pickRise(ctx, 6, 7)
	lava(ctx, ctx.z0, ctx.z1)
	run(ctx, ctx.z0, ctx.z1, 0, ctx.rise, { size = 4.5, width = w(ctx, 4), maxGap = 3.5 + ctx.diff * 0.5 })
end)

builder("Beams", 1, 14, function(ctx)
	ctx.rise = pickRise(ctx, 6, 8)
	local width = w(ctx, ({ 3.6, 3.3, 3 })[ctx.diff])
	run(ctx, ctx.z0, ctx.z1, 0, ctx.rise, { size = 8 - ctx.diff, width = width, zigzag = 2, maxGap = 2 + ctx.diff * 0.5, maxRise = 2.5 })
end)

builder("JumpPads", 1, 16, function(ctx)
	platform(ctx, -ctx.lane, ctx.lane, ctx.z0 + 1, 12, 1)
	local padId, pad = platform(ctx, -3.5, 3.5, 12, 16, 1, "pad")
	pad.boost = 64 -- ~10 studs up
	local upId = platform(ctx, -ctx.lane, ctx.lane, 15, 23, 9)
	link(ctx, padId, upId)
	ctx.rise = pickRise(ctx, 9, 10)
	run(ctx, 23, ctx.z1, 9, ctx.rise, { size = w(ctx, 5.5), maxGap = 3.5 + ctx.diff * 0.5 })
end)

builder("Truss", 1, 18, function(ctx)
	local floorId = platform(ctx, -ctx.lane, ctx.lane, ctx.z0, 14, 0)
	add(ctx, "truss", -1, 1, 0, 12, 14, 16)
	local upId = platform(ctx, -ctx.lane, ctx.lane, 16, 26, 12)
	link(ctx, floorId, upId)
	ctx.rise = pickRise(ctx, 12, 13)
	run(ctx, 26, ctx.z1, 12, ctx.rise, { size = w(ctx, 5.5), maxGap = 3.5 + ctx.diff * 0.5 })
end)

-- A platform sliding back and forth over a wide gap. Ride it across.
builder("Mover", 1, 6, function(ctx)
	local size = w(ctx, 7)
	local aId = platform(ctx, -ctx.lane, ctx.lane, ctx.z0, 12, 1)
	local gapStart, gapEnd = 12, 30
	lava(ctx, gapStart, gapEnd)
	local travel = (gapEnd - gapStart) - size - 2 -- leaves 1 stud at each end
	local mover = add(ctx, "mover", -size / 2, size / 2, 1 - Course.Thickness, 1, gapStart + 1, gapStart + 1 + size)
	mover.travel = travel
	mover.period = travel / (2 + ctx.diff) * 2
	mover.moveX, mover.moveZ = ctx.dx, ctx.dz
	table.insert(ctx.out.movers, { gapBefore = 1, gapAfter = 1, size = size })
	local bId = platform(ctx, -ctx.lane, ctx.lane, gapEnd, 34, 1)
	link(ctx, aId, bId)
	ctx.rise = pickRise(ctx, 4, 6)
	run(ctx, 34, ctx.z1, 1, ctx.rise, { size = w(ctx, 4) })
end)

-- Conveyor belts that run backwards (and one that pushes you to the side).
builder("Conveyor", 1, 8, function(ctx)
	ctx.rise = pickRise(ctx, 6, 7)
	local count = 3
	local length = 9
	local gap = ((ctx.z1 - ctx.z0) - count * length) / (count + 1)
	local speed = 5 + ctx.diff * 2
	for i = 1, count do
		local near = ctx.z0 + gap * i + length * (i - 1)
		local top = ctx.rise * i / (count + 1)
		local sideways = ctx.diff >= 2 and i == 2
		stream(ctx, near, near + length, top, speed, if sideways then 1 else 0, if sideways then 0 else -1, "belt")
	end
end)

-- A cracked wall blocks the path. Go round over small stones — or smash it.
-- The long way round a smashable wall: a big loop of stepping stones out to
-- the side, forward, and back in — 7 jumps (harder ones crumble or vanish)
-- against one swing of the hammer.
local function loopAround(ctx: Ctx, fromZ: number, landZ0: number, landZ1: number, tops: { number })
	local L = ctx.lane
	local hard = ctx.diff >= 3
	local s = w(ctx, if hard then 3 else 3.5)
	local g = 3 + ctx.diff * 0.4 -- gap between stones
	local step = s + g
	local x0 = L + g + s / 2
	local cells = { { 0, 0 }, { 1, 0 }, { 2, 0 }, { 2, 1 }, { 2, 2 }, { 2, 3 }, { 1, 3 }, { 0, 3 } }
	local side = ctx.freeSide
	for i, c in cells do
		local x = side * (x0 + c[1] * step)
		local z = fromZ + c[2] * step
		local kind = "platform"
		if hard and (i == 3 or i == 6) then
			kind = "crumble"
		elseif hard and i == 4 then
			kind = "vanish"
		end
		platform(ctx, math.min(x - s / 2, x + s / 2), math.max(x - s / 2, x + s / 2), z - s / 2, z + s / 2, tops[i], kind)
	end
	local _ = landZ0 + landZ1
	table.insert(ctx.out.detours, #cells)
	return fromZ + 3 * step
end

-- A cracked wall blocks the path. Smash it — or take the long loop round.
builder("Detour", 2, 3, function(ctx)
	local L = ctx.lane
	local s = w(ctx, if ctx.diff >= 3 then 3 else 3.5)
	local step = s + 3 + ctx.diff * 0.4
	local wallZ = 10 + step * 1.5 -- halfway along the loop: far from where it starts and ends
	platform(ctx, -L, L, ctx.z0, wallZ, 0)
	local h = wallHeight(ctx)
	blocker(ctx, add(ctx, "breakable", -L - 3, L + 3, 0, h, wallZ, wallZ + 2)) -- wider than the path: no sneaking round its ends
	table.insert(ctx.out.walls, h)
	add(ctx, "floor", -L, L, -Course.Thickness, 0, wallZ, wallZ + 2)
	local backZ = loopAround(ctx, 10, wallZ + 2, 32, { 1.5, 3, 4.5, 6, 6, 4.5, 3, 1.5 })
	local _ = backZ
	platform(ctx, -L, L, wallZ + 2, ctx.z1, 0) -- the landing runs on to the next checkpoint
	ctx.rise = pickRise(ctx, 1, 3)
end)

-- A crate wall on a bridge. Smash it — or climb the long loop up round it.
builder("Barricade", 2, 3, function(ctx)
	local L = ctx.lane
	local s = w(ctx, if ctx.diff >= 3 then 3 else 3.5)
	local step = s + 3 + ctx.diff * 0.4
	local wallZ = 10 + step * 1.5
	local h = wallHeight(ctx)
	platform(ctx, -L, L, ctx.z0, wallZ, 0)
	blocker(ctx, add(ctx, "breakable", -L - 3, L + 3, 0, h, wallZ, wallZ + 2)) -- wider than the path: no sneaking round its ends
	table.insert(ctx.out.walls, h)
	add(ctx, "floor", -L, L, -Course.Thickness, 0, wallZ, wallZ + 2)
	local backZ = loopAround(ctx, 10, wallZ + 2, 32, { 2.5, 5, 7.5, 10, 10, 7.5, 5, 2.5 })
	local _ = backZ
	platform(ctx, -L, L, wallZ + 2, ctx.z1, 0) -- the landing runs on to the next checkpoint
	ctx.rise = pickRise(ctx, 1, 3)
end)

-- Tiles that crumble a moment after you step on them.
builder("Crumble", 2, 14, function(ctx)
	ctx.rise = pickRise(ctx, 5, 8)
	lava(ctx, ctx.z0, ctx.z1)
	run(ctx, ctx.z0, ctx.z1, 0, ctx.rise, { size = w(ctx, 4.5), maxGap = 3.5 + ctx.diff * 0.3, kind = "crumble" })
end)

-- Team tiles: each holds two people — the third one to step on breaks it.
-- Two tiles side by side, so a squad has to split up.
builder("Fragile", 2, 10, function(ctx)
	ctx.rise = pickRise(ctx, 4, 7)
	local s = w(ctx, 3.5)
	local g = 3 + ctx.diff * 0.3
	local length = ctx.z1 - ctx.z0
	local n = math.max(1, math.ceil((length - g) / (s + g)))
	local gap = (length - n * s) / (n + 1)
	for i = 1, n do
		local near = ctx.z0 + gap * i + s * (i - 1)
		local top = ctx.rise * i / (n + 1)
		for _, side in { -1, 1 } do
			local x = side * (s / 2 + 0.6)
			platform(ctx, x - s / 2, x + s / 2, near, near + s, top, "fragile")
		end
	end
end)

-- Ice: one step and you slide on for a few studs. Mind the holes.
builder("Slide", 1, 6, function(ctx)
	ctx.rise = pickRise(ctx, 2, 5)
	local L = ctx.lane
	local strips = 4
	local hole = 2.5 + ctx.diff * 0.5
	local length = (ctx.z1 - ctx.z0 - (strips - 1) * hole) / strips
	for i = 1, strips do
		local near = ctx.z0 + (i - 1) * (length + hole)
		local top = ctx.rise * i / (strips + 1)
		if i % 2 == 0 then
			-- a hole in the middle: slide down one side or the other
			local side = (2 * L - hole) / 2
			platform(ctx, -L, -L + side, near, near + length, top, "slide")
			platform(ctx, L - side, L, near, near + length, top, "slide")
		else
			platform(ctx, -L, L, near, near + length, top, "slide")
		end
	end
end)

-- A long platform with walls sliding at you: jump the low one, dodge the tall one.
builder("WallRun", 2, 3, function(ctx)
	local L = ctx.lane
	ctx.rise = pickRise(ctx, 1, 3)
	platform(ctx, -L, L, ctx.z0, ctx.z1, 0)
	local function sweeper(minX: number, maxX: number, height: number, speed: number)
		local startZ = ctx.z1 - 4
		local travel = (ctx.z1 - 4) - (ctx.z0 + 6)
		local piece = add(ctx, "sweeper", minX, maxX, 0.3, 0.3 + height, startZ - 0.75, startZ + 0.75)
		piece.travel = travel
		piece.period = travel / speed * 2
		piece.moveX, piece.moveZ = -ctx.dx, -ctx.dz -- towards the player
		table.insert(ctx.out.sweepers, { height = height, low = height <= 3 })
	end
	sweeper(-L, L, 2.4, 8 + ctx.diff * 2) -- low: jump over it
	local side = if ctx.rng:NextInteger(0, 1) == 0 then -1 else 1
	sweeper(if side < 0 then -L else 0.5, if side < 0 then -0.5 else L, 8, 6 + ctx.diff * 2) -- tall: step aside
end)

-- A rock wall: ledges zig-zag steeply up, then a short run to the next pad.
builder("Climb", 1, 33, function(ctx)
	local L = ctx.lane
	local s = w(ctx, ({ 4.5, 4, 3.6 })[ctx.diff])
	local xs = { -(L - s / 2), L - s / 2 }
	local target = pickRise(ctx, 14, 16)
	-- more ledges when it has to climb higher (never squeezed thinner)
	local steps = math.clamp(math.ceil((target - 3) / 2.5), 5, 12)
	local top = 0
	local depth = 3 * ctx.widthScale
	for i = 1, steps do
		top += 2.5
		local near = ctx.z0 + 1 + (i - 1) * 2.4
		local x = xs[(i % 2) + 1]
		platform(ctx, x - s / 2, x + s / 2, near, near + depth, top)
	end
	local last = ctx.z0 + 1 + (steps - 1) * 2.4 + depth
	ctx.rise = math.max(target, top + 1)
	run(ctx, last, ctx.z1, top, ctx.rise, { size = w(ctx, 4.5), maxGap = 3 + ctx.diff * 0.5 })
end)

-- A ceiling over part of the section (tunnels, shafts, arches).
local function roof(ctx: Ctx, minX: number, maxX: number, minZ: number, maxZ: number, y: number)
	local piece = add(ctx, "roof", minX, maxX, y, y + 1.5, minZ, maxZ)
	table.insert(ctx.out.roofs, {
		minX = piece.cx - piece.sx / 2,
		maxX = piece.cx + piece.sx / 2,
		minZ = piece.cz - piece.sz / 2,
		maxZ = piece.cz + piece.sz / 2,
		bottom = piece.cy - piece.sy / 2,
		section = ctx.section,
	})
end

-- Walls with window gaps along both sides of a stretch.
local function sideWalls(ctx: Ctx, minZ: number, maxZ: number, y0: number, y1: number)
	local L = ctx.lane
	local z = minZ
	while z < maxZ do
		local z2 = math.min(maxZ, z + 6)
		for _, side in { -1, 1 } do
			add(ctx, "wall", if side < 0 then -L - 1.5 else L, if side < 0 then -L else L + 1.5, y0, y1, z, z2)
		end
		-- a window: only the lower and upper parts of the wall
		local w2 = math.min(maxZ, z2 + 3)
		if w2 > z2 then
			for _, side in { -1, 1 } do
				local a, b = if side < 0 then -L - 1.5 else L, if side < 0 then -L else L + 1.5
				add(ctx, "wall", a, b, y0, y0 + 3.5, z2, w2)
				add(ctx, "wall", a, b, y1 - 3, y1, z2, w2)
			end
		end
		z = w2
	end
end

-- Through a building: walls with windows, a roof, and jumps inside.
builder("Tunnel", 1, 6, function(ctx)
	ctx.rise = pickRise(ctx, 2, 5)
	local inside0, inside1 = 10, ctx.z1 - 6
	local L = ctx.lane
	platform(ctx, -L, L, ctx.z0, inside0 + 2, 0)
	local hops = run(ctx, inside0 + 2, inside1, 0, ctx.rise, { size = w(ctx, 5), maxGap = 3 + ctx.diff * 0.5 })
	platform(ctx, -L, L, inside1, ctx.z1, ctx.rise)
	local ceiling = math.max(0, ctx.rise) + 11
	sideWalls(ctx, inside0, inside1, -2, ceiling)
	roof(ctx, -L - 1.5, L + 1.5, inside0, inside1, ceiling)
	if ctx.diff >= 2 and #hops >= 3 then
		-- a spinner in the middle of the hall
		local mid = hops[math.ceil(#hops / 2)]
		local zc = (mid.near + mid.far) / 2
		local radius = math.min((mid.far - mid.near) / 2 + 2, L - math.abs(mid.x) - 0.5)
		add(ctx, "pivot", mid.x - 0.6, mid.x + 0.6, mid.top, mid.top + 2.2, zc - 0.6, zc + 0.6)
		local bar = add(ctx, "spinner", mid.x - 0.5, mid.x + 0.5, mid.top + 0.9, mid.top + 1.9, zc - radius, zc + radius)
		bar.spinSpeed = 1.6 + ctx.diff * 0.4
	end
end)

-- Jumping from roof to roof across a row of buildings of different heights.
builder("Rooftops", 1, 10, function(ctx)
	ctx.rise = pickRise(ctx, -2, 8)
	local size = w(ctx, ({ 7, 6, 5 })[ctx.diff])
	run(ctx, ctx.z0, ctx.z1, 0, ctx.rise, { size = size, width = w(ctx, 7.5), maxGap = 3 + ctx.diff * 0.6, kind = "building", pillar = true, depth = 22 })
end)

-- Into a tall shaft through a doorway, up the ladder inside, out at the top.
builder("Shaft", 2, 18, function(ctx)
	local L = ctx.lane
	local top = 14
	local front, back = 14, 24
	local aId = platform(ctx, -L, L, ctx.z0, front + 4, 0)
	add(ctx, "truss", -1, 1, 0, top, front + 4, front + 6)
	local uId = platform(ctx, -L, L, front + 6, 32, top)
	link(ctx, aId, uId)
	-- walls: the front has a doorway at the bottom, the back an opening at the top
	add(ctx, "wall", -L - 1.5, -L, -2, top + 10, front, back) -- left
	add(ctx, "wall", L, L + 1.5, -2, top + 10, front, back) -- right
	add(ctx, "wall", -L, L, 8, top + 10, front, front + 1) -- above the doorway
	add(ctx, "wall", -L, L, -2, top - Course.Thickness, back - 1, back) -- below the exit
	roof(ctx, -L - 1.5, L + 1.5, front, back, top + 10)
	ctx.rise = pickRise(ctx, 15, 18)
	run(ctx, 32, ctx.z1, top, ctx.rise, { size = w(ctx, 4.5) })
end)

-- Under a row of arches, over stepping stones.
builder("Gateway", 1, 8, function(ctx)
	ctx.rise = pickRise(ctx, 3, 7)
	local hops = run(ctx, ctx.z0, ctx.z1, 0, ctx.rise, { size = w(ctx, 5.5), maxGap = 3 + ctx.diff * 0.6, extra = 1 })
	local L = ctx.lane
	for i, h in hops do
		-- arches stay away from both ends, where the route may turn a corner
		if i % 2 == 1 and h.near >= ctx.z0 + L + 2 and h.far <= ctx.z1 - L - 2 then
			local zc = (h.near + h.far) / 2
			for _, side in { -1, 1 } do
				local x0 = if side < 0 then -L - 2.5 else L + 1
				add(ctx, "wall", x0, x0 + 1.5, h.top - 8, h.top + 11, zc - 0.75, zc + 0.75)
			end
			roof(ctx, -L - 2.5, L + 2.5, zc - 0.75, zc + 0.75, h.top + 11)
		end
	end
end)

-- Going down: jumps onto smaller and smaller ledges below.
builder("Drop", 1, 0, function(ctx)
	ctx.rise = -pickRise(ctx, 6, 10)
	run(ctx, ctx.z0, ctx.z1, 0, ctx.rise, { size = w(ctx, ({ 5, 4.5, 4 })[ctx.diff]), maxGap = 4 + ctx.diff * 0.5, extra = 1 })
end)

-- Floating rocks scattered at different heights.
builder("Asteroids", 1, 16, function(ctx)
	ctx.rise = pickRise(ctx, 7, 9)
	local size = w(ctx, ({ 5, 4.5, 4 })[ctx.diff])
	run(ctx, ctx.z0, ctx.z1, 0, ctx.rise, { size = size, maxGap = 3 + ctx.diff * 0.5, extra = 2, kind = "rock" })
end)

builder("Spinner", 2, 7, function(ctx)
	run(ctx, ctx.z0, 10, 0, 2)
	platform(ctx, -ctx.lane, ctx.lane, 10, 38, 2)
	local centers = if ctx.diff >= 3 then { 17, 31 } else { 24 }
	local radius = math.min(ctx.lane - 0.4, 5.6)
	local speed = if ctx.diff >= 3 then 2.6 else 1.8
	for i, zc in centers do
		add(ctx, "pivot", -0.6, 0.6, 2, 4.2, zc - 0.6, zc + 0.6)
		local bar = add(ctx, "spinner", -0.5, 0.5, 2.9, 3.9, zc - radius, zc + radius)
		bar.spinSpeed = if i % 2 == 0 then -speed else speed
	end
	ctx.rise = pickRise(ctx, 6, 7)
	run(ctx, 38, ctx.z1, 2, ctx.rise, { size = w(ctx, 5) })
end)

builder("Vanish", 2, 16, function(ctx)
	ctx.rise = pickRise(ctx, 6, 7)
	lava(ctx, ctx.z0, ctx.z1)
	run(ctx, ctx.z0, ctx.z1, 0, ctx.rise, { size = w(ctx, 5), maxGap = 3.5, kind = "vanish" })
end)

builder("Pillars", 2, 16, function(ctx)
	ctx.rise = pickRise(ctx, 6, 8)
	lava(ctx, ctx.z0, ctx.z1)
	run(ctx, ctx.z0, ctx.z1, 0, ctx.rise, { size = w(ctx, 4), maxGap = 4.5, pillar = true, extra = 1 })
end)

-- Wide steps with strips of rushing water that sweep you off the side.
builder("Rapids", 1, 8, function(ctx)
	ctx.rise = pickRise(ctx, 6, 7)
	local steps = 3
	local length = (ctx.z1 - ctx.z0) / steps
	local speed = ({ 8, 10, 13 })[ctx.diff]
	local strip = 4
	local side = if ctx.rng:NextInteger(0, 1) == 0 then 1 else -1
	for i = 0, steps - 1 do
		local near = ctx.z0 + i * length
		local top = ctx.rise * (i + 1) / (steps + 1)
		local dry = (length - strip) / 2
		platform(ctx, -ctx.lane, ctx.lane, near, near + dry, top)
		stream(ctx, near + dry, near + dry + strip, top, speed, side, 0, "water")
		platform(ctx, -ctx.lane, ctx.lane, near + dry + strip, near + length, top)
	end
end)

Course.Builders = builders

----------------------------------------------------------------------
-- Whole course
----------------------------------------------------------------------
-- Today's section list for a level: picked from the theme's pool, respecting
-- difficulty, never the same type twice in a row, and as varied as possible.
-- Daily challenge: every "must" section plus a random handful of the rest,
-- shuffled, so each day has lava, water, walls, spinners... in a new order.
local function challengeSequence(day: number): { string }
	local rng = Course.rng(day * 6271 + 99)
	local picked = table.clone(Themes.ChallengeMust)
	local others = table.clone(Themes.ChallengeOthers)
	while #picked < Themes.ChallengeSections and #others > 0 do
		table.insert(picked, table.remove(others, rng:NextInteger(1, #others)) :: string)
	end
	for i = #picked, 2, -1 do
		local j = rng:NextInteger(1, i)
		picked[i], picked[j] = picked[j], picked[i]
	end
	return picked
end

function Course.sequenceFor(theme: Themes.Theme, day: number): { string }
	if theme.id == "Challenge" then
		return challengeSequence(day)
	end
	local rng = Course.rng(theme.seed * 31 + day * 7919 + 13)
	local count = Themes.sectionCount(theme.level)
	local half = math.ceil(count / 2)
	local used: { [string]: boolean } = {}
	local out: { string } = {}
	for i = 1, count do
		local diff = if i <= half then theme.diff[1] else theme.diff[2]
		local fresh, ok = {}, {}
		for _, name in theme.pool do
			local b = builders[name]
			if b and b.minDiff <= diff and name ~= out[i - 1] then
				table.insert(ok, name)
				if not used[name] then
					table.insert(fresh, name)
				end
			end
		end
		local choices = if #fresh > 0 then fresh elseif #ok > 0 then ok else { "Stones" }
		local name = choices[rng:NextInteger(1, #choices)]
		used[name] = true
		table.insert(out, name)
	end
	return out
end

-- Seed for a level's layout on a given day (changes the details every day).
function Course.dailySeed(theme: Themes.Theme, day: number): number
	return theme.seed + day * 101
end

local DIRS = { { 0, 1 }, { 1, 0 }, { 0, -1 }, { -1, 0 } } -- N, E, S, W on the grid
local LAP_RISE = 34 -- tower mode: one full lap (4 sections) climbs at least this much

-- The route on the grid: a walk that mostly goes straight, sometimes turns,
-- never visits a cell twice and never runs right next to itself.
function Course.walk(count: number, rng: Rng): ({ { number } }, { number })
	for _ = 1, 200 do
		local nodes = { { 0, 0 } }
		local headings = {}
		local used = { ["0,0"] = true }
		local heading = 1
		local ok = true
		for i = 1, count do
			local options = {}
			for _, turn in { 0, 0, 0, 1, -1 } do -- straight is 3x more likely
				local h = ((heading - 1 + turn) % 4) + 1
				local last = nodes[#nodes]
				local nx, nz = last[1] + DIRS[h][1], last[2] + DIRS[h][2]
				local free = not used[nx .. "," .. nz]
				-- keep away from older parts of the route (not just the cell itself)
				for _, d in DIRS do
					local key = (nx + d[1]) .. "," .. (nz + d[2])
					if used[key] and not (nx + d[1] == last[1] and nz + d[2] == last[2]) then
						free = false
					end
				end
				if free then
					table.insert(options, h)
				end
			end
			if #options == 0 then
				ok = false
				break
			end
			heading = options[rng:NextInteger(1, #options)]
			local last = nodes[#nodes]
			local node = { last[1] + DIRS[heading][1], last[2] + DIRS[heading][2] }
			table.insert(nodes, node)
			used[node[1] .. "," .. node[2]] = true
			headings[i] = heading
		end
		if ok then
			return nodes, headings
		end
	end
	-- (practically never) fall back to a straight line
	local nodes, headings = { { 0, 0 } }, {}
	for i = 1, count do
		table.insert(nodes, { 0, i })
		headings[i] = 1
	end
	return nodes, headings
end

function Course.generate(theme: Themes.Theme, origin: { number }, rng: Rng, seed: number?, sequence: { string }?): Result
	local sections = sequence or Course.sequenceFor(theme, 0)
	local worldInfo = Themes.Worlds[theme.world]
	local cpHalf = worldInfo.checkpoint
	local SECTION = worldInfo.section
	local lane = worldInfo.lane
	local out: Result = {
		theme = theme,
		seed = seed or theme.seed,
		pieces = {},
		surfaces = {},
		links = {},
		blockers = {},
		checkpoints = {},
		startSurface = 0,
		winSurface = 0,
		builders = {},
		walls = {},
		roofs = {},
		movers = {},
		sweepers = {},
		detours = {},
		minWidth = math.huge,
		bottom = origin[2],
		top = origin[2],
		finishDir = { 0, 1 },
		nodes = {},
		mode = if theme.layout == "tower" then "tower" else "journey",
		center = { origin[1], origin[3] },
		coreHalf = SECTION / 2 - lane - 4,
	}

	local count = #sections
	local tower = out.mode == "tower"
	local nodes, headings
	if tower then
		-- round the four corners of a square around the landmark, again and again
		local corners = { { -0.5, -0.5 }, { 0.5, -0.5 }, { 0.5, 0.5 }, { -0.5, 0.5 } }
		local turn = { 2, 1, 4, 3 } -- E, N, W, S
		nodes, headings = {}, {}
		for i = 0, count do
			table.insert(nodes, corners[(i % 4) + 1])
			if i > 0 then
				headings[i] = turn[((i - 1) % 4) + 1]
			end
		end
	else
		nodes, headings = Course.walk(count, rng)
	end
	out.nodes = nodes

	local function nodePos(i: number): (number, number)
		local n = nodes[i + 1]
		return origin[1] + n[1] * SECTION, origin[3] + n[2] * SECTION
	end

	local function checkpoint(index: number, top: number, kind: string): number
		local half = if kind == "win" then cpHalf + 1 else cpHalf
		local x, z = nodePos(index)
		local piece: Piece = {
			kind = kind,
			section = index,
			index = index,
			cx = x,
			cy = top - Course.Thickness / 2,
			cz = z,
			sx = half * 2,
			sy = Course.Thickness,
			sz = half * 2,
		}
		table.insert(out.pieces, piece)
		out.checkpoints[index + 1] = { piece.cx, top, piece.cz }
		return addSurface(out, piece, kind)
	end

	local y = origin[2]
	out.startSurface = checkpoint(0, y, "checkpoint")
	local half = math.ceil(count / 2)
	local rises: { number } = {}
	for i = 1, count do
		local diff = math.clamp(if i <= half then theme.diff[1] else theme.diff[2], 1, 3)
		local chosen = builders[sections[i]] or builders.Stones
		-- tower mode: each lap must climb enough that laps never bump heads
		local minRise = 0
		if tower and i >= 4 then
			local lastThree = rises[i - 1] + rises[i - 2] + rises[i - 3]
			minRise = math.max(0, LAP_RISE - lastThree)
		end
		if chosen.maxRise < minRise then
			chosen = builders.Climb -- this one can always climb high enough
		end
		table.insert(out.builders, chosen.name)
		local x, z = nodePos(i - 1)
		local dir = DIRS[headings[i]]
		local ctx: Ctx = {
			rng = rng,
			diff = diff,
			section = i,
			cx = x,
			cz = z,
			dx = dir[1],
			dz = dir[2],
			ux = dir[2], -- right-hand side
			uz = -dir[1],
			oy = y,
			minRise = minRise,
			-- after a right turn the previous section lies on our right: loop left
			freeSide = if not tower and i > 1 and headings[i] == (headings[i - 1] % 4) + 1 then -1 else 1,
			lane = lane,
			widthScale = worldInfo.widthScale,
			z0 = cpHalf,
			z1 = SECTION - cpHalf,
			theme = theme,
			out = out,
			rise = 6,
		}
		chosen.build(ctx)
		rises[i] = ctx.rise
		y += ctx.rise
		local kind = if i == count then "win" else "checkpoint"
		local id = checkpoint(i, y, kind)
		if i == count then
			out.winSurface = id
			out.finishDir = { dir[1], dir[2] }
		end
	end
	for _, p in out.pieces do
		out.bottom = math.min(out.bottom, p.cy - p.sy / 2)
		out.top = math.max(out.top, p.cy + p.sy / 2)
	end
	return out
end

----------------------------------------------------------------------
-- Reachability check (used by the tests): can you walk from the start to the
-- finish without smashing anything and without items?
----------------------------------------------------------------------
local function gapXZ(a: Surface, b: Surface): number
	local dx = math.max(0, a.minX - b.maxX, b.minX - a.maxX)
	local dz = math.max(0, a.minZ - b.maxZ, b.minZ - a.maxZ)
	return math.sqrt(dx * dx + dz * dz)
end

local function segmentHitsBox(x0: number, y0: number, z0: number, x1: number, y1: number, z1: number, box: Box): boolean
	local tMin, tMax = 0, 1
	local p = { x0, y0, z0 }
	local d = { x1 - x0, y1 - y0, z1 - z0 }
	local lo = { box.minX, box.minY, box.minZ }
	local hi = { box.maxX, box.maxY, box.maxZ }
	for axis = 1, 3 do
		if math.abs(d[axis]) < 1e-9 then
			if p[axis] < lo[axis] or p[axis] > hi[axis] then
				return false
			end
		else
			local t0 = (lo[axis] - p[axis]) / d[axis]
			local t1 = (hi[axis] - p[axis]) / d[axis]
			if t0 > t1 then
				t0, t1 = t1, t0
			end
			tMin = math.max(tMin, t0)
			tMax = math.min(tMax, t1)
			if tMin > tMax then
				return false
			end
		end
	end
	return true
end

local function closest(a: Surface, b: Surface): (number, number, number, number)
	local ax = math.clamp((b.minX + b.maxX) / 2, a.minX, a.maxX)
	local az = math.clamp((b.minZ + b.maxZ) / 2, a.minZ, a.maxZ)
	local bx = math.clamp(ax, b.minX, b.maxX)
	local bz = math.clamp(az, b.minZ, b.maxZ)
	return ax, az, bx, bz
end

function Course.canJump(a: Surface, b: Surface, blockers: { Box }): boolean
	local d = gapXZ(a, b)
	local dy = b.top - a.top
	local overlapX = math.min(a.maxX, b.maxX) - math.max(a.minX, b.minX)
	local overlapZ = math.min(a.maxZ, b.maxZ) - math.max(a.minZ, b.minZ)
	if overlapX > 0.01 and overlapZ > 0.01 and math.abs(dy) > Course.MaxRise then
		return false -- stacked on top of each other, not a jump
	end
	local ok = (dy <= Course.MaxRise and d <= Course.MaxGap) or (dy < 0 and d <= Course.MaxDropGap)
	if not ok then
		return false
	end
	local ax, az, bx, bz = closest(a, b)
	local h = math.max(a.top, b.top) + 2.5
	for _, box in blockers do
		if segmentHitsBox(ax, h, az, bx, h, bz, box) then
			return false
		end
	end
	return true
end

function Course.reachable(result: Result): (boolean, { [number]: boolean })
	local surfaces = result.surfaces
	local adjacency: { [number]: { number } } = {}
	for _, l in result.links do
		adjacency[l[1]] = adjacency[l[1]] or {}
		table.insert(adjacency[l[1]], l[2])
	end
	local seen = { [result.startSurface] = true }
	local queue = { result.startSurface }
	local head = 1
	while head <= #queue do
		local current = surfaces[queue[head]]
		head += 1
		for _, other in surfaces do
			if not seen[other.id] and other.kind ~= "kill" then
				if math.abs(other.section - current.section) <= 1 and Course.canJump(current, other, result.blockers) then
					seen[other.id] = true
					table.insert(queue, other.id)
				end
			end
		end
		for _, to in adjacency[current.id] or {} do
			if not seen[to] then
				seen[to] = true
				table.insert(queue, to)
			end
		end
	end
	return seen[result.winSurface] == true, seen
end

return Course
