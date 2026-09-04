--!strict
local PathfindingModule = {}
PathfindingModule.__index = PathfindingModule

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")
local UserInputService = game:GetService("UserInputService")
print("Version2.2")
function PathfindingModule.Init(State: any, Toggles: any)
	local self = setmetatable({}, PathfindingModule)
	self.State = State
	self.Toggles = Toggles
	self.Player = Players.LocalPlayer

	-- Physics & Position Parameters
	self.MAX_SPEED = 35
	self.UNFOCUSED_MULTIPLIER = 1.5 -- Default 1.5x speed boost when unfocused
	self.HOVER_HEIGHT = 9
	self.ENGAGE_DISTANCE = 15
	self.OFFSET_DISTANCE = 3
	self.POST_MODE = true
	self.BOSS_MODE = false

	-- Drift & Arrival Thresholds
	self.MAX_DRIFT_DISTANCE_NORMAL = 5.0
	self.MAX_DRIFT_DISTANCE_BOSS = 3.0
	self.ARRIVAL_DISTANCE_NORMAL = 3.5
	self.ARRIVAL_DISTANCE_BOSS = 2.0

	-- Speed Anomaly Thresholds
	self.SPEED_ANOMALY_THRESHOLD = 250

	-- Window Focus Tracking
	self.IsUnfocused = false
	self.FocusConnections = {}

	-- Track Window Focus Events
	table.insert(self.FocusConnections, UserInputService.WindowFocusReleased:Connect(function()
		self.IsUnfocused = true
		print("[DEBUG] Window lost focus -> Applied unfocused speed multiplier.")
	end))

	table.insert(self.FocusConnections, UserInputService.WindowFocused:Connect(function()
		self.IsUnfocused = false
		print("[DEBUG] Window focused -> Reset to base speed.")
	end))

	-- Active Target & Static Post Tracking
	self.CurrentEnemy = nil :: BasePart?
	self.LockPosition = nil :: Vector3?
	self.IsAnchoredAtPost = false
	self.IsAtPost = false

	self.MoveState = {
		waypoints = nil :: {PathWaypoint}?,
		waypointIndex = 1,
		lastComputeTime = 0,
		done = true,
	}

	self.MoveConnection = nil :: RBXScriptConnection?
	self.LastDebugPrint = 0

	return self
end

-- Set Unfocused Multiplier via UI
function PathfindingModule:SetUnfocusedMultiplier(mult: number)
	self.UNFOCUSED_MULTIPLIER = mult
	print("[DEBUG] Unfocused Multiplier Set To ->", mult)
end

-- Calculates effective max speed based on window focus state
function PathfindingModule:GetEffectiveSpeed(): number
	if self.IsUnfocused then
		return self.MAX_SPEED * self.UNFOCUSED_MULTIPLIER
	end
	return self.MAX_SPEED
end

-- Direct Step Movement with Dynamic Focus Speed Scaling
function PathfindingModule:StepMovement(root: BasePart, wishDir: Vector3, wishSpeed: number, targetYVelocity: number)
	if root.Anchored then
		root.Anchored = false
		self.IsAnchoredAtPost = false
		print("[DEBUG] Unanchored RootPart for movement step.")
	end

	local effectiveMaxSpeed = self:GetEffectiveSpeed()
	local activeSpeed = math.min(wishSpeed, effectiveMaxSpeed)
	local targetVel = wishDir * activeSpeed
	local clampedY = math.clamp(targetYVelocity, -self.MAX_AIR_VELOCITY or -25, self.MAX_AIR_VELOCITY or 25)

	root.AssemblyLinearVelocity = Vector3.new(targetVel.X, clampedY, targetVel.Z)
end

function PathfindingModule:IsAtPostPosition(): boolean
	return self.IsAtPost
end

function PathfindingModule:SetHoverHeight(height: number)
	self.HOVER_HEIGHT = height
end

function PathfindingModule:SetWalkSpeed(speed: number)
	self.MAX_SPEED = speed
end

function PathfindingModule:SetAirVelocity(maxAirVel: number)
	self.MAX_AIR_VELOCITY = maxAirVel
end

function PathfindingModule:SetAirAccel(airAccel: number)
	self.AIR_ACCEL = airAccel
end

function PathfindingModule:SetOffsetDistance(offset: number)
	self.OFFSET_DISTANCE = offset
end

function PathfindingModule:SetPostMode(enabled: boolean)
	self.POST_MODE = enabled
	if not enabled then
		self.LockPosition = nil
		self.IsAtPost = false
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

function PathfindingModule:SetBossMode(enabled: boolean)
	self.BOSS_MODE = enabled
	self.LockPosition = nil
	self.CurrentEnemy = nil
	self.IsAtPost = false
	local char = self.Player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root and root.Anchored then
		root.Anchored = false
		self.IsAnchoredAtPost = false
	end
	print("[DEBUG] BOSS_MODE Toggled ->", self.BOSS_MODE)
end

function PathfindingModule:IsBossEnemy(target: BasePart?): boolean
	if not target or not target.Parent then return false end

	local dungeon = Workspace:FindFirstChild("dungeon")
	local bossRoom = dungeon and dungeon:FindFirstChild("bossRoom")
	local enemyFolder = bossRoom and bossRoom:FindFirstChild("enemyFolder")

	if not enemyFolder then return false end

	return target:IsDescendantOf(enemyFolder)
end

function PathfindingModule:IsInBossRoom(root: BasePart): boolean
	local dungeon = Workspace:FindFirstChild("dungeon")
	if not dungeon then return false end

	local bossRoom = dungeon:FindFirstChild("bossRoom")
	if not bossRoom then return false end

	if bossRoom:IsA("Model") then
		local roomCFrame, roomSize = bossRoom:GetBoundingBox()
		local localPos = roomCFrame:PointToObjectSpace(root.Position)
		local halfSize = roomSize * 0.5
		return math.abs(localPos.X) <= halfSize.X and math.abs(localPos.Z) <= halfSize.Z
	end

	return false
end

function PathfindingModule:GetBossEnemy(): BasePart?
	local dungeon = Workspace:FindFirstChild("dungeon")
	if not dungeon then return nil end

	local bossRoom = dungeon:FindFirstChild("bossRoom")
	if not bossRoom then return nil end

	local enemyFolder = bossRoom:FindFirstChild("enemyFolder")
	if not enemyFolder then return nil end

	for _, child in pairs(enemyFolder:GetChildren()) do
		if child:IsA("Model") then
			local bossHum = child:FindFirstChildOfClass("Humanoid")
			local bossRoot = child:FindFirstChild("HumanoidRootPart") :: BasePart?
			if bossRoot and bossHum and bossHum.Health > 0 then
				return bossRoot
			end
		end
	end
	return nil
end

function PathfindingModule:GetClosestEnemy(): (BasePart?, boolean)
	local char = self.Player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return nil, false end

	local inBossRoom = self:IsInBossRoom(root)
	if self.BOSS_MODE and inBossRoom then
		local bossRoot = self:GetBossEnemy()
		if bossRoot then
			if self.CurrentEnemy ~= bossRoot then
				self.CurrentEnemy = bossRoot
				self.LockPosition = nil
				self.IsAtPost = false
			end
			return bossRoot, true
		end
	end

	if self.CurrentEnemy and self.CurrentEnemy.Parent then
		local parentModel = self.CurrentEnemy.Parent
		local hum = parentModel:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 then
			local isBoss = self:IsBossEnemy(self.CurrentEnemy)
			return self.CurrentEnemy, isBoss
		end
	end

	if self.CurrentEnemy then
		print("[DEBUG] Target died/lost. Clearing target & unanchoring.")
	end

	self.CurrentEnemy = nil
	self.LockPosition = nil
	self.IsAtPost = false

	if root.Anchored then
		root.Anchored = false
		self.IsAnchoredAtPost = false
	end

	local dungeon = Workspace:FindFirstChild("dungeon")
	if not dungeon then return nil, false end

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

	self.CurrentEnemy = closestEnemyPart
	local isBoss = self:IsBossEnemy(closestEnemyPart)

	if closestEnemyPart then
		local enemyName = closestEnemyPart.Parent and closestEnemyPart.Parent.Name or "Unknown"
		print(string.format("[DEBUG] New Enemy Found -> %s | IsBoss: %s", enemyName, tostring(isBoss)))
	end

	return closestEnemyPart, isBoss
end

local function faceDownward(root: BasePart)
	local currentPos = root.Position
	root.CFrame = CFrame.new(currentPos) * CFrame.Angles(-math.rad(90), 0, 0)
end

function PathfindingModule:GetGroundWishDir(root: BasePart, targetPos: Vector3): Vector3
	local state = self.MoveState
	local currentTime = os.clock()

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

function PathfindingModule:RestartPathing()
	print("[WARNING] Speed anomaly detected! Resetting pathing...")
	self:StopPathfinding()
	task.wait(0.05)
	self:StartHoverTargeting()
end

function PathfindingModule:StartHoverTargeting()
	self:StopPathfinding()

	local char = self.Player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not char or not root then return end

	self.State.Navigating = true
	self.MoveState.done = false
	print("[DEBUG] Started Targeting")

	self.MoveConnection = RunService.Heartbeat:Connect(function(dt)
		if not self.State.Navigating or not root or not char then return end

		local currentSpeed = root.AssemblyLinearVelocity.Magnitude
		if currentSpeed > self.SPEED_ANOMALY_THRESHOLD then
			print(string.format("[WARNING] Speed Anomaly Detected: %.2f studs/s! Triggering reset.", currentSpeed))
			self:RestartPathing()
			return
		end

		local enemyRoot, isBoss = self:GetClosestEnemy()
		if enemyRoot then
			local currentPos = root.Position
			local enemyPos = enemyRoot.Position
			local now = os.clock()

			-- Calculate thresholds (widen slightly when unfocused to avoid arrival jitter at low FPS)
			local focusScalar = self.IsUnfocused and 1.3 or 1.0
			local maxDriftDist = (isBoss and self.MAX_DRIFT_DISTANCE_BOSS or self.MAX_DRIFT_DISTANCE_NORMAL) * focusScalar
			local arrivalDist = (isBoss and self.ARRIVAL_DISTANCE_BOSS or self.ARRIVAL_DISTANCE_NORMAL) * focusScalar
			local effectiveSpeed = self:GetEffectiveSpeed()

			if self.LockPosition then
				local postDelta = self.LockPosition - currentPos
				local distToLock = isBoss 
					and Vector3.new(postDelta.X, 0, postDelta.Z).Magnitude 
					or postDelta.Magnitude

				if (now - self.LastDebugPrint) > 0.5 then
					self.LastDebugPrint = now
					local enemyTypeStr = isBoss and "BOSS" or "NORMAL ENEMY"
					print(string.format("[%s ACTIVE] DistToLock: %.2f | Unfocused: %s | EffectiveSpeed: %.1f | Anchored: %s",
						isBoss and "BOSS MODE" or "POST",
						distToLock,
						tostring(self.IsUnfocused),
						effectiveSpeed,
						tostring(root.Anchored)
					))
				end

				-- Anti-drift pull-back: Speed scales dynamically with effective speed
				if distToLock > maxDriftDist then
					self.IsAtPost = false
					if root.Anchored then
						root.Anchored = false
						self.IsAnchoredAtPost = false
					end
					if not isBoss then
						faceDownward(root)
					end
					
					local dynamicCorrection = (distToLock / math.max(dt, 0.016))
					local correctionSpeed = math.clamp(dynamicCorrection, effectiveSpeed, effectiveSpeed * 2.5)
					root.AssemblyLinearVelocity = postDelta.Unit * correctionSpeed
					return
				end

				-- Snap & Anchor
				if distToLock <= arrivalDist then
					root.AssemblyLinearVelocity = Vector3.zero
					self.IsAtPost = true

					if isBoss then
						local currentRotation = root.CFrame - root.CFrame.Position
						root.CFrame = CFrame.new(self.LockPosition.X, currentPos.Y, self.LockPosition.Z) * currentRotation
					else
						faceDownward(root)
						root.CFrame = CFrame.new(self.LockPosition) * CFrame.Angles(-math.rad(90), 0, 0)
					end

					if not root.Anchored then
						root.Anchored = true
						self.IsAnchoredAtPost = true
						print(string.format("[DEBUG] ANCHORED AT POST SPOT -> %s (EnemyType: %s)", tostring(root.Position), isBoss and "BOSS" or "NORMAL"))
					end
				else
					self.IsAtPost = false
					if root.Anchored then
						root.Anchored = false
						self.IsAnchoredAtPost = false
					end
					if not isBoss then
						faceDownward(root)
					end
					local wishDir = postDelta.Unit
					local targetYVel = isBoss and 0 or (wishDir.Y * effectiveSpeed)
					self:StepMovement(root, Vector3.new(wishDir.X, 0, wishDir.Z), effectiveSpeed, targetYVel)
				end
				return
			end

			-- Pathing / Target approach
			self.IsAtPost = false
			local flatDelta = Vector3.new(enemyPos.X - currentPos.X, 0, enemyPos.Z - currentPos.Z)
			if flatDelta.Magnitude > self.ENGAGE_DISTANCE then
				local wishDir = self:GetGroundWishDir(root, enemyPos)
				self:StepMovement(root, wishDir, effectiveSpeed, root.AssemblyLinearVelocity.Y)
			else
				if isBoss then
					self.LockPosition = Vector3.new(enemyPos.X, currentPos.Y, enemyPos.Z)
					print("[DEBUG] BOSS POSITION REACHED -> LOCKED POST (X/Z only) AT:", self.LockPosition)
				else
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
				end
			end
		else
			self.CurrentEnemy = nil
			self.LockPosition = nil
			self.IsAtPost = false
			self.MoveState.waypoints = nil
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
	self.IsAtPost = false
	self.MoveState.done = true
	self.MoveState.waypoints = nil

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
