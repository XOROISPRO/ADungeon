--!strict
local ConfigManager = {}
ConfigManager.__index = ConfigManager

local HttpService = game:GetService("HttpService")

function ConfigManager.Init(State: any, Options: any, Toggles: any, Modules: { AbilityModule: any, PathfindingModule: any, AutoClickerModule: any })
	local self = setmetatable({}, ConfigManager)

	self.State = State
	self.Options = Options
	self.Toggles = Toggles
	self.Modules = Modules

	self.FolderName = "DungeonFarmConfig"
	self.AutoLoadFile = self.FolderName .. "/autoload.txt"

	-- Ensure root folder exists
	if typeof(makefolder) == "function" and typeof(isfolder) == "function" then
		if not isfolder(self.FolderName) then
			makefolder(self.FolderName)
		end
	end

	return self
end

-- Formats configuration path
function ConfigManager:GetPath(configName: string): string
	return self.FolderName .. "/" .. configName .. ".json"
end

-- Extracts current settings into a table
function ConfigManager:ExportSettings(): { [string]: any }
	return {
		Toggles = self.Toggles or {},
		Options = self.Options or {},
	}
end

-- Applies loaded data into live state & module settings
function ConfigManager:ImportSettings(data: { [string]: any })
	if data.Toggles then
		for key, val in pairs(data.Toggles) do
			self.Toggles[key] = val
		end
	end

	if data.Options then
		for key, val in pairs(data.Options) do
			self.Options[key] = val
		end
	end

	-- Update active module states if options exist
	if self.Modules.PathfindingModule and self.Options.HoverHeight then
		self.Modules.PathfindingModule:SetHoverHeight(self.Options.HoverHeight)
	end

	if self.Modules.PathfindingModule and self.Options.WalkSpeed then
		self.Modules.PathfindingModule:SetWalkSpeed(self.Options.WalkSpeed)
	end

	if self.Modules.AbilityModule and self.Options.AbilityMode then
		self.Modules.AbilityModule:SetMode(self.Options.AbilityMode)
	end

	if self.Modules.AutoClickerModule and self.Options.ClickInterval then
		self.Modules.AutoClickerModule:SetInterval(self.Options.ClickInterval)
	end
end

-- 1. Save Config
function ConfigManager:SaveConfig(configName: string): boolean
	if not configName or configName == "" then return false end
	if typeof(writefile) ~= "function" then return false end

	local path = self:GetPath(configName)
	local data = self:ExportSettings()

	local success, encoded = pcall(function()
		return HttpService:JSONEncode(data)
	end)

	if success and encoded then
		writefile(path, encoded)
		print("[ConfigManager] Saved config: " .. configName)
		return true
	end

	return false
end

-- 2. Load Config
function ConfigManager:LoadConfig(configName: string): boolean
	if not configName or configName == "" then return false end
	if typeof(readfile) ~= "function" or typeof(isfile) ~= "function" then return false end

	local path = self:GetPath(configName)
	if not isfile(path) then return false end

	local success, decoded = pcall(function()
		local content = readfile(path)
		return HttpService:JSONDecode(content)
	end)

	if success and type(decoded) == "table" then
		self:ImportSettings(decoded)
		print("[ConfigManager] Loaded config: " .. configName)
		return true
	end

	return false
end

-- 3. Delete Config
function ConfigManager:DeleteConfig(configName: string): boolean
	if not configName or configName == "" then return false end
	if typeof(delfile) ~= "function" or typeof(isfile) ~= "function" then return false end

	local path = self:GetPath(configName)
	if isfile(path) then
		delfile(path)

		-- Clear autoload reference if the deleted file was the autoloaded config
		if self:GetAutoLoadConfig() == configName then
			self:SetAutoLoadConfig("")
		end

		print("[ConfigManager] Deleted config: " .. configName)
		return true
	end

	return false
end

-- 4. Get Config List
function ConfigManager:GetConfigList(): { string }
	local configs = {}
	if typeof(listfiles) ~= "function" then return configs end

	local success, files = pcall(function()
		return listfiles(self.FolderName)
	end)

	if success and files then
		for _, filePath in ipairs(files) do
			if filePath:sub(-5) == ".json" then
				local filename = filePath:match("([^/\\]+)%.json$")
				if filename then
					table.insert(configs, filename)
				end
			end
		end
	end

	return configs
end

-- 5. Set Autoload Config Target
function ConfigManager:SetAutoLoadConfig(configName: string)
	if typeof(writefile) ~= "function" then return end
	writefile(self.AutoLoadFile, configName or "")
	print("[ConfigManager] Set autoload target: " .. tostring(configName))
end

-- 6. Get Autoload Config Target
function ConfigManager:GetAutoLoadConfig(): string
	if typeof(readfile) ~= "function" or typeof(isfile) ~= "function" then return "" end
	if isfile(self.AutoLoadFile) then
		return readfile(self.AutoLoadFile)
	end
	return ""
end

-- 7. Execute Autoload Sequence
function ConfigManager:AutoLoad()
	local targetConfig = self:GetAutoLoadConfig()
	if targetConfig ~= "" then
		self:LoadConfig(targetConfig)
	end
end

return ConfigManager
