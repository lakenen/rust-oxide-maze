PLUGIN.Title = 'Maze Plugin'
PLUGIN.Description = 'Teleporter Addon with economy support'
PLUGIN.Author = 'camupod'
PLUGIN.Version = '0.0.1'

local dateTime = util.GetStaticPropertyGetter(System.DateTime, 'Now')

function PLUGIN:Init()
    print('Maze :: Plugin loading...')

    print('Maze :: Loading data file')
    self:LoadMazedata()

    print('Maze :: Loading config file')
    self:LoadMazeConfig()

    self.LogFile = util.GetDatafile('maze_log')
    local x = self.LogFile:GetText()
    if (x ~= '') then
        self.Log = self.LogFile:GetText()
        self.Log = 'SERVER RESTARTED.'
        self:LogSave()
    else
        print('Maze :: No log file found. Creating new log file...')
        self.Log = 'Log created!'
        self:LogSave()
        print('Maze :: Log file created!')
    end

    print('Maze :: Adding commands')
    self:AddChatCommand('maze', self.HandleMazeCommand)

    print('Maze :: Plugin loaded')
end

function PLUGIN:SaveMazeConfig()
    self.MazeConfigFile:SetText(json.encode(self.MazeConfig, { indent = true }))
    self.MazeConfigFile:Save()
end

function PLUGIN:LoadMazeConfig()
    self.MazeConfigFile = util.GetDatafile('maze_config')
    local txt = self.MazeConfigFile:GetText()
    if (txt ~= '') then
        local MazeConfigTmp = json.decode(txt)
        if (not (MazeConfigTmp)) then
            print ('Maze :: Config file is corrupted!')
            return false
        else
            self.MazeConfig = MazeConfigTmp
            self:LoadDefaultConfig() -- Update any new config values
            return true
        end
    else
        print ('Maze :: Config file is empty, setting defaults!')
        self:LoadDefaultConfig() -- Update any new config values
        self.MazeConfig = self.MazeDefaultConfig
        self:SaveMazeConfig()
    end
end

function PLUGIN:LoadDefaultConfig()
    local MazeDefaultConfig = {
        VERSION = '0.0.1'
        yOffset = 5
        items = {}
    }

    if (not self.MazeConfig.VERSION or MazeDefaultConfig.VERSION > self.MazeConfig.VERSION) then
        print ('Maze :: Creating Backup copy of Maze Config')
        self.MazeConfigBackup = util.GetDatafile('maze_config_backup')
        self.MazeConfigBackup:SetText(json.encode(self.MazeConfig, { indent = true }))
        self.MazeConfigBackup:Save()
        print ('Maze :: Loading new default config values')
        for _key, _value in pairs(MazeDefaultConfig) do
            if (not self.MazeConfig[_key] and self.MazeConfig[_key] == nil) then --also test for bool false
                print(_key, _value)
                self.MazeConfig[_key] = _value
            end
        end
        print ('Maze :: Removing Obselete config values')
        for _key, _value in pairs(self.MazeConfig) do
            if (not MazeDefaultConfig[_key] and MazeDefaultConfig[_key] == nil) then -- also test for bool false
                print(_key, _value)
                self.MazeConfig[_key] = nil
            end
        end
    print ('Maze :: Done updating Config, Saving new config file')
    self:SaveMazeConfig()
    end
    return
end

function PLUGIN:LogSave()
    local templog = self.LogFile:GetText()
    self.LogFile:SetText(tostring(templog) .. '\n' .. tostring(dateTime()) .. ': ' .. tostring(self.Log)) -- !!! Find better solution for this. !!!
    self.LogFile:Save()
end

function PLUGIN:SaveMazeData()
    self.MazeDataFile:SetText(json.encode(self.MazeData, { indent = true }))
    self.MazeDataFile:Save()
end

function PLUGIN:LoadMazeData()
    print('Maze :: Loading data file')
    self.MazeDataFile = util.GetDatafile('maze_data')
    local txt = self.MazeDataFile:GetText()
    if (txt ~= '') then
        local MazeDataTmp = json.decode(txt)
        if (not (MazeDataTmp)) then
            print ('Maze :: Data file is corrupted!')
            --would be good to check for corruption and load backup file
            return false
        end
        self.MazeData = MazeDataTmp
        print ('Maze :: Data file loaded.')
        return true
    else
        print ('Maze :: Data file is empty! Setting defaults.')
        self.MazeData = {}
        self.MazeData['meta'] = {}
        self.MazeData['meta']['VERSION'] = '1.0'

        self:SaveMazeData()
    end
end

function PLUGIN:addSpawnLocation(netuser, name)
    if (not netuser:CanAdmin()) then
        return
    end

    if (not self.MazeData.spawnLocations) then
        -- first spawn point ?
        self.MazeData.spawnLocations = {}
    end

    local coords = netuser.playerClient.lastKnownPosition

    self.MazeData.spawnLocations[name] = {
        x = coords.x,
        y = coords.y,
        z = coords.z
    }
    self:SaveMazeData()
    self.Log =  'Created maze spawn point "' .. name .. '"'
    self:LogSave()

    rust.Notice(netuser, 'Spawn location set!')
end

function PLUGIN:deleteSpawnLocation(netuser, name)
    if (not self:CanUserAdmin(netuser)) then
        return
    end

    if (not self.MazeData.spawnLocations) then
        return
    end

    self.MazeData.spawnLocations[name] = nil
    self:SaveMazeData()
    self.Log =  'Removed maze spawn point "' .. name .. '"'
    self:LogSave()

    rust.Notice(netuser, 'Spawn location removed!')
end

function PLUGIN:goToMaze(netuser)
    local spawnLocations = self.MazeData.spawnLocations
    local playerCoords = netuser.playerClient.lastKnownPosition
    local spawnCoords = spawnLocations[math.random(#spawnLocations)]

    playerCoords.x = spawnCoords.x
    playerCoords.y = spawnCoords.y + self.MazeConfig.yOffset
    playerCoords.z = spawnCoords.z

    -- send them in!
    rust.ServerManagement():TeleportPlayer(netuser.playerClient.netPlayer, playerCoords)

    -- clear their inventory, and give them a few things...
    local inv = rust.GetInventory(netuser)
    inv:Clear()
    for item in self.MazeConfig.items
        self.giveItem(netuser, item.name, item.amount)
    end

    rust.Notice(netuser, 'You are now in the maze. Good luck!')
end

function PLUGIN:giveItem(netuser, name, amount)
    local item = tostring(name)
    local datablock = rust.GetDatablockByName(item)
    if (not datablock) then
        self.Log =  'Bad item name "' .. name .. '"'
        self:LogSave()
        return
    end
    amount = math.ceil(tonumber(amount))
    if (amount < 1) then
        self.Log =  'Bad item amount "' .. amount .. '"'
        self:LogSave()
        return
    end
    local inv = rust.GetInventory(netuser)
    inv:AddItemAmount(datablock, amount)
end

