--!strict
-- Reward cosmetics built from parts (no uploaded meshes needed):
--   wings  (weekly top 10)  - two feathered wings on your back that flap
--   halo   (weekly #1)      - a ring of lights over your head
--   crown  (daily #1)       - a little golden crown
-- Used both on characters and on the lobby display stand.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local Cosmetics = {}

local function ghost(part: BasePart)
	part.Anchored = false
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
end

local function weldTo(part: BasePart, to: BasePart)
	local w = Instance.new("WeldConstraint")
	w.Part0 = to
	w.Part1 = part
	w.Parent = part
end

local SPARK = "rbxasset://textures/particles/sparkles_main.dds"

-- How each wing look is finished: feather material, glowing edge colour,
-- the dust it sheds and its light. (Colours and size live in Config.Wings.)
type WingStyle = {
	material: Enum.Material,
	alpha: number,
	reflect: number,
	edge: Color3,
	dust: { Color3 },
	dustRate: number,
	dustFall: number, -- downward pull on the dust
	light: Color3,
	tip: { Color3 },
}
local STYLES: { [string]: WingStyle } = {
	Angel = {
		material = Enum.Material.SmoothPlastic, alpha = 0, reflect = 0,
		edge = Color3.fromRGB(255, 215, 90),
		dust = { Color3.fromRGB(255, 255, 230), Color3.fromRGB(255, 210, 90) }, dustRate = 16, dustFall = -1.5,
		light = Color3.fromRGB(255, 225, 150),
		tip = { Color3.fromRGB(255, 255, 255), Color3.fromRGB(255, 220, 110) },
	},
	Silver = {
		material = Enum.Material.Metal, alpha = 0, reflect = 0.35,
		edge = Color3.fromRGB(150, 220, 255),
		dust = { Color3.fromRGB(255, 255, 255), Color3.fromRGB(170, 215, 255) }, dustRate = 12, dustFall = -1,
		light = Color3.fromRGB(190, 220, 255),
		tip = { Color3.fromRGB(255, 255, 255), Color3.fromRGB(150, 210, 255) },
	},
	Bronze = {
		material = Enum.Material.Metal, alpha = 0, reflect = 0.2,
		edge = Color3.fromRGB(255, 140, 50),
		dust = { Color3.fromRGB(255, 210, 130), Color3.fromRGB(230, 110, 40) }, dustRate = 12, dustFall = -6,
		light = Color3.fromRGB(255, 160, 90),
		tip = { Color3.fromRGB(255, 200, 140), Color3.fromRGB(220, 110, 50) },
	},
	Fairy = {
		material = Enum.Material.Glass, alpha = 0.35, reflect = 0.1,
		edge = Color3.fromRGB(255, 140, 230),
		dust = { Color3.fromRGB(150, 255, 240), Color3.fromRGB(255, 160, 240), Color3.fromRGB(190, 140, 255) },
		dustRate = 26, dustFall = -2.5,
		light = Color3.fromRGB(210, 160, 255),
		tip = { Color3.fromRGB(150, 255, 240), Color3.fromRGB(200, 150, 255), Color3.fromRGB(255, 160, 240) },
	},
}

local function sequence(list: { Color3 }): ColorSequence
	local keys = {}
	for i, c in list do
		table.insert(keys, ColorSequenceKeypoint.new((i - 1) / math.max(1, #list - 1), c))
	end
	if #keys == 1 then
		table.insert(keys, ColorSequenceKeypoint.new(1, list[1]))
	end
	return ColorSequence.new(keys)
end

-- One wing: an invisible root with five long flight feathers fanning out
-- (each with a glowing edge), three short covert feathers on top, glitter
-- dust from the wing tip and a light streak that follows the tip as it flaps.
-- side = 1 (right) or -1 (left). Returns the root part; feathers are welded to it.
local function wing(model: Model, look: string, side: number, at: CFrame): BasePart
	local info = Config.Wings[look] or Config.Wings.Fairy
	local style = STYLES[look] or STYLES.Fairy
	local s = info.size
	local root = Instance.new("Part")
	root.Name = if side > 0 then "WingR" else "WingL"
	root.Size = Vector3.new(0.4, 0.4, 0.2)
	root.Transparency = 1
	ghost(root)
	root.CFrame = at
	root.Parent = model

	local function feather(length: number, width: number, angle: number, drop: number, depth: number, color: Color3, edge: boolean): BasePart
		local f = Instance.new("Part")
		f.Name = "Feather"
		f.Size = Vector3.new(length, width, 0.1)
		f.Color = color
		f.Material = style.material
		f.Transparency = style.alpha
		f.Reflectance = style.reflect
		ghost(f)
		f.CFrame = at * CFrame.Angles(0, 0, side * angle) * CFrame.new(side * (length / 2 + 0.1), -drop, depth)
		f.Parent = model
		weldTo(f, root)
		if edge then
			local e = Instance.new("Part")
			e.Name = "FeatherEdge"
			e.Size = Vector3.new(length * 0.96, 0.09, 0.12)
			e.Color = style.edge
			e.Material = Enum.Material.Neon
			e.Transparency = if look == "Fairy" then 0.2 else 0
			ghost(e)
			e.CFrame = f.CFrame * CFrame.new(side * length * 0.02, -width / 2 + 0.03, 0)
			e.Parent = model
			weldTo(e, root)
		end
		return f
	end

	local tipFeather: BasePart? = nil
	local tipLength = 0
	for i = 1, 5 do
		local k = (i - 1) / 4
		local length = (3.1 - k * 1.5) * s
		local f = feather(length, 0.62 * s, 0.85 - k * 1.25, k * 0.25 * s, 0, info.colors[1]:Lerp(info.colors[2], k), true)
		if i == 1 then
			tipFeather, tipLength = f, length
		end
	end
	for i = 1, 3 do
		local k = (i - 1) / 2
		feather((1.5 - k * 0.3) * s, 0.5 * s, 0.6 - k * 0.7, 0.05, 0.09, info.colors[1]:Lerp(Color3.new(1, 1, 1), 0.35), false)
	end

	if tipFeather then
		local tipA = Instance.new("Attachment")
		tipA.Name = "WingTip"
		tipA.Position = Vector3.new(side * tipLength / 2, 0, 0)
		tipA.Parent = tipFeather
		local tipB = Instance.new("Attachment")
		tipB.Name = "WingTipIn"
		tipB.Position = Vector3.new(side * (tipLength / 2 - 0.9 * s), 0, 0)
		tipB.Parent = tipFeather

		local streak = Instance.new("Trail")
		streak.Name = "WingStreak"
		streak.Attachment0 = tipA
		streak.Attachment1 = tipB
		streak.Color = sequence(style.tip)
		streak.Lifetime = 0.35
		streak.LightEmission = 1
		streak.LightInfluence = 0
		streak.FaceCamera = true
		streak.Transparency = NumberSequence.new(0.2, 1)
		streak.Parent = tipFeather

		local dust = Instance.new("ParticleEmitter")
		dust.Name = "WingDust"
		dust.Texture = SPARK
		dust.Color = sequence(style.dust)
		dust.Rate = style.dustRate
		dust.Lifetime = NumberRange.new(0.8, 1.6)
		dust.Speed = NumberRange.new(0.3, 1.2)
		dust.SpreadAngle = Vector2.new(180, 180)
		dust.Acceleration = Vector3.new(0, style.dustFall, 0)
		dust.RotSpeed = NumberRange.new(-120, 120)
		dust.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.2, 0.32 * s),
			NumberSequenceKeypoint.new(1, 0),
		})
		dust.LightEmission = 1
		dust.LightInfluence = 0
		dust.Parent = tipA

		-- a soft shine along the whole wing
		local shine = Instance.new("ParticleEmitter")
		shine.Name = "WingShine"
		shine.Texture = SPARK
		shine.Color = ColorSequence.new(style.edge)
		shine.Rate = 5
		shine.Lifetime = NumberRange.new(0.3, 0.6)
		shine.Speed = NumberRange.new(0, 0)
		shine.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.5, 0.7 * s),
			NumberSequenceKeypoint.new(1, 0),
		})
		shine.LightEmission = 1
		shine.LightInfluence = 0
		shine.LockedToPart = true
		shine.Parent = tipB
	end

	if side > 0 then
		local light = Instance.new("PointLight")
		light.Name = "WingGlow"
		light.Color = style.light
		light.Brightness = 1.2
		light.Range = 9
		light.Shadows = false
		light.Parent = root
	end
	return root
end

-- A pair of wings positioned around `back` (a CFrame facing the same way as the body).
function Cosmetics.buildWings(look: string, back: CFrame): Model
	local model = Instance.new("Model")
	model.Name = "CT_Wings"
	model:SetAttribute("Look", look)
	for _, side in { 1, -1 } do
		wing(model, look, side, back * CFrame.new(side * 0.25, 0.4, 0) * CFrame.Angles(0, side * -0.35, 0))
	end
	return model
end

local function glitter(parent: Instance, color: Color3, rate: number, size: number)
	local e = Instance.new("ParticleEmitter")
	e.Name = "Glitter"
	e.Texture = SPARK
	e.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
	e.Rate = rate
	e.Lifetime = NumberRange.new(0.6, 1.2)
	e.Speed = NumberRange.new(0.3, 1)
	e.SpreadAngle = Vector2.new(180, 180)
	e.RotSpeed = NumberRange.new(-90, 90)
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.3, size),
		NumberSequenceKeypoint.new(1, 0),
	})
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Parent = parent
end

local function glow(parent: Instance, color: Color3, brightness: number, range: number)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Brightness = brightness
	l.Range = range
	l.Shadows = false
	l.Parent = parent
end

-- A glowing ring of 18 lights with a soft halo of glitter.
function Cosmetics.buildHalo(center: CFrame): Model
	local model = Instance.new("Model")
	model.Name = "CT_Halo"
	local core = Instance.new("Part")
	core.Name = "HaloCore"
	core.Size = Vector3.new(0.2, 0.2, 0.2)
	core.Transparency = 1
	ghost(core)
	core.CFrame = center
	core.Parent = model
	for i = 0, 17 do
		local a = i / 18 * math.pi * 2
		local bead = Instance.new("Part")
		bead.Name = "HaloBead"
		bead.Shape = Enum.PartType.Ball
		bead.Size = Vector3.new(0.3, 0.3, 0.3)
		bead.Color = if i % 2 == 0 then Color3.fromRGB(255, 235, 130) else Color3.fromRGB(255, 250, 210)
		bead.Material = Enum.Material.Neon
		ghost(bead)
		bead.CFrame = center * CFrame.new(math.cos(a) * 1.1, 0, math.sin(a) * 1.1)
		bead.Parent = model
	end
	glow(core, Color3.fromRGB(255, 230, 150), 1.5, 8)
	glitter(core, Color3.fromRGB(255, 230, 120), 10, 0.3)
	return model
end

-- A gold crown: band, five points with glowing gems, light and sparkle.
function Cosmetics.buildCrown(top: CFrame): Model
	local model = Instance.new("Model")
	model.Name = "CT_Crown"
	local band = Instance.new("Part")
	band.Name = "CrownBand"
	band.Shape = Enum.PartType.Cylinder
	band.Size = Vector3.new(0.5, 1.5, 1.5)
	band.Color = Color3.fromRGB(255, 205, 50)
	band.Material = Enum.Material.Metal
	band.Reflectance = 0.3
	ghost(band)
	band.CFrame = top * CFrame.Angles(0, 0, math.pi / 2)
	band.Parent = model
	for i = 0, 4 do
		local a = i / 5 * math.pi * 2
		local point = Instance.new("Part")
		point.Name = "CrownPoint"
		point.Size = Vector3.new(0.28, 0.55, 0.28)
		point.Color = Color3.fromRGB(255, 205, 50)
		point.Material = Enum.Material.Metal
		point.Reflectance = 0.3
		ghost(point)
		point.CFrame = top * CFrame.new(math.cos(a) * 0.62, 0.45, math.sin(a) * 0.62) * CFrame.Angles(0, -a, 0) * CFrame.Angles(0, math.pi / 4, 0)
		point.Parent = model
		local gem = Instance.new("Part")
		gem.Name = "CrownGem"
		gem.Shape = Enum.PartType.Ball
		gem.Size = Vector3.new(0.3, 0.3, 0.3)
		gem.Color = if i % 2 == 0 then Color3.fromRGB(255, 80, 120) else Color3.fromRGB(90, 200, 255)
		gem.Material = Enum.Material.Neon
		ghost(gem)
		gem.CFrame = top * CFrame.new(math.cos(a) * 0.62, 0.8, math.sin(a) * 0.62)
		gem.Parent = model
	end
	glow(band, Color3.fromRGB(255, 220, 120), 1, 7)
	glitter(band, Color3.fromRGB(255, 220, 90), 8, 0.25)
	return model
end

-- Welds every part of a model to `to` (keeping their current positions).
local function attach(model: Model, to: BasePart)
	for _, part in model:GetChildren() do
		if part:IsA("BasePart") then
			weldTo(part, to)
		end
	end
end

-- Wings use real Welds (not WeldConstraints) on their roots so every client
-- can flap them by changing C0.
local function attachWings(model: Model, torso: BasePart)
	for _, root in model:GetChildren() do
		if root:IsA("BasePart") and (root.Name == "WingL" or root.Name == "WingR") then
			local weld = Instance.new("Weld")
			weld.Name = "FlapWeld"
			weld.Part0 = torso
			weld.Part1 = root
			weld.C0 = torso.CFrame:ToObjectSpace(root.CFrame)
			weld:SetAttribute("BaseC0", weld.C0)
			weld:SetAttribute("Side", if root.Name == "WingR" then 1 else -1)
			weld.Parent = root
		end
	end
end

-- For the lobby display: freeze a model in place.
function Cosmetics.anchor(model: Model)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
		end
	end
end

function Cosmetics.clear(character: Model)
	for _, name in { "CT_Wings", "CT_Halo", "CT_Crown" } do
		local old = character:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end
end

-- Puts the right reward cosmetics on a character.
function Cosmetics.apply(character: Model, wings: string?, halo: boolean, crown: boolean)
	Cosmetics.clear(character)
	local torso = (character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")) :: BasePart?
	local head = character:FindFirstChild("Head") :: BasePart?
	if wings and torso then
		local back = torso.CFrame * CFrame.new(0, 0.2, torso.Size.Z / 2 + 0.15)
		local model = Cosmetics.buildWings(wings, back)
		model.Parent = character
		attachWings(model, torso)
	end
	if halo and head then
		local model = Cosmetics.buildHalo(head.CFrame * CFrame.new(0, head.Size.Y / 2 + 1, 0))
		model.Parent = character
		attach(model, head)
	end
	if crown and head then
		local model = Cosmetics.buildCrown(head.CFrame * CFrame.new(0, head.Size.Y / 2 + 0.3, 0))
		model.Parent = character
		attach(model, head)
	end
end

return Cosmetics
