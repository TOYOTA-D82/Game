-- Compiles every source file with the real Luau compiler (syntax check).
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")

local root = process.args[1]
local failed = 0
local count = 0
local function walk(dir: string)
	for _, name in fs.readDir(dir) do
		local path = dir .. "/" .. name
		if fs.isDir(path) then
			walk(path)
		elseif name:match("%.luau$") then
			count += 1
			local ok, err = pcall(luau.compile, fs.readFile(path))
			if not ok then
				failed += 1
				print("COMPILE ERROR " .. path .. ": " .. tostring(err))
			end
		end
	end
end
walk(root)
print(("compiled %d files, %d failed"):format(count, failed))
if failed > 0 then
	process.exit(1)
end
