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

local World = {}

World.MainSpawn = CFrame.new(0, 3, -115)

export type Pad = { part: BasePart, mode: string, world: string, level: number }
export type Portal = { part: BasePart, target: string }
export type Lobby = {
	pads: { Pad },
	portals: { Portal },
	soloBoard: SurfaceGui, -- today's solo ranking (lobby, left wall)
	teamBoard: SurfaceGui, -- today's team ranking (lobby, right wall)
	pointsBoard: SurfaceGui, -- all-time daily points (lobby, behind the spawn)
	soloHubBoard: SurfaceGui, -- today's solo ranking again, on the solo island
	teamHubBoard: SurfaceGui, -- today's team ranking again, on the team island
	sign: TextLabel,
}
export type Level = {
	theme: Themes.Theme,
	folder: Folder,
	layout: Course.Result,
	checkpoints: { [number]: BasePart },
	winIndex: number,
	day: number, -- the day whose route this is
	movers: { { part: BasePart, x: number, y: number, z: number, travel: number, period: number } },
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

	local folder = Instance.new("Folder")
	folder.Name = "Lobby"
	folder.Parent = Workspace

	local ground = makePart({
		Name = "Ground",
		Size = Vector3.new(400, 2, 400),
		CFrame = CFrame.new(0, -1, -40),
		Color = Color3.fromRGB(110, 190, 95),
		Material = Enum.Material.Grass,
	})
	ground.Parent = folder
	makePart({
		Name = "Plaza",
		Size = Vector3.new(90, 0.4, 70),
		CFrame = CFrame.new(0, 0.2, -100),
		Color = Color3.fromRGB(220, 220, 230),
		Material = Enum.Material.Pavement,
	}).Parent = folder

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.CFrame = CFrame.new(0, 0.5, -115) * CFrame.Angles(0, math.pi, 0)
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Color = Color3.fromRGB(255, 255, 255)
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Parent = folder

	local portals: { Portal } = {}
	local function portal(parent: Instance, pos: Vector3, target: string, color: Color3)
		local pad = gate(parent, pos, 12, color)
		pad.Name = "Portal_" .. target
		pad:SetAttribute("Kind", "Portal")
		pad:SetAttribute("Target", target)
		table.insert(portals, { part = pad, target = target })
	end
	portal(folder, Vector3.new(-20, 0.5, -86), "solo", Color3.fromRGB(90, 170, 255))
	portal(folder, Vector3.new(20, 0.5, -86), "team", Color3.fromRGB(180, 90, 255))

	-- Title sign
	local sign = makePart({
		Name = "Sign",
		Size = Vector3.new(34, 9, 1),
		CFrame = CFrame.new(0, 16, -66),
		Color = Color3.fromRGB(40, 40, 60),
	})
	sign.Parent = folder
	local signGui = surfaceGui(sign, Enum.NormalId.Front, 30)
	label(signGui, "CHAINED TOWER  綁腳塔", 0.6, Color3.fromRGB(255, 220, 90))
	local eventLine = label(signGui, "", 0.4, Color3.fromRGB(255, 255, 255))
	eventLine.Position = UDim2.fromScale(0, 0.6)

	-- Two weekly leaderboards: solo on the left wall, teams on the right wall
	local function makeBoard(parent: Instance, name: string, cf: CFrame, size: Vector3, face: Enum.NormalId, color: Color3): SurfaceGui
		local boardPart = makePart({ Name = name, Size = size, CFrame = cf, Color = color })
		boardPart.Parent = parent
		return surfaceGui(boardPart, face, 25)
	end
	local sideSize = Vector3.new(1, 14, 18)
	local soloBoard = makeBoard(folder, "SoloLeaderboard", CFrame.new(-42, 8, -105), sideSize, Enum.NormalId.Right, Color3.fromRGB(25, 45, 70))
	local teamBoard = makeBoard(folder, "TeamLeaderboard", CFrame.new(42, 8, -105), sideSize, Enum.NormalId.Left, Color3.fromRGB(55, 30, 70))
	local pointsBoard = makeBoard(folder, "PointsLeaderboard", CFrame.new(0, 9, -134), Vector3.new(20, 14, 1), Enum.NormalId.Back, Color3.fromRGB(60, 45, 20))
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
		local spacing = if world == "solo" then 30 else 34
		for level = 1, count do
			local theme = Themes.forLevel(world, level) :: Themes.Theme
			local x = (level - (count + 1) / 2) * spacing
			local base = o + Vector3.new(x, 0.5, 20)
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
		soloBoard = soloBoard,
		teamBoard = teamBoard,
		pointsBoard = pointsBoard,
		soloHubBoard = hubBoards.solo,
		teamHubBoard = hubBoards.team,
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

		if kind == "platform" or kind == "floor" then
			part = makePart({ Size = size, CFrame = cf, Color = color, Material = theme.material })
			if slippery then
				(part :: BasePart).CustomPhysicalProperties = slippery
			end
		elseif kind == "checkpoint" or kind == "win" then
			local p = makePart({
				Size = size,
				CFrame = cf,
				Color = if kind == "win" then Color3.fromRGB(255, 205, 60) else theme.checkpoint,
				Material = Enum.Material.Neon,
			})
			p:SetAttribute("Index", piece.index)
			checkpoints[piece.index :: number] = p
			local bb = Instance.new("BillboardGui")
			bb.Size = UDim2.fromOffset(80, 50)
			bb.StudsOffset = Vector3.new(0, 4, 0)
			bb.MaxDistance = 80
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
			p:SetAttribute("Travel", piece.travel or 0)
			p:SetAttribute("Period", piece.period or 6)
			p:SetAttribute("BaseZ", piece.cz)
			table.insert(movers, { part = p, x = piece.cx, y = piece.cy, z = piece.cz, travel = piece.travel or 0, period = piece.period or 6 })
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

	-- Scenery
	local decor = Instance.new("Folder")
	decor.Name = "Decor"
	decor.Parent = folder
	local decorate = decorators[theme.decor]
	local rng = Random.new(theme.seed + 7)
	local lane = Themes.Worlds[theme.world].lane
	if decorate then
		local z = origin[3] - 10
		while z < origin[3] + layout.length + 10 do
			for _, side in { -1, 1 } do
				local offset = side * rng:NextNumber(lane + 12, lane + 34)
				local y = origin[2] + (z - origin[3]) / layout.length * (layout.checkpoints[#layout.checkpoints][2] - origin[2]) - rng:NextNumber(4, 16)
				decorate(decor, Vector3.new(origin[1] + offset, y, z + rng:NextNumber(-4, 4)), rng)
			end
			z += rng:NextNumber(14, 22)
		end
	end
	if theme.floor then
		decorPart(decor, {
			Name = "Backdrop",
			Size = Vector3.new(lane * 2 + 260, 2, layout.length + 260),
			CFrame = CFrame.new(origin[1], layout.bottom - 45, origin[3] + layout.length / 2),
			Color = theme.floor.color,
			Material = theme.floor.material,
			Transparency = theme.floor.transparency or 0,
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
