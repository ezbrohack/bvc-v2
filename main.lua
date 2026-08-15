local forwardedLicense = ...
local function resolveRuntimeEnvironment()
	if type(getgenv) == 'function' then
		local ok, environment = pcall(getgenv)
		if ok and type(environment) == 'table' then
			return environment
		end
	end
	if type(getfenv) == 'function' then
		local ok, environment = pcall(getfenv, 0)
		if ok and type(environment) == 'table' then
			return environment
		end
	end
	if type(_G) == 'table' then
		return _G
	end
	return {}
end
local runtimeEnvironment = resolveRuntimeEnvironment()
local restoreRuntimeEnvironment = type(shared.BVCRestoreRuntimeEnvironment) == 'function'
	and shared.BVCRestoreRuntimeEnvironment or function() end
local license = {}
if type(forwardedLicense) == 'table' then
	for key, value in forwardedLicense do
		license[key] = value
	end
end
license.Key = type(license.Key) == 'string' and license.Key or nil
local diagnostics = type(shared.BVCDiagnostics) == 'table' and shared.BVCDiagnostics or nil
local diagnosticsPath = diagnostics and diagnostics.path
	or (shared.BVCFolder or 'bvc')..'/bvc-debug.txt'
local function recordDiagnostic(event, fields)
	if diagnostics and type(diagnostics.record) == 'function' then
		pcall(diagnostics.record, event, fields)
	end
end
recordDiagnostic('main_start', {
	credentialKind = license.Key and (license.Key:match('^BV%-%u%-') and 'license' or 'uid') or 'free',
	placeId = game.PlaceId,
})
local floodCraftPlaces = {
	[6872265039] = true,
	[6872274481] = true,
	[8444591321] = true,
	[8560631822] = true,
}
local function floodCraftClientReady()
	local placeId = tonumber(game.PlaceId)
	if not floodCraftPlaces[placeId] then
		return true
	end
	local workspaceService = game:GetService('Workspace')
	local marker = workspaceService:FindFirstChild('ClientFlameReady')
	return marker ~= nil
		and (type(marker.IsA) ~= 'function' or marker:IsA('BoolValue'))
		and marker.Value == true
end
local readyDeadline = tick() + 45
local runtimeReady = false
local runtimeReadyState = {}
while tick() < readyDeadline do
	local ready = false
	runtimeReadyState.gameLoaded = false
	runtimeReadyState.playerGui = false
	runtimeReadyState.playerScripts = false
	runtimeReadyState.clientFlameReady = false
	pcall(function()
		local players = game:GetService('Players')
		local localPlayer = players.LocalPlayer
		runtimeReadyState.gameLoaded = game:IsLoaded()
		runtimeReadyState.playerGui = localPlayer ~= nil
			and localPlayer:FindFirstChild('PlayerGui') ~= nil
		runtimeReadyState.playerScripts = localPlayer ~= nil
			and localPlayer:FindFirstChild('PlayerScripts') ~= nil
		runtimeReadyState.clientFlameReady = floodCraftClientReady()
		ready = runtimeReadyState.gameLoaded
			and runtimeReadyState.playerGui
			and runtimeReadyState.playerScripts
			and runtimeReadyState.clientFlameReady
	end)
	if ready then
		runtimeReady = true
		break
	end
	task.wait()
end
if not runtimeReady then
	recordDiagnostic('runtime_ready_timeout', runtimeReadyState)
	error('BVC destination place did not finish loading', 0)
end
recordDiagnostic('runtime_ready', runtimeReadyState)
-- A loader sets this marker before starting a replacement runtime.  Capture it
-- before tearing down the previous GUI: the old runtime's Uninject method is
-- allowed to clear its own globals, but it must not make the replacement look
-- like a normal first load.
local reloadRequested = shared.BVCReload == true
local staleVape = shared.BVC
if type(staleVape) == 'table' and type(staleVape.Uninject) == 'function' then
	pcall(staleVape.Uninject, staleVape)
end
if shared.BVC == staleVape then
	shared.BVC = nil
end
if _G.BVC == staleVape then
	_G.BVC = nil
end
if reloadRequested then
	-- Restore the handoff marker after stale teardown.  This is deliberately
	-- done even when the old Uninject failed part-way through cleanup.
	shared.BVCReload = true
end

local vape
local nativeLoadstring = loadstring
local loadstring = function(source, chunkName)
	local res, err = nativeLoadstring(source, chunkName)
	if err and vape then
		vape:CreateNotification('BVC', 'Failed to compile '..tostring(chunkName)..' : '..tostring(err), 30, 'alert')
	end
	return res, err
end
local function runSource(source, chunkName, ...)
	if type(source) ~= 'string' or source == '' then
		local detail = tostring(chunkName)..' source unavailable'
		recordDiagnostic('source_unavailable', {chunk = chunkName})
		return false, detail
	end
	recordDiagnostic('source_compile_start', {bytes = #source, chunk = chunkName})
	local chunk, compileError = loadstring(source, chunkName)
	if type(chunk) ~= 'function' then
		local detail = tostring(chunkName)..' compile failed: '..tostring(compileError or 'rejected')
		recordDiagnostic('source_compile_failed', {chunk = chunkName, error = compileError or 'rejected'})
		return false, detail
	end
	recordDiagnostic('source_compile_complete', {chunk = chunkName})
	local arguments = table.pack(...)
	local function traceError(value)
		if type(debug) == 'table' and type(debug.traceback) == 'function' then
			local traceOk, trace = pcall(debug.traceback, tostring(value), 2)
			if traceOk and type(trace) == 'string' then return trace end
		end
		return tostring(value)
	end
	recordDiagnostic('source_execution_start', {chunk = chunkName})
	local result = table.pack(xpcall(function()
		return chunk(table.unpack(arguments, 1, arguments.n))
	end, traceError))
	if not result[1] then
		local detail = tostring(chunkName)..' runtime failed: '..tostring(result[2])
		recordDiagnostic('source_runtime_failed', {chunk = chunkName, error = result[2]})
		return false, detail
	end
	local protectedFailure = type(shared.BVCProtectedFailure) == 'table'
		and shared.BVCProtectedFailure or nil
	recordDiagnostic('source_execution_complete', {
		chunk = chunkName,
		protectedCorrelation = protectedFailure and protectedFailure.correlationId or 'none',
		protectedDetail = protectedFailure and protectedFailure.detail or 'none',
		protectedStage = protectedFailure and protectedFailure.stage or 'none',
		resultFalse = result[2] == false,
		resultType = typeof(result[2]),
	})
	return true, result[2]
end

local function addTeleportQueueCandidate(list, seen, candidate)
	if type(candidate) == 'function' and not seen[candidate] then
		seen[candidate] = true
		table.insert(list, candidate)
	end
end
local function teleportQueueCandidates()
	local list, seen = {}, {}
	local environmentSyn = type(runtimeEnvironment.syn) == 'table' and runtimeEnvironment.syn or nil
	local environmentFluxus = type(runtimeEnvironment.fluxus) == 'table' and runtimeEnvironment.fluxus or nil
	addTeleportQueueCandidate(list, seen, runtimeEnvironment.queue_on_teleport)
	addTeleportQueueCandidate(list, seen, runtimeEnvironment.queueonteleport)
	addTeleportQueueCandidate(list, seen, environmentSyn and environmentSyn.queue_on_teleport)
	addTeleportQueueCandidate(list, seen, environmentSyn and environmentSyn.queueonteleport)
	addTeleportQueueCandidate(list, seen, environmentFluxus and environmentFluxus.queue_on_teleport)
	addTeleportQueueCandidate(list, seen, environmentFluxus and environmentFluxus.queueonteleport)
	addTeleportQueueCandidate(list, seen, queue_on_teleport)
	addTeleportQueueCandidate(list, seen, queueonteleport)
	addTeleportQueueCandidate(list, seen, type(syn) == 'table' and syn.queue_on_teleport)
	addTeleportQueueCandidate(list, seen, type(syn) == 'table' and syn.queueonteleport)
	addTeleportQueueCandidate(list, seen, type(fluxus) == 'table' and fluxus.queue_on_teleport)
	addTeleportQueueCandidate(list, seen, type(fluxus) == 'table' and fluxus.queueonteleport)
	return list
end
local teleportQueueParts = {}
local teleportQueueFlushed = false
shared.BVCTeleportQueueParts = teleportQueueParts
local function flushTeleportQueue()
	if teleportQueueFlushed then
		recordDiagnostic('teleport_queue_flush_skipped', {reason = 'already-flushed'})
		return true
	end
	local names = {}
	for name in teleportQueueParts do table.insert(names, name) end
	table.sort(names)
	local scripts = {}
	for _, name in names do table.insert(scripts, teleportQueueParts[name]) end
	if #scripts == 0 then
		recordDiagnostic('teleport_queue_flush_failed', {reason = 'no-parts'})
		return false
	end
	recordDiagnostic('teleport_queue_flush_start', {
		candidates = #teleportQueueCandidates(),
		parts = #scripts,
	})
	local source = table.concat(scripts, '\n')
	local candidates = teleportQueueCandidates()
	for index, queueTeleport in candidates do
		local ok, result = pcall(queueTeleport, source)
		if ok and result ~= false then
			teleportQueueFlushed = true
			recordDiagnostic('teleport_queue_flush_complete', {
				adapter = index,
				parts = #scripts,
			})
			return true
		end
	end
	recordDiagnostic('teleport_queue_flush_failed', {
		candidates = #candidates,
		parts = #scripts,
		reason = 'all-adapters-rejected',
	})
	return false
end
shared.BVCQueueTeleport = function(name, source)
	if type(name) ~= 'string' or name == '' or type(source) ~= 'string' or source == '' then return false end
	if teleportQueueFlushed then return false end
	teleportQueueParts[name] = source
	recordDiagnostic('teleport_queue_part_registered', {
		name = name,
		parts = #teleportQueueParts,
	})
	return true
end
shared.BVCFlushTeleportQueue = flushTeleportQueue
local isfile = isfile or function(file)
	local suc, res = pcall(function()
		return readfile(file)
	end)
	return suc and res ~= nil and res ~= ''
end
local cloneref = cloneref or function(obj)
	return obj
end
local playersService = cloneref(game:GetService('Players'))
local httpService = cloneref(game:GetService('HttpService'))
local runtimeFolder = shared.BVCFolder or 'bvc'

local redirect = function() end

local function readCachedFile(path)
	local ok, value = pcall(readfile, path)
	return ok and type(value) == 'string' and value ~= '' and value or nil
end

local function installedReleaseRef()
	local value = readCachedFile(runtimeFolder..'/cache/public-release-ref.txt')
	return value and #value == 40 and value:match('^[0-9a-f]+$') and value or 'main'
end

local function downloadFile(path, func)
	local contents = readCachedFile(path)
	if contents then
		recordDiagnostic('runtime_file_cache_hit', {bytes = #contents, path = path})
	end
	if not contents then
		recordDiagnostic('runtime_file_cache_miss', {path = path})
		if shared.BVCDeveloper then
			recordDiagnostic('runtime_file_missing_local', {path = path})
			error('Missing local BVC file: '..path)
		end

		local relative = path:gsub('^bvc/', '', 1)
		local releaseRef = installedReleaseRef()
		local urls = {
			'https://raw.githubusercontent.com/ezbrohack/bvc-v2/'..releaseRef..'/'..relative,
			'https://cdn.jsdelivr.net/gh/ezbrohack/bvc-v2@'..releaseRef..'/'..relative,
		}
		local lastError = 'download failed'
		for mirror, url in urls do
			local ok, response = pcall(function()
				return game:HttpGet(url)
			end)
			if ok and type(response) == 'string' and response ~= '' and response ~= '404: Not Found' then
				local wrote, writeError = pcall(writefile, path, response)
				if not wrote then
					recordDiagnostic('runtime_file_write_failed', {error = writeError, path = path})
					error(tostring(writeError), 0)
				end
				contents = response
				recordDiagnostic('runtime_file_downloaded', {
					bytes = #response,
					mirror = mirror,
					path = path,
					releaseRef = releaseRef,
				})
				break
			end
			lastError = response
			recordDiagnostic('runtime_file_download_failed', {
				error = response,
				mirror = mirror,
				path = path,
				releaseRef = releaseRef,
			})
		end
		if not contents then
			recordDiagnostic('runtime_file_unavailable', {error = lastError, path = path, releaseRef = releaseRef})
			error(tostring(lastError), 0)
		end
	end
	return func and func(path) or contents
end

local ownedDownloadFile
ownedDownloadFile = function(path)
	if type(path) ~= 'string'
		or not path:match('^bvc/[%w%._/%-]+$')
		or path:find('..', 1, true) then
		recordDiagnostic('runtime_file_path_rejected', {path = path})
		return nil
	end
	local ok, result = pcall(downloadFile, path)
	if not ok then
		recordDiagnostic('runtime_file_request_failed', {error = result, path = path})
	end
	return ok and result or nil
end
shared.BVCDownloadFile = ownedDownloadFile

local function loadBVCTheme()
	if not vape or not vape.Categories or not vape.Categories.Render then
		return
	end

	if vape.Modules and vape.Modules.Theme then
		return
	end

	local suc, res = pcall(function()
		local themeChunk = loadstring(downloadFile('bvc/libraries/bvc-theme.lua'), 'bvc-theme')
		if not themeChunk then
			return
		end

		local themeLoader = themeChunk()
		if type(themeLoader) == 'function' then
			return themeLoader(vape, vape.Libraries and vape.Libraries.entity)
		end
	end)

	if not suc then
		vape:CreateNotification('BVC', 'Theme failed to load : '..tostring(res), 10, 'alert')
	end
end

local function loadMaxPrediction()
	if not vape then
		return
	end

	vape.Libraries = vape.Libraries or {}
	shared.BVCPredictionMode = 'max-devirtualized'
	vape.Libraries.calculatePosition = function(selfPosition, rootPart)
		local targetPosition = rootPart and rootPart.Position
		if typeof(selfPosition) ~= 'Vector3' or typeof(targetPosition) ~= 'Vector3' then
			return Vector3.zero
		end
		return CFrame.lookAt(targetPosition, selfPosition).LookVector * math.max((selfPosition - targetPosition).Magnitude / 10, 0)
	end
end

local teleportReloadInstalled = false
local function installTeleportReload()
	if teleportReloadInstalled or shared.BVCIndependent then
		return teleportReloadInstalled
	end

	local installedRef = 'main'
	if type(readfile) == 'function' then
		local readOk, cachedRef = pcall(readfile, runtimeFolder..'/cache/public-release-ref.txt')
		if readOk and type(cachedRef) == 'string'
			and #cachedRef == 40 and cachedRef:match('^[0-9a-f]+$') then
			installedRef = cachedRef
		end
	end
	-- `main` is resolved by bootstrap/init; a cached SHA is forwarded so
	-- teleport reloads stay on the exact release that was already installed.
	local encodedReleaseRef = installedRef ~= 'main'
		and httpService:JSONEncode(installedRef)
		or 'nil'
	local encodedFolder = httpService:JSONEncode(runtimeFolder)
	local teleportScript
	if shared.BVCDeveloper then
		teleportScript = 'shared.BVCReload = true\n'
			..'shared.BVCDeveloper = true\n'
			..'shared.BVCFolder = '..encodedFolder..'\n'
			..'local bvcLoader, bvcLoadError = loadstring(readfile(shared.BVCFolder.."/loader.lua"), "@bvc/loader.lua")\n'
			..'if type(bvcLoader) ~= "function" then error(bvcLoadError or "BVC local loader rejected", 0) end\n'
			..'return bvcLoader()'
	else
		local loaderUrl = httpService:JSONEncode(
			'https://raw.githubusercontent.com/ezbrohack/bvc-v2/main/bootstrap.lua'
		)
		teleportScript = 'shared.BVCReload = true\n'
			..'shared.BVCFolder = '..encodedFolder..'\n'
			..'local u = '..loaderUrl..'\n'
			..'local s\n'
			..'pcall(function() s = game:HttpGet(u, true) end)\n'
			..'if type(s) ~= "string" or s == "" then\n'
			..'  local h = type(http) == "table" and http or nil\n'
			..'  local q = h and h.request or request\n'
			..'  local adapters, seen = {q, http_request}, {}\n'
			..'  for _, library in pairs({syn, fluxus, krnl}) do\n'
			..'    if type(library) == "table" then table.insert(adapters, library.request) end\n'
			..'  end\n'
			..'  for _, requestFunction in ipairs(adapters) do\n'
			..'    if type(requestFunction) == "function" and not seen[requestFunction] then\n'
			..'      seen[requestFunction] = true\n'
			..'      local ok, response = pcall(requestFunction, {Url = u, Method = "GET"})\n'
			..'      local responseType = ok and type(response) or nil\n'
			..'      local status = responseType == "string" and 200 or (responseType == "table" and tonumber(response.StatusCode or response.Status or response.status_code or response.status) or nil)\n'
			..'      local body = responseType == "string" and response or (responseType == "table" and (response.Body or response.body) or nil)\n'
			..'      if (status == nil or status == 0 or status == 200 or status == 201) and type(body) == "string" and body ~= "" and body ~= "404: Not Found" then s = body; break end\n'
			..'    end\n'
			..'  end\n'
			..'end\n'
			..'local b, e = loadstring(s, "@bvc/bootstrap")\n'
			..'if type(b) ~= "function" then error(e or "BVC bootstrap rejected", 0) end\n'
			..'return b('..encodedReleaseRef..')'
	end
	if shared.BVCCustomProfile then
		teleportScript = 'shared.BVCCustomProfile = '
			..httpService:JSONEncode(tostring(shared.BVCCustomProfile))..'\n'..teleportScript
	end

	if not shared.BVCQueueTeleport('99-loader', teleportScript) then
		recordDiagnostic('teleport_queue_registration_failed', {reason = 'queue-part-rejected'})
		return false
	end
	recordDiagnostic('teleport_queue_ready', {
		credentialKind = 'free',
		releaseRef = installedRef,
	})
	local queueAttempted = false
	local queueFlushScheduled = false
	local teleportFailed = false
	local teleportGeneration = 0
	local function teleportStateName(state)
		if type(state) == 'string' then
			return state:lower()
		end
		local ok, enumName = pcall(function()
			return state and state.Name
		end)
		if ok and type(enumName) == 'string' and enumName ~= '' then
			return enumName:lower()
		end
		return tostring(state or ''):lower()
	end
	local function rearmTeleportQueue(reason)
		teleportGeneration += 1
		teleportFailed = true
		queueAttempted = false
		queueFlushScheduled = false
		-- The executor may retain or discard a queued script after a failed
		-- request. Re-arm the broker so the next accepted teleport can replace
		-- it deterministically.
		teleportQueueFlushed = false
		recordDiagnostic('teleport_queue_rearmed', {reason = reason})
	end
	local function isTeleportFailure(state)
		local name = teleportStateName(state)
		return name:find('failed', 1, true) ~= nil
			or name:find('cancel', 1, true) ~= nil
	end
	local function isTeleportStart(state)
		local name = teleportStateName(state)
		-- RequestedFromClient/RequestedFromServer can be emitted for a request
		-- that is later rejected. Wait for an accepted transition state so a
		-- transient lobby request cannot consume the one-shot queue handoff.
		return name:find('started', 1, true) ~= nil
			or name:find('waitingforserver', 1, true) ~= nil
			or name:find('inprogress', 1, true) ~= nil
	end
	local connection = playersService.LocalPlayer.OnTeleport:Connect(function(teleportState)
		recordDiagnostic('teleport_state', {state = tostring(teleportState)})
		if isTeleportFailure(teleportState) then
			rearmTeleportQueue('teleport-failed')
			return
		end
		if not isTeleportStart(teleportState) or queueAttempted or queueFlushScheduled then return end
		teleportFailed = false
		teleportGeneration += 1
		local generation = teleportGeneration
		queueFlushScheduled = true
		task.defer(function()
			queueFlushScheduled = false
			if teleportFailed or generation ~= teleportGeneration or queueAttempted then return end
			queueAttempted = true
			if not shared.BVCFlushTeleportQueue() then
				queueAttempted = false
				vape:CreateNotification('BVC', 'Your executor could not queue the teleport reload.', 8, 'warning')
			else
				recordDiagnostic('teleport_started', {state = tostring(teleportState)})
			end
		end)
	end)
	vape:Clean(connection)
	local teleportService = cloneref(game:GetService('TeleportService'))
	if teleportService and teleportService.TeleportInitFailed then
		local failureConnection = teleportService.TeleportInitFailed:Connect(function(player)
			if player == playersService.LocalPlayer then
				rearmTeleportQueue('teleport-init-failed')
			end
		end)
		vape:Clean(failureConnection)
	end
	teleportReloadInstalled = true
	if #teleportQueueCandidates() == 0 then
		vape:CreateNotification('BVC', 'This executor does not support queue on teleport.', 8, 'warning')
	end
	return true
end

local function finishLoading()
	vape.Init = nil
	local loaded, loadError = pcall(vape.Load, vape)
	if not loaded then
		error('BVC GUI load failed: '..tostring(loadError), 0)
	end
	task.spawn(function()
		repeat
			pcall(vape.Save, vape)
			task.wait(10)
		until not vape.Loaded
	end)

	installTeleportReload()

	local suppressFinishedNotification = reloadRequested or shared.BVCReload == true
	if not suppressFinishedNotification then
		if not vape.Categories then return end
		if vape.Categories.Main.Options['GUI bind indicator'].Enabled then
			if vape.Place ~= 6872274481 then
				--task.spawn(redirect)
			end
			vape:CreateNotification('Finished Loading', (vape.VapeButton and 'Press the button in the top right' or 'Press '..table.concat(vape.Keybind, ' + '):upper())..' to open GUI', 5)
			task.delay(1, function()
				if shared.BVCUpdated then
					vape:CreateNotification('BVC', `Script has updated from {shared.BVCUpdated} to {readfile('bvc/profiles/commit.txt')}`, 10, 'info')
				end
			end)
		end
	end
	-- The marker is a one-load handoff, not permanent runtime state.  Consume it
	-- only after the replacement GUI has loaded so a failed startup can still be
	-- diagnosed/retried normally.
	if reloadRequested then
		if shared.BVCReload == true then
			shared.BVCReload = nil
		end
		reloadRequested = false
	end
end

-- Show a one-time choice for changed game profiles after the runtime is fully
-- loaded.  The installer stages release profiles separately, so this menu can
-- preserve the active profile and GUI/theme data when the user chooses Install.
local function showProfileUpdateMenu()
	local updateApi = shared.BVCProfileUpdate
	if type(updateApi) ~= 'table' or type(updateApi.Get) ~= 'function' then
		return
	end
	local state = updateApi.Get()
	if type(state) ~= 'table' or state.status ~= 'pending' or type(state.profiles) ~= 'table' or #state.profiles == 0 then
		return
	end
	if tonumber(state.placeId) ~= tonumber(vape and vape.Place) then
		return
	end
	if not vape or not vape.gui or not vape.Loaded then
		return
	end

	local staged = {}
	local function profileBase(item)
		if type(item) ~= 'table' or type(item.path) ~= 'string' then return nil end
		local base = item.path:match('^profiles/([%a_]+)%d+%.txt$')
		return (base == 'default' or base == 'blatant') and base or nil
	end
	for _, item in ipairs(state.profiles) do
		if not profileBase(item) then
			if type(updateApi.Mark) == 'function' then pcall(updateApi.Mark, 'skipped') end
			return
		end
		local contents = type(updateApi.ReadStaged) == 'function' and updateApi.ReadStaged(item) or nil
		if type(contents) ~= 'string' or contents == '' then
			if type(updateApi.Mark) == 'function' then pcall(updateApi.Mark, 'skipped') end
			return
		end
		table.insert(staged, {item = item, contents = contents})
	end

	local updateNames = {}
	for _, entry in ipairs(staged) do
		local name = profileBase(entry.item) or 'profile'
		table.insert(updateNames, name)
	end

	local function destinationFor(name, item)
		local place = type(item) == 'table' and tostring(item.path):match('^profiles/[%a_]+(%d+)%.txt$')
			or tostring(vape.Place)
		return runtimeFolder..'/profiles/'..name..tostring(place)..'.txt'
	end
	local function uniqueName(base, item)
		local candidate = base..' (updated)'
		local suffix = 2
		local function exists(name)
			for _, profile in ipairs(vape.Profiles or {}) do
				if type(profile) == 'table' and profile.Name == name then return true end
			end
			return isfile(destinationFor(name, item))
		end
		while exists(candidate) do
			candidate = base..' (updated '..tostring(suffix)..')'
			suffix += 1
		end
		return candidate
	end

	local function overrideProfiles()
		local activeProfile = vape.Profile
		local reloadActive = false
		local added = {}
		vape.Profiles = vape.Profiles or {}
		for _, entry in ipairs(staged) do
			local base = profileBase(entry.item)
			if type(base) ~= 'string' then return false end
			-- Override the built-in default profile. Keep a user's custom blatant
			-- profile intact while still making its updated release available.
			local targetName = base == 'default' and base or uniqueName(base, entry.item)
			local ok = pcall(function()
				local path = base == 'default' and runtimeFolder..'/'..entry.item.path
					or destinationFor(targetName, entry.item)
				local parent = path:match('^(.+)/[^/]+$')
				if parent and not isfolder(parent) then makefolder(parent) end
				writefile(path, entry.contents)
			end)
			if not ok then return false end
			if base == 'default' and activeProfile == base then reloadActive = true end
			if base ~= 'default' then
				table.insert(added, {Name = targetName, Bind = {}})
			end
		end
		for _, profile in ipairs(added) do table.insert(vape.Profiles, profile) end
		if #added > 0 and vape.Categories and vape.Categories.Profiles
			and type(vape.Categories.Profiles.ChangeValue) == 'function' then
			pcall(vape.Categories.Profiles.ChangeValue, vape.Categories.Profiles)
		end
		if #added > 0 and type(vape.Save) == 'function' then pcall(vape.Save, vape) end
		if reloadActive and type(vape.Load) == 'function' then
			pcall(vape.Load, vape, true, activeProfile)
		end
		return true
	end

	local function installProfiles()
		local added = {}
		vape.Profiles = vape.Profiles or {}
		for _, entry in ipairs(staged) do
			local base = profileBase(entry.item)
			if type(base) ~= 'string' then return false end
			local name = uniqueName(base, entry.item)
			local ok = pcall(function()
				writefile(destinationFor(name, entry.item), entry.contents)
			end)
			if not ok then return false end
			table.insert(added, {Name = name, Bind = {}})
		end
		for _, profile in ipairs(added) do table.insert(vape.Profiles, profile) end
		if vape.Categories and vape.Categories.Profiles
			and type(vape.Categories.Profiles.ChangeValue) == 'function' then
			pcall(vape.Categories.Profiles.ChangeValue, vape.Categories.Profiles)
		end
		-- Save only after the list has been updated; this preserves the existing
		-- GUI color/theme and active profile while persisting the new entries.
		if type(vape.Save) == 'function' then pcall(vape.Save, vape) end
		return true
	end

	-- Use the same category/list/button components as the rest of the Vape UI.
	-- This replaces the old ad-hoc modal and also means scaling/theme changes are
	-- applied consistently. The temporary category removes itself after a choice.
	-- The compatibility GUI does not expose the new GUI's global asset helper or
	-- divider component, so resolve both through the loaded GUI when available and
	-- degrade to a plain category when it is not.
	local assetLoader = vape.Libraries and vape.Libraries.getcustomasset
	local iconPath = 'bvc/assets/new/profilesicon.png'
	local updateIcon = ''
	if type(assetLoader) == 'function' then
		local iconOk, icon = pcall(assetLoader, iconPath)
		if iconOk and type(icon) == 'string' then updateIcon = icon end
		if updateIcon == '' then
			local fallbackOk, fallbackIcon = pcall(assetLoader, 'bvc/assets/old/profilesicon.png')
			if fallbackOk and type(fallbackIcon) == 'string' then updateIcon = fallbackIcon end
		end
	end
	local updateSettings = {
		Name = 'Profile Update',
		Icon = updateIcon,
		Placeholder = 'Profile update',
		Color = Color3.fromRGB(85, 170, 255),
		WindowSize = 250,
		Size = UDim2.fromOffset(17, 10),
		Position = UDim2.fromOffset(12, 16)
	}
	local updateMenu = vape:CreateCategoryList(updateSettings)
	if type(updateMenu.CreateDivider) == 'function' then
		updateMenu:CreateDivider('Updated: '..table.concat(updateNames, ', '))
	end
	local closed = false
	local function closeMenu()
		if closed then return end
		closed = true
		if type(vape.Remove) == 'function' then
			pcall(vape.Remove, vape, 'Profile Update')
		elseif updateMenu.Button and type(updateMenu.Button.Toggle) == 'function' then
			pcall(updateMenu.Button.Toggle, updateMenu.Button)
		end
	end
	updateMenu:CreateButton({
		Name = 'Nothing',
		Tooltip = 'Keep the existing profiles unchanged',
		Function = function()
			if type(updateApi.Mark) == 'function' then pcall(updateApi.Mark, 'skipped') end
			vape:CreateNotification('BVC', 'Profile update skipped.', 5, 'info')
			closeMenu()
		end
	})
	updateMenu:CreateButton({
		Name = 'Install',
		Tooltip = 'Add updated profiles without replacing your defaults',
		Function = function()
			if installProfiles() then
				if type(updateApi.Mark) == 'function' then pcall(updateApi.Mark, 'installed') end
				vape:CreateNotification('BVC', 'Updated profiles were added to the Profiles tab.', 6, 'info')
				closeMenu()
			else
				vape:CreateNotification('BVC', 'Could not install the updated profiles.', 8, 'alert')
			end
		end
	})
	updateMenu:CreateButton({
		Name = 'Override & Install',
		Tooltip = 'Apply the updated default profiles and install other updates',
		Function = function()
			if overrideProfiles() then
				if type(updateApi.Mark) == 'function' then pcall(updateApi.Mark, 'applied') end
				vape:CreateNotification('BVC', 'Updated profiles installed.', 6, 'info')
				closeMenu()
			else
				vape:CreateNotification('BVC', 'Could not apply the updated profiles.', 8, 'alert')
			end
		end
	})
	if type(vape.Clean) == 'function' then
		vape:Clean(function()
			if not closed and type(vape.Remove) == 'function' then
				pcall(vape.Remove, vape, 'Profile Update')
			end
		end)
	end
	if updateMenu.Button and type(updateMenu.Button.Toggle) == 'function' then
		updateMenu.Button:Toggle()
	end
end

-- Show release notes in the same category/list UI used by the rest of the
-- runtime.  The installer may provide a structured shared.BVCChangelog;
-- the fallback keeps the window useful for revisions that only ship the
-- runtime metadata.  Nothing here loads or executes a game module.
local function showChangelogWindow()
	local previousRevision = shared.BVCUpdated
	if previousRevision == nil or shared.BVCChangelogShownFor == previousRevision then
		return
	end
	if not vape or not vape.Loaded or type(vape.CreateCategoryList) ~= 'function' then
		return
	end
	local currentRevision = ''
	if isfile('bvc/profiles/commit.txt') then
		local ok, value = pcall(readfile, 'bvc/profiles/commit.txt')
		if ok and type(value) == 'string' then currentRevision = value end
	end
	if currentRevision == '' or currentRevision == tostring(previousRevision) then return end

	local entries = {}
	if type(shared.BVCChangelog) == 'table' then
		for _, entry in ipairs(shared.BVCChangelog) do
			if type(entry) == 'table' then
				local title = tostring(entry.title or entry.Name or ''):gsub('^%s+', ''):gsub('%s+$', '')
				local detail = tostring(entry.detail or entry.description or entry.Tooltip or ''):gsub('^%s+', ''):gsub('%s+$', '')
				if title ~= '' then table.insert(entries, {title = title, detail = detail}) end
			elseif type(entry) == 'string' and entry:gsub('%s+', '') ~= '' then
				table.insert(entries, {title = entry, detail = ''})
			end
		end
	end
	if #entries == 0 then
		entries = {
			{title = 'Runtime updated', detail = 'BVC is now running revision '..currentRevision},
			{title = 'Profile metadata', detail = 'Named profile creation and saved-module details are available.'},
			{title = 'Cloud config details', detail = 'Select a public config to view its rating and install metadata.'},
		}
	end

	local icon = ''
	local assetLoader = vape.Libraries and vape.Libraries.getcustomasset
	if type(assetLoader) == 'function' then
		local ok, value = pcall(assetLoader, 'bvc/assets/new/profilesicon.png')
		if ok and type(value) == 'string' then icon = value end
	end
	local changelog = vape:CreateCategoryList({
		Name = 'Changelog',
		Icon = icon,
		Placeholder = 'Release notes',
		Color = Color3.fromRGB(85, 170, 255),
		WindowSize = 250,
		Size = UDim2.fromOffset(17, 10),
		Position = UDim2.fromOffset(12, 16),
	})
	for _, entry in ipairs(entries) do
		local title = tostring(entry.title):gsub('[%c]', ' ')
		if #title > 48 then title = title:sub(1, 45)..'...' end
		local detail = tostring(entry.detail or ''):gsub('[%c]', ' ')
		changelog:CreateButton({
			Name = '+ '..title,
			Tooltip = detail ~= '' and detail or nil,
			Function = function()
				vape:CreateNotification('Changelog', detail ~= '' and detail or title, 8, 'info')
			end,
		})
	end
	changelog:CreateButton({
		Name = 'Dismiss',
		Function = function()
			if type(vape.Remove) == 'function' then pcall(vape.Remove, vape, 'Changelog') end
		end,
	})
	shared.BVCChangelogShownFor = previousRevision
	if changelog.Button and type(changelog.Button.Toggle) == 'function' then
		changelog.Button:Toggle()
	end
	if type(vape.Clean) == 'function' then
		vape:Clean(function()
			if type(vape.Remove) == 'function' then pcall(vape.Remove, vape, 'Changelog') end
		end)
	end
end

if not isfile('bvc/profiles/gui.txt') then
	writefile('bvc/profiles/gui.txt', 'new')
end
local gui = readCachedFile('bvc/profiles/gui.txt') or 'new'
if gui == 'rise' then
	gui = 'new'
	writefile('bvc/profiles/gui.txt', gui)
end
if gui ~= 'new' and gui ~= 'old' then
	gui = 'new'
	writefile('bvc/profiles/gui.txt', gui)
end
if not isfile('bvc/profiles/commit.txt') then
	writefile('bvc/profiles/commit.txt', 'main')
end

pcall(function()
	runtimeEnvironment.BVCUsedInit = true
end)

local function loadGuiCandidate(name)
	local path = 'bvc/guis/'..name..'.lua'
	if not isfolder('bvc/assets/'..name) then
		makefolder('bvc/assets/'..name)
	end
	local sourceOk, source = pcall(downloadFile, path)
	if not sourceOk then
		return nil, path..' download failed: '..tostring(source)
	end
	local success, result = runSource(source, path, license)
	if not success then return nil, result end
	if type(result) ~= 'table' or type(result.Load) ~= 'function'
		or type(result.Save) ~= 'function' or type(result.CreateNotification) ~= 'function' then
		return nil, path..' returned an invalid GUI object'
	end
	return result
end

local guiError
vape, guiError = loadGuiCandidate(gui)
local guiFallbackReason
if not vape and gui ~= 'old' then
	guiFallbackReason = guiError
	local fallbackError
	vape, fallbackError = loadGuiCandidate('old')
	if vape then
		gui = 'old'
		pcall(writefile, 'bvc/profiles/gui.txt', gui)
	else
		guiError = tostring(guiError)..' | '..tostring(fallbackError)
	end
end
if not vape then
	error('BVC GUI unavailable: '..tostring(guiError), 0)
end

if not isfolder('bvc/assets/'..gui) then
	makefolder('bvc/assets/'..gui)
end
vape.Place = game.PlaceId
_G.BVC = vape
shared.BVC = vape
local previousUninject = vape.Uninject
if type(previousUninject) == 'function' then
	vape.Uninject = function(self, ...)
		local ownsSharedRuntime = shared.BVC == self
		if shared.BVCDownloadFile == ownedDownloadFile then
			shared.BVCDownloadFile = nil
		end
		local results = table.pack(pcall(previousUninject, self, ...))
		-- These handles are runtime-scoped.  Clear only values owned by this
		-- instance so a stale teardown cannot erase a replacement runtime's
		-- teleport/auth state if both loaders briefly overlap.
		if ownsSharedRuntime then
			for _, key in {
				'BVCTeleportQueueParts',
				'BVCQueueTeleport',
				'BVCFlushTeleportQueue',
			} do
				shared[key] = nil
			end
		end
		restoreRuntimeEnvironment()
		if not results[1] then
			error(results[2], 0)
		end
		return table.unpack(results, 2, results.n)
	end
end
loadMaxPrediction()
loadBVCTheme()
if guiFallbackReason then
	vape:CreateNotification('BVC', 'The selected GUI failed, so compatibility mode was loaded: '..tostring(guiFallbackReason), 12, 'warning')
end

local function loadGameModule(placeId)
	vape.Place = placeId
	local gamePath = 'bvc/games/'..placeId..'.lua'
	if diagnostics and type(diagnostics.fileState) == 'function' then
		pcall(diagnostics.fileState, gamePath, nil, 'game-module-load')
	end
	local gameSource = readCachedFile(gamePath)
		or shared.BVCDownloadFile(gamePath)
	if type(gameSource) ~= 'string' or gameSource == '404: Not Found' then
		recordDiagnostic('game_module_source_unavailable', {path = gamePath, placeId = placeId})
		vape:CreateNotification(
			'BVC',
			'Game module file unavailable; loaded base modules only. Send '..diagnosticsPath..' to support.',
			15,
			'warning'
		)
		return false
	end

	-- Keep the legacy `shared.vape` alias scoped to game-module execution so
	-- modules written against the older runtime name keep working.
	local previousLegacyVape = shared.vape
	shared.vape = vape
	local ok, loaded = runSource(gameSource, tostring(placeId), license)
	if shared.vape == vape then
		shared.vape = previousLegacyVape
	end
	if not ok or loaded == false then
		local detail = not ok and tostring(loaded) or 'module returned false'
		recordDiagnostic('game_module_failed', {
			detail = detail,
			path = gamePath,
			placeId = placeId,
			reason = 'none',
			stage = ok and 'module-returned-false' or 'runtime-error',
		})
		vape:CreateNotification(
			'BVC',
			'Game module unavailable; loaded base modules only. '..detail:sub(1, 260)
				..' Send '..diagnosticsPath..' to support.',
			15,
			'warning'
		)
		return false
	end
	recordDiagnostic('game_module_loaded', {bytes = #gameSource, path = gamePath, placeId = placeId})
	return true
end

if not shared.BVCIndependent then
	-- Register the teleport handoff before any optional universal/game module
	-- can wait on Knit or a controller.  A lobby module must never be able to
	-- prevent the next server from receiving the clean runtime bootstrap.
	installTeleportReload()
	local registrationBatch = type(vape.BeginModuleRegistration) == 'function'
		and type(vape.EndModuleRegistration) == 'function'
	if registrationBatch then
		vape:BeginModuleRegistration()
	end
	local universalPath = 'bvc/games/universal.lua'
	local universalSourceOk, universalSource = pcall(downloadFile, universalPath)
	local universalOk, universalError = false, universalSource
	if universalSourceOk then
		universalOk, universalError = runSource(universalSource, universalPath, license)
	end
	if not universalOk then
		recordDiagnostic('base_modules_failed', {error = universalError, path = universalPath})
		vape:CreateNotification('BVC', 'Base modules failed to load: '..tostring(universalError):sub(1, 240), 12, 'alert')
	else
		recordDiagnostic('base_modules_loaded', {path = universalPath})
	end
	loadGameModule(game.PlaceId)
	loadBVCTheme()
	if registrationBatch then
		vape:EndModuleRegistration()
	end
	-- Cold-start yielding is scoped to the initial universal/game/theme pass;
	-- later custom-module loads should use the normal fast registration path.
	shared.BVCColdStart = false
	recordDiagnostic('main_finish_loading', {placeId = game.PlaceId})
	finishLoading()
	task.defer(showProfileUpdateMenu)
	task.defer(showChangelogWindow)
else
	loadBVCTheme()
	vape.Init = function(...)
		local result = table.pack(finishLoading(...))
		task.defer(showProfileUpdateMenu)
		task.defer(showChangelogWindow)
		return table.unpack(result, 1, result.n)
	end
	return vape
end
