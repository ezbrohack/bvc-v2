shared.BVCReload = true
local folder = shared.BVCFolder or 'bvc'
local chunk, loadError = loadstring(readfile(folder..'/os.luau'), folder..'/os.luau')
if type(chunk) ~= 'function' then
	error(loadError or 'BVC runtime rejected', 0)
end
return chunk(...)
