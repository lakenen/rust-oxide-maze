PLUGIN.Title = 'Maze Plugin'
PLUGIN.Description = 'Plugin that runs the awesome fucking maze'
PLUGIN.Author = 'camupod'
PLUGIN.Version = '0.0.1'

local MazeDefaultConfig = {
    VERSION = '0.0.1',
    yOffset = 0.5,
    items = {}
}
local dateTime = util.GetStaticPropertyGetter(System.DateTime, 'Now')

function PLUGIN:Init()
    print('Maze :: Plugin loading...')

    print('Maze :: Loading data file')
    self:LoadMazeData()

    print('Maze :: Loading config file')
    self:LoadMazeConfig()

    self.LogFile = util.GetDatafile('maze_log')
    local x = self.LogFile:GetText()
    if (x ~= '') then
        self:Log('SERVER RESTARTED.')
    else
        print('Maze :: No log file found. Creating new log file...')
        self:Log('Log created!')
        print('Maze :: Log file created!')
    end

    print('Maze :: Adding commands')
    self:AddChatCommand('maze', self.HandleMazeCommand)

    print('Maze :: Plugin loaded')
end

function PLUGIN:OnKilled(takedamage, damage)
    self:HandlePlayerKilled(takedamage)
end

function PLUGIN:HandlePlayerKilled(takedamage)
    local victim = takedamage:GetComponent('HumanController')
    if (victim) then
        local netplayer = victim.networkViewOwner
        if (netplayer) then
            local netuser = rust.NetUserFromNetPlayer(netplayer)
            if (netuser) then
                if (self:UserIsInMaze(netuser)) then
                    self:Log('User died in maze')
                    rust.Notice(netuser, 'You died! Select "RESPAWN" to respawn in maze or "AT A CAMP" to exit!')
                end
            end
        end
    end
end

function PLUGIN:OnSpawnPlayer(playerclient, usecamp, avatar)
    timer.NextFrame(function () self:HandlePlayerSpawn(playerclient, usecamp) end)
end

function PLUGIN:HandlePlayerSpawn(playerclient, usecamp)
    local netuser = playerclient.netUser
    if (self:UserIsInMaze(netuser)) then
        self:Log('Player in maze has spawned')
        if (usecamp) then
            self:Log('Player selected use camp... removing them from the maze!')
            timer.NextFrame(function () self:RemoveUserFromMaze(netuser, usecamp) end)
            return
        end
        self:Log('Sending player to a spawn location')
        self:SendUserToMaze(netuser)
    end
end

function PLUGIN:OnUserConnect(netuser)
    timer.NextFrame(function() self:HandleUserConnect(netuser) end)
end

function PLUGIN:HandleUserConnect(netuser)
    if (self:UserIsInMaze(netuser)) then
        self:Log('Player is in maze... sending to a spawn location')
        self:SendUserToMaze(netuser)
    end
end

function PLUGIN:HandleMazeCommand(netuser, cmd, args)
    if (args[1]) then
        args[1] = string.lower(args[1])
    end
    if (args[2]) then
        args[2] = string.lower(args[2])
    end

    local canAdmin = netuser:CanAdmin()

    if (not args[1]) then
        self:SendUserToMaze(netuser)
        return
    elseif (args[1] == 'enter') then
        self:SendUserToMaze(netuser)
        return
    elseif (args[1] == 'exit') then
        self:RemoveUserFromMaze(netuser)
        return
    elseif (args[1] == 'add') then
        if (not canAdmin) then
            rust.Notice(netuser, 'Must be admin to do that!')
            return
        end
        self:AddSpawnLocation(netuser, args[2])
        return
    elseif (args[1] == 'list') then
        if (not canAdmin) then
            rust.Notice(netuser, 'Must be admin to do that!')
            return
        end
        self:ListSpawnLocations(netuser)
        return
    elseif (args[1] == 'delete') then
        if (not canAdmin) then
            rust.Notice(netuser, 'Must be admin to do that!')
            return
        end
        self:DeleteSpawnLocation(netuser, args[2])
        return
    elseif (args[1] == 'reload') then
        if (not canAdmin) then
            rust.Notice(netuser, 'Must be admin to do that!')
            return
        end
        self:ReloadConfig(netuser)
        return
    else
        -- todo: show help
        rust.SendChatToUser(netuser, 'unknown command')
    end
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
            print ('Maze :: Config file is corrupted! Loading defaults.')
            self.MazeConfig = {}
            self:LoadDefaultConfig()
            return false
        else
            self.MazeConfig = MazeConfigTmp
            self:LoadDefaultConfig() -- Update any new config values
            return true
        end
    else
        print ('Maze :: Config file is empty, setting defaults!')
        self:LoadDefaultConfig() -- Update any new config values
    end
end

function PLUGIN:ReloadConfig(netuser)
    if (self:LoadMazeConfig()) then
        rust.Notice(netuser, 'Config reloaded!')
    else
        rust.Notice(netuser, 'There was an error reloading config...')
    end
end

function PLUGIN:LoadDefaultConfig()
    if (not self.MazeConfig.VERSION) then
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
end

function PLUGIN:Log(str)
    local templog = self.LogFile:GetText()
    self.LogFile:SetText(tostring(templog) .. '\n' .. tostring(dateTime()) .. ': ' .. tostring(str)) -- !!! Find better solution for this. !!!
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
        if (MazeDataTmp) then
            self.MazeData = MazeDataTmp
            print ('Maze :: Data file loaded.')
            return;
        else
            print ('Maze :: Data file is corrupted!')
            --would be good to check for corruption and load backup file
            -- just fall back to loading defaults...
        end
    end

    print ('Maze :: Data file is empty/corrupted! Setting defaults.')
    self.MazeData = {}
    self.MazeData.meta = {}
    self.MazeData.users = {}
    self.MazeData.spawnLocations = {}

    self:SaveMazeData()
end

function PLUGIN:AddSpawnLocation(netuser, name)
    if (not self.MazeData.spawnLocations) then
        -- first spawn point ?
        self.MazeData.spawnLocations = {}
    end

    if (name == 'all') then
        rust.Notice(netuser, 'That is a reserved name! Please choose another...')
        return
    end

    local coords = netuser.playerClient.lastKnownPosition

    self.MazeData.spawnLocations[name] = {
        x = coords.x,
        y = coords.y,
        z = coords.z
    }
    self:SaveMazeData()
    self:Log('Created maze spawn point "' .. name .. '"')

    rust.Notice(netuser, 'Spawn location set!')
end

function PLUGIN:DeleteSpawnLocation(netuser, name)
    if (not self.MazeData.spawnLocations or not self.MazeData.spawnLocations[name]) then
        if (name == 'all') then
            self.MazeData.spawnLocations = {}
            self:SaveMazeData();
            self:Log('Removed all maze spawn points')
            rust.Notice(netuser, 'All spawn locations removed!')
            return
        end
        rust.Notice(netuser, 'Spawn location not found!')
        return
    end

    self.MazeData.spawnLocations[name] = nil
    self:SaveMazeData()
    self:Log('Removed maze spawn point "' .. name .. '"')

    rust.Notice(netuser, 'Spawn location removed!')
end

function PLUGIN:ListSpawnLocations(netuser, name)
    if (not self.MazeData.spawnLocations) then
        rust.SendChatToUser(netuser, 'no locations set')
        return
    end

    local locations = self.MazeData.spawnLocations
    for name, coords in pairs(locations) do
        rust.SendChatToUser(netuser, name .. ': (' .. coords.x .. ', ' .. coords.y .. ', ' .. coords.z .. ')')
    end
end

function getRandomFromTable(t)
    local keys, count = {}, 1
    for k,_ in pairs(t) do
        keys[count] = k
        count = count + 1
    end

    return t[keys[math.random(count - 1)]]
end

function PLUGIN:SendUserToMaze(netuser)
    local spawnLocations = self.MazeData.spawnLocations
    local playerCoords = netuser.playerClient.lastKnownPosition
    local spawnCoords = getRandomFromTable(spawnLocations)
    local inv = rust.GetInventory(netuser)
    local netuserId = rust.GetUserID(netuser)

    if (not self:UserIsInMaze(netuser)) then
        self:Log('Adding new user to the maze! Saving previous inventory and location...')
        if (not self.MazeData.users) then
            -- first user!
            self.MazeData.users = {}
        end

        -- save user's position and items before entering maze for the first time
        self.MazeData.users[netuserId] = {
            inventory = self:GetAllInventoryItems(inv),
            location = {
                x = playerCoords.x,
                y = playerCoords.y,
                z = playerCoords.z
            }
        }
        self:SaveMazeData();
    end

    playerCoords.x = spawnCoords.x
    playerCoords.y = spawnCoords.y + self.MazeConfig.yOffset
    playerCoords.z = spawnCoords.z

    -- send them in!
    rust.ServerManagement():TeleportPlayer(netuser.playerClient.netPlayer, playerCoords)

    -- clear their inventory, and give them a few things...
    inv:Clear()
    for name, amount in pairs(self.MazeConfig.items) do
        self:GiveItem(inv, name, amount)
    end

    rust.Notice(netuser, 'You are now in the maze. Good luck! Type "/maze exit" to leave.')
end

function PLUGIN:RemoveUserFromMaze(netuser, noteleport)
    if (not self:UserIsInMaze(netuser)) then
        self:Log('Attempted to remove a user that is not in the maze!')
        return
    end

    self:Log('Removing user from the maze! Restoring previous inventory and location...')

    local netuserId = rust.GetUserID(netuser)
    local userData = self.MazeData.users[netuserId]
    local playerCoords = netuser.playerClient.lastKnownPosition
    local inv  = rust.GetInventory(netuser)
    playerCoords.x = userData.location.x
    playerCoords.y = userData.location.y
    playerCoords.z = userData.location.z

    -- clear out their maze items and restore their original items
    -- todo: figure out how to recall item positions in inv
    inv:Clear()
    for name, amount in pairs(userData.inventory) do
        self:GiveItem(inv, name, amount)
    end

    -- remove the user's entry from the MazeData
    self.MazeData.users[netuserId] = nil
    self:SaveMazeData();

    if (not noteleport) then
        rust.ServerManagement():TeleportPlayer(netuser.playerClient.netPlayer, playerCoords)
    end
    rust.Notice(netuser, 'You are now back where you started. Hope you had fun!')
end

function PLUGIN:UserIsInMaze(netuser)
    local netuserId = rust.GetUserID(netuser)
    if self.MazeData.users and self.MazeData.users[netuserId] then
        return true
    end
    return false
end

function PLUGIN:GiveItem(inventory, name, amount)
    self:Log('Giving user ' .. name .. ' x' .. amount)
    local item = tostring(name)
    local datablock = rust.GetDatablockByName(item)
    if (not datablock) then
        self:Log('Bad item name "' .. name .. '"')
        return
    end
    amount = math.ceil(tonumber(amount))
    if (amount < 1) then
        self:Log('Bad item amount "' .. amount .. '"')
        return
    end
    inventory:AddItemAmount(datablock, amount)
end

-- borrowed from invviewer (thanks to CareX)
local unstackable = {"M4", "9mm Pistol", "Shotgun", "P250", "MP5A4", "Pipe Shotgun", "Bolt Action Rifle" , "Revolver", "HandCannon", "Research Kit 1", "Torch" }
function table.containsval(t,cv) for _, v in ipairs(t) do  if v == cv then return true  end  end return nil end -- return true if value is in said table.
function PLUGIN:GetAllInventoryItems(inv)
    local inventory = {}
    local i = 0
    while (i <= 39) do
        local b, item = inv:GetItem(i)
        if (b) then
            local s = tostring(item)
            local x = string.find(s, "%(on", 2) -2
            local itemname = string.sub(s, 2, x)
            local isUnstackable = table.containsval(unstackable, itemname)
            local amount = 1
            if (not isUnstackable) then
                amount = item.uses
            end
            if (inventory[itemname]) then
                inventory[itemname] = inventory[itemname] + amount
            else
                inventory[itemname] = amount
            end
        end
        i = i + 1
    end
    return inventory
end
