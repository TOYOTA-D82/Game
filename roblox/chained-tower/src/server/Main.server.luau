--!strict
-- Server entry point: builds the world and wires every system together.

local Players = game:GetService("Players")

local Data = require(script.Parent.Data)
local Game = require(script.Parent.Game)
local Progress = require(script.Parent.Progress)
local Shop = require(script.Parent.Shop)
local World = require(script.Parent.World)

local lobby = World.buildLobby()
Progress.startLeaderboard(lobby.soloBoard, "Solo")
Progress.startLeaderboard(lobby.teamBoard, "Team")
Shop.init(Game.onGranted)
Data.start()
Game.start(lobby)

local function onPlayer(player: Player)
	Progress.setupLeaderstats(player)
	local profile = Data.load(player)
	if not profile then
		return
	end
	Shop.checkPasses(player)
	Progress.sync(player)

	local function onCharacter(character: Model)
		character:WaitForChild("HumanoidRootPart", 5)
		character:WaitForChild("Head", 5)
		Progress.applyCosmetics(player)
	end
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
end

Players.PlayerAdded:Connect(onPlayer)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayer, player)
end

Players.PlayerRemoving:Connect(function(player)
	Data.release(player)
end)
