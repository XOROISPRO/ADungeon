--!strict
local PathfindingModule = {}
PathfindingModule.__index = PathfindingModule

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")

function PathfindingModule.Init(State: any, Toggles: any)
	local self = setmetatable({}, PathfindingModule)

	self.State = State
	self.Toggles = Toggles
	self.Player = Players.LocalPlayer
	self.DEBUG = true

	-- Physics Parameters
	self.MAX_SPEED = 35
	self.ACCEL = 25
	self.AIR_ACCEL = 10
	self.FRICTION = 6
	self.STOP_SPEED = 1.5
	self.HOVER_HEIGHT = 9

	-- Movement State Vector Tracker
	self.MoveState = {
		velocity = Vector3.new(),
		waypoints = nil :: {PathWaypoint | Vector3}?,
		waypointIndex = 1,
		wpStartTime = 0,
		lastWpPos = nil :: Vector3?,
		done = true,
	}

	self.MoveConnection = nil :: RBXScriptConnection?

	return self
end

function PathfindingModule:DPrint(...)
	if self.DEBUG then print("[PathfindingModule]", ...) end
end

-- Physics Helpers
local function grounded(character: Model, root: BasePart): boolean
	local rayParams = RaycastParams.new()
	rayParams.FilterDescendantsInstances = { character }
	rayParams.FilterType = Enum.RaycastFilterType.Exclude

	local result = Workspace:Raycast(root.Position, Vector3.new(0, -4.5, 0), rayParams)
	return (result ~= nil and result.Instance ~= nil and result.Instance.CanCollide)
end

local function applyFriction(velocity: Vector3, isGrounded: boolean, friction: number, stopSpeed: number, dt: number): Vector3
	local speed = velocity.Magnitude
	if speed < 0.1 then return Vector3.new() end
	local drop = isGrounded and (math.max(speed, stopSpeed) * friction * dt) or 0
	local newSpeed = math.max(speed - drop, 0)
	return (newSpeed ~= speed) and (velocity * (newSpeed / speed)) or velocity
end

local function accel(velocity: Vector3, wishDir: Vector3, wishSpeed: number, accelRate: number, dt: number): Vector3
	local add = wishSpeed - velocity:Dot(wishDir)
	if add <= 0 then return velocity end
	return velocity + wishDir * math.min(accelRate * dt * wishSpeed, add)
end

function PathfindingModule:StepMovement(root: BasePart, character: Model, wishDir: Vector3, wishSpeed: number, dt: number)
	local isGrounded = grounded(character, root)
	local accelRate = isGrounded and self.ACCEL or self.AIR_ACCEL

	self.MoveState.velocity = applyFriction(self.MoveState.velocity, isGrounded, self.FRICTION, self.STOP_SPEED, dt)
	self.MoveState.velocity = accel(self.MoveState.velocity, wishDir, wishSpeed, accelRate, dt)
	
	-- Maintain target altitude directly via velocity vector component adjustments
	root.AssemblyLinearVelocity = Vector3.new(
		self.MoveState.velocity.X, 
		wishDir.Y * wishSpeed, 
		self.MoveState.velocity.Z
	)
end

function PathfindingModule:SetHoverHeight(height: number)
	self.HOVER_HEIGHT = height
end

function PathfindingModule:SetWalkSpeed(speed: number)
	self.MAX_SPEED = speed
end

-- Nearest Dungeon Enemy Tracker
function PathfindingModule:GetClosestEnemy(): BasePart?
	local char = self.Player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return nil end

	local dungeon = Workspace:FindFirstChild("dungeon")
	if not dungeon then return nil end

	local closestEnemyPart: BasePart? = nil
	local shortestDistance = math.huge

	for _, room in pairs(dungeon:GetChildren()) do
		local enemyFolder = room:FindFirstChild("enemyFolder")
		if enemyFolder then
			for _, enemy in pairs(enemyFolder:GetChildren()) do
				local enemyHum = enemy:FindFirstChildOfClass("Humanoid")
				local enemyRoot = enemy:FindFirstChild("HumanoidRootPart") :: BasePart?

				if enemyRoot and (not enemyHum or enemyHum.Health > 0) then
					local dist = (enemyRoot.Position - root.Position).Magnitude
					if dist < shortestDistance then
						shortestDistance = dist
						closestEnemyPart = enemyRoot
					end
				end
			end
		end
	end

	return closestEnemyPart
end

-- Continuous Vector Hover Logic over Target Enemies
function PathfindingModule:StartHoverTargeting()
	self:StopPathfinding()

	local char = self.Player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not char or not root then return end

	self.State.Navigating = true
	self.MoveState.done = false

	self.MoveConnection = RunService.Heartbeat:Connect(function(dt)
		if not self.State.Navigating or not root or not char then return end

		local enemyRoot = self:GetClosestEnemy()
		if enemyRoot then
			local targetPos = enemyRoot.Position + Vector3.new(0, self.HOVER_HEIGHT, 0)
			local delta = targetPos - root.Position
			local dist = delta.Magnitude

			if dist > 0.5 then
				local wishDir = delta.Unit
				self:StepMovement(root, char, wishDir, self.MAX_SPEED, dt)
			else
				self.MoveState.velocity = Vector3.new()
				root.AssemblyLinearVelocity = Vector3.zero
			end
		else
			self.MoveState.velocity = Vector3.new()
			root.AssemblyLinearVelocity = Vector3.zero
		end
	end)
end

function PathfindingModule:StopPathfinding()
	if self.State then
		self.State.Navigating = false
	end

	self.MoveState.done = true
	self.MoveState.velocity = Vector3.new()

	if self.MoveConnection then
		self.MoveConnection:Disconnect()
		self.MoveConnection = nil
	end

	local char = self.Player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		root.AssemblyLinearVelocity = Vector3.zero
	end
end

return PathfindingModule
