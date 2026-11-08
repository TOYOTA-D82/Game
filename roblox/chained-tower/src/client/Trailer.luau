--!strict
-- Recording tour (自動錄影導覽): an automatic ~29 second camera tour through
-- the REAL game (real levels, real lighting, real effects) so a trailer can be
-- screen-recorded without playing. Your character runs today's real routes
-- with the normal run / jump / climb animations, wearing the Fire trail and
-- the reward wings, halo and crown.
--
-- Starts by itself when you press Play in Studio with Config.TrailerMode on.
-- In the live game only the game's owner can start it: type /trailer in chat
-- (or press Shift+T). Everything goes back to normal when it ends.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TextChatService = game:GetService("TextChatService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Course = require(Shared:WaitForChild("Course"))
local Themes = require(Shared:WaitForChild("Themes"))

local Ambience = require(script.Parent.Ambience)

local Trailer = {}

local player = Players.LocalPlayer
local running = false

----------------------------------------------------------------------
-- Rebuild a level's real route (same generator, same seed as the server)
----------------------------------------------------------------------
type Seg = { kind: string, a: Vector3, b: Vector3, t0: number, t1: number, h: number }
type Route = { segs: { Seg }, total: number, sectionStart: { [number]: number }, builders: { string }, center: Vector3, top: number, bottom: number, tower: boolean }

local function levelFolder(id: string): Instance?
	local levels = Workspace:FindFirstChild("Levels")
	local hidden = ReplicatedStorage:FindFirstChild("CT_HiddenAreas")
	return (levels and levels:FindFirstChild("Level_" .. id)) or (hidden and hidden:FindFirstChild("Level_" .. id))
end

local function route(id: string): Route?
	local folder = levelFolder(id)
	local day = folder and folder:GetAttribute("Day")
	if type(day) ~= "number" then
		return nil
	end
	local theme = Themes.get(id, day)
	if not theme then
		return nil
	end
	local origin = Themes.levelOrigin(theme)
	local seed = Course.dailySeed(theme, day)
	local r = Course.generate(theme, origin, Course.rng(seed), seed, Course.sequenceFor(theme, day))

	-- shortest jump path start -> finish
	local adj: { [number]: { number } } = {}
	for _, l in r.links do
		adj[l[1]] = adj[l[1]] or {}
		table.insert(adj[l[1]], l[2])
	end
	local parent: { [number]: number } = { [r.startSurface] = 0 }
	local queue, head = { r.startSurface }, 1
	while head <= #queue do
		local cur = r.surfaces[queue[head]]
		head += 1
		if cur.id == r.winSurface then
			break
		end
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
	local path = {}
	local at = r.winSurface
	while at and at ~= 0 do
		table.insert(path, 1, r.surfaces[at])
		at = parent[at]
	end
	if #path < 2 then
		return nil
	end

	-- walk / jump / climb timeline
	local low = (theme.gravity or 196.2) < 120
	local speed = 16
	local segs: { Seg } = {}
	local sectionStart: { [number]: number } = {}
	local t = 0
	local function center(s): Vector3
		return Vector3.new((s.minX + s.maxX) / 2, s.top, (s.minZ + s.maxZ) / 2)
	end
	local function into(s, p: Vector3): Vector3
		local x = if s.maxX - s.minX > 1.8 then math.clamp(p.X, s.minX + 0.9, s.maxX - 0.9) else (s.minX + s.maxX) / 2
		local z = if s.maxZ - s.minZ > 1.8 then math.clamp(p.Z, s.minZ + 0.9, s.maxZ - 0.9) else (s.minZ + s.maxZ) / 2
		return Vector3.new(x, s.top, z)
	end
	local entry = center(path[1])
	for i, s in path do
		if sectionStart[s.section] == nil then
			sectionStart[s.section] = t
		end
		local n = path[i + 1]
		local exit = if n then into(s, center(n)) else center(s)
		local d = (exit - entry).Magnitude
		if d > 0.05 then
			table.insert(segs, { kind = "run", a = entry, b = exit, t0 = t, t1 = t + d / speed, h = 0 })
			t += d / speed
		end
		if not n then
			break
		end
		local nxt = into(n, exit)
		local h = Vector3.new(nxt.X - exit.X, 0, nxt.Z - exit.Z).Magnitude
		local dy = nxt.Y - exit.Y
		if h < 3 and math.abs(dy) > 3 then
			local dur = math.abs(dy) / 11 + 0.15
			table.insert(segs, { kind = "climb", a = exit, b = nxt, t0 = t, t1 = t + dur, h = 0 })
			t += dur
		else
			local dur = math.clamp(0.34 + h * 0.045 + math.max(dy, 0) * 0.05, 0.36, 0.95)
			if low then
				dur *= 1.35
			end
			local arc = (if low then 4.5 else 2.4) + math.abs(dy) * 0.45 + math.max(0, h - 9) * 0.25
			table.insert(segs, { kind = "jump", a = exit, b = nxt, t0 = t, t1 = t + dur, h = arc })
			t += dur
		end
		entry = nxt
	end
	local mid = Vector3.zero
	for _, c in r.checkpoints do
		mid += Vector3.new(c[1], c[2], c[3]) / #r.checkpoints
	end
	if r.mode == "tower" then
		mid = Vector3.new(r.center[1], (r.top + r.bottom) / 2, r.center[2])
	end
	return { segs = segs, total = t, sectionStart = sectionStart, builders = r.builders, center = mid, top = r.top, bottom = r.bottom, tower = r.mode == "tower" }
end

-- Where the runner is at time t: position, what it's doing, which way it faces.
local function stateAt(rt: Route, t: number): (Vector3, string, Vector3)
	local segs = rt.segs
	local seg = segs[#segs]
	if t <= 0 then
		seg = segs[1]
	else
		for _, s in segs do
			if t < s.t1 then
				seg = s
				break
			end
		end
	end
	local u = math.clamp((t - seg.t0) / math.max(1e-3, seg.t1 - seg.t0), 0, 1)
	local p = seg.a:Lerp(seg.b, u)
	if seg.kind == "jump" then
		p = Vector3.new(p.X, seg.a.Y + (seg.b.Y - seg.a.Y) * u + 4 * seg.h * u * (1 - u), p.Z)
	end
	local dir = Vector3.new(seg.b.X - seg.a.X, 0, seg.b.Z - seg.a.Z)
	local kind = if t >= rt.total then "idle" elseif seg.kind == "jump" and u > 0.55 and seg.b.Y < seg.a.Y - 2 then "fall" else seg.kind
	return p, kind, dir
end

-- First section whose type is one of `wanted` (to show off lava, spinners...).
local function startFor(rt: Route, wanted: { string }, fallback: number): number
	for _, name in wanted do
		local i = table.find(rt.builders, name)
		if i and rt.sectionStart[i] then
			return math.max(0, rt.sectionStart[i] - 0.6)
		end
	end
	return rt.sectionStart[fallback] or 0
end

----------------------------------------------------------------------
-- Characters and animations
----------------------------------------------------------------------
type Runner = { model: Model, root: BasePart, tracks: { [string]: AnimationTrack }, playing: string?, lastDir: Vector3 }

local function loadTracks(model: Model, animateFrom: Instance?): { [string]: AnimationTrack }
	local tracks: { [string]: AnimationTrack } = {}
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	local animate = animateFrom or model:FindFirstChild("Animate")
	if not (animator and animate) then
		return tracks
	end
	for kind, folderName in { run = "run", jump = "jump", fall = "fall", climb = "climb", idle = "idle" } do
		local f = animate:FindFirstChild(folderName)
		local anim = f and f:FindFirstChildOfClass("Animation")
		if anim then
			local ok, track = pcall(function()
				return (animator :: Animator):LoadAnimation(anim)
			end)
			if ok and track then
				track.Priority = Enum.AnimationPriority.Action
				tracks[kind] = track
			end
		end
	end
	return tracks
end

local function playKind(r: Runner, kind: string)
	local want = if kind == "jump" or kind == "fall" or kind == "climb" or kind == "run" then kind else "idle"
	if r.playing == want then
		return
	end
	for name, track in r.tracks do
		if name ~= want and track.IsPlaying then
			track:Stop(0.12)
		end
	end
	local track = r.tracks[want] or r.tracks.run
	if track then
		track:Play(0.12)
		if want == "run" then
			track:AdjustSpeed(1.25)
		end
	end
	r.playing = want
end

local function place(r: Runner, rt: Route, t: number, dt: number)
	local p, kind, dir = stateAt(rt, t)
	if dir.Magnitude < 0.01 then
		dir = r.lastDir
	else
		r.lastDir = dir.Unit
	end
	local hip = 3 -- the root part stands ~3 studs above the floor
	local pos = p + Vector3.new(0, hip, 0)
	local before = r.root.Position
	r.root.CFrame = CFrame.lookAt(pos, pos + r.lastDir)
	-- give the anchored root a velocity so trail particles and footsteps react
	if dt > 0 then
		r.root.AssemblyLinearVelocity = (pos - before) / dt
	end
	playKind(r, kind)
end

-- A friend chained to you for the team shot: a copy of your avatar in yellow.
local function makeFriend(character: Model): Runner?
	character.Archivable = true
	local ok, copy = pcall(function()
		return character:Clone()
	end)
	character.Archivable = false
	if not ok or not copy then
		return nil
	end
	local friend = copy :: Model
	friend.Name = "TrailerFriend"
	for _, d in friend:GetDescendants() do
		if d:IsA("LuaSourceContainer") or d:IsA("Accessory") or d:IsA("Clothing") or d:IsA("ShirtGraphic") or d:IsA("BillboardGui") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			if d.Parent == friend then -- body parts only (wings keep their colours)
				d.Color = Color3.fromRGB(255, 205, 50)
			end
			d.CanCollide = false
		end
	end
	local humanoid = friend:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
	local root = friend:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		friend:Destroy()
		return nil
	end
	root.Anchored = true
	friend.Parent = Workspace
	return { model = friend, root = root, tracks = loadTracks(friend, character:FindFirstChild("Animate")), lastDir = Vector3.zAxis }
end

-- The ankle chain between the two runners (same look as the team chain).
local chainLinks: { BasePart } = {}
local function drawChain(a: BasePart?, b: BasePart?, show: boolean)
	if #chainLinks == 0 then
		for i = 1, 14 do
			local l = Instance.new("Part")
			l.Name = "TrailerChain"
			l.Anchored = true
			l.CanCollide = false
			l.CanQuery = false
			l.CanTouch = false
			l.Size = Vector3.new(0.3, 0.3, 0.9)
			l.Material = Enum.Material.Metal
			l.Color = Color3.fromRGB(140, 145, 160)
			l.Parent = Workspace
			chainLinks[i] = l
		end
	end
	for i, l in chainLinks do
		l.Transparency = if show then 0 else 1
		if show and a and b then
			local pa = a.Position - Vector3.new(0, 2.6, 0)
			local pb = b.Position - Vector3.new(0, 2.6, 0)
			local u = (i - 0.5) / #chainLinks
			local sag = math.clamp(12 - (pa - pb).Magnitude, 0, 12) * 0.35
			local p = pa:Lerp(pb, u) - Vector3.new(0, math.sin(u * math.pi) * sag, 0)
			l.CFrame = CFrame.lookAt(p, pb) * CFrame.Angles(0, 0, if i % 2 == 0 then math.pi / 2 else 0)
		end
	end
end

----------------------------------------------------------------------
-- Camera
----------------------------------------------------------------------
local camera = Workspace.CurrentCamera
local function followCam(rt: Route, t: number, dist: number, height: number, side: number)
	local tgt = Vector3.zero
	for k = 0, 7 do
		local p = stateAt(rt, t - k * 0.1)
		tgt += p / 8
	end
	local f = (stateAt(rt, t + 0.5)) - (stateAt(rt, t - 1.2))
	f = Vector3.new(f.X, 0, f.Z)
	f = if f.Magnitude < 0.01 then Vector3.zAxis else f.Unit
	local right = Vector3.new(f.Z, 0, -f.X)
	local eye = tgt - f * dist + Vector3.new(0, height, 0) + right * side
	camera.CFrame = CFrame.lookAt(eye, tgt + Vector3.new(0, 2.5, 0) + f * 5)
end

local function orbitCam(c: Vector3, r: number, h: number, a: number)
	camera.CFrame = CFrame.lookAt(c + Vector3.new(math.cos(a) * r, h, math.sin(a) * r), c)
end

----------------------------------------------------------------------
-- Logo overlay (logos / branding are allowed on Roblox video thumbnails)
----------------------------------------------------------------------
local function makeOverlay(): (ScreenGui, Frame)
	local gui = Instance.new("ScreenGui")
	gui.Name = "CT_TrailerOverlay"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 60
	local frame = Instance.new("Frame")
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.fromScale(1, 1)
	frame.Parent = gui
	local function line(text: string, y: number, h: number, color: Color3)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.AnchorPoint = Vector2.new(0.5, 0.5)
		l.Position = UDim2.fromScale(0.5, y)
		l.Size = UDim2.fromScale(0.9, h)
		l.Font = Enum.Font.FredokaOne
		l.TextScaled = true
		l.Text = text
		l.TextColor3 = color
		l.TextStrokeColor3 = Color3.fromRGB(27, 22, 54)
		l.TextStrokeTransparency = 0
		l.Parent = frame
		return l
	end
	line("CHAINED TOWER", 0.43, 0.12, Color3.new(1, 1, 1))
	line("綁腳塔", 0.55, 0.12, Color3.fromRGB(255, 210, 63))
	gui.Parent = player:WaitForChild("PlayerGui")
	return gui, frame
end

local function setOverlay(frame: Frame, alpha: number)
	for _, l in frame:GetChildren() do
		if l:IsA("TextLabel") then
			l.TextTransparency = 1 - alpha
			l.TextStrokeTransparency = 1 - alpha
		end
	end
end

----------------------------------------------------------------------
-- The tour
----------------------------------------------------------------------
type Shot = { t0: number, t1: number, area: string, cam: string, wanted: { string }?, from: number?, friend: boolean?, logo: boolean? }

local SHOTS: { Shot } = {
	{ t0 = 0, t1 = 3.5, area = "Candy", cam = "orbit", logo = true },
	{ t0 = 3.5, t1 = 8.5, area = "Meadow", cam = "follow", wanted = { "Gateway", "Tunnel", "Rooftops" }, from = 1 },
	{ t0 = 8.5, t1 = 13.5, area = "Castle", cam = "follow", wanted = { "Crumble", "Gateway", "Mover" }, from = 1, friend = true },
	{ t0 = 13.5, t1 = 17.5, area = "Volcano", cam = "follow", wanted = { "LavaPlanks", "Crumble" }, from = 1 },
	{ t0 = 17.5, t1 = 21.5, area = "Space", cam = "follow", wanted = { "Asteroids", "Spinner" }, from = 1 },
	{ t0 = 21.5, t1 = 25.5, area = "Challenge", cam = "follow", wanted = { "WallRun", "Rapids", "Spinner", "LavaPlanks" }, from = 3 },
	{ t0 = 25.5, t1 = 29.5, area = "Neon", cam = "orbit", logo = true },
}

function Trailer.run()
	if running then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (character and root and humanoid) then
		return
	end
	running = true
	local toServer = ReplicatedStorage:WaitForChild("Net"):WaitForChild("ToServer") :: RemoteEvent
	toServer:FireServer("trailer", true) -- show off the Fire trail, wings, halo and crown
	task.wait(1)

	-- routes for every shot
	local routes: { [string]: Route } = {}
	for _, s in SHOTS do
		if not routes[s.area] then
			local ok, rt = pcall(route, s.area)
			if ok and rt then
				routes[s.area] = rt
			end
		end
	end

	-- hide every HUD, chat, player list and the top bar
	local hidden: { ScreenGui } = {}
	for _, g in player:WaitForChild("PlayerGui"):GetChildren() do
		if g:IsA("ScreenGui") and g.Enabled and g.Name ~= "CT_Transition" then
			g.Enabled = false
			table.insert(hidden, g)
		end
	end
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false)
	end)
	pcall(function()
		StarterGui:SetCore("TopbarEnabled", false)
	end)

	local home = root.CFrame
	local homeTheme = player:GetAttribute("Theme")
	local animate = character:FindFirstChild("Animate") :: LocalScript?
	if animate then
		animate.Disabled = true
	end
	for _, track in humanoid:GetPlayingAnimationTracks() do
		track:Stop(0)
	end
	root.Anchored = true
	local me: Runner = { model = character, root = root, tracks = loadTracks(character, nil), lastDir = Vector3.zAxis }
	local friend = makeFriend(character)
	if friend then
		friend.model.Parent = nil
	end
	camera.CameraType = Enum.CameraType.Scriptable
	local overlay, logo = makeOverlay()

	local started = os.clock()
	local last = 0
	local shownArea = ""
	local starts: { [Shot]: number } = {}
	local done = Instance.new("BindableEvent")
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local T = os.clock() - started
		local dt = T - last
		last = T
		local shot = SHOTS[#SHOTS]
		for _, s in SHOTS do
			if T < s.t1 then
				shot = s
				break
			end
		end
		if shot.area ~= shownArea then
			shownArea = shot.area
			Ambience.setArea(shot.area)
		end
		local rt = routes[shot.area]
		local isFriend = shot.friend == true and friend ~= nil
		if friend then
			friend.model.Parent = if isFriend then Workspace else nil
		end
		if rt then
			if starts[shot] == nil then
				starts[shot] = startFor(rt, shot.wanted or {}, shot.from or 1)
			end
			local local_ = T - shot.t0
			if shot.cam == "orbit" then
				local r = 130 - local_ * 6
				orbitCam(rt.center + Vector3.new(0, local_ * 3, 0), r, 20, 0.6 + T * 0.18)
				place(me, rt, (rt.sectionStart[2] or 0) + T * 0.9, dt)
			else
				local tRun = starts[shot] + local_
				place(me, rt, tRun, dt)
				if isFriend and friend then
					place(friend, rt, tRun - 0.42, dt)
					local side = Vector3.new(friend.lastDir.Z, 0, -friend.lastDir.X)
					friend.root.CFrame += side * 2.2
					followCam(rt, tRun - 0.2, 19, 8, -10)
				else
					followCam(rt, tRun, if shot.area == "Space" then 22 else 19, if shot.area == "Space" then 10 else 8, 4)
				end
			end
		end
		drawChain(me.root, friend and friend.root, isFriend)
		-- logo at the start and the end
		local a = 0
		if shot.logo then
			local k = T - shot.t0
			a = math.clamp(k / 0.4, 0, 1) * math.clamp((shot.t1 - T) / 0.4, 0, 1)
			if shot == SHOTS[#SHOTS] then
				a = math.clamp(k / 0.4, 0, 1)
			end
		end
		setOverlay(logo, a)
		if T >= SHOTS[#SHOTS].t1 then
			conn:Disconnect()
			done:Fire()
		end
	end)
	done.Event:Wait()

	-- back to normal
	for _, l in chainLinks do
		l:Destroy()
	end
	table.clear(chainLinks)
	if friend then
		friend.model:Destroy()
	end
	overlay:Destroy()
	for _, track in me.tracks do
		track:Stop(0)
	end
	root.Anchored = false
	root.CFrame = home
	if animate then
		animate.Disabled = false
	end
	camera.CameraType = Enum.CameraType.Custom
	Ambience.setArea(if type(homeTheme) == "string" then homeTheme else "main")
	for _, g in hidden do
		g.Enabled = true
	end
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, true)
	end)
	pcall(function()
		StarterGui:SetCore("TopbarEnabled", true)
	end)
	toServer:FireServer("trailer", false)
	running = false
end

-- Who may start it: Studio with Config.TrailerMode, or the game's owner.
local function isOwner(): boolean
	return game.CreatorType == Enum.CreatorType.User and player.UserId == game.CreatorId
end

function Trailer.start()
	if RunService:IsStudio() and Config.TrailerMode then
		task.spawn(function()
			player.CharacterAdded:Wait()
			Workspace:WaitForChild("Levels", 60)
			task.wait(4) -- let every level arrive
			Trailer.run()
		end)
	end
	if not (isOwner() or RunService:IsStudio()) then
		return
	end
	-- /trailer in chat, or Shift+T
	pcall(function()
		local cmd = Instance.new("TextChatCommand")
		cmd.Name = "CT_TrailerCommand"
		cmd.PrimaryAlias = "/trailer"
		cmd.Triggered:Connect(function()
			task.spawn(Trailer.run)
		end)
		cmd.Parent = TextChatService
	end)
	player.Chatted:Connect(function(msg)
		if string.lower(msg) == "/trailer" then
			task.spawn(Trailer.run)
		end
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.T and UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then
			task.spawn(Trailer.run)
		end
	end)
end

return Trailer
