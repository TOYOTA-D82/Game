-- Builds the lobby, both world hubs and all 10 levels with real Roblox instance
-- rules (Lune checks every property name and value type against the Roblox API).
local env = require("./__prelude")
local World = require("./World")
local Themes = require("./Themes")

local lobby = World.buildLobby()
assert(#lobby.portals == 4, "2 lobby portals + 1 back-portal per world hub, got " .. #lobby.portals)
assert(#lobby.pads == 8 + 16, "8 solo gates + 8x2 team gates, got " .. #lobby.pads)

local folder = env.Instance.new("Folder")
folder.Name = "Levels"
folder.Parent = env.game:GetService("Workspace")
local parts = 0
for _, theme in Themes.List do
	local level = World.buildLevel(theme, folder, 20400)
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
print(("built lobby, 2 world hubs and 16 levels (%d instances in levels)"):format(parts))

-- Reward cosmetics on a (fake) character
do
	local Cosmetics = require("./Cosmetics")
	local Instance, Vector3, CFrame = env.Instance, env.Vector3, env.CFrame
	local character = Instance.new("Model")
	local torso = Instance.new("Part")
	torso.Name = "UpperTorso"
	torso.Size = Vector3.new(2, 1.6, 1)
	torso.CFrame = CFrame.new(0, 5, 0)
	torso.Parent = character
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(1.2, 1.2, 1.2)
	head.CFrame = CFrame.new(0, 6.5, 0)
	head.Parent = character
	for _, look in { "Angel", "Silver", "Bronze", "Fairy" } do
		Cosmetics.apply(character, look, look == "Angel", true)
		local wings = character:FindFirstChild("CT_Wings")
		assert(wings, look .. " wings attached")
		local flapWelds = 0
		for _, d in wings:GetDescendants() do
			if d.ClassName == "Weld" and d.Name == "FlapWeld" then
				flapWelds += 1
				assert(d:GetAttribute("BaseC0") ~= nil, "flap weld remembers its base position")
			end
		end
		assert(flapWelds == 2, "two flapping wings")
		assert((character:FindFirstChild("CT_Halo") ~= nil) == (look == "Angel"), "halo only for the weekly champion")
		assert(character:FindFirstChild("CT_Crown"), "crown attached")
	end
	Cosmetics.clear(character)
	assert(not character:FindFirstChild("CT_Wings"), "cleared")
	print("reward cosmetics: wings x4 looks, halo and crown attach and clear correctly")
end

-- Every trail builds its own look on a (fake) character
do
	local TrailFx = require("./TrailFx")
	local Config = require("./Config")
	local Instance = env.Instance
	local character = Instance.new("Model")
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Parent = character
	local seen: { [string]: string } = {}
	for _, trail in Config.Trails do
		assert(TrailFx.Looks[trail.id], "trail " .. trail.id .. " has its own look")
		local ribbon = TrailFx.apply(character, trail.id)
		assert(ribbon and ribbon.Attachment0 and ribbon.Attachment1, trail.id .. " ribbon")
		assert(character:GetAttribute("TrailFx") == trail.id, trail.id .. " tells the client which effect to run")
		local emitters = 0
		local sig = {}
		for _, d in root:GetDescendants() do
			if d.ClassName == "ParticleEmitter" then
				emitters += 1
				assert(d:GetAttribute("MoveRate") ~= nil, "emitter has a running rate")
				table.insert(sig, d.Texture .. d.Parent.Name)
			end
		end
		assert(trail.id == "Basic" or emitters > 0, trail.id .. " has particles")
		table.sort(sig)
		local key = table.concat(sig, "|") .. tostring(ribbon.Lifetime) .. tostring(ribbon.WidthScale)
		assert(not seen[key], trail.id .. " looks the same as " .. tostring(seen[key]))
		seen[key] = trail.id
	end
	local chain = Instance.new("Attachment")
	chain.Name = "CT_Chain"
	chain.Parent = root
	TrailFx.clear(root)
	assert(#root:GetChildren() == 1 and root:FindFirstChild("CT_Chain"), "trail cleared, chain attachment kept")
	print(("trails: %d distinct looks build and clear correctly"):format(#Config.Trails))
end
