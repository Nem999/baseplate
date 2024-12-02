local UDim2_new = UDim2.new

local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local DraggableObject 		= {}
DraggableObject.__index 	= DraggableObject
local DraggingObj = nil


function MouseOrTouchMovement(input)
	return input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch
end

function DraggableObject.new(Object, MainGui, MoveCodes, BP)
	local self 			= {}
	self.Object			= Object.Frame.Button
	self.DragStarted	= nil
	self.DragEnded		= nil
	self.Dragged		= nil
	self.Dragging		= false
	self.MainGui 		= MainGui
	self.FastMoveCodes 	= MoveCodes
	self.BP = BP
	self.Data = Object

	setmetatable(self, DraggableObject)

	return self
end

function DraggableObject:Enable()
	local object:ImageButton			= self.Object
	local dragInput			= nil
	local dragStart			= nil
	local startPos			= nil
	local preparingToDrag	= false
    local isDragging = false
	local Data = self.Data

	local GhostObject

	local function update(input)
		local mouselocation = UserInputService:GetMouseLocation()

		local newPosition	= UDim2_new(0, mouselocation.X + GuiService:GetGuiInset().X - (object.AbsoluteSize.X / 2), 0, mouselocation.Y + (object.AbsoluteSize.Y / 2) - GuiService:GetGuiInset().Y)

		GhostObject.Position = newPosition

		return newPosition
	end

    local function doDragging (input, _, ignore)
        if not self.BP.Settings.CanOrganize then return end

		if object.Parent.Parent == self.MainGui.Inventory.InventoryMain.Background.ScrollingFrame then
			if not self.BP:IsInventoryOpen() then return end
		end

		if UserInputService.TouchEnabled then
			if not self.BP:IsInventoryOpen() then return end
		end

		if not object.Parent.Tool.Value then return end

		if ignore or MouseOrTouchMovement(input) and preparingToDrag then
			if DraggingObj then return end
			preparingToDrag = false


			if ignore or self.DragStarted then
                if not isDragging then return end

				local StartTime = workspace:GetServerTimeNow()
				local NeededTime = workspace:GetServerTimeNow() + 0.15

				local Stroke = Instance.new("UIStroke")
				Stroke.Color = Color3.fromRGB(84, 104, 216)
				Stroke.Thickness = 2
				Stroke.Transparency = 1

				Stroke.Parent = object

                DraggingObj = object

				while workspace:GetServerTimeNow() < NeededTime do
					if not isDragging then Stroke:Destroy() DraggingObj = nil return end
                    if not UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then DraggingObj = nil Stroke:Destroy() return end

					Stroke.Transparency = 1 + math.abs(1 - (workspace:GetServerTimeNow() - StartTime) / ((StartTime + 0.15) - StartTime))
					task.wait()
				end

				Stroke:Destroy()

				if not isDragging then return end

				if GhostObject then GhostObject:Destroy() self.GhostObject = nil end

				GhostObject = self.Object.Parent:Clone()
				self.GhostObject = GhostObject

				if GhostObject.Parent ~= self.MainGui then 
					GhostObject.Parent = self.MainGui

					GhostObject.Visible = true
				end

				GhostObject.Name = "_Ghost"

				self.BP.DragStarted:Fire(Data.Tool, Data.Frame, GhostObject, false)

				self.DragStarted()
			end

            if not input then
                local mouselocation = UserInputService:GetMouseLocation()

                dragStart = UDim2_new(0, mouselocation.X + GuiService:GetGuiInset().X - (object.AbsoluteSize.X / 2), 0, mouselocation.Y + (object.AbsoluteSize.Y / 2) - GuiService:GetGuiInset().Y)
            else
                dragStart 		= input.Position
            end

			self.Dragging	= true
			startPos 		= UDim2.fromOffset(object.AbsolutePosition.X + GuiService:GetGuiInset().X,  object.AbsolutePosition.Y + GuiService:GetGuiInset().Y)
		end

		if input == dragInput and self.Dragging then
			local newPosition = update(input)

			if self.Dragged then
				self.Dragged(newPosition)
			end
		end
    end

	self.InputBegan = object.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			if Data.Locked then return end
			if Data.Glued then return end
			if not Data.Tool then return end

			local isOneKeyDown = false

			for _, key in pairs(self.FastMoveCodes) do
				if UserInputService:IsKeyDown(key) then
					isOneKeyDown = true
					break
				end
			end

			if isOneKeyDown then return end

			preparingToDrag = true
            isDragging = true

            doDragging(false, nil, true)

			local connection 
			connection = input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End and (self.Dragging or preparingToDrag or isDragging) then
					self.Dragging = false
					connection:Disconnect()

					DraggingObj = nil

					if self.DragEnded and not preparingToDrag and GhostObject then

						local GhostPosition = UDim2.fromOffset(GhostObject.AbsolutePosition.X  + (GhostObject.AbsoluteSize.X / 2), (GhostObject.AbsolutePosition.Y + (GhostObject.AbsoluteSize.Y / 2)))

						if GhostObject then GhostObject:Destroy() self.GhostObject = nil end

						self.BP.DragEnded:Fire(Data.Tool, Data.Frame, GhostObject, false, GhostPosition)

						self.DragEnded(GhostPosition)
					end

                    isDragging = false
					preparingToDrag = false
				end
			end)
		end
	end)

	self.InputChanged = object.InputChanged:Connect(function(input)
		if MouseOrTouchMovement(input) then
			dragInput = input
		end
	end)

	self.InputChanged2 = UserInputService.InputChanged:Connect(doDragging)
end

function DraggableObject:Disable()
	self.InputBegan:Disconnect()
	self.InputChanged:Disconnect()
	self.InputChanged2:Disconnect()

	DraggingObj = nil

	local GhostPosition

	if self.GhostObject then
		GhostPosition =  UDim2.fromOffset(self.GhostObject.AbsolutePosition.X  + (self.GhostObject.AbsoluteSize.X / 2), (self.GhostObject.AbsolutePosition.Y + (self.GhostObject.AbsoluteSize.Y / 2)))
		self.GhostObject:Destroy()

		self.GhostObject = nil
	end

	if self.Dragging then
		self.Dragging = false
		self.BP.DragEnded:Fire(self.Data.Tool, self.Data.Frame, self.GhostObject, false, GhostPosition or UDim2_new())

		if self.DragEnded then
			self.DragEnded(GhostPosition)
		end
	end
end


return DraggableObject