--!strict
-- Client entry point.

local LocalizationService = game:GetService("LocalizationService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Strings = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Strings"))

-- Pick the UI language before any UI is built.
local locale = LocalizationService.RobloxLocaleId
pcall(function()
	locale = Players.LocalPlayer.LocaleId
end)
Strings.setLocale(locale)

local Ambience = require(script.Parent.Ambience)
local Chains = require(script.Parent.Chains)
local Effects = require(script.Parent.Effects)
local Trailer = require(script.Parent.Trailer)
local UI = require(script.Parent.UI)

Ambience.start()
Chains.start()
Effects.start()
Trailer.start()
UI.start()
