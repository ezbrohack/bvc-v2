local license = ...
local shimPath = 'bvc/games/6872274481.lua'
local diagnostics = shared and shared.BVCDiagnostics or nil
local function note(event, fields)
	if diagnostics and type(diagnostics.record) == 'function' then
		pcall(diagnostics.record, diagnostics, event, fields or {})
	end
end

local vape = shared and shared.BVC
if type(vape) ~= 'table' then
	note('game_shim_guard', {
		error = 'shared-bvc-missing',
		path = shimPath,
	})
	return false
end

vape.Place = 6872274481
local source

local cachedOk, cached = pcall(readfile, shimPath)
if cachedOk and type(cached) == 'string' and cached ~= '' then
	source = cached
end

if not source and shared and type(shared.BVCDownloadFile) == 'function' then
	local downloadOk, downloaded = pcall(shared.BVCDownloadFile, shimPath)
	if downloadOk and type(downloaded) == 'string' and downloaded ~= '' then
		source = downloaded
	end
end

if type(source) ~= 'string' or source == '404: Not Found' or type(loadstring) ~= 'function' then
	note('game_shim_guard', {
		error = 'source-unavailable',
		path = shimPath,
		sourceType = type(source),
		loadstringType = type(loadstring),
	})
	return false
end

local compileOk, chunk = pcall(loadstring, source, tostring(vape.Place))
if not compileOk or type(chunk) ~= 'function' then
	note('game_shim_guard', {
		error = 'compile-failed',
		detail = tostring(chunk),
		path = shimPath,
	})
	return false
end

local runOk, result = pcall(chunk, license)
if not runOk or result == false then
	note('game_shim_guard', {
		error = not runOk and 'runtime-failed' or 'module-returned-false',
		detail = not runOk and tostring(result) or 'none',
		path = shimPath,
	})
	return false
end

return result
