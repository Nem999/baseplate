local BackpackScript = require(script.Parent.BackpackScript)

BackpackScript.CooldownEnded:Connect(function()
    print('completed')
end)


BackpackScript.StartBackpack()

local t = BackpackScript:GetTools()[1]

while true do
    print('yes')
    BackpackScript:SetViewportEnabled(true, t)
    wait(4)
    BackpackScript:SetViewportEnabled(false, t)
    print('not')
    wait(4)
end