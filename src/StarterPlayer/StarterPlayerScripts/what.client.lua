local BackpackScript = require(script.Parent.BackpackScript)

BackpackScript.CooldownEnded:Connect(function()
    print('completed')
end)


BackpackScript.StartBackpack()
