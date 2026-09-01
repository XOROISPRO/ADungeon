--!strict
local DungeonFarmModule = {}
DungeonFarmModule.__index = DungeonFarmModule

local ReplicatedStorage = game:GetService("ReplicatedStorage")

function DungeonFarmModule.Init(State: any, Toggles: any, PathfindingModule: any, AbilityModule: any, AutoClickerModule: any)
	local self = setmetatable({}, DungeonFarmModule)

	self.State = State
	self.Toggles = Toggles
	self.PathfindingModule = PathfindingModule
	self.AbilityModule = AbilityModule
	self.AutoClickerModule = AutoClickerModule
	self.Running = false

	return self
end

function DungeonFarmModule:TriggerStartRemote()
	local remotes = ReplicatedStorage:FindFirstChild("remotes")
	if remotes then
		local changeStartValue = remotes:FindFirstChild("changeStartValue") :: RemoteEvent?
		if changeStartValue and changeStartValue:IsA("RemoteEvent") then
			changeStartValue:FireServer()
		end
	end
end

function DungeonFarmModule:Start()
	if self.Running then return end
	self.Running = true
	self.State.AutoFarmActive = true

	self:TriggerStartRemote()

	if self.PathfindingModule then
		self.PathfindingModule:StartHoverTargeting()
	end

	if self.AbilityModule then
		self.AbilityModule:Start()
	end

	if self.AutoClickerModule then
		self.AutoClickerModule:Start()
	end
end

function DungeonFarmModule:Stop()
	self.Running = false
	self.State.AutoFarmActive = false

	if self.PathfindingModule then
		self.PathfindingModule:StopPathfinding()
	end

	if self.AbilityModule then
		self.AbilityModule:Stop()
	end

	if self.AutoClickerModule then
		self.AutoClickerModule:Stop()
	end
end

function DungeonFarmModule:SetDistance(height: number)
	if self.PathfindingModule then
		self.PathfindingModule:SetHoverHeight(height)
	end
end

function DungeonFarmModule:SetSpeed(speed: number)
	if self.PathfindingModule then
		self.PathfindingModule:SetWalkSpeed(speed)
	end
end

return DungeonFarmModule
