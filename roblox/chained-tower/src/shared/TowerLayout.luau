--!strict
-- Pure tower layout: turns a seed into a list of boxes (no Roblox instances).
-- Keeping it pure lets us test thousands of towers outside Roblox and prove
-- every tower can be cleared WITHOUT buying anything.
--
-- The tower is a square spiral around a solid core. Each section runs along one
-- side, from one corner checkpoint to the next, and climbs while it goes.
-- Inside a section we work in local coordinates:
--   z: forward along the side, 0 = start corner, 48 = end corner
--   x: sideways, -5..5 is the lane, + is the outside of the tower
--   y: height above the start checkpoint

local Config = require(script.Parent.Config)

local Layout = {}

export type Rng = {
	NextInteger: (self: any, min: number, max: number) -> number,
	NextNumber: (self: any, min: number, max: number) -> number,
}

export type Piece = {
	kind: string, -- platform | checkpoint | win | kill | breakable | truss | pad | vanish | spinner | pivot | core | floor
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
	alongX: boolean?, -- spinner: true if the bar starts along world X
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
	seed: number,
	pieces: { Piece },
	surfaces: { Surface },
	links: { { number } },
	blockers: { Box },
	checkpoints: { { number } }, -- [index + 1] = { x, topY, z }
	startSurface: number,
	winSurface: number,
	height: number,
	builders: { string },
}

local S = Config.TowerHalfSize
local SIDE = S * 2 -- length of one side, corner to corner
local LANE = 5 -- half width of the lane
local CP = 5 -- half size of a checkpoint pad
local Z0 = CP -- section content starts after the start pad
local Z1 = SIDE - CP -- and ends before the end pad

-- Jump rules used by the builders AND the tests (Roblox default character:
-- JumpHeight 7.2, WalkSpeed 16 -> ~8 stud jumps; we stay well inside that).
Layout.MaxGap = 5
Layout.MaxRise = 3
Layout.MaxDropGap = 6

local CORNERS = { { -S, -S }, { S, -S }, { S, S }, { -S, S } }
local DIRS = { { 1, 0 }, { 0, 1 }, { -1, 0 }, { 0, -1 } }

----------------------------------------------------------------------
-- Section builder context
----------------------------------------------------------------------
type Ctx = {
	rng: Rng,
	diff: number,
	section: number,
	side: number,
	baseY: number,
	out: Result,
	rise: number,
	minRise: number, -- keeps one full lap (4 sections) at least LAP_RISE tall
}

local LAP_RISE = 32

local function pickRise(ctx: Ctx, low: number, high: number): number
	return math.max(ctx.rng:NextInteger(low, high), ctx.minRise)
end

local function toWorld(ctx: Ctx, minX: number, maxX: number, minZ: number, maxZ: number): (number, number, number, number)
	local corner = CORNERS[ctx.side + 1]
	local dir = DIRS[ctx.side + 1]
	local outX, outZ = dir[2], -dir[1]
	local function point(x: number, z: number): (number, number)
		return corner[1] + dir[1] * z + outX * x, corner[2] + dir[2] * z + outZ * x
	end
	local ax, az = point(minX, minZ)
	local bx, bz = point(maxX, maxZ)
	return math.min(ax, bx), math.max(ax, bx), math.min(az, bz), math.max(az, bz)
end

local function add(ctx: Ctx, kind: string, minX: number, maxX: number, minY: number, maxY: number, minZ: number, maxZ: number): Piece
	local wx0, wx1, wz0, wz1 = toWorld(ctx, minX, maxX, minZ, maxZ)
	local piece: Piece = {
		kind = kind,
		section = ctx.section,
		cx = (wx0 + wx1) / 2,
		cy = ctx.baseY + (minY + maxY) / 2,
		cz = (wz0 + wz1) / 2,
		sx = wx1 - wx0,
		sy = maxY - minY,
		sz = wz1 - wz0,
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
	return id
end

local function platform(ctx: Ctx, minX: number, maxX: number, minZ: number, maxZ: number, top: number, kind: string?): (number, Piece)
	local k = kind or "platform"
	local piece = add(ctx, k, minX, maxX, top - 1, top, minZ, maxZ)
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

-- Fill the space between zFrom (far edge of what came before) and zTo (near edge
-- of what comes next) with hops climbing from yFrom to yTo. Built so every gap
-- is <= maxGap and every rise <= maxRise, which keeps it beatable by design.
local function run(ctx: Ctx, zFrom: number, zTo: number, yFrom: number, yTo: number, opts: RunOpts?)
	local o: RunOpts = opts or {}
	local size = o.size or 5
	local width = o.width or size
	local maxGap = math.min(o.maxGap or 4, Layout.MaxGap)
	local maxRise = math.min(o.maxRise or 2.5, Layout.MaxRise - 0.5)
	local length = zTo - zFrom
	local dy = yTo - yFrom
	if length <= 0 then
		return
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
		return
	end

	local s = size
	if n * s > length - (n + 1) * 1 then
		s = math.max(1.5, (length - (n + 1)) / n)
	end
	local gap = (length - n * s) / (n + 1)
	local jitter = math.max(0, math.min(LANE - width / 2, width * 0.4))
	for i = 1, n do
		local near = zFrom + gap * i + s * (i - 1)
		local top = yFrom + dy * i / (n + 1)
		local x
		if o.zigzag then
			x = if i % 2 == 0 then o.zigzag else -o.zigzag
		else
			x = ctx.rng:NextNumber(-jitter, jitter)
		end
		local k = o.kind or "platform"
		if o.pillar then
			local piece = add(ctx, k, x - width / 2, x + width / 2, -6, top, near, near + s)
			addSurface(ctx.out, piece, k)
		else
			platform(ctx, x - width / 2, x + width / 2, near, near + s, top, k)
		end
	end
end

local function lava(ctx: Ctx, zFrom: number, zTo: number)
	add(ctx, "kill", -LANE, LANE, -3, -2, zFrom, zTo)
end

----------------------------------------------------------------------
-- Section types. Each one must end with ctx.rise set and its last hop
-- reachable from the end pad (z = Z1, top = ctx.rise).
----------------------------------------------------------------------
type Builder = { name: string, minDiff: number, maxDiff: number, build: (ctx: Ctx) -> () }

local builders: { Builder } = {
	{
		name = "Stones",
		minDiff = 1,
		maxDiff = 3,
		build = function(ctx)
			ctx.rise = pickRise(ctx, 7, 9)
			local size = ({ 5, 4.5, 4 })[ctx.diff]
			run(ctx, Z0, Z1, 0, ctx.rise, { size = size, maxGap = 3.5 + ctx.diff * 0.5, extra = 1 })
		end,
	},
	{
		name = "LavaPlanks",
		minDiff = 1,
		maxDiff = 2,
		build = function(ctx)
			ctx.rise = pickRise(ctx, 7, 8)
			lava(ctx, Z0, Z1)
			run(ctx, Z0, Z1, 0, ctx.rise, { size = 3.5, width = 3, maxGap = 3.5 + ctx.diff * 0.5 })
		end,
	},
	{
		name = "Beams",
		minDiff = 1,
		maxDiff = 3,
		build = function(ctx)
			ctx.rise = pickRise(ctx, 7, 9)
			local width = ({ 2.2, 1.8, 1.5 })[ctx.diff]
			run(ctx, Z0, Z1, 0, ctx.rise, { size = 7, width = width, zigzag = 1.8, maxGap = 2.5, maxRise = 2 })
		end,
	},
	{
		name = "JumpPads",
		minDiff = 1,
		maxDiff = 3,
		build = function(ctx)
			run(ctx, Z0, 12, 0, 1)
			local padId, pad = platform(ctx, -3, 3, 12, 16, 1, "pad")
			pad.boost = 64 -- ~10 studs up
			local upId = platform(ctx, -LANE, LANE, 15, 23, 9)
			link(ctx, padId, upId)
			ctx.rise = pickRise(ctx, 9, 10)
			run(ctx, 23, Z1, 9, ctx.rise, { maxGap = 3.5 + ctx.diff * 0.5 })
		end,
	},
	{
		name = "Truss",
		minDiff = 1,
		maxDiff = 3,
		build = function(ctx)
			local floorId = platform(ctx, -LANE, LANE, Z0, 14, 0)
			add(ctx, "truss", -1, 1, 0, 12, 14, 16)
			local upId = platform(ctx, -LANE, LANE, 16, 26, 12)
			link(ctx, floorId, upId)
			ctx.rise = pickRise(ctx, 12, 13)
			run(ctx, 26, Z1, 12, ctx.rise, { maxGap = 3.5 + ctx.diff * 0.5 })
		end,
	},
	{
		-- A cracked wall blocks the lane. Go the long way round over small
		-- stones on the outside — or smash straight through.
		name = "Detour",
		minDiff = 2,
		maxDiff = 3,
		build = function(ctx)
			run(ctx, Z0, 14, 0, 3)
			platform(ctx, -LANE, LANE, 14, 24, 3)
			add(ctx, "floor", -LANE, LANE, 2, 3, 24, 26)
			blocker(ctx, add(ctx, "breakable", -LANE, LANE, 3, 13, 24, 26))
			platform(ctx, -LANE, LANE, 26, 36, 3)
			local s = if ctx.diff >= 3 then 2 else 3
			local kind = if ctx.diff >= 3 then "vanish" else "platform"
			local x0 = 7
			platform(ctx, x0, x0 + s, 18, 18 + s, 4.5, kind)
			platform(ctx, x0, x0 + s, 23.5, 23.5 + s, 6, kind)
			platform(ctx, x0, x0 + s, 29, 29 + s, 4.5, kind)
			ctx.rise = pickRise(ctx, 7, 8)
			run(ctx, 36, Z1, 3, ctx.rise)
		end,
	},
	{
		-- A wall of crates. Climb the ladder and go over the top — or smash it.
		name = "CrateWall",
		minDiff = 2,
		maxDiff = 3,
		build = function(ctx)
			run(ctx, Z0, 14, 0, 2)
			local aId = platform(ctx, -LANE, LANE, 14, 24, 2)
			for _, col in { { -LANE, 0 }, { 0, LANE } } do
				for _, row in { { 2, 7 }, { 7, 12 } } do
					blocker(ctx, add(ctx, "breakable", col[1], col[2], row[1], row[2], 24, 28))
				end
			end
			local capId = platform(ctx, -LANE, LANE, 24, 28, 13)
			add(ctx, "truss", -1, 1, 2, 12, 22, 24)
			link(ctx, aId, capId)
			add(ctx, "floor", -LANE, LANE, 1, 2, 24, 28)
			platform(ctx, -LANE, LANE, 28, 38, 2)
			ctx.rise = pickRise(ctx, 7, 8)
			run(ctx, 38, Z1, 2, ctx.rise)
		end,
	},
	{
		name = "Spinner",
		minDiff = 2,
		maxDiff = 3,
		build = function(ctx)
			run(ctx, Z0, 12, 0, 2)
			platform(ctx, -LANE, LANE, 12, 36, 2)
			local centers = if ctx.diff >= 3 then { 18, 30 } else { 24 }
			local speed = if ctx.diff >= 3 then 2.6 else 1.8
			for i, zc in centers do
				add(ctx, "pivot", -0.6, 0.6, 2, 4.2, zc - 0.6, zc + 0.6)
				local bar = add(ctx, "spinner", -0.5, 0.5, 2.9, 3.9, zc - 4.6, zc + 4.6)
				bar.spinSpeed = if i % 2 == 0 then -speed else speed
				bar.alongX = bar.sx > bar.sz
			end
			ctx.rise = pickRise(ctx, 7, 8)
			run(ctx, 36, Z1, 2, ctx.rise)
		end,
	},
	{
		name = "Vanish",
		minDiff = 2,
		maxDiff = 3,
		build = function(ctx)
			ctx.rise = pickRise(ctx, 7, 8)
			lava(ctx, Z0, Z1)
			run(ctx, Z0, Z1, 0, ctx.rise, { size = 4, maxGap = 3.5, kind = "vanish" })
		end,
	},
	{
		name = "Pillars",
		minDiff = 3,
		maxDiff = 3,
		build = function(ctx)
			ctx.rise = pickRise(ctx, 7, 9)
			lava(ctx, Z0, Z1)
			run(ctx, Z0, Z1, 0, ctx.rise, { size = 3, maxGap = 4.5, pillar = true, extra = 1 })
		end,
	},
}
Layout.Builders = builders

----------------------------------------------------------------------
-- Whole tower
----------------------------------------------------------------------
function Layout.generate(seed: number, rng: Rng, sections: number?): Result
	local count = sections or Config.SectionsPerTower
	local out: Result = {
		seed = seed,
		pieces = {},
		surfaces = {},
		links = {},
		blockers = {},
		checkpoints = {},
		startSurface = 0,
		winSurface = 0,
		height = 0,
		builders = {},
	}

	local function checkpoint(index: number, side: number, top: number, kind: string): number
		local corner = CORNERS[side + 1]
		local half = if kind == "win" then CP + 1 else CP
		local piece: Piece = {
			kind = kind,
			section = index,
			index = index,
			cx = corner[1],
			cy = top - 0.5,
			cz = corner[2],
			sx = half * 2,
			sy = 1,
			sz = half * 2,
		}
		table.insert(out.pieces, piece)
		out.checkpoints[index + 1] = { corner[1], top, corner[2] }
		return addSurface(out, piece, kind)
	end

	local y = Config.TowerBaseY
	local rises: { number } = {}
	out.startSurface = checkpoint(0, 0, y, "checkpoint")
	local previous = ""
	for i = 1, count do
		local diff = math.clamp(1 + math.floor((i - 1) / 4), 1, 3)
		local options = {}
		for _, b in builders do
			if diff >= b.minDiff and diff <= b.maxDiff and b.name ~= previous then
				table.insert(options, b)
			end
		end
		local chosen = options[rng:NextInteger(1, #options)]
		previous = chosen.name
		table.insert(out.builders, chosen.name)

		local lastThree = 0
		for back = 1, 3 do
			lastThree += rises[i - back] or 0
		end
		local ctx: Ctx = {
			rng = rng,
			diff = diff,
			section = i,
			side = (i - 1) % 4,
			baseY = y,
			out = out,
			rise = 7,
			minRise = if i >= 4 then math.max(0, LAP_RISE - lastThree) else 0,
		}
		chosen.build(ctx)
		rises[i] = ctx.rise
		y += ctx.rise
		local kind = if i == count then "win" else "checkpoint"
		local id = checkpoint(i, i % 4, y, kind)
		if i == count then
			out.winSurface = id
		end
	end

	out.height = y
	local coreHalf = S - LANE - 1
	table.insert(out.pieces, {
		kind = "core",
		section = -1,
		cx = 0,
		cy = (y + 30) / 2,
		cz = 0,
		sx = coreHalf * 2,
		sy = y + 30,
		sz = coreHalf * 2,
	})
	return out
end

----------------------------------------------------------------------
-- Reachability check (used by the tests): can you walk from the start to the
-- top without smashing anything and without items?
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

function Layout.canJump(a: Surface, b: Surface, blockers: { Box }): boolean
	local d = gapXZ(a, b)
	local dy = b.top - a.top
	local overlapX = math.min(a.maxX, b.maxX) - math.max(a.minX, b.minX)
	local overlapZ = math.min(a.maxZ, b.maxZ) - math.max(a.minZ, b.minZ)
	if overlapX > 0.01 and overlapZ > 0.01 and math.abs(dy) > Layout.MaxRise then
		return false -- stacked on top of each other, not a jump
	end
	local ok = (dy <= Layout.MaxRise and d <= Layout.MaxGap) or (dy < 0 and d <= Layout.MaxDropGap)
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

function Layout.reachable(result: Result): (boolean, { [number]: boolean })
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
				-- only consider neighbours in this section or the next one
				if math.abs(other.section - current.section) <= 1 and Layout.canJump(current, other, result.blockers) then
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

return Layout
