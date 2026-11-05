--!strict
-- Pure course layout: turns a theme (+ seed) into a list of boxes. No Roblox
-- instances, so the tests can build thousands of courses and prove each one is
-- beatable WITHOUT buying anything.
--
-- A course is a straight run of sections that climbs as it goes. Each section
-- goes from one checkpoint pad to the next. Inside a section we use local
-- coordinates:
--   z: forward, 0 = centre of the start pad, SECTION = centre of the end pad
--   x: sideways, -lane..lane is the path
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
	travel: number?, -- mover: distance along +z it slides back and forth
	period: number?, -- mover: seconds for a full back-and-forth
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
	hurdles: { { height: number, before: number, after: number } },
	movers: { { gapBefore: number, gapAfter: number, size: number } },
	minWidth: number, -- narrowest standable thing (tests check it's not too thin)
	length: number,
	bottom: number, -- lowest point of the course (falls below this = fallen)
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
	ox: number, -- world position of this section's local origin
	oy: number,
	oz: number,
	lane: number,
	widthScale: number,
	z0: number, -- where section content starts / ends (pads take the rest)
	z1: number,
	theme: Themes.Theme,
	out: Result,
	rise: number,
}

local function add(ctx: Ctx, kind: string, minX: number, maxX: number, minY: number, maxY: number, minZ: number, maxZ: number): Piece
	local piece: Piece = {
		kind = kind,
		section = ctx.section,
		cx = ctx.ox + (minX + maxX) / 2,
		cy = ctx.oy + (minY + maxY) / 2,
		cz = ctx.oz + (minZ + maxZ) / 2,
		sx = maxX - minX,
		sy = maxY - minY,
		sz = maxZ - minZ,
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
	return ctx.rng:NextInteger(low, high)
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
			local piece = add(ctx, k, x - width / 2, x + width / 2, -14, top, near, near + s)
			addSurface(ctx.out, piece, k)
		else
			platform(ctx, x - width / 2, x + width / 2, near, near + s, top, k)
		end
	end
	return hops
end

-- A breakable block standing on the route. Players jump over it — or smash it.
local function hurdle(ctx: Ctx, minX: number, maxX: number, zMid: number, thick: number, top: number, height: number, before: number, after: number)
	add(ctx, "breakable", minX, maxX, top, top + height, zMid - thick / 2, zMid + thick / 2)
	table.insert(ctx.out.hurdles, { height = height, before = before, after = after })
end

-- Water (or a conveyor belt) that pushes you along (fx, fz).
local function stream(ctx: Ctx, minZ: number, maxZ: number, top: number, speed: number, fx: number, fz: number, style: string)
	local id, piece = platform(ctx, -ctx.lane, ctx.lane, minZ, maxZ, top, "current")
	piece.flowX, piece.flowZ = fx, fz
	piece.flowSpeed = speed
	piece.style = style
	return id
end

-- Lava under a stretch of the course (only in lava themes; elsewhere a fall is a fall).
local function lava(ctx: Ctx, zFrom: number, zTo: number)
	if ctx.theme.lava then
		add(ctx, "kill", -ctx.lane - 2, ctx.lane + 2, -4, -3, zFrom, zTo)
	end
end

----------------------------------------------------------------------
-- Section types. Each sets ctx.rise and ends with a hop reachable from the
-- end pad (z = z1, top = ctx.rise).
----------------------------------------------------------------------
type Builder = { name: string, minDiff: number, build: (ctx: Ctx) -> () }

local builders: { [string]: Builder } = {}
local function builder(name: string, minDiff: number, build: (ctx: Ctx) -> ())
	builders[name] = { name = name, minDiff = minDiff, build = build }
end

builder("Stones", 1, function(ctx)
	ctx.rise = pickRise(ctx, 6, 8)
	local size = w(ctx, ({ 6, 5.5, 5 })[ctx.diff])
	run(ctx, ctx.z0, ctx.z1, 0, ctx.rise, { size = size, maxGap = 3.5 + ctx.diff * 0.5, extra = 1 })
end)

builder("LavaPlanks", 1, function(ctx)
	ctx.rise = pickRise(ctx, 6, 7)
	lava(ctx, ctx.z0, ctx.z1)
	run(ctx, ctx.z0, ctx.z1, 0, ctx.rise, { size = 4.5, width = w(ctx, 4), maxGap = 3.5 + ctx.diff * 0.5 })
end)

builder("Beams", 1, function(ctx)
	ctx.rise = pickRise(ctx, 6, 8)
	local width = w(ctx, ({ 3.6, 3.3, 3 })[ctx.diff])
	local hops = run(ctx, ctx.z0, ctx.z1, 0, ctx.rise, { size = 8, width = width, zigzag = 2, maxGap = 2.5, maxRise = 2 })
	if ctx.diff >= 2 then
		-- a post in the middle of every other beam: hop over it, or smash it
		for i, h in hops do
			if i % 2 == 0 and h.far - h.near >= 6 then
				local mid = (h.near + h.far) / 2
				hurdle(ctx, h.x - 0.75, h.x + 0.75, mid, 1.5, h.top, 2.5 + ctx.diff * 0.5, mid - h.near - 0.75, h.far - mid - 0.75)
			end
		end
	end
end)

builder("JumpPads", 1, function(ctx)
	platform(ctx, -ctx.lane, ctx.lane, ctx.z0 + 1, 12, 1)
	local padId, pad = platform(ctx, -3.5, 3.5, 12, 16, 1, "pad")
	pad.boost = 64 -- ~10 studs up
	local upId = platform(ctx, -ctx.lane, ctx.lane, 15, 23, 9)
	link(ctx, padId, upId)
	ctx.rise = pickRise(ctx, 9, 10)
	run(ctx, 23, ctx.z1, 9, ctx.rise, { size = w(ctx, 5.5), maxGap = 3.5 + ctx.diff * 0.5 })
end)

builder("Truss", 1, function(ctx)
	local floorId = platform(ctx, -ctx.lane, ctx.lane, ctx.z0, 14, 0)
	add(ctx, "truss", -1, 1, 0, 12, 14, 16)
	local upId = platform(ctx, -ctx.lane, ctx.lane, 16, 26, 12)
	link(ctx, floorId, upId)
	ctx.rise = pickRise(ctx, 12, 13)
	run(ctx, 26, ctx.z1, 12, ctx.rise, { size = w(ctx, 5.5), maxGap = 3.5 + ctx.diff * 0.5 })
end)

-- A platform sliding back and forth over a wide gap. Ride it across.
builder("Mover", 1, function(ctx)
	local size = w(ctx, 7)
	local aId = platform(ctx, -ctx.lane, ctx.lane, ctx.z0, 14, 1)
	local gapStart, gapEnd = 14, 34
	lava(ctx, gapStart, gapEnd)
	local travel = (gapEnd - gapStart) - size - 2 -- leaves 1 stud at each end
	local mover = add(ctx, "mover", -size / 2, size / 2, 1 - Course.Thickness, 1, gapStart + 1, gapStart + 1 + size)
	mover.travel = travel
	mover.period = travel / (2.5 + ctx.diff) * 2
	table.insert(ctx.out.movers, { gapBefore = 1, gapAfter = 1, size = size })
	local bId = platform(ctx, -ctx.lane, ctx.lane, gapEnd, ctx.z1 - 3, 1)
	link(ctx, aId, bId)
	ctx.rise = pickRise(ctx, 3, 4) -- one step up from the landing to the next pad
end)

-- Conveyor belts that run backwards (and one that pushes you to the side).
builder("Conveyor", 1, function(ctx)
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
builder("Detour", 2, function(ctx)
	local L = ctx.lane
	run(ctx, ctx.z0, 14, 0, 3)
	platform(ctx, -L, L, 14, 24, 3)
	add(ctx, "floor", -L, L, 3 - Course.Thickness, 3, 24, 26)
	blocker(ctx, add(ctx, "breakable", -L, L, 3, 13, 24, 26))
	platform(ctx, -L, L, 26, 36, 3)
	local s = w(ctx, if ctx.diff >= 3 then 3 else 3.5)
	local kind = if ctx.diff >= 3 then "vanish" else "platform"
	local x0 = L + 2
	platform(ctx, x0, x0 + s, 18, 18 + s, 4.5, kind)
	platform(ctx, x0, x0 + s, 23.5, 23.5 + s, 6, kind)
	platform(ctx, x0, x0 + s, 29, 29 + s, 4.5, kind)
	ctx.rise = pickRise(ctx, 6, 7)
	run(ctx, 36, ctx.z1, 3, ctx.rise, { size = w(ctx, 5) })
end)

-- Long planks with a crate on each one. Jump the crates — or smash them.
builder("Hurdles", 2, function(ctx)
	ctx.rise = pickRise(ctx, 6, 7)
	lava(ctx, ctx.z0, ctx.z1)
	local count = 3
	local length = 9
	local gap = ((ctx.z1 - ctx.z0) - count * length) / (count + 1)
	local height = if ctx.diff >= 3 then 4.5 else 3.5
	local half = w(ctx, 3.5)
	for i = 1, count do
		local near = ctx.z0 + gap * i + length * (i - 1)
		local top = ctx.rise * i / (count + 1)
		platform(ctx, -half, half, near, near + length, top)
		local mid = near + length / 2
		hurdle(ctx, -half, half, mid, 2, top, height, length / 2 - 1, length / 2 - 1)
	end
end)

builder("Spinner", 2, function(ctx)
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

builder("Vanish", 2, function(ctx)
	ctx.rise = pickRise(ctx, 6, 7)
	lava(ctx, ctx.z0, ctx.z1)
	run(ctx, ctx.z0, ctx.z1, 0, ctx.rise, { size = w(ctx, 5), maxGap = 3.5, kind = "vanish" })
end)

builder("Pillars", 2, function(ctx)
	ctx.rise = pickRise(ctx, 6, 8)
	lava(ctx, ctx.z0, ctx.z1)
	run(ctx, ctx.z0, ctx.z1, 0, ctx.rise, { size = w(ctx, 4), maxGap = 4.5, pillar = true, extra = 1 })
end)

-- Wide steps with strips of rushing water that sweep you off the side.
builder("Rapids", 1, function(ctx)
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
function Course.generate(theme: Themes.Theme, origin: { number }, rng: Rng, seed: number?): Result
	local worldInfo = Themes.Worlds[theme.world]
	local cpHalf = worldInfo.checkpoint
	local SECTION = worldInfo.section
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
		hurdles = {},
		movers = {},
		minWidth = math.huge,
		length = #theme.sections * SECTION,
		bottom = origin[2],
	}

	local function checkpoint(index: number, top: number, kind: string): number
		local half = if kind == "win" then cpHalf + 2 else cpHalf
		local piece: Piece = {
			kind = kind,
			section = index,
			index = index,
			cx = origin[1],
			cy = top - Course.Thickness / 2,
			cz = origin[3] + index * SECTION,
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
	local count = #theme.sections
	local half = math.ceil(count / 2)
	for i = 1, count do
		local diff = math.clamp(if i <= half then theme.diff[1] else theme.diff[2], 1, 3)
		local chosen = builders[theme.sections[i]] or builders.Stones
		table.insert(out.builders, chosen.name)

		local ctx: Ctx = {
			rng = rng,
			diff = diff,
			section = i,
			ox = origin[1],
			oy = y,
			oz = origin[3] + (i - 1) * SECTION,
			lane = worldInfo.lane,
			widthScale = worldInfo.widthScale,
			z0 = cpHalf,
			z1 = SECTION - cpHalf,
			theme = theme,
			out = out,
			rise = 6,
		}
		chosen.build(ctx)
		y += ctx.rise
		local kind = if i == count then "win" else "checkpoint"
		local id = checkpoint(i, y, kind)
		if i == count then
			out.winSurface = id
		end
	end
	for _, p in out.pieces do
		out.bottom = math.min(out.bottom, p.cy - p.sy / 2)
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
