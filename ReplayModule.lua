--!strict
local ReplayModule = {}
ReplayModule.__index = ReplayModule

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

function ReplayModule.Init(State: any, Toggles: any)
	local self = setmetatable({}, ReplayModule)

	self.State = State
	self.Toggles = Toggles
	self.Player = Players.LocalPlayer

	self.ReplayRemote = ReplicatedStorage:WaitForChild("remotes"):WaitForChild("replayDungeon") :: RemoteEvent
	self.MonitorConnection = nil :: RBXScriptConnection?
	self.DeathConnection = nil :: RBXScriptConnection?
	
	self.IsReplaying = false
	self.LastReplayAttempt = 0

	return self
end

function ReplayModule:FireReplay()
	local now = tick()
	-- Prevent rapid firing (3 second cooldown)
	if self.IsReplaying or (now - self.LastReplayAttempt) < 3 then return end

	self.IsReplaying = true
	self.LastReplayAttempt = now
	print("[REPLAY MODULE] Triggering Replay Dungeon Remote...")

	pcall(function()
		self.ReplayRemote:FireServer()
	end)

	task.delay(5, function()
		self.IsReplaying = false
	end)
end

function ReplayModule:SetupDeathListener(character: Model)
	if self.DeathConnection then
		self.DeathConnection:Disconnect()
		self.DeathConnection = nil
	end

	local humanoid = character:WaitForChild("Humanoid", 5) :: Humanoid?
	if humanoid then
		self.DeathConnection = humanoid.Died:Connect(function()
			local hardcoreObj = Workspace:FindFirstChild("hardcore") :: BoolValue?
			local isHardcore = hardcoreObj and hardcoreObj.Value == true

			if isHardcore then
				print("[REPLAY MODULE] Player died in Hardcore mode! Replaying dungeon...")
				self:FireReplay()
			end
		end)
	end
end

function ReplayModule:Start()
	self:Stop()

	-- Bind to current and future characters for death monitoring
	if self.Player.Character then
		self:SetupDeathListener(self.Player.Character)
	end

	self.Player.CharacterAdded:Connect(function(newChar)
		self:SetupDeathListener(newChar)
	end)

	-- Monitor Timer GUI
	self.MonitorConnection = RunService.Heartbeat:Connect(function()
		local playerGui = self.Player:FindFirstChild("PlayerGui")
		if not playerGui then return end

		local timeLeftGui = playerGui:FindFirstChild("timeLeftGui")
		if not timeLeftGui then return end

		local frame = timeLeftGui:FindFirstChild("Frame")
		local timeLabel = frame and frame:FindFirstChild("time") :: TextLabel?

		if timeLabel and timeLabel.Text == "00:00" then
			print("[REPLAY MODULE] Time limit reached (00:00)! Replaying dungeon...")
			self:FireReplay()
		end
	end)

	print("[REPLAY MODULE] Started Replay & Hardcore Monitor.")
end

function ReplayModule:Stop()
	if self.MonitorConnection then
		self.MonitorConnection:Disconnect()
		self.MonitorConnection = nil
	end

	if self.DeathConnection then
		self.DeathConnection:Disconnect()
		self.DeathConnection = nil
	end

	self.IsReplaying = false
	print("[REPLAY MODULE] Stopped Replay Monitor.")
end

return ReplayModule
