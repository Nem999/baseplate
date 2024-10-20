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

function init()
	PlayerDataService:EnableAutoSetup(Template)
end

PlayersService.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		local mesh = Instance.new("CharacterMesh")
		
		mesh.MeshId = 48112070
		mesh.BodyPart = Enum.BodyPart.Torso
		
		mesh.Parent = character
	end)
end)

task.wait(2)

--[[for i = 1, 60 do
	local to = Instance.new("Tool")
	to.Name = i
	
	to.Parent = game.Players:GetPlayers()[1].Backpack
end]]