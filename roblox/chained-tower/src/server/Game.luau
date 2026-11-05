--!strict
-- Worlds, levels, teams, chains, checkpoints, falls and items.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Calendar = require(Shared.Calendar)
local Config = require(Shared.Config)
local Ranking = require(Shared.Ranking)
local Themes = require(Shared.Themes)
local Data = require(script.Parent.Data)
local Net = require(script.Parent.Net)
local Progress = require(script.Parent.Progress)
local World = require(script.Parent.World)

local Game = {}

type Team = {
	id: string,
	mode: string,
	members: { Player },
	checkpoint: number,
	folder: Folder,
	unchainUntil: number,
	lastReset: number,
	fails: { [number]: number },
	finished: boolean,
	graceUntil: number, -- skip fall checks right after a teleport
	unsafeSince: number?, -- when the last teammate stopped standing on something
	burning: boolean, -- lava fire is running along the chain
	level: World.Level,
	startedAt: number, -- server time the run started
	lastProgressAt: number, -- last checkpoint reached (active-minute points)
}

local lobby: World.Lobby = nil :: any
local levels: { [string]: World.Level } = {}
local teams: { [string]: Team } = {}
local teamOf: { [Player]: Team } = {}
local nextTeamId = 0

local teamsFolder = Instance.new("Folder")
teamsFolder.Name = "Teams"
teamsFolder.Parent = ReplicatedStorage

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	if not character then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function teleport(player: Player, cf: CFrame)
	local character = player.Character
	local root = rootOf(player)
	if character and root then
		root.AssemblyLinearVelocity = Vector3.zero
		character:PivotTo(cf)
	end
end

-- Where a player is: "main", "solo" or "team" (hub), and which sky to show.
local function setZone(player: Player, zone: string, theme: string)
	player:SetAttribute("Zone", zone)
	player:SetAttribute("Theme", theme)
end

-- Back to a world island: stand in front of the gate of the level you'd play
-- next today (level 1 if you haven't cleared anything today). The lobby uses
-- its normal spawn.
local function toHub(player: Player, world: string)
	local offset = Vector3.new(math.random(-2, 2), 0, math.random(-1, 1))
	if world == "solo" or world == "team" then
		local level = 1
		local p = Data.get(player)
		if p then
			Data.refreshDaily(player)
			local wd = (p.today :: any)[world]
			level = math.clamp((wd and wd.cleared or 0) + 1, 1, Themes.levelCount(world))
		end
		teleport(player, World.gateSpawn(world, level) + offset)
	else
		teleport(player, World.hubSpawn(world) + offset)
	end
	setZone(player, world, world)
end

----------------------------------------------------------------------
-- Teams
----------------------------------------------------------------------
local function publish(team: Team)
	local ids = {}
	for _, m in team.members do
		table.insert(ids, tostring(m.UserId))
		m:SetAttribute("TeamId", team.id)
		m:SetAttribute("Section", team.checkpoint)
		m:SetAttribute("Level", team.level.theme.id)
	end
	local f = team.folder
	f:SetAttribute("Mode", team.mode)
	f:SetAttribute("Members", table.concat(ids, ","))
	f:SetAttribute("Checkpoint", team.checkpoint)
	f:SetAttribute("UnchainUntil", team.unchainUntil)
	local mode = Config.Modes[team.mode]
	f:SetAttribute("Length", mode.chainLength or 0)
	f:SetAttribute("Radius", mode.zoneRadius or 0)
	f:SetAttribute("Level", team.level.theme.id)
	f:SetAttribute("Sections", team.level.winIndex)
end

local function teleportTeam(team: Team, index: number)
	team.graceUntil = now() + 1.5
	for slot, m in team.members do
		teleport(m, World.checkpointCFrame(team.level, index, slot))
	end
end

local function toastTeam(team: Team, key: string, args: { any }?, good: boolean?)
	for _, m in team.members do
		Net.send(m, "toast", { key = key, args = args, good = good })
	end
end

local function formTeam(players: { Player }, mode: string, level: World.Level)
	local members = {}
	for _, p in players do
		if p.Parent == Players and not teamOf[p] and rootOf(p) then
			table.insert(members, p)
		end
	end
	if #members == 0 then
		return
	end
	if #members == 1 then
		mode = "solo"
	end
	nextTeamId += 1
	local folder = Instance.new("Folder")
	folder.Name = "T" .. nextTeamId
	local team: Team = {
		id = folder.Name,
		mode = mode,
		members = members,
		checkpoint = 0,
		folder = folder,
		unchainUntil = 0,
		lastReset = 0,
		fails = {},
		finished = false,
		graceUntil = 0,
		burning = false,
		level = level,
		startedAt = now(),
		lastProgressAt = now(),
	}
	folder:SetAttribute("StartedAt", team.startedAt)
	teams[team.id] = team
	for _, m in members do
		teamOf[m] = team
		setZone(m, level.theme.world, level.theme.id)
	end
	publish(team)
	folder.Parent = teamsFolder
	teleportTeam(team, 0)

	for _, m in members do
		Net.send(m, "modeIntro", { mode = mode, level = level.theme.id })
		if mode == "solo" then
			Net.send(m, "toast", { key = "soloStart" })
		else
			local names = {}
			for _, other in members do
				if other ~= m then
					table.insert(names, other.DisplayName)
				end
			end
			Net.send(m, "toast", { key = "teamFormed", args = { table.concat(names, ", ") }, good = true })
		end
	end
end

local function removeMember(player: Player, sendToLobby: boolean)
	local team = teamOf[player]
	if not team then
		return
	end
	teamOf[player] = nil
	local index = table.find(team.members, player)
	if index then
		table.remove(team.members, index)
	end
	if player.Parent == Players then
		player:SetAttribute("TeamId", nil)
		player:SetAttribute("Section", nil)
		player:SetAttribute("Level", nil)
		if sendToLobby then
			toHub(player, team.level.theme.world)
		end
	end
	if #team.members == 0 then
		teams[team.id] = nil
		team.folder:Destroy()
	else
		if #team.members == 1 then
			team.mode = "solo"
		end
		publish(team)
	end
end

local function dissolve(team: Team)
	for _, m in table.clone(team.members) do
		removeMember(m, true)
	end
end

----------------------------------------------------------------------
-- Progress through the tower
----------------------------------------------------------------------
local function finish(team: Team)
	team.finished = true
	local seconds = now() - team.startedAt
	team.folder:SetAttribute("FinishedIn", seconds)
	local mult = Config.Modes[team.mode].coinMultiplier
	local theme = team.level.theme
	local hasNext = Themes.forLevel(theme.world, theme.level + 1) ~= nil
	local sections = team.level.winIndex
	for _, m in team.members do
		local got = Progress.addCoins(m, Config.CoinsForFinish * mult, true)
		local isNew, best = Progress.recordClear(m, theme.world, theme.level, seconds)
		local points, fast = Ranking.clearPoints(theme.level, team.mode, seconds, sections, isNew)
		Progress.addPoints(m, points, if fast then "fast" elseif isNew then "first" else "clear")
		local p = Data.get(m)
		if p then
			p.wins += 1
			if isNew then
				-- first clear of this level today: bonus coins
				local bonus = Config.FirstClearBonus * theme.level
				p.coins += bonus
				got += bonus
			end
			Data.markDirty(m)
		end
		Progress.addStat(m, "finishes")
		if team.mode ~= "solo" then
			Progress.addStat(m, "teamFinishes")
		end
		Net.send(m, "finish", {
			coins = got,
			seconds = seconds,
			best = best,
			points = points,
			unlocked = if isNew and hasNext then (Themes.forLevel(theme.world, theme.level + 1) :: Themes.Theme).id else nil,
		})
	end
	task.delay(5, function()
		if teams[team.id] == team then
			dissolve(team)
		end
	end)
end

local function advance(team: Team, index: number, reward: boolean)
	if team.finished or index ~= team.checkpoint + 1 then
		return
	end
	team.checkpoint = index
	team.fails = {}
	team.lastProgressAt = now()
	if reward then
		local mult = Config.Modes[team.mode].coinMultiplier
		for _, m in team.members do
			Progress.addCoins(m, Config.CoinsPerSection * mult, true)
			if index < team.level.winIndex then
				Progress.addPoints(m, Ranking.checkpointPoints(team.mode), "checkpoint")
			end
			Progress.addStat(m, "sections")
			if team.mode ~= "solo" then
				Progress.addStat(m, "teamSections")
			end
			local p = Data.get(m)
			if p and index > p.bestSection then
				p.bestSection = index
			end
		end
	end
	publish(team)
	if index >= team.level.winIndex then
		finish(team)
	end
end

local function resetTeam(team: Team, _who: Player)
	if team.finished or now() - team.lastReset < Config.SecondsBetweenResets then
		return
	end
	team.lastReset = now()
	teleportTeam(team, team.checkpoint)
	local cp = team.checkpoint
	team.fails[cp] = (team.fails[cp] or 0) + 1
	if team.mode ~= "solo" then
		toastTeam(team, "teamFell")
	end
	if team.fails[cp] % Config.OfferSkipAfterFails == 0 and cp + 1 < team.level.winIndex then
		for _, m in team.members do
			Net.send(m, "offerSkip")
		end
	end
end

-- Lava: the touched player catches fire, the fire runs along the chain to each
-- teammate (closest first), then the whole team goes back to the checkpoint.
local function burnTeam(team: Team, toucher: Player)
	if team.burning or team.finished then
		return
	end
	if team.mode == "solo" then
		resetTeam(team, toucher)
		return
	end
	team.burning = true
	local origin = rootOf(toucher)
	local order = table.clone(team.members)
	if origin then
		table.sort(order, function(a, b)
			local ra, rb = rootOf(a), rootOf(b)
			local da = if ra then (ra.Position - origin.Position).Magnitude else math.huge
			local db = if rb then (rb.Position - origin.Position).Magnitude else math.huge
			return da < db
		end)
	end
	local total = #order * Config.BurnHopSeconds + 0.6
	team.graceUntil = now() + total + 0.5
	team.folder:SetAttribute("BurnUntil", now() + total)
	toastTeam(team, "lavaBurn")
	local fires: { Instance } = {}
	for i, m in order do
		task.delay((i - 1) * Config.BurnHopSeconds, function()
			local root = rootOf(m)
			if root then
				local fire = Instance.new("Fire")
				fire.Size = 6
				fire.Heat = 12
				fire.Parent = root
				table.insert(fires, fire)
			end
		end)
	end
	task.delay(total, function()
		for _, fire in fires do
			fire:Destroy()
		end
		team.burning = false
		if teams[team.id] == team then
			team.lastReset = 0
			resetTeam(team, toucher)
		end
	end)
end

----------------------------------------------------------------------
-- Items
----------------------------------------------------------------------
local function consume(player: Player, item: string): boolean
	local p = Data.get(player)
	if not p then
		return false
	end
	Data.refreshDaily(player)
	if item == "unchain" then
		if p.freeUnchain > 0 then
			p.freeUnchain -= 1
		elseif p.unchain > 0 then
			p.unchain -= 1
		else
			return false
		end
	elseif item == "smash" then
		if p.freeSmash > 0 then
			p.freeSmash -= 1
		elseif p.smash > 0 then
			p.smash -= 1
		else
			return false
		end
	else
		return false
	end
	Data.markDirty(player)
	return true
end

local function useUnchain(player: Player)
	local team = teamOf[player]
	if not team or team.mode == "solo" or team.finished then
		return
	end
	if not consume(player, "unchain") then
		Net.send(player, "noItems", { item = "unchain" })
		return
	end
	team.unchainUntil = math.max(now(), team.unchainUntil) + Config.UnchainSeconds
	publish(team)
	toastTeam(team, "unchained", { Config.UnchainSeconds }, true)
	Progress.addStat(player, "unchains")
end

local function reelIn(team: Team)
	local leader: Player? = nil
	local best = -math.huge
	for _, m in team.members do
		local root = rootOf(m)
		if root and root.Position.Y > best then
			best = root.Position.Y
			leader = m
		end
	end
	if not leader then
		return
	end
	local leaderRoot = rootOf(leader) :: BasePart
	local mode = Config.Modes[team.mode]
	local limit = (mode.chainLength or (mode.zoneRadius or 12) * 2) * 1.3
	team.graceUntil = now() + 1.5
	for slot, m in team.members do
		local root = rootOf(m)
		if m ~= leader and root and (root.Position - leaderRoot.Position).Magnitude > limit then
			local offset = Vector3.new(slot % 2 == 0 and 2 or -2, 1, 0)
			teleport(m, leaderRoot.CFrame + offset)
			Net.send(m, "toast", { key = "reeledIn" })
		end
	end
end

local function canRestore(part: BasePart): boolean
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { part.Parent :: Instance }
	for _, hit in Workspace:GetPartBoundsInBox(part.CFrame, part.Size, params) do
		local model = hit:FindFirstAncestorOfClass("Model")
		if model and model:FindFirstChildOfClass("Humanoid") then
			return false
		end
	end
	return true
end

local function breakPart(part: BasePart)
	part:SetAttribute("Broken", true)
	local oldTransparency = part.Transparency
	part.Transparency = 1
	part.CanCollide = false
	for _, gui in part:GetChildren() do
		if gui:IsA("SurfaceGui") then
			gui.Enabled = false
		end
	end

	local boom = Instance.new("Explosion")
	boom.Position = part.Position
	boom.BlastPressure = 0
	boom.BlastRadius = 4
	boom.DestroyJointRadiusPercent = 0
	boom.ExplosionType = Enum.ExplosionType.NoCraters
	boom.Parent = Workspace

	local count = math.clamp(math.floor(part.Size.X * part.Size.Y * part.Size.Z / 12), 4, 10)
	for _ = 1, count do
		local chunk = Instance.new("Part")
		chunk.Size = Vector3.new(math.random(6, 16) / 10, math.random(6, 16) / 10, math.random(6, 16) / 10)
		chunk.Color = part.Color
		chunk.Material = part.Material
		local local_ = Vector3.new(
			(math.random() - 0.5) * part.Size.X,
			(math.random() - 0.5) * part.Size.Y,
			(math.random() - 0.5) * part.Size.Z
		)
		chunk.CFrame = part.CFrame * CFrame.new(local_)
		chunk.CanCollide = true
		chunk.Massless = true
		chunk.Parent = Workspace
		chunk.AssemblyLinearVelocity = (local_.Unit * math.random(15, 35)) + Vector3.new(0, math.random(20, 40), 0)
		chunk.AssemblyAngularVelocity = Vector3.new(math.random(-10, 10), math.random(-10, 10), math.random(-10, 10))
		game:GetService("Debris"):AddItem(chunk, 3)
	end

	local function restore()
		if not part.Parent then
			return
		end
		if not canRestore(part) then
			task.delay(1, restore)
			return
		end
		part.Transparency = oldTransparency
		part.CanCollide = true
		part:SetAttribute("Broken", nil)
		for _, gui in part:GetChildren() do
			if gui:IsA("SurfaceGui") then
				gui.Enabled = true
			end
		end
	end
	task.delay(Config.SmashRespawnSeconds, restore)
end

local function useSmash(player: Player)
	local team = teamOf[player]
	local root = rootOf(player)
	if not team or not root or team.finished then
		return
	end
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { team.level.folder }
	local range = Config.SmashRange
	local look = root.CFrame.LookVector * Vector3.new(1, 0, 1)
	if look.Magnitude < 0.1 then
		return
	end
	local center = CFrame.lookAt(root.Position, root.Position + look) * CFrame.new(0, 1, -range / 2)
	local found: { BasePart } = {}
	for _, part in Workspace:GetPartBoundsInBox(center, Vector3.new(10, 12, range), params) do
		if part:GetAttribute("Kind") == "Breakable" and not part:GetAttribute("Broken") then
			table.insert(found, part)
		end
	end
	if #found == 0 then
		Net.send(player, "toast", { key = "nothingToSmash" })
		return
	end
	if not consume(player, "smash") then
		Net.send(player, "noItems", { item = "smash" })
		return
	end
	table.sort(found, function(a, b)
		return (a.Position - root.Position).Magnitude < (b.Position - root.Position).Magnitude
	end)
	for i = 1, math.min(#found, Config.SmashMaxParts) do
		breakPart(found[i])
	end
	Net.send(player, "toast", { key = "smashed", good = true })
	Progress.addStat(player, "smashes", math.min(#found, Config.SmashMaxParts))
end

function Game.useSkip(player: Player)
	local team = teamOf[player]
	local p = Data.get(player)
	if not team or not p or team.finished then
		return
	end
	if team.checkpoint + 1 >= team.level.winIndex then
		return -- no skipping the final section
	end
	if p.skip <= 0 then
		Net.send(player, "promptProduct", { key = "Skip" })
		return
	end
	p.skip -= 1
	Data.markDirty(player)
	advance(team, team.checkpoint + 1, false)
	teleportTeam(team, team.checkpoint)
end

function Game.onGranted(player: Player, grant: { skip: number? })
	if grant.skip then
		Game.useSkip(player)
	end
end

Net.on("useUnchain", useUnchain)
Net.on("useSmash", useSmash)
Net.on("useSkip", Game.useSkip)
Net.on("leaveTeam", function(player)
	removeMember(player, true)
end)

----------------------------------------------------------------------
-- Level parts with behaviour
----------------------------------------------------------------------
local function wireLevel(t: World.Level)
	for index, part in t.checkpoints do
		part.Touched:Connect(function(hit)
			local player = Players:GetPlayerFromCharacter(hit.Parent)
			local team = player and teamOf[player]
			if team and team.level == t and index == team.checkpoint + 1 then
				advance(team, index, true)
			end
		end)
	end
	for _, part in t.folder:GetChildren() do
		if not part:IsA("BasePart") then
			continue
		end
		local kind = part:GetAttribute("Kind")
		if kind == "Kill" then
			-- one touch burns the whole chained team
			part.Touched:Connect(function(hit)
				local player = Players:GetPlayerFromCharacter(hit.Parent)
				local team = player and teamOf[player]
				if player and team and team.level == t then
					burnTeam(team, player)
				end
			end)
		elseif kind == "Crumble" then
			-- cracks, shakes, then falls apart about a second after someone steps on it
			local busy = false
			local original = part.Color
			local home = part.CFrame
			part.Touched:Connect(function(hit)
				if busy or not Players:GetPlayerFromCharacter(hit.Parent) then
					return
				end
				busy = true
				part.Color = Color3.fromRGB(255, 120, 60)
				for i = 1, 6 do
					part.CFrame = home * CFrame.new(math.random(-10, 10) / 60, 0, math.random(-10, 10) / 60)
					task.wait(0.15)
					if i == 6 then
						part.CFrame = home
					end
				end
				part.Transparency = 1
				part.CanCollide = false
				task.wait(4)
				part.Color = original
				part.Transparency = 0
				part.CanCollide = true
				busy = false
			end)
		elseif kind == "Fragile" then
			-- holds two different people; the third one to step on breaks it
			local stepped: { [Player]: boolean } = {}
			local count = 0
			local broken = false
			local capacity = (part:GetAttribute("Capacity") :: number?) or 2
			local labelText = part:FindFirstChild("CapacityLabel", true) :: TextLabel?
			local function show()
				if labelText then
					labelText.Text = "👣 " .. tostring(math.max(0, capacity - count))
				end
			end
			part.Touched:Connect(function(hit)
				local player = Players:GetPlayerFromCharacter(hit.Parent)
				if broken or not player or stepped[player] then
					return
				end
				stepped[player] = true
				count += 1
				show()
				if count > capacity then
					broken = true
					part.Transparency = 1
					part.CanCollide = false
					task.wait(6)
					table.clear(stepped)
					count = 0
					part.Transparency = 0.2
					part.CanCollide = true
					broken = false
					show()
				end
			end)
		elseif kind == "Vanish" then
			local busy = false
			part.Touched:Connect(function(hit)
				if busy or not Players:GetPlayerFromCharacter(hit.Parent) then
					return
				end
				busy = true
				task.wait(0.5)
				TweenService:Create(part, TweenInfo.new(0.25), { Transparency = 0.9 }):Play()
				task.wait(0.25)
				part.CanCollide = false
				task.wait(2.5)
				part.CanCollide = true
				part.Transparency = 0.15
				busy = false
			end)
		end
	end
end

local function updateSign()
	local event = Progress.currentEvent()
	Workspace:SetAttribute("EventId", event and event.id or "")
	if lobby then
		lobby.sign.Text = if event then ("🎉 %s event — free %s trail!"):format(event.id, event.trail) else ""
	end
end

----------------------------------------------------------------------
-- Loops
----------------------------------------------------------------------
type PadState = { started: number? }
local padStates: { [BasePart]: PadState } = {}

local function occupants(pad: BasePart): { Player }
	local list = {}
	for _, player in Players:GetPlayers() do
		local root = rootOf(player)
		if root and not teamOf[player] then
			local rel = pad.CFrame:PointToObjectSpace(root.Position)
			if math.abs(rel.X) <= pad.Size.X / 2 and math.abs(rel.Z) <= pad.Size.Z / 2 and rel.Y > 0 and rel.Y < 8 then
				table.insert(list, player)
			end
		end
	end
	return list
end

local lockedToast: { [Player]: number } = {}

-- Today's daily challenge: level 1 is always open, each clear opens the next.
local function unlockedLevel(player: Player, world: string): number
	local p = Data.get(player)
	if not p then
		return 0
	end
	if RunService:IsStudio() and Config.StudioUnlockAll then
		return math.huge
	end
	Data.refreshDaily(player)
	return ((p.today :: any)[world] :: Data.WorldDay).cleared + 1
end

local function portalTick()
	for _, portal in lobby.portals do
		for _, player in occupants(portal.part) do
			toHub(player, portal.target)
		end
	end
end

local function padTick()
	portalTick()
	for _, pad in lobby.pads do
		local part = pad.part
		local state = padStates[part] or {}
		padStates[part] = state
		local level = levels[(Themes.forLevel(pad.world, pad.level) :: Themes.Theme).id]
		local list = {}
		for _, player in occupants(part) do
			if unlockedLevel(player, pad.world) >= pad.level then
				table.insert(list, player)
			elseif os.clock() - (lockedToast[player] or 0) > 4 then
				lockedToast[player] = os.clock()
				Net.send(player, "toast", { key = "locked", args = { pad.level - 1 } })
			end
		end
		local max = Config.Modes[pad.mode].maxPlayers
		part:SetAttribute("Count", math.min(#list, max))

		if pad.mode == "solo" then
			for _, p in list do
				formTeam({ p }, "solo", level)
			end
			part:SetAttribute("Countdown", -1)
			continue
		end

		local needed = if pad.mode == "duo" then 2 else Config.SquadMinPlayers
		if #list < needed then
			state.started = nil
			part:SetAttribute("Countdown", -1)
			continue
		end
		local duration = if #list >= max then Config.FullPadCountdown else Config.SquadCountdown
		if not state.started then
			state.started = os.clock()
		end
		local remaining = duration - (os.clock() - (state.started :: number))
		if remaining <= 0 then
			state.started = nil
			part:SetAttribute("Countdown", -1)
			local group = {}
			for i = 1, math.min(#list, max) do
				group[i] = list[i]
			end
			formTeam(group, pad.mode, level)
		else
			part:SetAttribute("Countdown", math.ceil(remaining))
		end
	end
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include

local trussParams = OverlapParams.new()
trussParams.FilterType = Enum.RaycastFilterType.Include

-- Is this player standing on something (or climbing a ladder)?
-- Returns "safe", "air" (jumping / hanging on the chain), "lava" or "fallen"
-- (landed somewhere below the team's checkpoint, which means the chain gave way).
local function footing(team: Team, root: BasePart, unchained: boolean): string
	local cp = team.level.layout.checkpoints[team.checkpoint + 1]
	if root.Position.Y < cp[2] - Config.FallBelowCheckpoint then
		return "fallen" -- far below the team's checkpoint: nobody's holding the chain
	end
	rayParams.FilterDescendantsInstances = { team.level.folder, Workspace.Terrain }
	trussParams.FilterDescendantsInstances = { team.level.folder }
	local hit = Workspace:Raycast(root.Position, Vector3.new(0, -5, 0), rayParams)
	if hit then
		local kind = hit.Instance:GetAttribute("Kind")
		local section = hit.Instance:GetAttribute("Section")
		if kind == "Kill" then
			return "lava"
		end
		if kind == "Scenery" or hit.Instance:IsA("Terrain") then
			return "fallen" -- off the route (mountains, trees, buildings in the background)
		end
		if not unchained and type(section) == "number" and section >= 0 and section < team.checkpoint then
			return "fallen"
		end
		return "safe"
	end
	for _, part in Workspace:GetPartBoundsInRadius(root.Position, 3, trussParams) do
		if part:GetAttribute("Kind") == "Truss" then
			return "safe"
		end
	end
	return "air"
end

local function fallTick()
	local t = now()
	-- players walking around a world hub who fall off the island
	for _, player in Players:GetPlayers() do
		local zone = player:GetAttribute("Zone")
		if not teamOf[player] and (zone == "solo" or zone == "team" or zone == "main") then
			local root = rootOf(player)
			if root and root.Position.Y < World.hubSpawn(zone).Position.Y - 45 then
				toHub(player, zone) -- fell off the island
			end
		end
	end
	for _, team in teams do
		if team.finished or team.burning or t < team.graceUntil then
			continue
		end
		local unchained = team.unchainUntil > t
		local anySafe = false
		local fallenBy: Player? = nil
		local burnedBy: Player? = nil
		for _, m in team.members do
			local root = rootOf(m)
			if not root then
				anySafe = true -- respawning; don't count it as a fall
				continue
			end
			local state = footing(team, root, unchained)
			if state == "safe" then
				anySafe = true
			elseif state == "fallen" then
				fallenBy = m
			elseif state == "lava" then
				burnedBy = m
			end
		end
		if burnedBy then
			team.unsafeSince = nil
			burnTeam(team, burnedBy)
		elseif fallenBy then
			team.unsafeSince = nil
			resetTeam(team, fallenBy)
		elseif #team.members >= 2 then
			-- one player hanging off an edge is fine; everyone down is a fail
			if anySafe then
				team.unsafeSince = nil
			elseif team.unsafeSince == nil then
				team.unsafeSince = t
			elseif t - (team.unsafeSince :: number) >= Config.AllFallSeconds then
				team.unsafeSince = nil
				resetTeam(team, team.members[1])
			end
		end
		if team.unchainUntil > 0 and not unchained then
			team.unchainUntil = 0
			publish(team)
			reelIn(team)
		end
	end
end

-- Moving platforms follow a smooth back-and-forth based on server time, so the
-- clients can animate the exact same motion locally.
local function moverTick()
	local t = now()
	for _, level in levels do
		for _, m in level.movers do
			local phase = 0.5 - 0.5 * math.cos(2 * math.pi * (t % m.period) / m.period)
			m.part.CFrame = CFrame.new(m.base + m.dir * (m.travel * phase))
		end
	end
end

function Game.start(theLobby: World.Lobby)
	lobby = theLobby
	local levelsFolder = Instance.new("Folder")
	levelsFolder.Name = "Levels"
	levelsFolder.Parent = Workspace
	local builtDay = Calendar.dayNumber(os.time())
	for _, theme in Themes.List do
		local level = World.buildLevel(theme, levelsFolder, builtDay)
		levels[theme.id] = level
		wireLevel(level)
	end
	updateSign()

	-- A new day: rebuild every level with today's route. A level that a team
	-- is still running is rebuilt as soon as they leave it.
	local function rebuildIdleLevels()
		for _, theme in Themes.List do
			local level = levels[theme.id]
			if level.day ~= builtDay then
				local busy = false
				for _, team in teams do
					if team.level == level then
						busy = true
					end
				end
				if not busy then
					World.clearTerrain(level) -- sculpted landmarks move with the route
					level.folder:Destroy()
					local fresh = World.buildLevel(theme, levelsFolder, builtDay)
					levels[theme.id] = fresh
					wireLevel(fresh)
				end
			end
		end
	end
	task.spawn(function()
		while true do
			task.wait(20)
			local today = Calendar.dayNumber(os.time())
			if today ~= builtDay then
				builtDay = today
				Net.sendAll("toast", { key = "newDay", good = true })
			end
			rebuildIdleLevels()
		end
	end)

	-- Time points: every interval in a level, each player who actually moved
	-- gets points (standing still / AFK earns nothing). Clients show a countdown.
	task.spawn(function()
		local lastPos: { [Player]: Vector3 } = {}
		local moved: { [Player]: number } = {}
		local nextAt = now() + Config.Points.interval
		Workspace:SetAttribute("NextPointsAt", nextAt)
		while true do
			task.wait(1)
			-- add up how far each player in a level walked
			for _, team in teams do
				for _, m in team.members do
					local root = rootOf(m)
					if root then
						local last = lastPos[m]
						if last then
							local step = (root.Position - last).Magnitude
							if step < 40 then -- ignore teleports
								moved[m] = (moved[m] or 0) + step
							end
						end
						lastPos[m] = root.Position
					end
				end
			end
			if now() >= nextAt then
				for _, team in teams do
					if not team.finished then
						for _, m in team.members do
							if (moved[m] or 0) >= Config.Points.minMovePerInterval then
								Progress.addPoints(m, Config.Points.perInterval, "time")
							end
						end
					end
				end
				table.clear(moved)
				table.clear(lastPos)
				nextAt = now() + Config.Points.interval
				Workspace:SetAttribute("NextPointsAt", nextAt)
			end
		end
	end)
	game:GetService("RunService").Heartbeat:Connect(moverTick)

	local function watch(player: Player)
		-- respawned while in a team (e.g. pressed Reset): back to the team checkpoint
		player.CharacterAdded:Connect(function(character)
			local team = teamOf[player]
			character:WaitForChild("HumanoidRootPart", 5)
			task.wait(0.1)
			if team then
				local slot = table.find(team.members, player) or 1
				team.graceUntil = now() + 1.5
				teleport(player, World.checkpointCFrame(team.level, team.checkpoint, slot))
			else
				local zone = player:GetAttribute("Zone")
				if zone == "solo" or zone == "team" then
					toHub(player, zone)
				else
					setZone(player, "main", "main")
				end
			end
		end)
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		removeMember(player, false)
		lockedToast[player] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(0.25)
			local ok, err = pcall(padTick)
			if not ok then
				warn("[Game] padTick", err)
			end
		end
	end)
	task.spawn(function()
		while true do
			task.wait(0.2)
			local ok, err = pcall(fallTick)
			if not ok then
				warn("[Game] fallTick", err)
			end
		end
	end)
	task.spawn(function()
		while true do
			task.wait(60)
			updateSign()
		end
	end)
end

return Game
