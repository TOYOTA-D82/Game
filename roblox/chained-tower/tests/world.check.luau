-- Builds the lobby, both world hubs and all 10 levels with real Roblox instance
-- rules (Lune checks every property name and value type against the Roblox API).
local env = require("./__prelude")
local World = require("./World")
local Themes = require("./Themes")

local lobby = World.buildLobby()
assert(#lobby.portals == 4, "2 lobby portals + 1 back-portal per world hub, got " .. #lobby.portals)
assert(#lobby.pads == 5 + 10, "5 solo gates + 5x2 team gates, got " .. #lobby.pads)

local folder = env.Instance.new("Folder")
folder.Name = "Levels"
folder.Parent = env.game:GetService("Workspace")
local parts = 0
for _, theme in Themes.List do
	local level = World.buildLevel(theme, folder)
	assert(level.checkpoints[0] and level.checkpoints[level.winIndex], theme.id .. ": checkpoints exist")
	local n = #level.folder:GetDescendants()
	parts += n
	local cf = World.checkpointCFrame(level, 2, 3)
	assert(cf.Position.Y > Themes.Worlds[theme.world].origin[2], theme.id .. ": teleport target above the hub")
	print(("  %-8s %-5s level %d: %4d instances, sections: %s"):format(theme.id, theme.world, theme.level, n, table.concat(level.layout.builders, ", ")))
end
-- levels must be far apart so each feels like its own world
for _, a in Themes.List do
	for _, b in Themes.List do
		if a ~= b then
			local oa, ob = World.levelOrigin(a), World.levelOrigin(b)
			local d = math.sqrt((oa[1] - ob[1]) ^ 2 + (oa[3] - ob[3]) ^ 2)
			assert(d >= 600, ("%s and %s are only %d studs apart"):format(a.id, b.id, d))
		end
	end
end
print(("built lobby, 2 world hubs and 10 levels (%d instances in levels)"):format(parts))
