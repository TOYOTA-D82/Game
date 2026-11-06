-- The guide book: every tab has entries, both languages are filled in and
-- no number placeholder was left unformatted.
local Manual = require("./Manual")
local count = 0
for _, tab in Manual.Tabs do
	assert(tab.en ~= "" and tab.zh ~= "", tab.id .. " tab names")
	assert(#tab.entries >= 3, tab.id .. " has entries")
	for _, e in tab.entries do
		count += 1
		for _, lang in { e.en, e.zh } do
			assert(#lang == 2 and #lang[1] > 0 and #lang[2] > 0, tab.id .. ": title and text")
			assert(not string.find(lang[2], "%%[ds%.]"), "unformatted number in: " .. lang[2])
		end
	end
end
print(("manual: %d tabs, %d entries in English and Chinese"):format(#Manual.Tabs, count))
