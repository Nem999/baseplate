local BackpackScript = require(script.Parent.BackpackScript)

local glue = false

BackpackScript.ItemAdded:Connect(function(Item)
    if glue then return end
    glue = true
    BackpackScript:GlueTool(Item.Tool.Value)
end)

BackpackScript.StartBackpack()

