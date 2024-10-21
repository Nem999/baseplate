-- Author: NemPaws
-- Created: 10/7/24
-- Description: Replaces default backpack
-- Released under the MIT license.

--[[ SERVICES ]]--
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGuiService = game:GetService("StarterGui")
local PlayersService = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")

--[[ MODULES ]]--
local Spring = require(ReplicatedStorage.Lib.Spring)
local Signal = require(ReplicatedStorage.Lib.Signal)
local DragDetector = require(ReplicatedStorage.Lib.UIDrag) -- Unfortantely we cannot use UI drag detectors because they do not play well with buttons at the time of writing this.

--[[ CONSTANTS ]]--
local Backpack = {}
local HotbarSlots = {}
local BackpackSlots = {}
local BackpackInstance

--[[ SETTINGS ]]--
Backpack.Settings = {}
Backpack.Settings.MaxHotbarToolSlots = 10
Backpack.Settings.MaxHeldTools = 1
Backpack.Settings.USE_SCROLLWHEEL = true
Backpack.Settings.AutoCalculateMaxToolSlots = true
Backpack.Settings.EquipCooldown = 0.1
Backpack.Settings.Animate = true
Backpack.Settings.BackpackButtonOpenedColor = Color3.fromRGB(141, 164, 238)
Backpack.Settings.INVENTORY_KEYCODES = {
	Enum.KeyCode.Backquote,
	Enum.KeyCode.DPadDown,
}
Backpack.Settings.FASTMOVE_KEYCODES = {
	Enum.KeyCode.LeftControl,
	Enum.KeyCode.RightControl,
	Enum.KeyCode.ButtonY,
}
Backpack.Settings.UseViewportFrame = true

Backpack.Settings.DesiredPadding = UDim.new(0, 10)

--*/ Don't touch */--
local Humanoid
local LocalPlayer = PlayersService.LocalPlayer
local Character
local BackpackIsDisabled = false
local ScreenGui = LocalPlayer:WaitForChild("PlayerGui"):WaitForChild("SplashGui")
local HighlightedTools = {}
local InventoryFrame
local ToolTipFrame
local SelectionUIFrame
local isSearching = false
local BPButton
local BackpackSlotFrame
local doesHaveEquipCooldown = false
local lastScrollWheelPosition = nil
local BPConnection
local BackgroundTransparency
local InvCooldown = false
local InventoryIsOpen = false
local EquippedTools = {}
local Tweens = {}
local SlotChangedSignal = Signal.new()
local InvAnimation = 1

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
Backpack.ItemAdded = Signal.new() --> [Instance](Slot)
Backpack.ItemRemoving = Signal.new() --> [Instance](Slot), [Instance](Ghost Slot)
Backpack.InventoryOpened = Signal.new()
Backpack.InventoryClosed = Signal.new()

--[[ FUNCTIONS ]]--
local spawn = task.spawn
local wait = task.wait
local delay = task.delay
local defer = task.defer

local rbxwarn = warn
local rbxerror = error

local function warn(warning)
	rbxwarn("[BackpackScript]:", warning)
end

local function error(err)
	rbxerror("[BackpackScript]: "..err, 0)
end

function SetBackpack(BackpackInst : Backpack)
	if typeof(BackpackInst) ~= "Instance" or not BackpackInst:IsA("Backpack") or BackpackInst.Parent ~= LocalPlayer then error("Invalid backpack") end
	if BackpackInstance then resetBackpack() BackpackInstance:Destroy() end
	if BPConnection then BPConnection:Disconnect() end

	BackpackInstance = BackpackInst
	BPConnection = BackpackInst.ChildAdded:Connect(newSlot)

	for _, Tool in pairs(BackpackInst:GetChildren()) do
		if not Tool:IsA("Tool") then continue end

		newSlot(Tool)
	end
end

function CharacterAdded(char : Model)
	Character = char
	Humanoid = char:WaitForChild("Humanoid")

	char.ChildAdded:Connect(newSlot)
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

function isToolRegistered(Tool)
	for _, Slot in pairs(HotbarSlots) do
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

	return cmpVectors(top, boundryTop) or cmpVectors(boundryBot, bot)
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

function onParentUpdate(Tool, Parent)
	if not LocalPlayer:IsDescendantOf(PlayersService) then return end -- Need this check or else a bunch of errors are spit out when the game is shutting down

	local ToolSlot = Backpack:GetSlotFromTool(Tool)
	local Frame = ToolSlot.Frame.Button

	if Parent ~= Character and Parent ~= BackpackInstance then
		-- Player has lost control of the tool disconnect all connections

		for _, Connection in pairs(ToolSlot.Connections) do 
			Connection:Disconnect()
		end

		for _, Highlight in pairs(HighlightedTools) do
			if Highlight.Frame == Frame.Parent then
				MoveEquipBar(false, ToolSlot.Frame, 0)
				break
			end
		end

		local GhostSlot = Frame.Parent:Clone()

		Backpack.ItemRemoving:Fire(ToolSlot.Frame, GhostSlot)

		if ToolSlot.Dragger then
			ToolSlot.Dragger:Disable()

			ToolSlot.Dragger = nil
		end

		ToolSlot.Tool = nil
		ToolSlot.Glued = false
		ToolSlot.Locked = false

		if ToolSlot.PlacementSlot then
			ToolSlot.PlacementSlot.Visible = false
		end

		ToolSlot.Frame.Tool.Value = nil
		table.clear(ToolSlot.Connections)

		ToolSlot.Loaded = false

		GhostSlot.Name = "_Ghost"
		GhostSlot.Visible = true
		GhostSlot.Button.Parent = GhostSlot.Group
		GhostSlot.Parent = ScreenGui.BackpackMain

		if ToolSlot.PlacementSlot then
			Animate(GhostSlot, "Position", UDim2.fromOffset(GhostSlot.AbsolutePosition.X, GhostSlot.AbsolutePosition.Y + 200), .7, 2)
			Frame.Parent.Visible = false
		else

			ToolSlot.Frame.Group.GroupTransparency = 1
			ToolSlot.Frame.Button.Visible = false

			GhostSlot.Group.Button.ToolName.Text = ""
			GhostSlot.Group.Button.ToolImage.Visible = false

			GhostSlot.Position = UDim2.fromOffset(ToolSlot.Frame.AbsolutePosition.X + GuiService:GetGuiInset().X, ToolSlot.Frame.AbsolutePosition.Y + GuiService:GetGuiInset().Y)

			delay(.35, function()
				if not ToolSlot.Frame.Tool.Value then
					ToolSlot.Frame.Visible = false
				end
			end)

			Animate(GhostSlot.Group, "GroupTransparency", 1, 1.2, 6)
			Animate(GhostSlot.Group, "Size", UDim2.fromOffset(ToolSlot.Frame.Size.X.Offset / 1.8, ToolSlot.Frame.Size.Y.Offset / 1.8), 1.2, 6)
		end

		if Backpack.Settings.Animate == true then
			Spring.completed(GhostSlot, function()
				GhostSlot:Destroy()
			end)
		else
			GhostSlot:Destroy()
		end
	end
end

function resetBackpack()
	for _, ToolSlot in pairs(HotbarSlots) do
		local Tool = ToolSlot.Tool 

		if Tool then
			onParentUpdate(Tool, nil) -- Free the tool
		end

		for _, Connection in pairs(ToolSlot.Connections) do 
			Connection:Disconnect()
		end

	end

	for _, ToolSlot in pairs(BackpackSlots) do
		local Tool = ToolSlot.Tool 

		if Tool then
			onParentUpdate(Tool, nil)
		end

		for _, Connection in pairs(ToolSlot.Connections) do 
			Connection:Disconnect()
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
	-- nothing yet
end

function newSlot(Tool : Tool, BPSlot)
	if not Tool:IsA("Tool") then return end
	if not BPSlot then
		if isToolRegistered(Tool) then return end
	end

	local Slot = findNextAvaliableSlot()
	
	if BPSlot then
		Slot = nil
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
			Connections = {},
		}
		
		newSlot.Position = TotalBP + Backpack.Settings.MaxHotbarToolSlots + 1

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
				
				if isOneKeyDown and InventoryIsOpen then
					local NewPosition = UDim2.fromOffset(newSlot.Frame.Button.AbsolutePosition.X  + (newSlot.Frame.Button.AbsoluteSize.X / 2), (newSlot.Frame.Button.AbsolutePosition.Y + (newSlot.Frame.Button.AbsoluteSize.Y / 2)))
						
					if newSlot.Position <= Backpack.Settings.MaxHotbarToolSlots then
						Backpack:MoveToolToInventory(newSlot.Tool, NewPosition)
					else
						Backpack:MoveToolToHotbar(newSlot.Tool, NewPosition)
					end
					
					return
				end

				Backpack:Equip(newSlot.Tool)
			end)

			newSlot.Frame:GetPropertyChangedSignal("AbsolutePosition"):Connect(function()
				SlotChangedSignal:Fire(newSlot)
			end)
			
		end

		newSlot.Connections["POSITION_UPDATE_SIGNAL"] = SlotChangedSignal:Connect(function(Slot)
			if Slot ~= newSlot then return end
			if not EquippedTools[Slot.Tool] then return end
			if not InventoryIsOpen then return end

			for _, Highlight in pairs(HighlightedTools) do
				if Highlight.Tool == Slot.Tool and newSlot.Loaded then

					Highlight.Highlight.Position = UDim2.fromOffset(newSlot.Frame.AbsolutePosition.X + GuiService:GetGuiInset().X, newSlot.Frame.AbsolutePosition.Y + GuiService:GetGuiInset().Y)

					if isClipped(Highlight.Highlight, InventoryFrame.Background.ScrollingFrame) then
						SetBarTransparency(Highlight.Highlight, 1, 0)
					else
						SetBarTransparency(Highlight.Highlight, 0)
					end

				end
			end
		end)

		if not InventoryIsOpen then
			Backpack:PopNotificationIcon(true)
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

	ToolSlot.Dragger = DragDetector.new(ToolSlot.Frame.Button, ScreenGui.BackpackMain, Backpack.Settings.FASTMOVE_KEYCODES)

	ToolSlot.Dragger:Enable()

	ToolSlot.Dragger.DragStarted = function()
		ToolSlot.Frame.Button.Interactable = false
		ToolSlot.Frame.Button.Visible = false
	end

	ToolSlot.Dragger.DragEnded = function(Position) -- TODO Bug fix: This will be called 3 times on mobile
		ToolSlot.Frame.Button.Interactable = true
		ToolSlot.Frame.Button.Visible = true

		if not ToolSlot.Tool then return end

		local MouseLocation = UserInputService:GetMouseLocation()
		
		local Pos = UDim2.fromOffset(Position.X, Position.Y) or UDim2.fromOffset(MouseLocation.X + GuiService:GetGuiInset().X, MouseLocation.Y + GuiService:GetGuiInset().Y)

		local GuiObjects = LocalPlayer.PlayerGui:GetGuiObjectsAtPosition(Pos.X.Offset, Pos.Y.Offset)

		for _, Gui in pairs(GuiObjects) do -- // For swapping
			if not tonumber(Gui.Name) or not Gui:IsDescendantOf(ScreenGui.BackpackMain) then continue end

			local ToolValue = Gui:FindFirstChildWhichIsA("ObjectValue")

			local Tool

			if ToolValue then
				Tool = ToolValue.Value
			end

			if Tool then
				if Tool == ToolSlot.Tool then continue end

				Backpack:SwapTools(Tool, ToolSlot.Tool)
				return
			end
		end
		
		if table.find(GuiObjects, InventoryFrame) and InventoryIsOpen then
			Backpack:MoveToolToInventory(ToolSlot.Tool, Pos)
		else
			Backpack:MoveToolToHotbar(ToolSlot.Tool, Pos)
		end
	end


	local Frame = ToolSlot.Frame.Button
	ToolSlot.Frame.Tool.Value = Tool

	local ToolTip = Tool.ToolTip
	local Img = Tool.TextureId

	for _, Connection in pairs(ToolSlot.Connections) do
		Connection:Disconnect()
	end

	table.clear(ToolSlot.Connections)

	Frame.Visible = true
	ToolSlot.Frame.Button.Visible = true
	ToolSlot.Frame.Group.GroupTransparency = 0

	if ToolSlot.PlacementSlot then
		ToolSlot.PlacementSlot.Visible = true

		defer(function()
			if not ToolSlot.Loaded then
				while ToolSlot.PlacementSlot.AbsolutePosition.Y ~= ScreenGui.BackpackMain.HotbarContainer.AbsolutePosition.Y do
					wait() -- Need to wait for the UIListLayout to calculate the position
				end

				ToolSlot.Loaded = true
			end

			CalculateInventoryButtonPosition()
		end)

	else
		ToolSlot.Loaded = true
	end

	Backpack.ItemAdded:Fire(Frame.Parent)

	if ToolSlot.PlacementSlot then
		local TargetPosition : Vector2 = ToolSlot.PlacementSlot.AbsolutePosition
		
		ToolSlot.Frame.Position = UDim2.fromOffset(TargetPosition.X, TargetPosition.Y + GuiService:GetGuiInset().Y + 80)

		SlotChangedSignal:Fire(ToolSlot.PlacementSlot)
	end

	if not Backpack.Settings.UseViewportFrame then
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

		Cam.CFrame *= CFrame.Angles(math.rad(90), math.rad(-90), 0) 

		ViewportFrame.CurrentCamera = Cam

		zoomToExtents(ViewportFrame.CurrentCamera, ToolClone)

		defer(function()
			local isSpinning = false
			local left = true

			local temp = Instance.new("NumberValue")

			while true do
				RunService.Heartbeat:Wait()

				local doesConnectionExist = false

				for _, con in pairs(ToolSlot.Connections) do
					doesConnectionExist = true
					break
				end

				if not doesConnectionExist then print('No more connections breaking') temp:Destroy() break end

				ToolClone:PivotTo(CFrame.new(0, 0, 0) * CFrame.Angles(0 , 0, math.rad(temp.Value)))

				if ToolSlot.Position > Backpack.Settings.MaxHotbarToolSlots then 
					if not InventoryIsOpen then continue end
				end

				if isSpinning then continue end

				local direction

				if left then direction = -120 else direction = 120 end

				isSpinning = true

				print('gop')

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

	ToolSlot.Connections["ICON_UPDATE_SIGNAL"] = Tool:GetPropertyChangedSignal("TextureId"):Connect(function()
		iconUpdate(ToolSlot)
	end)

	ToolSlot.Connections["TOOLTIP_UPDATE_SIGNAL"] = Tool:GetPropertyChangedSignal("ToolTip"):Connect(function()
		toolTipUpdate(ToolSlot)
	end)

	ToolSlot.Connections["NAME_UPDATE_SIGNAL"] = Tool:GetPropertyChangedSignal("Name"):Connect(function()
		nameUpdate(ToolSlot)
	end)

	ToolSlot.Connections["PARENT_UPDATE_SIGNAL"] = Tool:GetPropertyChangedSignal("Parent"):Connect(function()
		onParentUpdate(Tool, Tool.Parent)
	end)
	
	Frame.ToolName.Text = Tool.Name
	ToolSlot.Frame.LayoutOrder = ToolSlot.Position
	ToolSlot.Frame.Visible = true

	if Tool.Parent == Character then

		if ToolSlot.PlacementSlot then
			lastScrollWheelPosition = Slot
		end

		for idx, FrameTable in pairs(HighlightedTools) do
			FrameTable.Highlight:Destroy()
		end
		
		table.clear(HighlightedTools)
		table.clear(EquippedTools)

		EquippedTools[Tool] = ToolSlot
		
		print(ToolSlot)

		MoveEquipBar(ToolSlot)
	end
	
	return ToolSlot
end

function FastMove(Slot, Tool)
	if not Slot then
		Slot = Backpack:GetSlotFromTool(Tool)
	end
	
	
end

function findNextAvaliableSlot()
	for i = 1, #HotbarSlots do
		if not HotbarSlots[i].Tool then
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

function sweepFreeSlots()
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
	end
end

function SetBarTransparency(Bar, Transparency, time)
	local realtime = time or 0.1
	for _, ImageFrame in pairs(Bar:GetChildren()) do
		if ImageFrame:IsA("ImageLabel") then

			local stack = Tweens[ImageFrame]
			if stack then stack:Destroy() table.remove(Tweens, table.find(Tweens, ImageFrame)) end

			defer(function()
				local NewTween = TweenService:Create(ImageFrame, TweenInfo.new(realtime, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), {ImageTransparency = Transparency})
				NewTween:Play()

				NewTween.Completed:Wait()

				table.remove(Tweens, table.find(Tweens, ImageFrame))
				NewTween:Destroy()
			end)
		end
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
	else
		isSearching = true
		for _, slot in pairs(BackpackSlots) do
			if slot.Tool and string.lower(slot.Tool.Name):match(text) then
				slot.Frame.Visible = true
			else
				slot.Frame.Visible = false
			end
		end
	end
end

function MoveEquipBar(FrameSlot, DisabledFrame, time)
	local function track(enableordisable : boolean, frame)

	end

	local InvParent = InventoryFrame.Background.ScrollingFrame

	if FrameSlot == false then
		track(false, DisabledFrame)

		for _, Highlight in pairs(HighlightedTools) do
			if Highlight.Frame == DisabledFrame then
				SetBarTransparency(Highlight.Highlight, 1, time)
				break
			end
		end
		return
	end

	local Num = 0

	for _ in pairs(HighlightedTools) do
		Num += 1
	end

	if Num < Backpack.Settings.MaxHeldTools then
		local NewUISection = SelectionUIFrame:Clone()

		NewUISection.Visible = true

		if FrameSlot.Frame.Parent == InvParent then
			NewUISection.Parent = InventoryFrame.Parent

			NewUISection.Position = UDim2.fromOffset(FrameSlot.Frame.AbsolutePosition.X + GuiService:GetGuiInset().X, FrameSlot.Frame.AbsolutePosition.Y + GuiService:GetGuiInset().Y)
		else
			NewUISection.Parent = ScreenGui.BackpackMain
		end

		table.insert(HighlightedTools, {
			Frame = FrameSlot.Frame,
			Highlight = NewUISection,
			Tool = FrameSlot.Tool
		})


		SetBarTransparency(NewUISection, 0)
		
		if FrameSlot.PlacementSlot then
			SlotChangedSignal:Fire(FrameSlot.PlacementSlot)
		else
			SlotChangedSignal:Fire(FrameSlot.Tool)
		end
	else
		for _, Highlight in pairs(HighlightedTools) do

			if Highlight.Tool.Parent ~= Character then

				if FrameSlot.Frame.Parent == InvParent then
					Highlight.Highlight.Parent = InventoryFrame.Parent
				else
					Highlight.Highlight.Parent = ScreenGui.BackpackMain
				end

				if Highlight.Highlight.Parent  == ScreenGui.BackpackMain then
					Highlight.Highlight.Visible = true
				end

				if Highlight.Highlight.ImageLabel.ImageTransparency ~= 1 then
					Animate(Highlight.Highlight, "Position", UDim2.fromOffset(FrameSlot.Frame.AbsolutePosition.X + GuiService:GetGuiInset().X, FrameSlot.Frame.AbsolutePosition.Y + GuiService:GetGuiInset().Y), 0.78, 4)
				else
					Spring.stop(Highlight.Highlight, "Position")

					Highlight.Highlight.Position = UDim2.fromOffset(FrameSlot.Frame.AbsolutePosition.X + GuiService:GetGuiInset().X, FrameSlot.Frame.AbsolutePosition.Y + GuiService:GetGuiInset().Y)
					SetBarTransparency(Highlight.Highlight, 0, 0)
				end

				local Clone = table.clone(Highlight)

				for dex, key in pairs(Clone) do
					Highlight[dex] = key
				end

				Highlight.Frame = FrameSlot.Frame
				Highlight.Tool = FrameSlot.Tool
				break
			else
				Animate(Highlight.Highlight, "Position",  UDim2.fromOffset(FrameSlot.Frame.AbsolutePosition.X + GuiService:GetGuiInset().X, FrameSlot.Frame.AbsolutePosition.Y + GuiService:GetGuiInset().Y), .79, 3)

				if FrameSlot.Frame.Parent ~= ScreenGui.BackpackMain then
					Highlight.Highlight.Parent = InventoryFrame.Parent
				else
					Highlight.Highlight.Parent = ScreenGui.BackpackMain
				end

				SetBarTransparency(Highlight.Highlight, 0)
			end	

		end
	end
end

function BuildGui()
	StarterGuiService:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)

	InventoryFrame = ScreenGui.InventoryMain:Clone() -- ok shut up we're doing something cool here
	ToolTipFrame = ScreenGui.ToolTip:Clone()
	SelectionUIFrame = ScreenGui.SelectionUI:Clone()
	BackpackSlotFrame = ScreenGui.BackpackSlot:Clone()
	BPButton = ScreenGui.BackpackButton:Clone()

	ScreenGui.InventoryMain:Destroy()
	ScreenGui.SelectionUI:Destroy()
	ScreenGui.ToolTip:Destroy()
	ScreenGui.BackpackSlot:Destroy()
	ScreenGui.BackpackButton:Destroy()

	BackgroundTransparency = BPButton.ImageButton.BackgroundColor3

	local MainFrame = create("Frame", {
		Name = "BackpackMain",
		Size = UDim2.fromScale(1,1),
		BackgroundTransparency = 1,
		Visible = true,
		Parent = ScreenGui,
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
				end

				defer(function()
					while not Completed do
						CalculateInventoryButtonPosition()
						wait()
					end
				end)

				InventoryFrame.Position = UDim2.new(.5, 0, 0, PlacementFrame.AbsolutePosition.Y - 100)

				if HotbarSlots[i].Tool then
					if EquippedTools[HotbarSlots[i].Tool] then
						for _, Highlight in pairs(HighlightedTools) do
							if Highlight.Tool == HotbarSlots[i].Tool and HotbarSlots[i].Loaded then

								local TargetPosition = PlacementFrame.AbsolutePosition
								Highlight.Highlight.Position = UDim2.fromOffset(Highlight.Highlight.AbsolutePosition.X, TargetPosition.Y + GuiService:GetGuiInset().Y)

								Animate(Highlight.Highlight, "Position",  UDim2.fromOffset(PlacementFrame.AbsolutePosition.X + GuiService:GetGuiInset().X, PlacementFrame.AbsolutePosition.Y + GuiService:GetGuiInset().Y), .79, 3)
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
			
			if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) and InventoryIsOpen then
				local NewPosition = UDim2.fromOffset(NewSlot.Button.AbsolutePosition.X  + (NewSlot.Button.AbsoluteSize.X / 2), (NewSlot.Button.AbsolutePosition.Y + (NewSlot.Button.AbsoluteSize.Y / 2)))
				
				if HotbarSlots[i].Position <= Backpack.Settings.MaxHotbarToolSlots then
					Backpack:MoveToolToInventory(HotbarSlots[i].Tool, NewPosition)
				else
					Backpack:MoveToolToHotbar(HotbarSlots[i].Tool, NewPosition)
				end
				return
			end
			
			Backpack:Equip(i)
		end)
	end

	for _, Button : Instance in pairs(BPButton:GetDescendants()) do
		if Button:IsA("GuiButton") then
			Button.MouseButton1Click:Connect(function()

				if InventoryIsOpen then
					Backpack:CloseInventory()
				else
					Backpack:OpenInventory()
				end

			end)
		end
	end

	BPButton.Visible = true
	BPButton.Parent = ScreenGui

	Backpack:PopNotificationIcon(false)
end

function CalculateInventoryButtonPosition()
	local Max

	for _, slot in pairs(HotbarSlots) do
		if not Max and slot.Tool then Max = slot continue end

		if slot.Frame.Visible and slot.Position > Max.Position then
			Max = slot
		end
	end

	if not Max then 
		BPButton.Position = UDim2.new(0.5, 0, 0, ScreenGui.BackpackMain.HotbarContainer.AbsolutePosition.Y + (BackpackSlotFrame.Size.Y.Offset * 1.5))
		return
	end

	local MaxAbsolutePosition = Max.Frame.AbsolutePosition

	BPButton.Position = UDim2.fromOffset(MaxAbsolutePosition.X + (BackpackSlotFrame.Size.X.Offset * 1.4), MaxAbsolutePosition.Y  + (BackpackSlotFrame.Size.Y.Offset * 1.2))
end

function Animate(Instance, Prop, Value, Damping, Ratio)
	if Backpack.Settings.Animate == true then
		Spring.stop(Instance, Prop)

		local Insert = {}

		Insert[Prop] = Value

		Spring.target(Instance, Damping, Ratio, Insert)
	else
		Instance[Prop] = Value
	end
end

function refreshSlot(Slot)

	for conName, Connection in pairs(Slot.Connections) do
		if conName == "POSITION_UPDATE_SIGNAL" then continue end
		Connection:Disconnect()
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
	print(Slot)
		onParentUpdate(Slot.Tool, Slot.Tool.Parent)
	end)


	iconUpdate(Slot)
	toolTipUpdate(Slot)
	nameUpdate(Slot)

	for Tool, _ in pairs(EquippedTools) do
		if Tool == Slot.Tool then
			EquippedTools[Tool] = Slot
			break
		end
	end
	 
	for _, Highlight in pairs(HighlightedTools) do
		if Highlight.Tool == Slot.Tool then
			MoveEquipBar(Slot)
			SlotChangedSignal:Fire(Slot.PlacementSlot or Slot)
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
	if InputObject.UserInputType == Enum.UserInputType.Keyboard then
		if KEYBOARD_TRANSLATIONS[InputObject.KeyCode.Name] then
			return tonumber(KEYBOARD_TRANSLATIONS[InputObject.KeyCode.Name])
		end
	elseif InputObject.UserInputType == Enum.UserInputType.MouseWheel and Backpack.Settings.USE_SCROLLWHEEL == true or InputObject.KeyCode == Enum.KeyCode.ButtonR1 or InputObject.KeyCode == Enum.KeyCode.ButtonL1 then
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

		if InputObject.UserInputType.Name:match("Gamepad") then
			if InputObject.KeyCode == Enum.KeyCode.ButtonR1 then
				Direction = 1
			else
				Direction = -1
			end
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
	end
end

function deleteToolSlotData(ToolSlot)
	ToolSlot.Tool = nil
	ToolSlot.Glued = false
	ToolSlot.Locked = false

	if ToolSlot.PlacementSlot then
		ToolSlot.PlacementSlot.Visible = false
	end

	ToolSlot.Frame.Tool.Value = nil
	
	for conName, Connection in pairs(ToolSlot.Connections) do
		if conName == "POSITION_UPDATE_SIGNAL" then continue end
		Connection:Disconnect()
	end

	table.clear(ToolSlot.Connections)

	ToolSlot.Loaded = false
end

function convert(ToolOrSlot, num)
	if typeof(ToolOrSlot) == "Instance" then
		if not ToolOrSlot:IsA("Tool") then error("Arugment "..num.. " isn't a tool.") return end

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

function Backpack:Equip(ToolOrSlot)
	if BackpackIsDisabled then print('dis') return end
	if not Character then print('no char') return end
	if not Character:IsDescendantOf(workspace) then print('not work') return end
	if doesHaveEquipCooldown then print('coold') return end

	doesHaveEquipCooldown = true

	delay(Backpack.Settings.EquipCooldown, function()
		doesHaveEquipCooldown = false
	end)

	-- AAAA WHY ARENT YOU USING HUMANOID:EQUIP() AAGAGAAHA
	-- SHUT UP Humanoid:EquipTool() doesn't support multiple tools so we are just manually parenting the tool


	local Tool = convert(ToolOrSlot, 1)

	if not Tool then return end

	if Tool.Parent ~= Character and Tool.Parent ~= BackpackInstance then
		warn("Not equipping tool because cannot equip tool that is not parent of LocalCharacter or backpack.")
		return
	end

	local HBarSlot = Backpack:GetSlotFromTool(Tool)

	if Tool.Parent == Character and not HBarSlot.Glued then
		Tool.Parent = BackpackInstance
		EquippedTools[Tool] = nil
		MoveEquipBar(false, HBarSlot.Frame)
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

function Backpack:OpenInventory()
	if BackpackIsDisabled then return end
	if InventoryIsOpen then return end
	if InvCooldown then return end

	InventoryIsOpen = true
	InvCooldown = true

	local useAnimation = InvAnimation

	local OrginalSize = InventoryFrame.Size
	local OrginalBackgroundTransparency = 0

	local Temp = {}

	Animate(BPButton.ImageButton, "BackgroundColor3", Backpack.Settings.BackpackButtonOpenedColor, 6, 11)

	Backpack:PopNotificationIcon(false)
	
	Backpack.InventoryOpened:Fire()

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

function Backpack:CloseInventory()
	if BackpackIsDisabled then return end
	if not InventoryIsOpen then return end
	if InvCooldown then return end

	InventoryIsOpen = false
	InvCooldown = true

	local useAnimation = InvAnimation

	local OrginalSize = InventoryFrame.Size

	local Temp = {}

	Animate(BPButton.ImageButton, "BackgroundColor3", BackgroundTransparency, 6, 11)
	
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
end

function Backpack:MoveToolToInventory(Tool : Tool, fromPosition : UDim2)
	Tool = convert(Tool, 1)

	if not Tool then
		warn("Tool does not exist within backpack")
		return
	end
	
	if not fromPosition then 
		local MouseLocation = UserInputService:GetMouseLocation() 
		
		fromPosition = UDim2.fromOffset(MouseLocation.X + GuiService:GetGuiInset().X, MouseLocation.Y - GuiService:GetGuiInset().Y)
	end

	local ToolSlot = Backpack:GetSlotFromTool(Tool)

	if ToolSlot.Position > Backpack.Settings.MaxHotbarToolSlots then
		return -- Tool is already in inventory
	end
	
	local TargetSlot = newSlot(Tool, true) -- No animation will play when set to true
	

	TargetSlot.Glued = ToolSlot.Glued
	TargetSlot.Locked = ToolSlot.Locked
	
	deleteToolSlotData(ToolSlot)
	refreshSlot(TargetSlot)
	
	local GhostSlot = TargetSlot.Frame:Clone()

	
	ToolSlot.Frame.Visible = false
	--ToolSlot.Frame.Button.Visible = false
	
	if not isSearching then
		TargetSlot.Frame.Visible = true
	end

	TargetSlot.Frame.Button.Visible = false
	
	GhostSlot.Name = "_Ghost"
	GhostSlot.Visible = false
	GhostSlot.Button.Visible = true
	GhostSlot.Group.Visible = true

	GhostSlot.Position = fromPosition
	GhostSlot.Group.Position = UDim2.fromScale(0, 0)
	GhostSlot.Button.Position = UDim2.fromScale(0, 0)
	
	GhostSlot.Parent = ScreenGui.BackpackMain
	
	local AbsPos = TargetSlot.Frame.AbsolutePosition

	Animate(GhostSlot, "Position", UDim2.fromOffset(AbsPos.X + GuiService:GetGuiInset().X, AbsPos.Y + GuiService:GetGuiInset().Y), 1, 6)
	
	spawn(function()
		while GhostSlot.Parent do
			
			if isClipped(GhostSlot, InventoryFrame) then
				GhostSlot.Visible = false
			else
				GhostSlot.Visible = true
			end
			
			wait()
		end
	end)

	Spring.completed(GhostSlot, function()
		if TargetSlot.Tool == Tool then -- This may make it safe.
			TargetSlot.Frame.Button.Visible = true
		end
		
		GhostSlot:Destroy()
	end)
	
	return TargetSlot
end

function Backpack:MoveToolToHotbar(Tool : Tool, fromPosition : UDim2)
	Tool = convert(Tool, 1)

	if not Tool then
		warn("Tool does not exist within backpack")
		return
	end
	
	if not fromPosition then 
		local MouseLocation = UserInputService:GetMouseLocation() 

		fromPosition = UDim2.fromOffset(MouseLocation.X + GuiService:GetGuiInset().X, MouseLocation.Y + GuiService:GetGuiInset().Y)
	end

	local ToolSlot = Backpack:GetSlotFromTool(Tool)
	
	if ToolSlot.Position <= Backpack.Settings.MaxHotbarToolSlots then
		return -- Exit out if the tool is already in the hotbar
	end

	local Slot = findNextAvaliableSlot()

	if not Slot then
		warn("Not moving tool to hotbar because the hotbar currently has the max amount of allowed tools. Please move a tool first.")
		return
	end
	
	local TargetSlot = HotbarSlots[Slot]
	
	TargetSlot.Tool = Tool
	TargetSlot.Glued = ToolSlot.Glued
	TargetSlot.Locked = ToolSlot.Locked
	
	TargetSlot.Frame.Tool.Value = Tool

	if Backpack.Settings.UseViewportFrame == true then
		local Toolold = TargetSlot.Frame.Button.ViewportFrame.WorldModel:FindFirstChildWhichIsA("Tool")

		if Toolold then
			Toolold:Destroy()
		end

		local ToolClone = Tool:Clone()

		local function removeScripts()
			for _, inst in pairs(ToolClone:GetDescendants()) do
				if inst:IsA("BaseScript") then
					inst:Destroy()
				end
			end
		end

		removeScripts()

		ToolClone.Parent = TargetSlot.Frame.Button.ViewportFrame.WorldModel

		local Cam = Instance.new("Camera")
		TargetSlot.Frame.Button.ViewportFrame.CurrentCamera = Cam
		zoomToExtents(Cam, ToolClone)
	end
	
	deleteToolSlotData(ToolSlot)
	refreshSlot(TargetSlot)
	
	-- now we can animate the slot
	
	if typeof(fromPosition) ~= "UDim2" then return end
	
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
	
	GhostSlot.Parent = ScreenGui.BackpackMain
	
	local AbsPos = TargetSlot.PlacementSlot.AbsolutePosition

	Animate(GhostSlot, "Position", UDim2.fromOffset(AbsPos.X + GuiService:GetGuiInset().X, AbsPos.Y + GuiService:GetGuiInset().Y), 1, 6)

	Spring.completed(GhostSlot, function()
		if TargetSlot.Tool == Tool then -- This may make it safe.
			TargetSlot.Frame.Button.Visible = true
		end
		GhostSlot:Destroy()
	end)
	
	return TargetSlot
end

function Backpack:SwapTools(Tool1, Tool2)

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

	local Clone1 = table.clone(Slot1)
	local Clone2 = table.clone(Slot2)

	Slot1.Tool = Clone2.Tool
	Slot1.Glued = Clone2.Glued
	Slot1.Locked = Clone2.Locked

	Slot2.Tool = Clone1.Tool
	Slot2.Glued = Clone1.Glued
	Slot2.Locked = Clone1.Locked

	Slot2.Frame.Tool.Value = Tool1
	Slot1.Frame.Tool.Value = Tool2

	for _, Highlight in pairs(HighlightedTools) do
		if Highlight.Tool == Tool1 and Tool1.Parent == Character then
			Highlight.Frame = Slot2.Frame

			MoveEquipBar(Slot2)
			SlotChangedSignal:Fire(Slot2.PlacementSlot or Slot2)
		elseif Highlight.Tool == Tool2 and Tool2.Parent == Character then
			Highlight.Frame = Slot1.Frame

			MoveEquipBar(Slot1)
			SlotChangedSignal:Fire(Slot1.PlacementSlot or Slot1)
		end -- Hotfix for fixing highlights
	end

	if Backpack.Settings.Animate == false then return end

	if Slot1.Position > Backpack.Settings.MaxHotbarToolSlots then
		Tool1Type = "BP"
		inBP = true
	end

	if Slot1.Position <= Backpack.Settings.MaxHotbarToolSlots then
		Tool1Type = "HB"
		inHB = true
	end

	if Slot2.Position > Backpack.Settings.MaxHotbarToolSlots then
		Tool2Type = "BP"
		inBP = true
	end

	if Slot2.Position <= Backpack.Settings.MaxHotbarToolSlots then
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

		GhostSlot1.Parent = ScreenGui.BackpackMain
		GhostSlot2.Parent = ScreenGui.BackpackMain

		local Pos1 = GhostSlot1.Position
		local Pos2 = GhostSlot2.Position

		Animate(GhostSlot1, "Position", Pos2, 1, 6)
		Animate(GhostSlot2, "Position", Pos1, 1, 6)

		delay(.16, function() -- // TODO maybe not safe
			Slot1.Frame.Button.Visible = true
			Slot2.Frame.Button.Visible = true

			GhostSlot1.Visible = false
			GhostSlot2.Visible = false
		end)

		Spring.completed(GhostSlot1, function()
			GhostSlot1:Destroy()
			GhostSlot2:Destroy()
		end)
	end

	local function specialSwap(main, BPSlot)
		local GhostSlot1 = main.Frame:Clone()
		local GhostSlot2 = BPSlot.Frame:Clone()

		GhostSlot1.Name = "_Ghost"
		GhostSlot2.Name = "_Ghost"

		GhostSlot1.Visible = true
		GhostSlot2.Visible = true

		GhostSlot1.Button.ToolNum.Text = ""
		GhostSlot2.Button.ToolNum.Text = ""

		main.Frame.Button.Visible = false

		GhostSlot1.Position = UDim2.fromOffset(main.Frame.AbsolutePosition.X + GuiService:GetGuiInset().X, main.Frame.AbsolutePosition.Y + GuiService:GetGuiInset().Y)
		GhostSlot2.Position = UDim2.fromOffset(BPButton.AbsolutePosition.X + GuiService:GetGuiInset().X, BPButton.AbsolutePosition.Y + GuiService:GetGuiInset().Y)

		GhostSlot1.Parent = ScreenGui.BackpackMain
		GhostSlot2.Parent = ScreenGui.BackpackMain

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

		delay(.32, function()
			main.Frame.Button.Visible = true
			GhostSlot1.Visible = false
			GhostSlot2.Visible = false
		end)

		Spring.completed(GhostSlot1, function()
			GhostSlot1:Destroy()
			GhostSlot2:Destroy()
		end)
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

	refreshSlot(Slot1)
	refreshSlot(Slot2)
	

	print(Slot1)
	print(Slot2)
end

function Backpack:PopNotificationIcon(State : boolean)
	if typeof(State) ~= "boolean" then error("Argument 1 is not of type: boolean") end

	BPButton.Notification.Visible = State
end

function Backpack:UnequipTools() -- Unequips non glued tools
	if not Character then return end

	for Tool, ToolData in pairs(EquippedTools) do
		if Tool.Parent == Character and not ToolData.Glued then
			Backpack:Equip(Tool)
		end
	end
end

function Backpack:GetEquippedTools()
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

function Backpack:GetSlotFromTool(Tool : Tool)
	if typeof(Tool) ~= "Instance" then error("Argument one is not of type: Instance") end
	if not Tool:IsA("Tool") then error("Argument 1 is not a tool.") end

	for _, Slot in pairs(HotbarSlots) do
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

function Backpack:GetSlotFromNumber(Number : number)
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

function Backpack:GetHotbarTools()
	local Tools = {}

	for _, Slot in ipairs(HotbarSlots) do
		if Slot.Tool then
			table.insert(Tools, Slot.Tool)
		end
	end

	return Tools
end

function Backpack:GetInventoryTools()
	local Tools = {}

	for _, Slot in ipairs(BackpackSlots) do
		if Slot.Tool then
			table.insert(Tools, Slot.Tool)
		end
	end

	return Tools
end

--[[ RUNTIME ]]--

if RunService:IsServer() then error("Cannot require on the server.") return nil end

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
		Connections = {},
	})
end

BuildGui()

SetBackpack(LocalPlayer:FindFirstChild("Backpack"))

if not BackpackInstance then
	SetBackpack(LocalPlayer:WaitForChild("Backpack"))
end

LocalPlayer.ChildAdded:Connect(function(Child)
	if Child.ClassName == "Backpack" then
		SetBackpack(Child)
	end
end)

UserInputService.InputBegan:Connect(function(InputObject, processed)
	if processed then return end
	if BackpackIsDisabled then return end

	if table.find(Backpack.Settings.INVENTORY_KEYCODES, InputObject.KeyCode) then

		if InventoryIsOpen then
			Backpack:CloseInventory()
		else
			Backpack:OpenInventory()
		end

		return
	end
	
	if UserInputService:GetLastInputType().Name:match("Gamepad") then
		if GuiService.SelectedObject and GuiService.SelectedObject.Name == "ControllerSelectionFrame" and table.find(Backpack.Settings.FASTMOVE_KEYCODES, InputObject.KeyCode) then
			
			local Target
			
			local function findToolValue(inst)
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
			
			if not Target then return end
			
			local Slot = Backpack:GetSlotFromTool(Target.Value)
			local NewPosition = UDim2.fromOffset(Slot.Frame.Button.AbsolutePosition.X  + (Slot.Frame.Button.AbsoluteSize.X / 2), (Slot.Frame.Button.AbsolutePosition.Y + (Slot.Frame.Button.AbsoluteSize.Y / 2)))
			
			local NewSlot
			local NewerSlot
			
			if Slot.Position > Backpack.Settings.MaxHotbarToolSlots then
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
			
			GuiService.SelectedObject = NewerSlot.Frame.Button.ControllerSelectionFrame
			return
		end
	end

	local NumSlot = TranslateInput(InputObject)

	if not NumSlot then return end

	rbxwarn(HotbarSlots[NumSlot], NumSlot)

	if HotbarSlots[NumSlot] then
		Backpack:Equip(NumSlot)
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
		Backpack:Equip(NumSlot)
	end
end)

LocalPlayer.CharacterAdded:Connect(CharacterAdded)

if LocalPlayer.Character and LocalPlayer.Character:IsDescendantOf(workspace) then
	CharacterAdded(LocalPlayer.Character)
end

-- // 

return Backpack 