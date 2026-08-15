
local vape = shared.BVC
local loadstring = function(...)
	local res, err = loadstring(...)
	if err and vape then
		vape:CreateNotification('BVC', 'Failed to load : ' .. err, 30, 'alert')
	end
	return res
end
local isfile = isfile or function(file)
	local suc, res = pcall(function()
		return readfile(file)
	end)
	return suc and res ~= nil and res ~= '' 
end
local function downloadFile(path, func)
	if not isfile(path) then
		if shared.BVCDeveloper then
			error('Missing local BVC file: '..path)
		end

		local suc, res = pcall(function()
			return game:HttpGet('https://raw.githubusercontent.com/ezbrohack/bvc-v2/'.. readfile('bvc/profiles/commit.txt').. '/'.. select(1, path:gsub('bvc/', '')), true)
		end)
		if not suc or res == '404: Not Found' then
			error(res)
		end
		if path:find('.lua') then
			res = '--This watermark is used to delete the file if its cached, remove it to make the file persist after vape updates.\n'.. res
		end
		writefile(path, res)
	end
	return (func or readfile)(path)
end

vape.Place = 5938036553
if isfile('bvc/games/' .. vape.Place .. '.lua') then
	loadstring(readfile('bvc/games/' .. vape.Place .. '.lua'), tostring(vape.Place))()
else
	if not shared.BVCDeveloper then
		local suc, res = pcall(function()
			return game:HttpGet('https://raw.githubusercontent.com/ezbrohack/bvc-v2/'.. readfile('bvc/profiles/commit.txt').. '/games/'.. vape.Place.. '.lua', true)
		end)
		if suc and res ~= '404: Not Found' then
			loadstring(downloadFile('bvc/games/' .. vape.Place .. '.lua'), tostring(vape.Place))()
		end
	end
end
