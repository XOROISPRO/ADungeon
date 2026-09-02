--!strict
local AutoClickerModule = {}
AutoClickerModule.__index = AutoClickerModule

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

function AutoClickerModule.Init(State: any, Toggles: any)
	local self = setmetatable({}, AutoClickerModule)

	self.State = State
	self.Toggles = Toggles
	self.Player = Players.LocalPlayer
	self.Running = false
	self.ClickThread = nil :: thread?
	self.Interval = 0.1

	return self
end

-- Searches character for any equipped tool containing a "swing" RemoteEvent
local function fireWeaponSwingEvent(player: Player)
	local char = player.Character or Workspace:FindFirstChild(player.Name)
	if not char then return end

	for _, child in ipairs(char:GetChildren()) do
		if child:IsA("Tool") then
			local swingEvent = child:FindFirstChild("swing", true)
			if swingEvent and swingEvent:IsA("RemoteEvent") then
				pcall(function()
					swingEvent:FireServer()
				end)
			end
		end
	end
end

function AutoClickerModule:Start()
	if self.Running then return end
	self.Running = true

	self.ClickThread = task.spawn(function()
		while self.Running do
			fireWeaponSwingEvent(self.Player)
			task.wait(self.Interval)
		end
	end)
end

function AutoClickerModule:Stop()
	self.Running = false

	if self.ClickThread then
		task.cancel(self.ClickThread)
		self.ClickThread = nil
	end
end

function AutoClickerModule:SetInterval(interval: number)
	self.Interval = interval
end

return AutoClickerModule
