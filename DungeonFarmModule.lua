--!strict
local DungeonFarmModule = {}
DungeonFarmModule.__index = DungeonFarmModule

local Players = game:GetService("Players")
local VirtualInputManager = game:GetService("VirtualInputManager")

function DungeonFarmModule.Init(State: any, Toggles: any, PathfindingModule: any, AbilityModule: any)
	local self = setmetatable({}, DungeonFarmModule)

	self.State = State
	self.Toggles = Toggles
	self.PathfindingModule = PathfindingModule
	self.AbilityModule = AbilityModule
	self.Player = Players.LocalPlayer
	self.Running = false

	return self
end

-- Safely fires the start UI button
function DungeonFarmModule:ClickStartButton()
	local pgui = self.Player:FindFirstChild("PlayerGui")
	if not pgui then return end

	local startBtn = pgui:FindFirstChild("startButton")
	if not startBtn then return end

	local frame1 = startBtn:FindFirstChild("Frame")
	local frame3D = frame1 and frame1:FindFirstChild("3d")
	local frameInner = frame3D and frame3D:FindFirstChild("Frame")
	local textButton = frameInner and frameInner:FindFirstChild("TextButton") :: TextButton?

	if textButton and textButton:IsA("TextButton") then
		-- Approach 1: Virtual Mouse Click
		local pos = textButton.AbsolutePosition
		local size = textButton.AbsoluteSize
		local centerX = pos.X + (size.X / 2)
		local centerY = pos.Y + (size.Y / 2) + 36 -- Account for top bar offset

		pcall(function()
			VirtualInputManager:SendMouseButtonEvent(centerX, centerY, 0, true, game, 1)
			task.wait(0.05)
			VirtualInputManager:SendMouseButtonEvent(centerX, centerY, 0, false, game, 1)
		end)

		-- Approach 2: Safe firesignal execution for exploit environments
		if typeof(firesignal) == "function" then
			pcall(function()
				firesignal(textButton.MouseButton1Click)
				firesignal(textButton.MouseButton1Down)
				firesignal(textButton.Activated)
			end)
		elseif typeof(getconnections) == "function" then
			pcall(function()
				for _, connection in pairs(getconnections(textButton.MouseButton1Click)) do
					if connection.Function then connection:Fire() end
				end
				for _, connection in pairs(getconnections(textButton.Activated)) do
					if connection.Function then connection:Fire() end
				end
			end)
		end
	end
end

function DungeonFarmModule:Start()
	if self.Running then return end
	self.Running = true
	self.State.AutoFarmActive = true

	-- Direct Start Button Input
	self:ClickStartButton()

	if self.PathfindingModule then
		self.PathfindingModule:StartHoverTargeting()
	end

	if self.AbilityModule then
		self.AbilityModule:Start()
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
