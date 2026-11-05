--!strict
-- Rounds, teams, chains, checkpoints, falls and items.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local TowerLayout = require(Shared.TowerLayout)
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
}

local tower: World.Tower = nil :: any
local lobby: World.Lobby = nil :: any
local roundEndsAt = 0
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

local function toLobby(player: Player)
	local offset = Vector3.new(math.random(-4, 4), 0, math.random(-4, 4))
	teleport(player, World.LobbySpawn + offset)
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
	end
	local f = team.folder
	f:SetAttribute("Mode", team.mode)
	f:SetAttribute("Members", table.concat(ids, ","))
	f:SetAttribute("Checkpoint", team.checkpoint)
	f:SetAttribute("UnchainUntil", team.unchainUntil)
	local mode = Config.Modes[team.mode]
	f:SetAttribute("Length", mode.chainLength or 0)
	f:SetAttribute("Radius", mode.zoneRadius or 0)
end

local function teleportTeam(team: Team, index: number)
	team.graceUntil = now() + 1.5
	for slot, m in team.members do
		teleport(m, World.checkpointCFrame(tower, index, slot))
	end
end

local function toastTeam(team: Team, key: string, args: { any }?, good: boolean?)
	for _, m in team.members do
		Net.send(m, "toast", { key = key, args = args, good = good })
	end
end

local function formTeam(players: { Player }, mode: string)
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
	}
	teams[team.id] = team
	for _, m in members do
		teamOf[m] = team
	end
	publish(team)
	folder.Parent = teamsFolder
	teleportTeam(team, 0)

	for _, m in members do
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
		if sendToLobby then
			toLobby(player)
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
	local mult = Config.Modes[team.mode].coinMultiplier
	for _, m in team.members do
		local got = Progress.addCoins(m, Config.CoinsForFinish * mult, true)
		local p = Data.get(m)
		if p then
			p.wins += 1
			Data.markDirty(m)
		end
		Progress.recordWin(m)
		Progress.addStat(m, "finishes")
		if team.mode ~= "solo" then
			Progress.addStat(m, "teamFinishes")
		end
		Net.send(m, "finish", { coins = got })
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
	if reward then
		local mult = Config.Modes[team.mode].coinMultiplier
		for _, m in team.members do
			Progress.addCoins(m, Config.CoinsPerSection * mult, true)
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
	if index >= tower.winIndex then
		finish(team)
	end
end

local function resetTeam(team: Team, who: Player)
	if team.finished or now() - team.lastReset < Config.SecondsBetweenResets then
		return
	end
	team.lastReset = now()
	teleportTeam(team, team.checkpoint)
	local cp = team.checkpoint
	team.fails[cp] = (team.fails[cp] or 0) + 1
	if team.mode ~= "solo" then
		toastTeam(team, "teamFell", { who.DisplayName })
	end
	if team.fails[cp] % Config.OfferSkipAfterFails == 0 and cp + 1 < tower.winIndex then
		for _, m in team.members do
			Net.send(m, "offerSkip")
		end
	end
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
	params.FilterDescendantsInstances = { tower.folder }
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
	params.FilterDescendantsInstances = { tower.folder }
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
	if team.checkpoint + 1 >= tower.winIndex then
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
-- Tower parts with behaviour
----------------------------------------------------------------------
local function wireTower(t: World.Tower)
	for index, part in t.checkpoints do
		part.Touched:Connect(function(hit)
			local player = Players:GetPlayerFromCharacter(hit.Parent)
			local team = player and teamOf[player]
			if team and index == team.checkpoint + 1 then
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
			part.Touched:Connect(function(hit)
				local player = Players:GetPlayerFromCharacter(hit.Parent)
				local team = player and teamOf[player]
				if player and team then
					resetTeam(team, player)
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

local function newTower()
	local event = Progress.currentEvent()
	local seed = math.floor(os.time() + math.random(1, 1e6))
	local layout = TowerLayout.generate(seed, Random.new(seed))
	local old = tower
	tower = World.buildTower(layout, event and event.accent or nil)
	wireTower(tower)
	if old then
		old.folder:Destroy()
	end
	Workspace:SetAttribute("TowerSections", tower.winIndex)
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

local function padTick()
	for _, pad in lobby.pads do
		local part = pad.part
		local state = padStates[part] or {}
		padStates[part] = state
		local list = occupants(part)
		local max = Config.Modes[pad.mode].maxPlayers
		part:SetAttribute("Count", math.min(#list, max))

		if pad.mode == "solo" then
			for _, p in list do
				formTeam({ p }, "solo")
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
			formTeam(group, pad.mode)
		else
			part:SetAttribute("Countdown", math.ceil(remaining))
		end
	end
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include

local function fallTick()
	rayParams.FilterDescendantsInstances = { tower.folder, Workspace:FindFirstChild("Lobby") :: Instance }
	local t = now()
	for _, team in teams do
		if team.finished or t < team.graceUntil then
			continue
		end
		local unchained = team.unchainUntil > t
		for _, m in team.members do
			local root = rootOf(m)
			if not root then
				continue
			end
			if root.Position.Y < -30 then
				resetTeam(team, m)
				break
			end
			local hit = Workspace:Raycast(root.Position, Vector3.new(0, -5, 0), rayParams)
			if hit then
				local kind = hit.Instance:GetAttribute("Kind")
				local section = hit.Instance:GetAttribute("Section")
				if kind == "Kill" or kind == "Ground" then
					resetTeam(team, m)
					break
				end
				if not unchained and type(section) == "number" and section >= 0 and section < team.checkpoint then
					resetTeam(team, m)
					break
				end
			end
		end
		if team.unchainUntil > 0 and not unchained then
			team.unchainUntil = 0
			publish(team)
			reelIn(team)
		end
	end
end

local function startRound()
	newTower()
	roundEndsAt = now() + Config.RoundSeconds
	Workspace:SetAttribute("RoundEndsAt", roundEndsAt)
end

function Game.start(theLobby: World.Lobby)
	lobby = theLobby
	startRound()

	local function watch(player: Player)
		-- respawned while in a team (e.g. pressed Reset): back to the team checkpoint
		player.CharacterAdded:Connect(function(character)
			local team = teamOf[player]
			if team then
				character:WaitForChild("HumanoidRootPart", 5)
				task.wait(0.1)
				local slot = table.find(team.members, player) or 1
				team.graceUntil = now() + 1.5
				teleport(player, World.checkpointCFrame(tower, team.checkpoint, slot))
			end
		end)
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		removeMember(player, false)
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
			task.wait(1)
			if now() >= roundEndsAt then
				for _, team in teams do
					dissolve(team)
				end
				startRound()
				Net.sendAll("toast", { key = "newTower", good = true })
			end
		end
	end)
end

return Game
