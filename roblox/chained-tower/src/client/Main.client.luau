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

local Chains = require(script.Parent.Chains)
local UI = require(script.Parent.UI)

Chains.start()
UI.start()
