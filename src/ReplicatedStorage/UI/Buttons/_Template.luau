--!strict
-- Copy this file to a new ModuleScript under Buttons/ and implement your button API.

local Button = {}
Button.__index = Button

function Button.new()
	return setmetatable({}, Button)
end

--- Optional. Auto-run from UI:Start() on the client (see UI/init).
function Button:Start(_ui: any) end

function Button:Destroy()
	-- cleanup
end

return Button
