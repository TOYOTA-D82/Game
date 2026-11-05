-- Fake just enough of the Roblox globals for Lune (used by world.check.luau).
local roblox = require("@lune/roblox") :: any
local env = {}
env.roblox = roblox
env.game = roblox.Instance.new("DataModel")
local shared = roblox.Instance.new("Folder")
shared.Name = "Shared"
shared.Parent = env.game:GetService("ReplicatedStorage")
for _, name in { "Instance", "Vector3", "Vector2", "CFrame", "Color3", "UDim", "UDim2", "Enum", "ColorSequence",
	"ColorSequenceKeypoint", "NumberSequence", "NumberRange", "PhysicalProperties", "BrickColor" } do
	env[name] = roblox[name]
end
-- Random stand-in
env.Random = {
	new = function(seed: number?)
		local state = math.floor(seed or 1) % 2147483647
		if state <= 0 then
			state += 2147483646
		end
		local function nextFloat()
			state = (state * 48271) % 2147483647
			return state / 2147483647
		end
		return {
			NextInteger = function(_, a, b)
				return a + math.floor(nextFloat() * (b - a + 1))
			end,
			NextNumber = function(_, a, b)
				a = a or 0
				b = b or 1
				return a + nextFloat() * (b - a)
			end,
		}
	end,
}
return env
