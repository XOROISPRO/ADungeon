--!strict
local AbilityModule = {}
AbilityModule.__index = AbilityModule

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local VirtualInputManager = game:GetService("VirtualInputManager")

function AbilityModule.Init(State: any, Toggles: any, Options: any)
	local self = setmetatable({}, AbilityModule)

	self.State = State
	self.Toggles = Toggles
	self.Options = Options
	self.Player = Players.LocalPlayer
	self.Running = false

	-- Threads for independent ability execution
	self.QThread = nil :: thread?
	self.EThread = nil :: thread?
	self.SpamThread = nil :: thread?

	-- Configurations
	self.Mode = "Cycle" -- "Cycle" or "Spam"
	self.SpamInterval = 0.1

	return self
end

-- Helper: Simulate keypress
local function pressKey(keyCode: Enum.KeyCode)
	VirtualInputManager:SendKeyEvent(true, keyCode, false, game)
	task.wait(0.05)
	VirtualInputManager:SendKeyEvent(false, keyCode, false, game)
end

-- UI Readers
function AbilityModule:IsBusyCasting(): boolean
	local char = self.Player.Character
	if char then
		local busyVal = char:FindFirstChild("busyCasting")
		if busyVal and busyVal:IsA("BoolValue") then
			return busyVal.Value
		end
	end
	
	-- Fallback check in workspace root for character model
	local charModel = Workspace:FindFirstChild(self.Player.Name)
	if charModel then
		local busyVal = charModel:FindFirstChild("busyCasting")
		if busyVal and busyVal:IsA("BoolValue") then
			return busyVal.Value
		end
	end

	return false
end

function AbilityModule:WaitUntilNotBusy()
	while self.Running and self:IsBusyCasting() do
		task.wait(0.05)
	end
end

function AbilityModule:GetCooldown(abilityType: "Q" | "E"): number
	local pgui = self.Player:FindFirstChild("PlayerGui")
	if not pgui then return 999 end

	local abilities = pgui:FindFirstChild("abilities")
	if not abilities then return 999 end

	local frame = abilities:FindFirstChild("Frame")
	if not frame then return 999 end

	local slotName = (abilityType == "Q") and "LeftAbility" or "RightAbility"
	local abilitySlot = frame:FindFirstChild(slotName)
	if not abilitySlot then return 999 end

	local slot = abilitySlot:FindFirstChild("slot")
	local cdNum = slot and slot:FindFirstChild("cooldownNumber") :: TextLabel?

	if cdNum then
		local num = tonumber(cdNum.Text)
		return num or 0.0
	end

	return 0.0
end

-- Individual Ability Handler (Runs independently per key)
function AbilityModule:RunIndependentAbility(key: Enum.KeyCode, abilityType: "Q" | "E")
	while self.Running and self.Mode == "Cycle" do
		-- 1. Wait until the specific ability's cooldown reaches 0.0
		if self:GetCooldown(abilityType) <= 0 then
			-- 2. Wait until character finishes any active casting state
			if not self:IsBusyCasting() then
				pressKey(key)
				task.wait(0.1)
				-- 3. Block this specific thread until casting finishes
				self:WaitUntilNotBusy()
			end
		end
		task.wait(0.05)
	end
end

-- Core Execution Logic
function AbilityModule:Start()
	if self.Running then return end
	self.Running = true

	if self.Mode == "Cycle" then
		-- Spawn Q independent loop
		self.QThread = task.spawn(function()
			self:RunIndependentAbility(Enum.KeyCode.Q, "Q")
		end)

		-- Spawn E independent loop
		self.EThread = task.spawn(function()
			self:RunIndependentAbility(Enum.KeyCode.E, "E")
		end)
	elseif self.Mode == "Spam" then
		self.SpamThread = task.spawn(function()
			while self.Running and self.Mode == "Spam" do
				if not self:IsBusyCasting() then
					if self:GetCooldown("Q") <= 0 then
						pressKey(Enum.KeyCode.Q)
					end
					if self:GetCooldown("E") <= 0 then
						pressKey(Enum.KeyCode.E)
					end
				end
				task.wait(self.SpamInterval)
			end
		end)
	end
end

function AbilityModule:Stop()
	self.Running = false
	
	if self.QThread then
		task.cancel(self.QThread)
		self.QThread = nil
	end
	if self.EThread then
		task.cancel(self.EThread)
		self.EThread = nil
	end
	if self.SpamThread then
		task.cancel(self.SpamThread)
		self.SpamThread = nil
	end
end

function AbilityModule:SetMode(mode: string)
	local wasRunning = self.Running
	self:Stop()
	self.Mode = mode
	if wasRunning then
		self:Start()
	end
end

function AbilityModule:SetSpamInterval(interval: number)
	self.SpamInterval = interval
end

return AbilityModule
