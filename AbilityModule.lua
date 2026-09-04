--!strict
local AbilityModule = {}
AbilityModule.__index = AbilityModule

local Players = game:GetService("Players")

function AbilityModule.Init(State: any, Toggles: any, Options: any, PathfindingModule: any?)
	local self = setmetatable({}, AbilityModule)
	self.State = State
	self.Toggles = Toggles
	self.Options = Options
	self.PathfindingModule = PathfindingModule
	self.Player = Players.LocalPlayer
	self.Running = false
	self.SpamThread = nil :: thread?
	self.Mode = "Spam"
	self.SpamInterval = 0.1
	self.OnlyAtPost = false
	return self
end

function AbilityModule:SetPathfindingModule(pathfindingModule: any)
	self.PathfindingModule = pathfindingModule
end

function AbilityModule:SetOnlyAtPost(enabled: boolean)
	self.OnlyAtPost = enabled
end

-- Fires all RemoteEvents named "spellEvent" found inside the player's Backpack
local function fireBackpackSpellEvents(self: any)
	-- Check if we should restrict firing until post position is reached
	if self.OnlyAtPost and self.PathfindingModule then
		if not self.PathfindingModule:IsAtPostPosition() then
			return
		end
	end

	local player = Players.LocalPlayer
	if not player then return end
	local backpack = player:FindFirstChild("Backpack")
	if not backpack then return end

	for _, item in ipairs(backpack:GetDescendants()) do
		if item:IsA("RemoteEvent") and item.Name == "spellEvent" then
			pcall(function()
				item:FireServer()
			end)
		end
	end
end

function AbilityModule:Start()
	if self.Running then return end
	self.Running = true
	self.SpamThread = task.spawn(function()
		while self.Running do
			fireBackpackSpellEvents(self)
			task.wait(self.SpamInterval)
		end
	end)
end

function AbilityModule:Stop()
	self.Running = false
	if self.SpamThread then
		task.cancel(self.SpamThread)
		self.SpamThread = nil
	end
end

function AbilityModule:SetMode(mode: string)
	self.Mode = mode
end

function AbilityModule:SetSpamInterval(interval: number)
	self.SpamInterval = interval
end

return AbilityModule
