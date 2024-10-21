--[[ SERVICES ]]--
local ServerScriptService = game:GetService("ServerScriptService")
local PlayersService = game:GetService("Players")

--[[ MODULES ]]--
local PlayerDataService = require(ServerScriptService.PlayerSaveService)

--[[ FUNCTIONS ]]--

local Template = {
	["Settings"] = {
		canrun = true,
		something = false
	}
}

local function stateChanged(state, dataStore)
	while dataStore.State == false do
		if dataStore:Open() ~= "Success" then task.wait(7) end
	end
end

function init()
	PlayerDataService:EnableAutoSetup(Template)
end

--[[function PlayerAdded(plr)
	local DataStore = DataStoreModule.new("Player", plr.UserId)

	local function CharacterAdded()
		if DataStore.State == true then
			local Tools = DataStore.Value.Tools

			for _, Tool in pairs(Tools) do
				local ToolInstance = game.ReplicatedStorage.Tools:FindFirstChild(Tool.Name)

				local ToolClone = ToolInstance:Clone()

				ToolClone.Parent = plr.Backpack
			end
		end
	end

	plr.CharacterAdded:Connect(CharacterAdded)

	if plr.Character then
		CharacterAdded(plr.Character)
	end

	DataStore.StateChanged:Connect(stateChanged)

	task.defer(function()
		stateChanged(DataStore.State, DataStore)
	end)
end]]


task.wait(2)

--[[for i = 1, 60 do
	local to = Instance.new("Tool")
	to.Name = i
	
	to.Parent = game.Players:GetPlayers()[1].Backpack
end]]