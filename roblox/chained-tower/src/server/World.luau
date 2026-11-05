--!strict
-- Builds the lobby once and turns a TowerLayout result into real parts.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local TowerLayout = require(Shared.TowerLayout)

local World = {}

World.LobbySpawn = CFrame.new(0, 3, -115)

export type Pad = { part: BasePart, mode: string }
export type Lobby = { pads: { Pad }, board: SurfaceGui, sign: TextLabel }
export type Tower = {
	folder: Folder,
	layout: TowerLayout.Result,
	checkpoints: { [number]: BasePart },
	winIndex: number,
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

----------------------------------------------------------------------
-- Lobby
----------------------------------------------------------------------
function World.buildLobby(): Lobby
	Lighting.ClockTime = 14.5
	Lighting.Brightness = 2.2
	Lighting.OutdoorAmbient = Color3.fromRGB(150, 150, 170)
	if not Lighting:FindFirstChildOfClass("Atmosphere") then
		local atmosphere = Instance.new("Atmosphere")
		atmosphere.Density = 0.25
		atmosphere.Haze = 1
		atmosphere.Color = Color3.fromRGB(200, 220, 255)
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
	ground:SetAttribute("Kind", "Ground")
	ground:SetAttribute("Section", -1)
	ground.Parent = folder

	local plaza = makePart({
		Name = "Plaza",
		Size = Vector3.new(90, 0.4, 70),
		CFrame = CFrame.new(0, 0.2, -100),
		Color = Color3.fromRGB(220, 220, 230),
		Material = Enum.Material.Pavement,
	})
	plaza:SetAttribute("Kind", "Ground")
	plaza:SetAttribute("Section", -1)
	plaza.Parent = folder

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

	local pads: { Pad } = {}
	local padInfo = {
		{ mode = "solo", x = -24, z = -90, color = Color3.fromRGB(120, 200, 255) },
		{ mode = "duo", x = 0, z = -86, color = Color3.fromRGB(255, 150, 40) },
		{ mode = "squad", x = 24, z = -90, color = Color3.fromRGB(170, 90, 255) },
	}
	for _, info in padInfo do
		local pad = makePart({
			Name = "Pad_" .. info.mode,
			Size = Vector3.new(12, 1, 12),
			CFrame = CFrame.new(info.x, 0.5, info.z),
			Color = info.color,
			Material = Enum.Material.Neon,
		})
		pad:SetAttribute("Kind", "Pad")
		pad:SetAttribute("Mode", info.mode)
		pad:SetAttribute("Count", 0)
		pad:SetAttribute("Max", Config.Modes[info.mode].maxPlayers)
		pad:SetAttribute("Countdown", -1)
		pad.Parent = folder
		table.insert(pads, { part = pad, mode = info.mode })
	end

	-- Title sign
	local sign = makePart({
		Name = "Sign",
		Size = Vector3.new(34, 9, 1),
		CFrame = CFrame.new(0, 14, -72),
		Color = Color3.fromRGB(40, 40, 60),
	})
	sign.Parent = folder
	local signGui = Instance.new("SurfaceGui")
	signGui.Face = Enum.NormalId.Front
	signGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	signGui.PixelsPerStud = 30
	signGui.Parent = sign
	label(signGui, "CHAINED TOWER  綁腳塔", 0.6, Color3.fromRGB(255, 220, 90))
	local eventLine = label(signGui, "", 0.4, Color3.fromRGB(255, 255, 255))
	eventLine.Position = UDim2.fromScale(0, 0.6)

	-- Weekly leaderboard
	local boardPart = makePart({
		Name = "Leaderboard",
		Size = Vector3.new(1, 14, 18),
		CFrame = CFrame.new(-42, 8, -105),
		Color = Color3.fromRGB(30, 30, 45),
	})
	boardPart.Parent = folder
	local board = Instance.new("SurfaceGui")
	board.Face = Enum.NormalId.Right
	board.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	board.PixelsPerStud = 25
	board.Parent = boardPart

	return { pads = pads, board = board, sign = eventLine }
end

----------------------------------------------------------------------
-- Tower
----------------------------------------------------------------------
local function paletteFor(seed: number, accent: Color3?)
	local rng = Random.new(seed)
	local hue = rng:NextNumber()
	return {
		platform = function(section: number): Color3
			return Color3.fromHSV((hue + section * 0.045) % 1, 0.45, 0.95)
		end,
		core = accent or Color3.fromHSV((hue + 0.5) % 1, 0.25, 0.55),
		checkpoint = Color3.fromRGB(80, 225, 120),
	}
end

local function crackIcon(part: BasePart)
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back, Enum.NormalId.Left, Enum.NormalId.Right } do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 20
		gui.LightInfluence = 0
		local text = Instance.new("TextLabel")
		text.BackgroundTransparency = 1
		text.Size = UDim2.fromScale(1, 1)
		text.TextScaled = true
		text.Text = "🔨"
		text.TextTransparency = 0.15
		text.Parent = gui
		gui.Parent = part
	end
end

local function makeSpinner(folder: Folder, bar: TowerLayout.Piece, pivotPiece: TowerLayout.Piece?): BasePart
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

function World.buildTower(layout: TowerLayout.Result, accent: Color3?): Tower
	local folder = Instance.new("Folder")
	folder.Name = "Tower"
	local palette = paletteFor(layout.seed, accent)
	local checkpoints: { [number]: BasePart } = {}
	local spinners: { BasePart } = {}

	-- pivots are matched to bars by position
	local pivots: { TowerLayout.Piece } = {}
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

		if kind == "platform" or kind == "floor" then
			part = makePart({ Size = size, CFrame = cf, Color = palette.platform(piece.section) })
		elseif kind == "checkpoint" or kind == "win" then
			part = makePart({
				Size = size,
				CFrame = cf,
				Color = if kind == "win" then Color3.fromRGB(255, 205, 60) else palette.checkpoint,
				Material = Enum.Material.Neon,
			})
			local p = part :: BasePart
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
		elseif kind == "kill" then
			part = makePart({
				Size = size,
				CFrame = cf,
				Color = Color3.fromRGB(255, 90, 20),
				Material = Enum.Material.CrackedLava,
			})
		elseif kind == "breakable" then
			part = makePart({
				Size = size,
				CFrame = cf,
				Color = Color3.fromRGB(190, 120, 70),
				Material = Enum.Material.Cobblestone,
			})
			crackIcon(part :: BasePart) -- every smashable block shows a 🔨
		elseif kind == "truss" then
			part = makePart({ Size = size, CFrame = cf, Color = Color3.fromRGB(200, 200, 210), Material = Enum.Material.Metal }, "TrussPart")
		elseif kind == "pad" then
			local pad = makePart({ Size = size, CFrame = cf, Color = Color3.fromRGB(60, 240, 255), Material = Enum.Material.Neon })
			pad:SetAttribute("Boost", piece.boost or 60)
			part = pad
		elseif kind == "vanish" then
			part = makePart({
				Size = size,
				CFrame = cf,
				Color = Color3.fromRGB(255, 160, 220),
				Material = Enum.Material.Glass,
				Transparency = 0.15,
			})
		elseif kind == "core" then
			part = makePart({ Size = size, CFrame = cf, Color = palette.core, Material = Enum.Material.Brick })
		elseif kind == "spinner" then
			local best: TowerLayout.Piece? = nil
			for _, pv in pivots do
				if math.abs(pv.cx - piece.cx) < 0.1 and math.abs(pv.cz - piece.cz) < 0.1 then
					best = pv
				end
			end
			table.insert(spinners, makeSpinner(folder, piece, best))
		end

		if part then
			local p = part :: BasePart
			local kindName = ({
				platform = "Platform",
				floor = "Platform",
				checkpoint = "Checkpoint",
				win = "Win",
				kill = "Kill",
				breakable = "Breakable",
				truss = "Truss",
				pad = "JumpPad",
				vanish = "Vanish",
				core = "Core",
			})[kind]
			p.Name = kindName or kind
			p:SetAttribute("Kind", kindName or kind)
			p:SetAttribute("Section", piece.section)
			p.Parent = folder
		end
	end

	folder.Parent = Workspace
	-- network ownership can only be set once the parts are in the Workspace
	for _, bar in spinners do
		bar:SetNetworkOwner(nil)
	end
	return { folder = folder, layout = layout, checkpoints = checkpoints, winIndex = #layout.checkpoints - 1 }
end

-- Where to put a player standing on checkpoint `index` (spread out a little).
function World.checkpointCFrame(tower: Tower, index: number, slot: number): CFrame
	local cp = tower.layout.checkpoints[index + 1]
	local offsets = { Vector3.new(-2, 0, -2), Vector3.new(2, 0, 2), Vector3.new(2, 0, -2), Vector3.new(-2, 0, 2) }
	local offset = offsets[((slot - 1) % 4) + 1]
	local pos = Vector3.new(cp[1], cp[2] + 3, cp[3]) + offset
	-- face along the next side of the spiral
	local dirs = { Vector3.new(1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(-1, 0, 0), Vector3.new(0, 0, -1) }
	local look = dirs[(index % 4) + 1]
	return CFrame.lookAt(pos, pos + look)
end

return World
