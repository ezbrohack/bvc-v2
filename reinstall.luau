local cloneref = cloneref or function(ref)
	return ref
end

local folder = shared.BVCFolder or 'bvc'
if isfolder(folder) then
	if type(delfolder) ~= 'function' then
		error('Your executor cannot remove the existing BVC folder.', 0)
	end
	local deleted, deleteError = pcall(delfolder, folder)
	if not deleted or isfolder(folder) then
		error('Failed to remove the existing BVC folder: '..tostring(deleteError or 'folder still exists'), 0)
	end
end

cloneref(game:GetService('StarterGui')):SetCore('SendNotification', {
	Title = 'BVC',
	Text = 'Successfully reinstalled BVC. Rejoin the game to take effect.',
	Duration = 20,
})
