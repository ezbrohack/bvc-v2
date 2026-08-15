-- Versioned public fallback loader for the BVC runtime.
-- No credential is required: the build is free and open to anyone.
-- Keep this file small and limited to broadly supported executor primitives.

local function pause(seconds)
	if type(task) == 'table' and type(task.wait) == 'function' then
		pcall(task.wait, seconds)
	elseif type(wait) == 'function' then
		pcall(wait, seconds)
	end
end

local function cachedBootstrap()
	if type(readfile) ~= 'function' then
		return nil
	end
	local folder = type(shared) == 'table' and type(shared.BVCFolder) == 'string'
		and shared.BVCFolder or 'bvc'
	local ok, source = pcall(readfile, folder..'/init.lua')
	if not ok or type(source) ~= 'string' or source == '' then
		return nil
	end
	local chunk = loadstring(source, '@'..folder..'/init.lua')
	return type(chunk) == 'function' and chunk or nil
end

local function remoteBootstrap()
	local urls = {
		'https://raw.githubusercontent.com/ezbrohack/bvc-v2/main/init.lua',
		'https://cdn.jsdelivr.net/gh/ezbrohack/bvc-v2@main/init.lua',
	}
	for attempt = 1, 3 do
		for index = 1, #urls do
			local ok, source = pcall(game.HttpGet, game, urls[index], true)
			if ok and type(source) == 'string' and source ~= '' then
				local chunk = loadstring(source, '@bvc/public-init')
				if type(chunk) == 'function' then
					return chunk
				end
			end
		end
		if attempt < 3 then
			pause(0.25 * attempt)
		end
	end
	return nil
end

return function()
	local bootstrap = cachedBootstrap() or remoteBootstrap()
	if type(bootstrap) ~= 'function' then
		error('BVC loader download failed. Try another network.', 0)
	end
	return bootstrap(nil)
end
