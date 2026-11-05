--!strict
-- What each run trail looks like. The server builds the parts that everybody
-- sees the same way (the ribbon, particle emitters, glow). The client module
-- Effects.luau adds the moving pieces (flames left on the ground, lightning
-- bolts, falling leaves, bubbles...) for the trail named in the character's
-- "TrailFx" attribute.
--
-- Emitters named "CT_Fx" carry a "MoveRate" and "IdleRate" attribute: the
-- client turns them up while you run and down while you stand still.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local TrailFx = {}

local TEX = {
	spark = "rbxasset://textures/particles/sparkles_main.dds",
	fire = "rbxasset://textures/particles/fire_main.dds",
	smoke = "rbxasset://textures/particles/smoke_main.dds",
}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local function colors(list: { Color3 }): ColorSequence
	if #list == 1 then
		return ColorSequence.new(list[1])
	end
	local keys = {}
	for i, c in list do
		table.insert(keys, ColorSequenceKeypoint.new((i - 1) / (#list - 1), c))
	end
	return ColorSequence.new(keys)
end

local function numbers(list: { number }): NumberSequence
	if #list == 1 then
		return NumberSequence.new(list[1])
	end
	local keys = {}
	for i, v in list do
		table.insert(keys, NumberSequenceKeypoint.new((i - 1) / (#list - 1), v))
	end
	return NumberSequence.new(keys)
end

-- Where emitters sit, relative to the HumanoidRootPart (R15 and R6 both stand
-- about 3 studs above the floor).
local SPOTS = {
	feet = Vector3.new(0, -2.8, 0.2),
	body = Vector3.new(0, 0, 0),
	head = Vector3.new(0, 2.6, 0),
	sky = Vector3.new(0, 4, 0), -- above your head, for things that fall
	orbitA = Vector3.new(2.2, 0.2, 0), -- moved in a circle by the client
	orbitB = Vector3.new(-2.2, -1.2, 0),
}

export type Emitter = {
	at: string,
	tex: string,
	colors: { Color3 },
	size: { number },
	transparency: { number }?,
	life: { number },
	speed: { number },
	rate: number,
	idle: number?,
	spread: number?,
	accel: Vector3?,
	drag: number?,
	rotation: { number }?,
	spin: { number }?,
	light: number?,
	locked: boolean?,
	up: boolean?, -- emit upwards (Top) instead of the default
	inherit: number?, -- VelocityInheritance
	z: number?,
}

export type Look = {
	ribbon: { width: number, life: number, light: number, from: number, to: number, alpha: number },
	emitters: { Emitter },
	glow: { color: Color3, brightness: number, range: number }?,
}

-- ribbon.from / ribbon.to: the ribbon's top and bottom height on your body.
local Looks: { [string]: Look } = {
	-- A plain soft streak. Free, so deliberately simple.
	Basic = {
		ribbon = { width = 0.8, life = 0.4, light = 0.4, from = 0.6, to = -1.0, alpha = 0.35 },
		emitters = {},
	},

	-- Green ribbon + tiny pollen; the client drops spinning leaves.
	Leaf = {
		ribbon = { width = 0.7, life = 0.45, light = 0.3, from = 0.4, to = -1.2, alpha = 0.3 },
		emitters = {
			{ at = "body", tex = TEX.spark, colors = { rgb(200, 255, 140), rgb(120, 220, 90) }, size = { 0.15, 0.25, 0 },
				life = { 0.8, 1.4 }, speed = { 0.5, 1.5 }, rate = 8, spread = 180, accel = Vector3.new(0, -1, 0), light = 0.5 },
		},
	},

	-- Pastel ribbon; the client blows real soap bubbles that float up and pop.
	Bubble = {
		ribbon = { width = 0.6, life = 0.4, light = 0.6, from = 0.4, to = -1.0, alpha = 0.45 },
		emitters = {
			{ at = "body", tex = TEX.spark, colors = { rgb(200, 245, 255), rgb(255, 190, 240) }, size = { 0.1, 0.2, 0 },
				life = { 0.6, 1 }, speed = { 0.5, 1 }, rate = 6, spread = 180, light = 0.8 },
		},
	},

	-- Falling gold dust; the client flips coins out of your footsteps.
	Gold = {
		ribbon = { width = 1.1, life = 0.5, light = 0.8, from = 0.6, to = -1.2, alpha = 0.15 },
		emitters = {
			{ at = "body", tex = TEX.spark, colors = { rgb(255, 245, 170), rgb(255, 200, 50), rgb(255, 150, 20) },
				size = { 0.35, 0.45, 0 }, life = { 0.7, 1.2 }, speed = { 1, 2.5 }, rate = 28, idle = 4, spread = 180,
				accel = Vector3.new(0, -7, 0), spin = { -200, 200 }, light = 1 },
		},
		glow = { color = rgb(255, 205, 90), brightness = 1, range = 8 },
	},

	-- Wide rainbow ribbon + coloured twinkles; the client paints rainbow footprints.
	Rainbow = {
		ribbon = { width = 1.6, life = 0.8, light = 0.7, from = 0.8, to = -1.4, alpha = 0.1 },
		emitters = {
			{ at = "body", tex = TEX.spark, colors = { rgb(255, 70, 70), rgb(255, 200, 60), rgb(80, 220, 100), rgb(70, 160, 255), rgb(180, 90, 255) },
				size = { 0, 0.4, 0 }, life = { 0.6, 1 }, speed = { 1, 2 }, rate = 16, spread = 180, light = 1 },
		},
	},

	-- Flames burning on the floor where you step (they stay behind because
	-- they are not locked to you), rising embers, a little smoke and a warm glow.
	Fire = {
		ribbon = { width = 1.4, life = 0.35, light = 1, from = -1.4, to = -2.9, alpha = 0.2 },
		emitters = {
			{ at = "feet", tex = TEX.fire, colors = { rgb(255, 250, 180), rgb(255, 170, 40), rgb(230, 60, 10), rgb(90, 20, 10) },
				size = { 1.1, 1.8, 0.4 }, transparency = { 0.15, 0.3, 1 }, life = { 0.8, 1.3 }, speed = { 0.5, 2 },
				rate = 55, idle = 6, spread = 25, up = true, accel = Vector3.new(0, 4, 0), rotation = { 0, 360 }, spin = { -40, 40 },
				light = 1, z = 0.5 },
			{ at = "feet", tex = TEX.spark, colors = { rgb(255, 230, 120), rgb(255, 110, 20) }, size = { 0.25, 0 },
				life = { 0.7, 1.4 }, speed = { 3, 6 }, rate = 18, idle = 3, spread = 35, up = true, accel = Vector3.new(0, 2, 0),
				drag = 1, light = 1 },
			{ at = "body", tex = TEX.smoke, colors = { rgb(70, 60, 55), rgb(30, 30, 30) }, size = { 1, 3 },
				transparency = { 0.75, 1 }, life = { 1.4, 2 }, speed = { 1, 2 }, rate = 4, spread = 20, up = true,
				rotation = { 0, 360 }, spin = { -20, 20 }, light = 0 },
		},
		glow = { color = rgb(255, 140, 40), brightness = 2, range = 12 },
	},

	-- Thin, fast, bright streak + electric sparks; the client draws the bolts.
	Lightning = {
		ribbon = { width = 0.45, life = 0.22, light = 1, from = 0.4, to = -1.6, alpha = 0 },
		emitters = {
			{ at = "feet", tex = TEX.spark, colors = { rgb(255, 255, 255), rgb(120, 210, 255), rgb(60, 90, 255) },
				size = { 0.4, 0 }, life = { 0.12, 0.3 }, speed = { 8, 14 }, rate = 30, idle = 4, spread = 180, drag = 4, light = 1 },
			{ at = "body", tex = TEX.spark, colors = { rgb(200, 240, 255), rgb(90, 160, 255) }, size = { 0.2, 0 },
				life = { 0.1, 0.2 }, speed = { 2, 5 }, rate = 14, idle = 6, spread = 180, light = 1, locked = true },
		},
		glow = { color = rgb(130, 200, 255), brightness = 1.5, range = 10 },
	},

	-- Twinkling stars that stay where you ran, a purple nebula and two star
	-- streams circling your body; the client adds shooting stars.
	Galaxy = {
		ribbon = { width = 1.8, life = 0.9, light = 0.9, from = 0.8, to = -1.4, alpha = 0.25 },
		emitters = {
			{ at = "body", tex = TEX.spark, colors = { rgb(255, 255, 255), rgb(255, 150, 255), rgb(130, 200, 255) },
				size = { 0, 0.4, 0 }, life = { 1.5, 2.5 }, speed = { 0.2, 0.8 }, rate = 26, idle = 8, spread = 180, light = 1 },
			{ at = "body", tex = TEX.smoke, colors = { rgb(170, 60, 255), rgb(60, 80, 255), rgb(255, 80, 200) },
				size = { 1.5, 3.5 }, transparency = { 0.8, 1 }, life = { 1.5, 2.2 }, speed = { 0.2, 0.6 }, rate = 7, idle = 2,
				spread = 180, rotation = { 0, 360 }, spin = { -30, 30 }, light = 1 },
			{ at = "orbitA", tex = TEX.spark, colors = { rgb(255, 200, 255), rgb(160, 120, 255) }, size = { 0.35, 0 },
				life = { 0.8, 1.2 }, speed = { 0, 0.2 }, rate = 22, idle = 12, light = 1 },
			{ at = "orbitB", tex = TEX.spark, colors = { rgb(150, 230, 255), rgb(90, 120, 255) }, size = { 0.35, 0 },
				life = { 0.8, 1.2 }, speed = { 0, 0.2 }, rate = 22, idle = 12, light = 1 },
		},
		glow = { color = rgb(170, 110, 255), brightness = 1, range = 10 },
	},

	-- Halloween: purple-green ghostly mist; the client bounces pumpkins and ghosts.
	Pumpkin = {
		ribbon = { width = 1, life = 0.5, light = 0.5, from = 0.4, to = -1.4, alpha = 0.2 },
		emitters = {
			{ at = "feet", tex = TEX.smoke, colors = { rgb(140, 60, 200), rgb(80, 200, 90) }, size = { 1, 2.5 },
				transparency = { 0.6, 1 }, life = { 1, 1.6 }, speed = { 0.5, 1 }, rate = 14, idle = 3, spread = 60, up = true,
				rotation = { 0, 360 }, spin = { -30, 30 }, light = 0.6 },
		},
	},

	-- Snow drifting down around you; the client adds snowflakes and frost prints.
	Snowflake = {
		ribbon = { width = 0.9, life = 0.5, light = 0.6, from = 0.4, to = -1.2, alpha = 0.3 },
		emitters = {
			{ at = "sky", tex = TEX.spark, colors = { rgb(255, 255, 255), rgb(200, 235, 255) }, size = { 0.3, 0.2 },
				life = { 1.6, 2.4 }, speed = { 0.5, 1.5 }, rate = 24, idle = 10, spread = 180, accel = Vector3.new(0, -2.5, 0),
				spin = { -90, 90 }, light = 0.6, inherit = 0.3 },
		},
	},

	-- Lunar New Year: golden sparks rising; the client floats little red lanterns.
	Lantern = {
		ribbon = { width = 1, life = 0.5, light = 0.9, from = 0.4, to = -1.4, alpha = 0.15 },
		emitters = {
			{ at = "feet", tex = TEX.spark, colors = { rgb(255, 230, 120), rgb(255, 120, 40) }, size = { 0.3, 0 },
				life = { 1.2, 2 }, speed = { 1.5, 3 }, rate = 16, idle = 4, spread = 30, up = true, light = 1 },
		},
		glow = { color = rgb(255, 90, 60), brightness = 1, range = 9 },
	},

	-- Valentine: pink glitter; the client floats hearts.
	Heart = {
		ribbon = { width = 1, life = 0.55, light = 0.7, from = 0.4, to = -1.4, alpha = 0.2 },
		emitters = {
			{ at = "body", tex = TEX.spark, colors = { rgb(255, 200, 230), rgb(255, 70, 130) }, size = { 0, 0.35, 0 },
				life = { 0.7, 1.2 }, speed = { 1, 2 }, rate = 14, idle = 3, spread = 180, accel = Vector3.new(0, 1.5, 0), light = 1 },
		},
	},

	-- Daily #1: royal gold-and-rainbow ribbon, gold stars, rainbow stars circling
	-- you; the client adds golden shockwaves on every few steps.
	Champion = {
		ribbon = { width = 2, life = 0.9, light = 1, from = 1, to = -1.6, alpha = 0 },
		emitters = {
			{ at = "body", tex = TEX.spark, colors = { rgb(255, 250, 200), rgb(255, 210, 60) }, size = { 0, 0.6, 0 },
				life = { 0.8, 1.4 }, speed = { 1, 3 }, rate = 30, idle = 10, spread = 180, accel = Vector3.new(0, -2, 0),
				spin = { -180, 180 }, light = 1 },
			{ at = "orbitA", tex = TEX.spark, colors = { rgb(255, 120, 200), rgb(255, 240, 120), rgb(120, 220, 255) },
				size = { 0.45, 0 }, life = { 0.8, 1.2 }, speed = { 0, 0.3 }, rate = 26, idle = 16, light = 1 },
			{ at = "orbitB", tex = TEX.spark, colors = { rgb(120, 220, 255), rgb(255, 240, 120), rgb(255, 120, 200) },
				size = { 0.45, 0 }, life = { 0.8, 1.2 }, speed = { 0, 0.3 }, rate = 26, idle = 16, light = 1 },
		},
		glow = { color = rgb(255, 220, 120), brightness = 2, range = 14 },
	},

	-- Daily #2: cool silver shimmer; the client throws glinting mirror shards.
	Silver = {
		ribbon = { width = 1.6, life = 0.7, light = 0.9, from = 0.8, to = -1.4, alpha = 0.05 },
		emitters = {
			{ at = "body", tex = TEX.spark, colors = { rgb(255, 255, 255), rgb(200, 220, 255) }, size = { 0, 0.45, 0 },
				life = { 0.6, 1.1 }, speed = { 1, 2.5 }, rate = 26, idle = 8, spread = 180, spin = { -180, 180 }, light = 1 },
			{ at = "orbitA", tex = TEX.spark, colors = { rgb(230, 240, 255), rgb(170, 185, 210) }, size = { 0.35, 0 },
				life = { 0.6, 1 }, speed = { 0, 0.2 }, rate = 18, idle = 10, light = 1 },
		},
		glow = { color = rgb(210, 225, 255), brightness = 1.5, range = 12 },
	},

	-- Daily #3: warm copper sparks flying from your feet + dust puffs.
	Bronze = {
		ribbon = { width = 1.5, life = 0.6, light = 0.8, from = 0.8, to = -1.4, alpha = 0.05 },
		emitters = {
			{ at = "feet", tex = TEX.spark, colors = { rgb(255, 220, 160), rgb(230, 140, 60), rgb(160, 80, 30) },
				size = { 0.35, 0 }, life = { 0.4, 0.8 }, speed = { 5, 9 }, rate = 30, idle = 4, spread = 50, up = true,
				accel = Vector3.new(0, -14, 0), light = 1 },
			{ at = "feet", tex = TEX.smoke, colors = { rgb(200, 150, 110) }, size = { 0.8, 2 }, transparency = { 0.7, 1 },
				life = { 0.8, 1.2 }, speed = { 0.5, 1 }, rate = 6, spread = 70, up = true, rotation = { 0, 360 }, light = 0.2 },
		},
		glow = { color = rgb(255, 170, 100), brightness = 1, range = 10 },
	},
}
TrailFx.Looks = Looks

local function emitter(spec: Emitter): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = "CT_Fx"
	e.Texture = spec.tex
	e.Color = colors(spec.colors)
	e.Size = numbers(spec.size)
	e.Transparency = numbers(spec.transparency or { 0, 1 })
	e.Lifetime = NumberRange.new(spec.life[1], spec.life[2])
	e.Speed = NumberRange.new(spec.speed[1], spec.speed[2])
	e.Rate = spec.rate
	local spread = spec.spread or 0
	e.SpreadAngle = Vector2.new(spread, spread)
	e.Acceleration = spec.accel or Vector3.zero
	e.Drag = spec.drag or 0
	if spec.rotation then
		e.Rotation = NumberRange.new(spec.rotation[1], spec.rotation[2])
	end
	if spec.spin then
		e.RotSpeed = NumberRange.new(spec.spin[1], spec.spin[2])
	end
	e.LightEmission = spec.light or 0.8
	e.LightInfluence = 0
	e.LockedToPart = spec.locked == true
	e.EmissionDirection = if spec.up then Enum.NormalId.Top else Enum.NormalId.Back
	e.VelocityInheritance = spec.inherit or 0
	e.ZOffset = spec.z or 0
	e:SetAttribute("MoveRate", spec.rate)
	e:SetAttribute("IdleRate", spec.idle or 0)
	return e
end

-- Removes everything a previous trail left on the root part.
function TrailFx.clear(root: BasePart)
	for _, child in root:GetChildren() do
		-- only what a trail made (chains and ice slides also live here)
		if child:GetAttribute("TrailPiece") or child.Name == "CT_Sparkle" then
			child:Destroy()
		end
	end
end

-- Builds trail `id` on a character. Returns the ribbon (for tests).
function TrailFx.apply(character: Model, id: string): Trail?
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return nil
	end
	TrailFx.clear(root)
	local look = Looks[id] or Looks.Basic
	local info = nil
	for _, t in Config.Trails do
		if t.id == id then
			info = t
		end
	end
	local palette = if info then info.colors else { Color3.new(1, 1, 1) }

	local spots: { [string]: Attachment } = {}
	local function spot(name: string): Attachment
		local att = spots[name]
		if not att then
			att = Instance.new("Attachment")
			att.Name = "CT_" .. name
			att.Position = SPOTS[name] or Vector3.zero
			att:SetAttribute("TrailPiece", true)
			att.Parent = root
			spots[name] = att
		end
		return att :: Attachment
	end

	-- the ribbon
	local r = look.ribbon
	local a0 = Instance.new("Attachment")
	a0.Name = "CT_A0"
	a0.Position = Vector3.new(0, r.from, 0.4)
	a0:SetAttribute("TrailPiece", true)
	a0.Parent = root
	local a1 = Instance.new("Attachment")
	a1.Name = "CT_A1"
	a1.Position = Vector3.new(0, r.to, 0.4)
	a1:SetAttribute("TrailPiece", true)
	a1.Parent = root
	local ribbon = Instance.new("Trail")
	ribbon.Name = "CT_Trail"
	ribbon.Attachment0 = a0
	ribbon.Attachment1 = a1
	ribbon.Color = colors(palette)
	ribbon.Lifetime = r.life
	ribbon.LightEmission = r.light
	ribbon.LightInfluence = 1 - r.light
	ribbon.FaceCamera = true
	ribbon.MinLength = 0.05
	ribbon.WidthScale = NumberSequence.new(r.width, 0.05)
	ribbon.Transparency = NumberSequence.new(r.alpha, 1)
	ribbon:SetAttribute("TrailPiece", true)
	ribbon.Parent = root

	for _, spec in look.emitters do
		emitter(spec).Parent = spot(spec.at)
	end

	if look.glow then
		local light = Instance.new("PointLight")
		light.Name = "CT_Glow"
		light.Color = look.glow.color
		light.Brightness = look.glow.brightness
		light.Range = look.glow.range
		light.Shadows = false
		light:SetAttribute("Base", look.glow.brightness)
		light:SetAttribute("TrailPiece", true)
		light.Parent = root
	end

	character:SetAttribute("TrailFx", id)
	return ribbon
end

return TrailFx
