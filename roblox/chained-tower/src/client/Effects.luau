--!strict
-- Client-side half of the run trails and reward wings (the server half is
-- server/TrailFx.luau and server/Cosmetics.luau). Runs for every player you
-- can see, so everyone sees the same thing:
--   * particle emitters turn up while running and down while standing
--   * each trail's own moving pieces: flames burning on the ground where you
--     stepped, lightning bolts striking the floor, falling leaves, soap
--     bubbles, flipping coins, rainbow footprints, shooting stars, pumpkins,
--     snowflakes + frost, floating lanterns, hearts, golden shockwaves...
--   * wings flap faster while running and hard while in the air, and the
--     feathered ones shed a feather now and then.
-- Pieces are local-only, never collide, and are capped so a crowded lobby
-- stays smooth.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local Effects = {}

local VIEW_DISTANCE = 160
local MAX_PIECES = 260
local SPARK = "rbxasset://textures/particles/sparkles_main.dds"
local FIRE = "rbxasset://textures/particles/fire_main.dds"

local folder = Instance.new("Folder")
folder.Name = "CT_LocalFx"
folder.Parent = Workspace

local pieces = 0
local rng = Random.new()

local function rand(a: number, b: number): number
	return rng:NextNumber(a, b)
end

local function pick<T>(list: { T }): T
	return list[rng:NextInteger(1, #list)]
end

-- A throwaway part that lives for `life` seconds.
local function piece(life: number, props: { [string]: any }): Part?
	if pieces >= MAX_PIECES then
		return nil
	end
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.Neon
	-- shape first, then size, so a Ball/Cylinder keeps the size we asked for
	if props.Shape then
		p.Shape = props.Shape
	end
	if props.Size then
		p.Size = props.Size
	end
	for k, v in props do
		if k ~= "Shape" and k ~= "Size" then
			(p :: any)[k] = v
		end
	end
	p.Parent = folder
	pieces += 1
	task.delay(life, function()
		p:Destroy()
		pieces -= 1
	end)
	return p
end

local function tween(obj: Instance, seconds: number, goal: { [string]: any }, style: Enum.EasingStyle?, dir: Enum.EasingDirection?)
	local t = TweenService:Create(obj, TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), goal)
	t:Play()
end

-- Runs `steps` one after another: each is { seconds, goal, style? }.
local function chain(obj: Instance, steps: { { any } })
	task.spawn(function()
		for _, s in steps do
			if not obj.Parent then
				return
			end
			tween(obj, s[1], s[2], s[3], s[4])
			task.wait(s[1])
		end
	end)
end

-- A CFrame lying flat on a surface: a Cylinder's axis (X) points along `normal`.
local function flat(pos: Vector3, normal: Vector3): CFrame
	local side = if math.abs(normal.Y) > 0.9 then Vector3.xAxis else Vector3.yAxis
	local y = normal:Cross(side).Unit
	return CFrame.fromMatrix(pos, normal, y)
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
local function refreshFilter()
	local list: { Instance } = { folder }
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	rayParams.FilterDescendantsInstances = list
end

local function ground(from: Vector3, depth: number?): (Vector3?, Vector3)
	local hit = Workspace:Raycast(from, Vector3.new(0, -(depth or 4.5), 0), rayParams)
	if hit then
		return hit.Position, hit.Normal
	end
	return nil, Vector3.yAxis
end

-- A flat glowing disc on the floor that grows/fades.
local function disc(pos: Vector3, normal: Vector3, size: number, color: Color3, life: number, props: { [string]: any }?)
	local p = piece(life, {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.05, size, size),
		CFrame = flat(pos + normal * 0.04, normal),
		Color = color,
		Transparency = 0.25,
	})
	if p then
		local goal: { [string]: any } = { Transparency = 1 }
		for k, v in props or {} do
			goal[k] = v
		end
		tween(p, life, goal)
	end
	return p
end

-- A floating emoji (hearts, snowflakes, pumpkins, ghosts).
local function emoji(text: string, pos: Vector3, size: number, life: number, path: { Vector3 }, color: Color3?, spin: number?)
	local p = piece(life, { Size = Vector3.new(0.2, 0.2, 0.2), Transparency = 1, CFrame = CFrame.new(pos) })
	if not p then
		return
	end
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromScale(size, size)
	bb.LightInfluence = 0
	bb.MaxDistance = VIEW_DISTANCE
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.Text = text
	label.TextColor3 = color or Color3.new(1, 1, 1)
	label.Parent = bb
	bb.Parent = p
	local legs = #path
	local steps = {}
	for _, offset in path do
		table.insert(steps, { life / legs, { CFrame = CFrame.new(pos + offset) }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut })
	end
	chain(p, steps)
	tween(label, life, { TextTransparency = 1, Rotation = spin or 0 }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
end

----------------------------------------------------------------------
-- Per-character bookkeeping
----------------------------------------------------------------------
type State = {
	fx: string?,
	root: BasePart?,
	emitters: { ParticleEmitter },
	glow: PointLight?,
	orbits: { Attachment },
	moving: boolean?,
	last: Vector3?,
	stride: number,
	timers: { [string]: number },
	count: number,
	phase: number,
	amp: number,
}
local states: { [Model]: State } = {}

local function scan(state: State, root: BasePart)
	state.root = root
	state.emitters = {}
	state.orbits = {}
	state.glow = nil
	state.moving = nil
	for _, d in root:GetDescendants() do
		if d:IsA("ParticleEmitter") and d.Name == "CT_Fx" then
			table.insert(state.emitters, d)
		elseif d:IsA("Attachment") and (d.Name == "CT_orbitA" or d.Name == "CT_orbitB") then
			table.insert(state.orbits, d)
		elseif d:IsA("PointLight") and d.Name == "CT_Glow" then
			state.glow = d
		end
	end
end

-- true once every `interval` seconds
local function every(state: State, key: string, interval: number, dt: number): boolean
	local t = (state.timers[key] or rand(0, interval)) - dt
	if t <= 0 then
		state.timers[key] = interval * rand(0.75, 1.25)
		return true
	end
	state.timers[key] = t
	return false
end

----------------------------------------------------------------------
-- The trails
----------------------------------------------------------------------
type Ctx = { state: State, root: BasePart, pos: Vector3, vel: Vector3, moving: boolean, air: boolean, dt: number, footstep: boolean }

local GOLD = Color3.fromRGB(255, 200, 50)
local RAINBOW = {
	Color3.fromRGB(255, 70, 70),
	Color3.fromRGB(255, 160, 50),
	Color3.fromRGB(255, 230, 60),
	Color3.fromRGB(80, 220, 100),
	Color3.fromRGB(70, 160, 255),
	Color3.fromRGB(180, 90, 255),
}

-- Burning patch left on the floor: a glowing scorch mark with real flames
-- that keep burning for a moment after you've gone.
local function flameStep(c: Ctx)
	local at, normal = ground(c.pos)
	if not at then
		return
	end
	local mark = disc(at, normal, rand(1.3, 1.7), Color3.fromRGB(255, 130, 30), 2.8, {
		Color = Color3.fromRGB(50, 20, 10),
		Size = Vector3.new(0.05, 0.7, 0.7),
	})
	if not mark then
		return
	end
	local flame = Instance.new("ParticleEmitter")
	flame.Texture = FIRE
	flame.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 245, 170)),
		ColorSequenceKeypoint.new(0.4, Color3.fromRGB(255, 140, 30)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(150, 30, 10)),
	})
	flame.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.6),
		NumberSequenceKeypoint.new(0.35, 1.1),
		NumberSequenceKeypoint.new(1, 0),
	})
	flame.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	flame.Lifetime = NumberRange.new(0.4, 0.8)
	flame.Speed = NumberRange.new(0.3, 1)
	flame.SpreadAngle = Vector2.new(180, 180)
	flame.Acceleration = Vector3.new(0, 7, 0)
	flame.Rotation = NumberRange.new(0, 360)
	flame.RotSpeed = NumberRange.new(-60, 60)
	flame.LightEmission = 1
	flame.LightInfluence = 0
	flame.Rate = 22
	flame.Parent = mark
	task.delay(1.5, function()
		flame.Enabled = false
	end)
end

-- One jagged bolt from a to b (plus a glow around the main bolt).
local function bolt(a: Vector3, b: Vector3, segments: number, width: number, branch: boolean)
	local points = { a }
	local dir = b - a
	local length = dir.Magnitude
	if length < 0.5 then
		return
	end
	local side1 = dir:Cross(Vector3.yAxis)
	if side1.Magnitude < 0.01 then
		side1 = Vector3.xAxis
	end
	side1 = side1.Unit
	local side2 = dir:Cross(side1).Unit
	for i = 1, segments - 1 do
		local jitter = length / segments * 0.6
		table.insert(points, a + dir * (i / segments) + side1 * rand(-jitter, jitter) + side2 * rand(-jitter, jitter))
	end
	table.insert(points, b)
	local parts = {}
	for i = 1, #points - 1 do
		local p0, p1 = points[i], points[i + 1]
		local len = (p1 - p0).Magnitude
		local cf = CFrame.lookAt((p0 + p1) / 2, p1)
		local core = piece(0.22, { Size = Vector3.new(width, width, len + width), CFrame = cf, Color = Color3.fromRGB(235, 250, 255) })
		if core then
			table.insert(parts, core)
		end
		if branch then
			local aura = piece(0.22, {
				Size = Vector3.new(width * 3.2, width * 3.2, len + width),
				CFrame = cf,
				Color = Color3.fromRGB(90, 160, 255),
				Transparency = 0.65,
			})
			if aura then
				table.insert(parts, aura)
			end
		end
	end
	-- flicker: on, off, on, gone
	task.delay(0.06, function()
		for _, p in parts do
			p.LocalTransparencyModifier = 1
		end
	end)
	task.delay(0.1, function()
		for _, p in parts do
			p.LocalTransparencyModifier = 0
		end
	end)
	task.delay(0.16, function()
		for _, p in parts do
			p.LocalTransparencyModifier = 1
		end
	end)
	if branch and #points >= 3 then
		local from = points[2]
		local out = (b - a).Unit * length * 0.4 + side1 * rand(-1.5, 1.5) + side2 * rand(-1.5, 1.5)
		bolt(from, from + out, 3, width * 0.6, false)
	end
end

local function lightningStrike(c: Ctx)
	local start = c.pos + Vector3.new(rand(-1.4, 1.4), rand(0, 1.6), rand(-1.4, 1.4))
	local angle = rand(0, math.pi * 2)
	local r = rand(1.2, 2.8)
	local target, normal = ground(c.pos + Vector3.new(math.cos(angle) * r, 0.5, math.sin(angle) * r), 6)
	local finish = target or (c.pos + Vector3.new(math.cos(angle) * r, -3, math.sin(angle) * r))
	bolt(start, finish, 5, 0.12, true)
	if target then
		disc(target, normal, 1.2, Color3.fromRGB(150, 220, 255), 0.35, { Size = Vector3.new(0.05, 2.2, 2.2) })
	end
	local glow = c.state.glow
	if glow then
		local base = glow:GetAttribute("Base")
		glow.Brightness = 5
		tween(glow, 0.25, { Brightness = if type(base) == "number" then base else 1.5 })
	end
end

local function leaf(c: Ctx)
	local start = c.pos + Vector3.new(rand(-1.3, 1.3), rand(-0.5, 1.6), rand(-1.3, 1.3))
	local color = pick({
		Color3.fromRGB(110, 210, 80),
		Color3.fromRGB(60, 160, 60),
		Color3.fromRGB(170, 220, 70),
		Color3.fromRGB(230, 190, 60),
	})
	local p = piece(1.9, { Size = Vector3.new(0.55, 0.05, 0.32), Color = color, Material = Enum.Material.SmoothPlastic, CFrame = CFrame.new(start) * CFrame.Angles(rand(0, 6), rand(0, 6), rand(0, 6)) })
	if not p then
		return
	end
	local sway = rand(0.8, 1.4) * (if rng:NextNumber() > 0.5 then 1 else -1)
	local floor = ground(start, 8)
	local fall = if floor then math.max(1, start.Y - floor.Y - 0.1) else 3.5
	chain(p, {
		{ 0.6, { CFrame = CFrame.new(start + Vector3.new(sway, -fall * 0.35, rand(-0.5, 0.5))) * CFrame.Angles(0.6, rand(0, 6), 0.4) }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut },
		{ 0.6, { CFrame = CFrame.new(start + Vector3.new(-sway * 0.6, -fall * 0.7, rand(-0.5, 0.5))) * CFrame.Angles(-0.5, rand(0, 6), -0.4) }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut },
		{ 0.6, { CFrame = CFrame.new(start + Vector3.new(sway * 0.3, -fall, rand(-0.5, 0.5))) * CFrame.Angles(0, rand(0, 6), 0), Transparency = 1 }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut },
	})
end

local function bubble(c: Ctx)
	local size = rand(0.4, 0.85)
	local start = c.pos + Vector3.new(rand(-1, 1), rand(-1.5, 0.8), rand(-1, 1))
	local life = rand(1.2, 1.8)
	local p = piece(life + 0.7, {
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(size, size, size),
		CFrame = CFrame.new(start),
		Color = Color3.fromRGB(150, 230, 255):Lerp(Color3.fromRGB(255, 170, 235), rand(0, 1)),
		Material = Enum.Material.ForceField,
	})
	if not p then
		return
	end
	local top = start + Vector3.new(rand(-0.8, 0.8), rand(2.5, 4), rand(-0.8, 0.8))
	tween(p, life, { CFrame = CFrame.new(top), Size = Vector3.one * size * 1.3 }, Enum.EasingStyle.Sine)
	task.delay(life, function()
		if not p.Parent then
			return
		end
		-- pop!
		local pop = Instance.new("ParticleEmitter")
		pop.Texture = SPARK
		pop.Color = ColorSequence.new(Color3.fromRGB(220, 250, 255), Color3.fromRGB(255, 200, 240))
		pop.Size = NumberSequence.new(0.25, 0)
		pop.Lifetime = NumberRange.new(0.2, 0.4)
		pop.Speed = NumberRange.new(3, 5)
		pop.SpreadAngle = Vector2.new(180, 180)
		pop.LightEmission = 1
		pop.Rate = 0
		pop.Parent = p
		pop:Emit(8)
		tween(p, 0.1, { Size = Vector3.one * size * 1.8, Transparency = 1 })
	end)
end

local function coin(c: Ctx)
	local at = ground(c.pos)
	if not at then
		return
	end
	local start = at + Vector3.new(rand(-0.4, 0.4), 0.4, rand(-0.4, 0.4))
	local p = piece(1.4, {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.12, 0.75, 0.75),
		Color = GOLD,
		Material = Enum.Material.Metal,
		Reflectance = 0.45,
		CFrame = CFrame.new(start) * CFrame.Angles(0, rand(0, 6), 0),
	})
	if not p then
		return
	end
	local side = Vector3.new(rand(-1, 1), 0, rand(-1, 1))
	chain(p, {
		{ 0.35, { CFrame = CFrame.new(start + side * 0.6 + Vector3.new(0, 1.8, 0)) * CFrame.Angles(0, 3, 1.5) }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out },
		{ 0.4, { CFrame = CFrame.new(start + side * 1.1 + Vector3.new(0, -0.3, 0)) * CFrame.Angles(0, 6, 0) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In },
		{ 0.6, { Transparency = 1 } },
	})
end

local function rainbowStep(c: Ctx)
	local at, normal = ground(c.pos)
	if at then
		c.state.count += 1
		disc(at, normal, 1.3, RAINBOW[(c.state.count - 1) % #RAINBOW + 1], 1.8, { Size = Vector3.new(0.05, 1.8, 1.8) })
	end
end

local function shootingStar(c: Ctx)
	local start = c.pos + Vector3.new(rand(-7, 7), rand(6, 9), rand(-7, 7))
	local finish = c.pos + Vector3.new(rand(-3, 3), rand(-2, 0), rand(-3, 3))
	local p = piece(1.2, { Shape = Enum.PartType.Ball, Size = Vector3.new(0.35, 0.35, 0.35), Color = Color3.new(1, 1, 1), CFrame = CFrame.new(start) })
	if not p then
		return
	end
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 0.15, 0)
	a0.Parent = p
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -0.15, 0)
	a1.Parent = p
	local tail = Instance.new("Trail")
	tail.Attachment0 = a0
	tail.Attachment1 = a1
	tail.Color = ColorSequence.new(Color3.fromRGB(255, 220, 255), Color3.fromRGB(110, 80, 255))
	tail.Lifetime = 0.35
	tail.LightEmission = 1
	tail.FaceCamera = true
	tail.WidthScale = NumberSequence.new(1.6, 0)
	tail.Transparency = NumberSequence.new(0, 1)
	tail.Parent = p
	chain(p, {
		{ 0.55, { CFrame = CFrame.new(finish) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In },
		{ 0.3, { Transparency = 1, Size = Vector3.one * 1.2 } },
	})
end

local function pumpkin(c: Ctx)
	if rng:NextNumber() < 0.3 then
		local start = c.pos + Vector3.new(rand(-1.5, 1.5), rand(-1, 0.5), rand(-1.5, 1.5))
		emoji("👻", start, rand(1, 1.4), 1.8, {
			Vector3.new(rand(-0.6, 0.6), 1.5, rand(-0.6, 0.6)),
			Vector3.new(rand(-1, 1), 3.5, rand(-1, 1)),
		})
	else
		local at = ground(c.pos)
		local start = (at or c.pos - Vector3.new(0, 2.5, 0)) + Vector3.new(0, 0.5, 0)
		local out = Vector3.new(rand(-1.5, 1.5), 0, rand(-1.5, 1.5))
		emoji("🎃", start, rand(0.9, 1.2), 1.4, {
			out * 0.5 + Vector3.new(0, 1.6, 0),
			out + Vector3.new(0, 0.1, 0),
			out * 1.2 + Vector3.new(0, 0.6, 0),
			out * 1.4 + Vector3.new(0, 0.1, 0),
		}, nil, rand(-40, 40))
	end
end

local function snowflake(c: Ctx)
	local start = c.pos + Vector3.new(rand(-2.5, 2.5), rand(2.5, 4), rand(-2.5, 2.5))
	emoji("❄", start, rand(0.5, 0.9), 2.2, {
		Vector3.new(rand(-0.6, 0.6), -2.2, rand(-0.6, 0.6)),
		Vector3.new(rand(-1, 1), -5.5, rand(-1, 1)),
	}, Color3.fromRGB(220, 240, 255), rand(-180, 180))
end

local function frostStep(c: Ctx)
	local at, normal = ground(c.pos)
	if at then
		local p = disc(at, normal, rand(1.1, 1.5), Color3.fromRGB(215, 240, 255), 3)
		if p then
			p.Material = Enum.Material.Ice
			p.Transparency = 0.15
		end
	end
end

local function lantern(c: Ctx)
	local start = c.pos + Vector3.new(rand(-1.5, 1.5), rand(-0.5, 1), rand(-1.5, 1.5))
	local life = 3.4
	local body = piece(life, { Size = Vector3.new(0.55, 0.65, 0.55), Color = Color3.fromRGB(225, 40, 30), CFrame = CFrame.new(start) })
	local top = piece(life, { Size = Vector3.new(0.62, 0.1, 0.62), Color = Color3.fromRGB(255, 200, 60), Material = Enum.Material.Metal, CFrame = CFrame.new(start + Vector3.new(0, 0.37, 0)) })
	local bottom = piece(life, { Size = Vector3.new(0.62, 0.1, 0.62), Color = Color3.fromRGB(255, 200, 60), Material = Enum.Material.Metal, CFrame = CFrame.new(start - Vector3.new(0, 0.37, 0)) })
	if not (body and top and bottom) then
		return
	end
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 120, 60)
	light.Range = 6
	light.Brightness = 1
	light.Parent = body
	local sway = rand(-1.2, 1.2)
	for _, p in { body, top, bottom } do
		local home = p.CFrame
		chain(p, {
			{ life * 0.5, { CFrame = home + Vector3.new(sway, 2.8, rand(-0.5, 0.5)) }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut },
			{ life * 0.5, { CFrame = home + Vector3.new(-sway * 0.5, 6, 0), Transparency = 1 }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut },
		})
	end
end

local function heart(c: Ctx)
	local start = c.pos + Vector3.new(rand(-1.5, 1.5), rand(-1, 1), rand(-1.5, 1.5))
	emoji(pick({ "💖", "💕", "💗", "❤️" }), start, rand(0.7, 1.3), 1.4, {
		Vector3.new(rand(-0.5, 0.5), 1.4, rand(-0.5, 0.5)),
		Vector3.new(rand(-0.8, 0.8), 3, rand(-0.8, 0.8)),
	}, nil, rand(-25, 25))
end

local function shockwave(c: Ctx)
	local at, normal = ground(c.pos)
	if at then
		disc(at, normal, 0.6, Color3.fromRGB(255, 215, 90), 0.6, { Size = Vector3.new(0.05, 6, 6) })
		disc(at + normal * 0.02, normal, 0.4, Color3.fromRGB(255, 255, 230), 0.4, { Size = Vector3.new(0.05, 3.5, 3.5) })
	end
end

local function shard(c: Ctx)
	local start = c.pos + Vector3.new(rand(-0.6, 0.6), rand(-1, 0.8), rand(-0.6, 0.6))
	local p = piece(1, {
		Size = Vector3.new(0.4, 0.05, 0.28),
		Color = Color3.fromRGB(225, 235, 250),
		Material = Enum.Material.Foil,
		Reflectance = 0.7,
		CFrame = CFrame.new(start) * CFrame.Angles(rand(0, 6), rand(0, 6), rand(0, 6)),
	})
	if not p then
		return
	end
	local out = Vector3.new(rand(-2.5, 2.5), 0, rand(-2.5, 2.5))
	chain(p, {
		{ 0.3, { CFrame = CFrame.new(start + out * 0.6 + Vector3.new(0, 1, 0)) * CFrame.Angles(rand(0, 6), rand(0, 6), 0) } },
		{ 0.6, { CFrame = CFrame.new(start + out + Vector3.new(0, -1.5, 0)) * CFrame.Angles(rand(0, 6), 0, rand(0, 6)), Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In },
	})
end

local function copperStep(c: Ctx)
	local at, normal = ground(c.pos)
	if at then
		disc(at, normal, 0.8, Color3.fromRGB(230, 140, 70), 0.5, { Size = Vector3.new(0.05, 2.6, 2.6) })
	end
end

-- For each trail: what happens on each footstep (every `stride` studs walked
-- on the floor) and what happens every `every` seconds (`idle` = slower rate
-- while standing still, nil = only while running).
type Handler = { stride: number?, step: ((Ctx) -> ())?, every: number?, idle: number?, tick: ((Ctx) -> ())? }
local HANDLERS: { [string]: Handler } = {
	Basic = {},
	Leaf = { every = 0.12, idle = 0.9, tick = leaf },
	Bubble = { every = 0.15, idle = 0.6, tick = bubble },
	Gold = { stride = 2.6, step = coin },
	Rainbow = { stride = 2.2, step = rainbowStep },
	Fire = { stride = 1.8, step = flameStep },
	Lightning = { every = 0.16, idle = 0.9, tick = lightningStrike },
	Galaxy = { every = 1.3, idle = 3, tick = shootingStar },
	Pumpkin = { every = 0.45, idle = 2, tick = pumpkin },
	Snowflake = { every = 0.22, idle = 0.6, tick = snowflake, stride = 2.4, step = frostStep },
	Lantern = { every = 0.6, idle = 1.6, tick = lantern },
	Heart = { every = 0.22, idle = 0.9, tick = heart },
	Champion = { stride = 3.2, step = shockwave },
	Silver = { every = 0.16, tick = shard },
	Bronze = { stride = 2.2, step = copperStep },
}
Effects.Handlers = HANDLERS

----------------------------------------------------------------------
-- Wings: flapping + loose feathers
----------------------------------------------------------------------
local function looseFeather(wings: Model, look: string)
	local info = Config.Wings[look]
	local roots = {}
	for _, child in wings:GetChildren() do
		if child:IsA("BasePart") and (child.Name == "WingL" or child.Name == "WingR") then
			table.insert(roots, child)
		end
	end
	if #roots == 0 or not info then
		return
	end
	local from = pick(roots).Position + Vector3.new(rand(-1, 1), rand(-0.5, 0.5), rand(-0.5, 0.5))
	local p = piece(2.4, {
		Size = Vector3.new(0.8, 0.22, 0.05),
		Color = info.colors[1]:Lerp(info.colors[2], rand(0, 1)),
		Material = if look == "Angel" then Enum.Material.SmoothPlastic else Enum.Material.Metal,
		Reflectance = if look == "Angel" then 0 else 0.3,
		CFrame = CFrame.new(from) * CFrame.Angles(rand(0, 6), rand(0, 6), rand(0, 6)),
	})
	if not p then
		return
	end
	local sway = rand(0.7, 1.3)
	chain(p, {
		{ 0.8, { CFrame = CFrame.new(from + Vector3.new(sway, -1.2, 0)) * CFrame.Angles(0.5, 1, 0.3) }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut },
		{ 0.8, { CFrame = CFrame.new(from + Vector3.new(-sway, -2.4, 0.3)) * CFrame.Angles(-0.4, 2, -0.3) }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut },
		{ 0.8, { CFrame = CFrame.new(from + Vector3.new(0, -3.4, 0.5)) * CFrame.Angles(0, 3, 0), Transparency = 1 }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut },
	})
end

local function updateWings(character: Model, state: State, moving: boolean, air: boolean, dt: number)
	local wings = character:FindFirstChild("CT_Wings")
	if not wings or not wings:IsA("Model") then
		return
	end
	local speed = if air then 11 elseif moving then 5.5 else 2.4
	local target = if air then 0.6 elseif moving then 0.36 else 0.2
	state.amp += (target - state.amp) * math.min(1, dt * 4)
	state.phase += dt * speed
	local swing = math.sin(state.phase) * state.amp
	for _, weld in wings:GetDescendants() do
		if weld:IsA("Weld") and weld.Name == "FlapWeld" then
			local base = weld:GetAttribute("BaseC0")
			local side = weld:GetAttribute("Side")
			if typeof(base) == "CFrame" and type(side) == "number" then
				weld.C0 = base * CFrame.Angles(swing * 0.15, side * swing, side * swing * 0.25)
			end
		end
	end
	local look = wings:GetAttribute("Look")
	if type(look) == "string" and look ~= "Fairy" then
		if every(state, "feather", if air or moving then 0.9 else 2.8, dt) then
			looseFeather(wings, look)
		end
	end
end

----------------------------------------------------------------------
-- Main loop
----------------------------------------------------------------------
local function update(dt: number)
	local camera = Workspace.CurrentCamera
	local eye = if camera then camera.CFrame.Position else Vector3.zero
	local alive: { [Model]: boolean } = {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not (character and root and root:IsA("BasePart")) then
			continue
		end
		alive[character] = true
		local pos = root.Position
		if (pos - eye).Magnitude > VIEW_DISTANCE then
			continue
		end
		local state = states[character]
		local fx = character:GetAttribute("TrailFx")
		if not state then
			state = { emitters = {}, orbits = {}, stride = 0, timers = {}, count = 0, phase = 0, amp = 0.2 }
			states[character] = state
		end
		-- the server rebuilds the trail when you equip another one or respawn
		local s = state :: State
		if s.fx ~= fx or s.root ~= root or (#s.emitters > 0 and not s.emitters[1].Parent) then
			s.fx = if type(fx) == "string" then fx else nil
			scan(s, root)
		end

		local vel = root.AssemblyLinearVelocity
		local flatSpeed = Vector3.new(vel.X, 0, vel.Z).Magnitude
		local moving = flatSpeed > 3
		local air = math.abs(vel.Y) > 6

		if s.moving ~= moving then
			s.moving = moving
			for _, e in s.emitters do
				local rate = e:GetAttribute(if moving then "MoveRate" else "IdleRate")
				if type(rate) == "number" then
					e.Rate = rate
				end
			end
		end

		-- star streams circling your body
		if #s.orbits > 0 then
			local t = os.clock() * (if moving then 3.2 else 1.8)
			for i, att in s.orbits do
				local a = t + (i - 1) * math.pi
				att.Position = Vector3.new(math.cos(a) * 2.2, math.sin(t * 0.7 + i) * 1.2 - 0.4, math.sin(a) * 2.2)
			end
		end

		-- flickering firelight
		if s.fx == "Fire" and s.glow then
			s.glow.Brightness = 1.6 + math.noise(os.clock() * 6, 0, 0) * 1.4
		end

		local handler = s.fx and HANDLERS[s.fx]
		if handler then
			local last = s.last or pos
			local onFloor = not air
			if onFloor then
				s.stride += Vector3.new(pos.X - last.X, 0, pos.Z - last.Z).Magnitude
			end
			local ctx: Ctx = { state = s, root = root, pos = pos, vel = vel, moving = moving, air = air, dt = dt, footstep = false }
			if handler.step and handler.stride and s.stride >= handler.stride then
				s.stride = 0
				handler.step(ctx)
			end
			if handler.tick and handler.every then
				local interval = if moving then handler.every else handler.idle
				if interval and every(s, "tick", interval, dt) then
					handler.tick(ctx)
				end
			end
		end
		s.last = pos
		updateWings(character, s, moving, air, dt)
	end
	for character in states do
		if not alive[character] then
			states[character] = nil
		end
	end
end

function Effects.start()
	refreshFilter()
	task.spawn(function()
		while true do
			task.wait(1)
			refreshFilter()
		end
	end)
	RunService.RenderStepped:Connect(update)
end

return Effects
