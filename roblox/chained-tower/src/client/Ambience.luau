--!strict
-- Changes the sky, light, fog colour and gravity on YOUR screen to match where
-- you are (lobby, a world hub, or a level), so every level feels like its own
-- world. Only affects the local player.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Themes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Themes"))

local Ambience = {}

local player = Players.LocalPlayer
local DEFAULT_GRAVITY = 196.2

local function atmosphere(): Atmosphere
	local a = Lighting:FindFirstChildOfClass("Atmosphere")
	if not a then
		a = Instance.new("Atmosphere")
		a.Parent = Lighting
	end
	return a :: Atmosphere
end

local function apply(key: string)
	local sky: Themes.Sky
	local gravity = DEFAULT_GRAVITY
	local theme = Themes.ById[key]
	if theme then
		sky = theme.sky
		gravity = theme.gravity or DEFAULT_GRAVITY
	else
		sky = Themes.HubSky[key] or Themes.HubSky.main
	end
	local info = TweenInfo.new(1.2, Enum.EasingStyle.Sine)
	TweenService:Create(Lighting, info, {
		ClockTime = sky.clock,
		Brightness = sky.brightness,
		OutdoorAmbient = sky.ambient,
	}):Play()
	TweenService:Create(atmosphere(), info, {
		Color = sky.atmosphere,
		Decay = sky.atmosphere:Lerp(Color3.new(0, 0, 0), 0.4),
		Density = sky.density,
		Haze = sky.haze,
	}):Play()
	Workspace.Gravity = gravity
end

function Ambience.start()
	local function update()
		local key = player:GetAttribute("Theme")
		apply(if type(key) == "string" then key else "main")
	end
	player:GetAttributeChangedSignal("Theme"):Connect(update)
	update()
end

return Ambience
