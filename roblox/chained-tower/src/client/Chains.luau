--!strict
-- Chains: pulls your character back when the chain is tight (runs on your own
-- client because you own your character's physics), draws everyone's chains,
-- and handles jump pads.
--   duo   = ankle chain between two players
--   squad = everyone chained to a heavy iron ball in the middle of the group

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

local Chains = {}

local player = Players.LocalPlayer
local teamsFolder = ReplicatedStorage:WaitForChild("Teams")

local visuals = Instance.new("Folder")
visuals.Name = "ChainVisuals"
visuals.Parent = Workspace

type Visual = { beams: { Beam }, ball: BasePart?, ballAtt: Attachment?, zone: BasePart? }
local cache: { [Instance]: Visual } = {}

local function rootOf(p: Player): BasePart?
	local character = p.Character
	if not character then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function membersOf(folder: Instance): { Player }
	local list = {}
	local raw = folder:GetAttribute("Members")
	if type(raw) ~= "string" then
		return list
	end
	for _, id in string.split(raw, ",") do
		local p = Players:GetPlayerByUserId(tonumber(id) or 0)
		if p then
			table.insert(list, p)
		end
	end
	return list
end

local function isUnchained(folder: Instance): boolean
	local untilTime = folder:GetAttribute("UnchainUntil")
	return type(untilTime) == "number" and untilTime > Workspace:GetServerTimeNow()
end

function Chains.myTeam(): Instance?
	local id = player:GetAttribute("TeamId")
	if type(id) ~= "string" then
		return nil
	end
	return teamsFolder:FindFirstChild(id)
end

local function chainAttachment(root: BasePart): Attachment
	local existing = root:FindFirstChild("CT_Chain")
	if existing and existing:IsA("Attachment") then
		return existing
	end
	local a = Instance.new("Attachment")
	a.Name = "CT_Chain"
	a.Position = Vector3.new(0, -2.4, 0) -- around the ankles
	a.Axis = Vector3.new(0, -1, 0) -- beam curves bend downward (chain sag)
	a.Parent = root
	return a
end

local function beam(v: Visual, i: number): Beam
	local b = v.beams[i]
	if not b then
		b = Instance.new("Beam")
		b.Width0 = 0.35
		b.Width1 = 0.35
		b.Segments = 12
		b.FaceCamera = true
		b.LightInfluence = 1
		b.Parent = visuals
		v.beams[i] = b
	end
	return b
end

local CHAIN = Color3.fromRGB(70, 70, 80)
local TIGHT = Color3.fromRGB(255, 70, 50)
local FIRE = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 230, 80)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 110, 20)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 40, 10)),
})

local function drawLink(b: Beam, a0: Attachment, a1: Attachment, limit: number, burning: boolean)
	b.Attachment0 = a0
	b.Attachment1 = a1
	b.Enabled = true
	local d = (a0.WorldPosition - a1.WorldPosition).Magnitude
	local slack = math.max(0, limit - d)
	b.CurveSize0 = slack * 0.35
	b.CurveSize1 = -slack * 0.35
	if burning then
		b.Color = FIRE
		b.LightEmission = 1
		b.Width0, b.Width1 = 0.6, 0.6
		return
	end
	b.LightEmission = 0
	b.Width0, b.Width1 = 0.35, 0.35
	local stretch = math.clamp((d / math.max(limit, 1) - 0.75) / 0.35, 0, 1)
	b.Color = ColorSequence.new(CHAIN:Lerp(TIGHT, stretch))
end

local function hide(v: Visual)
	for _, b in v.beams do
		b.Enabled = false
	end
	if v.ball then
		v.ball.Transparency = 1
	end
	if v.zone then
		v.zone.Transparency = 1
	end
end

local function makeBall(v: Visual)
	local ball = Instance.new("Part")
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.new(2.4, 2.4, 2.4)
	ball.Color = Color3.fromRGB(45, 45, 55)
	ball.Material = Enum.Material.Metal
	ball.Anchored = true
	ball.CanCollide = false
	ball.CanQuery = false
	ball.CanTouch = false
	ball.Parent = visuals
	local att = Instance.new("Attachment")
	att.Axis = Vector3.new(0, -1, 0)
	att.Parent = ball
	v.ball = ball
	v.ballAtt = att

	local zone = Instance.new("Part")
	zone.Shape = Enum.PartType.Cylinder
	zone.Color = Color3.fromRGB(180, 110, 255)
	zone.Material = Enum.Material.Neon
	zone.Anchored = true
	zone.CanCollide = false
	zone.CanQuery = false
	zone.CanTouch = false
	zone.Transparency = 1
	zone.Parent = visuals
	v.zone = zone
end

local function updateVisuals()
	local seen: { [Instance]: boolean } = {}
	local mine = Chains.myTeam()
	for _, folder in teamsFolder:GetChildren() do
		seen[folder] = true
		local v = cache[folder]
		if not v then
			v = { beams = {} }
			cache[folder] = v
		end
		local visual = v :: Visual
		local mode = folder:GetAttribute("Mode")
		local members = membersOf(folder)
		local burnUntil = folder:GetAttribute("BurnUntil")
		local burning = type(burnUntil) == "number" and burnUntil > Workspace:GetServerTimeNow()
		if isUnchained(folder) or #members < 2 then
			hide(visual)
			continue
		end
		local roots = {}
		for _, m in members do
			local r = rootOf(m)
			if r then
				table.insert(roots, r)
			end
		end
		if #roots < 2 then
			hide(visual)
			continue
		end

		if mode == "duo" then
			local length = folder:GetAttribute("Length") :: number
			drawLink(beam(visual, 1), chainAttachment(roots[1]), chainAttachment(roots[2]), length, burning)
			for i = 2, #visual.beams do
				visual.beams[i].Enabled = false
			end
		elseif mode == "squad" then
			if not visual.ball then
				makeBall(visual)
			end
			local radius = folder:GetAttribute("Radius") :: number
			local sum = Vector3.zero
			for _, r in roots do
				sum += r.Position
			end
			local center = sum / #roots - Vector3.new(0, 2, 0)
			local ball = visual.ball :: BasePart
			ball.Transparency = 0
			ball.CFrame = ball.CFrame:Lerp(CFrame.new(center), 0.35)
			for i, r in roots do
				drawLink(beam(visual, i), chainAttachment(r), visual.ballAtt :: Attachment, radius, burning)
			end
			for i = #roots + 1, #visual.beams do
				visual.beams[i].Enabled = false
			end
			local zone = visual.zone :: BasePart
			if folder == mine then
				zone.Size = Vector3.new(0.2, radius * 2, radius * 2)
				zone.CFrame = CFrame.new(center - Vector3.new(0, 0.6, 0)) * CFrame.Angles(0, 0, math.pi / 2)
				zone.Transparency = 0.85
			else
				zone.Transparency = 1
			end
		end
	end
	for folder, v in cache do
		if not seen[folder] then
			for _, b in v.beams do
				b:Destroy()
			end
			if v.ball then
				v.ball:Destroy()
			end
			if v.zone then
				v.zone:Destroy()
			end
			cache[folder] = nil
		end
	end
end

-- Hints for the UI ("hold jump to climb", ...). UI listens to this.
local hintEvent = Instance.new("BindableEvent")
Chains.Hint = hintEvent.Event
local lastHint: { [string]: number } = {}
local function hint(key: string)
	if os.clock() - (lastHint[key] or -100) > 12 then
		lastHint[key] = os.clock()
		hintEvent:Fire(key)
	end
end

local lastJumpRequest = -100
UserInputService.JumpRequest:Connect(function()
	lastJumpRequest = os.clock()
end)

local function humanoidOf(root: BasePart): Humanoid?
	return (root.Parent :: Model):FindFirstChildOfClass("Humanoid")
end

local function isGrounded(root: BasePart): boolean
	local humanoid = humanoidOf(root)
	return humanoid ~= nil and humanoid.FloorMaterial ~= Enum.Material.Air
end

-- Strong rope: if you're further than `limit` from the target, your speed away
-- from it is cancelled and you get pulled back in (this is what holds a player
-- who fell off an edge, so they dangle instead of dropping).
local function yank(root: BasePart, dir: Vector3, over: number, dt: number)
	local v = root.AssemblyLinearVelocity
	local radial = v:Dot(dir)
	local want = math.min(over * Config.ChainPullStrength, 70)
	if radial < want then
		root.AssemblyLinearVelocity = v + dir * (want - radial)
	end
	-- the humanoid fights velocity changes on the ground, so also nudge directly
	if over > 2 then
		root.CFrame += dir * math.min(over - 2, 4) * dt * 8
	end
end

-- One rope between me and a target point (partner, or the squad's iron ball).
local function rope(root: BasePart, target: Vector3, limit: number, dt: number)
	local offset = target - root.Position
	local d = offset.Magnitude
	if d <= limit or d < 0.01 then
		return
	end
	local dir = offset / d
	local over = d - limit
	local grounded = isGrounded(root)
	local targetBelow = target.Y < root.Position.Y - 2

	if grounded and targetBelow and over < 6 then
		-- Someone is hanging off an edge: their weight drags me slowly toward it.
		-- Walking the other way is faster than the drag, which hauls them back up.
		local flat = Vector3.new(dir.X, 0, dir.Z)
		if flat.Magnitude > 0.05 then
			root.CFrame += flat.Unit * Config.ChainDragSpeed * dt
		end
		hint("hintAnchor")
		return
	end

	yank(root, dir, over, dt)
	if not grounded and target.Y > root.Position.Y + 1 then
		-- I'm the one hanging: hold Jump to climb up the chain
		hint("hintHanging")
		if os.clock() - lastJumpRequest < 0.3 then
			local v = root.AssemblyLinearVelocity
			if v:Dot(dir) < Config.ClimbSpeed then
				root.AssemblyLinearVelocity = v + dir * (Config.ClimbSpeed - v:Dot(dir))
			end
		end
	end
end

local function applyChain(dt: number)
	local folder = Chains.myTeam()
	local me = rootOf(player)
	if not folder or not me or isUnchained(folder) then
		return
	end
	local mode = folder:GetAttribute("Mode")
	local members = membersOf(folder)
	if mode == "duo" then
		local length = folder:GetAttribute("Length") :: number
		for _, m in members do
			if m ~= player then
				local r = rootOf(m)
				if r then
					rope(me, r.Position, length, dt)
				end
			end
		end
	elseif mode == "squad" then
		local radius = folder:GetAttribute("Radius") :: number
		local sum, n = Vector3.zero, 0
		for _, m in members do
			local r = rootOf(m)
			if r then
				sum += r.Position
				n += 1
			end
		end
		if n >= 2 then
			rope(me, sum / n, radius, dt)
		end
	end
end

-- Water currents push you along their flow (you own your character's physics,
-- so this runs here). Walking against it is slow; get swept off and the chain
-- catches you.
local function currentPush(hitPart: Instance, me: BasePart, dt: number)
	if hitPart:GetAttribute("Kind") ~= "Current" then
		return
	end
	local fx = hitPart:GetAttribute("FlowX") :: number? or 0
	local fz = hitPart:GetAttribute("FlowZ") :: number? or 0
	local speed = hitPart:GetAttribute("FlowSpeed") :: number? or 10
	local flow = Vector3.new(fx :: number, 0, fz :: number)
	if flow.Magnitude < 0.1 then
		return
	end
	me.CFrame += flow.Unit * (speed :: number) * dt
	hint("hintCurrent")
end

local padParams = RaycastParams.new()
padParams.FilterType = Enum.RaycastFilterType.Include
local lastPad = 0

local function surfaces(dt: number)
	local me = rootOf(player)
	local tower = Workspace:FindFirstChild("Tower")
	if not me or not tower then
		return
	end
	padParams.FilterDescendantsInstances = { tower }
	local hit = Workspace:Raycast(me.Position, Vector3.new(0, -4, 0), padParams)
	if hit then
		currentPush(hit.Instance, me, dt)
	end
	if os.clock() - lastPad < 0.3 then
		return
	end
	if hit and hit.Instance:GetAttribute("Kind") == "JumpPad" then
		lastPad = os.clock()
		local boost = hit.Instance:GetAttribute("Boost")
		local humanoid = (me.Parent :: Model):FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
		end
		local v = me.AssemblyLinearVelocity
		me.AssemblyLinearVelocity = Vector3.new(v.X, if type(boost) == "number" then boost else 60, v.Z)
	end
end

-- White foam lines sliding along each water current (local visual only).
type Foam = { part: BasePart, origin: Vector3, dir: Vector3, span: number, speed: number, offset: number }
local foams: { Foam } = {}

local function buildFoam(tower: Instance)
	for _, f in foams do
		f.part:Destroy()
	end
	table.clear(foams)
	for _, water in tower:GetChildren() do
		if not water:IsA("BasePart") or water:GetAttribute("Kind") ~= "Current" then
			continue
		end
		local fx = water:GetAttribute("FlowX") :: number? or 0
		local fz = water:GetAttribute("FlowZ") :: number? or 0
		local flow = Vector3.new(fx :: number, 0, fz :: number)
		if flow.Magnitude < 0.1 then
			continue
		end
		flow = flow.Unit
		local alongX = math.abs(flow.X) > 0.5
		local span = if alongX then water.Size.X else water.Size.Z
		local cross = if alongX then water.Size.Z else water.Size.X
		local origin = water.Position + Vector3.new(0, water.Size.Y / 2 + 0.06, 0) - flow * span / 2
		for k = 0, 2 do
			local foam = Instance.new("Part")
			foam.Size = if alongX then Vector3.new(0.35, 0.1, cross - 0.2) else Vector3.new(cross - 0.2, 0.1, 0.35)
			foam.Color = Color3.new(1, 1, 1)
			foam.Material = Enum.Material.Neon
			foam.Transparency = 0.45
			foam.Anchored = true
			foam.CanCollide = false
			foam.CanQuery = false
			foam.CanTouch = false
			foam.Parent = visuals
			table.insert(foams, {
				part = foam,
				origin = origin,
				dir = flow,
				span = span,
				speed = (water:GetAttribute("FlowSpeed") :: number?) or 10,
				offset = k / 3 * span,
			})
		end
	end
end

local function animateFoam()
	local t = os.clock()
	for _, f in foams do
		local d = (f.offset + t * f.speed) % f.span
		f.part.CFrame = CFrame.new(f.origin + f.dir * d)
	end
end

function Chains.start()
	Workspace.ChildAdded:Connect(function(child)
		if child.Name == "Tower" then
			task.wait(0.5) -- let the parts replicate
			buildFoam(child)
		end
	end)
	local existing = Workspace:FindFirstChild("Tower")
	if existing then
		task.defer(buildFoam, existing)
	end
	RunService.RenderStepped:Connect(animateFoam)
	RunService.Heartbeat:Connect(function(dt)
		applyChain(dt)
		surfaces(dt)
	end)
	RunService.RenderStepped:Connect(updateVisuals)
end

return Chains
