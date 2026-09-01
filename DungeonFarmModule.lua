--!strict
local DungeonFarmModule = {}
DungeonFarmModule.__index = DungeonFarmModule

function DungeonFarmModule.Init(State: any, Toggles: any, PathfindingModule: any)
	local self = setmetatable({}, DungeonFarmModule)
	self.State = State
	self.Toggles = Toggles
	self.PathfindingModule = PathfindingModule
	return self
end

function DungeonFarmModule:Start()
	self.State.AutoFarmActive = true
	if self.PathfindingModule then
		self.PathfindingModule:StartHoverTargeting()
	end
end

function DungeonFarmModule:Stop()
	self.State.AutoFarmActive = false
	if self.PathfindingModule then
		self.PathfindingModule:StopPathfinding()
	end
end

return DungeonFarmModule
