--!strict
-- Builds everything players walk on:
--   * the main lobby with two portals (solo world / team world) and leaderboards
--   * a hub island for each world with one gate per level
--   * all 10 level courses, each with its own colours, backdrop and decorations

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Course = require(Shared.Course)
local Themes = require(Shared.Themes)
local Cosmetics = require(script.Parent.Cosmetics)

local World = {}

local C = Vector3.new(0, 0, -100) -- centre of the main lobby plaza
World.MainSpawn = CFrame.lookAt(C + Vector3.new(0, 3, -38), C + Vector3.new(0, 3, 0))

export type Pad = { part: BasePart, mode: string, world: string, level: number }
export type Portal = { part: BasePart, target: string }
export type Lobby = {
	pads: { Pad },
	portals: { Portal },
	dayBoard: SurfaceGui, -- today's points (lobby, west)
	weekBoard: SurfaceGui, -- this week's points (lobby, east)
	soloHubBoard: SurfaceGui, -- today's points again, on the solo island
	teamHubBoard: SurfaceGui, -- today's points again, on the team island
	podium: { TextLabel }, -- hall of fame name labels: 1st, 2nd, 3rd
	sign: TextLabel,
}
export type Level = {
	theme: Themes.Theme,
	folder: Folder,
	layout: Course.Result,
	checkpoints: { [number]: BasePart },
	winIndex: number,
	day: number, -- the day whose route this is
	movers: { { part: BasePart, base: Vector3, dir: Vector3, travel: number, period: number } },
}

local function makePart(props: { [string]: any }, className: string?): BasePart
	local part = Instance.new((className or "Part") :: any) :: BasePart
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = Enum.Material.SmoothPlastic
	for k, v in props do
		(part :: any)[k] = v
	end
	return part
end

-- Scenery: can't be stood on, can't block raycasts, doesn't cast heavy shadows.
local function decorPart(parent: Instance, props: { [string]: any }, className: string?): BasePart
	local part = makePart(props, className)
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Parent = parent
	return part
end

local function label(parent: Instance, text: string, size: number, color: Color3?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = UDim2.fromScale(1, size)
	l.Font = Enum.Font.FredokaOne
	l.TextScaled = true
	l.TextColor3 = color or Color3.new(1, 1, 1)
	l.TextStrokeTransparency = 0.4
	l.Text = text
	l.Parent = parent
	return l
end

local function surfaceGui(part: BasePart, face: Enum.NormalId, pixels: number): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = pixels
	gui.Parent = part
	return gui
end

-- A glowing pad with an arch over it.
local function gate(parent: Instance, pos: Vector3, size: number, color: Color3): BasePart
	local pad = makePart({
		Size = Vector3.new(size, 1, size),
		CFrame = CFrame.new(pos),
		Color = color,
		Material = Enum.Material.Neon,
	})
	pad.Parent = parent
	local h = 12
	for _, side in { -1, 1 } do
		decorPart(parent, {
			Size = Vector3.new(1.5, h, 1.5),
			CFrame = CFrame.new(pos + Vector3.new(side * (size / 2 + 0.5), h / 2, 0)),
			Color = color:Lerp(Color3.new(0, 0, 0), 0.35),
			Material = Enum.Material.SmoothPlastic,
		})
	end
	decorPart(parent, {
		Size = Vector3.new(size + 3, 1.5, 1.5),
		CFrame = CFrame.new(pos + Vector3.new(0, h, 0)),
		Color = color,
		Material = Enum.Material.Neon,
	})
	return pad
end

----------------------------------------------------------------------
-- Positions
----------------------------------------------------------------------
local function hubOrigin(world: string): Vector3
	local o = Themes.Worlds[world].origin
	return Vector3.new(o[1], o[2], o[3])
end

function World.hubSpawn(world: string): CFrame
	if world == "main" then
		return World.MainSpawn
	end
	local o = hubOrigin(world)
	return CFrame.lookAt(o + Vector3.new(0, 3, -12), o + Vector3.new(0, 3, 10))
end

-- Where level `level`'s gate stands on a world island.
local function gatePosition(world: string, level: number): Vector3
	local o = hubOrigin(world)
	local count = Themes.levelCount(world)
	local spacing = if world == "solo" then 30 else 34
	local x = (level - (count + 1) / 2) * spacing
	return o + Vector3.new(x, 0.5, 20)
end
World.gatePosition = gatePosition

-- Arriving on a world island: stand a few steps in front of a level's gate
-- (not on the pad itself), facing it.
function World.gateSpawn(world: string, level: number): CFrame
	local gatePos = gatePosition(world, level)
	local pos = gatePos + Vector3.new(0, 2.5, -9)
	return CFrame.lookAt(pos, Vector3.new(gatePos.X, pos.Y, gatePos.Z))
end

-- Each level course sits far away from the others so every one feels like its own world.
function World.levelOrigin(theme: Themes.Theme): { number }
	local o = hubOrigin(theme.world)
	local dir = if theme.world == "solo" then 1 else -1
	return { o.X + dir * (theme.level - 4.5) * 700, o.Y + 40, o.Z + 500 }
end

----------------------------------------------------------------------
-- Lobby and world hubs
----------------------------------------------------------------------
function World.buildLobby(): Lobby
	local sky = Themes.HubSky.main
	Lighting.ClockTime = sky.clock
	Lighting.Brightness = sky.brightness
	Lighting.OutdoorAmbient = sky.ambient
	if not Lighting:FindFirstChildOfClass("Atmosphere") then
		local atmosphere = Instance.new("Atmosphere")
		atmosphere.Density = sky.density
		atmosphere.Haze = sky.haze
		atmosphere.Color = sky.atmosphere
		atmosphere.Parent = Lighting
	end

	-- Lobby/Main, Lobby/Hub_solo and Lobby/Hub_team are separate areas; each
	-- player only sees the one they're in (see client Ambience).
	local folder = Instance.new("Folder")
	folder.Name = "Lobby"
	folder.Parent = Workspace
	local main = Instance.new("Folder")
	main.Name = "Main"
	main.Parent = folder

	local function disc(parent: Instance, center: Vector3, diameter: number, thickness: number, color: Color3, material: Enum.Material, solid: boolean): BasePart
		local part = makePart({
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(thickness, diameter, diameter),
			CFrame = CFrame.new(center) * CFrame.Angles(0, 0, math.pi / 2),
			Color = color,
			Material = material,
		})
		if not solid then
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
		end
		part.Parent = parent
		return part
	end

	-- A floating grass island with a stone plaza in the middle
	disc(main, C + Vector3.new(0, -1, 0), 190, 2, Color3.fromRGB(110, 190, 95), Enum.Material.Grass, true)
	disc(main, C + Vector3.new(0, -14, 0), 176, 24, Color3.fromRGB(125, 100, 75), Enum.Material.Rock, false)
	disc(main, C + Vector3.new(0, -36, 0), 120, 24, Color3.fromRGB(105, 85, 65), Enum.Material.Rock, false)
	disc(main, C + Vector3.new(0, -56, 0), 60, 20, Color3.fromRGB(90, 75, 60), Enum.Material.Rock, false)
	disc(main, C + Vector3.new(0, 0.1, 0), 80, 0.4, Color3.fromRGB(205, 200, 215), Enum.Material.Pavement, true)
	disc(main, C + Vector3.new(0, 0.15, 0), 66, 0.4, Color3.fromRGB(235, 232, 240), Enum.Material.Marble, true)

	-- Fountain
	disc(main, C + Vector3.new(0, 1, 0), 16, 2, Color3.fromRGB(190, 190, 200), Enum.Material.Marble, true)
	disc(main, C + Vector3.new(0, 1.8, 0), 14, 0.6, Color3.fromRGB(80, 170, 255), Enum.Material.Glass, false).Transparency = 0.2
	makePart({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(7, 2, 2),
		CFrame = CFrame.new(C + Vector3.new(0, 5, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		Color = Color3.fromRGB(200, 200, 210),
		Material = Enum.Material.Marble,
	}).Parent = main
	local top = disc(main, C + Vector3.new(0, 8.5, 0), 6, 1, Color3.fromRGB(200, 200, 210), Enum.Material.Marble, true)
	local spray = Instance.new("ParticleEmitter")
	spray.Color = ColorSequence.new(Color3.fromRGB(200, 235, 255), Color3.fromRGB(120, 200, 255))
	spray.Rate = 60
	spray.Lifetime = NumberRange.new(1, 1.4)
	spray.Speed = NumberRange.new(12, 16)
	spray.SpreadAngle = Vector2.new(12, 12)
	spray.Acceleration = Vector3.new(0, -30, 0)
	spray.Size = NumberSequence.new(0.5, 0.2)
	spray.Transparency = NumberSequence.new(0.2, 1)
	spray.EmissionDirection = Enum.NormalId.Right -- the disc is rotated: +X points up
	spray.Parent = top

	-- Paths from the plaza to the two portals
	for _, side in { -1, 1 } do
		makePart({
			Size = Vector3.new(8, 0.3, 26),
			CFrame = CFrame.new(C + Vector3.new(side * 18, 0.15, 42)) * CFrame.Angles(0, side * 0.35, 0),
			Color = Color3.fromRGB(215, 205, 190),
			Material = Enum.Material.Pavement,
		}).Parent = main
	end

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.CFrame = CFrame.new(C + Vector3.new(0, 0.5, -38)) * CFrame.Angles(0, math.pi, 0)
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Color = Color3.fromRGB(255, 255, 255)
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Parent = main

	local portals: { Portal } = {}
	local function portal(parent: Instance, pos: Vector3, target: string, color: Color3, size: number?)
		local pad = gate(parent, pos, size or 12, color)
		pad.Name = "Portal_" .. target
		pad:SetAttribute("Kind", "Portal")
		pad:SetAttribute("Target", target)
		table.insert(portals, { part = pad, target = target })
	end
	portal(main, C + Vector3.new(-26, 0.5, 52), "solo", Color3.fromRGB(90, 170, 255), 14)
	portal(main, C + Vector3.new(26, 0.5, 52), "team", Color3.fromRGB(180, 90, 255), 14)
	-- glowing rings floating over the portals
	for _, info in { { -26, Color3.fromRGB(90, 170, 255) }, { 26, Color3.fromRGB(180, 90, 255) } } do
		local ring = decorPart(main, {
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.6, 16, 16),
			CFrame = CFrame.new(C + Vector3.new(info[1] :: number, 22, 52)) * CFrame.Angles(0, math.pi / 2, 0),
			Color = info[2],
			Material = Enum.Material.Neon,
			Transparency = 0.35,
		})
		ring.Name = "PortalRing"
	end

	-- Title sign high above the portals
	local sign = makePart({
		Name = "Sign",
		Size = Vector3.new(40, 10, 1),
		CFrame = CFrame.new(C + Vector3.new(0, 30, 62)),
		Color = Color3.fromRGB(40, 40, 60),
	})
	sign.Parent = main
	local signGui = surfaceGui(sign, Enum.NormalId.Front, 30)
	label(signGui, "CHAINED TOWER  綁腳塔", 0.6, Color3.fromRGB(255, 220, 90))
	local eventLine = label(signGui, "", 0.4, Color3.fromRGB(255, 255, 255))
	eventLine.Position = UDim2.fromScale(0, 0.6)

	-- How to play (next to the spawn)
	local howTo = makePart({
		Name = "HowToPlay",
		Size = Vector3.new(16, 10, 0.6),
		CFrame = CFrame.new(C + Vector3.new(-17, 6, -30)) * CFrame.Angles(0, 0.35, 0),
		Color = Color3.fromRGB(45, 50, 70),
	})
	howTo.Parent = main
	local howGui = surfaceGui(howTo, Enum.NormalId.Front, 25)
	local howText = label(
		howGui,
		"HOW TO PLAY 玩法\n🧍 Blue portal: solo world 單人世界\n🔗 Purple portal: team world 組隊世界\n⭐ Earn points every level 每關都有積分\n👑 Daily top 3 · 🪽 weekly top 10 wings",
		1,
		Color3.new(1, 1, 1)
	)
	howText.TextWrapped = true

	-- Leaderboards on stands: today (west) and this week (east)
	local function makeBoard(parent: Instance, name: string, cf: CFrame, size: Vector3, face: Enum.NormalId, color: Color3): SurfaceGui
		local boardPart = makePart({ Name = name, Size = size, CFrame = cf, Color = color })
		boardPart.Parent = parent
		return surfaceGui(boardPart, face, 25)
	end
	local function boardStand(x: number, color: Color3, face: Enum.NormalId, name: string): SurfaceGui
		for _, dz in { -9.5, 9.5 } do
			makePart({
				Size = Vector3.new(1.4, 20, 1.4),
				CFrame = CFrame.new(C + Vector3.new(x, 10, dz)),
				Color = Color3.fromRGB(90, 80, 70),
				Material = Enum.Material.Wood,
			}).Parent = main
		end
		return makeBoard(main, name, CFrame.new(C + Vector3.new(x, 11, 0)), Vector3.new(1, 16, 18), face, color)
	end
	local dayBoard = boardStand(-46, Color3.fromRGB(30, 45, 80), Enum.NormalId.Right, "DayLeaderboard")
	local weekBoard = boardStand(46, Color3.fromRGB(60, 35, 80), Enum.NormalId.Left, "WeekLeaderboard")

	-- Hall of fame podium: last week's top 3
	local podium: { TextLabel } = {}
	local podiumBase = C + Vector3.new(30, 0, -22)
	local steps = {
		{ x = 0, h = 4, color = Color3.fromRGB(255, 205, 60) },
		{ x = -6, h = 3, color = Color3.fromRGB(205, 210, 225) },
		{ x = 6, h = 2, color = Color3.fromRGB(215, 140, 80) },
	}
	for rank, step in steps do
		local block = makePart({
			Size = Vector3.new(6, step.h, 6),
			CFrame = CFrame.new(podiumBase + Vector3.new(step.x, step.h / 2, 0)),
			Color = step.color,
			Material = Enum.Material.Marble,
		})
		block.Parent = main
		local numberGui = surfaceGui(block, Enum.NormalId.Back, 20)
		label(numberGui, tostring(rank), 1, Color3.fromRGB(60, 40, 20))
		local bb = Instance.new("BillboardGui")
		bb.Size = UDim2.fromOffset(160, 60)
		bb.StudsOffset = Vector3.new(0, step.h / 2 + 3, 0)
		bb.MaxDistance = 90
		bb.Parent = block
		local name = Instance.new("TextLabel")
		name.BackgroundTransparency = 1
		name.Size = UDim2.fromScale(1, 1)
		name.Font = Enum.Font.FredokaOne
		name.TextScaled = true
		name.TextColor3 = Color3.new(1, 1, 1)
		name.TextStrokeTransparency = 0.2
		name.Text = "—"
		name.Parent = bb
		podium[rank] = name
	end
	local fameSign = makePart({
		Size = Vector3.new(18, 3, 0.5),
		CFrame = CFrame.new(podiumBase + Vector3.new(0, 11, 3)),
		Color = Color3.fromRGB(60, 45, 20),
	})
	fameSign.Parent = main
	label(surfaceGui(fameSign, Enum.NormalId.Back, 25), "🏆 HALL OF FAME 名人堂", 1, Color3.fromRGB(255, 220, 90))

	-- Reward display: the weekly champion's wings and halo, and the daily crown
	local showBase = C + Vector3.new(-30, 0, -22)
	makePart({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(3, 6, 6),
		CFrame = CFrame.new(showBase + Vector3.new(0, 1.5, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		Color = Color3.fromRGB(235, 232, 240),
		Material = Enum.Material.Marble,
	}).Parent = main
	local wingsShow = Cosmetics.buildWings("Angel", CFrame.lookAt(showBase + Vector3.new(0, 6, 0), showBase + Vector3.new(0, 6, -10)) * CFrame.Angles(0, math.pi, 0))
	Cosmetics.anchor(wingsShow)
	wingsShow.Name = "WingsDisplay"
	wingsShow.Parent = main
	local haloShow = Cosmetics.buildHalo(CFrame.new(showBase + Vector3.new(0, 9, 0)))
	Cosmetics.anchor(haloShow)
	haloShow.Parent = main
	local crownShow = Cosmetics.buildCrown(CFrame.new(showBase + Vector3.new(5, 3.3, 0)))
	Cosmetics.anchor(crownShow)
	crownShow.Parent = main
	makePart({
		Size = Vector3.new(2, 3, 2),
		CFrame = CFrame.new(showBase + Vector3.new(5, 1.5, 0)),
		Color = Color3.fromRGB(235, 232, 240),
		Material = Enum.Material.Marble,
	}).Parent = main
	local showSign = makePart({
		Size = Vector3.new(18, 3, 0.5),
		CFrame = CFrame.new(showBase + Vector3.new(0, 12, 3)),
		Color = Color3.fromRGB(45, 40, 70),
	})
	showSign.Parent = main
	label(surfaceGui(showSign, Enum.NormalId.Back, 25), "🪽 WEEKLY TOP 10 · 👑 DAILY TOP 3", 1, Color3.fromRGB(255, 235, 150))

	-- Trees and lamps around the plaza
	local rng = Random.new(42)
	for i = 0, 15 do
		local a = i / 16 * math.pi * 2 + 0.1
		local r = rng:NextNumber(60, 84)
		local pos = C + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
		if math.abs(pos.X) > 18 or pos.Z < C.Z then -- keep the portal side clear
			local h = rng:NextNumber(10, 16)
			decorPart(main, {
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(h, 1.8, 1.8),
				CFrame = CFrame.new(pos + Vector3.new(0, h / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2),
				Color = Color3.fromRGB(120, 85, 55),
				Material = Enum.Material.Wood,
			})
			decorPart(main, {
				Shape = Enum.PartType.Ball,
				Size = Vector3.new(10, 10, 10),
				CFrame = CFrame.new(pos + Vector3.new(0, h + 2, 0)),
				Color = Color3.fromRGB(80, 170, 80):Lerp(Color3.fromRGB(255, 180, 210), if i % 4 == 0 then 0.6 else 0),
				Material = Enum.Material.Grass,
			})
		end
	end
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2 + math.pi / 8
		local pos = C + Vector3.new(math.cos(a) * 42, 0, math.sin(a) * 42)
		decorPart(main, {
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(8, 0.6, 0.6),
			CFrame = CFrame.new(pos + Vector3.new(0, 4, 0)) * CFrame.Angles(0, 0, math.pi / 2),
			Color = Color3.fromRGB(50, 50, 60),
			Material = Enum.Material.Metal,
		})
		local bulb = decorPart(main, {
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(1.6, 1.6, 1.6),
			CFrame = CFrame.new(pos + Vector3.new(0, 8.6, 0)),
			Color = Color3.fromRGB(255, 230, 160),
			Material = Enum.Material.Neon,
		})
		local light = Instance.new("PointLight")
		light.Range = 14
		light.Brightness = 1.2
		light.Color = Color3.fromRGB(255, 220, 160)
		light.Parent = bulb
	end

	local hubBoards: { [string]: SurfaceGui } = {}

	-- World hubs: an island with one gate per level and a portal home
	local pads: { Pad } = {}
	for _, world in { "solo", "team" } do
		local o = hubOrigin(world)
		local hub = Instance.new("Folder")
		hub.Name = "Hub_" .. world
		hub.Parent = folder
		local islandColor = if world == "solo" then Color3.fromRGB(235, 245, 255) else Color3.fromRGB(245, 230, 245)
		makePart({
			Name = "Island",
			Size = Vector3.new(300, 2, 80),
			CFrame = CFrame.new(o + Vector3.new(0, -1, 0)),
			Color = islandColor,
			Material = Enum.Material.Pavement,
		}).Parent = hub
		-- a rim of grass and rock under the island so it looks like a floating island
		decorPart(hub, {
			Size = Vector3.new(290, 14, 70),
			CFrame = CFrame.new(o + Vector3.new(0, -9, 0)),
			Color = Color3.fromRGB(120, 100, 80),
			Material = Enum.Material.Rock,
		})
		portal(hub, o + Vector3.new(0, 0.5, -30), "main", Color3.fromRGB(255, 255, 255))
		hubBoards[world] = makeBoard(
			hub,
			"TodayLeaderboard",
			CFrame.new(o + Vector3.new(0, 24, 36)), -- above and behind the level gates
			Vector3.new(20, 14, 1),
			Enum.NormalId.Front,
			if world == "solo" then Color3.fromRGB(25, 45, 70) else Color3.fromRGB(55, 30, 70)
		)

		local count = Themes.levelCount(world)
		for level = 1, count do
			local theme = Themes.forLevel(world, level) :: Themes.Theme
			local base = gatePosition(world, level)
			if world == "solo" then
				local pad = gate(hub, base, 10, theme.colors[1])
				pad.Name = "Gate_" .. theme.id
				pad:SetAttribute("Kind", "Pad")
				pad:SetAttribute("Mode", "solo")
				pad:SetAttribute("World", world)
				pad:SetAttribute("Level", level)
				pad:SetAttribute("Theme", theme.id)
				pad:SetAttribute("Count", 0)
				pad:SetAttribute("Max", 1)
				pad:SetAttribute("Countdown", -1)
				table.insert(pads, { part = pad, mode = "solo", world = world, level = level })
			else
				for _, entry in { { mode = "duo", dx = -6.5 }, { mode = "squad", dx = 6.5 } } do
					local tint = if entry.mode == "duo" then Color3.fromRGB(255, 160, 60) else Color3.fromRGB(170, 100, 255)
					local pad = gate(hub, base + Vector3.new(entry.dx, 0, 0), 11, theme.colors[1]:Lerp(tint, 0.45))
					pad.Name = ("Gate_%s_%s"):format(theme.id, entry.mode)
					pad:SetAttribute("Kind", "Pad")
					pad:SetAttribute("Mode", entry.mode)
					pad:SetAttribute("World", world)
					pad:SetAttribute("Level", level)
					pad:SetAttribute("Theme", theme.id)
					pad:SetAttribute("Count", 0)
					pad:SetAttribute("Max", Config.Modes[entry.mode].maxPlayers)
					pad:SetAttribute("Countdown", -1)
					table.insert(pads, { part = pad, mode = entry.mode, world = world, level = level })
				end
			end
		end
	end

	return {
		pads = pads,
		portals = portals,
		dayBoard = dayBoard,
		weekBoard = weekBoard,
		soloHubBoard = hubBoards.solo,
		teamHubBoard = hubBoards.team,
		podium = podium,
		sign = eventLine,
	}
end

----------------------------------------------------------------------
-- Decorations: a few shapes per theme on both sides of the course
----------------------------------------------------------------------
type Decorator = (parent: Instance, pos: Vector3, rng: Random) -> ()

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local function cylinder(parent: Instance, pos: Vector3, height: number, radius: number, color: Color3, material: Enum.Material?)
	decorPart(parent, {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height, radius * 2, radius * 2),
		CFrame = CFrame.new(pos + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		Color = color,
		Material = material or Enum.Material.SmoothPlastic,
	})
end

local function ball(parent: Instance, pos: Vector3, diameter: number, color: Color3, material: Enum.Material?)
	decorPart(parent, {
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(diameter, diameter, diameter),
		CFrame = CFrame.new(pos),
		Color = color,
		Material = material or Enum.Material.SmoothPlastic,
	})
end

local function block(parent: Instance, cf: CFrame, size: Vector3, color: Color3, material: Enum.Material?)
	decorPart(parent, { Size = size, CFrame = cf, Color = color, Material = material or Enum.Material.SmoothPlastic })
end

local decorators: { [string]: Decorator } = {
	trees = function(parent, pos, rng)
		local h = rng:NextNumber(8, 16)
		cylinder(parent, pos, h, 0.9, rgb(120, 85, 55), Enum.Material.Wood)
		ball(parent, pos + Vector3.new(0, h + 2, 0), rng:NextNumber(7, 11), rgb(70, 160, 70), Enum.Material.Grass)
		ball(parent, pos + Vector3.new(1.5, h - 1, 1), rng:NextNumber(4, 6), rgb(90, 185, 80), Enum.Material.Grass)
	end,
	cacti = function(parent, pos, rng)
		local h = rng:NextNumber(6, 12)
		cylinder(parent, pos, h, 1.1, rgb(80, 150, 80))
		cylinder(parent, pos + Vector3.new(1.8, h * 0.4, 0), h * 0.35, 0.6, rgb(80, 150, 80))
		cylinder(parent, pos + Vector3.new(-1.8, h * 0.55, 0), h * 0.3, 0.6, rgb(80, 150, 80))
		block(parent, CFrame.new(pos + Vector3.new(4, 1, 2)) * CFrame.Angles(0, rng:NextNumber(0, 3), 0.2), Vector3.new(4, 2.5, 3), rgb(200, 150, 100), Enum.Material.Sandstone)
	end,
	crystals = function(parent, pos, rng)
		for _ = 1, 3 do
			local h = rng:NextNumber(5, 14)
			block(
				parent,
				CFrame.new(pos + Vector3.new(rng:NextNumber(-3, 3), h / 2, rng:NextNumber(-3, 3))) * CFrame.Angles(rng:NextNumber(-0.3, 0.3), rng:NextNumber(0, 3), rng:NextNumber(-0.3, 0.3)),
				Vector3.new(1.6, h, 1.6),
				rgb(150, 220, 255),
				Enum.Material.Glass
			)
		end
	end,
	candy = function(parent, pos, rng)
		local colors = { rgb(255, 90, 150), rgb(90, 220, 200), rgb(255, 210, 80), rgb(170, 120, 255) }
		local h = rng:NextNumber(7, 13)
		cylinder(parent, pos, h, 0.35, rgb(255, 255, 255))
		decorPart(parent, {
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.8, 6, 6),
			CFrame = CFrame.new(pos + Vector3.new(0, h + 2.5, 0)),
			Color = colors[rng:NextInteger(1, #colors)],
			Material = Enum.Material.SmoothPlastic,
		})
		ball(parent, pos + Vector3.new(3, 1.2, 2), 2.4, colors[rng:NextInteger(1, #colors)])
	end,
	planets = function(parent, pos, rng)
		local colors = { rgb(255, 140, 90), rgb(120, 200, 255), rgb(200, 120, 255), rgb(255, 230, 120) }
		local far = pos + Vector3.new((if rng:NextNumber() < 0.5 then -1 else 1) * rng:NextNumber(20, 60), rng:NextNumber(-10, 40), 0)
		ball(parent, far, rng:NextNumber(8, 22), colors[rng:NextInteger(1, #colors)], Enum.Material.SmoothPlastic)
		for _ = 1, 3 do
			ball(parent, pos + Vector3.new(rng:NextNumber(-8, 8), rng:NextNumber(0, 30), rng:NextNumber(-8, 8)), 0.6, rgb(255, 255, 230), Enum.Material.Neon)
		end
	end,
	jungle = function(parent, pos, rng)
		local h = rng:NextNumber(14, 24)
		cylinder(parent, pos, h, 1.3, rgb(100, 75, 50), Enum.Material.Wood)
		for i = 1, 3 do
			block(
				parent,
				CFrame.new(pos + Vector3.new(0, h, 0)) * CFrame.Angles(0, i * 2.1 + rng:NextNumber(0, 0.5), 0.35) * CFrame.new(3.5, 0, 0),
				Vector3.new(8, 0.4, 3),
				rgb(60, 150, 60),
				Enum.Material.Grass
			)
		end
		cylinder(parent, pos + Vector3.new(0, h - 8, 1.4), 8, 0.15, rgb(70, 120, 50))
	end,
	rocks = function(parent, pos, rng)
		local h = rng:NextNumber(10, 22)
		block(parent, CFrame.new(pos + Vector3.new(0, h / 2, 0)) * CFrame.Angles(0, rng:NextNumber(0, 3), rng:NextNumber(-0.15, 0.15)), Vector3.new(4, h, 4), rgb(55, 45, 45), Enum.Material.Basalt)
		block(parent, CFrame.new(pos + Vector3.new(0, h * 0.4, 0)) * CFrame.Angles(0, rng:NextNumber(0, 3), 0), Vector3.new(4.3, 0.5, 4.3), rgb(255, 110, 30), Enum.Material.Neon)
	end,
	harbor = function(parent, pos, rng)
		if rng:NextNumber() < 0.5 then
			-- a little boat
			local hull = CFrame.new(pos + Vector3.new(0, -8, 0)) * CFrame.Angles(0, rng:NextNumber(-0.4, 0.4), 0)
			block(parent, hull, Vector3.new(5, 2.5, 12), rgb(150, 90, 60), Enum.Material.WoodPlanks)
			cylinder(parent, hull.Position + Vector3.new(0, 1, 0), 12, 0.3, rgb(120, 90, 60))
			block(parent, CFrame.new(hull.Position + Vector3.new(0, 8, 0.6)), Vector3.new(0.2, 7, 5), rgb(250, 250, 245))
		else
			cylinder(parent, pos + Vector3.new(0, -10, 0), 12, 0.8, rgb(130, 95, 65), Enum.Material.Wood)
			ball(parent, pos + Vector3.new(2.5, -8, 0), 1.6, rgb(240, 60, 50))
		end
	end,
	factory = function(parent, pos, rng)
		if rng:NextNumber() < 0.5 then
			local gear = decorPart(parent, {
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(1, 9, 9),
				CFrame = CFrame.new(pos + Vector3.new(0, rng:NextNumber(3, 14), 0)) * CFrame.Angles(0, math.pi / 2, 0),
				Color = rgb(150, 150, 160),
				Material = Enum.Material.Metal,
			})
			for i = 0, 5 do
				block(parent, gear.CFrame * CFrame.Angles(i * math.pi / 3, 0, 0) * CFrame.new(0, 4.8, 0), Vector3.new(1, 1.6, 1.4), rgb(150, 150, 160), Enum.Material.Metal)
			end
		else
			cylinder(parent, pos, rng:NextNumber(12, 24), 1.4, rgb(110, 105, 100), Enum.Material.Metal)
			block(parent, CFrame.new(pos + Vector3.new(0, 4, 0)), Vector3.new(3.2, 0.6, 3.2), rgb(255, 200, 40), Enum.Material.SmoothPlastic)
		end
	end,
	palms = function(parent, pos, rng)
		local h = rng:NextNumber(10, 16)
		local lean = rng:NextNumber(-0.25, 0.25)
		decorPart(parent, {
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(h, 1.4, 1.4),
			CFrame = CFrame.new(pos + Vector3.new(0, h / 2, 0)) * CFrame.Angles(lean, 0, math.pi / 2),
			Color = rgb(160, 120, 80),
			Material = Enum.Material.Wood,
		})
		for i = 1, 5 do
			block(parent, CFrame.new(pos + Vector3.new(0, h, 0)) * CFrame.Angles(0, i * 1.25, -0.4) * CFrame.new(3.2, 0, 0), Vector3.new(6.5, 0.3, 1.8), rgb(60, 170, 70), Enum.Material.Grass)
		end
		ball(parent, pos + Vector3.new(0.6, h - 0.8, 0.3), 1.1, rgb(120, 80, 40))
	end,
	clouds = function(parent, pos, rng)
		local c = pos + Vector3.new(0, rng:NextNumber(-12, 6), 0)
		for _ = 1, 4 do
			ball(parent, c + Vector3.new(rng:NextNumber(-5, 5), rng:NextNumber(-1, 2), rng:NextNumber(-4, 4)), rng:NextNumber(5, 9), rgb(255, 255, 255))
		end
		if rng:NextNumber() < 0.3 then
			-- a little golden pillar of the sky city
			cylinder(parent, c + Vector3.new(0, 2, 0), rng:NextNumber(6, 12), 1, rgb(255, 225, 140), Enum.Material.Marble)
		end
	end,
	pines = function(parent, pos, rng)
		local h = rng:NextNumber(10, 18)
		cylinder(parent, pos, h * 0.35, 0.7, rgb(110, 80, 55), Enum.Material.Wood)
		for i = 0, 2 do
			local size = (3 - i) * 2.6
			block(parent, CFrame.new(pos + Vector3.new(0, h * 0.35 + i * h * 0.22, 0)) * CFrame.Angles(0, i * 0.7, 0), Vector3.new(size, h * 0.25, size), rgb(60, 110, 80), Enum.Material.Grass)
			block(parent, CFrame.new(pos + Vector3.new(0, h * 0.35 + i * h * 0.22 + h * 0.13, 0)) * CFrame.Angles(0, i * 0.7, 0), Vector3.new(size * 0.9, 0.4, size * 0.9), rgb(250, 252, 255), Enum.Material.Snow)
		end
	end,
	neon = function(parent, pos, rng)
		local colors = { rgb(255, 60, 200), rgb(60, 240, 255), rgb(170, 90, 255), rgb(255, 230, 60) }
		local h = rng:NextNumber(14, 30)
		block(parent, CFrame.new(pos + Vector3.new(0, h / 2 - 10, 0)), Vector3.new(6, h, 6), rgb(25, 25, 40))
		for i = 1, 3 do
			block(parent, CFrame.new(pos + Vector3.new(0, i * h / 4 - 10, 0)), Vector3.new(6.3, 0.4, 6.3), colors[rng:NextInteger(1, #colors)], Enum.Material.Neon)
		end
	end,
	castle = function(parent, pos, rng)
		local h = rng:NextNumber(14, 26)
		cylinder(parent, pos, h, 2.5, rgb(130, 125, 140), Enum.Material.Cobblestone)
		decorPart(parent, {
			Size = Vector3.new(5.5, 4, 5.5),
			CFrame = CFrame.new(pos + Vector3.new(0, h + 2, 0)),
			Color = rgb(110, 60, 160),
			Material = Enum.Material.Slate,
		})
		block(parent, CFrame.new(pos + Vector3.new(0, h + 6, 0)), Vector3.new(0.3, 4, 0.3), rgb(80, 60, 50))
		block(parent, CFrame.new(pos + Vector3.new(1.2, h + 7, 0)), Vector3.new(2.2, 1.3, 0.1), rgb(200, 60, 200), Enum.Material.Neon)
	end,
}

----------------------------------------------------------------------
-- Level courses
----------------------------------------------------------------------
local function crackIcon(part: BasePart)
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back, Enum.NormalId.Left, Enum.NormalId.Right } do
		local gui = surfaceGui(part, face, 20)
		gui.LightInfluence = 0
		local text = Instance.new("TextLabel")
		text.BackgroundTransparency = 1
		text.Size = UDim2.fromScale(1, 1)
		text.TextScaled = true
		text.Text = "🔨"
		text.TextTransparency = 0.15
		text.Parent = gui
	end
end

local function makeSpinner(folder: Folder, bar: Course.Piece, pivotPiece: Course.Piece?): BasePart
	local pivotPos = Vector3.new(bar.cx, (pivotPiece and pivotPiece.cy) or bar.cy, bar.cz)
	local pivot = makePart({
		Name = "SpinnerPivot",
		Size = Vector3.new(1.2, (pivotPiece and pivotPiece.sy) or 2, 1.2),
		CFrame = CFrame.new(pivotPos),
		Color = Color3.fromRGB(60, 60, 70),
		Material = Enum.Material.Metal,
		CanCollide = false,
	})
	pivot.Parent = folder

	local part = makePart({
		Name = "Spinner",
		Size = Vector3.new(bar.sx, bar.sy, bar.sz),
		CFrame = CFrame.new(bar.cx, bar.cy, bar.cz),
		Color = Color3.fromRGB(235, 70, 70),
		Material = Enum.Material.Neon,
		Anchored = false,
		CustomPhysicalProperties = PhysicalProperties.new(2, 0.2, 0.5),
	})
	part:SetAttribute("Kind", "Breakable")
	part:SetAttribute("Section", bar.section)

	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, bar.cy - pivotPos.Y, 0)
	a0.Axis = Vector3.yAxis
	a0.SecondaryAxis = Vector3.xAxis
	a0.Parent = pivot
	local a1 = Instance.new("Attachment")
	a1.Axis = Vector3.yAxis
	a1.SecondaryAxis = Vector3.xAxis
	a1.Parent = part

	local hinge = Instance.new("HingeConstraint")
	hinge.Attachment0 = a0
	hinge.Attachment1 = a1
	hinge.ActuatorType = Enum.ActuatorType.Motor
	hinge.MotorMaxTorque = 1e9
	hinge.AngularVelocity = bar.spinSpeed or 2
	hinge.Parent = part

	part.Parent = folder
	return part
end

local KIND_NAMES = {
	platform = "Platform",
	floor = "Platform",
	rock = "Platform",
	checkpoint = "Checkpoint",
	win = "Win",
	kill = "Kill",
	breakable = "Breakable",
	truss = "Truss",
	pad = "JumpPad",
	vanish = "Vanish",
	current = "Current",
	mover = "Mover",
}

-- Builds a level as it is on `day` (the route changes every day).
function World.buildLevel(theme: Themes.Theme, parent: Instance, day: number): Level
	local origin = World.levelOrigin(theme)
	local seed = Course.dailySeed(theme, day)
	local layout = Course.generate(theme, origin, Course.rng(seed), seed, Course.sequenceFor(theme, day))
	local folder = Instance.new("Folder")
	folder.Name = "Level_" .. theme.id
	folder:SetAttribute("Theme", theme.id)
	local checkpoints: { [number]: BasePart } = {}
	local spinners: { BasePart } = {}
	local movers = {}

	local slippery = if theme.slippery then PhysicalProperties.new(0.9, 0.04, 0, 100, 1) else nil

	local pivots: { Course.Piece } = {}
	for _, piece in layout.pieces do
		if piece.kind == "pivot" then
			table.insert(pivots, piece)
		end
	end

	for _, piece in layout.pieces do
		local size = Vector3.new(piece.sx, piece.sy, piece.sz)
		local cf = CFrame.new(piece.cx, piece.cy, piece.cz)
		local kind = piece.kind
		local part: BasePart? = nil
		local color = theme.colors[((piece.section - 1) % #theme.colors) + 1]

		if kind == "rock" then
			part = makePart({ Size = size, CFrame = cf, Color = color:Lerp(Color3.fromRGB(80, 75, 85), 0.35), Material = Enum.Material.Rock })
		elseif kind == "platform" or kind == "floor" then
			part = makePart({ Size = size, CFrame = cf, Color = color, Material = theme.material })
			if slippery then
				(part :: BasePart).CustomPhysicalProperties = slippery
			end
		elseif kind == "checkpoint" or kind == "win" then
			local isWin = kind == "win"
			local p = makePart({
				Size = size,
				CFrame = cf,
				Color = if isWin then Color3.fromRGB(255, 205, 60) else theme.checkpoint,
				Material = if isWin then Enum.Material.Neon else Enum.Material.SmoothPlastic,
			})
			p:SetAttribute("Index", piece.index)
			checkpoints[piece.index :: number] = p
			-- a soft glowing border and a small flag on the outside corner: easy to
			-- spot without shouting. The flag turns green once your team reached it.
			local topY = piece.cy + piece.sy / 2
			local halfX, halfZ = piece.sx / 2, piece.sz / 2
			for _, edge in { { 0, halfZ, piece.sx, 0.4 }, { 0, -halfZ, piece.sx, 0.4 }, { halfX, 0, 0.4, piece.sz }, { -halfX, 0, 0.4, piece.sz } } do
				local trim = decorPart(folder, {
					Size = Vector3.new(edge[3], 0.15, edge[4]),
					CFrame = CFrame.new(piece.cx + edge[1], topY + 0.08, piece.cz + edge[2]),
					Color = Color3.new(1, 1, 1),
					Material = Enum.Material.Neon,
					Transparency = 0.35,
				})
				trim.Name = "CheckpointTrim"
				trim:SetAttribute("Index", piece.index)
			end
			if not isWin then
				local sx = if piece.cx >= layout.center[1] then 1 else -1
				local sz = if piece.cz >= layout.center[2] then 1 else -1
				local base = Vector3.new(piece.cx + sx * (halfX - 0.8), topY, piece.cz + sz * (halfZ - 0.8))
				decorPart(folder, {
					Shape = Enum.PartType.Cylinder,
					Size = Vector3.new(6, 0.3, 0.3),
					CFrame = CFrame.new(base + Vector3.new(0, 3, 0)) * CFrame.Angles(0, 0, math.pi / 2),
					Color = Color3.fromRGB(230, 230, 235),
					Material = Enum.Material.Metal,
				})
				local flag = decorPart(folder, {
					Size = Vector3.new(0.1, 1.4, 2.2),
					CFrame = CFrame.new(base + Vector3.new(0, 5.2, 0)) * CFrame.new(0, 0, -sz * 1.1),
					Color = theme.checkpoint:Lerp(Color3.fromRGB(255, 120, 80), 0.5),
					Material = Enum.Material.SmoothPlastic,
				})
				flag.Name = "CheckpointFlag"
				flag:SetAttribute("Index", piece.index)
			end
			local bb = Instance.new("BillboardGui")
			bb.Size = UDim2.fromOffset(60, 36)
			bb.StudsOffset = Vector3.new(0, 3, 0)
			bb.MaxDistance = 50
			local t = Instance.new("TextLabel")
			t.BackgroundTransparency = 1
			t.Size = UDim2.fromScale(1, 1)
			t.Font = Enum.Font.FredokaOne
			t.TextScaled = true
			t.TextColor3 = Color3.new(1, 1, 1)
			t.TextStrokeTransparency = 0.3
			t.Text = if kind == "win" then "🏆" else tostring(piece.index)
			t.Parent = bb
			bb.Parent = p
			part = p
		elseif kind == "kill" then
			part = makePart({ Size = size, CFrame = cf, Color = Color3.fromRGB(255, 90, 20), Material = Enum.Material.CrackedLava })
		elseif kind == "breakable" then
			part = makePart({ Size = size, CFrame = cf, Color = Color3.fromRGB(190, 120, 70), Material = Enum.Material.Cobblestone })
			crackIcon(part :: BasePart)
		elseif kind == "truss" then
			part = makePart({ Size = size, CFrame = cf, Color = Color3.fromRGB(200, 200, 210), Material = Enum.Material.Metal }, "TrussPart")
		elseif kind == "pad" then
			local pad = makePart({ Size = size, CFrame = cf, Color = theme.pad, Material = Enum.Material.Neon })
			pad:SetAttribute("Boost", piece.boost or 60)
			part = pad
		elseif kind == "vanish" then
			part = makePart({ Size = size, CFrame = cf, Color = color:Lerp(Color3.new(1, 1, 1), 0.4), Material = Enum.Material.Glass, Transparency = 0.15 })
		elseif kind == "current" then
			local isBelt = piece.style == "belt"
			local p = makePart({
				Size = size,
				CFrame = cf,
				Color = if isBelt then Color3.fromRGB(45, 45, 50) else Color3.fromRGB(50, 150, 255),
				Material = if isBelt then Enum.Material.DiamondPlate else Enum.Material.Glass,
				Transparency = if isBelt then 0 else 0.25,
			})
			p:SetAttribute("FlowX", piece.flowX or 0)
			p:SetAttribute("FlowZ", piece.flowZ or 0)
			p:SetAttribute("FlowSpeed", piece.flowSpeed or 10)
			p:SetAttribute("Style", piece.style or "water")
			part = p
		elseif kind == "mover" then
			local p = makePart({ Size = size, CFrame = cf, Color = color:Lerp(Color3.fromRGB(255, 220, 90), 0.5), Material = theme.material })
			local base = Vector3.new(piece.cx, piece.cy, piece.cz)
			local dir = Vector3.new(piece.moveX or 0, 0, piece.moveZ or 1)
			p:SetAttribute("Travel", piece.travel or 0)
			p:SetAttribute("Period", piece.period or 6)
			p:SetAttribute("BasePos", base)
			p:SetAttribute("MoveDir", dir)
			table.insert(movers, { part = p, base = base, dir = dir, travel = piece.travel or 0, period = piece.period or 6 })
			part = p
		elseif kind == "spinner" then
			local best: Course.Piece? = nil
			for _, pv in pivots do
				if math.abs(pv.cx - piece.cx) < 0.1 and math.abs(pv.cz - piece.cz) < 0.1 then
					best = pv
				end
			end
			table.insert(spinners, makeSpinner(folder, piece, best))
		end

		if part then
			local p = part :: BasePart
			local kindName = KIND_NAMES[kind] or kind
			p.Name = kindName
			p:SetAttribute("Kind", kindName)
			p:SetAttribute("Section", piece.section)
			p.Parent = folder
		end
	end

	-- Scenery around the climb
	local decor = Instance.new("Folder")
	decor.Name = "Decor"
	decor.Parent = folder
	local decorate = decorators[theme.decor]
	local rng = Random.new(theme.seed + 7)
	local lane = Themes.Worlds[theme.world].lane
	local center = Vector3.new(layout.center[1], 0, layout.center[2])
	local height = layout.top - layout.bottom
	if decorate then
		for i = 0, 27 do
			local a = i / 28 * math.pi * 2 + rng:NextNumber(-0.1, 0.1)
			local r = layout.ringHalf + lane + rng:NextNumber(14, 42)
			local y = layout.bottom + rng:NextNumber(-8, height + 4)
			decorate(decor, center + Vector3.new(math.cos(a) * r, y, math.sin(a) * r), rng)
		end
	end
	if theme.floor then
		decorPart(decor, {
			Name = "Backdrop",
			Size = Vector3.new(layout.ringHalf * 2 + 320, 2, layout.ringHalf * 2 + 320),
			CFrame = CFrame.new(center + Vector3.new(0, layout.bottom - 45, 0)),
			Color = theme.floor.color,
			Material = theme.floor.material,
			Transparency = theme.floor.transparency or 0,
		})
	end

	-- The landmark you climb around (solid, so nobody cuts through the middle)
	local lm = theme.landmark
	local coreHalf = layout.coreHalf
	local baseY = layout.bottom - 30
	local function chunk(y0: number, y1: number, half: number, color: Color3, material: Enum.Material)
		local h = y1 - y0
		local props: { [string]: any } = { Color = color, Material = material }
		if lm.round then
			props.Shape = Enum.PartType.Cylinder
			props.Size = Vector3.new(h, half * 2, half * 2)
			props.CFrame = CFrame.new(center + Vector3.new(0, (y0 + y1) / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2)
		else
			props.Size = Vector3.new(half * 2, h, half * 2)
			props.CFrame = CFrame.new(center + Vector3.new(0, (y0 + y1) / 2, 0))
		end
		-- not solid: you can't stand on its ledges to skip the route
		local part = decorPart(decor, props)
		part.Name = "Landmark"
	end
	if lm.shape == "taper" then
		-- mountain / pyramid / cake: tiers getting smaller towards the top
		local tiers = 7
		local topY = layout.top + 18
		for t = 0, tiers - 1 do
			local y0 = baseY + (topY - baseY) * t / tiers
			local y1 = baseY + (topY - baseY) * (t + 1) / tiers
			local half = coreHalf * (1 - t / tiers * 0.7)
			local color = lm.colors[1]:Lerp(lm.colors[2], t / (tiers - 1))
			if lm.cap and t == tiers - 1 then
				color = lm.cap
			end
			chunk(y0, y1, half, color, if lm.cap and t == tiers - 1 then Enum.Material.Snow else lm.material)
		end
	else
		-- tower / lighthouse / station: a striped column with a lit top
		local topY = layout.top + 10
		local band = 12
		local y0 = baseY
		local i = 0
		while y0 < topY do
			local y1 = math.min(topY, y0 + band)
			chunk(y0, y1, coreHalf * 0.8, lm.colors[(i % 2) + 1], lm.material)
			y0 = y1
			i += 1
		end
		decorPart(decor, {
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(coreHalf, coreHalf, coreHalf),
			CFrame = CFrame.new(center + Vector3.new(0, topY + coreHalf * 0.3, 0)),
			Color = lm.colors[2],
			Material = Enum.Material.Neon,
			Transparency = 0.2,
		})
	end

	-- What waits at the top (on the finish pad)
	local win = layout.checkpoints[#layout.checkpoints]
	local goalPos = Vector3.new(win[1], win[2], win[3])
	local outward = (goalPos - Vector3.new(center.X, goalPos.Y, center.Z)).Unit
	local goalBase = goalPos + outward * 3
	if lm.goal == "flag" then
		decorPart(decor, {
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(16, 0.6, 0.6),
			CFrame = CFrame.new(goalBase + Vector3.new(0, 8, 0)) * CFrame.Angles(0, 0, math.pi / 2),
			Color = Color3.fromRGB(240, 240, 245),
			Material = Enum.Material.Metal,
		})
		decorPart(decor, {
			Size = Vector3.new(0.2, 4, 6),
			CFrame = CFrame.lookAt(goalBase + Vector3.new(0, 14, 0), goalBase + Vector3.new(0, 14, 0) + outward) * CFrame.new(3, 0, 0) * CFrame.Angles(0, math.pi / 2, 0),
			Color = Color3.fromRGB(255, 70, 70),
			Material = Enum.Material.SmoothPlastic,
		})
	elseif lm.goal == "station" then
		local hub = goalPos + Vector3.new(0, 16, 0)
		decorPart(decor, {
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(10, 8, 8),
			CFrame = CFrame.new(hub) * CFrame.Angles(0, 0, math.pi / 2),
			Color = Color3.fromRGB(220, 225, 235),
			Material = Enum.Material.Metal,
		})
		for _, side in { -1, 1 } do
			decorPart(decor, {
				Size = Vector3.new(16, 0.3, 5),
				CFrame = CFrame.new(hub + Vector3.new(side * 13, 0, 0)),
				Color = Color3.fromRGB(40, 70, 160),
				Material = Enum.Material.Glass,
			})
		end
		decorPart(decor, {
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.6, 18, 18),
			CFrame = CFrame.new(hub) * CFrame.Angles(0, 0, math.pi / 2) * CFrame.Angles(0.3, 0, 0),
			Color = Color3.fromRGB(90, 220, 255),
			Material = Enum.Material.Neon,
			Transparency = 0.4,
		})
	elseif lm.goal == "beacon" then
		local light = decorPart(decor, {
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(4, 4, 4),
			CFrame = CFrame.new(goalBase + Vector3.new(0, 9, 0)),
			Color = Color3.fromRGB(255, 240, 160),
			Material = Enum.Material.Neon,
		})
		local glow = Instance.new("PointLight")
		glow.Range = 30
		glow.Brightness = 3
		glow.Parent = light
		decorPart(decor, {
			Size = Vector3.new(1, 7, 1),
			CFrame = CFrame.new(goalBase + Vector3.new(0, 3.5, 0)),
			Color = Color3.fromRGB(60, 60, 70),
			Material = Enum.Material.Metal,
		})
	else -- crown: a golden arch over the finish
		for _, side in { -1, 1 } do
			decorPart(decor, {
				Size = Vector3.new(1.5, 12, 1.5),
				CFrame = CFrame.new(goalPos + Vector3.new(side * 6, 6, 0)),
				Color = Color3.fromRGB(255, 210, 90),
				Material = Enum.Material.Marble,
			})
		end
		decorPart(decor, {
			Size = Vector3.new(14, 1.5, 1.5),
			CFrame = CFrame.new(goalPos + Vector3.new(0, 12, 0)),
			Color = Color3.fromRGB(255, 220, 110),
			Material = Enum.Material.Neon,
		})
	end

	folder.Parent = parent
	-- network ownership can only be set once the parts are in the Workspace
	for _, bar in spinners do
		bar:SetNetworkOwner(nil)
	end
	return {
		theme = theme,
		folder = folder,
		layout = layout,
		checkpoints = checkpoints,
		winIndex = #layout.checkpoints - 1,
		day = day,
		movers = movers,
	}
end

-- Where to put a player standing on checkpoint `index` (spread out a little).
function World.checkpointCFrame(level: Level, index: number, slot: number): CFrame
	local cp = level.layout.checkpoints[index + 1]
	local offsets = { Vector3.new(-2, 0, -1), Vector3.new(2, 0, 1), Vector3.new(2, 0, -1), Vector3.new(-2, 0, 1) }
	local offset = offsets[((slot - 1) % 4) + 1]
	local pos = Vector3.new(cp[1], cp[2] + 3, cp[3]) + offset
	return CFrame.lookAt(pos, pos + Vector3.new(0, 0, 1))
end

return World
