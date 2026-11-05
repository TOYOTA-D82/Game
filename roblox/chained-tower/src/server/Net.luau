--!strict
-- Two remotes: ToClient (server -> client messages) and ToServer (player actions).
-- Every action goes through a rate limit and a pcall so a bad request can't break the server.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = {}

local folder = Instance.new("Folder")
folder.Name = "Net"
local toClient = Instance.new("RemoteEvent")
toClient.Name = "ToClient"
toClient.Parent = folder
local toServer = Instance.new("RemoteEvent")
toServer.Name = "ToServer"
toServer.Parent = folder
folder.Parent = ReplicatedStorage

type Handler = (player: Player, payload: any) -> ()
local handlers: { [string]: Handler } = {}
local budget: { [Player]: { tokens: number, last: number } } = {}

function Net.on(kind: string, handler: Handler)
	handlers[kind] = handler
end

function Net.send(player: Player, kind: string, payload: any?)
	if player.Parent == Players then
		toClient:FireClient(player, kind, payload)
	end
end

function Net.sendAll(kind: string, payload: any?)
	toClient:FireAllClients(kind, payload)
end

toServer.OnServerEvent:Connect(function(player: Player, kind: any, payload: any)
	if type(kind) ~= "string" then
		return
	end
	local b = budget[player]
	local now = os.clock()
	if not b then
		b = { tokens = 10, last = now }
		budget[player] = b
	end
	b.tokens = math.min(10, b.tokens + (now - b.last) * 5)
	b.last = now
	if b.tokens < 1 then
		return
	end
	b.tokens -= 1
	local handler = handlers[kind]
	if handler then
		local ok, err = pcall(handler, player, payload)
		if not ok then
			warn("[Net] handler", kind, "failed:", err)
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	budget[player] = nil
end)

return Net
