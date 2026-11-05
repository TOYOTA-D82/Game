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

-- One wing: a thin root plate plus three feathers fanning out to the side.
-- side = 1 (right) or -1 (left). Returns the root part; feathers are welded to it.
local function wing(model: Model, look: string, side: number, at: CFrame): BasePart
	local info = Config.Wings[look] or Config.Wings.Fairy
	local s = info.size
	local root = Instance.new("Part")
	root.Name = if side > 0 then "WingR" else "WingL"
	root.Size = Vector3.new(0.4, 0.4, 0.2)
	root.Transparency = 1
	ghost(root)
	root.CFrame = at
	root.Parent = model
	for i = 1, 3 do
		local feather = Instance.new("Part")
		feather.Name = "Feather"
		local length = 2.6 * s * (1 - (i - 1) * 0.18)
		feather.Size = Vector3.new(length, 0.7 * s, 0.12)
		feather.Color = info.colors[1]:Lerp(info.colors[2], (i - 1) / 2)
		feather.Material = if look == "Fairy" then Enum.Material.Glass else Enum.Material.SmoothPlastic
		feather.Transparency = if look == "Fairy" then 0.25 else 0
		ghost(feather)
		feather.CFrame = at
			* CFrame.Angles(0, 0, side * (0.55 - (i - 1) * 0.35))
			* CFrame.new(side * length / 2, -(i - 1) * 0.15 * s, 0)
		feather.Parent = model
		weldTo(feather, root)
		if i == 1 then
			local sparkle = Instance.new("ParticleEmitter")
			sparkle.Color = ColorSequence.new(info.colors[1], info.colors[2])
			sparkle.Rate = 10
			sparkle.Lifetime = NumberRange.new(0.5, 1)
			sparkle.Speed = NumberRange.new(0.5, 1.5)
			sparkle.Size = NumberSequence.new(0.25, 0)
			sparkle.LightEmission = 0.9
			sparkle.Parent = feather
		end
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

function Cosmetics.buildHalo(center: CFrame): Model
	local model = Instance.new("Model")
	model.Name = "CT_Halo"
	for i = 0, 9 do
		local a = i / 10 * math.pi * 2
		local bead = Instance.new("Part")
		bead.Shape = Enum.PartType.Ball
		bead.Size = Vector3.new(0.35, 0.35, 0.35)
		bead.Color = Color3.fromRGB(255, 230, 120)
		bead.Material = Enum.Material.Neon
		ghost(bead)
		bead.CFrame = center * CFrame.new(math.cos(a) * 1.1, 0, math.sin(a) * 1.1)
		bead.Parent = model
	end
	return model
end

function Cosmetics.buildCrown(top: CFrame): Model
	local model = Instance.new("Model")
	model.Name = "CT_Crown"
	local band = Instance.new("Part")
	band.Shape = Enum.PartType.Cylinder
	band.Size = Vector3.new(0.5, 1.5, 1.5)
	band.Color = Color3.fromRGB(255, 205, 50)
	band.Material = Enum.Material.Metal
	ghost(band)
	band.CFrame = top * CFrame.Angles(0, 0, math.pi / 2)
	band.Parent = model
	for i = 0, 4 do
		local a = i / 5 * math.pi * 2
		local spike = Instance.new("Part")
		spike.Shape = Enum.PartType.Ball
		spike.Size = Vector3.new(0.35, 0.35, 0.35)
		spike.Color = if i % 2 == 0 then Color3.fromRGB(255, 80, 120) else Color3.fromRGB(90, 200, 255)
		spike.Material = Enum.Material.Neon
		ghost(spike)
		spike.CFrame = top * CFrame.new(math.cos(a) * 0.65, 0.4, math.sin(a) * 0.65)
		spike.Parent = model
	end
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
