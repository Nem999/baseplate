-- @Author: NemPaws
-- @Created: 10/7/24
-- @Description: Replaces default backpack
-- Released under the MIT license.

--[[ SERVICES ]]--
local UserInputService = game:GetService("UserInputService")
local StarterGuiService = game:GetService("StarterGui")
local PlayersService = game:GetService("Players")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")

--[[ MODULES ]]--
local Spring = require(script:WaitForChild("Spring"))
local Signal = require(game.ReplicatedStorage.Lib.Signal)
local DragDetector = require(script:WaitForChild("UIDrag")) -- Unfortantely we cannot use UI drag detectors because they do not play well with buttons at the time of writing this.

--[[ CONSTANTS ]]--
local BackpackSlots = {}
local HotbarSlots = {}
local GluedSlots = {}
local Backpack = {}

--[[ SETTINGS ]]--
Backpack.Settings = require(script.BackpackSettings)

--*/ Don't touch */--
local SlotChangedSignal = Signal.new()
local ToolTipChangedSignal = Signal.new()
local HoverStartedInternal = Signal.new()
local HoverEndedInternal = Signal.new()

local LocalPlayer = PlayersService.LocalPlayer
local MaxSlotsInternal = Backpack.Settings.MaxHotbarToolSlots
local ScreenGui = LocalPlayer:WaitForChild("PlayerGui"):WaitForChild("Backpack")
local BackpackGui = ScreenGui.BackpackGui

local MaxGluedSlots = 3
local InvAnimation = 1

local HighlightedTools = {}
local ActiveCooldowns = {}
local UISelectedSlots = {}
local EquippedTools = {}
local RemappedSlots = {}

local doesHaveEquipCooldown = false
local InventoryIsDisabled = false
local BackpackIsDisabled = false
local InventoryIsOpen = false
local BackpackStarted = false
local InvCooldown = false
local isSearching = false
local Locked = false

local lastScrollWheelPosition = nil
local BackgroundTransparency = nil
local BackpackSlotFrame = nil
local BackpackInstance = nil
local SelectionUIFrame = nil
local LastSelectedObj = nil
local NextSweepThread = nil
local InventoryFrame = nil
local ToolTipSignal = nil
local BPConnection = nil
local ToolTipFrame = nil
local Character = nil
local Humanoid = nil
local BPButton = nil

local KEYBOARD_TRANSLATIONS = {
	["One"] = 1,
	["Two"] = 2,
	["Three"] = 3,
	["Four"] = 4,
	["Five"] = 5,
	["Six"] = 6,
	["Seven"] = 7,
	["Eight"] = 8,
	["Nine"] = 9,
	["Zero"] = 10,
}

--[[ PUBLIC CONNECTIONS ]]--
Backpack.InventoryOpened = Signal.new()
Backpack.InventoryClosed = Signal.new()

Backpack.HoverStarted = Signal.new() --> [Instance](Slot)
Backpack.HoverEnded = Signal.new() --> [Instance](Slot)

Backpack.ToolRemoving = Signal.new() --> [Instance](Tool) [Instance](Slot), [Instance](Ghost Slot)
Backpack.ToolAdded = Signal.new() --> [Instance](Tool), [Instance](Slot)

Backpack.DragStarted = Signal.new() --> [Instance](Tool) [Instance](Slot), [Instance](Ghost Slot), isController(boolean)
Backpack.DragEnded = Signal.new()  --> [Instance](Tool) [Instance](Slot), [Instance](Ghost Slot), isController(boolean), Position

Backpack.CooldownEnded = Signal.new() --> [Instance](Tool), [Instance](Slot)

--[[ FUNCTIONS ]]--
local spawn = task.spawn
local delay = task.delay
local defer = task.defer
local wait = task.wait

local rbxerror = error
local rbxwarn = warn

local function warn(warning)
	rbxwarn("[BackpackScript]:", warning)
end

local function error(err)
	rbxerror("[BackpackScript]: "..err, 0)
end

local function isModuleRunning()
	if not BackpackStarted then error("Call .StartBackpack() before using this method.") end
end

local function waitForChildOfClass(ClassName, inst : Instance)
	local waiting = true

	local function wait()

		if inst:FindFirstChildOfClass(ClassName) then
			waiting = false
			return inst:FindFirstChildOfClass(ClassName)
		end

		inst.ChildAdded:Wait()

		return wait()
	end

	local Child

	delay(3, function()
		if waiting == true then
			warn("Infinite yield possible on waitForChildOfClass: "..debug.traceback())
		end
	end)

	Child = wait()

	return Child
end

function SetBackpack(BackpackInst : Backpack)
	if typeof(BackpackInst) ~= "Instance" or not BackpackInst:IsA("Backpack") or BackpackInst.Parent ~= LocalPlayer then error("Invalid backpack please don't parent instances named 'Backpack' that aren't actually backpacks to the LocalPlayer.'") end
	if BackpackInstance then resetBackpack() end
	if BPConnection then BPConnection:Disconnect() end

	BackpackInstance = BackpackInst
	BPConnection = BackpackInst.ChildAdded:Connect(newSlot)

	for _, Tool in pairs(BackpackInst:GetChildren()) do
		if not Tool:IsA("Tool") then continue end

		newSlot(Tool)
	end

	if LocalPlayer.Character then
		for _, Tool in pairs(LocalPlayer.Character:GetChildren()) do
			if not Tool:IsA("Tool") then continue end

			newSlot(Tool)
		end
	end
end

function CharacterAdded(char : Model)
	Character = char
	Humanoid = char:WaitForChild("Humanoid")

	char.ChildAdded:Connect(newSlot)

	SetBackpack(waitForChildOfClass("Backpack", LocalPlayer))
end

function getCameraOffset(fov, extentsSize)
	local halfSize = extentsSize.Magnitude / 2
	local fovDivisor = math.tan(math.rad(fov / 2))
	return halfSize / fovDivisor
end

function zoomToExtents(camera, instance) -- ty thegamer101
	local isModel = instance:IsA("Model")

	local instanceCFrame = isModel and instance:GetModelCFrame() or instance.CFrame
	local extentsSize = isModel and instance:GetExtentsSize() or instance.Size

	local cameraOffset = getCameraOffset(camera.FieldOfView, extentsSize)
	local cameraRotation = camera.CFrame - camera.CFrame.p

	local instancePosition = instanceCFrame.p
	camera.CFrame = cameraRotation + instancePosition + (-cameraRotation.LookVector * cameraOffset)
	camera.Focus = cameraRotation + instancePosition
end

function advanceCanvasToPosition(ScrollingFrame: ScrollingFrame, GuiObject: GuiObject)
	local scrollingframeabs = ScrollingFrame.AbsolutePosition
	local currentCanvasPosition = ScrollingFrame.CanvasPosition
	local guiObjectAbsolutePosition = GuiObject.AbsolutePosition

	local difference = guiObjectAbsolutePosition - scrollingframeabs

	local prev = ScrollingFrame.CanvasPosition

	ScrollingFrame.CanvasPosition += difference

	return prev
end

function isToolRegistered(Tool)
	for _, Slot in pairs(HotbarSlots) do
		if Slot.Tool == Tool then
			return true
		end
	end

	for _, Slot in pairs(GluedSlots) do 	
		if Slot.Tool == Tool then
			return true
		end
	end

	for _, Slot in pairs(BackpackSlots) do
		if Slot.Tool == Tool then
			return true
		end
	end

	return false
end

function isClipped(uiObject: GuiObject, clipping)
	local parent = clipping
	local boundryTop = parent.AbsolutePosition
	local boundryBot = boundryTop + parent.AbsoluteSize 

	local top = uiObject.AbsolutePosition + Vector2.new(0, uiObject.Size.Y.Offset)
	local bot = top + uiObject.AbsoluteSize - (Vector2.new(0, uiObject.Size.Y.Offset) * 2)

	local function cmpVectors(a, b) -- Compare is a is above or to the left of b
		return (a.X < b.X) or (a.Y < b.Y)
	end

	return cmpVectors(top, boundryTop) or cmpVectors(boundryBot, bot), (boundryBot.Y - bot.Y)
end

function HoverStart(ToolSlot) -- <-- Old code but whatever
	local Previous
	local ToolTip = ToolSlot.Tool.ToolTip
	local Text = string.split(ToolTip, "")


	if ToolSlot.ToolTipFrame then ToolSlot.ToolTipFrame.Parent:Destroy() end

	ToolSlot.ToolTipFrame = ToolTipFrame:Clone()
	ToolSlot.ToolTipFrame.LayoutOrder = 1
	ToolSlot.ToolTipFrame.Name = "_ToolTip"
	ToolSlot.ToolTipFrame.Visible = true

	local Frame = create("Frame", {
		Size = BackpackSlotFrame.Size,
		AnchorPoint = BackpackSlotFrame.AnchorPoint,
		BackgroundTransparency = 1,
		Parent = BackpackGui.ToolTips,
		["Children"] = {
			create("Frame", {
				Size = UDim2.fromOffset(1,1),
				BackgroundTransparency = 1,
				Name = "",
				LayoutOrder = 0
			}),
			create("UIListLayout", {
				Padding = UDim.new(0, -40),
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment = Enum.VerticalAlignment.Top
			}),
			ToolSlot.ToolTipFrame,
		}
	})


	spawn(function()
		while true do
			wait()

			if not ToolSlot.Tool or not ToolSlot.ToolTipFrame then
				break
			end

			Frame.Position = UDim2.fromOffset(ToolSlot.Frame.AbsolutePosition.X + GuiService:GetGuiInset().X, ToolSlot.Frame.AbsolutePosition.Y + GuiService:GetGuiInset().Y ) 
		end
	end)

	Animate(ToolSlot.ToolTipFrame.TipText, "BackgroundTransparency", 0, 1, 11)

	local Previous = nil
	ToolSlot.TipRemoving = nil
	local TempSignal = os.clock()

	if ToolTipSignal then ToolTipSignal:Disconnect() end

	local function showToolTip()
		if Backpack.Settings.Animate == true then
			spawn(function()
				local willDisconnect = TempSignal
				Previous = nil

				for i,v in ipairs(Text) do
					if not Previous then Previous = "" end
					if not ToolSlot or not ToolSlot.ToolTipFrame then return end 
					if ToolSlot.TipRemoving then return end
					if willDisconnect ~= TempSignal then return end

					local x = "_"

					if i == #Text then x = "" end

					ToolSlot.ToolTipFrame.TipText.Text = Previous..v..x
					Previous = Previous..v

					wait(.035)
				end

				if ToolSlot and ToolSlot.ToolTipFrame and ToolSlot.Tool then
					ToolSlot.ToolTipFrame.TipText.Text = ToolTip
				end
			end)

		else
			if ToolSlot and ToolSlot.ToolTipFrame and ToolSlot.Tool  then
				ToolSlot.ToolTipFrame.TipText.Text = ToolTip
			end
		end
	end

	ToolTipSignal = ToolTipChangedSignal:Connect(function(Slot)
		if Slot == ToolSlot then
			TempSignal = os.clock()
			ToolTip = Slot.Tool.ToolTip
			Text = string.split(ToolTip, "")
			ToolSlot.ToolTipFrame.TipText.Text = ""

			if ToolTip == "" then HoverEnd(Slot) return end

			showToolTip()
		end
	end)

	showToolTip()

end

function HoverEnd(ToolSlot)
	if not ToolSlot.ToolTipFrame then return end

	Animate(ToolSlot.ToolTipFrame.TipText, "BackgroundTransparency", 1, 1, 11)
	Animate(ToolSlot.ToolTipFrame.TipText.UIStroke, "Transparency", 1, 1, 11)
	Animate(ToolSlot.ToolTipFrame.TipText, "TextTransparency", 1, 1, 11)


	local ToolFrame = ToolSlot.ToolTipFrame
	ToolSlot.TipRemoving = true

	if ToolTipSignal then ToolTipSignal:Disconnect() end

	if Backpack.Settings.Animate == true then
		Spring.completed(ToolSlot.ToolTipFrame.TipText, function()
			if ToolFrame.Parent ~= nil then
				ToolFrame.Parent:Destroy()

				ToolSlot.ToolTipFrame = nil
				ToolSlot.TipRemoving = nil
			end
		end)
	else
		if ToolFrame.Parent ~= nil then
			ToolFrame.Parent:Destroy()
			ToolSlot.ToolTipFrame = nil
			ToolSlot.TipRemoving = nil
		end
	end
end

function create(className : string, properties : {[string]:any})

	local Prop = Instance.new(className)

	for property, val in pairs(properties) do

		if property == "Children" then 
			for _, Child in pairs(val) do
				Child.Parent = Prop
			end	

			continue
		end


		Prop[property] = val
	end

	return Prop
end

function onParentUpdate(Tool, Parent, ForceRemove)
	if not LocalPlayer:IsDescendantOf(PlayersService) then return end -- Need this check or else a bunch of errors are spit out when the game is shutting down

	local ToolSlot = Backpack:GetSlotFromTool(Tool)
	local Frame = ToolSlot.Frame.Button

	if Parent ~= Character and Parent ~= BackpackInstance or ForceRemove then
		-- Player has lost control of the tool disconnect all connections


		for _, Highlight in pairs(HighlightedTools) do
			if Highlight.Frame == Frame.Parent then
				MoveEquipBar(false, ToolSlot.Frame, 0)
				break
			end
		end

		local GhostSlot: Frame = Frame.Parent:Clone()

		Backpack.ToolRemoving:Fire(Tool, ToolSlot.Frame, GhostSlot)

		ToolSlot.Tool = nil
		ToolSlot.Locked = false

		if ToolSlot.PlacementSlot and not ToolSlot.Glued then
			ToolSlot.PlacementSlot.Visible = false
		end

		ToolSlot.Frame.Tool.Value = nil
		table.clear(ToolSlot.Connections)

		ToolSlot.Loaded = false

		local Visiblity = ToolSlot.Frame.Visible

		deleteToolSlotData(ToolSlot)


		GhostSlot.Name = "_Ghost"
		GhostSlot.Visible = true
		GhostSlot.Button.Parent = GhostSlot.Group
		GhostSlot.Parent = BackpackGui.BackpackMain
		GhostSlot.ZIndex -= 1

		MoveEquipBar(false)

		if EquippedTools[Tool] then
			EquippedTools[Tool] = nil
		end

		if ToolSlot.PlacementSlot then
			Animate(GhostSlot, "Position", UDim2.fromOffset(GhostSlot.AbsolutePosition.X, GhostSlot.AbsolutePosition.Y + 200), .7, 2)

			spawn(function()
				while ToolSlot.IsAnimating do wait() end

				if not InventoryIsOpen then
					Frame.Parent.Visible = false
				end
			end)

			if Backpack.Settings.Animate == true then
				Spring.completed(GhostSlot, function()
					GhostSlot:Destroy()
				end)
			else
				GhostSlot:Destroy()
			end

			if InventoryIsOpen then revealSlots(true) end
		else

			ToolSlot.Frame.Group.GroupTransparency = 1
			ToolSlot.Frame.Button.Visible = false
			ToolSlot.Frame.Visible = true

			if Visiblity == false then
				ToolSlot.Frame.Visible = false
				GhostSlot.Visible = false
			end

			GhostSlot.Parent = InventoryFrame.Parent
			GhostSlot.Group.GroupTransparency = 0

			GhostSlot.Position = UDim2.fromOffset(ToolSlot.Frame.AbsolutePosition.X + GuiService:GetGuiInset().X, ToolSlot.Frame.AbsolutePosition.Y + GuiService:GetGuiInset().Y)

			delay(.28, function()
				if not ToolSlot.Frame.Tool.Value and InventoryIsOpen then
					ToolSlot.Frame.Visible = false
				end
			end)

			Animate(GhostSlot.Group, "GroupTransparency", 1, 1.3, 9)
			Animate(GhostSlot.Group.Button, "Position", UDim2.fromScale(0, .9), 1.3, 9)

			if Backpack.Settings.Animate == true then
				Spring.completed(GhostSlot.Group, function()
					GhostSlot:Destroy()
				end)
			else
				GhostSlot:Destroy()
			end

		end

		if Backpack.Settings.AutoSortSlots then
			Backpack:SortTools()
		end
	end
end

function resetBackpack()
	for _, ToolSlot in pairs(HotbarSlots) do
		local Tool = ToolSlot.Tool 

		if Tool then
			onParentUpdate(Tool, nil, true) -- Free the tool
		end

	end

	for _, ToolSlot in pairs(BackpackSlots) do
		local Tool = ToolSlot.Tool 

		if Tool then
			onParentUpdate(Tool, nil, true)
		end
	end

	for _, ToolSlot in pairs(GluedSlots) do
		local Tool = ToolSlot.Tool 

		if Tool then
			onParentUpdate(Tool, nil, true)
		end

	end

	for _, ToolSlot in pairs(EquippedTools) do
		local Tool = ToolSlot.Tool 

		if Tool then
			onParentUpdate(Tool, nil, true)
		end

	end

	for _, Highlight in pairs(HighlightedTools) do
		Highlight.Highlight:Destroy()

		if Highlight.TrackingConnection then Highlight.TrackingConnection:Disconnect() end
	end

	table.clear(HighlightedTools)
end

function iconUpdate(ToolSlot)
	local Tool = ToolSlot.Tool
	local Frame = ToolSlot.Frame.Button

	if Tool.TextureId ~= "" then
		Frame.ToolImage.Visible = true
		Frame.ToolName.Visible = false
		Frame.ToolImage.Image = Tool.TextureId
	else
		Frame.ToolImage.Visible = false
		Frame.ToolName.Visible = true
	end
end

function nameUpdate(ToolSlot)
	ToolSlot.Frame.Button.ToolName.Text = ToolSlot.Tool.Name
end

function toolTipUpdate(ToolSlot)
	ToolTipChangedSignal:Fire(ToolSlot)
end

function CalculateMaxToolSlots()
	if Backpack.Settings.AutoCalculateMaxToolSlots then
		return math.clamp(math.round((workspace.CurrentCamera.ViewportSize.X - Backpack.Settings.NeededFreeSpace) / (BackpackSlotFrame.AbsoluteSize.X + Backpack.Settings.DesiredPadding.Offset)), Backpack.Settings.MinHotbarSlots, MaxSlotsInternal)
	else
		return Backpack.Settings.MaxHotbarToolSlots
	end
end

function scheduleNextInternalSweep()
	if NextSweepThread then task.cancel(NextSweepThread) end

	NextSweepThread = task.delay(Backpack.Settings.SweepInterval, sweepFreeSlots)
end

function WindowSizeChanged()
	if not Backpack.Settings.AutoCalculateMaxToolSlots then return end

	local AllSlots = Backpack:GetHotbarTools()

	local NewMaxHotbarSlots = CalculateMaxToolSlots()

	for _, Slot in pairs(HotbarSlots) do
		if Slot.Position > NewMaxHotbarSlots and Slot.Tool then
			local NewSlot = Backpack:MoveToolToInventory(Slot.Tool, Slot.Frame.Position)

			if NewSlot.Tool.Parent == Character then
				MoveEquipBar(NewSlot)
			end
		end
	end

	Backpack.Settings.MaxHotbarToolSlots = NewMaxHotbarSlots

	if InventoryIsOpen then revealSlots(true) end
end

function clearUIHighlights()
	local Slot1 = UISelectedSlots[1]
	local Slot2 = UISelectedSlots[2]

	local UISelect1
	local UISelect2

	if Slot1 then
		UISelect1 = Slot1.Frame.Button:FindFirstChild("_UISelectController")
	end

	if Slot2 then
		UISelect2 = Slot2.Frame.Button:FindFirstChild("_UISelectController")
	end

	if UISelect1 then UISelect1:Destroy() end
	if UISelect2 then UISelect2:Destroy() end

	table.clear(UISelectedSlots)

	return Slot1, Slot2
end

function setCanUIHighlight(boolean)
	for _, Slot in pairs(HotbarSlots) do
		if Slot.Frame then
			Slot.Frame.Button.ControllerSelectionFrame.Selectable = boolean
		end
	end

	InventoryFrame.TextBox.Selectable = boolean
end

function newSlot(Tool: Tool, BPSlot, SlotNum)
	if not Tool:IsA("Tool") then return end
	if BPSlot == nil then
		if isToolRegistered(Tool) then return end
	end

	CalculateMaxToolSlots()

	local Slot = findNextAvaliableSlot()

	if BPSlot then
		Slot = nil
	elseif BPSlot == false then
		Slot = SlotNum
	end	

	local ToolSlot

	if Slot then
		HotbarSlots[Slot].Tool = Tool
		ToolSlot = HotbarSlots[Slot]
	else
		-- If we find a free slot just reuse it otherwise create a new one

		local TotalBP = #Backpack:GetInventoryTools()
		local TotalHB = #Backpack:GetHotbarTools()

		local freeSlot = findFreeBackpackSlot()

		local newSlot = BackpackSlots[freeSlot] or {
			Frame = BackpackSlotFrame:Clone(),
			Tool = Tool,
			Position = nil,
			Locked = false,
			Glued = false,
			Loaded = false,
			Dragger = nil,
			ViewportEnabled = Backpack.Settings.UseViewportFrame,
			ViewportOffset = CFrame.new(0, 0, 0) * CFrame.Angles(0 , 0, math.rad(60)),
			Connections = {},
		}

		newSlot.Position = TotalBP + MaxSlotsInternal + 1
		newSlot.LayoutOrder = TotalBP + MaxSlotsInternal + 1

		if not freeSlot then
			table.insert(BackpackSlots, newSlot)

			newSlot.Frame.Button.MouseButton1Click:Connect(function()
				if not newSlot.Tool then return end

				local isOneKeyDown = false

				for _, key in pairs(Backpack.Settings.FASTMOVE_KEYCODES) do
					if UserInputService:IsKeyDown(key) then
						isOneKeyDown = true
						break
					end
				end

				if isOneKeyDown and InventoryIsOpen and Backpack.Settings.CanOrganize then
					local NewPosition = UDim2.fromOffset(newSlot.Frame.Button.AbsolutePosition.X  + (newSlot.Frame.Button.AbsoluteSize.X / 2), (newSlot.Frame.Button.AbsolutePosition.Y + (newSlot.Frame.Button.AbsoluteSize.Y / 2)))

					if newSlot.PlacementSlot then
						Backpack:MoveToolToInventory(newSlot.Tool, NewPosition)
					else
						if #Backpack:GetHotbarTools() >= Backpack.Settings.MaxHotbarToolSlots then return end -- Can't do it or else will warning.

						Backpack:MoveToolToHotbar(newSlot.Tool, NewPosition)
					end

					return
				end

				Backpack:Equip(newSlot.Tool, nil, true)
			end)

			newSlot.Frame:GetPropertyChangedSignal("AbsolutePosition"):Connect(function()
				SlotChangedSignal:Fire(newSlot)
			end)


			newSlot.Connections["POSITION_UPDATE_SIGNAL"] = SlotChangedSignal:Connect(function(Slot)
				if Slot ~= newSlot then return end
				if not EquippedTools[Slot.Tool] then return end
				--	if not InventoryIsOpen then return end

				for _, Highlight in pairs(HighlightedTools) do
					if Highlight.Tool == Slot.Tool and newSlot.Loaded then

						Highlight.Highlight.Parent = InventoryFrame.Parent

						if InventoryIsOpen then
							Animate(Highlight.Highlight, "Position", UDim2.fromOffset(newSlot.Frame.AbsolutePosition.X + GuiService:GetGuiInset().X, newSlot.Frame.AbsolutePosition.Y + GuiService:GetGuiInset().Y), .6, 8)

							-- Highlight.Highlight.Position = UDim2.fromOffset(newSlot.Frame.AbsolutePosition.X + GuiService:GetGuiInset().X, newSlot.Frame.AbsolutePosition.Y + GuiService:GetGuiInset().Y)

							if isClipped(newSlot.Frame, InventoryFrame.Background.ScrollingFrame) then
								SetBarTransparency(Highlight.Highlight, 1, 0)
							else
								SetBarTransparency(Highlight.Highlight, 0)
							end
						end

					end
				end
			end)

		end

		if not InventoryIsOpen then
			Backpack:PopNotificationIcon(true)
		end

		if not BPSlot then
			newSlot.Frame.Button.Position = UDim2.fromScale(0, 2)
			Animate(newSlot.Frame.Button, "Position", UDim2.fromScale(0, 0), 0.9, 2)
		end

		newSlot.Loaded = false
		newSlot.Locked = false
		newSlot.Glued = false
		newSlot.Tool = Tool
		newSlot.Frame.Name = newSlot.Position
		newSlot.Frame.Button.ToolNum.Text = ""
		newSlot.Frame.Parent = InventoryFrame.Background.ScrollingFrame

		if not isSearching then
			newSlot.Frame.Visible = true
		end

		ToolSlot = newSlot
	end

	if not ToolSlot.Dragger then
		ToolSlot.Dragger = DragDetector.new(ToolSlot, BackpackGui.BackpackMain, Backpack.Settings.FASTMOVE_KEYCODES, Backpack)

		ToolSlot.Dragger:Enable()

		ToolSlot.Dragger.DragStarted = function()
			if ToolSlot.Glued then return end
			if not ToolSlot.Tool then return end

			ToolSlot.Frame.Button.Interactable = false
			ToolSlot.Frame.Button.Visible = false
		end

		ToolSlot.Dragger.DragEnded = function(Position)
			ToolSlot.Frame.Button.Interactable = true
			ToolSlot.Frame.Button.Visible = true

			if not ToolSlot then return end

			local exitingearly = false

			if ToolSlot.Glued then exitingearly = true end
			if not ToolSlot.Tool then exitingearly = true end
			if ToolSlot.Tool.Parent ~= Character and ToolSlot.Tool.Parent ~= BackpackInstance then exitingearly = true end
			if not ToolSlot.Tool then exitingearly = true end

			if exitingearly then
				if not InventoryIsOpen then
					deleteToolSlotData(ToolSlot)
					ToolSlot.Frame.Visible = false
				end

				return
			end

			local MouseLocation = UserInputService:GetMouseLocation()

			local Pos = Position or UDim2.fromOffset(MouseLocation.X + GuiService:GetGuiInset().X, MouseLocation.Y + GuiService:GetGuiInset().Y)

			local GuiObjects = LocalPlayer.PlayerGui:GetGuiObjectsAtPosition(Pos.X.Offset, Pos.Y.Offset)

			for _, Gui in pairs(GuiObjects) do -- // For swapping
				if not tonumber(Gui.Name) or not Gui:IsDescendantOf(BackpackGui.BackpackMain) then continue end

				local ToolValue = Gui:FindFirstChildWhichIsA("ObjectValue")

				local Tool

				if ToolValue then
					Tool = ToolValue.Value
				end

				if Tool then
					if Tool == ToolSlot.Tool then continue end

					Backpack:SwapTools(Tool, ToolSlot.Tool)
					return
				else
					if not InventoryIsOpen then return end
					if not ToolValue then return end

					local SlotNum = tonumber(ToolValue.Parent.Button.ToolNum.Text)

					if SlotNum == 0 then
						SlotNum = 10
					end

					Backpack:MoveToolToHotbarSlotNumber(ToolSlot.Tool, SlotNum, Pos)
					revealSlots(true)

					return
				end
			end

			if table.find(GuiObjects, InventoryFrame) and InventoryIsOpen then
				Backpack:MoveToolToInventory(ToolSlot.Tool, Pos)
			else
				if #Backpack:GetHotbarTools() >= Backpack.Settings.MaxHotbarToolSlots then return end

				Backpack:MoveToolToHotbar(ToolSlot.Tool, Pos)
			end
		end
	end

	local Frame = ToolSlot.Frame.Button
	ToolSlot.Frame.Tool.Value = Tool

	local ToolTip = Tool.ToolTip
	local Img = Tool.TextureId

	Frame.Visible = true
	ToolSlot.Frame.Button.Visible = true
	ToolSlot.Frame.Group.GroupTransparency = 0

	if ToolSlot.PlacementSlot then
		ToolSlot.PlacementSlot.Visible = true

		defer(function()
			if not ToolSlot.Loaded then
				while ToolSlot.PlacementSlot.AbsolutePosition.Y ~= BackpackGui.BackpackMain.HotbarContainer.AbsolutePosition.Y do
					wait() -- Need to wait for the UIListLayout to calculate the position
				end

				ToolSlot.Loaded = true
			end
		end)

	else
		ToolSlot.Loaded = true
	end

	refreshSlot(ToolSlot)

	if ToolSlot.PlacementSlot then
		ToolSlot.Frame.Position = UDim2.fromOffset(ToolSlot.PlacementSlot.AbsolutePosition.X, ToolSlot.PlacementSlot.AbsolutePosition.Y + 100)
		SlotChangedSignal:Fire(ToolSlot.PlacementSlot)
	end

	local atleastonebasepart = false

	for _, something in pairs(ToolSlot.Tool:GetDescendants()) do
		if something:IsA("BasePart") then
			atleastonebasepart = true
			break
		end
	end

	if not Backpack.Settings.UseViewportFrame or not atleastonebasepart then
		if Img ~= "" then
			Frame.ToolImage.Image = Img
			Frame.ToolName.Visible = false
			Frame.ToolImage.Visible = true
		else
			Frame.ToolImage.Visible = false
			Frame.ToolName.Visible = true
		end
	else
		-- We need to build the viewport now
		local ViewportFrame = ToolSlot.Frame.Button.ViewportFrame
		local Tool = ViewportFrame.WorldModel:FindFirstChildWhichIsA("Tool")

		if Tool then
			Tool:Destroy()
		end

		local ToolClone : Tool = ToolSlot.Tool:Clone()

		local function removeScripts()
			for _, inst in pairs(ToolClone:GetDescendants()) do
				if inst:IsA("BaseScript") then
					inst:Destroy()
				end
			end
		end

		removeScripts()

		ToolClone:PivotTo(CFrame.new(0, 0, 0) * CFrame.Angles(0 , 0, math.rad(60)))
		ToolClone.Parent = ViewportFrame.WorldModel

		local Cam = Instance.new("Camera")

		Cam.CFrame = ToolSlot.ViewportOffset
		ViewportFrame.CurrentCamera = Cam

		zoomToExtents(ViewportFrame.CurrentCamera, ToolClone)

		defer(function()
			local isSpinning = false
			local left = true

			local temp = Instance.new("NumberValue")

			while true do
				wait()

				local doesConnectionExist = false

				for _, con in pairs(ToolSlot.Connections) do
					if con then
						doesConnectionExist = true
					end
					break
				end

				if not doesConnectionExist and not ToolSlot.PlacementSlot then temp:Destroy() break end

				if not ToolSlot.Tool then continue end

				ToolClone:PivotTo(CFrame.new(0, 0, 0) * CFrame.Angles(0 , 0, math.rad(temp.Value)))

				if not ToolSlot.PlacementSlot then 
					if not InventoryIsOpen then continue end
				end

				if isSpinning then continue end

				local direction

				if left then direction = -120 else direction = 120 end

				isSpinning = true

				Spring.stop(temp, "Value")

				Spring.target(temp, 1.6, .8, {
					["Value"] = direction,
				})

				delay(2.3, function()
					isSpinning = false
					left = not left
				end)
			end
		end)
	end

	if Tool.Parent == Character and not BPSlot and not SlotNum then

		defer(function()
			Tool.Parent = BackpackInstance

			for Tool, _ in pairs(EquippedTools) do
				if Tool.Parent ~= Character then
					Tool.Parent = Character
				end
			end
		end)

	end

	if not BPSlot and not SlotNum then
		Backpack.ToolAdded:Fire(Tool, Frame.Parent)
	end

	return ToolSlot
end

function findNextAvaliableSlot()
	for i = 1, #HotbarSlots do
		if not HotbarSlots[i].Tool and i <= Backpack.Settings.MaxHotbarToolSlots then
			return i
		end
	end
end

function findFreeBackpackSlot()
	for i = 1, #BackpackSlots do
		if not BackpackSlots[i].Tool then
			return i
		end
	end
end

function findNextAvaliableGlueSlot()
	for i = MaxGluedSlots, 1, -1 do
		if not GluedSlots[i].Tool then
			return i
		end
	end
end

function sweepFreeSlots()
	NextSweepThread = nil

	local CloneOfBPSlots = table.clone(BackpackSlots)

	for _, Slot in pairs(CloneOfBPSlots) do
		if not Slot.Tool then
			local RealTable = table.find(BackpackSlots, Slot)

			for _, Connection in pairs(BackpackSlots[RealTable].Connections) do
				Connection:Disconnect()
			end

			BackpackSlots[RealTable].Frame:Destroy()
			table.remove(BackpackSlots, RealTable)
		end
	end 

	-- Now the .Position property is all messed up lets fix it

	for i = 1, #BackpackSlots do
		BackpackSlots[i].Position = i

		BackpackSlots[i].Frame.Name = MaxSlotsInternal + i
	end

	scheduleNextInternalSweep()
end

function SetBarTransparency(Bar, Transparency, time)
	local realtime = time or 1.4

	if Backpack.Settings.Animate == false then
		realtime = 0
	end

	Spring.stop(Bar, "GroupTransparency")

	if realtime == 0 then
		Bar.GroupTransparency = Transparency
	else
		Spring.target(Bar, realtime, 8.3, {["GroupTransparency"] = Transparency})
	end
end

function Search(text : string)
	if not text then text = "" end

	text = string.lower(text)

	if string.len(text) <= 0 then
		isSearching = false
		for _, slot in pairs(BackpackSlots) do
			if slot.Tool then
				slot.Frame.Visible = true
			end
		end

		for _, Highlight in pairs(HighlightedTools) do
			if Highlight.Tool then
				Highlight.Highlight.Visible = true
			end
		end

	else
		isSearching = true
		for _, slot in pairs(BackpackSlots) do
			if slot.Tool and string.lower(slot.Tool.Name):match(text) then
				slot.Frame.Visible = true

				for _, Highlight in pairs(HighlightedTools) do
					if Highlight.Tool and Highlight.Tool == slot.Tool then
						Highlight.Highlight.Visible = true
					end
				end

			else

				for _, Highlight in pairs(HighlightedTools) do
					if Highlight.Tool and Highlight.Tool == slot.Tool then
						Highlight.Highlight.Visible = false
					end
				end

				slot.Frame.Visible = false
			end
		end

	end

end

function MoveEquipBar(FrameSlot, DisabledFrame, time)
	local InvParent = InventoryFrame.Background.ScrollingFrame

	if FrameSlot == false then

		for i, Highlight in pairs(HighlightedTools) do
			if not Highlight.Tool or Highlight.Tool.Parent ~= Character then
				Highlight.Highlight.ActiveValue.Value = false
				SetBarTransparency(Highlight.Highlight, 1, time)
				Highlight.Tool = nil
			end
		end

		return
	end

	local Num = 0

	for _ in pairs(HighlightedTools) do
		Num += 1
	end

	for _, Glue in pairs(GluedSlots) do
		if Glue.Tool then
			Num += 1
		end
	end

	if Num < Backpack.Settings.MaxHeldTools then
		local NewUISection = SelectionUIFrame:Clone()

		NewUISection.Visible = true

		if FrameSlot.Frame.Parent == InvParent then
			NewUISection.Parent = InventoryFrame.Parent

			NewUISection.Position = UDim2.fromOffset(FrameSlot.Frame.AbsolutePosition.X + GuiService:GetGuiInset().X, FrameSlot.Frame.AbsolutePosition.Y + GuiService:GetGuiInset().Y)
		else
			NewUISection.Position = UDim2.fromOffset( FrameSlot.Frame.AbsolutePosition.X + GuiService:GetGuiInset().X, FrameSlot.Frame.AbsolutePosition.Y + GuiService:GetGuiInset().Y + 20)
			NewUISection.Parent = BackpackGui.BackpackMain
		end

		table.insert(HighlightedTools, {
			Slot = FrameSlot,
			Frame = FrameSlot.Frame,
			Highlight = NewUISection,
			Tool = FrameSlot.Tool
		})

		NewUISection.ActiveValue.Value = true
		SetBarTransparency(NewUISection, 0)

		if FrameSlot.PlacementSlot then
			SlotChangedSignal:Fire(FrameSlot.PlacementSlot)
		else
			SlotChangedSignal:Fire(FrameSlot.Tool)
		end
	else
		for i, Highlight in pairs(HighlightedTools) do

			if not Highlight.Tool or Highlight.Tool.Parent ~= Character then

				if FrameSlot.Frame.Parent == InvParent then
					Highlight.Highlight.Parent = InventoryFrame.Parent
				else
					Highlight.Highlight.Parent = BackpackGui.BackpackMain
				end

				if Highlight.Highlight.Parent == BackpackGui.BackpackMain then
					Highlight.Highlight.Visible = true
				end

				HighlightedTools[i].FrameSlot = FrameSlot
				HighlightedTools[i].Frame = FrameSlot.Frame
				HighlightedTools[i].Tool = FrameSlot.Tool

				SetBarTransparency(Highlight.Highlight, 0, 0)

				local function move()
					if Highlight.Highlight.GroupTransparency ~= 1 then

						if Backpack.Settings.Animate == true then
							Spring.target(Highlight.Highlight,  0.78, 4, {["Position"] = UDim2.fromOffset(FrameSlot.Frame.AbsolutePosition.X + GuiService:GetGuiInset().X, FrameSlot.Frame.AbsolutePosition.Y + GuiService:GetGuiInset().Y)})
						else
							Highlight.Highlight.Position = UDim2.fromOffset(FrameSlot.Frame.AbsolutePosition.X + GuiService:GetGuiInset().X, FrameSlot.Frame.AbsolutePosition.Y + GuiService:GetGuiInset().Y)
						end
					else
						Spring.stop(Highlight.Highlight, "Position")

						Highlight.Highlight.Position = UDim2.fromOffset(FrameSlot.Frame.AbsolutePosition.X + GuiService:GetGuiInset().X, FrameSlot.Frame.AbsolutePosition.Y + GuiService:GetGuiInset().Y)
					end
				end

				while FrameSlot.Moving do
					move()

					wait()
				end

				move()

				break
			else
				if Highlight.Tool then continue end
				Spring.stop(Highlight.Highlight, "Position")

				HighlightedTools[i].FrameSlot = FrameSlot
				HighlightedTools[i].Frame = FrameSlot.Frame
				HighlightedTools[i].Tool = FrameSlot.Tool

				if FrameSlot.Frame.Parent ~= BackpackGui.BackpackMain then
					Highlight.Highlight.Parent = InventoryFrame.Parent
				else
					Highlight.Highlight.Parent = BackpackGui.BackpackMain
				end

				SetBarTransparency(Highlight.Highlight, 0)

				while FrameSlot.Moving do
					Animate(Highlight.Highlight, "Position",  UDim2.fromOffset(FrameSlot.Frame.AbsolutePosition.X + GuiService:GetGuiInset().X, FrameSlot.Frame.AbsolutePosition.Y + GuiService:GetGuiInset().Y), .79, 3)
				end

				Animate(Highlight.Highlight, "Position",  UDim2.fromOffset(FrameSlot.Frame.AbsolutePosition.X + GuiService:GetGuiInset().X, FrameSlot.Frame.AbsolutePosition.Y + GuiService:GetGuiInset().Y), .79, 3)
				break
			end	

		end
	end
end

function BuildGui()
	StarterGuiService:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)

	InventoryFrame = BackpackGui.InventoryMain:Clone() -- ok shut up we're doing something cool here
	ToolTipFrame = BackpackGui.ToolTip:Clone()
	SelectionUIFrame = BackpackGui.SelectionUI:Clone()
	BackpackSlotFrame = BackpackGui.BackpackSlot:Clone()
	BPButton = BackpackGui.BackpackButton:Clone()

	BackpackGui.InventoryMain:Destroy()
	BackpackGui.SelectionUI:Destroy()
	BackpackGui.ToolTip:Destroy()
	BackpackGui.BackpackSlot:Destroy()
	BackpackGui.BackpackButton:Destroy()

	BPButton.Visible = false
	BackpackSlotFrame.Visible = false
	SelectionUIFrame.Visible = false
	ToolTipFrame.Visible = false
	InventoryFrame.Visible = false

	BackgroundTransparency = BPButton.ImageButton.BackgroundColor3
	InventoryFrame:SetAttribute("Size", InventoryFrame.Size)

	if not BackpackIsDisabled then BackpackGui.Visible = true end

	for i = 1, Backpack.Settings.MaxHotbarToolSlots do
		table.insert(HotbarSlots, {
			Frame = nil,
			Tool = nil,
			Position = i,
			Locked = false,
			Glued = false,
			Loaded = false,
			PlacementSlot = nil,
			Dragger = nil,
			ViewportEnabled = Backpack.Settings.UseViewportFrame,
			ViewportOffset = CFrame.new(0, 0, 0) * CFrame.Angles(0 , math.rad(-100), math.rad(-45)),
			Connections = {},
		})
	end

	for i = 1, MaxGluedSlots do
		table.insert(GluedSlots, {
			Frame = nil,
			Tool = nil,
			Position = i,
			Locked = false,
			Glued = true,
			Loaded = false,
			PlacementSlot = nil,
			Dragger = nil,
			ViewportEnabled = Backpack.Settings.UseViewportFrame,
			ViewportOffset = CFrame.new(0, 0, 0) * CFrame.Angles(0 , math.rad(-100), math.rad(-45)),
			Connections = {},
		})
	end

	local MainFrame = create("Frame", {
		Name = "BackpackMain",
		Size = UDim2.fromScale(1,1),
		BackgroundTransparency = 1,
		Visible = true,
		Parent = BackpackGui,
		["Children"] = {

			create("Frame", {
				Name = "HotbarContainer",
				Size = UDim2.new(1, 0, 0, 60),
				Position = UDim2.new(.5, 0, 1, -45),
				Visible = true,
				AnchorPoint = Vector2.new(.5, .5),
				BackgroundTransparency = 1,
				["Children"] = {
					create("UIListLayout", {
						HorizontalAlignment = Enum.HorizontalAlignment.Center,
						SortOrder = Enum.SortOrder.LayoutOrder,
						VerticalAlignment = Enum.VerticalAlignment.Center,
						FillDirection = Enum.FillDirection.Horizontal,
						Padding = Backpack.Settings.DesiredPadding, 
					}),
				}
			}), 
			create("Frame", {
				Name = "GlueContainer",
				Size = UDim2.new(.4, 0, 0, 60),
				AnchorPoint = Vector2.new(1, 0),
				Visible = true,
				BackgroundTransparency = 1,
				["Children"] = {
					create("UIListLayout", {
						HorizontalAlignment = Enum.HorizontalAlignment.Right,
						SortOrder = Enum.SortOrder.LayoutOrder,
						VerticalAlignment = Enum.VerticalAlignment.Center,
						FillDirection = Enum.FillDirection.Horizontal,
						Padding = Backpack.Settings.DesiredPadding, 
					}),
				}
			}),
			create("CanvasGroup", {
				Name = "Inventory",
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Position = UDim2.new(0, 0, 0, 0),
				["Children"] = {
					InventoryFrame
				}
			}),
		}
	})

	InventoryFrame.Background.ScrollingFrame.UIListLayout.Padding = Backpack.Settings.DesiredPadding


	InventoryFrame.TextBox:GetPropertyChangedSignal("Text"):Connect(function()
		local Text = InventoryFrame.TextBox.Text

		Search(Text)
	end)

	for i = 1, Backpack.Settings.MaxHotbarToolSlots do
		local use

		if i == 10 then 
			use = 0
		end

		local using = use or i

		local NewSlot = BackpackSlotFrame:Clone()

		local PlacementFrame = create("Frame", {
			Size = NewSlot.Size,
			Transparency = 1,
			AnchorPoint = NewSlot.AnchorPoint,
			Position = UDim2.fromOffset(0, 0),
			Visible = false,
			Name = use or i,
			LayoutOrder = i,
		})

		PlacementFrame.Parent = MainFrame.HotbarContainer

		NewSlot.Name = use or i
		NewSlot.LayoutOrder = i
		NewSlot.Parent = MainFrame

		PlacementFrame:GetPropertyChangedSignal("AbsolutePosition"):Connect(function()
			SlotChangedSignal:Fire(PlacementFrame)
		end)

		SlotChangedSignal:Connect(function(Slot)
			if Slot == PlacementFrame then
				local Completed = false
				Animate(NewSlot, "Position", UDim2.fromOffset(PlacementFrame.AbsolutePosition.X + GuiService:GetGuiInset().X, PlacementFrame.AbsolutePosition.Y + GuiService:GetGuiInset().Y), .79, 3)

				if Backpack.Settings.Animate == true then
					Spring.completed(NewSlot, function()
						Completed = true
					end)
				else
					Completed = true
				end

				defer(function()
					while not Completed do
						HotbarSlots[i].Moving = true
						wait()
					end
					HotbarSlots[i].Moving = nil
				end)

				InventoryFrame.Position = UDim2.new(.5, 0, 0, PlacementFrame.AbsolutePosition.Y - 100)

				if HotbarSlots[i].Tool then
					if EquippedTools[HotbarSlots[i].Tool] then
						for _, Highlight in pairs(HighlightedTools) do
							if Highlight.Tool == HotbarSlots[i].Tool then

								Highlight.Highlight.Parent = BackpackGui.BackpackMain

								local TargetPosition = PlacementFrame.AbsolutePosition
								local NewPos = UDim2.fromOffset(PlacementFrame.AbsolutePosition.X + GuiService:GetGuiInset().X, PlacementFrame.AbsolutePosition.Y + GuiService:GetGuiInset().Y)

								if not InventoryIsOpen then
									Highlight.Highlight.Position = UDim2.fromOffset(Highlight.Highlight.AbsolutePosition.X, PlacementFrame.AbsolutePosition.Y + GuiService:GetGuiInset().Y)
								end

								Animate(Highlight.Highlight, "Position",  NewPos, .79, 3, true)
								SetBarTransparency(Highlight.Highlight, 0, 0)
							end
						end
					end
				end
			end
		end)

		HotbarSlots[i].PlacementSlot = PlacementFrame
		HotbarSlots[i].Frame = NewSlot

		NewSlot.Button.ToolNum.Text = use or i

		NewSlot.Button.MouseButton1Click:Connect(function()
			if not HotbarSlots[i].Tool then return end

			local isOneKeyDown = false

			for _, key in pairs(Backpack.Settings.FASTMOVE_KEYCODES) do
				if UserInputService:IsKeyDown(key) then
					isOneKeyDown = true
					break
				end
			end

			if isOneKeyDown and InventoryIsOpen and Backpack.Settings.CanOrganize then
				local NewPosition = UDim2.fromOffset(NewSlot.Button.AbsolutePosition.X  + (NewSlot.Button.AbsoluteSize.X / 2), (NewSlot.Button.AbsolutePosition.Y + (NewSlot.Button.AbsoluteSize.Y / 2)))

				if HotbarSlots[i].PlacementSlot then
					Backpack:MoveToolToInventory(HotbarSlots[i].Tool, NewPosition)
				else
					if #Backpack:GetHotbarTools() >= Backpack.Settings.MaxHotbarToolSlots then return end -- Can't do it or else will warning.

					Backpack:MoveToolToHotbar(HotbarSlots[i].Tool, NewPosition)
				end

				return
			end

			Backpack:Equip(i, nil, true)
		end)
	end

	for i = 1, MaxGluedSlots do
		local NewSlot = BackpackSlotFrame:Clone()

		local PlacementFrame = create("Frame", {
			Size = NewSlot.Size,
			Transparency = 1,
			AnchorPoint = NewSlot.AnchorPoint,
			Position = UDim2.fromOffset(0, 0),
			Visible = true,
			Name = i,
			LayoutOrder = i,
		})

		PlacementFrame.Parent = MainFrame.GlueContainer

		NewSlot.Name = "Glueslot"..i
		NewSlot.LayoutOrder = i
		NewSlot.Parent = MainFrame

		PlacementFrame:GetPropertyChangedSignal("AbsolutePosition"):Connect(function()
			SlotChangedSignal:Fire(PlacementFrame)
		end)

		SlotChangedSignal:Connect(function(Slot)
			if Slot == PlacementFrame then

				local Completed = false


				Animate(NewSlot, "Position", UDim2.fromOffset(PlacementFrame.AbsolutePosition.X + GuiService:GetGuiInset().X, PlacementFrame.AbsolutePosition.Y + GuiService:GetGuiInset().Y), .79, 3, true)

				if Backpack.Settings.Animate == true then
					Spring.completed(NewSlot, function()
						Completed = true
					end)
				end

				defer(function()
					while not Completed do
						CalculateGluedSlotPosition()
						wait()
					end
				end)

			end
		end)

		CalculateGluedSlotPosition()

		GluedSlots[i].Loaded = true

		GluedSlots[i].PlacementSlot = PlacementFrame
		GluedSlots[i].Frame = NewSlot

		NewSlot.Button.ToolNum.Text = ""
	end

	for _, Button : Instance in pairs(BPButton:GetDescendants()) do
		if Button:IsA("GuiButton") then
			Button.MouseButton1Click:Connect(function()

				if InventoryIsOpen then
					Backpack:CloseInventory(true)
				else
					Backpack:OpenInventory(true)
				end

			end)
		end
	end

	if not InventoryIsDisabled then
		BPButton.Visible = true
	end

	BPButton.Parent = BackpackGui

	Backpack:PopNotificationIcon(false)

	create("Frame", {
		Size = UDim2.fromScale(1,1),
		Position = UDim2.fromScale(0,0),
		BackgroundTransparency = 1,
		Name = "ToolTips",
		Parent = BackpackGui,
	})
end

function CalculateInventoryButtonPosition()
	local Max

	for _, slot in pairs(HotbarSlots) do
		if not slot.Frame.Visible then continue end
		if not Max then Max = slot end


		if slot.Position > Max.Position then
			Max = slot
		end
	end

	if not Max then 
		BPButton.Position = UDim2.new(0.5, 0, 0, BackpackGui.BackpackMain.HotbarContainer.AbsolutePosition.Y + (BackpackSlotFrame.Size.Y.Offset * 1.5))
		return
	end

	local MaxAbsolutePosition = Max.Frame.AbsolutePosition

	BPButton.Position = UDim2.fromOffset(MaxAbsolutePosition.X + (BackpackSlotFrame.Size.X.Offset * 1.4), MaxAbsolutePosition.Y  + (BackpackSlotFrame.Size.Y.Offset * 1.2))
end

function CalculateGluedSlotPosition()
	local Min

	for _, slot in pairs(HotbarSlots) do
		if not slot.Frame.Visible then continue end
		if not Min then Min = slot end

		if slot.Position < Min.Position then
			Min = slot
		end
	end

	if not Min then
		BackpackGui.BackpackMain.GlueContainer.Position = UDim2.new(0.42, 0, 0, BackpackGui.BackpackMain.HotbarContainer.AbsolutePosition.Y + GuiService:GetGuiInset().Y)
		return
	end

	local MinAbsolutePosition = Min.PlacementSlot.AbsolutePosition

	BackpackGui.BackpackMain.GlueContainer.Position = UDim2.fromOffset(MinAbsolutePosition.X + GuiService:GetGuiInset().X - 30 , MinAbsolutePosition.Y  + GuiService:GetGuiInset().Y)
end

function Animate(Instance, Prop, Value, Damping, Ratio, noStop)
	if Backpack.Settings.Animate == true then
		if not noStop then
			Spring.stop(Instance, Prop)
		end

		local Insert = {}

		Insert[Prop] = Value

		Spring.target(Instance, Damping, Ratio, Insert)
	else
		Instance[Prop] = Value
	end
end

function refreshSlot(Slot, PrevSlot)

	for conName, Connection in pairs(Slot.Connections) do
		if conName == "POSITION_UPDATE_SIGNAL" then continue end
		Connection:Disconnect()
	end

	if Slot.PlacementSlot then
		Slot.PlacementSlot.Visible = true

		defer(function()
			if not Slot.Loaded then
				while Slot.PlacementSlot.AbsolutePosition.Y ~= BackpackGui.BackpackMain.HotbarContainer.AbsolutePosition.Y do
					wait() -- Need to wait for the UIListLayout to calculate the position
				end

				Slot.Loaded = true
			end
		end)

	else
		Slot.Loaded = true
	end

	if Slot.PlacementSlot then
		local Abs = Slot.PlacementSlot.AbsolutePosition

		Slot.Frame.Position = UDim2.fromOffset(Abs.X + GuiService:GetGuiInset().X, Abs.Y + GuiService:GetGuiInset().Y)
	end

	Slot.Connections["ICON_UPDATE_SIGNAL"] = Slot.Tool:GetPropertyChangedSignal("TextureId"):Connect(function()
		iconUpdate(Slot)
	end)

	Slot.Connections["TOOLTIP_UPDATE_SIGNAL"] = Slot.Tool:GetPropertyChangedSignal("ToolTip"):Connect(function()
		toolTipUpdate(Slot)
	end)

	Slot.Connections["NAME_UPDATE_SIGNAL"] = Slot.Tool:GetPropertyChangedSignal("Name"):Connect(function()
		nameUpdate(Slot)
	end)

	Slot.Connections["PARENT_UPDATE_SIGNAL"] = Slot.Tool:GetPropertyChangedSignal("Parent"):Connect(function()
		if not Slot.Tool then return end

		onParentUpdate(Slot.Tool, Slot.Tool.Parent)
	end)

	Slot.Connections["MOUSE_ENTER_CONNECTION"] = Slot.Frame.MouseEnter:Connect(function(...)
		HoverStartedInternal:Fire(Slot.Frame, ...)
		Backpack.HoverStarted:Fire(Slot.Frame, ...)
	end)

	Slot.Connections["MOUSE_LEAVE_CONNECTION"] = Slot.Frame.MouseLeave:Connect(function(...)
		HoverEndedInternal:Fire(Slot.Frame, ...)
		Backpack.HoverEnded:Fire(Slot.Frame, ...)
	end)

	Slot.Frame.Tool.Value = Slot.Tool
	Slot.Frame.Button.ToolName.Text = Slot.Tool.Name
	Slot.Frame.LayoutOrder = Slot.Position
	Slot.Frame.Visible = true

	if not Slot.IsAnimating then
		Slot.Frame.Button.Visible = true
	end

	Slot.Frame.Button.CooldownFrame.Visible = false
	Slot.Frame.Button.CooldownText.Visible = false
	Slot.Frame.Button.CooldownFrame.Size = UDim2.fromScale(1, 1)

	if InventoryIsOpen then
		Slot.Frame.Button.ControllerSelectionFrame.Selectable = true
	end

	if Slot.Glued then
		Slot.Frame.Name = "Glueslot"..Slot.Position
	else
		Slot.Frame.Name = Slot.Position
	end

	if Slot.Locked then
		Slot.Frame.Button.LockImg.Visible = true
	else
		Slot.Frame.Button.LockImg.Visible = false
	end

	local atleastonebasepart = false

	for _, something in pairs(Slot.Tool:GetDescendants()) do
		if something:IsA("BasePart") then
			atleastonebasepart = true

			break
		end
	end

	toolTipUpdate(Slot)

	if not Slot.ViewportEnabled or not atleastonebasepart then
		iconUpdate(Slot)
		nameUpdate(Slot)
		Slot.Frame.Button.ViewportFrame.Visible = false

		local ToolInViewport = Slot.Frame.Button.ViewportFrame.WorldModel:FindFirstChildWhichIsA("Tool")

		if ToolInViewport then 
			ToolInViewport:Destroy()
		end
	else
		Slot.Frame.Button.ViewportFrame.Visible = true
		Slot.Frame.Button.ToolName.Text = ""
		Slot.Frame.Button.ToolImage.Visible = false
		-- We need to build the viewport now
		local ViewportFrame = Slot.Frame.Button.ViewportFrame
		local Tool = ViewportFrame.WorldModel:FindFirstChildWhichIsA("Tool")

		if Tool then
			Tool:Destroy()
		end

		local ToolClone : Tool = Slot.Tool:Clone()

		local function removeScripts()
			for _, inst in pairs(ToolClone:GetDescendants()) do
				if inst:IsA("BaseScript") then
					inst:Destroy()
				end
			end
		end

		removeScripts()

		ToolClone:PivotTo(CFrame.new())

		ToolClone.Parent = ViewportFrame.WorldModel

		local Cam = Instance.new("Camera")

		Cam.CFrame = Slot.ViewportOffset

		ViewportFrame.CurrentCamera = Cam

		zoomToExtents(ViewportFrame.CurrentCamera, ToolClone)

		defer(function()
			local isSpinning = false
			local left = true

			local temp = Instance.new("NumberValue")

			local lastViewportUpdate = os.clock()

			Slot.lastViewportUpdate = lastViewportUpdate

			while Slot.lastViewportUpdate == lastViewportUpdate do
				wait()

				local doesConnectionExist = false

				for _, con in pairs(Slot.Connections) do
					if con then
						doesConnectionExist = true
					end
					break
				end

				if not doesConnectionExist and not Slot.PlacementSlot then temp:Destroy() break end

				if not Slot.Tool then temp:Destroy() break end

				ToolClone:PivotTo(CFrame.new(0, 0, 0) * CFrame.Angles(0 , 0, math.rad(temp.Value)))

				if not Slot.PlacementSlot then 
					if not InventoryIsOpen then continue end
				end

				if isSpinning then continue end

				local direction

				if left then direction = -120 else direction = 120 end

				isSpinning = true

				Spring.stop(temp, "Value")

				Spring.target(temp, 1.6, .8, {
					["Value"] = direction,
				})

				delay(2.3, function()
					isSpinning = false
					left = not left
				end)
			end

			if temp then temp:Destroy() end
		end)

	end

	for Tool, _ in pairs(EquippedTools) do
		if Tool == Slot.Tool then
			EquippedTools[Tool] = Slot
			break
		end
	end

	if not Slot.Glued then
		if Slot.PlacementSlot then
			SlotChangedSignal:Fire(Slot.PlacementSlot)
		else
			SlotChangedSignal:Fire(Slot)
		end
	end
end

function findTakenHotbarSlot(slot, Direction)
	local Max = 0	

	for _, slot in pairs(HotbarSlots) do

		if slot.Tool and slot.Position > Max then
			Max = slot.Position
		end
	end

	local Min = 0

	for i, slot in pairs(HotbarSlots) do
		if slot.Tool and slot.Position < Min then
			Min = slot.Position
		end
	end

	local Slot, didClamp = slot, false

	local function set()
		Slot += Direction


		if HotbarSlots[Slot] and HotbarSlots[Slot].Tool then
			return Slot
		else
			if Slot > Max then
				didClamp = true
				return
			elseif Slot <= Min then
				didClamp = true
				return
			end

			set()
		end
	end

	set()

	return Slot, Max, Min, didClamp
end

function findTakenInventorySlot(slot, Direction)
	local Max = 0	

	for _, slot in pairs(BackpackSlots) do

		if slot.Tool and slot.Position > Max then
			Max = slot.Position
		end
	end

	local Min = 0

	for i, slot in pairs(BackpackSlots) do
		if slot.Tool and slot.Position < Min then
			Min = slot.Position
		end
	end

	local Slot = slot

	local function set()
		Slot += Direction


		if BackpackSlots[Slot] and BackpackSlots[Slot].Tool then
			return Slot
		else
			if Slot > Max then
				return Slot
			elseif Slot <= Min then
				return Slot
			end

			set()
		end
	end

	set()

	return Slot, Max, Min
end

function TranslateInput(InputObject : InputObject)
	if InputObject.UserInputType == Enum.UserInputType.MouseWheel and Backpack.Settings.USE_SCROLLWHEEL == true or table.find(Backpack.Settings.CYCLE_LEFT_KEYCODES, InputObject.KeyCode) or table.find(Backpack.Settings.CYCLE_RIGHT_KEYCODES, InputObject.KeyCode) then
		local MouseLocation = UserInputService:GetMouseLocation()

		if table.find(LocalPlayer.PlayerGui:GetGuiObjectsAtPosition(MouseLocation.X + GuiService:GetGuiInset().X, MouseLocation.Y - GuiService:GetGuiInset().Y), InventoryFrame) then return end -- Cancel it if they are currently scrolling in their inventory.

		local Direction = 1

		if InputObject.UserInputType == Enum.UserInputType.MouseWheel then
			if InputObject.Position.Z > 0 then 
				Direction = 1
			else
				Direction = -1
			end
		end

		if table.find(Backpack.Settings.CYCLE_LEFT_KEYCODES, InputObject.KeyCode) then
			Direction = -1
		elseif table.find(Backpack.Settings.CYCLE_RIGHT_KEYCODES, InputObject.KeyCode) then
			Direction = 1
		end

		if lastScrollWheelPosition then

			local Slot = lastScrollWheelPosition

			local NewSlot, Max, Min = findTakenHotbarSlot(Slot, Direction)

			if not HotbarSlots[NewSlot] or not HotbarSlots[NewSlot].Tool then
				Backpack:UnequipTools()

				if NewSlot > Max then
					lastScrollWheelPosition = 0
				elseif NewSlot <= 0 then
					lastScrollWheelPosition = Max + 1
				end
			else
				lastScrollWheelPosition = NewSlot

				return NewSlot
			end
		else

			for i, Slot in ipairs(HotbarSlots) do
				if Slot.Tool then
					lastScrollWheelPosition = Slot.Position

					return i
				end
			end


		end
	elseif InputObject.UserInputType == Enum.UserInputType.Keyboard then
		if KEYBOARD_TRANSLATIONS[InputObject.KeyCode.Name] then
			return tonumber(KEYBOARD_TRANSLATIONS[InputObject.KeyCode.Name])
		end
	end
end

function deleteToolSlotData(ToolSlot)
	ToolSlot.Tool = nil
	ToolSlot.Glued = false
	ToolSlot.Locked = false

	ToolSlot.Frame.Visible = false
	ToolSlot.Frame.Button.CooldownFrame.Visible = false
	ToolSlot.Frame.Button.CooldownText.Visible = false
	ToolSlot.Frame.Button.CooldownFrame.Size = UDim2.fromScale(1, 1)

	if ToolSlot.PlacementSlot then
		ToolSlot.PlacementSlot.Visible = false
	end

	ToolSlot.Frame.Tool.Value = nil

	for conName, Connection in pairs(ToolSlot.Connections) do
		if conName == "POSITION_UPDATE_SIGNAL" then continue end
		Connection:Disconnect()
	end

	if ToolSlot.ToolTipFrame then
		task.spawn(HoverEnd, ToolSlot)
	end

	table.clear(ToolSlot.Connections)

	ToolSlot.Loaded = false
end

function convert(ToolOrSlot, num)
	if typeof(ToolOrSlot) == "Instance" then
		if not ToolOrSlot:IsA("Tool") then error("Arugment "..num.. " isn't a tool.") return end
		if not isToolRegistered(ToolOrSlot) then error("Tool is not in LocalPlayer's control.") end

		return ToolOrSlot
	elseif typeof(ToolOrSlot) == "number" then
		if ToolOrSlot == 0 then ToolOrSlot = 10 end

		local Slot = HotbarSlots[ToolOrSlot]

		if ToolOrSlot > Backpack.Settings.MaxHotbarToolSlots then -- If inputted number is more than the max slots allowed then we need to find the slot from the inventory.
			for _, BPSlot in ipairs(BackpackSlots) do
				if BPSlot.Position > ToolOrSlot then break end

				if BPSlot.Position == ToolOrSlot then
					Slot = BPSlot
					break
				end
			end
		end

		if Slot and Slot.Tool then
			return Slot.Tool
		else
			return
		end
	elseif typeof(ToolOrSlot) == "table" then
		if not ToolOrSlot.Tool then error("Argument "..num .."'s table didn't have a valid tool. Must be {Tool = (ToolInstance)}.") return end

		return ToolOrSlot.Tool
	elseif typeof(ToolOrSlot) == "string" then

		ToolOrSlot = tonumber(ToolOrSlot)

		if not ToolOrSlot then
			error("cannot convert argument "..num.."'s string to a number.")
		end

		local Slot = HotbarSlots[tonumber(ToolOrSlot)]

		if ToolOrSlot > Backpack.Settings.MaxHotbarToolSlots then
			for _, BPSlot in ipairs(BackpackSlots) do
				if BPSlot.Position > ToolOrSlot then break end

				if BPSlot.Position == ToolOrSlot then
					Slot = BPSlot
					break
				end
			end
		end

		if Slot and Slot.Tool then
			return Slot.Tool
		else
			return
		end
	else
		error("Argument "..num.." has an unsupported type or nil.")
	end
end

function revealSlots(State)
	if State then
		local Setting = Backpack.Settings.Animate

		Backpack.Settings.Animate = false

		for i, Slot in ipairs(HotbarSlots) do

			if not Slot.Tool and Slot.PlacementSlot then
				if i <= Backpack.Settings.MaxHotbarToolSlots then
					Slot.PlacementSlot.Visible = true
					Slot.Frame.Visible = true
				else
					Slot.PlacementSlot.Visible = false
					Slot.Frame.Visible = false
				end

				Slot.Frame.Button.Visible = true
				Slot.Frame.Button.ViewportFrame.Visible = false
				Slot.Frame.Button.CooldownFrame.Visible = false
				Slot.Frame.Button.LockImg.Visible = false
				Slot.Frame.Button.ToolImage.Visible = false
				Slot.Frame.Button.ToolName.Visible = false

				local use

				if i == 10 then 
					use = 0
				end

				local using = use or i

				Slot.Frame.Button.ToolNum.Text = using

				Slot.Frame.Button.ToolNum.Visible = true
			end

			spawn(function()
				for i = 1, 50 do
					if not InventoryIsOpen then break end
					SlotChangedSignal:Fire(Slot.PlacementSlot)
					Spring.stop(Slot.Frame, "Position")
					local Abs = Slot.PlacementSlot.AbsolutePosition

					Slot.Frame.Position = UDim2.fromOffset(Abs.X + GuiService:GetGuiInset().X, Abs.Y + GuiService:GetGuiInset().Y)
					wait()
				end
			end)

		end

		for i, Slot in pairs(GluedSlots) do
			if Slot.Tool and Slot.PlacementSlot then
				Spring.stop(Slot.Frame, "Position")
				local Abs = Slot.PlacementSlot.AbsolutePosition

				Slot.Frame.Position = UDim2.fromOffset(Abs.X + GuiService:GetGuiInset().X, Abs.Y + GuiService:GetGuiInset().Y)
			end
		end

		Backpack.Settings.Animate = Setting

	else
		for i, Slot in ipairs(HotbarSlots) do
			if not Slot.Tool and Slot.PlacementSlot then
				Slot.PlacementSlot.Visible = false
				Slot.Frame.Visible = false
				Slot.Frame.Button.ViewportFrame.Visible = true
				Slot.Frame.Button.CooldownFrame.Visible = true
				Slot.Frame.Button.LockImg.Visible = false
				Slot.Frame.Button.ToolImage.Visible = true
				Slot.Frame.Button.ToolName.Visible = true

				local use

				if i == 10 then 
					use = 0
				end

				local using = use or i

				Slot.Frame.Button.ToolNum.Text = using

				Slot.Frame.Button.ToolNum.Visible = true
			end
		end
	end
end

--[[
	Maps a slot's equip function to a certain keycode.
]]
function Backpack:MapKeybind(SlotNumber : number, Keycode : Enum.KeyCode)
	isModuleRunning()
	if typeof(SlotNumber) ~= "number" then error("Argument 1 is not of type: number") end
	if typeof(Keycode) ~= "EnumItem" then error("Argument 2 is not of type: EnumItem") end
	if Keycode.EnumType ~= Enum.KeyCode then error("Argument 2 must be a keycode enum type.") end

	RemappedSlots[SlotNumber] = Keycode
end

--[[
	Unmap a slot's equip function.
]]
function Backpack:UnmapKeybind(SlotNumber : number)
	isModuleRunning()
	if typeof(SlotNumber) ~= "number" then error("Argument 1 is not of type: number") end

	if RemappedSlots[SlotNumber] then
		RemappedSlots[SlotNumber] = nil
	end
end

--[[
	Equips a tool if it's not currently equipped and unequips it if it is.
]]
function Backpack:Equip(ToolOrSlot, Generic : boolean, RespectsCooldown: boolean)
	isModuleRunning()
	if BackpackIsDisabled then return end
	if not Character then return end
	if not Character:IsDescendantOf(workspace) then return end
	if RespectsCooldown == true then
		if doesHaveEquipCooldown then return end
	end
	if Locked then return end

	doesHaveEquipCooldown = true

	delay(Backpack.Settings.EquipCooldown, function()
		doesHaveEquipCooldown = false
	end)

	-- AAAA WHY ARENT YOU USING HUMANOID:EQUIP() AAGAGAAHA
	-- SHUT UP Humanoid:EquipTool() doesn't support multiple tools so we are just manually parenting the tool

	local Tool = convert(ToolOrSlot, 1)

	if Generic == true then -- If generic then we are just going to look in the hotbar slots
		local TSlot = HotbarSlots[ToolOrSlot]

		if TSlot then
			Tool = TSlot.Tool
		end
	end

	if not Tool then return end
	if not Tool.Parent then return end
	if not Tool.Parent.Parent then return end
	if BackpackInstance.Parent ~= LocalPlayer then return end

	if Tool.Parent ~= Character and Tool.Parent ~= BackpackInstance then
		warn("Not equipping tool because cannot equip tool that is not parent of LocalCharacter or backpack.")
		return
	end

	local HBarSlot = Backpack:GetSlotFromTool(Tool)

	if Backpack.Settings.PreventEquippingOnToolCooldown then
		if ActiveCooldowns[Tool] then return end
	end

	if HBarSlot.Locked then return end
	if HBarSlot.Glued then return end

	if Tool.Parent == Character then
		Tool.Parent = BackpackInstance
		EquippedTools[Tool] = nil

		MoveEquipBar(false)
		return
	end

	if #Backpack:GetEquippedTools() < Backpack.Settings.MaxHeldTools then
		Tool.Parent = Character
		EquippedTools[Tool] = HBarSlot
		MoveEquipBar(HBarSlot)
	else
		-- If the player has the max amount of tools we need to search for a non glued tool to unequip

		for _, Slot in pairs(EquippedTools) do
			if not Slot.Tool then continue end

			if Slot.Tool.Parent == Character and not Slot.Glued then
				Slot.Tool.Parent = BackpackInstance
				Tool.Parent = Character

				EquippedTools[Slot.Tool] = nil
				EquippedTools[Tool] = HBarSlot

				MoveEquipBar(HBarSlot)
				break
			end
		end

	end
end

--[[
	Returns true if the inventory is currently open and false if it's not.
]]
function Backpack:IsInventoryOpen():boolean
	return InventoryIsOpen
end

--[[
	Returns true if the backpack is currently enabled and false if it's not currently enabled.
]]
function Backpack:IsEnabled():boolean
	return not BackpackIsDisabled
end

--[[
	Returns true if the inventory is currently enabled and false if it's not currently enabled.
]]
function Backpack:IsInventoryEnabled():boolean
	return not InventoryIsDisabled
end

--[[
	Opens the inventory.
]]
function Backpack:OpenInventory(RespectsCooldown: boolean)
	isModuleRunning()
	if BackpackIsDisabled then return end
	if InventoryIsOpen then return end
	if RespectsCooldown == true then
		if InvCooldown then return end
	end
	if InventoryIsDisabled then return end

	InventoryIsOpen = true
	InvCooldown = true

	local useAnimation = InvAnimation

	local OrginalSize = InventoryFrame:GetAttribute("Size")
	local OrginalBackgroundTransparency = 0

	local Temp = {}

	setCanUIHighlight(true)

	Animate(BPButton.ImageButton, "BackgroundColor3", Backpack.Settings.BackpackButtonOpenedColor, 6, 11)

	Backpack:PopNotificationIcon(false)

	revealSlots(true)

	Backpack.InventoryOpened:Fire()

	local function fixHighlight()
		for _, Highlight in pairs(HighlightedTools) do
			if not Highlight.PlacementSlot then
				Highlight.Highlight.Position = UDim2.fromOffset(Highlight.Frame.AbsolutePosition.X + GuiService:GetGuiInset().X, Highlight.Frame.AbsolutePosition.Y + GuiService:GetGuiInset().Y)
			end
		end
	end

	if useAnimation == 1 then -- Windows 10 Window open animation
		local Factor = 1.8
		InventoryFrame.Size = UDim2.fromOffset(InventoryFrame.Size.X.Offset / Factor, InventoryFrame.Size.Y.Offset / Factor)
		InventoryFrame.Parent.GroupTransparency = 1

		InventoryFrame.Visible = true

		for _, Stroke in pairs(InventoryFrame:GetDescendants()) do
			if Stroke:IsA("UIStroke") then
				Temp[Stroke] = Stroke.Transparency
			end
		end

		local damping = 1.2
		local ratio = 6

		InventoryFrame.Background.ScrollingFrame.Visible = true

		for Stroke, Org in pairs(Temp) do
			Stroke.Transparency = 1

			Animate(Stroke, "Transparency", Org, damping, ratio)
		end

		Animate(InventoryFrame, "Size", OrginalSize, damping, ratio)
		Animate(InventoryFrame.Parent, "GroupTransparency", OrginalBackgroundTransparency, damping, ratio)

		if Backpack.Settings.Animate == true then
			Spring.completed(InventoryFrame, function()
				InvCooldown = false
			end)
		else
			InvCooldown = false
		end
	end
end

--[[
	Closes the inventory.
]]
function Backpack:CloseInventory(RespectsCooldown: boolean)
	isModuleRunning()
	if BackpackIsDisabled then return end
	if not InventoryIsOpen then return end
	if RespectsCooldown == true then
		if InvCooldown then return end
	end

	if UISelectedSlots[1] then
		Backpack.DragEnded:Fire(UISelectedSlots[1].Tool, UISelectedSlots[1].Frame, nil, true, UDim2.fromOffset(UISelectedSlots[1].Frame.AbsolutePosition.X, UISelectedSlots[1].Frame.AbsolutePosition.Y))
	end

	InventoryIsOpen = false
	InvCooldown = true

	local useAnimation = InvAnimation

	local OrginalSize = InventoryFrame.Size

	local Temp = {}

	setCanUIHighlight(false)
	clearUIHighlights()

	Animate(BPButton.ImageButton, "BackgroundColor3", BackgroundTransparency, 6, 11)

	revealSlots(false)

	Backpack.InventoryClosed:Fire()

	if useAnimation == 1 then
		local damping = 1.2
		local ratio = 6
		local Factor = 1.8

		for _, Stroke in pairs(InventoryFrame:GetDescendants()) do
			if Stroke:IsA("UIStroke") then
				Temp[Stroke] = Stroke.Transparency
			end
		end

		InventoryFrame.Visible = true
		InventoryFrame.Background.ScrollingFrame.Visible = false

		for Stroke, _ in pairs(Temp) do
			Animate(Stroke, "Transparency", 1, damping, ratio)
		end

		Animate(InventoryFrame, "Size", UDim2.fromOffset(InventoryFrame.Size.X.Offset / Factor, InventoryFrame.Size.Y.Offset / Factor), damping, ratio)
		Animate(InventoryFrame.Parent, "GroupTransparency", 1, damping, ratio)

		local function resetFrame()
			if InventoryIsOpen then return end

			InventoryFrame.Size = OrginalSize

			for Stroke, Org in pairs(Temp) do
				Stroke.Transparency = Org
			end

			InventoryFrame.Visible = false
			InvCooldown = false
		end

		if Backpack.Settings.Animate == true then
			Spring.completed(InventoryFrame, resetFrame)
		else
			resetFrame()
		end

	end

	for _, Highlight in pairs(HighlightedTools) do
		if Highlight.Highlight.ActiveValue.Value == true and not Highlight.Slot.PlacementSlot then
			Highlight.Highlight.Parent = InventoryFrame.Parent
		end
	end
end

--[[
	Moves a tool to a certain hotbar slot number.
]]
function Backpack:MoveToolToHotbarSlotNumber(Tool, SlotNumber: number, fromPosition):table
	isModuleRunning()
	if typeof(SlotNumber) ~= "number" then error("Argument 1 is not of type: number") end
	if SlotNumber > Backpack.Settings.MaxHotbarToolSlots then warn("Not moving slot because number is bigger than tool max.") return end
	Tool = convert(Tool, 1)
	if HotbarSlots[SlotNumber].Tool then warn("Not moving tool because a tool occupies slot "..SlotNumber) return end

	if not Tool then
		warn("Tool does not exist within backpack")
		return
	end

	local ToolSlot = Backpack:GetSlotFromTool(Tool)

	if ToolSlot.Glued then return end

	if not ToolSlot.PlacementSlot and not InventoryIsOpen then
		fromPosition = BPButton.Position
	end

	local TargetSlot = HotbarSlots[SlotNumber]

	TargetSlot.Tool = Tool
	TargetSlot.Locked = ToolSlot.Locked

	TargetSlot.Frame.Tool.Value = Tool

	deleteToolSlotData(ToolSlot)

	ToolSlot.Frame.Visible = false

	if InventoryIsOpen and ToolSlot.PlacementSlot then
		ToolSlot.PlacementSlot.Visible = true
		ToolSlot.Frame.Visible = true
	end

	newSlot(Tool, false, SlotNumber)

	-- now we can animate the slot

	if typeof(fromPosition) ~= "UDim2" then if InventoryIsOpen then revealSlots(true) end return end

	local GhostSlot = TargetSlot.Frame:Clone()

	ToolSlot.Frame.Visible = false

	TargetSlot.PlacementSlot.Visible = true

	TargetSlot.Frame.Visible = true
	TargetSlot.Frame.Button.Visible = false

	GhostSlot.Name = "_Ghost"
	GhostSlot.Visible = true
	GhostSlot.Button.Visible = true
	GhostSlot.Group.Visible = true

	GhostSlot.Position = fromPosition
	GhostSlot.Group.Position = UDim2.fromScale(0, 0)
	GhostSlot.Button.Position = UDim2.fromScale(0, 0)

	GhostSlot.Parent = BackpackGui.BackpackMain

	local AbsPos = TargetSlot.PlacementSlot.AbsolutePosition

	Animate(GhostSlot, "Position", UDim2.fromOffset(AbsPos.X + GuiService:GetGuiInset().X, AbsPos.Y + GuiService:GetGuiInset().Y), 1, 6)

	if Backpack.Settings.Animate == true then
		local Moving = true

		spawn(function()
			while Moving do
				if not TargetSlot then break end

				MoveEquipBar(false)

				if TargetSlot.Tool ~= Tool then
					TargetSlot.Frame.Button.Visible = true
					GhostSlot.Visible = false
				end

				wait()
			end
		end)

		Spring.completed(GhostSlot, function()
			Moving = false
			if TargetSlot.Tool == Tool then
				TargetSlot.Frame.Button.Visible = true
			end
			GhostSlot:Destroy()
		end) 
	else
		if TargetSlot.Tool == Tool then
			TargetSlot.Frame.Button.Visible = true
		end

		GhostSlot:Destroy()
	end

	return TargetSlot
end

--[[
	Moves a tool to the inventory.
]]
function Backpack:MoveToolToInventory(Tool: Tool, fromPosition: UDim2):table
	Tool = convert(Tool, 1)

	if not Tool then
		warn("Tool does not exist within backpack")
		return
	end

	local ToolSlot = Backpack:GetSlotFromTool(Tool)

	if not fromPosition then
		local Location = ToolSlot.Frame.AbsolutePosition

		fromPosition = UDim2.fromOffset(Location.X + GuiService:GetGuiInset().X, Location.Y + GuiService:GetGuiInset().Y)
	end

	if ToolSlot.Glued then return end

	if not ToolSlot.PlacementSlot then
		return -- Tool is already in inventory
	end

	local TargetSlot = newSlot(Tool, true) -- No animation will play when set to true

	local Previous = advanceCanvasToPosition(InventoryFrame.Background.ScrollingFrame, TargetSlot.Frame)

	TargetSlot.Glued = ToolSlot.Glued
	TargetSlot.Locked = ToolSlot.Locked
	TargetSlot.ViewportEnabled = ToolSlot.ViewportEnabled
	TargetSlot.ViewportOffset = ToolSlot.ViewportOffset

	deleteToolSlotData(ToolSlot)
	refreshSlot(TargetSlot)

	ToolSlot.Frame.Visible = false

	if InventoryIsOpen then
		local GhostSlot = TargetSlot.Frame:Clone()

		if not isSearching then
			TargetSlot.Frame.Visible = true
		end

		GhostSlot.Name = "_Ghost"
		GhostSlot.Visible = false
		GhostSlot.Button.Visible = true
		GhostSlot.Group.Visible = true

		GhostSlot.Position = fromPosition
		GhostSlot.Group.Position = UDim2.fromScale(0, 0)
		GhostSlot.Button.Position = UDim2.fromScale(0, 0)

		GhostSlot.Parent = BackpackGui.BackpackMain

		local AbsPos = TargetSlot.Frame.AbsolutePosition

		local ScrollingFrame = InventoryFrame.Background.ScrollingFrame
		local now = ScrollingFrame.CanvasPosition

		local clipped, distance = isClipped(TargetSlot.Frame, InventoryFrame) 

		if clipped or distance > 40 then
			ScrollingFrame.CanvasPosition = Previous
		end

		Animate(
			GhostSlot,
			"Position",
			UDim2.fromOffset(AbsPos.X + GuiService:GetGuiInset().X, AbsPos.Y + GuiService:GetGuiInset().Y),
			1,
			6
		)

		ScrollingFrame.CanvasPosition = Previous

		if clipped or distance > 40 then
			Animate(ScrollingFrame, "CanvasPosition", now, 0.8, 6)
		end

		if Backpack.Settings.Animate == true then
			spawn(function()
				while GhostSlot.Parent do

					if isClipped(GhostSlot, InventoryFrame) then
						GhostSlot.Visible = false
					else
						GhostSlot.Visible = true
					end

					if not TargetSlot then GhostSlot.Visible = false end
					if TargetSlot.Tool ~= Tool then GhostSlot.Visible = false end

					if TargetSlot.Tool == Tool then
						SlotChangedSignal:Fire(TargetSlot.PlacementSlot or TargetSlot)
					end

					MoveEquipBar(false)

					wait()
				end
			end) 
		end

		revealSlots(true)

		TargetSlot.Frame.Button.Visible = false

		if Backpack.Settings.Animate == true then
			Spring.completed(GhostSlot, function()
				if TargetSlot and TargetSlot.Tool == Tool and (Tool.Parent == Character or Tool.Parent == BackpackInstance) then -- This may make it safe.
					TargetSlot.Frame.Button.Visible = true
				end

				GhostSlot:Destroy()
			end)            
		else
			GhostSlot:Destroy()
			TargetSlot.Frame.Button.Visible = true
		end

	else
		local GhostSlot = TargetSlot.Frame:Clone()

		GhostSlot.Tool:Destroy()
		GhostSlot.Parent = BackpackGui.BackpackMain

		GhostSlot.Name = "_Ghost"

		GhostSlot.Button.ToolNum.Text = ""

		TargetSlot.Frame.Button.Visible = false

		GhostSlot.Position = fromPosition
		GhostSlot.Group.Position = UDim2.fromScale(0, 0)
		GhostSlot.Button.Position = UDim2.fromScale(0, 0)
		GhostSlot.Visible = true
		GhostSlot.Button.Visible = true

		local Pos1 = GhostSlot.Position
		local Pos2 = BPButton.Position

		local OrgSize = GhostSlot.Size

		local Div = 1.6
		local Damping = 1.6
		local Ratio = 8

		GhostSlot.Button.Parent = GhostSlot.Group

		Animate(GhostSlot, "Position", Pos2, Damping, Ratio)
		Animate(GhostSlot.Group, "GroupTransparency", 1, Damping, Ratio)

		if Backpack.Settings.Animate == true then
			delay(.32, function()

				if TargetSlot and TargetSlot.Tool == Tool and (Tool.Parent == Character or Tool.Parent == BackpackInstance) then
					TargetSlot.Frame.Button.Visible = true
				end

				GhostSlot.Visible = false
			end)

			Spring.completed(GhostSlot, function()
				GhostSlot:Destroy()
			end)

		else
			TargetSlot.Frame.Button.Visible = true
			GhostSlot:Destroy()
		end
	end

	return TargetSlot
end

--[[
	Moves a tool to a free hotbar slot if one exist.
]]
function Backpack:MoveToolToHotbar(Tool : Tool, fromPosition : UDim2):table
	isModuleRunning()
	Tool = convert(Tool, 1)

	if not Tool then
		warn("Tool does not exist within backpack")
		return
	end

	local ToolSlot = Backpack:GetSlotFromTool(Tool)

	if not fromPosition and InventoryIsOpen then 
		local Location = ToolSlot.Frame.AbsolutePosition

		fromPosition = UDim2.fromOffset(Location.X + GuiService:GetGuiInset().X, Location.Y + GuiService:GetGuiInset().Y)
	end

	if ToolSlot.Glued then return end

	if ToolSlot.PlacementSlot then
		return -- Exit out if the tool is already in the hotbar
	end

	local Slot = findNextAvaliableSlot()

	if not Slot then
		warn("Not moving tool to hotbar because the hotbar currently has the max amount of allowed tools. Please move a tool first.")
		return
	end

	local TargetSlot = HotbarSlots[Slot]

	if not InventoryIsOpen then 
		local Location = TargetSlot.Frame.AbsolutePosition

		fromPosition = UDim2.fromOffset(Location.X + GuiService:GetGuiInset().X, Location.Y + GuiService:GetGuiInset().Y)
	end

	TargetSlot.Tool = Tool
	TargetSlot.Glued = ToolSlot.Glued
	TargetSlot.Locked = ToolSlot.Locked
	TargetSlot.ViewportEnabled = ToolSlot.ViewportEnabled
	TargetSlot.ViewportOffset = ToolSlot.ViewportOffset

	TargetSlot.IsAnimating = true

	TargetSlot.Frame.Tool.Value = Tool

	deleteToolSlotData(ToolSlot)
	refreshSlot(TargetSlot)

	-- now we can animate the slot

	if InventoryIsOpen then
		local GhostSlot = TargetSlot.Frame:Clone()

		ToolSlot.Frame.Visible = false

		TargetSlot.PlacementSlot.Visible = true

		TargetSlot.Frame.Visible = true

		TargetSlot.Frame.Button.ToolName.Visible = false
		TargetSlot.Frame.Button.ViewportFrame.Visible = false
		TargetSlot.Frame.Button.ToolImage.Visible = false

		GhostSlot.Name = "_Ghost"
		GhostSlot.Visible = true
		GhostSlot.Button.Visible = true
		GhostSlot.Group.Visible = true

		GhostSlot.Position = fromPosition
		GhostSlot.Group.Position = UDim2.fromScale(0, 0)
		GhostSlot.Button.Position = UDim2.fromScale(0, 0)

		GhostSlot.Parent = BackpackGui.BackpackMain

		local AbsPos = TargetSlot.PlacementSlot.AbsolutePosition

		Animate(GhostSlot, "Position", UDim2.fromOffset(AbsPos.X + GuiService:GetGuiInset().X, AbsPos.Y + GuiService:GetGuiInset().Y), 1, 6)

		if Backpack.Settings.Animate == true then
			local Moving = true

			delay(.3, function()
				GhostSlot.Visible = false
				if TargetSlot.Tool == Tool then
					refreshSlot(TargetSlot)
					GhostSlot.Visible = false
				end
			end)

			spawn(function()
				while Moving do
					if not TargetSlot then break end

					MoveEquipBar(false)

					if TargetSlot.Tool ~= Tool then
						GhostSlot.Visible = false
					end

					wait()
				end
			end)

			Spring.completed(GhostSlot, function()
				TargetSlot.IsAnimating = false
				Moving = false

				if TargetSlot.Tool == Tool then 
					refreshSlot(TargetSlot) -- i forgot why i added this but im just keeping it cause idk what might happen
				end
				GhostSlot:Destroy()
			end) 
		else
			TargetSlot.IsAnimating = false
			GhostSlot:Destroy()
			refreshSlot(TargetSlot)
		end
	else
		local GhostSlot = TargetSlot.Frame:Clone()

		ToolSlot.Frame.Visible = false

		TargetSlot.PlacementSlot.Visible = true

		TargetSlot.Frame.Visible = true

		TargetSlot.Frame.Button.ToolName.Visible = false
		TargetSlot.Frame.Button.ViewportFrame.Visible = false
		TargetSlot.Frame.Button.ToolImage.Visible = false


		GhostSlot.Tool:Destroy()
		GhostSlot.Parent = BackpackGui.BackpackMain

		GhostSlot.Name = "_Ghost"

		GhostSlot.Button.ToolNum.Text = ""

		TargetSlot.Frame.Button.Visible = false
		GhostSlot.Group.GroupTransparency = 1

		GhostSlot.Position = BPButton.Position
		GhostSlot.Group.Position = UDim2.fromScale(0, 0)
		GhostSlot.Button.Position = UDim2.fromScale(0, 0)
		GhostSlot.Visible = true
		GhostSlot.Button.Visible = true

		local Pos1 = GhostSlot.Position
		local Pos2 = fromPosition

		local OrgSize = GhostSlot.Size

		local Damping = 1.6
		local Ratio = 8

		local AbsPos = TargetSlot.PlacementSlot.AbsolutePosition

		GhostSlot.Button.Parent = GhostSlot.Group

		Animate(GhostSlot, "Position", UDim2.fromOffset(AbsPos.X + GuiService:GetGuiInset().X + 30, AbsPos.Y + GuiService:GetGuiInset().Y + 30), Damping, Ratio)
		Animate(GhostSlot.Group, "GroupTransparency", 0, Damping, Ratio)

		if Backpack.Settings.Animate == true then
			local ToolTemp = TargetSlot.Tool
			local Moving = true
			delay(.32, function()

				if ToolTemp == TargetSlot.Tool then
					TargetSlot.Frame.Button.Visible = true
				end

				GhostSlot.Visible = false
			end)

			spawn(function()
				while Moving do
					if not TargetSlot then break end
					if not TargetSlot.Tool then break end 

					if GhostSlot.Parent then
						refreshSlot(TargetSlot)
						local Location = TargetSlot.Frame.AbsolutePosition

					end
					wait()
				end
			end)

			Spring.completed(GhostSlot, function()

				if TargetSlot.Tool == Tool then
					refreshSlot(TargetSlot)
				end

				Moving = false
				TargetSlot.IsAnimating = false
				GhostSlot:Destroy()
			end)

		else
			TargetSlot.IsAnimating = false
			TargetSlot.Frame.Button.Visible = true
			GhostSlot:Destroy()
		end
	end

	return TargetSlot
end

--[[
	Swaps two tools.
]]
function Backpack:SwapTools(Tool1, Tool2):(table | table)
	isModuleRunning()

	Tool1 = convert(Tool1, 1)
	Tool2 = convert(Tool2, 2)

	if not Tool1 or not Tool2 then
		warn("Could not find 2 tools to swap with.")
		return
	end

	if Tool1 == Tool2 then
		warn("Cannot swap the same tool.")
		return
	end

	local inBP = false
	local inHB = false

	local Tool1Type
	local Tool2Type

	local Slot1 = Backpack:GetSlotFromTool(Tool1)
	local Slot2 = Backpack:GetSlotFromTool(Tool2)

	if Slot1.Glued or Slot2.Glued then return end -- Cannot swap with a glued slot

	local Clone1 = table.clone(Slot1)
	local Clone2 = table.clone(Slot2)

	Slot1.Tool = Clone2.Tool
	Slot1.Locked = Clone2.Locked
	Slot1.ViewportEnabled = Clone2.ViewportEnabled
	Slot1.ViewportOffset = Clone2.ViewportOffset
	Slot1.IsAnimating = true

	Slot2.Tool = Clone1.Tool
	Slot2.Glued = Clone1.Glued
	Slot2.Locked = Clone1.Locked
	Slot2.ViewportEnabled = Clone1.ViewportEnabled
	Slot2.ViewportOffset = Clone1.ViewportOffset
	Slot2.IsAnimating  = true

	Slot2.Frame.Tool.Value = Tool1
	Slot1.Frame.Tool.Value = Tool2

	local function hotfixHighlights()
		for _, Highlight in pairs(HighlightedTools) do
			if Highlight.Tool == Tool1 and Tool1.Parent == Character then
				Highlight.Frame = Slot2.Frame

				if Slot2.PlacementSlot then
					SlotChangedSignal:Fire(Slot2.PlacementSlot)
				else
					SlotChangedSignal:Fire(Slot2)
				end

				MoveEquipBar(Slot2)
			elseif Highlight.Tool == Tool2 and Tool2.Parent == Character then
				Highlight.Frame = Slot1.Frame

				if Slot1.PlacementSlot then
					SlotChangedSignal:Fire(Slot1.PlacementSlot)
				else
					SlotChangedSignal:Fire(Slot1)
				end

				MoveEquipBar(Slot1)
			end -- Hotfix for fixing highlights
		end
	end

	if Backpack.Settings.Animate == false then refreshSlot(Slot1) refreshSlot(Slot2) hotfixHighlights() return end

	if not Slot1.PlacementSlot then
		Tool1Type = "BP"
		inBP = true
	end

	if Slot1.PlacementSlot then
		Tool1Type = "HB"
		inHB = true
	end

	if not Slot2.PlacementSlot then
		Tool2Type = "BP"
		inBP = true
	end

	if Slot2.PlacementSlot then
		Tool2Type = "HB"
		inHB = true
	end

	local function normalSwap()
		local GhostSlot1 = Slot1.Frame:Clone()
		local GhostSlot2 = Slot2.Frame:Clone()

		GhostSlot1.Name = "_Ghost"
		GhostSlot2.Name = "_Ghost"

		GhostSlot1.Position = UDim2.fromOffset(Slot1.Frame.AbsolutePosition.X + GuiService:GetGuiInset().X, Slot1.Frame.AbsolutePosition.Y + GuiService:GetGuiInset().Y)
		GhostSlot2.Position = UDim2.fromOffset(Slot2.Frame.AbsolutePosition.X + GuiService:GetGuiInset().X, Slot2.Frame.AbsolutePosition.Y + GuiService:GetGuiInset().Y)

		GhostSlot1.Visible = true
		GhostSlot2.Visible = true

		GhostSlot1.Button.ToolNum.Text = ""
		GhostSlot2.Button.ToolNum.Text = ""

		Slot1.Frame.Button.Visible = false
		Slot2.Frame.Button.Visible = false

		GhostSlot1.Parent = BackpackGui.BackpackMain
		GhostSlot2.Parent = BackpackGui.BackpackMain

		local Pos1 = GhostSlot1.Position
		local Pos2 = GhostSlot2.Position

		Animate(GhostSlot1, "Position", Pos2, 1, 6)
		Animate(GhostSlot2, "Position", Pos1, 1, 6)

		if Backpack.Settings.Animate == true then
			local Moving = true
			delay(.16, function()

				Slot1.Frame.Button.Visible = true
				Slot2.Frame.Button.Visible = true 

				if Slot1.Tool == Clone2.Tool then 
					Slot1.IsAnimating = false
				end

				if Slot2.Tool == Clone1.Tool then
					Slot1.IsAnimating = false
				end

				GhostSlot1.Visible = false
				GhostSlot2.Visible = false
			end)

			spawn(function()
				while Moving do
					if not Slot1 then break end
					if not Slot2 then break end

					if Slot1.Tool ~= Clone2.Tool then
						GhostSlot1.Visible = false
					end

					if Slot2.Tool ~= Clone1.Tool then
						GhostSlot2.Visible = false
					end

					wait()
				end
			end)

			Spring.completed(GhostSlot1, function()
				Moving = false
				GhostSlot1:Destroy()
				GhostSlot2:Destroy()
			end) 

		else
			Slot1.Frame.Button.Visible = true
			Slot2.Frame.Button.Visible = true 
			GhostSlot1.Visible = false
			GhostSlot2.Visible = false
			GhostSlot1:Destroy()
			GhostSlot2:Destroy()
		end
	end

	local function specialSwap(main, BPSlot)
		local GhostSlot1 = main.Frame:Clone()
		local GhostSlot2 = BPSlot.Frame:Clone()

		GhostSlot1.Tool:Destroy()
		GhostSlot2.Tool:Destroy()

		GhostSlot1.Name = "_Ghost"
		GhostSlot2.Name = "_Ghost"

		GhostSlot1.Visible = true
		GhostSlot2.Visible = true

		GhostSlot1.Button.ToolNum.Text = ""
		GhostSlot2.Button.ToolNum.Text = ""

		main.Frame.Button.Visible = false

		GhostSlot1.Position = UDim2.fromOffset(main.Frame.AbsolutePosition.X + GuiService:GetGuiInset().X, main.Frame.AbsolutePosition.Y + GuiService:GetGuiInset().Y)
		GhostSlot2.Position = UDim2.fromOffset(BPButton.AbsolutePosition.X + GuiService:GetGuiInset().X, BPButton.AbsolutePosition.Y + GuiService:GetGuiInset().Y)

		GhostSlot1.Parent = BackpackGui.BackpackMain
		GhostSlot2.Parent = BackpackGui.BackpackMain

		local Pos1 = GhostSlot1.Position
		local Pos2 = GhostSlot2.Position

		local OrgSize = GhostSlot2.Size

		local Div = 1.6
		local Damping = 1.6
		local Ratio = 8

		GhostSlot1.Button.Parent = GhostSlot1.Group

		GhostSlot2.Size = UDim2.new(OrgSize.X.Scale / Div, OrgSize.X.Offset / Div, OrgSize.Y.Scale / Div, OrgSize.Y.Offset / Div)

		Animate(GhostSlot1, "Position", Pos2, Damping, Ratio)
		Animate(GhostSlot2, "Position", Pos1, Damping, Ratio)

		Animate(GhostSlot1.Group, "GroupTransparency", 1, Damping, Ratio)
		Animate(GhostSlot2, "Size", OrgSize, Damping, Ratio)

		if Backpack.Settings.Animate == true then
			local ToolTemp = main.Tool
			delay(.32, function()

				if ToolTemp == main.Tool then
					main.Frame.Button.Visible = true
				end
				GhostSlot1.Visible = false
				GhostSlot2.Visible = false
				Slot2.IsAnimating  = false
				Slot1.IsAnimating  = false
			end)

			Spring.completed(GhostSlot1, function()
				Slot2.IsAnimating  = false
				Slot1.IsAnimating  = false
				GhostSlot1:Destroy()
				GhostSlot2:Destroy()
			end)

		else
			Slot2.IsAnimating  = false
			Slot1.IsAnimating  = false
			main.Frame.Button.Visible = true
			GhostSlot1.Visible = false
			GhostSlot2.Visible = false
			GhostSlot1:Destroy()
			GhostSlot2:Destroy()
		end

	end

	if inBP and not inHB then
		if not InventoryIsOpen then return end -- do nothing

		normalSwap()
	elseif inHB and not inBP then
		normalSwap()
	elseif inBP and inHB then
		if InventoryIsOpen then

			local swapped = false


			if Tool1Type == "BP" then 
				if isClipped(Slot1.Frame, InventoryFrame.Background.ScrollingFrame) then
					swapped = true
				end

			elseif Tool2Type == "BP" then
				if isClipped(Slot2.Frame, InventoryFrame.Background.ScrollingFrame) then
					swapped = true
				end
			end

			if not swapped then normalSwap() end
		else

			if Tool1Type == "HB" then
				specialSwap(Slot1, Slot2)
			else
				specialSwap(Slot2, Slot1)
			end

		end
	end

	hotfixHighlights()

	refreshSlot(Slot1)
	refreshSlot(Slot2)

	return Slot1, Slot2
end

--[[
    Sorts the tools in the hotbar filling any missing gap.
]]
function Backpack:SortTools()
    for _, Slot in ipairs(HotbarSlots) do
        if Slot.Tool and not Slot.Preferred then

            for i, ToolSlot in ipairs(HotbarSlots) do
                if ToolSlot.Position >= Slot.Position then continue end
                if ToolSlot.Tool then continue end

                ToolSlot.Tool = Slot.Tool
                ToolSlot.Glued = Slot.Glued
                ToolSlot.ViewportEnabled = Slot.ViewportEnabled
                ToolSlot.ViewportOffset = Slot.ViewportOffset
                ToolSlot.Preferred = Slot.Preferred
                ToolSlot.Locked = Slot.Locked

                deleteToolSlotData(Slot)

                refreshSlot(ToolSlot, true)

            --    Backpack:MoveToolToHotbarSlotNumber(Slot.Tool, i, nil, true)
                break
            end
        end
    end
end

--[[
	Shows the notification icon on the backpack icon.
]]
function Backpack:PopNotificationIcon(State : boolean)
	if typeof(State) ~= "boolean" then error("Argument 1 is not of type: boolean") end

	BPButton.Notification.Visible = State
end

--[[
	Unequips non glued tools.
]]
function Backpack:UnequipTools()
	if not Character then return end

	for Tool, ToolData in pairs(EquippedTools) do
		if Tool.Parent == Character and not ToolData.Glued then
			Backpack:Equip(Tool, nil, true)
		end
	end
end

--[[
	Returns a table of all tools that are currently equipped.
]]
function Backpack:GetEquippedTools():table
	local Tools = {}

	if LocalPlayer.Character then
		for _, v in pairs(LocalPlayer.Character:GetChildren()) do
			if v:IsA("Tool") then 
				table.insert(Tools, v)
			end
		end
	end

	return Tools
end

--[[
	Returns a table of all tools that are currently in the backpack and on the current character.
]]
function Backpack:GetTools()
	local Tools = {}

	if LocalPlayer:FindFirstChild("Backpack") then
		for _,v in pairs(LocalPlayer.Backpack:GetChildren()) do
			if v:IsA("Tool") then
				table.insert(Tools, v)
			end
		end
	end

	if LocalPlayer.Character then
		for _, v in pairs(LocalPlayer.Character:GetChildren()) do
			if v:IsA("Tool") then 
				table.insert(Tools, v)
			end
		end
	end

	return Tools
end

--[[
	Returns the slot data for a certain tool.
]]
function Backpack:GetSlotFromTool(Tool : Tool):table
	isModuleRunning()
	if typeof(Tool) ~= "Instance" then error("Argument one is not of type: Instance") end
	if not Tool:IsA("Tool") then error("Argument 1 is not a tool.") end

	for _, Slot in pairs(HotbarSlots) do
		if Slot.Tool == Tool then 
			return Slot
		end
	end

	for _, Slot in pairs(GluedSlots) do
		if Slot.Tool == Tool then
			return Slot
		end
	end

	for _, Slot in pairs(BackpackSlots) do
		if Slot.Tool == Tool then
			return Slot
		end
	end

end

--[[
	Returns the slot data for a certain tool slot.
]]
function Backpack:GetSlotFromNumber(Number : number):table
	isModuleRunning()
	if typeof(Number) ~= "number" then error("Argument 1 is not of type: number") end
	if Number % 1 ~= 0 then error("Argument 1 must be a integer (whole number)") end

	if Number < 1 then
		return nil
	end

	local HBSlots = Backpack:GetHotbarTools()
	local BPSlots = Backpack:GetInventoryTools()

	if Number > (#HBSlots + #BPSlots) then
		return nil
	end

	if Number < Backpack.Settings.MaxHotbarToolSlots then
		if HotbarSlots[Number].Tool then
			return HotbarSlots[Number]
		end
	else
		for _, Slot in pairs(BackpackSlots) do
			if Slot.Position == Number then
				return Slot
			end
		end
	end

end

--[[
	Returns a table of all tools that are currently in the hotbar.
]]
function Backpack:GetHotbarTools():table
	isModuleRunning()
	local Tools = {}

	for _, Slot in ipairs(HotbarSlots) do
		if Slot.Tool then
			table.insert(Tools, Slot.Tool)
		end
	end

	return Tools
end

--[[
	Returns a table of all tools that are currently in the inventory.
]]
function Backpack:GetInventoryTools():table
	isModuleRunning()
	local Tools = {}

	for _, Slot in ipairs(BackpackSlots) do
		if Slot.Tool then
			table.insert(Tools, Slot.Tool)
		end
	end

	return Tools
end

--[[
	Enables or disables the viewport frame displaying the physical tool.
]]
function Backpack:SetViewportEnabled(ToolOrSlot, boolean : boolean)
	isModuleRunning()
	if typeof(boolean) ~= "boolean" then error("Argument 1 is not of type: boolean") end

	local Tool = convert(ToolOrSlot, 2)
	local Slot = Backpack:GetSlotFromTool(Tool)

	Slot.ViewportEnabled = boolean
	refreshSlot(Slot)
end

--[[
	Sets the camera offset for the viewport frame displaying the physical tool.
]]
function Backpack:SetViewportOffset(ToolOrSlot, OffsetCFrame : CFrame)
	isModuleRunning()
	if typeof(OffsetCFrame) ~= "CFrame" then error("Argument 1 is not of type: CFrame") end

	local Tool = convert(ToolOrSlot, 2)
	local Slot = Backpack:GetSlotFromTool(Tool)

	Slot.ViewportOffset = OffsetCFrame
	refreshSlot(Slot)
end

--[[
	Forces a tool to be equipped at all times and prevents said tool from being moved (This will not use a hotbar slot).
]]
function Backpack:GlueTool(ToolOrSlot)
	isModuleRunning()

	local Tool = convert(ToolOrSlot, 1)

	local Num = findNextAvaliableGlueSlot()

	if not Num then warn("Cannot glue "..Tool.Name.." because only "..MaxGluedSlots.." tool(s) can be glued at a time.") return end

	onParentUpdate(Tool, nil, true)

	local GlueSlot = GluedSlots[Num]
	GlueSlot.Glued = true
	GlueSlot.Tool = Tool

	refreshSlot(GlueSlot)

	EquippedTools[Tool] = GlueSlot

	local Abs = GlueSlot.PlacementSlot.AbsolutePosition

	if Backpack.Settings.Animate == true then
		Spring.stop(GlueSlot.Frame, "Position")
	end

	if #Backpack:GetEquippedTools() >= Backpack.Settings.MaxHeldTools then
		for _, Slot in pairs(EquippedTools) do
			if not Slot.Tool then continue end

			if Slot.Tool.Parent == Character and not Slot.Glued then
				Slot.Tool.Parent = BackpackInstance

				MoveEquipBar(false, Slot.Frame, 0)

				EquippedTools[Slot.Tool] = nil
				break
			end
		end
	end

	defer(function()
		if Tool.Parent ~= Character then
			Tool.Parent = Character
		end
	end)

	GlueSlot.Frame.Position = UDim2.fromOffset(Abs.X + GuiService:GetGuiInset().X, Abs.Y + GuiService:GetGuiInset().Y + 100)
	Animate(GlueSlot.Frame, "Position", UDim2.fromOffset(Abs.X + GuiService:GetGuiInset().X, Abs.Y + GuiService:GetGuiInset().Y), .76, 3)
end

--[[
	Removes a glued tool, returning it back to normal.
]]
function Backpack:RemoveGlue(ToolOrSlot)
	isModuleRunning()
	if not LocalPlayer.Character then return end

	local Tool = convert(ToolOrSlot, 1)

	local Slot = Backpack:GetSlotFromTool(Tool)

	onParentUpdate(Tool, nil, true)

	newSlot(Tool)
end

--[[
	Disables the inventory, prevents it from being used, and closes it if it's currently open.
]]
function Backpack:DisableInventory()
	isModuleRunning()
	InventoryIsDisabled = true
	BPButton.Visible = false

	spawn(function()
		if InvCooldown then repeat wait() until not InvCooldown end

		if InventoryIsOpen then Backpack:CloseInventory(true) end
	end)
end

--[[
	Enables the inventory.
]]
function Backpack:EnableInventory()
	isModuleRunning()
	InventoryIsDisabled = false

	BPButton.Visible = true
end

--[[
	Prevents a tool from being equipped.
]]
function Backpack:LockTool(ToolOrSlot)
	isModuleRunning()
	local Tool = convert(ToolOrSlot, 1)	

	local Slot = Backpack:GetSlotFromTool(Tool)

	Slot.Locked = true
	Slot.Frame.Button.LockImg.Visible = true
end

--[[
	Unlocks a tool letting it be equipped again.
]]
function Backpack:UnlockTool(ToolOrSlot)
	isModuleRunning()
	local Tool = convert(ToolOrSlot, 1)	

	local Slot = Backpack:GetSlotFromTool(Tool)

	Slot.Locked = false
	Slot.Frame.Button.LockImg.Visible = false
end

--[[
	Stops rendering the backpack and prevents it from responding to user input.
]]
function Backpack:Disable()
	isModuleRunning()
	BackpackIsDisabled = true

	BackpackGui.BackpackMain.Visible = false
	BPButton.Visible = false
end

--[[
	Starts rendering the backpack, and makes the backpack respond to user input again.
]]
function Backpack:Enable()
	isModuleRunning()
	BackpackIsDisabled = false

	BackpackGui.BackpackMain.Visible = true

	if not InventoryIsDisabled then
		BPButton.Visible = true
	end
end

--[[
	Returns the current backpack instance being used by the BackpackScript.
]]
function Backpack:GetBackpack():Backpack
	return BackpackInstance
end

--[[
	Puts the tool on cooldown which displays on the tool slot.
]]
function Backpack:SetCooldown(Tool, Seconds: number)
	isModuleRunning()
	local Tool = convert(Tool, 1)

	if not Tool then return end

	if typeof(Seconds) ~= "number" then error("Argument 3 is not of type: number") end

	local TempConnection
	local Slot = Backpack:GetSlotFromTool(Tool)
	local StartingServerTime = workspace:GetServerTimeNow()

	Slot.Frame.Button.CooldownFrame.Size = UDim2.fromScale(1, 1)

	Seconds = Seconds or 0

	ActiveCooldowns[Tool] = {Started = false, StartTime = StartingServerTime, Seconds = Seconds}
end

--[[
	Returns true if the tool has a cooldown active and false if the tool does not have a cooldown active.
]]
function Backpack:IsOnCooldown(Tool):boolean
	isModuleRunning()
	local Tool = convert(Tool, 1)

	if not Tool then return false end

	local Slot = Backpack:GetSlotFromTool(Tool)

	local isOnCooldown = false

	if ActiveCooldowns[Tool] then
		isOnCooldown = true
	end

	return isOnCooldown
end

--[[
	Starts the backpack, builds the gui, disables Roblox's default backpack, and only runs once.
]]
function Backpack.StartBackpack()
	if BackpackStarted then return end

	if not LocalPlayer then
		PlayersService:GetPropertyChangedSignal("LocalPlayer"):Wait()

		LocalPlayer = PlayersService.LocalPlayer
	end

	BackpackStarted = true

	BuildGui()

	HoverStartedInternal:Connect(function(Frame)
		if not Frame.Tool.Value then return end 
		if Frame.Tool.Value.ToolTip == "" then return end

		if UserInputService.TouchEnabled then
			if not InventoryIsOpen then return end
		end

		local Slot = Backpack:GetSlotFromTool(Frame.Tool.Value)

		HoverStart(Slot)
	end)

	HoverEndedInternal:Connect(function(Frame)
		if not Frame.Tool.Value then return end 

		local Slot = Backpack:GetSlotFromTool(Frame.Tool.Value)

		HoverEnd(Slot)
	end)

	SetBackpack(waitForChildOfClass("Backpack", LocalPlayer))

	LocalPlayer.ChildAdded:Once(function(Child)
		if Child.ClassName == "Backpack" then
			SetBackpack(Child)
		end
	end)

	UserInputService.InputBegan:Connect(function(InputObject, processed)
		if processed then return end
		if BackpackIsDisabled then return end

		if table.find(Backpack.Settings.INVENTORY_OPENANDCLOSE_KEYCODES, InputObject.KeyCode) then

			if InventoryIsOpen then
				Backpack:CloseInventory(true)
			else
				Backpack:OpenInventory(true)
			end

			return
		end

		local Keycode 

		for Position, Key in pairs(RemappedSlots) do
			if Key == InputObject.KeyCode then
				Keycode = Position
				break
			end
		end

		if Keycode then
			if HotbarSlots[Keycode] then
				Backpack:Equip(Keycode, nil, true)
			end

			return
		end

		if GuiService.SelectedObject and GuiService.SelectedObject.Name == "ControllerSelectionFrame" and InventoryIsOpen and Backpack.Settings.CanOrganize then
			local Target

			local function findToolValue(inst)
				if not inst then return nil end
				if not inst.Parent then
					return nil
				end

				local thingValue = inst:FindFirstChildWhichIsA("ObjectValue")

				if thingValue and thingValue.Name == "Tool" then
					Target = thingValue
				end

				findToolValue(inst.Parent)
			end

			findToolValue(GuiService.SelectedObject)

			if table.find(Backpack.Settings.FASTMOVE_KEYCODES, InputObject.KeyCode) then

				if not Target then return end
				if not Target.Value then return end

				local Slot = Backpack:GetSlotFromTool(Target.Value)
				local NewPosition = UDim2.fromOffset(Slot.Frame.Button.AbsolutePosition.X  + (Slot.Frame.Button.AbsoluteSize.X / 2), (Slot.Frame.Button.AbsolutePosition.Y + (Slot.Frame.Button.AbsoluteSize.Y / 2)))

				local NewSlot
				local NewerSlot

				if not Slot.PlacementSlot then
					if #Backpack:GetHotbarTools() >= Backpack.Settings.MaxHotbarToolSlots then return end

					NewSlot = Backpack:MoveToolToHotbar(Slot.Tool, NewPosition)
				else
					NewSlot = Backpack:MoveToolToInventory(Slot.Tool, NewPosition)
				end

				local NextHBSlot, max, _, didClamp = findTakenHotbarSlot(Slot.Position, 1)
				NewerSlot = HotbarSlots[NextHBSlot]

				if Slot.Position >= max then
					local NextInvSlot = findTakenInventorySlot(Slot.Position - Backpack.Settings.MaxHotbarToolSlots, 1)

					if not BackpackSlots[NextInvSlot] then return end

					NewerSlot = BackpackSlots[NextInvSlot]
				end

				GuiService.SelectedObject = nil

				spawn(function()
					while NewerSlot.Tool do
						if NewerSlot.Frame.Button.Visible == false then
							wait()
							continue
						else
							break
						end
					end
				end)

				GuiService.SelectedObject = NewerSlot.Frame.Button.ControllerSelectionFrame
				return
			elseif table.find(Backpack.Settings.GUI_SELECTION_KEYCODES, InputObject.KeyCode) then
				-- Controller support for swapping is handled here

				local Slot

				if not Target then return end

				local use = Target.Parent.Name

				if use == "0" then
					use = "10"
				end

				if not Target.Value then
					if HotbarSlots[tonumber(use)] then
						Slot = HotbarSlots[tonumber(use)]
					else
						return
					end
				end

				Slot = Slot or Backpack:GetSlotFromTool(Target.Value)
				
				if Slot.Locked then return end
				if Slot.Glued then return end

				table.insert(UISelectedSlots, Slot)

				if #UISelectedSlots > 1 then
					local Slot1, Slot2 = clearUIHighlights()

					if Slot1 == Slot2 then Backpack.DragEnded:Fire(Slot1.Tool, Slot1.Frame, nil, true, UDim2.fromOffset(Slot1.Frame.AbsolutePosition.X, Slot1.Frame.AbsolutePosition.Y)) return end
					if not Slot1.Tool then Backpack.DragEnded:Fire(Slot1.Tool, Slot1.Frame, nil, true, UDim2.fromOffset(Slot2.Frame.AbsolutePosition.X, Slot2.Frame.AbsolutePosition.Y)) return end

					if Slot1.Tool and not Slot2.Tool then
						if #Backpack:GetHotbarTools() >= Backpack.Settings.MaxHotbarToolSlots then Backpack.DragEnded:Fire(Slot1.Tool, Slot1.Frame, nil, true, UDim2.fromOffset(Slot2.Frame.AbsolutePosition.X, Slot2.Frame.AbsolutePosition.Y)) return end

						Backpack:MoveToolToHotbarSlotNumber(Slot1.Tool, tonumber(use), Slot1.Frame.AbsolutePosition)
						Backpack.DragEnded:Fire(Slot1.Tool, Slot1.Frame, nil, true, UDim2.fromOffset(Slot2.Frame.AbsolutePosition.X, Slot2.Frame.AbsolutePosition.Y))
					else
						Backpack:SwapTools(Slot1, Slot2)

						Backpack.DragEnded:Fire(Slot1.Tool, Slot1.Frame, nil, true, UDim2.fromOffset(Slot2.Frame.AbsolutePosition.X, Slot2.Frame.AbsolutePosition.Y))
					end

					GuiService.SelectedObject = nil

					spawn(function()
						while Slot2.Tool do
							if Slot2.Frame.Button.Visible == false then
								wait()
								continue
							else
								break
							end
						end -- Doing this to prevent the warning

						GuiService.SelectedObject = Slot2.Frame.Button.ControllerSelectionFrame
					end)
				else
					create("UIStroke", {
						Name = "_UISelectController",
						Transparency = 0,
						Thickness = 1.6,
						Color = Color3.fromRGB(255, 255, 255),
						Parent = UISelectedSlots[1].Frame.Button,
					})

					Backpack.DragStarted:Fire(UISelectedSlots[1].Frame.Tool.Value, UISelectedSlots[1].Frame, nil, true)
				end
			end
		end


		local NumSlot = TranslateInput(InputObject)

		if not NumSlot then return end

		if HotbarSlots[NumSlot] then
			Backpack:Equip(NumSlot, true, true)
		end
	end)

	UserInputService.InputChanged:Connect(function(InputObject, processed)
		if InputObject.UserInputType ~= Enum.UserInputType.MouseWheel then return end
		if processed then return end
		if BackpackIsDisabled then return end
		if doesHaveEquipCooldown then return end

		local NumSlot = TranslateInput(InputObject)

		if not NumSlot then return end

		if HotbarSlots[NumSlot] then
			Backpack:Equip(NumSlot, nil, true)
		end
	end)

	GuiService:GetPropertyChangedSignal("SelectedObject"):Connect(function()
		local Target

		local function findToolValue(inst)
			if not inst then return nil end
			if not inst.Parent then
				return nil
			end

			local thingValue = inst:FindFirstChildWhichIsA("ObjectValue")

			if thingValue and thingValue.Name == "Tool" then
				Target = thingValue
			end

			findToolValue(inst.Parent)
		end

		findToolValue(GuiService.SelectedObject)

		if LastSelectedObj then
			HoverEndedInternal:Fire(LastSelectedObj, LastSelectedObj.AbsolutePosition.X, LastSelectedObj.AbsolutePosition.Y)
			Backpack.HoverEnded:Fire(LastSelectedObj, LastSelectedObj.AbsolutePosition.X, LastSelectedObj.AbsolutePosition.Y)
			LastSelectedObj = nil
		end

		if not Target then return end
		if not Target:IsDescendantOf(BackpackGui.BackpackMain) then return end 
		if not Target.Value then return end

		LastSelectedObj = GuiService.SelectedObject.Parent.Parent

		HoverStartedInternal:Fire(LastSelectedObj, LastSelectedObj.AbsolutePosition.X, LastSelectedObj.AbsolutePosition.Y)
		Backpack.HoverStarted:Fire(LastSelectedObj, LastSelectedObj.AbsolutePosition.X, LastSelectedObj.AbsolutePosition.Y)
	end)

	RunService.RenderStepped:Connect(function()
		CalculateGluedSlotPosition()
		CalculateInventoryButtonPosition()


		for Tool, CDData in pairs(ActiveCooldowns) do
			local Slot

			local function stop()
				Slot = Backpack:GetSlotFromTool(Tool)

				if Slot and Slot.Tool == Tool then
					Slot.Frame.Button.CooldownFrame.Visible = false
					Slot.Frame.Button.CooldownText.Visible = false
					Slot.Frame.Button.CooldownFrame.Size = UDim2.fromScale(1, 1)
				end

				ActiveCooldowns[Tool] = nil
				Backpack.CooldownEnded:Fire(Tool, Slot)
			end

			if not CDData.Started then
				Slot = Backpack:GetSlotFromTool(Tool)
				if Slot then Slot.Frame.Button.CooldownFrame.Size = UDim2.fromScale(1, 1) end
				CDData.Started = true
			end

			local ServerTime = workspace:GetServerTimeNow()

			if ServerTime >= (CDData.StartTime + CDData.Seconds) then
				stop()
				return
			end

			if not Slot then Slot = Backpack:GetSlotFromTool(Tool) end -- Tool probably was destroyed
			if not Slot then return end

			if Slot.Tool ~= Tool then Slot = Backpack:GetSlotFromTool(Tool) end
			if not Slot then return end

			-- If the slot gets switched find and set it again
			-- GetSlotFromTool can be an expensive call so lets use it sparingly.

			Slot.Frame.Button.CooldownFrame.Visible = true
			Slot.Frame.Button.CooldownText.Visible = true

			local num = tonumber(string.format("%."..(1 or 0).."f", (CDData.StartTime + CDData.Seconds) - ServerTime))

			if string.len(tostring(num)) == 1 then
				num = tostring(num)..".0s"
			else
				num = num.."s"
			end

			Slot.Frame.Button.CooldownText.Text = num

			Slot.Frame.Button.CooldownFrame:TweenSize(UDim2.fromScale(1, (math.abs(1 - (ServerTime -  CDData.StartTime) / ((CDData.StartTime +  CDData.Seconds) - CDData.StartTime)))), Enum.EasingDirection.InOut, Enum.EasingStyle.Sine, .1) -- Normalize the data
		end
	end)

	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(WindowSizeChanged)

	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(WindowSizeChanged)
	end)

	setCanUIHighlight(false)
	WindowSizeChanged()
	scheduleNextInternalSweep()

	LocalPlayer.CharacterAdded:Connect(CharacterAdded)

	if LocalPlayer.Character then
		spawn(CharacterAdded, LocalPlayer.Character)
	end

	if ScreenGui.ZIndexBehavior ~= Enum.ZIndexBehavior.Sibling then
		warn("Target ScreenGui needs to have a ZIndexBehavior of sibling in order for backpack to work. Setting ZIndexBehavior to sibling...")

		ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	end
end

--[[ RUNTIME ]]--

if RunService:IsServer() then error("Cannot require on the server.") end

-- // 

return Backpack