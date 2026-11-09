--!strict
-- Recording tour (自動錄影導覽): an automatic ~30 second tour through the REAL
-- game so a trailer can be screen-recorded without playing.
--
-- Your character really plays: it is steered like a player would (walk,
-- jump, steer in the air) with normal Roblox physics, collisions and
-- animations, so nothing passes through walls. The tour only films stretches
-- of today's routes the bot can run cleanly (no moving walls, spinners or
-- moving platforms), and if it falls it quickly retries that shot.
--
-- Starts by itself when you press Play in Studio with Config.TrailerMode on.
-- In the live game only the game's owner can start it: /trailer in chat or
-- Shift+T. Everything goes back to normal afterwards.

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
local camera = Workspace.CurrentCamera
local running = false

-- Sections the bot films (it can run these cleanly) and ones it never films.
local AVOID = { WallRun = true, Spinner = true, Mover = true, Rapids = true, Slide = true, Conveyor = true }
local HIP = 3 -- root part height above the floor

----------------------------------------------------------------------
-- Today's real route of a level (same generator + seed as the server)
----------------------------------------------------------------------
type Surface = Course.Surface
type Route = { path: { Surface }, builders: { string }, center: Vector3 }

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
	local mid = Vector3.zero
	for _, c in r.checkpoints do
		mid += Vector3.new(c[1], c[2], c[3]) / #r.checkpoints
	end
	if r.mode == "tower" then
		mid = Vector3.new(r.center[1], (r.top + r.bottom) / 2, r.center[2])
	end
	return { path = path, builders = r.builders, center = mid }
end

local function centerOf(s: Surface): Vector3
	return Vector3.new((s.minX + s.maxX) / 2, s.top, (s.minZ + s.maxZ) / 2)
end

-- a point on surface s, as close to p as possible, `inset` studs from the edge
local function into(s: Surface, p: Vector3, inset: number): Vector3
	local x = if s.maxX - s.minX > inset * 2 then math.clamp(p.X, s.minX + inset, s.maxX - inset) else (s.minX + s.maxX) / 2
	local z = if s.maxZ - s.minZ > inset * 2 then math.clamp(p.Z, s.minZ + inset, s.maxZ - inset) else (s.minZ + s.maxZ) / 2
	return Vector3.new(x, s.top, z)
end

local function gapXZ(a: Surface, b: Surface): number
	local dx = math.max(0, math.max(a.minX, b.minX) - math.min(a.maxX, b.maxX))
	local dz = math.max(0, math.max(a.minZ, b.minZ) - math.min(a.maxZ, b.maxZ))
	return math.sqrt(dx * dx + dz * dz)
end

local function builderOf(rt: Route, s: Surface): string
	return rt.builders[s.section] or ""
end

-- Can a player-like bot do this hop reliably?
local function doable(rt: Route, a: Surface, b: Surface): boolean
	if AVOID[builderOf(rt, a)] or AVOID[builderOf(rt, b)] then
		return false
	end
	local gap, dy = gapXZ(a, b), b.top - a.top
	if a.kind == "pad" then
		return gap <= 12
	end
	if gap <= 2.5 and dy > 3.6 then
		local name = builderOf(rt, b)
		return name == "Truss" or name == "Shaft" or name == "Climb"
	end
	return gap <= 6 and dy <= 3.6
end

-- Where to start a shot: the first stretch of `hops` doable hops, preferring
-- sections of the wanted types.
local function pickStart(rt: Route, wanted: { string }, hops: number): number?
	local function clean(i: number): boolean
		for k = i, math.min(#rt.path - 1, i + hops - 1) do
			if not doable(rt, rt.path[k], rt.path[k + 1]) then
				return false
			end
		end
		return i + hops <= #rt.path
	end
	for _, name in wanted do
		for i = 1, #rt.path - 1 do
			if builderOf(rt, rt.path[i]) == name and clean(i) then
				return i
			end
		end
	end
	for i = 2, #rt.path - 1 do
		if clean(i) then
			return i
		end
	end
	return nil
end

----------------------------------------------------------------------
-- Overlay: logo (allowed on Roblox video thumbnails) and a black fade
----------------------------------------------------------------------
local function makeOverlay(): (ScreenGui, Frame, Frame)
	local gui = Instance.new("ScreenGui")
	gui.Name = "CT_TrailerOverlay"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 60
	local logo = Instance.new("Frame")
	logo.BackgroundTransparency = 1
	logo.Size = UDim2.fromScale(1, 1)
	logo.Parent = gui
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
		l.TextStrokeTransparency = 1
		l.TextTransparency = 1
		l.Parent = logo
	end
	line("CHAINED TOWER", 0.43, 0.12, Color3.new(1, 1, 1))
	line("綁腳塔", 0.55, 0.12, Color3.fromRGB(255, 210, 63))
	local black = Instance.new("Frame")
	black.Size = UDim2.fromScale(1, 1)
	black.BackgroundColor3 = Color3.new(0, 0, 0)
	black.BackgroundTransparency = 1
	black.BorderSizePixel = 0
	black.Parent = gui
	gui.Parent = player:WaitForChild("PlayerGui")
	return gui, logo, black
end

local function setLogo(logo: Frame, alpha: number)
	for _, l in logo:GetChildren() do
		if l:IsA("TextLabel") then
			l.TextTransparency = 1 - alpha
			l.TextStrokeTransparency = 1 - alpha
		end
	end
end

----------------------------------------------------------------------
-- A friend chained behind you for the team shot. It replays exactly where
-- you were half a second earlier, so it only ever goes where you really went.
----------------------------------------------------------------------
type Ghost = { model: Model, root: BasePart, tracks: { [string]: AnimationTrack }, playing: string? }

local function makeGhost(character: Model): Ghost?
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
			if d.Parent == friend then
				d.Color = Color3.fromRGB(255, 205, 50)
			end
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end
	local humanoid = friend:FindFirstChildOfClass("Humanoid")
	local root = friend:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not (humanoid and root) then
		friend:Destroy()
		return nil
	end
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	root.Anchored = true
	local tracks: { [string]: AnimationTrack } = {}
	local animator = humanoid:FindFirstChildOfClass("Animator")
	local animate = character:FindFirstChild("Animate")
	if animator and animate then
		for kind, folderName in { run = "run", jump = "jump", fall = "fall", climb = "climb", idle = "idle" } do
			local f = animate:FindFirstChild(folderName)
			local anim = f and f:FindFirstChildOfClass("Animation")
			if anim then
				local okLoad, track = pcall(function()
					return animator:LoadAnimation(anim)
				end)
				if okLoad and track then
					tracks[kind] = track
				end
			end
		end
	end
	return { model = friend, root = root, tracks = tracks }
end

local function ghostAnim(g: Ghost, kind: string)
	if g.playing == kind then
		return
	end
	for name, track in g.tracks do
		if name ~= kind and track.IsPlaying then
			track:Stop(0.15)
		end
	end
	local track = g.tracks[kind]
	if track then
		track:Play(0.15)
	end
	g.playing = kind
end

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
-- The tour
----------------------------------------------------------------------
-- alts: other levels to use if today's route has no clean stretch here.
-- friend = the chained duo shot.
type Shot = { area: string, alts: { string }?, kind: string, seconds: number, wanted: { string }?, friend: boolean?, logo: boolean? }

local SHOTS: { Shot } = {
	{ area = "Candy", kind = "orbit", seconds = 3.5, logo = true },
	{ area = "Meadow", alts = { "Beach", "Clouds" }, kind = "run", seconds = 6, wanted = { "Gateway", "Tunnel", "Rooftops", "Stones" } },
	{ area = "Castle", alts = { "Harbor", "Pirate" }, kind = "run", seconds = 7, wanted = { "Crumble", "Gateway", "Climb" }, friend = true },
	{ area = "Jungle", alts = { "Harbor", "Pirate", "Factory" }, kind = "run", seconds = 6, wanted = { "Stones", "Truss", "Tunnel" }, friend = true },
	{ area = "Volcano", alts = { "Factory", "Pirate" }, kind = "run", seconds = 6.5, wanted = { "LavaPlanks", "Crumble", "Vanish" }, friend = true },
	{ area = "Space", alts = { "Clouds", "Beach" }, kind = "run", seconds = 5.5, wanted = { "Asteroids", "JumpPads" } },
	{ area = "Harbor", alts = { "Pirate", "Factory" }, kind = "run", seconds = 6.5, wanted = { "Rooftops", "Crumble", "Stones" }, friend = true },
	{ area = "Challenge", kind = "run", seconds = 6, wanted = { "LavaPlanks", "Vanish", "Crumble", "JumpPads" } },
	{ area = "Neon", kind = "orbit", seconds = 4, logo = true },
}
local WALK_SPEED = 12 -- calmer than normal play (16) so it's easy on the eyes

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
	toServer:FireServer("trailer", true) -- Fire trail, wings, halo and crown for the tour
	task.wait(1)
	-- tone the glow down for video (bright glow on bright levels looks harsh)
	for _, d in character:GetDescendants() do
		if d:IsA("ParticleEmitter") or d:IsA("Trail") then
			(d :: any).LightEmission *= 0.5
		elseif d:IsA("PointLight") then
			d.Range *= 0.6
		end
	end

	local routes: { [string]: Route } = {}
	for _, s in SHOTS do
		for _, area in { s.area, table.unpack(s.alts or {}) } do
			if routes[area] == nil then
				local ok, rt = pcall(route, area)
				if ok and rt and #rt.path > 2 then
					routes[area] = rt
					print(("[Trailer] %s: route with %d stones"):format(area, #rt.path))
				else
					print(("[Trailer] %s: could not rebuild the route (%s)"):format(area, if ok then "level not found yet" else tostring(rt)))
				end
			end
		end
	end

	-- no HUD, chat, player list or top bar; you don't steer, the bot does
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
	local controls: any = nil
	pcall(function()
		local module = require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule") :: ModuleScript) :: any
		controls = module:GetControls()
		controls:Disable()
	end)
	local oldSpeed = humanoid.WalkSpeed
	humanoid.WalkSpeed = WALK_SPEED

	local home = root.CFrame
	-- hold the character still: the lobby is hidden during the tour, and an
	-- unheld character would fall into the void (Roblox deletes it below -500)
	root.Anchored = true
	root.AssemblyLinearVelocity = Vector3.zero
	local homeTheme = player:GetAttribute("Theme")
	local overlay, logo, black = makeOverlay()
	camera.CameraType = Enum.CameraType.Scriptable
	local ghost = makeGhost(character)
	if ghost then
		ghost.model.Parent = nil
	end

	local camParams = RaycastParams.new()
	camParams.FilterType = Enum.RaycastFilterType.Exclude
	-- camera + ghost run every frame; `mode` says what the camera does
	local mode = "orbit"
	local orbitCenter, orbitT0 = Vector3.zero, os.clock()
	local camPos = camera.CFrame.Position
	local flatDir = Vector3.zAxis
	local history: { { t: number, cf: CFrame, state: string } } = {}
	local showGhost = false
	local frameConn = RunService.RenderStepped:Connect(function(dt)
		local now = os.clock()
		local pos = root.Position
		local vel = root.AssemblyLinearVelocity
		local flat = Vector3.new(vel.X, 0, vel.Z)
		if flat.Magnitude > 2 then
			flatDir = flatDir:Lerp(flat.Unit, math.min(1, dt * 3))
			if flatDir.Magnitude > 0.01 then
				flatDir = flatDir.Unit
			end
		end
		-- record where you are, for the chained friend
		local st = humanoid:GetState()
		local state = if st == Enum.HumanoidStateType.Climbing then "climb"
			elseif st == Enum.HumanoidStateType.Jumping then "jump"
			elseif st == Enum.HumanoidStateType.Freefall then "fall"
			elseif flat.Magnitude > 1 then "run"
			else "idle"
		table.insert(history, { t = now, cf = root.CFrame, state = state })
		while #history > 0 and now - history[1].t > 2 do
			table.remove(history, 1)
		end
		if ghost then
			ghost.model.Parent = if showGhost then Workspace else nil
			if showGhost then
				local pick = history[1]
				for _, h in history do
					if h.t <= now - 0.7 then
						pick = h
					end
				end
				ghost.root.CFrame = pick.cf
				ghostAnim(ghost, pick.state)
			end
		end
		drawChain(root, ghost and ghost.root, showGhost)

		if mode == "orbit" then
			local k = now - orbitT0
			local eye = orbitCenter + Vector3.new(math.cos(0.6 + k * 0.18) * (130 - k * 6), 20 + k * 3, math.sin(0.6 + k * 0.18) * (130 - k * 6))
			camera.CFrame = CFrame.lookAt(eye, orbitCenter + Vector3.new(0, k * 3, 0))
			camPos = eye
		elseif mode == "follow" then
			local right = Vector3.new(flatDir.Z, 0, -flatDir.X)
			local side = if showGhost then -10 else 4
			local want = pos - flatDir * 19 + Vector3.new(0, 9, 0) + right * side
			camPos = camPos:Lerp(want, 1 - math.exp(-dt * 2.5)) -- calm camera
			local focus = pos + Vector3.new(0, 1.5, 0)
			local ignore: { Instance } = { character }
			if ghost then
				table.insert(ignore, ghost.model)
			end
			for _, l in chainLinks do
				table.insert(ignore, l)
			end
			camParams.FilterDescendantsInstances = ignore
			local hit = Workspace:Raycast(focus, camPos - focus, camParams)
			if hit then
				-- something is between the camera and you (a tunnel roof, a wall): move in front of it
				camPos = hit.Position + (focus - hit.Position).Unit * 1.2
			end
			camera.CFrame = CFrame.lookAt(camPos, focus + flatDir * 4)
		end
	end)

	local function fade(to: number, seconds: number)
		local from = 1 - black.BackgroundTransparency
		local t0 = os.clock()
		while os.clock() - t0 < seconds do
			local k = (os.clock() - t0) / seconds
			black.BackgroundTransparency = 1 - (from + (to - from) * k)
			RunService.RenderStepped:Wait()
		end
		black.BackgroundTransparency = 1 - to
	end

	local function teleport(cf: CFrame)
		root.AssemblyLinearVelocity = Vector3.zero
		character:PivotTo(cf)
	end

	-- The bot plays from path[i] for `seconds`. Returns false if it fell.
	local function runBot(rt: Route, startI: number, seconds: number): boolean
		local path = rt.path
		local i = startI
		local t0 = os.clock()
		local lastProgress = t0
		local pauseUntil = 0
		local function onTop(s: Surface, p: Vector3, margin: number): boolean
			return p.X >= s.minX - margin and p.X <= s.maxX + margin and p.Z >= s.minZ - margin and p.Z <= s.maxZ + margin and math.abs(p.Y - HIP - s.top) < 1.8
		end
		while os.clock() - t0 < seconds do
			RunService.Heartbeat:Wait()
			local cur, nxt = path[i], path[i + 1]
			if not nxt then
				humanoid:Move(Vector3.zero, false)
				return true
			end
			local p = root.Position
			local grounded = humanoid.FloorMaterial ~= Enum.Material.Air
			-- landed further along the route (or back on an earlier stone)?
			if grounded then
				for k = math.max(startI, i - 2), math.min(#path, i + 3) do
					if k ~= i and onTop(path[k], p, 0.4) then
						if k > i then
							lastProgress = os.clock()
							pauseUntil = os.clock() + 0.12 -- a short beat after landing, like a player
						end
						i = k
						cur, nxt = path[i], path[i + 1]
						break
					end
				end
				if not nxt then
					return true
				end
			end
			-- fell off, or stuck (after a short grace period)
			local fell = os.clock() - t0 > 0.6 and humanoid:GetState() ~= Enum.HumanoidStateType.Climbing and p.Y < math.min(cur.top, nxt.top) + HIP - 4
			if fell or humanoid.Health <= 0 or os.clock() - lastProgress > 4 then
				humanoid:Move(Vector3.zero, false)
				print(("[Trailer] stopped at hop %d: %s (at %.0f,%.0f,%.0f; stone top %.0f)"):format(
					i, if fell then "fell" elseif humanoid.Health <= 0 then "died" else "stuck", p.X, p.Y, p.Z, cur.top))
				return false
			end
			if grounded and os.clock() < pauseUntil then
				humanoid:Move(Vector3.zero, false)
				continue
			end
			local gap, dy = gapXZ(cur, nxt), nxt.top - cur.top
			local land = into(nxt, centerOf(cur), 1.2):Lerp(centerOf(nxt), 0.45)
			local function steer(to: Vector3)
				local d = Vector3.new(to.X - p.X, 0, to.Z - p.Z)
				humanoid:Move(if d.Magnitude > 0.35 then d.Unit else Vector3.zero, false)
			end
			local climbing = humanoid:GetState() == Enum.HumanoidStateType.Climbing
			local touching = gap < 0.6 and dy < 1 and dy > -3
			local ladder = gap <= 2.5 and dy > 3.6
			if climbing or (grounded and (touching or ladder)) then
				-- climbing a ladder/truss, walking across, or walking into a ladder
				steer(centerOf(nxt))
			elseif not grounded then
				steer(land) -- steer in the air like a player does
			else
				local exit = into(cur, centerOf(nxt), 0.9)
				local d = Vector3.new(exit.X - p.X, 0, exit.Z - p.Z).Magnitude
				if d > 1.1 then
					steer(exit)
				else
					steer(land)
					humanoid.Jump = true
				end
			end
		end
		humanoid:Move(Vector3.zero, false)
		return true
	end

	local used: { [string]: boolean } = {}
	for index, shot in SHOTS do
		local area, rt, start = shot.area, routes[shot.area], nil :: number?
		if shot.kind == "run" then
			-- first level (main, then backups) with a clean stretch, longest first
			local hopsWanted = math.ceil(shot.seconds * 1.5)
			local found = false
			for _, hops in { hopsWanted, hopsWanted - 2, hopsWanted - 4, 5 } do
				for _, a in { shot.area, table.unpack(shot.alts or {}) } do
					local r = routes[a]
					local st = r and not used[a] and pickStart(r, shot.wanted or {}, hops)
					if r and st then
						area, rt, start, found = a, r, st, true
						break
					end
				end
				if found then
					break
				end
			end
		end
		if not rt then
			continue
		end
		used[area] = true
		if not root.Parent or humanoid.Health <= 0 then
			print("[Trailer] the character is gone (respawned?) - stopping the tour")
			break
		end
		if shot.kind == "orbit" then
			if index > 1 then
				fade(1, 0.2)
			end
			Ambience.setArea(shot.area)
			orbitCenter, orbitT0 = rt.center, os.clock()
			mode = "orbit"
			showGhost = false
			if index > 1 then
				fade(0, 0.2)
			end
			local t0 = os.clock()
			while os.clock() - t0 < shot.seconds do
				local k = os.clock() - t0
				local a = if shot.logo then math.clamp(k / 0.4, 0, 1) else 0
				if shot.logo and index < #SHOTS then
					a *= math.clamp((shot.seconds - k) / 0.4, 0, 1)
				end
				setLogo(logo, a)
				RunService.RenderStepped:Wait()
			end
			setLogo(logo, if index == #SHOTS then 1 else 0)
		else
			Ambience.setArea(area)
			RunService.Heartbeat:Wait()
			local ran = false
			if not start then
				print(("[Trailer] %s: no clean stretch to run today"):format(area))
			else
				for attempt = 1, 3 do
					local s = rt.path[start]
					local nxt = rt.path[start + 1]
					local c = centerOf(s)
					-- find the real floor under the start stone before standing on it
					local params = RaycastParams.new()
					params.FilterType = Enum.RaycastFilterType.Exclude
					params.FilterDescendantsInstances = { character, ghost and ghost.model or character }
					local floor: RaycastResult? = nil
					for _ = 1, 30 do
						floor = Workspace:Raycast(Vector3.new(c.X, c.Y + 30, c.Z), Vector3.new(0, -60, 0), params)
						if floor then
							break
						end
						RunService.Heartbeat:Wait()
					end
					if not floor then
						print(("[Trailer] %s: no floor found at the start (%.0f,%.0f,%.0f)"):format(area, c.X, c.Y, c.Z))
						break
					end
					local hit = floor :: RaycastResult
					local p = hit.Position + Vector3.new(0, HIP, 0)
					local look = Vector3.new(centerOf(nxt).X, p.Y, centerOf(nxt).Z)
					root.Anchored = true -- hold still while the cut happens
					teleport(CFrame.lookAt(p, look))
					flatDir = Vector3.new(look.X - p.X, 0, look.Z - p.Z)
					flatDir = if flatDir.Magnitude > 0.01 then flatDir.Unit else Vector3.zAxis
					camPos = p - flatDir * 17 + Vector3.new(0, 8, 0)
					table.clear(history)
					mode = "follow"
					showGhost = shot.friend == true and ghost ~= nil
					task.wait(0.25)
					root.Anchored = false
					print(("[Trailer] %s: running from hop %d (try %d)"):format(area, start, attempt))
					local ok = runBot(rt, start, shot.seconds)
					if not ok then
						showGhost = false -- cut away before the friend would "replay" the miss
					end
					root.Anchored = true -- hold still again between shots
					root.AssemblyLinearVelocity = Vector3.zero
					if ok then
						ran = true
						break
					end
				end
			end
			if not ran then
				-- can't run it: fly the camera along today's real route instead
				showGhost = false
				mode = "fly"
				local path = rt.path
				local from = start or math.max(1, math.floor(#path / 3))
				local t0 = os.clock()
				while os.clock() - t0 < shot.seconds do
					local u = (os.clock() - t0) / shot.seconds
					local f = from + u * math.min(8, #path - from - 1)
					local k = math.floor(f)
					local a0, a1 = centerOf(path[k]), centerOf(path[math.min(#path, k + 1)])
					local at = a0:Lerp(a1, f - k)
					local ahead = centerOf(path[math.min(#path, k + 3)])
					local dir = Vector3.new(ahead.X - at.X, 0, ahead.Z - at.Z)
					dir = if dir.Magnitude > 0.01 then dir.Unit else Vector3.zAxis
					local eye = at - dir * 14 + Vector3.new(0, 10, 0)
					camPos = camPos:Lerp(eye, 0.15)
					camera.CFrame = CFrame.lookAt(camPos, ahead + Vector3.new(0, 2, 0))
					RunService.RenderStepped:Wait()
				end
			end
		end
	end
	task.wait(0.8)

	-- back to normal
	frameConn:Disconnect()
	for _, l in chainLinks do
		l:Destroy()
	end
	table.clear(chainLinks)
	if ghost then
		ghost.model:Destroy()
	end
	overlay:Destroy()
	humanoid:Move(Vector3.zero, false)
	Ambience.setArea(if type(homeTheme) == "string" then homeTheme else "main")
	if root.Parent then
		teleport(home)
		root.Anchored = false
	end
	humanoid.WalkSpeed = oldSpeed
	camera.CameraType = Enum.CameraType.Custom
	if controls then
		pcall(function()
			controls:Enable()
		end)
	end
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
			if not player.Character then
				player.CharacterAdded:Wait()
			end
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
