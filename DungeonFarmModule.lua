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

-- Safely fires the start UI button without mouse cursor movement
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
		-- 1. Firesignal execution (Executor environment check)
		if typeof(firesignal) == "function" then
			pcall(function()
				firesignal(textButton.MouseButton1Click)
				firesignal(textButton.MouseButton1Down)
				firesignal(textButton.Activated)
			end)
		-- 2. Direct Function invocation (Solara compatibility)
		elseif typeof(getconnections) == "function" then
			pcall(function()
				local signalsToFire = {
					textButton.MouseButton1Click,
					textButton.MouseButton1Down,
					textButton.Activated
				}

				for _, signal in ipairs(signalsToFire) do
					for _, connection in pairs(getconnections(signal)) do
						-- Check for Solara-style direct .Function invocation
						if typeof(connection.Function) == "function" then
							pcall(connection.Function)
						-- Fallback for standard executor :Fire() method
						elseif typeof(connection.Fire) == "function" then
							pcall(function() connection:Fire() end)
						end
					end
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
