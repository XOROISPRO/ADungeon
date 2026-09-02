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
	self.QThread = nil :: thread?
	self.EThread = nil :: thread?
	self.SpamThread = nil :: thread?
	self.Mode = "Cycle"
	self.SpamInterval = 0.1

	return self
end

-- Map Roblox KeyCodes to Virtual Key Codes (VK Codes) for Executor keypress functions
local VK_CODES = {
	[Enum.KeyCode.Q] = 0x51,
	[Enum.KeyCode.E] = 0x45,
}

-- Key press simulator supporting Solara & VirtualInputManager
local function pressKey(keyCode: Enum.KeyCode)
	pcall(function()
		-- 1. Try Executor Native keypress/keyrelease using Virtual Key Codes
		if typeof(keypress) == "function" and typeof(keyrelease) == "function" then
			local vkCode = VK_CODES[keyCode] or keyCode.Value
			keypress(vkCode)
			task.wait(0.03)
			keyrelease(vkCode)
			return
		end

		-- 2. Fallback: VirtualInputManager
		VirtualInputManager:SendKeyEvent(true, keyCode, false, game)
		task.wait(0.03)
		VirtualInputManager:SendKeyEvent(false, keyCode, false, game)
	end)
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

-- Independent Ability Loop (Cycle Mode)
function AbilityModule:RunIndependentAbility(key: Enum.KeyCode, abilityType: "Q" | "E")
	while self.Running and self.Mode == "Cycle" do
		if self:GetCooldown(abilityType) <= 0 then
			if not self:IsBusyCasting() then
				pressKey(key)
				task.wait(0.15)
				self:WaitUntilNotBusy()
			end
		end
		task.wait(0.05)
	end
end

function AbilityModule:Start()
	if self.Running then return end
	self.Running = true

	if self.Mode == "Cycle" then
		self.QThread = task.spawn(function()
			self:RunIndependentAbility(Enum.KeyCode.Q, "Q")
		end)
		self.EThread = task.spawn(function()
			self:RunIndependentAbility(Enum.KeyCode.E, "E")
		end)
	elseif self.Mode == "Spam" then
		self.SpamThread = task.spawn(function()
			while self.Running and self.Mode == "Spam" do
				pressKey(Enum.KeyCode.Q)
				task.wait(0.02)
				pressKey(Enum.KeyCode.E)
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
