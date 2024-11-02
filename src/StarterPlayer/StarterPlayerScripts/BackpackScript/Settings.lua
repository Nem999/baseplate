local Settings = {}



Settings.MaxHotbarToolSlots = 10 -- Maxmimum amount of slots allowed to be displayed. Change to a lower number if you want less tools to be displayed reguardless of screen size.
Settings.NeededFreeSpace = 480 -- How much horizontal space is reserved.
Settings.MinHotbarSlots = 3 -- The minimum amount of hotbar slots allowed to be displayed. Change to higher number if you are willing to give up more space.
Settings.EquipCooldown = 0.1 -- How long the player has to wait in between equipping tools.
Settings.SweepInterval = 120 -- How long it takes for the backpack script to clear unused inventory slots from memory.
Settings.MaxHeldTools = 3 -- How many tools can be held at any given time.



Settings.AutoCalculateMaxToolSlots = true -- If set to true the backpack script will automatically calculate how many tools can fit at once.
Settings.UseViewportFrame = false -- If set to true then a viewport frame will display tools instead.
Settings.USE_SCROLLWHEEL = false -- If set to true then scrolling with your mouse will cycle through tools.
Settings.Animate = false -- If set to true then tools will be more animated if set to false then tools will not be animated.



Settings.BackpackButtonOpenedColor = Color3.fromRGB(141, 164, 238) -- Color of the backpack button when the inventory is opened



Settings.DesiredPadding = UDim.new(0, 10) -- Spacing of tools



Settings.INVENTORY_OPENANDCLOSE_KEYCODES = { -- Which keycodes will open and close the inventory
	Enum.KeyCode.Backquote,
	Enum.KeyCode.DPadDown,
}

Settings.FASTMOVE_KEYCODES = { -- Holding one of these keycodes while clicking on a tool slot while the inventory is open will preform a fast move
	Enum.KeyCode.LeftControl,
	Enum.KeyCode.RightControl,
	Enum.KeyCode.ButtonY,
}

Settings.GUI_SELECTION_KEYCODES = { -- Pressing one of these buttons while selecting a tool slot in Ui navigation mode will select that tool slot
	Enum.KeyCode.ButtonB,
	Enum.KeyCode.Return,
}

Settings.CYCLE_LEFT_KEYCODES = { -- Pressing one of these buttons will cycle left in the hotbar
    Enum.KeyCode.ButtonL1,
}

Settings.CYCLE_RIGHT_KEYCODES = { -- Pressing one of these buttons will cycle right in the hotbar
    Enum.KeyCode.ButtonR1,
}

local err = ""

local function insertError(error)
    err = err.."\n                "..error
end

local function checkType(value, NeededType)
    if typeof(Settings[value]) ~= NeededType then
        insertError(`Setting "{value}" is not of type: {NeededType}`)
    end
end

local function validateSettings()
    -- Type checks

    checkType("MaxHotbarToolSlots", "number")
    checkType("MinHotbarSlots", "number")
    checkType("EquipCooldown", "number")
    checkType("MaxHeldTools", "number")

    checkType("AutoCalculateMaxToolSlots", "boolean")
    checkType("UseViewportFrame", "boolean")
    checkType("USE_SCROLLWHEEL", "boolean")
    checkType("Animate", "boolean")

    checkType("BackpackButtonOpenedColor", "Color3")
    checkType("DesiredPadding", "UDim")

    checkType("INVENTORY_OPENANDCLOSE_KEYCODES", "table")
    checkType("FASTMOVE_KEYCODES", "table")
    checkType("GUI_SELECTION_KEYCODES", "table")
    checkType("CYCLE_LEFT_KEYCODES", "table")
    checkType("CYCLE_RIGHT_KEYCODES", "table")

    if typeof(Settings.MaxHotbarToolSlots) == "number" then -- Prevent it from erroring if developer didn't put a number
        if Settings.MaxHotbarToolSlots < Settings.MinHotbarSlots then
            insertError("Max hotbar slots cannot be less than minimum.")
        end
    
        if Settings.MaxHotbarToolSlots > 10 then
            insertError("Max hotbar slots cannot be more than 10")
        end
    end

    if err ~= "" then
        error("[BackpackScript]: Invalid Settings "..err, 0)
    end
end

validateSettings()

return Settings