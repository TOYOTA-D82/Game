-- Builds the lobby and many towers with real Roblox instance rules (Lune checks
-- every property name and value type against the Roblox API).
local env = require("./__prelude")
local World = require("./World")
local TowerLayout = require("./TowerLayout")

local lobby = World.buildLobby()
assert(#lobby.pads == 3, "3 pads")
local total = 0
for seed = 1, 40 do
	local layout = TowerLayout.generate(seed, env.Random.new(seed))
	local tower = World.buildTower(layout, if seed % 2 == 0 then env.Color3.fromRGB(255, 0, 0) else nil)
	local n = #tower.folder:GetChildren()
	total += n
	assert(tower.checkpoints[0] and tower.checkpoints[tower.winIndex], "checkpoints exist")
	local cf = World.checkpointCFrame(tower, 3, 2)
	assert(cf.Position.Y > 4, "teleport target above base")
	tower.folder:Destroy()
end
print(("built lobby + 40 towers (%d parts total, ~%d per tower)"):format(total, total // 40))
