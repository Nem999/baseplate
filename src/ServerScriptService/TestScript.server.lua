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

PlayersService.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
	end)
end)