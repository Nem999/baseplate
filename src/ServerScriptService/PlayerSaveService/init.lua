--[[ SERVICES ]]--
local MemoryStoreService = game:GetService("MemoryStoreService")
local DataStoreService = game:GetService("DataStoreService")
local HTTPService = game:GetService("HttpService")
local PlayersService = game:GetService("Players")

--[[ MODULES ]]--
local Signal = require(script.Signal)

--[[ CONSTANTS ]]--
local DataStoreObjects = {}
local DataStore = {}
local PendingClosureDatastores = {}
local retryAttempts = 3
local IsServiceActive = true
local autoSetup = false
local GlobalTemplate = nil

DataStore.Responses = {
	["IN_USE"] = "423 (LOCKED)",
	["ERROR"] = "500 (ERROR)",
	["OK"] = "200 (OK)",
}

DataStore.States = {
	["DEAD"] = "Dead",
	["DESTROYING"] = "Destroying",
	["SAVING"] = "Saving",
	["CLOSED"] = "Closed",
	["CLOSING"] = "Closing",
	["OPEN"] = "Open",
	["OPENING"] = "Opening"
}

--[[ FUNCTIONS ]]--

function isPlayer(Player)
	if typeof(Player) == "Instance" and Player:IsA("Player") then return true else return false end
end

function Clone(original)
	if type(original) ~= "table" then return original end
	local clone = {}
	for index, value in original do clone[index] = Clone(value) end
	return clone
end

function Reconcile(target, template)
	for index, value in template do
		if type(index) == "number" then continue end
		if target[index] == nil then
			target[index] = Clone(value)
		elseif type(target[index]) == "table" and type(value) == "table" then
			Reconcile(target[index], value)
		end
	end
end

function Destroy(DataStore)
	if DataStore.Status == DataStore.States.OPENING then DataStore.StatusChanged:Wait() end
	if DataStore.Status == DataStore.States.SAVING then DataStore.Saved:Wait() end
	if DataStore.Status == DataStore.States.DEAD or DataStore.Status == DataStore.States.DESTROYING then return end
	
	local IsDataStoreClosing = DataStore.Status == DataStore.States.CLOSING or DataStore.Status == DataStore.States.CLOSED
	
	DataStore.Status = DataStore.States.DESTROYING
	DataStore.StatusChanged:Fire(DataStore.States.DESTROYING)
	
	if not IsDataStoreClosing then
		DataStore:Close()
	end

	DataStore.Saving:DisconnectAll()
	DataStore.Saved:DisconnectAll()
	
	DataStore.Status = DataStore.States.DEAD
	DataStore.StatusChanged:Fire(DataStore.States.DEAD)
	DataStore.StatusChanged:DisconnectAll()
	
	DataStore.DataFetched:DisconnectAll()
	DataStore.FetchingData = false
	
	DataStore.DataStoreOptions:Destroy()
	
	DataStoreObjects[DataStore.Id] = nil
	PendingClosureDatastores[DataStore.Cookie] = nil
end

function LoadData(DataStore)
	local success, value, info = nil, nil, nil
	
	DataStore.FetchingData = true

	for i = 1, retryAttempts do
		if i > 1 then task.wait(1) end
		success, value, info = pcall(DataStore.DataStore.GetAsync, DataStore.DataStore, DataStore.key)
		if success == true then break end
	end
	
	DataStore.FetchingData = false

	if not success then DataStore.DataFetched:Fire(DataStore.Responses.ERROR) return DataStore.Responses.ERROR end

	if info then
		DataStore.Metadata = info:GetMetadata()
		DataStore.UserIds = info:GetUserIds()
		DataStore.CreatedTime = info.CreatedTime
		DataStore.Version = info.Version
	end
	
	DataStore.DataFetched:Fire(DataStore.Responses.OK, value)
	
	return DataStore.Responses.OK, value
end

function StartAutoSave(DataStore)
	if DataStore.SaveInterval == 0 then return end
	if DataStore.AutoSaveThread then task.cancel(DataStore.AutoSaveThread) end
	DataStore.AutoSaveThread = task.delay(DataStore.SaveInterval, AutoSaveTimerEnded, DataStore)
end

function AutoSaveTimerEnded(DataStore)
	DataStore.AutoSaveThread = nil
	Save(DataStore)
	
	task.spawn(StartAutoSave, DataStore)
end

function StopAutoSaving(DataStore)
	if DataStore.AutoSaveThread then task.cancel(DataStore.AutoSaveThread) end

	DataStore.AutoSaveThread = nil
end

function ScheduleNextServerLock(DataStore)
	if DataStore.LockThread then task.cancel(DataStore.LockThread)  end
	local startTime = DataStore.LastSessionLock - DataStore.AttemptsRemaining * DataStore.LockInterval
	
	DataStore.LockThread = task.delay(startTime - os.clock() + DataStore.LockInterval, LockTimerEnded, DataStore)
end

function LockTimerEnded(DataStore)
	DataStore.LockThread = nil
	local Response = LockDataStore(DataStore)

	if Response ~= DataStore.Responses.OK then
		DataStore.AttemptsRemaining -= 1
		
		if DataStore.AttemptsRemaining < 0 then
			DataStore:Close()

			return
		end
	end
	
	task.spawn(ScheduleNextServerLock, DataStore)
end

function StopServerLocking(DataStore)
	if DataStore.LockThread then task.cancel(DataStore.LockThread) end

	DataStore.LockThread = nil
end

function Save(DataStore)
	DataStore.Saving:Fire(DataStore.Data)
	
	local Status = DataStore.Status
	
	if Status ~= DataStore.States.DESTROYING then
		DataStore.Status = DataStore.States.SAVING
	end

	DataStore.DataStoreOptions:SetMetadata(DataStore.Metadata)
	local success, value, info

	if DataStore.Data == nil then
		for i = 1, retryAttempts do
			if i > 1 then task.wait(1) end

			success, value = pcall(DataStore.DataStore.RemoveAsync, DataStore.DataStore, DataStore.key)

			if success then break end
		end
	else
		for i = 1, retryAttempts do
			if i > 1 then task.wait(1) end

			success, value = pcall(DataStore.DataStore.SetAsync, DataStore.DataStore, DataStore.key, DataStore.Data, DataStore.UserIds, DataStore.DataStoreOptions)

			if success then break end
		end
	end
	
	DataStore.Status = Status

	if not success then
		DataStore.Saved:Fire(DataStore.Responses.ERROR, DataStore.Data)

		return DataStore.Responses.ERROR
	else
		DataStore.LastSave = os.clock()
		DataStore.Saved:Fire(DataStore.Responses.OK, DataStore.Data)

		return DataStore.Responses.OK, DataStore.Data
	end
end

function UnlockDatastore(DataStore)
	local success, value
	local id

	for i = 1, retryAttempts do
		if i > 1 then task.wait(1) end
		success, value = pcall(DataStore.MemoryStore.UpdateAsync, DataStore.MemoryStore, "Lock", function(value)
			id = value

			return if id == nil or id == DataStore.Cookie then DataStore.Cookie else nil -- Datastore is locked.
			
		end, 0)

		if success == nil then return DataStore.Responses.ERROR, value end
		if value == nil and id ~= DataStore.Cookie then return DataStore.Responses.IN_USE, id end

		return DataStore.Responses.OK
	end

end	

function LockDataStore(DataStore)
	local success, value
	local id
	local locktime
	local lockinterval = DataStore.LockInterval
	local lockAttempts = DataStore.LockAttmpts

	for i = 1, retryAttempts do
		if i > 1 then task.wait(1) end
		locktime = os.clock()
		success, value = pcall(DataStore.MemoryStore.UpdateAsync, DataStore.MemoryStore, "Lock", function(value)
			id = value

			return if id == nil or id == DataStore.Cookie then DataStore.Cookie else nil 
	
		end, lockinterval * lockAttempts + 30)

		if success then break end
	end


	if not value then return DataStore.Responses.IN_USE end
	if not success then return DataStore.Responses.ERROR end

	DataStore.LastSessionLock = locktime + lockinterval * lockAttempts
	DataStore.AttemptsRemaining = lockAttempts
	
	return DataStore.Responses.OK
end

function OnPlayerJoined(Player : Player)
	if not autoSetup then return end
	
	local DataStoreObject = DataStore.new("Players", Player.UserId)
	
	local template = GlobalTemplate or {}
	
	DataStoreObject.StatusChanged:Connect(function(Status) -- Datastore was closed for some reason
		if Status == DataStore.States.CLOSED and DataStoreObject.AttemptsRemaining == 0 then
			while DataStoreObject.Status ~= DataStore.States.DEAD do
				task.wait(6)
				
				local Response = DataStoreObject:Load(template)
				
				if Response == DataStore.Responses.OK then break end
			end
		end
	end)
	
	
	while DataStoreObject.Status ~= DataStore.States.DEAD do
		local Response = DataStoreObject:Load(template)

		if Response == DataStore.Responses.OK then print('OK') break end
		print('no load')
		task.wait(3)
	end
	
	DataStoreObject.Saving:Connect(function()
		print('saving')
	end)
	
	DataStoreObject.Saved:Connect(function(code)
		print("saved with "..code)
	end)
end

function OnPlayerLeave(Player : Player)
	if not autoSetup then return end
	
	local DataStoreObject = DataStore.find("Players", Player.UserId)
	
	if DataStoreObject then
		DataStoreObject:Destroy()
	end
end

function DataStore:GetPlayerData() -- Idk why you would use this function instead of just using DataStore.Data ???
	return self.Data
end

function DataStore:GetPlayerDataStore(Player : Player)
	if not isPlayer(Player) then error("Argument 1 is not a player.") end
	
	return DataStore.find("Players", Player.UserId)
end

function DataStore:Save() -- Force saves the data in this datastore object (Warning: Do not implement an auto save that uses this function. Data will save automatically.)
	if self.Status == DataStore.States.CLOSED then warn("Cannot save because datastore is currently closed.") return DataStore.Responses.ERROR, DataStore.States.CLOSED end
	if self.Status == DataStore.States.DEAD then  warn("Cannot save because datastore is currently destroyed.") return DataStore.Responses.ERROR, DataStore.States.DEAD end

	if self.Status == DataStore.States.SAVING then
		return self.Saved:Wait() -- If the datastore is already saving then we're just going to wait for the save to complete then return the result of that save.
	end

	local Response, Data = Save(self)

	return Response, Data
end

function DataStore:Load(templete : table) -- Loads the datastore
	if IsServiceActive == false then return DataStore.Responses.ERROR end
	if self.Status == DataStore.States.DEAD or self.Status == DataStore.States.DESTROYING then return DataStore.Responses.ERROR end
	if self.Status == DataStore.States.OPEN or self.Status == DataStore.States.SAVING then return DataStore.Responses.OK end
	if self.Status == DataStore.States.OPENING then self.StatusChanged:Wait() if self.Status == DataStore.States.OPEN then return DataStore.Responses.OK else return DataStore.Responses.ERROR end end
	
	self.AttemptsRemaining = self.LockAttmpts

	self.Status = DataStore.States.OPENING
	self.StatusChanged:Fire(DataStore.States.OPENING)

	local Response = LockDataStore(self)

	if Response ~= DataStore.Responses.OK then self.Status = DataStore.States.CLOSED return Response end

	local Response, Data = LoadData(self)

	if Response ~= DataStore.Responses.OK then
		UnlockDatastore(self)
		self.Status = DataStore.States.CLOSED
		return Response
	end
	
	self.Status = DataStore.States.OPEN
	self.StatusChanged:Fire(DataStore.States.OPEN)
	
	self.Data = Data
	
	if self.Data == nil then
		self.Data = Clone(templete)
	elseif typeof(Data) == "table" and typeof(templete) == "table" then
		Reconcile(self.Data, templete)
	end
	
	ScheduleNextServerLock(self)
	StartAutoSave(self)

	return Response
end

function DataStore:Read() -- Returns the data stored in the data store (Use DataStore.Data if you need to get the most up-to-date value.)
	if self.FetchingData then return self.DataFetched:Wait() end
	
	return LoadData(self)
end

function DataStore:Close() -- Closes the datastore
	if self.Status == DataStore.States.DEAD then return end
	if self.Status == DataStore.States.CLOSED then return end
	if self.Status == DataStore.States.CLOSING then return end
	
	if self.Status ~= DataStore.States.DESTROYING then
		self.Status = DataStore.States.CLOSING
		self.StatusChanged:Fire(DataStore.States.CLOSING)
	end
	
	self:Save()
	
	StopAutoSaving(self)
	StopServerLocking(self)
	
	UnlockDatastore(self)
	
	if self.Status ~= DataStore.States.DESTROYING then
		self.Status = DataStore.States.CLOSED
		self.StatusChanged:Fire(DataStore.States.CLOSED)
	end
end

function DataStore:Wipe() -- Wipes all of the data in a given datastore.
	if self.Status == DataStore.States.SAVING then DataStore.Saved:Wait() end
	if self.Status ~= DataStore.States.OPEN then error("Cannot wipe datastore because: Datastore is not open.") end
	
	self.Data = nil
end

function DataStore:Destroy() -- Closes and frees a datastore from memory
	Destroy(self)
end

function DataStore:Clone() -- Clones and returns the DataStore Data
	if self.Data then
		return Clone(self.Data)
	end
end

function DataStore.new(name : string?, scope : string?, key : string?) -- Creates and returns a datastore object if one for the current key doesn't already exist
	if key == nil then key, scope = scope, "global" end
	local id = name .. "/" .. scope .. "/" .. key

	if DataStoreObjects[id] then
		return DataStoreObjects[id] -- no need to create another datastore object if one already exists
	end

	local self = setmetatable({
		Saving = Signal.new(),
		Saved = Signal.new(),
		Status = DataStore.States.CLOSED,
		StatusChanged = Signal.new(),
		FetchingData = false,
		DataFetched = Signal.new(),
		SaveInterval = 30,
		LockInterval = 60,
		LockAttmpts = 5,
		AttemptsRemaining = 0,
		LastSessionLock = -math.huge,
		LastSave = -math.huge,
		DataStore = DataStoreService:GetDataStore(name, scope),
		DataStoreOptions = Instance.new("DataStoreSetOptions"),
		MemoryStore = MemoryStoreService:GetSortedMap(id),
		Cookie = HTTPService:GenerateGUID(false),
		UserIds = {},
		Metadata = {},
		CreatedTime = 0,
		UpdatedTime = 0,
		Version = "",
		key = key,
		Id = id,
		Hidden = false
	}, {__index = DataStore
	})

	DataStoreObjects[id] = self
	if IsServiceActive then PendingClosureDatastores[self.Cookie] = self end

	return self
end

function DataStore.hidden(name : string?, scope : string?, key : string?) -- Creates and returns a hidden datastore object this object will not be returned to any new calls.
	if key == nil then key, scope = scope, "global" end
	local id = name .. "/" .. scope .. "/" .. key
	

	local self = setmetatable({
		Saving = Signal.new(),
		Saved = Signal.new(),
		Status = DataStore.States.CLOSED,
		StatusChanged = Signal.new(),
		FetchingData = false,
		DataFetched = Signal.new(),
		SaveInterval = 30,
		LockInterval = 60,
		LockAttmpts = 5,
		AttemptsRemaining = 0,
		LastSessionLock = -math.huge,
		LastSave = -math.huge,
		DataStore = DataStoreService:GetDataStore(name, scope),
		DataStoreOptions = Instance.new("DataStoreSetOptions"),
		MemoryStore = MemoryStoreService:GetSortedMap(id),
		Cookie = HTTPService:GenerateGUID(false),
		UserIds = {},
		Metadata = {},
		CreatedTime = 0,
		UpdatedTime = 0,
		Version = "",
		key = key,
		Id = id,
		Hidden = true
	}, {__index = DataStore
	})

	if IsServiceActive then PendingClosureDatastores[self.Cookie] = self end

	return self
end

function DataStore.find(name, scope, key)
	if key == nil then key, scope = scope, "global" end
	local id = name .. "/" .. scope .. "/" .. key
	
	return DataStoreObjects[id]
end

function DataStore:EnableAutoSetup(template)
	if autoSetup then return end
	GlobalTemplate = template
	autoSetup = true
	
	for _, Player in pairs(PlayersService:GetPlayers()) do
		task.spawn(OnPlayerJoined, Player)
	end
end

function DataStore:DisableAutoSetup()
	autoSetup = false
end

function BindToClose(closeReason)
	IsServiceActive = false

	for id, DataStore in pairs(PendingClosureDatastores) do
		if DataStore.Status == DataStore.States.DEAD or DataStore.Status == DataStore.States.DESTROYING then continue end
		
		task.spawn(Destroy, DataStore)
	end
	
	while next(PendingClosureDatastores) ~= nil do task.wait() end -- Wait for all the datastores to finish destroying
end

--[[ RUNTIME ]]--

game:BindToClose(BindToClose)

PlayersService.PlayerAdded:Connect(OnPlayerJoined)
PlayersService.PlayerRemoving:Connect(OnPlayerLeave)

for _, Player in pairs(PlayersService:GetPlayers()) do
	task.spawn(OnPlayerJoined, Player)
end

-- //

return DataStore