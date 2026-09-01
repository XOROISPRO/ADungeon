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
	self.Thread = nil :: thread?

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
	
	-- Fallback check in workspace.jotla18
	local jotla = Workspace:FindFirstChild(self.Player.Name)
	if jotla then
		local busyVal = jotla:FindFirstChild("busyCasting")
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

function AbilityModule:WaitUntilCooldownReady(abilityType: "Q" | "E")
	while self.Running and self:GetCooldown(abilityType) > 0 do
		task.wait(0.05)
	end
end

-- Core Logic
function AbilityModule:Start()
	if self.Running then return end
	self.Running = true

	self.Thread = task.spawn(function()
		while self.Running do
			if self.Mode == "Cycle" then
				-- Step 1: Wait for Q cooldown to hit 0.0
				self:WaitUntilCooldownReady("Q")
				if not self.Running then break end

				-- Press Q
				pressKey(Enum.KeyCode.Q)
				task.wait(0.1)

				-- Wait until busyCasting is false
				self:WaitUntilNotBusy()
				if not self.Running then break end

				-- Step 2: Check/Wait for E cooldown to hit 0.0
				self:WaitUntilCooldownReady("E")
				if not self.Running then break end

				-- Press E
				pressKey(Enum.KeyCode.E)
				task.wait(0.1)

				-- Wait until busyCasting is false again
				self:WaitUntilNotBusy()

			elseif self.Mode == "Spam" then
				-- Press Q & E together if available and not casting
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
			task.wait(0.05)
		end
	end)
end

function AbilityModule:Stop()
	self.Running = false
	if self.Thread then
		task.cancel(self.Thread)
		self.Thread = nil
	end
end

function AbilityModule:SetMode(mode: string)
	self.Mode = mode
end

function AbilityModule:SetSpamInterval(interval: number)
	self.SpamInterval = interval
end

return AbilityModule
