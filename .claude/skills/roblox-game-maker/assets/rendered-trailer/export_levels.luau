local process = require("@lune/process")
-- Exports real Chained Tower courses (as the game builds them today) for the trailer.
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local Course = require("./Course")
local Themes = require("./Themes")
local Calendar = require("./Calendar")

local day = Calendar.dayNumber(os.time())
local function c3(c) return { math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5) } end

local function export(theme)
	local origin = { 0, 0, 0 }
	local seed = Course.dailySeed(theme, day)
	local seq = Course.sequenceFor(theme, day)
	local r = Course.generate(theme, origin, Course.rng(seed), seed, seq)
	-- shortest jump path start -> win (BFS, same rules as the fairness test)
	local adj = {}
	for _, l in r.links do
		adj[l[1]] = adj[l[1]] or {}
		table.insert(adj[l[1]], l[2])
	end
	local parent, queue, head = { [r.startSurface] = 0 }, { r.startSurface }, 1
	while head <= #queue do
		local cur = r.surfaces[queue[head]]
		head += 1
		if cur.id == r.winSurface then break end
		for _, o in r.surfaces do
			if parent[o.id] == nil and o.kind ~= "kill" and math.abs(o.section - cur.section) <= 1 and Course.canJump(cur, o, r.blockers) then
				parent[o.id] = cur.id
				table.insert(queue, o.id)
			end
		end
		for _, to in adj[cur.id] or {} do
			if parent[to] == nil then
				parent[to] = cur.id
				table.insert(queue, to)
			end
		end
	end
	local path, id = {}, r.winSurface
	while id and id ~= 0 do
		local s = r.surfaces[id]
		table.insert(path, 1, { x = (s.minX + s.maxX) / 2, z = (s.minZ + s.maxZ) / 2, top = s.top, kind = s.kind, section = s.section,
			minX = s.minX, maxX = s.maxX, minZ = s.minZ, maxZ = s.maxZ })
		id = parent[id]
	end
	local pieces = {}
	for _, p in r.pieces do
		table.insert(pieces, { k = p.kind, s = p.section, c = { p.cx, p.cy, p.cz }, z = { p.sx, p.sy, p.sz }, style = p.style,
			mv = p.moveX and { p.moveX, p.moveZ or 0 } or nil, travel = p.travel, period = p.period, spin = p.spinSpeed, index = p.index })
	end
	local cols = {}
	for _, c in theme.colors do table.insert(cols, c3(c)) end
	local lm = {}
	for _, c in theme.landmark.colors do table.insert(lm, c3(c)) end
	return {
		id = theme.id, base = theme.base, world = theme.world, level = theme.level, builders = r.builders, mode = r.mode,
		colors = cols, checkpoint = c3(theme.checkpoint), pad = c3(theme.pad), gravity = theme.gravity or 196.2,
		sky = { clock = theme.sky.clock, brightness = theme.sky.brightness, ambient = c3(theme.sky.ambient), atmosphere = c3(theme.sky.atmosphere), density = theme.sky.density },
		floor = theme.floor and { color = c3(theme.floor.color) } or nil,
		landmark = { shape = theme.landmark.shape, round = theme.landmark.round, colors = lm, cap = theme.landmark.cap and c3(theme.landmark.cap) or nil },
		center = r.center, finishDir = r.finishDir, top = r.top, bottom = r.bottom,
		checkpoints = r.checkpoints, pieces = pieces, path = path, lane = Themes.Worlds[theme.world].lane,
	}
end

local out = {}
for _, id in { "Meadow", "Volcano", "Ice", "Space", "Candy", "Neon", "Castle", "Clouds" } do
	table.insert(out, export(Themes.ById[id]))
end
table.insert(out, export(Themes.challengeFor(day)))
fs.writeFile(process.args[1], serde.encode("json", out))
for _, l in out do
	print(l.id, l.base or "", #l.pieces, "pieces", #l.path, "hops", table.concat(l.builders, ","))
end
