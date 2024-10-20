--[[@Author: Spynaz
@Description: Enables dragging on GuiObjects. Supports both mouse and touch.

For instructions on how to use this module, go to this link:
https://devforum.roblox.com/t/simple-module-for-creating-draggable-gui-elements/230678
--]]

local UDim2_new = UDim2.new

local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local DraggableObject 		= {}
DraggableObject.__index 	= DraggableObject

-- Check if either mouse movement or touch input
function MouseOrTouchMovement(input)
    return input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch
end

-- Sets up a new draggable object
function DraggableObject.new(Object, MainGui, MoveCodes)
    local self 			= {}
    self.Object			= Object
    self.DragStarted	= nil
    self.DragEnded		= nil
    self.Dragged		= nil
    self.Dragging		= false
    self.MainGui 		= MainGui
    self.FastMoveCodes 	= MoveCodes

    setmetatable(self, DraggableObject)

    return self
end

-- Enables dragging
function DraggableObject:Enable()
    local object			= self.Object
    local dragInput			= nil
    local dragStart			= nil
    local startPos			= nil
    local preparingToDrag	= false
    
    local GhostObject
        
    -- Updates the element
    local function update(input)
        local delta 		= input.Position - dragStart
        local newPosition	= UDim2_new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        
        GhostObject.Position = newPosition

        return newPosition
    end

    self.InputBegan = object.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            
        local isOneKeyDown = false

        for _, key in pairs(self.FastMoveCodes) do
            if UserInputService:IsKeyDown(key) then
                isOneKeyDown = true
                break
            end
        end
        
        if isOneKeyDown then return end
            
            preparingToDrag = true

            local connection 
            connection = input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End and (self.Dragging or preparingToDrag) then
                    self.Dragging = false
                    connection:Disconnect()

                    if self.DragEnded and not preparingToDrag then
                        
                    local GhostPosition = Vector2.new(GhostObject.AbsolutePosition.X  + (GhostObject.AbsoluteSize.X / 2), (GhostObject.AbsolutePosition.Y + (GhostObject.AbsoluteSize.Y / 2)))
                        
                    if GhostObject then GhostObject:Destroy() self.GhostObject = nil end
                    
                        self.DragEnded(GhostPosition)
                    end

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

    self.InputChanged2 = UserInputService.InputChanged:Connect(function(input)
        if object.Parent == nil then
            self:Disable()
            return
        end

        if MouseOrTouchMovement(input) and preparingToDrag then
            preparingToDrag = false

            if self.DragStarted then
                
            if GhostObject then GhostObject:Destroy() self.GhostObject = nil end
                
            GhostObject = self.Object.Parent:Clone()
            self.GhostObject = GhostObject
                
            if GhostObject.Parent ~= self.MainGui then 
                GhostObject.Parent = self.MainGui
                
                GhostObject.Visible = true
            end
            
            GhostObject.Name = "_Ghost"
            
                self.DragStarted()
            end

            self.Dragging	= true
            dragStart 		= input.Position
            startPos 		= UDim2.fromOffset(object.AbsolutePosition.X + GuiService:GetGuiInset().X,  object.AbsolutePosition.Y + GuiService:GetGuiInset().Y)
        end

        if input == dragInput and self.Dragging then
            local newPosition = update(input)

            if self.Dragged then
                self.Dragged(newPosition)
            end
        end
    end)
end

-- Disables dragging
function DraggableObject:Disable()
    self.InputBegan:Disconnect()
    self.InputChanged:Disconnect()
    self.InputChanged2:Disconnect()
    
    local GhostPosition
    
    if self.GhostObject then
    GhostPosition =  Vector2.new(self.GhostObject.AbsolutePosition.X  + (self.GhostObject.AbsoluteSize.X / 2), (self.GhostObject.AbsolutePosition.Y + (self.GhostObject.AbsoluteSize.Y / 2)))
        self.GhostObject:Destroy()
        
        self.GhostObject = nil
    end

    if self.Dragging then
        self.Dragging = false

        if self.DragEnded then
            self.DragEnded(GhostPosition)
        end
    end
end


return DraggableObject