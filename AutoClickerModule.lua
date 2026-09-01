--!strict
local AutoClickerModule = {}
AutoClickerModule.__index = AutoClickerModule

local VirtualInputManager = game:GetService("VirtualInputManager")

function AutoClickerModule.Init(State: any, Toggles: any)
	local self = setmetatable({}, AutoClickerModule)

	self.State = State
	self.Toggles = Toggles
	self.Running = false
	self.Thread = nil :: thread?
	self.Interval = 0.1 -- Click interval delay in seconds

	return self
end

local function clickMouse()
	pcall(function()
		if typeof(mouse1click) == "function" then
			mouse1click()
			return
		end

		-- VirtualInputManager fallback
		VirtualInputManager:SendMouseButtonEvent(0, 0, 0, true, game, 1)
		task.wait(0.02)
		VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 1)
	end)
end

function AutoClickerModule:Start()
	if self.Running then return end
	self.Running = true

	self.Thread = task.spawn(function()
		while self.Running do
			clickMouse()
			task.wait(self.Interval)
		end
	end)
end

function AutoClickerModule:Stop()
	self.Running = false
	if self.Thread then
		task.cancel(self.Thread)
		self.Thread = nil
	end
end

function AutoClickerModule:SetInterval(interval: number)
	self.Interval = interval
end

return AutoClickerModule
