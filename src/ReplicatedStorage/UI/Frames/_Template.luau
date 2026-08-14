--!strict
-- Copy this file to a new ModuleScript under Frames/ and implement your frame API.

local Frame = {}
Frame.__index = Frame

function Frame.new()
	return setmetatable({}, Frame)
end

--- Optional. Auto-run from UI:Start() on the client (see UI/init).
function Frame:Start(_ui: any) end

function Frame:Destroy()
	-- cleanup
end

return Frame
