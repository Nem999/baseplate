local BackpackScript = require(script.Parent.BackpackScript)

BackpackScript.StartBackpack()

BackpackScript.DragStarted:Connect(function()
    print('drag started')
end)

BackpackScript.DragEnded:Connect(function()
    print('drag ended')
end)