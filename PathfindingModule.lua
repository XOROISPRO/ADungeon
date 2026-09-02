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

	-- Physics & Position Parameters
	self.MAX_SPEED = 35
	self.ACCEL = 15
	self.AIR_ACCEL = 5
	self.MAX_AIR_VELOCITY = 25
	self.FRICTION = 6
	self.STOP_SPEED = 1.5
	self.HOVER_HEIGHT = 9
	self.ENGAGE_DISTANCE = 15
	self.OFFSET_DISTANCE = 3
	self.POST_MODE = true

	-- Active Target & Static Post Tracking
	self.CurrentEnemy = nil :: BasePart?
	self.LockPosition = nil :: Vector3?
	self.IsAnchoredAtPost = false

	self.MoveState = {
		velocity = Vector3.new(),
		waypoints = nil :: {PathWaypoint}?,
		waypointIndex = 1,
		lastComputeTime = 0,
		done = true,
	}

	self.MoveConnection = nil :: RBXScriptConnection?
	self.LastDebugPrint = 0

	return self
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

function PathfindingModule:StepMovement(root: BasePart, character: Model, wishDir: Vector3, wishSpeed: number, dt: number, targetYVelocity: number)
	if root.Anchored then
		root.Anchored = false
		self.IsAnchoredAtPost = false
		print("[DEBUG] Unanchored RootPart for movement step.")
	end

	local isGrounded = grounded(character, root)
	local currentAccel = isGrounded and self.ACCEL or self.AIR_ACCEL
	local activeMaxSpeed = isGrounded and wishSpeed or math.min(wishSpeed, self.MAX_AIR_VELOCITY)

	self.MoveState.velocity = applyFriction(self.MoveState.velocity, isGrounded, self.FRICTION, self.STOP_SPEED, dt)
	self.MoveState.velocity = accel(self.MoveState.velocity, wishDir, activeMaxSpeed, currentAccel, dt)
	
	local clampedY = math.clamp(targetYVelocity, -self.MAX_AIR_VELOCITY, self.MAX_AIR_VELOCITY)
	root.AssemblyLinearVelocity = Vector3.new(
		self.MoveState.velocity.X, 
		clampedY, 
		self.MoveState.velocity.Z
	)
end

function PathfindingModule:SetHoverHeight(height: number) self.HOVER_HEIGHT = height end
function PathfindingModule:SetWalkSpeed(speed: number) self.MAX_SPEED = speed end
function PathfindingModule:SetAirVelocity(maxAirVel: number) self.MAX_AIR_VELOCITY = maxAirVel end
function PathfindingModule:SetAirAccel(airAccel: number) self.AIR_ACCEL = airAccel end
function PathfindingModule:SetOffsetDistance(offset: number) self.OFFSET_DISTANCE = offset end

function PathfindingModule:SetPostMode(enabled: boolean)
	self.POST_MODE = enabled
	if not enabled then
		self.LockPosition = nil
		local char = self.Player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root and root.Anchored then
			root.Anchored = false
			self.IsAnchoredAtPost = false
			print("[DEBUG] Post mode disabled -> Unanchored RootPart.")
		end
	end
	print("[DEBUG] POST_MODE Toggled ->", self.POST_MODE)
end

-- Target Validation: Holds old enemy until dead
function PathfindingModule:GetClosestEnemy(): BasePart?
	local char = self.Player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return nil end

	-- Keep old target until it dies or gets destroyed
	if self.CurrentEnemy and self.CurrentEnemy.Parent then
		local parentModel = self.CurrentEnemy.Parent
		local hum = parentModel:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 then
			return self.CurrentEnemy
		end
	end

	-- Target dead/lost -> Clear target and release locked position + anchor
	if self.CurrentEnemy then
		print("[DEBUG] Target died/lost. Clearing current target, post lock, & unanchoring.")
	end
	self.CurrentEnemy = nil
	self.LockPosition = nil
	
	if root.Anchored then
		root.Anchored = false
		self.IsAnchoredAtPost = false
		print("[DEBUG] Target cleared -> Unanchored RootPart.")
	end

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

				if enemyRoot and enemyHum and enemyHum.Health > 0 then
					local dist = (enemyRoot.Position - root.Position).Magnitude
					if dist < shortestDistance then
						shortestDistance = dist
						closestEnemyPart = enemyRoot
					end
				end
			end
		end
	end

	if closestEnemyPart and closestEnemyPart ~= self.CurrentEnemy then
		print("[DEBUG] New Enemy Found ->", closestEnemyPart.Parent and closestEnemyPart.Parent.Name or "Unknown")
	end

	self.CurrentEnemy = closestEnemyPart
	return closestEnemyPart
end

-- Force character orientation facing downwards without overriding velocity/position
local function faceDownward(root: BasePart)
	local currentPos = root.Position
	root.CFrame = CFrame.new(currentPos) * CFrame.Angles(-math.rad(90), 0, 0)
end

-- Ground Pathfinding
function PathfindingModule:GetGroundWishDir(root: BasePart, targetPos: Vector3): Vector3
	local state = self.MoveState
	local currentTime = tick()

	if not state.waypoints or (currentTime - state.lastComputeTime) > 0.5 then
		state.lastComputeTime = currentTime
		local path = PathfindingService:CreatePath({
			AgentRadius = 2,
			AgentHeight = 5,
			AgentCanJump = true
		})

		local ok, _ = pcall(function()
			path:ComputeAsync(root.Position, targetPos)
		end)

		if ok and path.Status == Enum.PathStatus.Success then
			state.waypoints = path:GetWaypoints()
			state.waypointIndex = 1
		else
			state.waypoints = nil
		end
	end

	if state.waypoints and state.waypointIndex <= #state.waypoints then
		local currentWP = state.waypoints[state.waypointIndex]
		local wpPos = currentWP.Position
		local flatDelta = Vector3.new(wpPos.X - root.Position.X, 0, wpPos.Z - root.Position.Z)

		if flatDelta.Magnitude < 3 then
			state.waypointIndex += 1
			if state.waypointIndex <= #state.waypoints then
				local nextWP = state.waypoints[state.waypointIndex]
				flatDelta = Vector3.new(nextWP.Position.X - root.Position.X, 0, nextWP.Position.Z - root.Position.Z)
			end
		end

		if flatDelta.Magnitude > 0.1 then
			return flatDelta.Unit
		end
	end

	local directDelta = Vector3.new(targetPos.X - root.Position.X, 0, targetPos.Z - root.Position.Z)
	return directDelta.Magnitude > 0.1 and directDelta.Unit or Vector3.zero
end

-- Execution Loop
function PathfindingModule:StartHoverTargeting()
	self:StopPathfinding()

	local char = self.Player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not char or not root then return end

	self.State.Navigating = true
	self.MoveState.done = false

	print("[DEBUG] Started Hover Targeting")

	self.MoveConnection = RunService.Heartbeat:Connect(function(dt)
		if not self.State.Navigating or not root or not char then return end

		local enemyRoot = self:GetClosestEnemy()
		if enemyRoot then
			local currentPos = root.Position
			local enemyPos = enemyRoot.Position
			local now = tick()

			-- 1. IF LOCKED ON A STATIC POST
			if self.LockPosition then
				local postDelta = self.LockPosition - currentPos
				local distToLock = postDelta.Magnitude

				-- Periodic diagnostic print every 0.5s
				if (now - self.LastDebugPrint) > 0.5 then
					self.LastDebugPrint = now
					print(string.format("[POST ACTIVE] DistToLock: %.2f | Anchored: %s | RootPos: (%.1f, %.1f, %.1f)", 
						distToLock, 
						tostring(root.Anchored),
						currentPos.X, currentPos.Y, currentPos.Z
					))
				end

				if distToLock > 1.5 then
					if root.Anchored then
						root.Anchored = false
						self.IsAnchoredAtPost = false
						print("[DEBUG] Traveling to post lock -> Unanchored RootPart.")
					end
					faceDownward(root)
					local wishDir = postDelta.Unit
					self:StepMovement(root, char, Vector3.new(wishDir.X, 0, wishDir.Z), self.MAX_SPEED, dt, wishDir.Y * self.MAX_SPEED)
				else
					-- Reached post lock -> Zero out movement and ANCHOR
					self.MoveState.velocity = Vector3.zero
					root.AssemblyLinearVelocity = Vector3.zero
					
					if not root.Anchored then
						root.CFrame = CFrame.new(self.LockPosition) * CFrame.Angles(-math.rad(90), 0, 0)
						root.Anchored = true
						self.IsAnchoredAtPost = true
						print("[DEBUG] REACHED POST SPOT -> Anchored RootPart at:", self.LockPosition)
					end
				end
				return
			end

			-- 2. APPROACH ENEMY GROUND POSITION UNTIL ENGAGE DISTANCE
			local flatDelta = Vector3.new(enemyPos.X - currentPos.X, 0, enemyPos.Z - currentPos.Z)
			if flatDelta.Magnitude > self.ENGAGE_DISTANCE then
				local wishDir = self:GetGroundWishDir(root, enemyPos)
				self:StepMovement(root, char, wishDir, self.MAX_SPEED, dt, root.AssemblyLinearVelocity.Y)
			else
				-- 3. FIRST TIME ENTERING ENGAGEMENT RANGE
				local playerToEnemy = (enemyPos - currentPos)
				local flatPlayerToEnemy = Vector3.new(playerToEnemy.X, 0, playerToEnemy.Z)

				local targetHoverPoint = enemyPos
				if flatPlayerToEnemy.Magnitude > self.OFFSET_DISTANCE then
					local approachDir = flatPlayerToEnemy.Unit
					targetHoverPoint = enemyPos - (approachDir * self.OFFSET_DISTANCE)
				end

				local hoverPos = targetHoverPoint + Vector3.new(0, self.HOVER_HEIGHT, 0)
				self.MoveState.waypoints = nil

				if self.POST_MODE then
					self.LockPosition = hoverPos
					print("[DEBUG] POST LOCKED AT ->", hoverPos)
				end

				local offsetDelta = hoverPos - currentPos
				if offsetDelta.Magnitude > 1.5 then
					if root.Anchored then
						root.Anchored = false
						self.IsAnchoredAtPost = false
					end
					faceDownward(root)
					local wishDir = offsetDelta.Unit
					self:StepMovement(root, char, Vector3.new(wishDir.X, 0, wishDir.Z), self.MAX_SPEED, dt, wishDir.Y * self.MAX_SPEED)
				else
					self.MoveState.velocity = Vector3.zero
					root.AssemblyLinearVelocity = Vector3.zero
					
					if self.POST_MODE and not root.Anchored then
						root.CFrame = CFrame.new(hoverPos) * CFrame.Angles(-math.rad(90), 0, 0)
						root.Anchored = true
						self.IsAnchoredAtPost = true
						print("[DEBUG] REACHED POST SPOT -> Anchored RootPart at:", hoverPos)
					end
				end
			end
		else
			self.CurrentEnemy = nil
			self.LockPosition = nil
			self.MoveState.waypoints = nil
			self.MoveState.velocity = Vector3.zero
			if root.Anchored then
				root.Anchored = false
				self.IsAnchoredAtPost = false
				print("[DEBUG] No Enemy -> Unanchored RootPart.")
			end
		end
	end)
end

function PathfindingModule:StopPathfinding()
	if self.State then
		self.State.Navigating = false
	end

	print("[DEBUG] Stopped Pathfinding")

	self.CurrentEnemy = nil
	self.LockPosition = nil
	self.MoveState.done = true
	self.MoveState.waypoints = nil
	self.MoveState.velocity = Vector3.new()

	if self.MoveConnection then
		self.MoveConnection:Disconnect()
		self.MoveConnection = nil
	end

	local char = self.Player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		root.AssemblyLinearVelocity = Vector3.zero
		if root.Anchored then
			root.Anchored = false
			self.IsAnchoredAtPost = false
			print("[DEBUG] Stopped Pathfinding -> Unanchored RootPart.")
		end
	end
end

return PathfindingModule
