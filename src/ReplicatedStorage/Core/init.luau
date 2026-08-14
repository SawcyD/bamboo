--!strict

local ModuleLoader = require(script:WaitForChild("ModuleLoader"))

local Core = {}

local _loaders: { [string]: ModuleLoader.ModuleLoaderType } = {}

local function loaderFor(folderName: string): ModuleLoader.ModuleLoaderType
	local loader = _loaders[folderName]
	if not loader then
		loader = ModuleLoader.new(script:WaitForChild(folderName) :: Folder)
		_loaders[folderName] = loader
	end
	return loader
end

function Core:Get(name: string): any
	return loaderFor("Modules"):Get(name)
end

function Core:GetClass(name: string): any
	return loaderFor("Classes"):Get(name)
end

function Core:GetType(name: string): any
	return loaderFor("Types"):Get(name)
end

function Core:GetUtil(name: string): any
	return loaderFor("Utils"):Get(name)
end

function Core:GetShared(name: string): any
	return loaderFor("Shared"):Get(name)
end

--- Shared game domains (Core/Shared/Domains/<Name>), e.g. Core:GetDomain("Bamboo").
function Core:GetDomain(name: string): any
	local loader = _loaders.Domains
	if not loader then
		local domains = script:WaitForChild("Shared"):WaitForChild("Domains") :: Folder
		loader = ModuleLoader.new(domains)
		_loaders.Domains = loader
	end
	return loader:Get(name)
end

function Core:GetPackage(name: string): any
	return loaderFor("Packages"):Get(name)
end

function Core:GetConfig(name: string): any
	return loaderFor("Configs"):Get(name)
end

return Core
