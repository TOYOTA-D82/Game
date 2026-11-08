--!strict
-- Makes every place feel like its own world, on YOUR screen only:
--   * only the area you're in is shown (lobby, a world island, or one level);
--     everything else is tucked away so you never see other levels
--   * a short fade-to-black with a big title when you enter a new area
--   * the sky, light, fog colour and gravity change to match the area

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Strings = require(Shared:WaitForChild("Strings"))
local Themes = require(Shared:WaitForChild("Themes"))

local Ambience = {}

local player = Players.LocalPlayer
local DEFAULT_GRAVITY = 196.2
local T = Strings.get

----------------------------------------------------------------------
-- Sky / gravity
----------------------------------------------------------------------
local function atmosphere(): Atmosphere
	local a = Lighting:FindFirstChildOfClass("Atmosphere")
	if not a then
		a = Instance.new("Atmosphere")
		a.Parent = Lighting
	end
	return a :: Atmosphere
end

-- A level by id; the daily challenge looks like a different level each day.
local function themeOf(key: string): Themes.Theme?
	local day = Workspace:GetAttribute("ChallengeDay")
	return Themes.get(key, if type(day) == "number" then day else nil)
end

local function applySky(key: string, instant: boolean)
	local sky: Themes.Sky
	local gravity = DEFAULT_GRAVITY
	local theme = themeOf(key)
	if theme then
		sky = theme.sky
		gravity = theme.gravity or DEFAULT_GRAVITY
	else
		sky = Themes.HubSky[key] or Themes.HubSky.main
	end
	local info = TweenInfo.new(if instant then 0 else 1.2, Enum.EasingStyle.Sine)
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

----------------------------------------------------------------------
-- Show only the area you're in
----------------------------------------------------------------------
local stash = Instance.new("Folder")
stash.Name = "CT_HiddenAreas" -- things in ReplicatedStorage are not drawn
stash.Parent = ReplicatedStorage

type Area = { folder: Instance, home: Instance }
local areas: { [string]: Area } = {}
local activeKey = "main"

local function areaKeyFor(theme: string): string
	if Themes.ById[theme] or theme == "Challenge" then
		return "Level_" .. theme
	elseif theme == "solo" or theme == "team" or theme == "challenge" then
		return "Hub_" .. theme
	end
	return "Main"
end

-- Other modules (UI labels, moving platforms, foam) hook into each area here,
-- because hidden areas aren't under Workspace.
local listeners: { (folder: Instance) -> () } = {}
local known: { Instance } = {}

function Ambience.onArea(fn: (folder: Instance) -> ())
	table.insert(listeners, fn)
	for _, folder in known do
		task.spawn(fn, folder)
	end
end

local function register(folder: Instance, home: Instance)
	areas[folder.Name] = { folder = folder, home = home }
	table.insert(known, folder)
	for _, fn in listeners do
		task.spawn(fn, folder)
	end
	folder.Destroying:Connect(function()
		if areas[folder.Name] and areas[folder.Name].folder == folder then
			areas[folder.Name] = nil
		end
		local i = table.find(known, folder)
		if i then
			table.remove(known, i)
		end
	end)
	if folder.Name ~= activeKey then
		folder.Parent = stash
	end
end

local function showOnly(key: string)
	activeKey = key
	for name, area in areas do
		local want = if name == key then area.home else stash
		if area.folder.Parent ~= want then
			area.folder.Parent = want
		end
	end
end

-- Instantly show an area with its sky (used by the recording tour).
function Ambience.setArea(key: string)
	showOnly(areaKeyFor(key))
	applySky(key, true)
end

----------------------------------------------------------------------
-- Fade-to-black with a title
----------------------------------------------------------------------
local overlay = Instance.new("ScreenGui")
overlay.Name = "CT_Transition"
overlay.DisplayOrder = 50
overlay.IgnoreGuiInset = true
overlay.ResetOnSpawn = false
overlay.Parent = player:WaitForChild("PlayerGui")

local black = Instance.new("Frame")
black.Size = UDim2.fromScale(1, 1)
black.BackgroundColor3 = Color3.new(0, 0, 0)
black.BackgroundTransparency = 1
black.BorderSizePixel = 0
black.Parent = overlay

local title = Instance.new("TextLabel")
title.AnchorPoint = Vector2.new(0.5, 0.5)
title.Position = UDim2.fromScale(0.5, 0.45)
title.Size = UDim2.new(0.8, 0, 0, 80)
title.BackgroundTransparency = 1
title.Font = Enum.Font.FredokaOne
title.TextScaled = true
title.TextColor3 = Color3.fromRGB(255, 230, 120)
title.TextStrokeTransparency = 0.3
title.TextTransparency = 1
title.Text = ""
title.Parent = overlay

local subtitle = title:Clone()
subtitle.Position = UDim2.fromScale(0.5, 0.56)
subtitle.Size = UDim2.new(0.8, 0, 0, 40)
subtitle.TextColor3 = Color3.new(1, 1, 1)
subtitle.Parent = overlay

local function titleFor(key: string): (string, string)
	local theme = themeOf(key)
	if theme and theme.base then
		return "⚡ " .. T("lv_Challenge"), T("challengeLook", T("lv_" .. theme.base))
	elseif theme then
		return T("lv_" .. theme.id), T("levelLine", theme.level, T("worldShort_" .. theme.world)) .. " · " .. T("goal_" .. theme.id)
	end
	return T("world_" .. key), ""
end

local transitionId = 0
local function transition(key: string)
	transitionId += 1
	local myId = transitionId
	local fast = TweenInfo.new(0.25)
	TweenService:Create(black, fast, { BackgroundTransparency = 0 }):Play()
	task.wait(0.25)
	if myId ~= transitionId then
		return
	end
	showOnly(areaKeyFor(key))
	applySky(key, true)
	local main, sub = titleFor(key)
	title.Text = main
	subtitle.Text = sub
	TweenService:Create(title, fast, { TextTransparency = 0 }):Play()
	TweenService:Create(subtitle, fast, { TextTransparency = 0 }):Play()
	task.wait(0.9)
	if myId ~= transitionId then
		return
	end
	local slow = TweenInfo.new(0.5)
	TweenService:Create(black, slow, { BackgroundTransparency = 1 }):Play()
	TweenService:Create(title, slow, { TextTransparency = 1 }):Play()
	TweenService:Create(subtitle, slow, { TextTransparency = 1 }):Play()
end

function Ambience.start()
	-- collect the areas as they arrive from the server
	task.spawn(function()
		local lobby = Workspace:WaitForChild("Lobby", 60)
		if lobby then
			for _, child in lobby:GetChildren() do
				register(child, lobby)
			end
			lobby.ChildAdded:Connect(function(child)
				register(child, lobby)
			end)
		end
	end)
	task.spawn(function()
		local levels = Workspace:WaitForChild("Levels", 60)
		if levels then
			for _, child in levels:GetChildren() do
				register(child, levels)
			end
			levels.ChildAdded:Connect(function(child)
				task.defer(register, child, levels) -- daily rebuilds
			end)
		end
	end)

	local first = true
	local function update()
		local key = player:GetAttribute("Theme")
		local k = if type(key) == "string" then key else "main"
		if first then
			first = false
			activeKey = areaKeyFor(k)
			showOnly(activeKey)
			applySky(k, true)
		else
			task.spawn(transition, k)
		end
	end
	player:GetAttributeChangedSignal("Theme"):Connect(update)
	update()
end

return Ambience
