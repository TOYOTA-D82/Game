--!strict
-- All on-screen UI, built from code (no manual setup in Studio).

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Themes = require(Shared:WaitForChild("Themes"))
local Chains = require(script.Parent.Chains)

local player = Players.LocalPlayer
local net = ReplicatedStorage:WaitForChild("Net")
local toServer = net:WaitForChild("ToServer") :: RemoteEvent

local UI = {}

local T = Strings.get
local profile: { [string]: any } = {}

----------------------------------------------------------------------
-- Small helpers
----------------------------------------------------------------------
local FONT = Enum.Font.FredokaOne
local COLORS = {
	panel = Color3.fromRGB(30, 32, 48),
	card = Color3.fromRGB(48, 52, 76),
	text = Color3.fromRGB(255, 255, 255),
	sub = Color3.fromRGB(190, 195, 220),
	gold = Color3.fromRGB(255, 210, 70),
	green = Color3.fromRGB(70, 200, 110),
	blue = Color3.fromRGB(70, 150, 255),
	orange = Color3.fromRGB(255, 150, 40),
	purple = Color3.fromRGB(160, 90, 255),
	red = Color3.fromRGB(235, 70, 70),
	gray = Color3.fromRGB(110, 110, 130),
}

local function make(className: string, props: { [string]: any }, children: { Instance }?): any
	local inst = Instance.new(className :: any)
	for k, v in props do
		if k ~= "Parent" then
			(inst :: any)[k] = v
		end
	end
	for _, child in children or {} do
		child.Parent = inst
	end
	if props.Parent then
		inst.Parent = props.Parent
	end
	return inst
end

local function corner(radius: number?): UICorner
	return make("UICorner", { CornerRadius = UDim.new(0, radius or 12) })
end

local function stroke(color: Color3?, thickness: number?): UIStroke
	return make("UIStroke", {
		Color = color or Color3.new(0, 0, 0),
		Thickness = thickness or 2,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Transparency = 0.3,
	})
end

local function text(props: { [string]: any }): TextLabel
	local defaults = {
		BackgroundTransparency = 1,
		Font = FONT,
		TextColor3 = COLORS.text,
		TextScaled = true,
		TextStrokeTransparency = 0.6,
	}
	for k, v in props do
		defaults[k] = v
	end
	return make("TextLabel", defaults)
end

local function button(props: { [string]: any }, onClick: () -> ()): TextButton
	local defaults = {
		Font = FONT,
		TextColor3 = COLORS.text,
		TextScaled = true,
		AutoButtonColor = true,
		BackgroundColor3 = COLORS.blue,
	}
	for k, v in props do
		defaults[k] = v
	end
	local b = make("TextButton", defaults, { corner(10), stroke() })
	b.Activated:Connect(onClick)
	return b
end

local function robux(price: number): string
	return "R$ " .. tostring(price)
end

----------------------------------------------------------------------
-- Prices from Roblox (fallback: Config)
----------------------------------------------------------------------
local priceCache: { [string]: number } = {}
local iconCache: { [string]: string } = {} -- the image you uploaded on the Creator Dashboard
local onInfoLoaded: () -> () = function() end
local function priceOf(kind: string, key: string): number
	local cacheKey = kind .. key
	if priceCache[cacheKey] then
		return priceCache[cacheKey]
	end
	local entry = if kind == "pass" then Config.GamePasses[key] else Config.Products[key]
	priceCache[cacheKey] = entry.price
	if entry.id ~= 0 then
		task.spawn(function()
			local ok, info = pcall(function()
				return MarketplaceService:GetProductInfo(
					entry.id,
					if kind == "pass" then Enum.InfoType.GamePass else Enum.InfoType.Product
				)
			end)
			if ok and info then
				if info.PriceInRobux then
					priceCache[cacheKey] = info.PriceInRobux
				end
				if info.IconImageAssetId and info.IconImageAssetId ~= 0 then
					iconCache[cacheKey] = "rbxassetid://" .. tostring(info.IconImageAssetId)
				end
				onInfoLoaded()
			end
		end)
	end
	return entry.price
end

function UI.buy(kind: string, key: string)
	local entry = if kind == "pass" then Config.GamePasses[key] else Config.Products[key]
	if not entry then
		return
	end
	if entry.id == 0 then
		if RunService:IsStudio() then
			toServer:FireServer("studioBuy", { kind = kind, key = key })
		else
			UI.toast(T("comingSoon"))
		end
		return
	end
	if kind == "pass" then
		MarketplaceService:PromptGamePassPurchase(player, entry.id)
	else
		MarketplaceService:PromptProductPurchase(player, entry.id)
	end
end

----------------------------------------------------------------------
-- Root
----------------------------------------------------------------------
local gui = make("ScreenGui", {
	Name = "ChainedTowerUI",
	ResetOnSpawn = false,
	IgnoreGuiInset = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = player:WaitForChild("PlayerGui"),
})

-- Top bar: timer + section
local top = make("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 6),
	Size = UDim2.fromOffset(320, 62),
	BackgroundTransparency = 1,
	Parent = gui,
})
local placeLabel = text({ Size = UDim2.new(1, 0, 0, 30), Text = "", Parent = top })
local sectionLabel = text({
	Position = UDim2.fromOffset(0, 32),
	Size = UDim2.new(1, 0, 0, 26),
	Text = "",
	TextColor3 = COLORS.gold,
	Parent = top,
})

-- Coins (top-left, under the Roblox buttons)
local coinLabel = text({
	Position = UDim2.fromOffset(12, 50),
	Size = UDim2.fromOffset(200, 34),
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "🪙 0",
	TextColor3 = COLORS.gold,
	Parent = gui,
})

-- Toasts
local toastHolder = make("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 74),
	Size = UDim2.fromOffset(520, 200),
	BackgroundTransparency = 1,
	Parent = gui,
}, {
	make("UIListLayout", { HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 6) }),
})

function UI.toast(message: string, good: boolean?)
	local label = text({
		Size = UDim2.fromOffset(500, 36),
		BackgroundTransparency = 0.25,
		BackgroundColor3 = if good then Color3.fromRGB(30, 110, 60) else COLORS.panel,
		Text = message,
		TextStrokeTransparency = 1,
		Parent = toastHolder,
	})
	corner(10).Parent = label
	make("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), Parent = label })
	task.delay(3.2, function()
		TweenService:Create(label, TweenInfo.new(0.4), { TextTransparency = 1, BackgroundTransparency = 1 }):Play()
		task.wait(0.4)
		label:Destroy()
	end)
	while #toastHolder:GetChildren() > 5 do
		for _, c in toastHolder:GetChildren() do
			if c:IsA("TextLabel") then
				c:Destroy()
				break
			end
		end
	end
end

----------------------------------------------------------------------
-- Action buttons (bottom right): Unchain [Q], Smash [E], Skip
----------------------------------------------------------------------
local actions = make("Frame", {
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -12, 1, -110),
	Size = UDim2.fromOffset(110, 250),
	BackgroundTransparency = 1,
	Parent = gui,
}, {
	make("UIListLayout", { Padding = UDim.new(0, 8), VerticalAlignment = Enum.VerticalAlignment.Bottom }),
})

local function actionButton(order: number, icon: string, color: Color3, onClick: () -> ()): (TextButton, TextLabel)
	local b = button({
		LayoutOrder = order,
		Size = UDim2.fromOffset(110, 74),
		BackgroundColor3 = color,
		Text = "",
		Parent = actions,
	}, onClick)
	text({ Size = UDim2.new(1, 0, 0.55, 0), Text = icon, Parent = b })
	local sub = text({
		Position = UDim2.fromScale(0, 0.55),
		Size = UDim2.new(1, -8, 0.4, 0),
		Text = "",
		Parent = b,
	})
	sub.Position = UDim2.new(0, 4, 0.55, 0)
	return b, sub
end

local unchainButton, unchainSub = actionButton(1, "🔓", COLORS.purple, function()
	toServer:FireServer("useUnchain")
end)
local smashButton, smashSub = actionButton(2, "🔨", COLORS.orange, function()
	toServer:FireServer("useSmash")
end)
local skipButton, skipSub = actionButton(3, "⏭", COLORS.green, function()
	toServer:FireServer("useSkip")
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.Q and unchainButton.Visible then
		toServer:FireServer("useUnchain")
	elseif input.KeyCode == Enum.KeyCode.E and smashButton.Visible then
		toServer:FireServer("useSmash")
	end
end)

----------------------------------------------------------------------
-- Menu buttons (left side)
----------------------------------------------------------------------
local menu = make("Frame", {
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 12, 0.5, 0),
	Size = UDim2.fromOffset(96, 330),
	BackgroundTransparency = 1,
	Parent = gui,
}, {
	make("UIListLayout", { Padding = UDim.new(0, 8), VerticalAlignment = Enum.VerticalAlignment.Center }),
})

local panels: { [string]: Frame } = {}
local function openPanel(name: string?)
	for key, panel in panels do
		panel.Visible = key == name
	end
end

local function menuButton(order: number, label: string, color: Color3, onClick: () -> ()): TextButton
	return button({
		LayoutOrder = order,
		Size = UDim2.fromOffset(96, 56),
		BackgroundColor3 = color,
		Text = label,
		Parent = menu,
	}, onClick)
end

local shopButton = menuButton(1, "🛒 " .. T("shop"), COLORS.gold, function()
	openPanel(if panels.shop.Visible then nil else "shop")
end)
shopButton.TextColor3 = Color3.fromRGB(60, 40, 0)
menuButton(2, "✨ " .. T("trails"), COLORS.blue, function()
	openPanel(if panels.trails.Visible then nil else "trails")
end)
menuButton(3, "📅 " .. T("daily"), COLORS.green, function()
	openPanel(if panels.daily.Visible then nil else "daily")
end)
local leaveButton = menuButton(4, "🚪 " .. T("leave"), COLORS.gray, function()
	toServer:FireServer("leaveTeam")
end)

----------------------------------------------------------------------
-- Panels
----------------------------------------------------------------------
local function panel(name: string, title: string): ScrollingFrame
	local frame = make("Frame", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.new(0.9, 0, 0.72, 0),
		BackgroundColor3 = COLORS.panel,
		Visible = false,
		Parent = gui,
	}, {
		corner(16),
		stroke(Color3.new(1, 1, 1), 2),
		make("UISizeConstraint", { MaxSize = Vector2.new(640, 520) }),
	})
	text({ Position = UDim2.fromOffset(16, 8), Size = UDim2.new(1, -90, 0, 40), Text = title, TextXAlignment = Enum.TextXAlignment.Left, Parent = frame })
	button({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 10),
		Size = UDim2.fromOffset(40, 40),
		BackgroundColor3 = COLORS.red,
		Text = "✕",
		Parent = frame,
	}, function()
		openPanel(nil)
	end)
	local list = make("ScrollingFrame", {
		Position = UDim2.fromOffset(12, 56),
		Size = UDim2.new(1, -24, 1, -68),
		BackgroundTransparency = 1,
		ScrollBarThickness = 6,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = frame,
	}, {
		make("UIGridLayout", {
			CellSize = UDim2.new(0.5, -6, 0, 120),
			CellPadding = UDim2.fromOffset(8, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	panels[name] = frame
	return list
end

type Card = { frame: Frame, title: TextLabel, desc: TextLabel, action: TextButton, icon: ImageLabel }
local function card(parent: Instance, order: number, accent: Color3, onClick: () -> ()): Card
	local frame = make("Frame", { LayoutOrder = order, BackgroundColor3 = COLORS.card, Parent = parent }, { corner(12) })
	make("Frame", { Size = UDim2.new(0, 6, 1, 0), BackgroundColor3 = accent, BorderSizePixel = 0, Parent = frame }, { corner(3) })
	local title = text({ Position = UDim2.fromOffset(14, 6), Size = UDim2.new(1, -20, 0, 28), TextXAlignment = Enum.TextXAlignment.Left, Text = "", Parent = frame })
	local desc = text({
		Position = UDim2.fromOffset(14, 34),
		Size = UDim2.new(1, -20, 0, 40),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = COLORS.sub,
		TextWrapped = true,
		Font = Enum.Font.GothamMedium,
		TextStrokeTransparency = 1,
		Text = "",
		Parent = frame,
	})
	local action = button({
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -8, 1, -8),
		Size = UDim2.fromOffset(110, 34),
		BackgroundColor3 = COLORS.green,
		Text = "",
		Parent = frame,
	}, onClick)
	local icon = make("ImageLabel", {
		Position = UDim2.new(0, 14, 1, -46),
		Size = UDim2.fromOffset(40, 40),
		BackgroundTransparency = 1,
		Image = "",
		Parent = frame,
	}, { corner(8) })
	return { frame = frame, title = title, desc = desc, action = action, icon = icon }
end

-- Shop
local shopList = panel("shop", "🛒 " .. T("shop"))
local shopCards: { { card: Card, kind: string, key: string } } = {}
for i, entry in Config.ShopOrder do
	local isPass = entry.kind == "pass"
	local accent = if entry.key == "StarterPack" then COLORS.gold elseif isPass then COLORS.purple else COLORS.blue
	local c = card(shopList, i, accent, function()
		UI.buy(entry.kind, entry.key)
	end)
	local prefix = if isPass then "g_" else "p_"
	c.title.Text = T(prefix .. entry.key)
	c.desc.Text = T(prefix .. entry.key .. "_d")
	if entry.key == "Unchain5" or entry.key == "Unchain20" then
		c.title.Text ..= " " .. T("teamOnly")
	end
	table.insert(shopCards, { card = c, kind = entry.kind, key = entry.key })
end
-- trail passes at the end of the shop
for i, trail in Config.Trails do
	if trail.source == "pass" and trail.pass then
		local key = trail.pass :: string
		local c = card(shopList, 100 + i, trail.colors[2] or trail.colors[1], function()
			UI.buy("pass", key)
		end)
		c.title.Text = T("g_" .. key)
		c.desc.Text = T("g_" .. key .. "_d")
		table.insert(shopCards, { card = c, kind = "pass", key = key })
	end
end

-- Trails
local trailList = panel("trails", "✨ " .. T("trails"))
local trailCards: { { card: Card, trail: Config.Trail } } = {}
for i, trail in Config.Trails do
	local c = card(trailList, i, trail.colors[1], function()
		local owned = trail.source == "free"
			or (profile.trails and profile.trails[trail.id])
			or (trail.pass and profile.passes and profile.passes[trail.pass])
		if owned then
			toServer:FireServer("equipTrail", trail.id)
		elseif trail.source == "coins" then
			toServer:FireServer("buyTrail", trail.id)
		elseif trail.source == "pass" and trail.pass then
			UI.buy("pass", trail.pass)
		elseif trail.source == "starter" then
			UI.buy("product", "StarterPack")
		elseif trail.source == "event" then
			toServer:FireServer("claimEvent")
		end
	end)
	-- colour preview bar
	local preview = make("Frame", {
		Position = UDim2.new(0, 14, 1, -38),
		Size = UDim2.new(1, -140, 0, 20),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = c.frame,
	}, { corner(8) })
	local keypoints = {}
	for k, col in trail.colors do
		table.insert(keypoints, ColorSequenceKeypoint.new((k - 1) / math.max(1, #trail.colors - 1), col))
	end
	if #keypoints == 1 then
		table.insert(keypoints, ColorSequenceKeypoint.new(1, trail.colors[1]))
	end
	make("UIGradient", { Color = ColorSequence.new(keypoints), Parent = preview })
	c.title.Text = T("t_" .. trail.id)
	table.insert(trailCards, { card = c, trail = trail })
end

-- Daily
local dailyList = panel("daily", "📅 " .. T("daily"))
local dailyCards: { Card } = {}
for i = 1, Config.ChallengesPerDay + 1 do
	local c = card(dailyList, i, COLORS.green, function()
		if i == Config.ChallengesPerDay + 1 then
			toServer:FireServer("claimEvent")
		end
	end)
	dailyCards[i] = c
end

----------------------------------------------------------------------
-- Popups: offer skip / out of items
----------------------------------------------------------------------
local popup = make("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.6),
	Size = UDim2.fromOffset(380, 150),
	BackgroundColor3 = COLORS.panel,
	Visible = false,
	Parent = gui,
}, { corner(16), stroke(COLORS.gold, 3) })
local popupText = text({ Position = UDim2.fromOffset(16, 12), Size = UDim2.new(1, -32, 0, 70), TextWrapped = true, Text = "", Parent = popup })
local popupYes: () -> () = function() end
button({
	Position = UDim2.new(0, 16, 1, -54),
	Size = UDim2.new(0.5, -24, 0, 42),
	BackgroundColor3 = COLORS.green,
	Text = T("buy"),
	Name = "Yes",
	Parent = popup,
}, function()
	popup.Visible = false
	popupYes()
end)
button({
	Position = UDim2.new(0.5, 8, 1, -54),
	Size = UDim2.new(0.5, -24, 0, 42),
	BackgroundColor3 = COLORS.gray,
	Text = T("notNow"),
	Parent = popup,
}, function()
	popup.Visible = false
end)
local yesButton = popup:FindFirstChild("Yes") :: TextButton

local function showPopup(message: string, yesLabel: string, onYes: () -> ())
	popupText.Text = message
	yesButton.Text = yesLabel
	popupYes = onYes
	popup.Visible = true
	task.delay(8, function()
		if popupText.Text == message then
			popup.Visible = false
		end
	end)
end

----------------------------------------------------------------------
-- Rules card shown when a climb starts (different for solo and teams)
----------------------------------------------------------------------
local rulesCard = make("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(460, 260),
	BackgroundColor3 = COLORS.panel,
	Visible = false,
	Parent = gui,
}, { corner(16), stroke(COLORS.gold, 3), make("UISizeConstraint", { MaxSize = Vector2.new(460, 260) }) })
local rulesText = text({
	Position = UDim2.fromOffset(18, 12),
	Size = UDim2.new(1, -36, 1, -70),
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	TextWrapped = true,
	TextScaled = true,
	Font = Enum.Font.GothamBold,
	TextStrokeTransparency = 1,
	Text = "",
	Parent = rulesCard,
})
button({
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -12),
	Size = UDim2.fromOffset(160, 42),
	BackgroundColor3 = COLORS.green,
	Text = T("gotIt"),
	Parent = rulesCard,
}, function()
	rulesCard.Visible = false
end)

local function showRules(mode: string, levelId: string?)
	local solo = mode == "solo"
	local theme = if levelId then Themes.ById[levelId] else nil
	local header = if theme then "🏁 " .. T("levelLine", theme.level, T("lv_" .. theme.id)) .. "\n" else ""
	rulesText.Text = header .. T(if solo then "rules_solo" else "rules_team")
	rulesCard.BackgroundColor3 = if solo then Color3.fromRGB(25, 45, 70) else Color3.fromRGB(55, 30, 70)
	rulesCard.Visible = true
	local shownAt = os.clock()
	task.delay(7, function()
		if os.clock() - shownAt >= 6.9 then
			rulesCard.Visible = false
		end
	end)
end

----------------------------------------------------------------------
-- Finish banner
----------------------------------------------------------------------
local banner = text({
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.35),
	Size = UDim2.fromOffset(600, 90),
	Text = "",
	TextColor3 = COLORS.gold,
	TextStrokeTransparency = 0,
	Visible = false,
	Parent = gui,
})

----------------------------------------------------------------------
-- Lobby pad labels
----------------------------------------------------------------------
local padRefreshers: { () -> () } = {}

local function billboard(part: BasePart, height: number): BillboardGui
	return make("BillboardGui", {
		Size = UDim2.fromOffset(250, 130),
		StudsOffset = Vector3.new(0, height, 0),
		AlwaysOnTop = false,
		MaxDistance = 140,
		Adornee = part,
		ResetOnSpawn = false,
		Parent = player:WaitForChild("PlayerGui"),
	})
end

-- Portals in the lobby / hubs
local function labelPortal(part: BasePart)
	local target = tostring(part:GetAttribute("Target"))
	local bb = billboard(part, 15)
	text({ Size = UDim2.new(1, 0, 0.55, 0), Text = T("portal_" .. target), TextStrokeTransparency = 0.2, Parent = bb })
	text({
		Position = UDim2.fromScale(0, 0.55),
		Size = UDim2.new(1, 0, 0.3, 0),
		Text = T("portalSub_" .. target),
		TextColor3 = COLORS.sub,
		TextStrokeTransparency = 0.2,
		Parent = bb,
	})
end

-- Level gates in the world hubs
local function labelPad(pad: BasePart)
	local mode = tostring(pad:GetAttribute("Mode"))
	local world = tostring(pad:GetAttribute("World"))
	local level = pad:GetAttribute("Level") :: number
	local themeId = tostring(pad:GetAttribute("Theme"))
	local bb = billboard(pad, 9)
	text({ Size = UDim2.new(1, 0, 0.3, 0), Text = T("gateTitle", level, T("lv_" .. themeId)), TextStrokeTransparency = 0.2, Parent = bb })
	local modeKey = if mode == "solo" then "soloGate" elseif mode == "duo" then "duoPad" else "squadPad"
	text({
		Position = UDim2.fromScale(0, 0.3),
		Size = UDim2.new(1, 0, 0.22, 0),
		Text = T(modeKey) .. "  " .. T("padRule_" .. mode),
		TextColor3 = COLORS.sub,
		TextStrokeTransparency = 0.2,
		Parent = bb,
	})
	local status = text({ Position = UDim2.fromScale(0, 0.55), Size = UDim2.new(1, 0, 0.3, 0), Text = "", TextColor3 = COLORS.gold, TextStrokeTransparency = 0.2, Parent = bb })
	local function refreshPad()
		local unlockedTo = (if world == "solo" then profile.soloLevel else profile.teamLevel) or 1
		local countdown = pad:GetAttribute("Countdown") :: number? or -1
		if level > unlockedTo then
			status.Text = T("lockedShort")
			status.TextColor3 = COLORS.gray
		elseif mode ~= "solo" and (countdown :: number) >= 0 then
			status.Text = T("padStarting", countdown)
			status.TextColor3 = COLORS.gold
		elseif mode ~= "solo" then
			status.Text = T("padWaiting", pad:GetAttribute("Count") or 0, pad:GetAttribute("Max") or 0)
			status.TextColor3 = COLORS.gold
		else
			status.Text = if profile.cleared and profile.cleared[themeId] then T("clearedShort") else "▶"
			status.TextColor3 = COLORS.gold
		end
	end
	pad:GetAttributeChangedSignal("Count"):Connect(refreshPad)
	pad:GetAttributeChangedSignal("Countdown"):Connect(refreshPad)
	table.insert(padRefreshers, refreshPad)
	refreshPad()
end

----------------------------------------------------------------------
-- Refresh everything from the latest profile
----------------------------------------------------------------------
local function refresh()
	local p = profile
	coinLabel.Text = "🪙 " .. tostring(p.coins or 0)

	unchainSub.Text = T("unchain") .. " ×" .. tostring(p.unchain or 0)
	smashSub.Text = T("smash") .. " ×" .. tostring(p.smash or 0)
	skipSub.Text = if (p.skip or 0) > 0 then T("skip") .. " ×" .. tostring(p.skip) else robux(priceOf("product", "Skip"))

	for _, entry in shopCards do
		local c = entry.card
		c.icon.Image = iconCache[entry.kind .. entry.key] or ""
		if entry.kind == "pass" then
			local owned = p.passes and p.passes[entry.key]
			c.action.Text = if owned then T("owned") else robux(priceOf("pass", entry.key))
			c.action.BackgroundColor3 = if owned then COLORS.gray else COLORS.green
			c.action.Active = not owned
		elseif entry.key == "StarterPack" then
			c.frame.Visible = not p.starterBought
			c.action.Text = robux(priceOf("product", entry.key))
		else
			c.action.Text = robux(priceOf("product", entry.key))
		end
	end

	for _, entry in trailCards do
		local trail, c = entry.trail, entry.card
		local owned = trail.source == "free"
			or (p.trails and p.trails[trail.id])
			or (trail.pass and p.passes and p.passes[trail.pass])
		local action, color, desc
		if p.equipped == trail.id then
			action, color = T("equipped"), COLORS.gray
		elseif owned then
			action, color = T("equip"), COLORS.blue
		elseif trail.source == "coins" then
			action, color = "🪙 " .. tostring(trail.price), if (p.coins or 0) >= (trail.price or 0) then COLORS.green else COLORS.gray
		elseif trail.source == "pass" and trail.pass then
			action, color = robux(priceOf("pass", trail.pass)), COLORS.green
		elseif trail.source == "starter" then
			action, color = T("p_StarterPack"), COLORS.gold
		else
			local active = p.event and p.event.trail == trail.id
			action, color = if active then T("claim") else "🔒", if active then COLORS.green else COLORS.gray
		end
		desc = ""
		c.desc.Text = desc
		c.action.Text = action
		c.action.BackgroundColor3 = color
	end

	local challenges = p.challenges or {}
	for i = 1, Config.ChallengesPerDay do
		local c = dailyCards[i]
		local ch = challenges[i]
		c.frame.Visible = ch ~= nil
		if ch then
			c.title.Text = T("c_" .. ch.stat, ch.goal)
			c.desc.Text = ("%d / %d   +🪙%d"):format(ch.progress, ch.goal, ch.reward)
			c.action.Text = if ch.claimed then "✅ " .. T("claimed") else ("%d%%"):format(math.floor(ch.progress / ch.goal * 100))
			c.action.BackgroundColor3 = if ch.claimed then COLORS.green else COLORS.gray
		end
	end
	local eventCard = dailyCards[Config.ChallengesPerDay + 1]
	eventCard.frame.Visible = p.event ~= nil
	if p.event then
		eventCard.title.Text = "🎉 " .. T("e_" .. p.event.id)
		eventCard.desc.Text = T("eventOn", T("e_" .. p.event.id), T("t_" .. p.event.trail))
		eventCard.action.Text = if p.event.owned then T("owned") else T("claim")
		eventCard.action.BackgroundColor3 = if p.event.owned then COLORS.gray else COLORS.gold
	end
	local free = ("%s: %d · %s: %d"):format(T("unchain"), p.freeUnchain or 0, T("smash"), p.freeSmash or 0)
	panels.daily:FindFirstChildOfClass("TextLabel").Text = "📅 " .. T("daily") .. "   (" .. T("free") .. " — " .. free .. ")"
end

onInfoLoaded = function()
	task.defer(refresh)
end

local function tick()
	local team = Chains.myTeam()
	local inTower = team ~= nil
	local total = (team and team:GetAttribute("Sections")) or 6
	local section = player:GetAttribute("Section")
	local mode = team and team:GetAttribute("Mode")
	local levelId = team and team:GetAttribute("Level")
	local theme = if type(levelId) == "string" then Themes.ById[levelId] else nil
	if theme then
		placeLabel.Text = T("levelLine", theme.level, T("lv_" .. theme.id))
	else
		local zone = player:GetAttribute("Zone")
		placeLabel.Text = T("world_" .. (if type(zone) == "string" then zone else "main"))
	end
	sectionLabel.Text = if inTower and type(section) == "number"
		then ("[%s]  %s"):format(T("mode_" .. tostring(mode)), T("section", section, total))
		else ""

	unchainButton.Visible = inTower and mode ~= "solo"
	smashButton.Visible = inTower
	skipButton.Visible = inTower and type(section) == "number" and section + 1 < (total :: number)
	leaveButton.Visible = inTower

	if team then
		local untilTime = team:GetAttribute("UnchainUntil")
		if type(untilTime) == "number" and untilTime > Workspace:GetServerTimeNow() then
			unchainSub.Text = ("🔓 %ds"):format(math.ceil(untilTime - Workspace:GetServerTimeNow()))
		elseif unchainSub.Text:sub(1, 4) == "🔓" then
			refresh()
		end
	end
end

----------------------------------------------------------------------
-- Messages from the server
----------------------------------------------------------------------
local function translateArgs(args: { any }?): { any }
	local out = {}
	for i, a in args or {} do
		if type(a) == "string" and (a:sub(1, 2) == "p_" or a:sub(1, 2) == "g_") then
			out[i] = T(a)
		else
			out[i] = a
		end
	end
	return out
end

local function onMessage(kind: string, payload: any)
	if kind == "profile" then
		profile = payload
		refresh()
		for _, r in padRefreshers do
			r()
		end
	elseif kind == "toast" then
		UI.toast(T(payload.key, table.unpack(translateArgs(payload.args))), payload.good)
	elseif kind == "modeIntro" then
		showRules(payload.mode, payload.level)
	elseif kind == "offerSkip" then
		local hasSkip = (profile.skip or 0) > 0
		showPopup(T("offerSkip"), if hasSkip then T("skip") else robux(priceOf("product", "Skip")), function()
			toServer:FireServer("useSkip")
		end)
	elseif kind == "promptProduct" then
		UI.buy("product", payload.key)
	elseif kind == "noItems" then
		local isUnchain = payload.item == "unchain"
		local key = if isUnchain then "Unchain5" else "Smash3"
		if not profile.starterBought then
			key = "StarterPack"
		end
		showPopup(T("noItems", T(if isUnchain then "unchain" else "smash")) .. "\n" .. T("p_" .. key), robux(priceOf("product", key)), function()
			UI.buy("product", key)
		end)
	elseif kind == "finish" then
		if payload.unlocked then
			UI.toast(T("levelUnlocked", T("lv_" .. payload.unlocked)), true)
		end
		banner.Text = T("youFinished", payload.coins or 0)
		banner.Visible = true
		task.delay(4, function()
			banner.Visible = false
		end)
	end
end

function UI.start()
	local toClient = net:WaitForChild("ToClient") :: RemoteEvent
	toClient.OnClientEvent:Connect(onMessage)
	Chains.Hint:Connect(function(key: string)
		UI.toast(T(key))
	end)

	local lobby = Workspace:WaitForChild("Lobby", 30)
	if lobby then
		for _, child in lobby:GetDescendants() do
			if child:IsA("BasePart") then
				local kind = child:GetAttribute("Kind")
				if kind == "Pad" then
					labelPad(child)
				elseif kind == "Portal" then
					labelPortal(child)
				end
			end
		end
	end

	refresh()
	task.spawn(function()
		while true do
			tick()
			task.wait(0.25)
		end
	end)
end

return UI
