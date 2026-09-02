--!strict
local DungeonFarmModule = {}
DungeonFarmModule.__index = DungeonFarmModule

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

function DungeonFarmModule.Init(State: any, Toggles: any, PathfindingModule: any, AbilityModule: any, AutoClickerModule: any)
	local self = setmetatable({}, DungeonFarmModule)

	self.State = State
	self.Toggles = Toggles
	self.PathfindingModule = PathfindingModule
	self.AbilityModule = AbilityModule
	self.AutoClickerModule = AutoClickerModule
	self.Player = Players.LocalPlayer

	self.Running = false
	self.IsReplaying = false
	self.LastReplayAttempt = 0
	self.BossEngaged = false

	-- Connections
	self.MonitorConnection = nil :: RBXScriptConnection?
	self.DeathConnection = nil :: RBXScriptConnection?
	self.CharAddedConnection = nil :: RBXScriptConnection?

	-- Remote Event Reference
	local remotes = ReplicatedStorage:WaitForChild("remotes", 5)
	self.ReplayRemote = remotes and remotes:FindFirstChild("replayDungeon") :: RemoteEvent?

	return self
end

--------------------------------------------------------------------------------
-- REPLAY & UTILITY METHODS
--------------------------------------------------------------------------------

function DungeonFarmModule:TriggerStartRemote()
	local remotes = ReplicatedStorage:FindFirstChild("remotes")
	if remotes then
		local changeStartValue = remotes:FindFirstChild("changeStartValue") :: RemoteEvent?
		if changeStartValue and changeStartValue:IsA("RemoteEvent") then
			changeStartValue:FireServer()
		end
	end
end

function DungeonFarmModule:FireReplay()
	local now = tick()
	if self.IsReplaying or (now - self.LastReplayAttempt) < 3 then return end

	self.IsReplaying = true
	self.LastReplayAttempt = now
	print("[DUNGEON FARM] Triggering Replay Dungeon Remote...")

	if self.ReplayRemote then
		pcall(function()
			self.ReplayRemote:FireServer()
		end)
	end

	task.delay(5, function()
		self.IsReplaying = false
	end)
end

function DungeonFarmModule:SetupDeathListener(character: Model)
	if self.DeathConnection then
		self.DeathConnection:Disconnect()
		self.DeathConnection = nil
	end

	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if humanoid then
		self.DeathConnection = humanoid.Died:Connect(function()
			local hardcoreObj = Workspace:FindFirstChild("hardcore") :: BoolValue?
			local isHardcore = hardcoreObj and hardcoreObj.Value == true

			if isHardcore then
				print("[DUNGEON FARM] Player died in Hardcore mode! Replaying dungeon...")
				self:FireReplay()
			end
		end)
	end
end

function DungeonFarmModule:CheckBossDefeated(): boolean
	local dungeon = Workspace:FindFirstChild("dungeon")
	if not dungeon then return false end

	local bossRoom = dungeon:FindFirstChild("bossRoom")
	if not bossRoom then return false end

	local enemyFolder = bossRoom:FindFirstChild("enemyFolder")
	if not enemyFolder then return false end

	local bossAlive = false

	for _, child in pairs(enemyFolder:GetChildren()) do
		if child:IsA("Model") then
			local hum = child:FindFirstChildOfClass("Humanoid")
			if hum and hum.Health > 0 then
				bossAlive = true
				break
			end
		end
	end

	if bossAlive then
		self.BossEngaged = true
		return false
	end

	return self.BossEngaged and not bossAlive
end

--------------------------------------------------------------------------------
-- START / STOP CONTROLS
--------------------------------------------------------------------------------

function DungeonFarmModule:Start()
	if self.Running then return end
	self.Running = true
	self.State.AutoFarmActive = true
	self.BossEngaged = false

	-- 1. Trigger Start Remote & Core Farming Modules
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

	-- 2. Bind Character Death Listener & Character Respawn Watcher
	if self.Player.Character then
		self:SetupDeathListener(self.Player.Character)
	end

	self.CharAddedConnection = self.Player.CharacterAdded:Connect(function(newChar)
		self:SetupDeathListener(newChar)
		
		-- Handles Auto-Rejoin / Respawn delay issue
		task.delay(1.5, function()
			if self.Running and self.PathfindingModule then
				print("[DUNGEON FARM] Character Respawned/Loaded -> Restarting pathfinding...")
				self.PathfindingModule:StartHoverTargeting()
			end
		end)
	end)

	-- 3. Heartbeat Loop for Timer (00:00) and Boss Victory Monitoring
	self.MonitorConnection = RunService.Heartbeat:Connect(function()
		if not self.Running then return end

		-- Check Timer GUI
		local playerGui = self.Player:FindFirstChild("PlayerGui")
		if playerGui then
			local timeLeftGui = playerGui:FindFirstChild("timeLeftGui")
			local frame = timeLeftGui and timeLeftGui:FindFirstChild("Frame")
			local timeLabel = frame and frame:FindFirstChild("time") :: TextLabel?

			if timeLabel and timeLabel.Text == "00:00" then
				print("[DUNGEON FARM] Time limit reached (00:00)! Replaying dungeon...")
				self:FireReplay()
				return
			end
		end

		-- Check Boss Clearance
		if self:CheckBossDefeated() then
			print("[DUNGEON FARM] Boss defeated! Replaying dungeon...")
			self:FireReplay()
		end
	end)

	print("[DUNGEON FARM] Integrated Farm & Replay Active.")
end

function DungeonFarmModule:Stop()
	self.Running = false
	self.State.AutoFarmActive = false
	self.BossEngaged = false

	-- Stop Core Modules
	if self.PathfindingModule then
		self.PathfindingModule:StopPathfinding()
	end
	if self.AbilityModule then
		self.AbilityModule:Stop()
	end
	if self.AutoClickerModule then
		self.AutoClickerModule:Stop()
	end

	-- Disconnect Listeners
	if self.MonitorConnection then
		self.MonitorConnection:Disconnect()
		self.MonitorConnection = nil
	end
	if self.DeathConnection then
		self.DeathConnection:Disconnect()
		self.DeathConnection = nil
	end
	if self.CharAddedConnection then
		self.CharAddedConnection:Disconnect()
		self.CharAddedConnection = nil
	end

	print("[DUNGEON FARM] Stopped.")
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
