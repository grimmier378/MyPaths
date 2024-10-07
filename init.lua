--[[
    Title: My Paths
    Author: Grimmier
    Includes:
    Description: This script is a simple pathing script that allows you to record and navigate paths in the game.
                You can create, save, and edit paths in a zone and load them for navigation.
]]

-- Load Libraries
local mq                = require('mq')
local ImGui             = require('ImGui')
local Module            = {}
Module.Name             = 'MyPaths'
Module.IsRunning        = false
---@diagnostic disable-next-line:undefined-global
local loadedExeternally = MyUI_ScriptName ~= nil and true or false

if not loadedExeternally then
    MyUI_Utils       = require('lib.common')
    MyUI_ThemeLoader = require('lib.theme_loader')
    MyUI_Icons       = require('mq.ICONS')
    MyUI_CharLoaded  = mq.TLO.Me.DisplayName()
    MyUI_Server      = mq.TLO.MacroQuest.Server()
    MyUI_Base64      = require('lib.base64')
    MyUI_PackageMan  = require('mq.PackageMan')
    MyUI_SQLite3     = MyUI_PackageMan.Require('lsqlite3')
end

-- Variables
local script                                                     = 'MyPaths' -- Change this to the name of your script
local themeName                                                  = 'Default'
local themeID                                                    = 1
local theme, defaults, settings, debugMessages                   = {}, {}, {}, {}
local Paths, ChainedPaths                                        = {}, {}
local newPath                                                    = ''
local curTime                                                    = os.time()
local lastTime                                                   = curTime
local deleteWP, deleteWPStep                                     = false, 0
local status, lastStatus                                         = 'Idle', ''
local tmpLoc                                                     = ''
local currZone, lastZone                                         = '', ''
local lastHP, lastMP, intPauseTime, curWpPauseTime               = 0, 0, 0, 0
local lastRecordedWP                                             = ''
local PathStartClock, PathStartTime                              = nil, nil

local NavSet                                                     = {
    ChainPath        = 'Select Path...',
    ChainStart       = false,
    ChainLoop        = false,
    SelectedPath     = 'None',
    ChainZone        = 'Select Zone...',
    LastPath         = nil,
    CurChain         = 0,
    doChainPause     = false,
    autoRecord       = false,
    doNav            = false,
    doSingle         = false,
    doLoop           = false,
    doReverse        = false,
    doPingPong       = false,
    doPause          = false,
    RecordDelay      = 5,
    StopDist         = 30,
    PauseStart       = 0,
    WpPause          = 1,
    CurrentStepIndex = 1,
    LoopCount        = 0,
    RecordMinDist    = 25,
    PreviousDoNav    = false,
    PausedActiveGN   = false,
}

local InterruptSet                                               = {
    interruptsOn    = true,
    interruptFound  = false,
    reported        = false,
    interruptDelay  = 2,
    PauseStart      = 0,
    openDoor        = false,
    stopForAll      = true,
    stopForGM       = true,
    stopForSitting  = true,
    stopForCombat   = true,
    stopForGoupDist = 100,
    stopForDist     = false,
    stopForXtar     = true,
    stopForFear     = true,
    stopForCharm    = true,
    stopForMez      = true,
    stopForRoot     = true,
    stopForLoot     = true,
    stopForInvis    = false,
    stopForDblInvis = false,
    stopForCasting  = true,
    interruptCheck  = 0,
}

-- GUI Settings
local winFlags                                                   = bit32.bor(ImGuiWindowFlags.None, ImGuiWindowFlags.MenuBar)
local DEBUG                                                      = false
local showMainGUI, showConfigGUI, showDebugTab, showHUD, hudLock = true, false, true, false, false
local scale                                                      = 1
local aSize, locked, hasThemeZ                                   = false, false, false
local hudTransparency                                            = 0.5
local mouseOverTransparency                                      = 1.0
local doMouseOver                                                = true

-- File Paths
local themeFile                                                  = string.format('%s/MyUI/MyThemeZ.lua', mq.configDir)
local configFileOld                                              = string.format('%s/MyUI/%s/%s_Configs.lua', mq.configDir, script, script)
local configFile                                                 = string.format('%s/MyUI/%s/%s_Configs.lua', mq.configDir, script, script)
local pathsFile                                                  = string.format('%s/MyUI/%s/%s_Paths.lua', mq.configDir, script, script)
local themezDir                                                  = mq.luaDir .. '/themez/init.lua'
-- SQL information
local PathDB                                                     = string.format('%s/MyUI/%s/%s.db', mq.configDir, script, script)

-- Default Settings
defaults                                                         = {
    Scale                 = 1.0,
    LoadTheme             = 'Default',
    locked                = false,
    HudLock               = false,
    AutoSize              = false,
    stopForGM             = true,
    RecordDlay            = 5,
    WatchMana             = 60,
    WatchType             = 'None',
    InvisAction           = '',
    InvisDelay            = 3,
    WatchHealth           = 90,
    GroupWatch            = false,
    HeadsUpTransparency   = 0.5,
    MouseOverTransparency = 1.0,
    StopDistance          = 30,
    PauseStops            = 1,
    InterruptDelay        = 1,
    RecordMinDist         = 25,
    AutoStand             = false,
}

local manaClass                                                  = {
    'WIZ',
    'MAG',
    'NEC',
    'ENC',
    'DRU',
    'SHM',
    'CLR',
    'BST',
    --'BRD',
    'PAL',
    'RNG',
    'SHD',
}

local function loadTheme()
    -- Check for the Theme File
    if MyUI_Utils.File.Exists(themeFile) then
        theme = dofile(themeFile)
    else
        -- Create the theme file from the defaults
        theme = require('defaults.themes') -- your local themes file incase the user doesn't have one in config folder
        mq.pickle(themeFile, theme)
    end
    -- Load the theme from the settings file
    themeName = settings[script].LoadTheme or 'Default'
    -- Find the theme ID
    if theme and theme.Theme then
        for tID, tData in pairs(theme.Theme) do
            if tData['Name'] == themeName then
                themeID = tID
            end
        end
    end
end

local function DrawTheme(tName)
    local StyleCounter = 0
    local ColorCounter = 0
    for tID, tData in pairs(theme.Theme) do
        if tData.Name == tName then
            for pID, cData in pairs(theme.Theme[tID].Color) do
                ImGui.PushStyleColor(pID, ImVec4(cData.Color[1], cData.Color[2], cData.Color[3], cData.Color[4]))
                ColorCounter = ColorCounter + 1
            end
            if tData['Style'] ~= nil then
                if next(tData['Style']) ~= nil then
                    for sID, sData in pairs(theme.Theme[tID].Style) do
                        if sData.Size ~= nil then
                            ImGui.PushStyleVar(sID, sData.Size)
                            StyleCounter = StyleCounter + 1
                        elseif sData.X ~= nil then
                            ImGui.PushStyleVar(sID, sData.X, sData.Y)
                            StyleCounter = StyleCounter + 1
                        end
                    end
                end
            end
        end
    end
    return ColorCounter, StyleCounter
end

local function SavePaths()
    -- Save paths to the SQLite3 database
    local db = MyUI_SQLite3.open(PathDB)
    if db then
        -- Clear existing entries for fresh insert
        db:exec("DELETE FROM Paths_Table")

        local stmt = db:prepare([[
            INSERT INTO Paths_Table (zone_name, path_name, step_number, step_cmd, step_door, step_door_rev, step_loc, step_delay)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ]])

        for zone, paths in pairs(Paths) do
            for path, waypoints in pairs(paths) do
                for step, data in pairs(waypoints) do
                    stmt:bind_values(
                        zone,
                        path,
                        data.step,
                        data.cmd,
                        data.door and 1 or 0,
                        data.doorRev and 1 or 0,
                        data.loc,
                        data.delay
                    )
                    stmt:step()
                    stmt:reset()
                end
            end
        end

        stmt:finalize()
        db:close()
    else
        MyUI_Utils.PrintOutput('MyUI', nil, "Failed to open the database.")
    end

    -- Optionally, save paths to a Lua file as a backup
    mq.pickle(pathsFile, Paths)
end

local function loadPaths()
    -- Check if the SQLite3 database file exists
    if not MyUI_Utils.File.Exists(PathDB) then
        -- Create the database and its table if it doesn't exist
        MyUI_Utils.PrintOutput('MyUI', nil, "Creating the MyPaths Database")
        local db = MyUI_SQLite3.open(PathDB)
        db:exec [[
            CREATE TABLE IF NOT EXISTS Paths_Table (
                "zone_name" TEXT NOT NULL,
                "path_name" TEXT NOT NULL,
                "step_number" INTEGER NOT NULL,
                "step_cmd" TEXT,
                "step_door" INTEGER NOT NULL DEFAULT 0,
                "step_door_rev" INTEGER NOT NULL DEFAULT 0,
                "step_loc" TEXT NOT NULL,
                "step_delay" INTEGER NOT NULL DEFAULT 0,
                "id" INTEGER PRIMARY KEY AUTOINCREMENT
            );
        ]]
        db:close()
    end

    -- Reset the Paths table
    Paths = {}

    -- Load paths from the SQLite3 database
    local db = MyUI_SQLite3.open(PathDB, MyUI_SQLite3.OPEN_READONLY)
    if db then
        local stmt = db:prepare("SELECT * FROM Paths_Table ORDER BY zone_name, path_name, step_number")
        for row in stmt:nrows() do
            if not Paths[row.zone_name] then
                Paths[row.zone_name] = {}
            end
            if not Paths[row.zone_name][row.path_name] then
                Paths[row.zone_name][row.path_name] = {}
            end
            Paths[row.zone_name][row.path_name][row.step_number] = {
                doorRev = row.step_door_rev == 1,
                step = row.step_number,
                delay = row.step_delay,
                loc = row.step_loc,
                cmd = row.step_cmd,
                door = row.step_door == 1,
            }
        end
        stmt:finalize()
        db:close()
    else
        MyUI_Utils.PrintOutput('MyUI', nil, "Failed to open the database.")
    end

    -- Fallback to load from Lua file if the database is empty
    if next(Paths) == nil and MyUI_Utils.File.Exists(pathsFile) then
        Paths = dofile(pathsFile)
        MyUI_Utils.PrintOutput('MyUI', nil, "Populating MyPaths DB from Lua file! Depending on size, This may take some time...")
        SavePaths() -- Save to the SQLite database after loading from Lua file
    end
end

local function loadSettings()
    local newSetting = false -- Check if we need to save the settings file

    -- Check Settings
    if not MyUI_Utils.File.Exists(configFile) then
        if MyUI_Utils.File.Exists(configFileOld) then
            settings = dofile(configFileOld)
            mq.pickle(configFile, settings)
        else
            -- Create the settings file from the defaults
            settings[script] = defaults
            mq.pickle(configFile, settings)
            loadSettings()
        end
    else
        -- Load settings from the Lua config file
        settings = dofile(configFile)
        -- Check if the settings are missing from the file
        if settings[script] == nil then
            settings[script] = {}
            settings[script] = defaults
            newSetting = true
        end
    end

    -- Check if the settings are missing and use defaults if they are
    newSetting = MyUI_Utils.CheckDefaultSettings(defaults, settings[script])
    newSetting = MyUI_Utils.CheckDefaultSettings(InterruptSet, settings[script].Interrupts) or newSetting

    -- Load the theme
    loadTheme()
    hudLock = settings[script].HudLock
    InterruptSet = settings[script].Interrupts
    -- Set the settings to the variables
    NavSet.StopDist = settings[script].StopDistance
    NavSet.WpPause = settings[script].PauseStops
    NavSet.RecordMinDist = settings[script].RecordMinDist
    InterruptSet.stopForGM = settings[script].stopForGM
    InterruptSet.stopForDist = settings[script].Interrupts.stopForDist
    InterruptSet.interruptDelay = settings[script].InterruptDelay
    hudTransparency = settings[script].HeadsUpTransparency
    mouseOverTransparency = settings[script].MouseOverTransparency
    aSize = settings[script].AutoSize
    doMouseOver = settings[script].MouseHUD
    locked = settings[script].locked
    scale = settings[script].Scale
    themeName = settings[script].LoadTheme
    NavSet.RecordDelay = settings[script].RecordDelay


    -- Save the settings if new settings were added
    if newSetting then mq.pickle(configFile, settings) end
end

-------- Path Functions --------

local function RecordWaypoint(name)
    local zone = mq.TLO.Zone.ShortName()
    if not Paths[zone] then Paths[zone] = {} end
    if not Paths[zone][name] then Paths[zone][name] = {} end
    local tmp = Paths[zone][name]
    local loc = mq.TLO.Me.LocYXZ()
    local index = #tmp or 1
    local distToLast = 0
    if lastRecordedWP ~= loc and lastRecordedWP ~= '' then
        local tmpLastWP = lastRecordedWP
        local yx = tmpLastWP:match("^(.-,.-),") -- Match the y,x part of the string
        tmpLastWP = tmpLastWP:sub(1, #yx - 1)
        distToLast = mq.TLO.Math.Distance(tmpLastWP)()
        if distToLast < NavSet.RecordMinDist and NavSet.autoRecord then
            status = "Recording: Distance to Last WP is less than " .. NavSet.RecordMinDist .. "!"
            if DEBUG and not InterruptSet.reported then
                table.insert(debugMessages,
                    { Time = os.date("%H:%M:%S"), Zone = zone, Path = name, WP = 'Record WP', Status = 'Distance to Last WP is less than ' .. NavSet.RecordMinDist .. ' units!', })
                InterruptSet.reported = true
            end
            return
        end
    end
    if tmp[index] ~= nil then
        if tmp[index].loc == loc then return end
        table.insert(tmp, { step = index + 1, loc = loc, delay = 0, cmd = '', })
        lastRecordedWP = loc
        index = index + 1
        InterruptSet.reported = false
    else
        table.insert(tmp, { step = 1, loc = loc, delay = 0, cmd = '', })
        index = 1
        lastRecordedWP = loc
        InterruptSet.reported = false
    end
    Paths[zone][name] = tmp

    -- Update the database directly
    local db = MyUI_SQLite3.open(PathDB)
    local stmt = db:prepare([[
        INSERT INTO Paths_Table (zone_name, path_name, step_number, step_cmd, step_door, step_door_rev, step_loc, step_delay)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ]])
    stmt:bind_values(zone, name, index, '', 0, 0, loc, 0)
    stmt:step()
    stmt:finalize()
    db:close()
    mq.pickle(pathsFile, Paths)
    if NavSet.autoRecord then
        status = "Recording: Waypoint #" .. index .. " Added!"
    end
    if DEBUG then
        table.insert(debugMessages, {
            Time = os.date("%H:%M:%S"),
            Zone = zone,
            Path = name,
            WP = "Add WP#" .. index,
            Status = 'Waypoint #' .. index ..
                ' Added Successfully!',
        })
    end
end

local function RemoveWaypoint(name, step)
    local zone = mq.TLO.Zone.ShortName()
    if not Paths[zone] then return end
    if not Paths[zone][name] then return end
    local tmp = Paths[zone][name]
    if not tmp then return end

    -- Remove the specified waypoint from the in-memory table
    for i, data in pairs(tmp) do
        if data.step == step then
            table.remove(tmp, i)
            -- Also remove it from the database
            local db = MyUI_SQLite3.open(PathDB)
            local stmt = db:prepare("DELETE FROM Paths_Table WHERE zone_name = ? AND path_name = ? AND step_number = ?")
            stmt:bind_values(zone, name, step)
            stmt:step()
            stmt:finalize()
            db:close()
            break
        end
    end

    -- Reindex the remaining waypoints
    for i, data in pairs(tmp) do
        data.step = i
        -- Update the step number in the database
        local db = MyUI_SQLite3.open(PathDB)
        local stmt = db:prepare("UPDATE Paths_Table SET step_number = ? WHERE zone_name = ? AND path_name = ? AND step_loc = ?")
        stmt:bind_values(i, zone, name, data.loc)
        stmt:step()
        stmt:finalize()
        db:close()
    end

    -- Update the in-memory Paths table
    Paths[zone][name] = tmp
    mq.pickle(pathsFile, Paths)
end

local function ClearWaypoints(name)
    local zone = mq.TLO.Zone.ShortName()
    if not Paths[zone] then return end
    if not Paths[zone][name] then return end
    Paths[zone][name] = {}

    -- Remove all waypoints from the database for this path
    local db = MyUI_SQLite3.open(PathDB)
    local stmt = db:prepare("DELETE FROM Paths_Table WHERE zone_name = ? AND path_name = ?")
    stmt:bind_values(zone, name)
    stmt:step()
    stmt:finalize()
    db:close()
    mq.pickle(pathsFile, Paths)
    if DEBUG then table.insert(debugMessages, { Time = os.date("%H:%M:%S"), Zone = zone, Path = name, WP = 'All Waypoints', Status = 'All Waypoints Cleared Successfully!', }) end
end

local function DeletePath(name)
    local zone = mq.TLO.Zone.ShortName()
    if not Paths[zone] then return end
    if not Paths[zone][name] then return end
    Paths[zone][name] = nil

    -- Remove the entire path from the database
    local db = MyUI_SQLite3.open(PathDB)
    local stmt = db:prepare("DELETE FROM Paths_Table WHERE zone_name = ? AND path_name = ?")
    stmt:bind_values(zone, name)
    stmt:step()
    stmt:finalize()
    db:close()
    mq.pickle(pathsFile, Paths)
    if DEBUG then table.insert(debugMessages, { Time = os.date("%H:%M:%S"), Zone = zone, Path = name, WP = 'Path Deleted', Status = 'Path [' .. name .. '] Deleted Successfully!', }) end
end

local function CreatePath(name)
    local zone = mq.TLO.Zone.ShortName()
    if not Paths[zone] then Paths[zone] = {} end
    if not Paths[zone][name] then Paths[zone][name] = {} end

    -- No need to update the database until waypoints are added
    mq.pickle(pathsFile, Paths)
    if DEBUG then table.insert(debugMessages, { Time = os.date("%H:%M:%S"), Zone = zone, Path = name, WP = 'Path Created', Status = 'Path [' .. name .. '] Created Successfully!', }) end
end

local function AutoRecordPath(name)
    curTime = os.time()
    if curTime - lastTime > NavSet.RecordDelay then
        RecordWaypoint(name)
        lastTime = curTime
    end
end

local function UpdatePath(zone, pathName)
    if not Paths[zone] or not Paths[zone][pathName] then
        MyUI_Utils.PrintOutput('MyUI', nil, "Path %s in zone %s does not exist.", pathName, zone)
        return
    end

    -- Open the SQLite database
    local db = MyUI_SQLite3.open(PathDB)
    if not db then
        MyUI_Utils.PrintOutput('MyUI', nil, "Failed to open the database.")
        return
    end

    -- Delete the existing path in the database
    local deleteStmt = db:prepare("DELETE FROM Paths_Table WHERE zone_name = ? AND path_name = ?")
    deleteStmt:bind_values(zone, pathName)
    deleteStmt:step()
    deleteStmt:finalize()

    -- Re-add the updated path
    for _, waypoint in pairs(Paths[zone][pathName]) do
        local insertStmt = db:prepare([[
            INSERT INTO Paths_Table (zone_name, path_name, step_number, step_cmd, step_door, step_door_rev, step_loc, step_delay)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ]])
        insertStmt:bind_values(
            zone,
            pathName,
            waypoint.step,
            waypoint.cmd,
            waypoint.door and 1 or 0,
            waypoint.doorRev and 1 or 0,
            waypoint.loc,
            waypoint.delay
        )
        insertStmt:step()
        insertStmt:finalize()
    end

    -- Close the database connection
    db:close()
    mq.pickle(pathsFile, Paths)
end

local function groupDistance()
    local member = mq.TLO.Group.Member
    local gsize = mq.TLO.Me.GroupSize() or 0
    if gsize == 0 then return false end
    for i = 1, gsize - 1 do
        if member(i).Present() then
            if member(i).Distance() > InterruptSet.stopForGoupDist then
                status = string.format('Paused for Group Distance. %s is %.2f units away.', member(i).Name(), member(i).Distance())
                return true
            end
        else
            status = string.format('Paused for Group Distance. %s is not in Zone!', member(i).Name())
            return true
        end
    end
    return false
end

local function groupWatch(type)
    if type == 'None' then return false end
    local myClass = mq.TLO.Me.Class.ShortName()
    if type == "Self" then
        if mq.TLO.Me.PctHPs() < settings[script].WatchHealth then
            mq.TLO.Me.Sit()
            return true
        end
        for x = 1, #manaClass do
            if manaClass[x] == myClass and mq.TLO.Me.PctMana() < settings[script].WatchMana then
                mq.TLO.Me.Sit()
                status = string.format('Paused for Mana Watch.')
                return true
            end
        end
    elseif mq.TLO.Me.GroupSize() > 0 then
        local member = mq.TLO.Group.Member
        local gsize = mq.TLO.Me.GroupSize() or 0

        if type == 'Healer' then
            for i = 1, gsize - 1 do
                if member(i).Present() then
                    local class = member(i).Class.ShortName()

                    if class == 'CLR' or class == 'DRU' or class == 'SHM' then
                        if member(i).PctHPs() < settings[script].WatchHealth then
                            status = string.format('Paused for Healer Health.')
                            return true
                        end
                        if member(i).PctMana() < settings[script].WatchMana then
                            status = string.format('Paused for Healer Mana.')
                            return true
                        end
                    end
                end
            end
            if myClass == 'CLR' or myClass == 'DRU' or myClass == 'SHM' then
                if mq.TLO.Me.PctHPs() < settings[script].WatchHealth then
                    status = string.format('Paused for Health Watch.')
                    mq.TLO.Me.Sit()
                    return true
                end
                if manaClass[myClass] and mq.TLO.Me.PctMana() < settings[script].WatchMana then
                    mq.TLO.Me.Sit()
                    status = string.format('Paused for Mana Watch.')
                    return true
                end
            end
        end
        if type == 'All' then
            for i = 1, gsize - 1 do
                if member(i).Present() then
                    if member(i).PctHPs() < settings[script].WatchHealth then
                        status = string.format('Paused for Health Watch.')
                        return true
                    end
                    for x = 1, #manaClass do
                        if member(i).Class.ShortName() == manaClass[x] then
                            if member(i).PctMana() < settings[script].WatchMana then
                                status = string.format('Paused for Mana Watch.')
                                return true
                            end
                        end
                    end
                else
                    status = string.format('Paused for Group Member %s not Present.', member(i).CleanName())
                    return true
                end
                if mq.TLO.Me.PctHPs() < settings[script].WatchHealth then
                    status = string.format('Paused for Health Watch.')
                    mq.TLO.Me.Sit()
                    return true
                end
                for x = 1, #manaClass do
                    if manaClass[x] == myClass and mq.TLO.Me.PctMana() < settings[script].WatchMana then
                        mq.TLO.Me.Sit()
                        status = string.format('Paused for Mana Watch.')
                        return true
                    end
                end
            end
        end
        mq.delay(1)
    end
    return false
end
local interruptInProgress = false
local function CheckInterrupts()
    if not InterruptSet.interruptsOn then return false end
    if not NavSet.doNav then return false end
    local xCount = mq.TLO.Me.XTarget() or 0
    local flag = false
    local invis = false
    if mq.TLO.Me.Sitting() and InterruptSet.stopForSitting then
        local curHP, curMP = mq.TLO.Me.PctHPs(), mq.TLO.Me.PctMana() or 0
        mq.delay(10)
        if not interruptInProgress then
            mq.cmdf("/nav stop log=off")
            interruptInProgress = true
            status = string.format('Paused for Sitting. HP %s MP %s', curHP, curMP)
        end
        if curHP - lastHP > 5 or curMP - lastMP > 5 then
            status = string.format('Paused for Sitting. HP %s MP %s', curHP, curMP)
            lastHP, lastMP = curHP, curMP
        end

        flag = true

        if curHP >= 99 and curMP >= 99 and settings[script].AutoStand then
            mq.TLO.Me.Stand()
            status = 'Idle'
            flag = false
        end
    elseif mq.TLO.Window('LootWnd').Open() and InterruptSet.stopForLoot then
        if not interruptInProgress then
            mq.cmdf("/nav stop log=off")
            interruptInProgress = true
        end
        status = 'Paused for Looting.'
        flag = true
    elseif mq.TLO.Window('AdvancedLootWnd').Open() and InterruptSet.stopForLoot then
        if not interruptInProgress then
            mq.cmdf("/nav stop log=off")
            interruptInProgress = true
        end
        status = 'Paused for Looting.'
        flag = true
    elseif mq.TLO.Me.Combat() and InterruptSet.stopForCombat then
        if not interruptInProgress then
            mq.cmdf("/nav stop log=off")
            interruptInProgress = true
        end
        status = 'Paused for Combat.'
        flag = true
    elseif xCount > 0 and InterruptSet.stopForXtar then
        for i = 1, mq.TLO.Me.XTargetSlots() do
            if mq.TLO.Me.XTarget(i) ~= nil then
                if (mq.TLO.Me.XTarget(i).ID() ~= 0 and mq.TLO.Me.XTarget(i).Type() ~= 'PC' and mq.TLO.Me.XTarget(i).Master.Type() ~= "PC") then
                    if not interruptInProgress then
                        mq.cmdf("/nav stop log=off")
                        interruptInProgress = true
                    end
                    status = string.format('Paused for XTarget. XTarg Count %s', mq.TLO.Me.XTarget())
                    flag = true
                end
            end
        end
    elseif mq.TLO.Me.Rooted() and InterruptSet.stopForRoot then
        if not interruptInProgress then
            mq.cmdf("/nav stop log=off")
            interruptInProgress = true
        end
        status = 'Paused for Rooted.'
        flag = true
        ---@diagnostic disable-next-line: undefined-field
    elseif mq.TLO.Me.Feared() and InterruptSet.stopForFear then
        if not interruptInProgress then
            mq.cmdf("/nav stop log=off")
            interruptInProgress = true
        end
        status = 'Paused for Feared.'
        flag = true
    elseif mq.TLO.Me.Mezzed() and InterruptSet.stopForMez then
        if not interruptInProgress then
            mq.cmdf("/nav stop log=off")
            interruptInProgress = true
        end
        status = 'Paused for Mezzed.'
        flag = true
    elseif mq.TLO.Me.Charmed() and InterruptSet.stopForCharm then
        if not interruptInProgress then
            mq.cmdf("/nav stop log=off")
            interruptInProgress = true
        end
        status = 'Paused for Charmed.'
        flag = true
    elseif mq.TLO.Me.Casting() ~= nil and mq.TLO.Me.Class.ShortName() ~= 'BRD' and InterruptSet.stopForCasting then
        if not interruptInProgress then
            mq.cmdf("/nav stop log=off")
            interruptInProgress = true
        end
        status = 'Paused for Casting.'
        flag = true
    elseif not mq.TLO.Me.Invis() and InterruptSet.stopForInvis then
        if not interruptInProgress then
            mq.cmdf("/nav stop log=off")
            interruptInProgress = true
            status = 'Paused for Invis.'
        end

        flag = true
        invis = true
    elseif not (mq.TLO.Me.Invis(1)() and mq.TLO.Me.Invis(2)()) and InterruptSet.stopForDblInvis then
        if not interruptInProgress then
            mq.cmdf("/nav stop log=off")
            interruptInProgress = true
            status = 'Paused for Double Invis.'
        end

        flag = true
        invis = true
        -- elseif currZone ~= lastZone then
        --     if not interruptInProgress then mq.cmdf("/nav stop log=off") interruptInProgress = true end
        --     status = 'Paused for Zoning.'
        --     lastZone = ''
        --     flag = true
    elseif settings[script].GroupWatch == true and groupWatch(settings[script].WatchType) then
        flag = true
        if flag and not interruptInProgress then
            mq.cmdf("/nav stop log=off")
            interruptInProgress = true
        end
    elseif InterruptSet.stopForDist == true and groupDistance() then
        flag = true
        if flag and not interruptInProgress then
            mq.cmdf("/nav stop log=off")
            interruptInProgress = true
        end
    end
    if flag then
        InterruptSet.PauseStart = os.time()
        intPauseTime = InterruptSet.interruptDelay
        if invis then intPauseTime = settings[script].InvisDelay end
    else
        interruptInProgress = false
        intPauseTime = 0
    end

    return flag
end

--------- Navigation Functions --------
local doorTime = 0
local function ToggleSwitches()
    if doorTime == 0 then
        mq.cmdf("/squelch /multiline ; /doortarget; /timed 15, /click left door; /timed 25, /doortarget clear")
        doorTime = mq.gettime()
    end
    if mq.gettime() - doorTime >= 750 then
        InterruptSet.openDoor = not InterruptSet.openDoor
        doorTime = 0
    end
end

local function FindIndexClosestWaypoint(table)
    local tmp = table
    local closest = 999999
    local closestLoc = 1
    if tmp == nil then return closestLoc end
    for i = 1, #tmp do
        local tmpClosest = tmp[i].loc
        local yx = tmpClosest:match("^(.-,.-),") -- Match the y,x part of the string
        tmpClosest = tmpClosest:sub(1, #yx - 1)

        local dist = mq.TLO.Math.Distance(tmpClosest)()
        if dist < closest then
            closest = dist
            closestLoc = i
        end
    end
    return closestLoc
end

local function sortPathsTable(zone, path)
    if not Paths[zone] then return end
    if not Paths[zone][path] then return end
    local tmp = {}
    for i, data in pairs(Paths[zone][path]) do
        table.insert(tmp, data)
    end

    if NavSet.doReverse then
        table.sort(tmp, function(a, b) return a.step > b.step end)
    else
        table.sort(tmp, function(a, b) return a.step < b.step end)
    end
    return tmp
end

local function NavigatePath(name)
    if not NavSet.doNav then
        return
    end
    local zone = mq.TLO.Zone.ShortName()
    local startNum = 1
    if NavSet.CurrentStepIndex ~= 1 then
        startNum = NavSet.CurrentStepIndex
    end
    if NavSet.doSingle then NavSet.doNav = true end
    if NavSet.doLoop then
        table.insert(debugMessages, { Time = os.date("%H:%M:%S"), Zone = zone, Path = name, WP = 'Loop Started', Status = 'Loop Started!', })
    end
    if #ChainedPaths > 0 and not NavSet.ChainStart then
        NavSet.ChainPath = NavSet.SelectedPath
        NavSet.ChainStart = true
    end
    while NavSet.doNav do
        local tmp = sortPathsTable(zone, name)
        if tmp == nil then
            NavSet.doNav = false
            status = 'Idle'
            return
        end
        for i = startNum, #tmp do
            if NavSet.doSingle then i = NavSet.CurrentStepIndex end
            NavSet.CurrentStepIndex = i
            if not NavSet.doNav then
                return
            end
            local tmpDestLoc = tmp[i].loc
            local yx = tmpDestLoc:match("^(.-,.-),") -- Match the y,x part of the string
            tmpDestLoc = tmpDestLoc:sub(1, #yx - 1)

            local tmpDist = mq.TLO.Math.Distance(tmpDestLoc)() or 0
            mq.cmdf("/nav locyxz %s dist=%s log=off", tmp[i].loc, NavSet.StopDist)
            status = "Nav to WP #: " .. tmp[i].step .. " Distance: " .. string.format("%.2f", tmpDist)
            mq.delay(1)
            -- mq.delay(3000, function () return mq.TLO.Me.Speed() > 0 end)
            -- coroutine.yield()  -- Yield here to allow updates
            while mq.TLO.Math.Distance(tmpDestLoc)() > NavSet.StopDist do
                if not NavSet.doNav then
                    return
                end
                if currZone ~= lastZone then
                    NavSet.SelectedPath = 'None'
                    NavSet.doNav = false
                    intPauseTime = 0
                    InterruptSet.PauseStart = 0

                    return
                end
                if interruptInProgress then
                    coroutine.yield()
                    if not NavSet.doNav then return end
                elseif mq.TLO.Me.Speed() == 0 then
                    mq.delay(1)
                    if not mq.TLO.Me.Sitting() then
                        tmpDestLoc = tmp[i].loc
                        yx = tmpDestLoc:match("^(.-,.-),") -- Match the y,x part of the string
                        tmpDestLoc = tmpDestLoc:sub(1, #yx - 1)
                        mq.cmdf("/nav locyxz %s dist=%s log=off", tmp[i].loc, NavSet.StopDist)
                        tmpDist = mq.TLO.Math.Distance(tmpDestLoc)() or 0
                        status = "Nav to WP #: " .. tmp[i].step .. " Distance: " .. string.format("%.2f", tmpDist)
                        coroutine.yield()
                        if not NavSet.doNav then return end
                    end
                end
                mq.delay(1)
                tmpDestLoc = tmp[i].loc
                yx = tmpDestLoc:match("^(.-,.-),") -- Match the y,x part of the string
                tmpDestLoc = tmpDestLoc:sub(1, #yx - 1)
                tmpDist = mq.TLO.Math.Distance(tmpDestLoc)() or 0
                coroutine.yield() -- Yield here to allow updates
                if not NavSet.doNav then return end
            end
            -- mq.cmdf("/nav stop log=off")
            -- status = "Arrived at WP #: "..tmp[i].step

            if NavSet.doSingle then
                NavSet.doNav = false
                NavSet.doSingle = false
                status = 'Idle - Arrived at Destination!'
                NavSet.LoopCount = 0
                return
            end
            -- Check for Commands to execute at Waypoint
            if tmp[i].cmd ~= '' then
                table.insert(debugMessages, { Time = os.date("%H:%M:%S"), Zone = zone, Path = name, WP = 'Command', Status = 'Executing Command: ' .. tmp[i].cmd, })
                if tmp[i].cmd:find("/mypaths stop") then NavSet.doNav = false end
                mq.delay(1)
                mq.cmdf(tmp[i].cmd)
                mq.delay(1)
                coroutine.yield()
                if not NavSet.doNav then return end
            end
            -- Door Check
            if tmp[i].door and not NavSet.doReverse then
                InterruptSet.openDoor = true
                ToggleSwitches()
            elseif tmp[i].doorRev and NavSet.doReverse then
                InterruptSet.openDoor = true
                ToggleSwitches()
            end
            -- Check for Delay at Waypoint
            if tmp[i].delay > 0 then
                status = string.format("Paused %s seconds at WP #: %s", tmp[i].delay, tmp[i].step)
                curWpPauseTime = tmp[i].delay
                NavSet.PauseStart = os.time()
                coroutine.yield()
                if not NavSet.doNav then return end
                -- coroutine.yield()  -- Yield here to allow updates
            elseif NavSet.WpPause > 0 then
                status = string.format("Global Paused %s seconds at WP #: %s", NavSet.WpPause, tmp[i].step)
                curWpPauseTime = NavSet.WpPause
                NavSet.PauseStart = os.time()
                coroutine.yield()
                if not NavSet.doNav then return end
                -- coroutine.yield()  -- Yield here to allow updates
            else
                if not InterruptSet.interruptFound and tmp[i].delay == 0 then
                    curWpPauseTime = 0
                    NavSet.PauseStart = os.time()
                    if not NavSet.doNav then return end
                end
            end
        end
        -- Check if we need to loop
        if not NavSet.doLoop then
            NavSet.doNav = false
            status = 'Idle - Arrived at Destination!'
            NavSet.LoopCount = 0

            break
        else
            NavSet.LoopCount = NavSet.LoopCount + 1
            table.insert(debugMessages, {
                Time = os.date("%H:%M:%S"),
                Zone = zone,
                Path = name,
                WP = 'Loop #' .. NavSet.LoopCount,
                Status = 'Loop #' ..
                    NavSet.LoopCount .. ' Completed!',
            })
            NavSet.CurrentStepIndex = 1
            startNum = 1
            if NavSet.doPingPong then
                NavSet.doReverse = not NavSet.doReverse
            end
        end
    end
end

local co = coroutine.create(NavigatePath)

-------- Import and Export Functions --------
local function serialize_table(val, name, skipnewlines, depth)
    skipnewlines = skipnewlines or false
    depth = depth or 0

    local tmp = string.rep(" ", depth)

    if name then
        if type(name) ~= 'number' then
            tmp = tmp .. '["' .. name .. '"] = '
        else
            tmp = tmp .. '[' .. name .. '] = '
        end
    end

    if type(val) == "table" then
        tmp = tmp .. "{" .. (not skipnewlines and "\n" or "")

        for k, v in pairs(val) do
            tmp = tmp .. serialize_table(v, k, skipnewlines, depth + 1) .. "," .. (not skipnewlines and "\n" or "")
        end

        tmp = tmp .. string.rep(" ", depth) .. "}"
    elseif type(val) == "number" then
        tmp = tmp .. tostring(val)
    elseif type(val) == "string" then
        tmp = tmp .. string.format("%q", val)
    elseif type(val) == "boolean" then
        tmp = tmp .. (val and "true" or "false")
    else
        tmp = tmp .. "\"[inserializeable datatype:" .. type(val) .. "]\""
    end

    return tmp
end

local function export_paths(zone, pathname, paths)
    local serialized_paths = serialize_table({ [zone] = { [pathname] = paths, }, })
    return MyUI_Base64.enc('return ' .. serialized_paths)
end

local function import_paths(import_string)
    if not import_string or import_string == '' then return end
    local decoded = MyUI_Base64.dec(import_string)
    if not decoded or decoded == '' then return end
    local ok, imported_paths = pcall(load(decoded))
    if not ok or type(imported_paths) ~= 'table' then
        MyUI_Utils.PrintOutput('MyUI', nil, '\arERROR: Failed to import paths\ax')
        return
    end

    local db = MyUI_SQLite3.open(PathDB)
    if not db then
        MyUI_Utils.PrintOutput('MyUI', nil, '\arERROR: Failed to open database\ax')
        return
    end

    for zone, paths in pairs(imported_paths) do
        if not Paths[zone] then
            Paths[zone] = paths
        else
            for pathName, pathData in pairs(paths) do
                Paths[zone][pathName] = pathData
            end
        end

        for pathName, pathData in pairs(paths) do
            for _, waypoint in pairs(pathData) do
                local stmt = db:prepare([[
                    INSERT INTO Paths_Table (zone_name, path_name, step_number, step_cmd, step_door, step_door_rev, step_loc, step_delay)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                ]])
                stmt:bind_values(zone, pathName, waypoint.step, waypoint.cmd, waypoint.door and 1 or 0, waypoint.doorRev and 1 or 0, waypoint.loc, waypoint.delay)
                stmt:step()
                stmt:finalize()
            end
        end
    end

    db:close()
    return imported_paths
end

-------- GUI Functions --------
local mousedOverFlag = false
local importString = ''
local tmpCmd = ''
local exportZone, exportPathName = 'Select Zone...', 'Select Path...'

local function DrawStatus()
    ImGui.BeginGroup()
    -- Set Window Font Scale
    ImGui.SetWindowFontScale(scale)
    if showHUD and ImGui.IsWindowHovered() then
        mousedOverFlag = true
        if ImGui.IsMouseDoubleClicked(0) then
            showMainGUI = not showMainGUI
        end
        ImGui.SetTooltip("Double Click to Toggle Main GUI")
    else
        mousedOverFlag = false
    end
    if NavSet.PausedActiveGN then
        if mq.TLO.SpawnCount('gm')() > 0 then
            ImGui.TextColored(1, 0, 0, 1, "!!%s GM in Zone %s!!", MyUI_Icons.FA_BELL, MyUI_Icons.FA_BELL)
        end
    end
    ImGui.Text("Current Zone: ")
    ImGui.SameLine()
    ImGui.TextColored(0, 1, 0, 1, "%s", currZone)
    ImGui.SameLine()
    ImGui.Text("Selected Path: ")
    ImGui.SameLine()
    ImGui.TextColored(0, 1, 1, 1, "%s", NavSet.SelectedPath)
    ImGui.Text("Current Loc: ")
    ImGui.SameLine()
    ImGui.TextColored(1, 1, 0, 1, "%s", mq.TLO.Me.LocYXZ())
    -- if NavSet.doNav then
    --     local tmpTable = sortPathsTable(currZone, NavSet.SelectedPath) or {}
    --     if tmpTable[NavSet.CurrentStepIndex] then
    --         ImGui.Text("Current WP: ")
    --         ImGui.SameLine()
    --         ImGui.TextColored(1,1,0,1,"%s ",tmpTable[NavSet.CurrentStepIndex].step or 0)
    --         ImGui.SameLine()
    --         ImGui.Text("Distance: ")
    --         ImGui.SameLine()
    --         ImGui.TextColored(0,1,1,1,"%.2f", mq.TLO.Math.Distance(tmpLoc)())
    --         local tmpDist = mq.TLO.Math.Distance(tmpLoc)() or 0
    --         local dist = string.format("%.2f",tmpDist)
    --         local tmpStatus = status
    --         if tmpStatus:find("Distance") then
    --             tmpStatus = tmpStatus:sub(1, tmpStatus:find("Distance:") - 1)
    --             tmpStatus = string.format("%s Distance: %s",tmpStatus,dist)
    --             ImGui.TextColored(ImVec4(0,1,1,1), tmpStatus)
    --         end
    --     end
    -- end

    ImGui.Text("Nav Type: ")
    ImGui.SameLine()
    if not NavSet.doNav then
        ImGui.TextColored(ImVec4(0, 1, 0, 1), "None")
    else
        if NavSet.doPingPong then
            ImGui.TextColored(ImVec4(0, 1, 0, 1), "Ping Pong")
        elseif NavSet.doLoop then
            ImGui.TextColored(ImVec4(0, 1, 0, 1), "Loop ")
            ImGui.SameLine()
            ImGui.TextColored(ImVec4(0, 1, 1, 1), "(%s)", NavSet.LoopCount)
        elseif NavSet.doSingle then
            ImGui.TextColored(ImVec4(0, 1, 0, 1), "Single")
        else
            ImGui.TextColored(ImVec4(0, 1, 0, 1), "Normal")
        end
        ImGui.SameLine()
        ImGui.Text("Reverse: ")
        ImGui.SameLine()
        if NavSet.doReverse then
            ImGui.TextColored(ImVec4(0, 1, 0, 1), "Yes")
        else
            ImGui.TextColored(ImVec4(0, 1, 0, 1), "No")
        end
    end
    local tmpStatus = status
    if tmpStatus:find("Distance:") then
        tmpStatus = tmpStatus:sub(1, tmpStatus:find("Distance:") - 1)
    end
    if status:find("Idle") then
        ImGui.Text("Status: ")
        ImGui.SameLine()
        ImGui.TextColored(ImVec4(0, 1, 1, 1), status)
    elseif status:find("Paused") then
        ImGui.Text("Status: ")
        ImGui.SameLine()
        if status:find("Mana") then
            ImGui.TextColored(ImVec4(0.000, 0.438, 0.825, 1.000), status)
        elseif status:find("Health") then
            ImGui.TextColored(ImVec4(0.928, 0.352, 0.035, 1.000), status)
        else
            ImGui.TextColored(ImVec4(0.9, 0.4, 0.4, 1), status)
        end
    elseif status:find("Arrived") then
        ImGui.Text("Status: ")
        ImGui.SameLine()
        ImGui.TextColored(ImVec4(0, 1, 0, 1), status)
    elseif status:find("Last WP is less than") then
        ImGui.TextColored(ImVec4(0.9, 0.4, 0.4, 1), status)
    elseif status:find("Recording") then
        ImGui.TextColored(ImVec4(0.4, 0.9, 0.4, 1), status)
    elseif status:find("Nav to WP") then
        ImGui.Text("Status: ")
        ImGui.SameLine()
        ImGui.TextColored(ImVec4(1, 1, 0, 1), tmpStatus)
    else
        ImGui.Text("Status: ")
        ImGui.SameLine()
        ImGui.TextColored(ImVec4(1, 1, 1, 1), status)
    end
    if PathStartClock ~= nil then
        ImGui.Text("Start Time: ")
        ImGui.SameLine()
        ImGui.TextColored(0, 1, 1, 1, "%s", PathStartClock)
        ImGui.SameLine()
        ImGui.Text("Elapsed : ")
        ImGui.SameLine()
        local timeDiff = os.time() - PathStartTime
        local hours = math.floor(timeDiff / 3600)
        local minutes = math.floor((timeDiff % 3600) / 60)
        local seconds = timeDiff % 60

        ImGui.TextColored(0, 1, 0, 1, string.format("%02d:%02d:%02d", hours, minutes, seconds))
    end
    ImGui.EndGroup()
end

local sFlag = false

function Module.RenderGUI()
    -- Main Window
    if showMainGUI then
        if currZone ~= lastZone then return end
        -- local currZone = mq.TLO.Zone.ShortName()
        -- Set Window Name
        local winName = string.format('%s##Main_%s', script, MyUI_CharLoaded)
        -- Load Theme
        local ColorCount, StyleCount = DrawTheme(themeName)
        -- Create Main Window
        local openMain, showMain = ImGui.Begin(winName, true, winFlags)
        -- Check if the window is open
        if not openMain then
            showMainGUI = false
            showMain = false
        end
        -- Check if the window is showing
        if showMain then
            local tmpTable = sortPathsTable(currZone, NavSet.SelectedPath) or {}
            local closestWaypointIndex = FindIndexClosestWaypoint(tmpTable)
            local curWPTxt = 1
            tmpLoc = ''
            local xy = 0
            if tmpTable[NavSet.CurrentStepIndex] ~= nil then
                curWPTxt = tmpTable[NavSet.CurrentStepIndex].step or 0
                tmpLoc = tmpTable[NavSet.CurrentStepIndex].loc or ''
                xy = tmpLoc:match("^(.-,.-),") -- Match the y,x part of the string
                tmpLoc = tmpLoc:sub(1, #xy - 1)
            end

            if ImGui.BeginMenuBar() then
                if ImGui.MenuItem(MyUI_Icons.FA_COG) then
                    -- Toggle Config Window
                    showConfigGUI = not showConfigGUI
                end
                if ImGui.IsItemHovered() then
                    ImGui.SetTooltip("Settings")
                end
                ImGui.SameLine()
                local lIcon = locked and MyUI_Icons.FA_LOCK or MyUI_Icons.FA_UNLOCK

                if ImGui.MenuItem(lIcon) then
                    -- Toggle Config Window
                    locked = not locked
                    settings[script].locked = locked
                    mq.pickle(configFile, settings)
                end
                if ImGui.IsItemHovered() then
                    ImGui.SetTooltip("Toggle Lock Window")
                end
                ImGui.SameLine()

                if ImGui.MenuItem(MyUI_Icons.FA_BUG) then
                    if not DEBUG then DEBUG = true end
                    showDebugTab = not showDebugTab
                end
                if ImGui.IsItemHovered() then
                    ImGui.SetTooltip("Debug")
                end
                ImGui.SameLine()

                if ImGui.MenuItem(MyUI_Icons.MD_TV) then
                    showHUD = not showHUD
                end
                if ImGui.IsItemHovered() then
                    ImGui.SetTooltip("Toggle Heads Up Display")
                end
                ImGui.SameLine(ImGui.GetWindowWidth() - 30)

                if ImGui.MenuItem(MyUI_Icons.FA_WINDOW_CLOSE) then
                    Module.IsRunning = false
                end
                if ImGui.IsItemHovered() then
                    ImGui.SetTooltip("Exit\nThe Window Close button will only close the window.\nThis will exit the script completely.\nThe same as typing '/mypaths quit'.")
                end
                ImGui.EndMenuBar()
            end
            -- Set Window Font Scale
            ImGui.SetWindowFontScale(scale)
            if NavSet.PausedActiveGN then
                if mq.TLO.SpawnCount('gm')() > 0 then
                    ImGui.TextColored(1, 0, 0, 1, "!!%s GM in Zone %s!!", MyUI_Icons.FA_BELL, MyUI_Icons.FA_BELL)
                end
            end
            if not showHUD then
                -- Main Window Content
                if ImGui.CollapsingHeader("Status") then
                    sFlag = true
                    DrawStatus()
                    if NavSet.doNav then
                        ImGui.Text("Current Destination Waypoint: ")
                        ImGui.SameLine()
                        ImGui.TextColored(0, 1, 0, 1, "%s", curWPTxt)
                        ImGui.Text("Distance to Waypoint: ")
                        ImGui.SameLine()
                        if tmpTable[NavSet.CurrentStepIndex] ~= nil then
                            ImGui.TextColored(0, 1, 1, 1, "%.2f", mq.TLO.Math.Distance(tmpLoc)())
                        end
                    end
                else
                    sFlag = false
                end
            end
            if NavSet.SelectedPath ~= 'None' or #ChainedPaths > 0 then
                if NavSet.doPause and NavSet.doNav then
                    ImGui.PushStyleColor(ImGuiCol.Button, ImVec4(0.4, 1, 0.4, 0.4))
                    if ImGui.Button('Resume') then
                        NavSet.doPause = false
                        NavSet.PausedActiveGN = false
                        table.insert(debugMessages, { Time = os.date("%H:%M:%S"), Zone = currZone, Path = NavSet.SelectedPath, WP = 'Resume', Status = 'Resumed Navigation!', })
                    end
                    ImGui.PopStyleColor()
                    if ImGui.IsItemHovered() then
                        ImGui.SetTooltip("Resume Navigation")
                    end
                    ImGui.SameLine()
                elseif not NavSet.doPause and NavSet.doNav then
                    ImGui.PushStyleColor(ImGuiCol.Button, ImVec4(1, 0.4, 0.4, 0.4))
                    if ImGui.Button(MyUI_Icons.FA_PAUSE) then
                        NavSet.doPause = true
                        mq.cmd("/nav stop log=off")
                        table.insert(debugMessages, { Time = os.date("%H:%M:%S"), Zone = currZone, Path = NavSet.SelectedPath, WP = 'Pause', Status = 'Paused Navigation!', })
                    end
                    ImGui.PopStyleColor()
                    if ImGui.IsItemHovered() then
                        ImGui.SetTooltip("Pause Navigation")
                    end

                    ImGui.SameLine()
                end
                if NavSet.doNav then
                    ImGui.PushStyleColor(ImGuiCol.Button, ImVec4(1.0, 0.4, 0.4, 0.4))
                    if ImGui.Button(MyUI_Icons.FA_STOP) then
                        NavSet.doNav = false
                        NavSet.ChainStart = false
                        mq.cmdf("/nav stop log=off")
                        PathStartClock, PathStartTime = nil, nil
                    end
                    ImGui.PopStyleColor()

                    if ImGui.IsItemHovered() then
                        ImGui.SetTooltip("Stop Navigation")
                    end
                else
                    ImGui.PushStyleColor(ImGuiCol.Button, ImVec4(0.4, 1, 0.4, 0.4))
                    if ImGui.Button(MyUI_Icons.FA_PLAY) then
                        NavSet.PausedActiveGN = false
                        NavSet.doNav = true
                        PathStartClock, PathStartTime = os.date("%I:%M:%S %p"), os.time()
                    end
                    ImGui.PopStyleColor()
                    if ImGui.IsItemHovered() then
                        ImGui.SetTooltip("Start Navigation")
                    end
                end
            end
            if showHUD or not sFlag then
                ImGui.SameLine()
                ImGui.Text("Status: ")
                ImGui.SameLine()
                if status:find("Idle") then
                    ImGui.TextColored(ImVec4(0, 1, 1, 1), status)
                elseif status:find("Paused") then
                    if status:find("Mana") then
                        ImGui.TextColored(ImVec4(0.000, 0.438, 0.825, 1.000), status)
                    elseif status:find("Health") then
                        ImGui.TextColored(ImVec4(0.928, 0.352, 0.035, 1.000), status)
                    else
                        ImGui.TextColored(ImVec4(0.9, 0.4, 0.4, 1), status)
                    end
                elseif status:find("Last WP is less than") then
                    ImGui.TextColored(ImVec4(0.9, 0.4, 0.4, 1), status)
                elseif status:find("Recording") then
                    ImGui.TextColored(ImVec4(0.4, 0.9, 0.4, 1), status)
                elseif status:find("Arrived") then
                    ImGui.TextColored(ImVec4(0, 1, 0, 1), status)
                elseif status:find("Nav to WP") then
                    local tmpDist = mq.TLO.Math.Distance(tmpLoc)() or 0
                    local dist = string.format("%.2f", tmpDist)
                    local tmpStatus = status
                    if tmpStatus:find("Distance") then
                        tmpStatus = tmpStatus:sub(1, tmpStatus:find("Distance:") - 1)
                        tmpStatus = string.format("%s Distance: %s", tmpStatus, dist)
                        ImGui.TextColored(ImVec4(1, 1, 0, 1), tmpStatus)
                    end
                end
                if PathStartClock ~= nil and showHUD then
                    ImGui.Text("Start Time: ")
                    ImGui.SameLine()
                    ImGui.TextColored(0, 1, 1, 1, "%s", PathStartClock)
                    ImGui.SameLine()
                    ImGui.Text("Elapsed : ")
                    ImGui.SameLine()
                    local timeDiff = os.time() - PathStartTime
                    local hours = math.floor(timeDiff / 3600)
                    local minutes = math.floor((timeDiff % 3600) / 60)
                    local seconds = timeDiff % 60

                    ImGui.TextColored(0, 1, 0, 1, string.format("%02d:%02d:%02d", hours, minutes, seconds))
                end
            end
            ImGui.Separator()
            -- Tabs
            -- ImGui.BeginChild("Tabs##MainTabs", -1, -1,ImGuiChildFlags.AutoResizeX)
            if ImGui.BeginTabBar('MainTabBar') then
                ImGui.SetWindowFontScale(scale)
                if ImGui.BeginTabItem('Controls') then
                    if ImGui.BeginChild("Tabs##Controls", -1, -1, ImGuiChildFlags.AutoResizeX) then
                        ImGui.SeparatorText("Select a Path")
                        if not NavSet.doNav then
                            ImGui.SetNextItemWidth(120)
                            if ImGui.BeginCombo("##SelectPath", NavSet.SelectedPath) then
                                ImGui.SetWindowFontScale(scale)
                                if not Paths[currZone] then Paths[currZone] = {} end
                                for name, data in pairs(Paths[currZone]) do
                                    local isSelected = name == NavSet.SelectedPath
                                    if ImGui.Selectable(name, isSelected) then
                                        NavSet.SelectedPath = name
                                    end
                                end
                                ImGui.EndCombo()
                            end
                            ImGui.SameLine()
                            if ImGui.Button(MyUI_Icons.MD_DELETE_SWEEP .. '##ClearSelectedPath') then
                                NavSet.SelectedPath = 'None'
                            end
                            ImGui.SameLine()
                            ImGui.PushStyleColor(ImGuiCol.Button, ImVec4(1, 0.4, 0.4, 0.4))
                            if ImGui.Button(MyUI_Icons.MD_DELETE) then
                                DeletePath(NavSet.SelectedPath)
                                NavSet.SelectedPath = 'None'
                            end
                            ImGui.PopStyleColor()
                            if ImGui.IsItemHovered() then
                                ImGui.SetWindowFontScale(scale)
                                ImGui.SetTooltip("Delete Path")
                            end
                        else
                            ImGui.Text("Navigation Active")
                        end
                        ImGui.Spacing()
                        if ImGui.CollapsingHeader("Manage Paths##") then
                            ImGui.SetNextItemWidth(150)
                            newPath = ImGui.InputTextWithHint("##NewPathName", "New Path Name", newPath)
                            ImGui.SameLine()
                            ImGui.PushStyleColor(ImGuiCol.Button, ImVec4(0.4, 1, 0.4, 0.4))
                            if ImGui.Button(MyUI_Icons.MD_CREATE) then
                                CreatePath(newPath)
                                NavSet.SelectedPath = newPath
                                newPath = ''
                            end
                            ImGui.PopStyleColor()
                            if ImGui.IsItemHovered() then
                                ImGui.SetTooltip("Create New Path")
                            end
                            ImGui.SameLine()
                            if NavSet.SelectedPath ~= 'None' then
                                ImGui.PushStyleColor(ImGuiCol.Button, ImVec4(0.911, 0.461, 0.085, 1.000))
                                if ImGui.Button(MyUI_Icons.MD_CONTENT_COPY) then
                                    CreatePath(newPath)
                                    for i = 1, #Paths[currZone][NavSet.SelectedPath] do
                                        table.insert(Paths[currZone][newPath], Paths[currZone][NavSet.SelectedPath][i])
                                    end
                                    UpdatePath(currZone, newPath)
                                    NavSet.SelectedPath = newPath
                                    newPath = ''
                                end
                                ImGui.PopStyleColor()
                                if ImGui.IsItemHovered() then
                                    ImGui.SetWindowFontScale(scale)
                                    ImGui.SetTooltip("Copy Path")
                                end
                            else
                                ImGui.PushStyleColor(ImGuiCol.Button, ImVec4(0.500, 0.500, 0.500, 1.000))
                                ImGui.Button(MyUI_Icons.MD_CONTENT_COPY .. "##Dummy")
                                ImGui.PopStyleColor()
                            end
                            ImGui.SameLine()
                            if NavSet.SelectedPath ~= 'None' then
                                ImGui.PushStyleColor(ImGuiCol.Button, ImVec4(0.911, 0.461, 0.085, 1.000))
                                if ImGui.Button(MyUI_Icons.FA_SHARE .. "##ExportSelected") then
                                    local exportData = export_paths(currZone, NavSet.SelectedPath, Paths[currZone][NavSet.SelectedPath])
                                    ImGui.LogToClipboard()
                                    ImGui.LogText(exportData)
                                    ImGui.LogFinish()
                                    MyUI_Utils.PrintOutput('MyUI', nil, '\ayPath data copied to clipboard!\ax')
                                end
                                ImGui.PopStyleColor()
                            else
                                ImGui.PushStyleColor(ImGuiCol.Button, ImVec4(0.500, 0.500, 0.500, 1.000))
                                ImGui.Button(MyUI_Icons.FA_SHARE .. "##Dummy")
                                ImGui.PopStyleColor()
                            end
                            if ImGui.IsItemHovered() then
                                ImGui.SetWindowFontScale(scale)
                                ImGui.SetTooltip("Export: " .. currZone .. " : " .. NavSet.SelectedPath)
                            end
                            if ImGui.SmallButton("Write lua File") then
                                mq.pickle(pathsFile, Paths)
                            end
                            ImGui.Spacing()
                            if ImGui.CollapsingHeader("Share Paths##") then
                                importString = ImGui.InputTextWithHint("##ImportString", "Paste Import String", importString)
                                ImGui.SameLine()
                                if importString ~= '' then
                                    ImGui.PushStyleColor(ImGuiCol.Button, ImVec4(0.4, 1, 0.4, 0.4))
                                    if ImGui.Button(MyUI_Icons.FA_DOWNLOAD .. "##ImportPath") then
                                        local imported = import_paths(importString)
                                        if imported then
                                            for zone, paths in pairs(imported) do
                                                if not Paths[zone] then Paths[zone] = {} end
                                                for pathName, pathData in pairs(paths) do
                                                    Paths[zone][pathName] = pathData
                                                    if currZone == zone then NavSet.SelectedPath = pathName end
                                                end
                                            end
                                            importString = ''
                                            UpdatePath(currZone, NavSet.SelectedPath)
                                        end
                                    end
                                    ImGui.PopStyleColor()
                                else
                                    ImGui.PushStyleColor(ImGuiCol.Button, ImVec4(0.500, 0.500, 0.500, 1.000))
                                    ImGui.Button(MyUI_Icons.FA_DOWNLOAD .. "##Dummy")
                                    ImGui.PopStyleColor()
                                end
                                if ImGui.IsItemHovered() then
                                    ImGui.SetTooltip("Import Path")
                                end
                                ImGui.SeparatorText('Export Paths')
                                ImGui.SetNextItemWidth(120)
                                if ImGui.BeginCombo("Zone##SelectExportZone", exportZone) then
                                    if not Paths[exportZone] then Paths[exportZone] = {} end
                                    for name, data in pairs(Paths) do
                                        local isSelected = name == exportZone
                                        if ImGui.Selectable(name, isSelected) then
                                            exportZone = name
                                        end
                                    end
                                    ImGui.EndCombo()
                                end
                                if exportZone ~= 'Select Zone...' then
                                    ImGui.SetNextItemWidth(120)
                                    if ImGui.BeginCombo("Path##SelectExportPath", exportPathName) then
                                        if not Paths[exportZone] then Paths[exportZone] = {} end
                                        for name, data in pairs(Paths[exportZone]) do
                                            local isSelected = name == exportPathName
                                            if ImGui.Selectable(name, isSelected) then
                                                exportPathName = name
                                            end
                                        end
                                        ImGui.EndCombo()
                                    end
                                end
                                ImGui.SameLine()
                                if exportZone ~= 'Select Zone...' and exportPathName ~= 'Select Path...' then
                                    ImGui.PushStyleColor(ImGuiCol.Button, ImVec4(0.911, 0.461, 0.085, 1.000))
                                    if ImGui.Button(MyUI_Icons.FA_SHARE .. "##ExportZonePath") then
                                        local exportData = export_paths(exportZone, exportPathName, Paths[exportZone][exportPathName])
                                        ImGui.LogToClipboard()
                                        ImGui.LogText(exportData)
                                        ImGui.LogFinish()
                                        MyUI_Utils.PrintOutput('MyUI', nil, '\ayPath data copied to clipboard!\ax')
                                    end
                                    ImGui.PopStyleColor()
                                else
                                    ImGui.PushStyleColor(ImGuiCol.Button, ImVec4(0.500, 0.500, 0.500, 1.000))
                                    ImGui.Button(MyUI_Icons.FA_SHARE .. "##Dummy2")
                                    ImGui.PopStyleColor()
                                end
                                if ImGui.IsItemHovered() then
                                    ImGui.SetTooltip("Export:  " .. exportZone .. " : " .. exportPathName)
                                end
                            end
                        end
                        ImGui.Spacing()
                        ImGui.Separator()
                        if ImGui.CollapsingHeader("Chain Paths##") then
                            if NavSet.SelectedPath ~= 'None' then
                                ImGui.PushStyleColor(ImGuiCol.Button, ImVec4(0.4, 1, 0.4, 0.4))
                                if ImGui.Button(MyUI_Icons.MD_PLAYLIST_ADD .. " [" .. NavSet.SelectedPath .. "]##") then
                                    if not ChainedPaths then ChainedPaths = {} end
                                    table.insert(ChainedPaths, { Zone = currZone, Path = NavSet.SelectedPath, Type = 'Normal', })
                                end
                                ImGui.PopStyleColor()
                            else
                                ImGui.PushStyleColor(ImGuiCol.Button, ImVec4(0.500, 0.500, 0.500, 1.000))
                                ImGui.Button(MyUI_Icons.MD_PLAYLIST_ADD .. "##Dummy")
                                ImGui.PopStyleColor()
                            end
                            if ImGui.IsItemHovered() then
                                ImGui.SetWindowFontScale(scale)
                                ImGui.SetTooltip("Add " .. currZone .. ": " .. NavSet.SelectedPath .. " to Chain")
                            end
                            if #ChainedPaths > 0 then
                                NavSet.ChainLoop = ImGui.Checkbox('Loop Chain', NavSet.ChainLoop)
                            end
                            local tmpCZ, tmpCP = {}, {}
                            for name, data in pairs(Paths) do
                                table.insert(tmpCZ, name)
                            end
                            table.sort(tmpCZ)
                            ImGui.SetNextItemWidth(120)

                            if ImGui.BeginCombo("Zone##SelectChainZone", NavSet.ChainZone) then
                                ImGui.SetWindowFontScale(scale)
                                if not Paths[NavSet.ChainZone] then Paths[NavSet.ChainZone] = {} end
                                for k, name in pairs(tmpCZ) do
                                    local isSelected = name == NavSet.ChainZone
                                    if ImGui.Selectable(name, isSelected) then
                                        NavSet.ChainZone = name
                                    end
                                end
                                ImGui.EndCombo()
                            end
                            if NavSet.ChainZone ~= 'Select Zone...' then
                                ImGui.SetNextItemWidth(120)

                                if ImGui.BeginCombo("Path##SelectChainPath", NavSet.ChainPath) then
                                    ImGui.SetWindowFontScale(scale)
                                    if not Paths[NavSet.ChainZone] then Paths[NavSet.ChainZone] = {} end
                                    for k, data in pairs(Paths[NavSet.ChainZone]) do
                                        table.insert(tmpCP, k)
                                    end
                                    table.sort(tmpCP)
                                    for k, name in pairs(tmpCP) do
                                        local isSelected = name == NavSet.ChainPath
                                        if ImGui.Selectable(name, isSelected) then
                                            NavSet.ChainPath = name
                                        end
                                    end
                                    ImGui.EndCombo()
                                end
                            end
                            ImGui.SameLine()

                            if NavSet.ChainZone ~= 'Select Zone...' and NavSet.ChainPath ~= 'Select Path...' then
                                ImGui.PushStyleColor(ImGuiCol.Button, ImVec4(0.4, 1, 0.4, 0.4))
                                if ImGui.Button(MyUI_Icons.MD_PLAYLIST_ADD .. " [" .. NavSet.ChainPath .. "]##") then
                                    if not ChainedPaths then ChainedPaths = {} end
                                    table.insert(ChainedPaths, { Zone = NavSet.ChainZone, Path = NavSet.ChainPath, Type = 'Normal', })
                                end
                                ImGui.PopStyleColor()
                            else
                                ImGui.PushStyleColor(ImGuiCol.Button, ImVec4(0.500, 0.500, 0.500, 1.000))
                                ImGui.Button(MyUI_Icons.MD_PLAYLIST_ADD .. "##Dummy2")
                                ImGui.PopStyleColor()
                            end
                            if ImGui.IsItemHovered() then
                                ImGui.SetTooltip("Add " .. NavSet.ChainZone .. ": " .. NavSet.ChainPath .. " to Chain")
                            end
                            if #ChainedPaths > 0 then
                                ImGui.SameLine()
                                ImGui.PushStyleColor(ImGuiCol.Button, ImVec4(1, 0.4, 0.4, 0.4))
                                if ImGui.Button(MyUI_Icons.MD_DELETE_SWEEP .. "##") then
                                    ChainedPaths = {}
                                end
                                ImGui.PopStyleColor()

                                if ImGui.IsItemHovered() then
                                    ImGui.SetTooltip("Clear Chain")
                                end
                                ImGui.SeparatorText("Chain Paths:")
                                for i = 1, #ChainedPaths do
                                    ImGui.SetNextItemWidth(100)
                                    local chainType = { 'Normal', 'Loop', 'PingPong', 'Reverse', }
                                    if ImGui.BeginCombo("##PathType_" .. i, ChainedPaths[i].Type) then
                                        if not Paths[currZone] then Paths[currZone] = {} end
                                        for k, v in pairs(chainType) do
                                            local isSelected = v == ChainedPaths[i].Type
                                            if ImGui.Selectable(v, isSelected) then
                                                ChainedPaths[i].Type = v
                                            end
                                        end
                                        ImGui.EndCombo()
                                    end
                                    ImGui.SameLine()
                                    ImGui.TextColored(0.0, 1, 1, 1, "%s", ChainedPaths[i].Zone)
                                    ImGui.SameLine()
                                    if ChainedPaths[i].Path == NavSet.ChainPath then
                                        ImGui.TextColored(1, 1, 0, 1, "%s", ChainedPaths[i].Path)
                                    else
                                        ImGui.TextColored(0.0, 1, 0, 1, "%s", ChainedPaths[i].Path)
                                    end
                                end
                            end
                        end
                        ImGui.Spacing()
                        if NavSet.SelectedPath ~= 'None' or #ChainedPaths > 0 then
                            -- Navigation Controls
                            if ImGui.CollapsingHeader("Navigation##") then
                                if not NavSet.doNav then
                                    NavSet.doReverse = ImGui.Checkbox('Reverse Order', NavSet.doReverse)
                                    ImGui.SameLine()
                                end
                                NavSet.doLoop = ImGui.Checkbox('Loop Path', NavSet.doLoop)
                                ImGui.SameLine()
                                NavSet.doPingPong = ImGui.Checkbox('Ping Pong', NavSet.doPingPong)
                                if NavSet.doPingPong then
                                    NavSet.doLoop = true
                                end
                                ImGui.Separator()
                                if not Paths[currZone] then Paths[currZone] = {} end
                                if NavSet.doPause and NavSet.doNav then
                                    ImGui.PushStyleColor(ImGuiCol.Button, ImVec4(0.4, 1, 0.4, 0.4))

                                    if ImGui.Button(MyUI_Icons.FA_PLAY_CIRCLE_O) then
                                        NavSet.doPause = false
                                        NavSet.PausedActiveGN = false
                                        table.insert(debugMessages,
                                            { Time = os.date("%H:%M:%S"), Zone = currZone, Path = NavSet.SelectedPath, WP = 'Resume', Status = 'Resumed Navigation!', })
                                    end
                                    ImGui.PopStyleColor()

                                    if ImGui.IsItemHovered() then
                                        ImGui.SetTooltip("Resume Navigation")
                                    end
                                    ImGui.SameLine()
                                elseif not NavSet.doPause and NavSet.doNav then
                                    ImGui.PushStyleColor(ImGuiCol.Button, ImVec4(1, 0.4, 0.4, 0.4))

                                    if ImGui.Button(MyUI_Icons.FA_PAUSE) then
                                        NavSet.doPause = true
                                        mq.cmd("/nav stop log=off")
                                        table.insert(debugMessages,
                                            { Time = os.date("%H:%M:%S"), Zone = currZone, Path = NavSet.SelectedPath, WP = 'Pause', Status = 'Paused Navigation!', })
                                    end
                                    ImGui.PopStyleColor()

                                    if ImGui.IsItemHovered() then
                                        ImGui.SetTooltip("Pause Navigation")
                                    end
                                    ImGui.SameLine()
                                end
                                local tmpLabel = NavSet.doNav and MyUI_Icons.FA_STOP or MyUI_Icons.FA_PLAY
                                if NavSet.doNav then
                                    ImGui.PushStyleColor(ImGuiCol.Button, ImVec4(1.0, 0.4, 0.4, 0.4))
                                else
                                    ImGui.PushStyleColor(ImGuiCol.Button, ImVec4(0.4, 1.0, 0.4, 0.4))
                                end
                                if ImGui.Button(tmpLabel) then
                                    NavSet.PausedActiveGN = false
                                    NavSet.doNav = not NavSet.doNav
                                    NavSet.ChainStart = false
                                    if not NavSet.doNav then
                                        mq.cmdf("/nav stop log=off")
                                        NavSet.ChainStart = false
                                        PathStartClock, PathStartTime = nil, nil
                                    else
                                        PathStartClock, PathStartTime = os.date("%I:%M:%S %p"), os.time()
                                    end
                                end
                                ImGui.PopStyleColor()

                                if ImGui.IsItemHovered() then
                                    if NavSet.doNav then
                                        ImGui.SetTooltip("Stop Navigation")
                                    else
                                        ImGui.SetTooltip("Start Navigation")
                                    end
                                end
                                ImGui.SameLine()
                                ImGui.PushStyleColor(ImGuiCol.Button, ImVec4(0.4, 1.0, 0.4, 0.4))
                                if ImGui.Button(MyUI_Icons.FA_PLAY .. " Closest WP") then
                                    NavSet.CurrentStepIndex = closestWaypointIndex
                                    NavSet.doNav = true
                                    NavSet.PausedActiveGN = false
                                    PathStartClock, PathStartTime = os.date("%I:%M:%S %p"), os.time()
                                end
                                ImGui.PopStyleColor()
                                if ImGui.IsItemHovered() then
                                    ImGui.SetTooltip("Start Navigation at Closest Waypoint")
                                end
                                ImGui.SetNextItemWidth(100)
                                NavSet.StopDist = ImGui.InputInt("Stop Distance##" .. script, NavSet.StopDist, 1, 50)
                                ImGui.SetNextItemWidth(100)
                                NavSet.WpPause = ImGui.InputInt("Global Pause##" .. script, NavSet.WpPause, 1, 5)
                            end
                        end
                    end
                    ImGui.EndChild()
                    ImGui.EndTabItem()
                end
                if ImGui.BeginTabItem('Path Data') then
                    if ImGui.BeginChild("Tabs##PathTab", -1, -1, ImGuiChildFlags.AutoResizeX) then
                        if NavSet.SelectedPath ~= 'None' then
                            if ImGui.CollapsingHeader("Manage Waypoints##") then
                                ImGui.PushStyleColor(ImGuiCol.Button, ImVec4(0.4, 1, 0.4, 0.4))
                                if ImGui.Button(MyUI_Icons.MD_ADD_LOCATION) then
                                    RecordWaypoint(NavSet.SelectedPath)
                                end
                                ImGui.PopStyleColor()
                                if ImGui.IsItemHovered() then
                                    ImGui.SetTooltip("Add Waypoint")
                                end

                                ImGui.SameLine()
                                local label = MyUI_Icons.MD_FIBER_MANUAL_RECORD
                                if NavSet.autoRecord then
                                    label = MyUI_Icons.FA_STOP_CIRCLE
                                    ImGui.PushStyleColor(ImGuiCol.Button, ImVec4(1.0, 0.4, 0.4, 0.4))
                                else
                                    ImGui.PushStyleColor(ImGuiCol.Button, ImVec4(0.4, 1.0, 0.4, 0.4))
                                end
                                if ImGui.Button(label) then
                                    NavSet.autoRecord = not NavSet.autoRecord
                                    if NavSet.autoRecord then
                                        if DEBUG then
                                            table.insert(debugMessages,
                                                {
                                                    Time = os.date("%H:%M:%S"),
                                                    Zone = mq.TLO.Zone.ShortName(),
                                                    Path = NavSet.SelectedPath,
                                                    WP = 'Start Recording',
                                                    Status =
                                                    'Start Recording Waypoints!',
                                                })
                                        end
                                    else
                                        if DEBUG then
                                            table.insert(debugMessages,
                                                {
                                                    Time = os.date("%H:%M:%S"),
                                                    Zone = mq.TLO.Zone.ShortName(),
                                                    Path = NavSet.SelectedPath,
                                                    WP = 'Stop Recording',
                                                    Status =
                                                    'Stop Recording Waypoints!',
                                                })
                                        end
                                    end
                                end
                                ImGui.PopStyleColor()

                                if ImGui.IsItemHovered() then
                                    ImGui.SetTooltip("Auto Record Waypoints")
                                end
                                ImGui.SameLine()
                                ImGui.PushStyleColor(ImGuiCol.Button, ImVec4(1.0, 0.4, 0.4, 0.4))
                                if ImGui.Button(MyUI_Icons.MD_DELETE_SWEEP) then
                                    ClearWaypoints(NavSet.SelectedPath)
                                end
                                ImGui.PopStyleColor()
                                if ImGui.IsItemHovered() then
                                    ImGui.SetTooltip("Clear Waypoints")
                                end
                                ImGui.SameLine()
                                ImGui.SetNextItemWidth(80)
                                NavSet.RecordDelay = ImGui.InputInt("Record Delay##" .. script, NavSet.RecordDelay, 1, 10)
                            end
                            ImGui.Separator()
                        end
                        ImGui.Spacing()
                        if ImGui.CollapsingHeader("Waypoint Table##Header") then
                            -- Waypoint Table
                            if NavSet.SelectedPath ~= 'None' then
                                ImGui.SetWindowFontScale(scale)
                                if ImGui.BeginTable('PathTable', 6, bit32.bor(ImGuiTableFlags.Borders, ImGuiTableFlags.RowBg, ImGuiTableFlags.ScrollY, ImGuiTableFlags.Resizable, ImGuiTableFlags.Reorderable, ImGuiTableFlags.Hideable), -1, -1) then
                                    ImGui.TableSetupColumn('WP#', ImGuiTableColumnFlags.WidthFixed, -1)
                                    ImGui.TableSetupColumn('Loc', ImGuiTableColumnFlags.WidthFixed, -1)
                                    ImGui.TableSetupColumn('Delay', ImGuiTableColumnFlags.WidthFixed, -1)
                                    ImGui.TableSetupColumn('Actions', ImGuiTableColumnFlags.WidthFixed, -1)
                                    ImGui.TableSetupColumn('Door', ImGuiTableColumnFlags.WidthFixed, -1)
                                    ImGui.TableSetupColumn('Move', ImGuiTableColumnFlags.WidthFixed, -1)
                                    ImGui.TableSetupScrollFreeze(0, 1)
                                    ImGui.TableHeadersRow()

                                    for i = 1, #tmpTable do
                                        ImGui.TableNextRow()
                                        ImGui.TableSetColumnIndex(0)
                                        if tmpTable[i].step == tmpTable[NavSet.CurrentStepIndex].step then
                                            ImGui.TextColored(ImVec4(0, 1, 0, 1), "%s", tmpTable[i].step)
                                            if ImGui.IsItemHovered() then
                                                ImGui.SetTooltip("Current Waypoint")
                                            end
                                        else
                                            ImGui.Text("%s", tmpTable[i].step)
                                        end

                                        if i == closestWaypointIndex then
                                            ImGui.SameLine()
                                            ImGui.TextColored(ImVec4(1, 1, 0, 1), MyUI_Icons.MD_STAR)
                                            if ImGui.IsItemHovered() then
                                                ImGui.SetTooltip("Closest Waypoint")
                                            end
                                        end
                                        -- if tmpTable[i].step == tmpTable[currentStepIndex].step then
                                        --     ImGui.SameLine()
                                        --     ImGui.TextColored(ImVec4(0, 1, 1, 1), Icon.MD_STAR)
                                        --     if ImGui.IsItemHovered() then
                                        --         ImGui.SetTooltip("Current Waypoint")
                                        --     end
                                        -- end
                                        ImGui.TableSetColumnIndex(1)
                                        ImGui.Text(tmpTable[i].loc)
                                        if not NavSet.doNav then
                                            if ImGui.BeginPopupContextItem("WP_" .. tmpTable[i].step) then
                                                if ImGui.MenuItem('Nav to WP ' .. tmpTable[i].step) then
                                                    NavSet.CurrentStepIndex = i
                                                    NavSet.doNav = true
                                                    NavSet.doLoop = false
                                                    NavSet.doSingle = true
                                                    PathStartClock, PathStartTime = os.date("%I:%M:%S %p"), os.time()
                                                end

                                                if ImGui.MenuItem('Start Path Here: WP ' .. tmpTable[i].step) then
                                                    NavSet.CurrentStepIndex = i
                                                    NavSet.doNav = true
                                                    NavSet.doLoop = false
                                                    NavSet.doSingle = false
                                                    PathStartClock, PathStartTime = os.date("%I:%M:%S %p"), os.time()
                                                end
                                                if ImGui.MenuItem('Start Loop Here: WP ' .. tmpTable[i].step) then
                                                    NavSet.CurrentStepIndex = i
                                                    NavSet.doNav = true
                                                    NavSet.doLoop = true
                                                    NavSet.doSingle = false
                                                    PathStartClock, PathStartTime = os.date("%I:%M:%S %p"), os.time()
                                                end

                                                ImGui.EndPopup()
                                            end
                                        end
                                        ImGui.TableSetColumnIndex(2)
                                        ImGui.SetNextItemWidth(90)
                                        local changed, changedCmd = false, false
                                        tmpTable[i].delay, changed = ImGui.InputInt("##delay_" .. i, tmpTable[i].delay, 1, 1)
                                        if changed then
                                            for k, v in pairs(Paths[currZone][NavSet.SelectedPath]) do
                                                if v.step == tmpTable[i].step then
                                                    Paths[currZone][NavSet.SelectedPath][k].delay = tmpTable[i].delay
                                                    UpdatePath(currZone, NavSet.SelectedPath)
                                                end
                                            end
                                        end
                                        if ImGui.IsItemHovered() then
                                            ImGui.SetTooltip("Delay in Seconds")
                                        end
                                        ImGui.TableSetColumnIndex(3)
                                        ImGui.SetNextItemWidth(-1)
                                        tmpTable[i].cmd, changedCmd = ImGui.InputText("##cmd_" .. i, tmpTable[i].cmd)
                                        if changedCmd then
                                            for k, v in pairs(Paths[currZone][NavSet.SelectedPath]) do
                                                if v.step == tmpTable[i].step then
                                                    Paths[currZone][NavSet.SelectedPath][k].cmd = tmpTable[i].cmd
                                                    UpdatePath(currZone, NavSet.SelectedPath)
                                                end
                                            end
                                        end
                                        if ImGui.IsItemHovered() then
                                            ImGui.SetTooltip(tmpTable[i].cmd)
                                        end
                                        ImGui.TableSetColumnIndex(4)
                                        local changedDoor, changedDoorRev = false, false
                                        tmpTable[i].door, changedDoor = ImGui.Checkbox(MyUI_Icons.FA_FORWARD .. "##door_" .. i, tmpTable[i].door)
                                        if changedDoor then
                                            for k, v in pairs(Paths[currZone][NavSet.SelectedPath]) do
                                                if v.step == tmpTable[i].step then
                                                    Paths[currZone][NavSet.SelectedPath][k].door = tmpTable[i].door
                                                    UpdatePath(currZone, NavSet.SelectedPath)
                                                end
                                            end
                                        end
                                        if ImGui.IsItemHovered() then
                                            ImGui.SetTooltip("Door Forward")
                                        end
                                        ImGui.SameLine(0, 0)
                                        tmpTable[i].doorRev, changedDoorRev = ImGui.Checkbox(MyUI_Icons.FA_BACKWARD .. "##doorRev_" .. i, tmpTable[i].doorRev)
                                        if changedDoorRev then
                                            for k, v in pairs(Paths[currZone][NavSet.SelectedPath]) do
                                                if v.step == tmpTable[i].step then
                                                    Paths[currZone][NavSet.SelectedPath][k].doorRev = tmpTable[i].doorRev
                                                    UpdatePath(currZone, NavSet.SelectedPath)
                                                end
                                            end
                                        end
                                        if ImGui.IsItemHovered() then
                                            ImGui.SetTooltip("Door Reverse")
                                        end
                                        ImGui.TableSetColumnIndex(5)
                                        if not NavSet.doNav then
                                            if ImGui.Button(MyUI_Icons.FA_TRASH .. "##_" .. i) then
                                                deleteWP = true
                                                deleteWPStep = tmpTable[i].step
                                            end
                                            if ImGui.IsItemHovered() then
                                                ImGui.SetTooltip("Delete WP")
                                            end
                                            -- if not doReverse then
                                            ImGui.SameLine(0, 0)
                                            if ImGui.Button(MyUI_Icons.MD_UPDATE .. '##Update_' .. i) then
                                                tmpTable[i].loc = mq.TLO.Me.LocYXZ()
                                                -- Update Paths table
                                                for k, v in pairs(Paths[currZone][NavSet.SelectedPath]) do
                                                    if v.step == tmpTable[i].step then
                                                        Paths[currZone][NavSet.SelectedPath][k] = tmpTable[i]
                                                    end
                                                end
                                                -- Paths[currZone][selectedPath][tmpTable[i].step].loc = mq.TLO.Me.LocYXZ()
                                                UpdatePath(currZone, NavSet.SelectedPath)
                                            end
                                            if ImGui.IsItemHovered() then
                                                ImGui.SetTooltip("Update Loc")
                                            end
                                            -- end
                                            ImGui.SameLine(0, 0)
                                            if i > 1 and ImGui.Button(MyUI_Icons.FA_CHEVRON_UP .. "##up_" .. i) then
                                                -- Swap items in tmpTable
                                                local tmp = tmpTable[i]
                                                tmpTable[i] = tmpTable[i - 1]
                                                tmpTable[i - 1] = tmp

                                                -- Update step values
                                                tmpTable[i].step, tmpTable[i - 1].step = tmpTable[i - 1].step, tmpTable[i].step

                                                -- Update Paths table
                                                for k, v in pairs(Paths[currZone][NavSet.SelectedPath]) do
                                                    if v.step == tmpTable[i].step then
                                                        Paths[currZone][NavSet.SelectedPath][k] = tmpTable[i]
                                                    elseif v.step == tmpTable[i - 1].step then
                                                        Paths[currZone][NavSet.SelectedPath][k] = tmpTable[i - 1]
                                                    end
                                                end
                                                UpdatePath(currZone, NavSet.SelectedPath)
                                            end
                                            ImGui.SameLine(0, 0)
                                            if i < #tmpTable and ImGui.Button(MyUI_Icons.FA_CHEVRON_DOWN .. "##down_" .. i) then
                                                -- Swap items in tmpTable
                                                local tmp = tmpTable[i]
                                                tmpTable[i] = tmpTable[i + 1]
                                                tmpTable[i + 1] = tmp

                                                -- Update step values
                                                tmpTable[i].step, tmpTable[i + 1].step = tmpTable[i + 1].step, tmpTable[i].step

                                                -- Update Paths table
                                                for k, v in pairs(Paths[currZone][NavSet.SelectedPath]) do
                                                    if v.step == tmpTable[i].step then
                                                        Paths[currZone][NavSet.SelectedPath][k] = tmpTable[i]
                                                    elseif v.step == tmpTable[i + 1].step then
                                                        Paths[currZone][NavSet.SelectedPath][k] = tmpTable[i + 1]
                                                    end
                                                end
                                                UpdatePath(currZone, NavSet.SelectedPath)
                                            end
                                        end
                                    end
                                    ImGui.EndTable()
                                end
                            else
                                ImGui.Text("No Path Selected")
                            end
                        end
                    end
                    ImGui.EndChild()
                    ImGui.EndTabItem()
                end
                if showDebugTab and DEBUG then
                    if ImGui.BeginTabItem('Debug Messages') then
                        if ImGui.BeginChild("Tabs##DebugTab", -1, -1, ImGuiChildFlags.AutoResizeX) then
                            if ImGui.Button('Clear Debug Messages') then
                                debugMessages = {}
                            end
                            if ImGui.IsItemHovered() then
                                ImGui.SetTooltip("Clear Debug Messages")
                            end
                            ImGui.Separator()
                            ImGui.SetWindowFontScale(scale)
                            if ImGui.BeginTable('DebugTable', 5, bit32.bor(ImGuiTableFlags.Borders, ImGuiTableFlags.RowBg, ImGuiTableFlags.ScrollY, ImGuiTableFlags.Resizable, ImGuiTableFlags.Reorderable, ImGuiTableFlags.Hideable), ImVec2(0.0, 0.0)) then
                                ImGui.TableSetupColumn('Time##', ImGuiTableColumnFlags.WidthFixed, 100)
                                ImGui.TableSetupColumn('Zone##', ImGuiTableColumnFlags.WidthFixed, 100)
                                ImGui.TableSetupColumn('Path##', ImGuiTableColumnFlags.WidthFixed, 100)
                                ImGui.TableSetupColumn('Action / Step##', ImGuiTableColumnFlags.WidthFixed, 100)
                                ImGui.TableSetupColumn('Status##', ImGuiTableColumnFlags.WidthFixed, 100)
                                ImGui.TableSetupScrollFreeze(0, 1)
                                ImGui.TableHeadersRow()
                                local tmpDebug = {}
                                for i = 1, #debugMessages do
                                    table.insert(tmpDebug, debugMessages[i])
                                end
                                table.sort(tmpDebug, function(a, b) return a.Time > b.Time end)
                                for i = 1, #tmpDebug do
                                    ImGui.TableNextRow()
                                    ImGui.TableSetColumnIndex(0)
                                    ImGui.Text(tmpDebug[i].Time)
                                    ImGui.TableSetColumnIndex(1)
                                    ImGui.Text(tmpDebug[i].Zone)
                                    ImGui.TableSetColumnIndex(2)
                                    ImGui.Text(tmpDebug[i].Path)
                                    ImGui.TableSetColumnIndex(3)
                                    ImGui.Text(tmpDebug[i].WP)
                                    ImGui.TableSetColumnIndex(4)
                                    ImGui.TextWrapped(tmpDebug[i].Status)
                                end
                                ImGui.EndTable()
                            end
                        end
                        ImGui.EndChild()
                        ImGui.EndTabItem()
                    end
                end
                ImGui.EndTabBar()
            end
            -- ImGui.EndChild()
        end
        -- Reset Font Scale
        ImGui.SetWindowFontScale(1)
        -- Unload Theme
        MyUI_ThemeLoader.EndTheme(ColorCount, StyleCount)
        ImGui.End()
    end

    -- Config Window


    if showConfigGUI then
        if currZone ~= lastZone then return end
        local winName = string.format('%s Config##Config_%s', script, MyUI_CharLoaded)
        local ColCntConf, StyCntConf = DrawTheme(themeName)

        local openConfig, showConfig = ImGui.Begin(winName, true, bit32.bor(ImGuiWindowFlags.NoCollapse, ImGuiWindowFlags.AlwaysAutoResize))
        if not openConfig then
            showConfigGUI = false
            showConfig = false
        end
        if showConfig then
            -- Set Window Font Scale
            ImGui.SetWindowFontScale(scale)
            if ImGui.CollapsingHeader('Theme##Settings' .. script) then
                -- Configure ThemeZ --
                ImGui.SeparatorText("Theme##" .. script)
                ImGui.Text("Cur Theme: %s", themeName)

                -- Combo Box Load Theme
                ImGui.SetNextItemWidth(100)
                if ImGui.BeginCombo("Load Theme##" .. script, themeName) then
                    for k, data in pairs(theme.Theme) do
                        local isSelected = data.Name == themeName
                        if ImGui.Selectable(data.Name, isSelected) then
                            theme.LoadTheme = data.Name
                            themeID = k
                            themeName = theme.LoadTheme
                        end
                    end
                    ImGui.EndCombo()
                end

                -- Configure Scale --
                ImGui.SetNextItemWidth(100)
                scale = ImGui.SliderFloat("Scale##" .. script, scale, 0.5, 2)
                if scale ~= settings[script].Scale then
                    if scale < 0.5 then scale = 0.5 end
                    if scale > 2 then scale = 2 end
                end

                -- Edit ThemeZ Button if ThemeZ lua exists.
                if hasThemeZ then
                    if ImGui.Button('Edit ThemeZ') then
                        mq.cmd("/lua run themez")
                    end
                    ImGui.SameLine()
                end

                -- Reload Theme File incase of changes --
                if ImGui.Button('Reload Theme File') then
                    loadTheme()
                end
            end
            ImGui.Spacing()

            if ImGui.CollapsingHeader("HUD Settings##" .. script) then
                -- HUD Transparency --
                ImGui.SetNextItemWidth(100)
                local lblHudTrans = doMouseOver and "HUD Faded Transparency##" .. script or "HUD Transparency##" .. script
                hudTransparency = ImGui.SliderFloat(lblHudTrans, hudTransparency, 0.0, 1)
                if doMouseOver then
                    ImGui.SetNextItemWidth(100)
                    mouseOverTransparency = ImGui.SliderFloat("HUD MouseOver Transparency##" .. script, mouseOverTransparency, 0.0, 1)
                end
                doMouseOver = ImGui.Checkbox("On Mouseover##" .. script, doMouseOver)
            end
            ImGui.Spacing()

            if ImGui.CollapsingHeader("Interrupt Settings##" .. script) then
                -- Set Interrupts we will stop for
                InterruptSet.interruptsOn = ImGui.Checkbox("Interrupts On##" .. script, InterruptSet.interruptsOn)
                if ImGui.Button('Check All') then
                    InterruptSet.stopForDist = true
                    InterruptSet.stopForCharm = true
                    InterruptSet.stopForCombat = true
                    InterruptSet.stopForFear = true
                    InterruptSet.stopForGM = true
                    InterruptSet.stopForLoot = true
                    InterruptSet.stopForMez = true
                    InterruptSet.stopForRoot = true
                    InterruptSet.stopForSitting = true
                    InterruptSet.stopForXtar = true
                    InterruptSet.stopForInvis = true
                    InterruptSet.stopForDblInvis = true
                end

                if ImGui.BeginTable("##Interrupts", 2, bit32.bor(ImGuiTableFlags.Borders), -1, 0) then
                    ImGui.TableNextRow()
                    ImGui.TableSetColumnIndex(0)
                    InterruptSet.stopForCharm = ImGui.Checkbox("Stop for Charmed##" .. script, InterruptSet.stopForCharm)
                    if not InterruptSet.stopForCharm then InterruptSet.stopForAll = false end
                    ImGui.TableSetColumnIndex(1)
                    InterruptSet.stopForCombat = ImGui.Checkbox("Stop for Combat##" .. script, InterruptSet.stopForCombat)
                    if not InterruptSet.stopForCombat then InterruptSet.stopForAll = false end
                    ImGui.TableNextRow()

                    ImGui.TableSetColumnIndex(0)
                    InterruptSet.stopForFear = ImGui.Checkbox("Stop for Fear##" .. script, InterruptSet.stopForFear)
                    if not InterruptSet.stopForFear then InterruptSet.stopForAll = false end
                    ImGui.TableSetColumnIndex(1)
                    InterruptSet.stopForGM = ImGui.Checkbox("Stop for GM##" .. script, InterruptSet.stopForGM)
                    if not InterruptSet.stopForGM then InterruptSet.stopForAll = false end
                    ImGui.TableNextRow()

                    ImGui.TableSetColumnIndex(0)
                    InterruptSet.stopForLoot = ImGui.Checkbox("Stop for Loot##" .. script, InterruptSet.stopForLoot)
                    if not InterruptSet.stopForLoot then InterruptSet.stopForAll = false end
                    ImGui.TableSetColumnIndex(1)
                    InterruptSet.stopForMez = ImGui.Checkbox("Stop for Mez##" .. script, InterruptSet.stopForMez)
                    if not InterruptSet.stopForMez then InterruptSet.stopForAll = false end
                    ImGui.TableNextRow()

                    ImGui.TableSetColumnIndex(0)
                    InterruptSet.stopForRoot = ImGui.Checkbox("Stop for Root##" .. script, InterruptSet.stopForRoot)
                    if not InterruptSet.stopForRoot then InterruptSet.stopForAll = false end
                    ImGui.TableSetColumnIndex(1)
                    InterruptSet.stopForSitting = ImGui.Checkbox("Stop for Sitting##" .. script, InterruptSet.stopForSitting)
                    if not InterruptSet.stopForSitting then InterruptSet.stopForAll = false end
                    ImGui.TableNextRow()

                    ImGui.TableSetColumnIndex(0)
                    InterruptSet.stopForXtar = ImGui.Checkbox("Stop for Xtarget##" .. script, InterruptSet.stopForXtar)
                    if not InterruptSet.stopForXtar then InterruptSet.stopForAll = false end
                    ImGui.TableSetColumnIndex(1)
                    InterruptSet.stopForDist = ImGui.Checkbox("Stop for Party Dist##" .. script, InterruptSet.stopForDist)
                    if not InterruptSet.stopForDist then InterruptSet.stopForAll = false end
                    ImGui.TableNextRow()

                    ImGui.TableSetColumnIndex(0)
                    InterruptSet.stopForInvis = ImGui.Checkbox("Stop for Invis##" .. script, InterruptSet.stopForInvis)
                    if not InterruptSet.stopForInvis then InterruptSet.stopForAll = false end
                    ImGui.TableSetColumnIndex(1)
                    InterruptSet.stopForDblInvis = ImGui.Checkbox("Stop for Dbl Invis##" .. script, InterruptSet.stopForDblInvis)
                    if not InterruptSet.stopForDblInvis then InterruptSet.stopForAll = false end
                    ImGui.TableNextRow()
                    ImGui.TableSetColumnIndex(0)
                    settings[script].AutoStand, _ = ImGui.Checkbox("Auto Stand##" .. script, settings[script].AutoStand)
                    if _ then mq.pickle(configFile, settings) end
                    ImGui.EndTable()
                    if InterruptSet.stopForInvis or InterruptSet.stopForDblInvis then
                        settings[script].InvisAction = ImGui.InputText("Invis Action##" .. script, settings[script].InvisAction)
                        settings[script].InvisDelay = ImGui.InputInt("Invis Delay##" .. script, settings[script].InvisDelay, 1, 5)
                    end
                    if InterruptSet.stopForDist then
                        ImGui.SetNextItemWidth(100)
                        InterruptSet.stopForGoupDist = ImGui.InputInt("Party Distance##GroupDist", InterruptSet.stopForGoupDist, 1, 50)
                    end
                end
                settings[script].GroupWatch = ImGui.Checkbox("Group Watch##" .. script, settings[script].GroupWatch)
                if settings[script].GroupWatch then
                    if ImGui.CollapsingHeader("Group Watch Settings##" .. script) then
                        settings[script].WatchHealth = ImGui.InputInt("Watch Health##" .. script, settings[script].WatchHealth, 1, 5)
                        if settings[script].WatchHealth > 100 then settings[script].WatchHealth = 100 end
                        if settings[script].WatchHealth < 1 then settings[script].WatchHealth = 1 end
                        settings[script].WatchMana = ImGui.InputInt("Watch Mana##" .. script, settings[script].WatchMana, 1, 5)
                        if settings[script].WatchMana > 100 then settings[script].WatchMana = 100 end
                        if settings[script].WatchMana < 1 then settings[script].WatchMana = 1 end

                        if ImGui.BeginCombo("Watch Type##" .. script, settings[script].WatchType) then
                            local types = { "All", "Healer", "Self", "None", }
                            for i = 1, #types do
                                local isSelected = types[i] == settings[script].WatchType
                                if ImGui.Selectable(types[i], isSelected) then
                                    settings[script].WatchType = types[i]
                                end
                            end
                            ImGui.EndCombo()
                        end
                    end
                end
            end
            ImGui.Spacing()

            if ImGui.CollapsingHeader("Recording Settings##" .. script) then
                -- Set RecordDley
                ImGui.SetNextItemWidth(100)
                NavSet.RecordDelay = ImGui.InputInt("Record Delay##" .. script, NavSet.RecordDelay, 1, 5)
                -- Minimum Distance Between Waypoints
                ImGui.SetNextItemWidth(100)
                NavSet.RecordMinDist = ImGui.InputInt("Min Dist. Between WP##" .. script, NavSet.RecordMinDist, 1, 50)
            end
            ImGui.Spacing()

            if ImGui.CollapsingHeader("Navigation Settings##" .. script) then
                -- Set Stop Distance
                ImGui.SetNextItemWidth(100)
                NavSet.StopDist = ImGui.InputInt("Stop Distance##" .. script, NavSet.StopDist, 1, 50)
                -- Set Waypoint Pause time
                ImGui.SetNextItemWidth(100)
                NavSet.WpPause = ImGui.InputInt("Waypoint Pause##" .. script, NavSet.WpPause, 1, 5)
                -- Set Interrupt Delay
                ImGui.SetNextItemWidth(100)
                InterruptSet.interruptDelay = ImGui.InputInt("Interrupt Delay##" .. script, InterruptSet.interruptDelay, 1, 5)
            end
            ImGui.Spacing()

            -- Save & Close Button --
            if ImGui.Button("Save & Close") then
                settings[script].HeadsUpTransparency = hudTransparency
                settings[script].MouseOverTransparency = mouseOverTransparency
                settings[script].Scale = scale
                settings[script].LoadTheme = themeName
                settings[script].locked = locked
                settings[script].AutoSize = aSize
                settings[script].MouseHUD = doMouseOver
                settings[script].RecordDelay = NavSet.RecordDelay
                settings[script].StopForGM = InterruptSet.stopForGM
                settings[script].StopDistance = NavSet.StopDist
                settings[script].RecordMinDist = NavSet.RecordMinDist
                settings[script].PauseStops = NavSet.WpPause
                settings[script].InterruptDelay = InterruptSet.interruptDelay
                settings[script].Interrupts = InterruptSet
                mq.pickle(configFile, settings)
                showConfigGUI = false
            end
        end
        -- Reset Window Font Scale
        ImGui.SetWindowFontScale(1)
        MyUI_ThemeLoader.EndTheme(ColCntConf, StyCntConf)
        ImGui.End()
    end

    if showHUD then
        if currZone ~= lastZone then return end

        if mousedOverFlag and doMouseOver then
            ImGui.PushStyleColor(ImGuiCol.WindowBg, ImVec4(0.0, 0.0, 0.0, mouseOverTransparency))
        elseif not mousedOverFlag and doMouseOver then
            ImGui.PushStyleColor(ImGuiCol.WindowBg, ImVec4(0.0, 0.0, 0.0, hudTransparency))
        elseif not doMouseOver then
            ImGui.PushStyleColor(ImGuiCol.WindowBg, ImVec4(0.0, 0.0, 0.0, hudTransparency))
        end
        local hudFlags = bit32.bor(ImGuiWindowFlags.NoCollapse, ImGuiWindowFlags.AlwaysAutoResize, ImGuiWindowFlags.NoTitleBar)
        if hudLock then hudFlags = bit32.bor(hudFlags, ImGuiWindowFlags.NoMove) end
        local openHUDWin, showHUDWin = ImGui.Begin("MyPaths HUD##HUD", true, hudFlags)
        if not openHUDWin then
            ImGui.PopStyleColor()
            showHUD = false
            showHUDWin = false
        end
        if showHUDWin then
            DrawStatus()
            if ImGui.BeginPopupContextItem("##MyPaths_Context") then
                local lockLabel = hudLock and 'Unlock' or 'Lock'
                if ImGui.MenuItem(lockLabel .. "##MyPathsHud") then
                    hudLock = not hudLock

                    settings[script].HudLock = hudLock
                    mq.pickle(configFile, settings)
                end

                ImGui.EndPopup()
            end
        end
        ImGui.PopStyleColor()
        -- Set Window Font Scale
        ImGui.SetWindowFontScale(1)
        ImGui.End()
    end
end

-------- Main Functions --------

local function displayHelp()
    --[[
    Commands: /mypaths [go|stop|list|chainadd|chainclear|show|quit|help] [loop|rloop|start|reverse|pingpong|closest|rclosest] [path]
    Options: go = REQUIRES arguments and Path name see below for Arguments.
    Options: stop = Stops the current Navigation.
    Options: show = Toggles Main GUI.
    Options: chainclear = Clears the Current Chain.
    Options: chainadd [normal|reverse|loop|pingpong] [path] -- adds path to chain in current zone
    Options: chainadd [normal|reverse|loop|pingpong] [zone] [path] -- adds zone/path to chain
    Options: list = Lists all Paths in the current Zone.
    Options: list zone -- list all zones that have paths
    Options: list [zone] -- list all paths in specified zone
    Options: quit or exit = Exits the script.
    Options: help = Prints out this help list.
    Arguments: loop = Loops the path, rloop = Loop in reverse.
    Arguments: closest = start at closest wp, rclosest = start at closest wp and go in reverse.
    Arguments: start = starts the path normally, reverse = run the path backwards.
    Arguments: pingpong = start in ping pong mode.
    Example: /mypaths go loop "Loop A"
    Example: /mypaths stop
    Commands: /mypaths [combat|xtarg] [on|off] - Toggle Combat or Xtarget.]]
    MyUI_Utils.PrintOutput('MyUI', nil,
        "\ay[\at%s\ax] \agCommands: \ay/mypaths [go|stop|list|chainadd|chainclear|chainloop|show|quit|save|reload|help] [loop|rloop|start|reverse|pingpong|closest|rclosest] [path]",
        script)
    MyUI_Utils.PrintOutput('MyUI', nil, "\ay[\at%s\ax] \agOptions: \aygo \aw= \atREQUIRES arguments and Path name see below for Arguments.", script)
    MyUI_Utils.PrintOutput('MyUI', nil, "\ay[\at%s\ax] \agOptions: \aystop \aw= \atStops the current Navigation.", script)
    MyUI_Utils.PrintOutput('MyUI', nil, "\ay[\at%s\ax] \agOptions: \ayshow \aw= \atToggles Main GUI.", script)
    MyUI_Utils.PrintOutput('MyUI', nil, "\ay[\at%s\ax] \agOptions: \aychainclear \aw= \atClears the Current Chain.", script)
    MyUI_Utils.PrintOutput('MyUI', nil, "\ay[\at%s\ax] \agOptions: \aychainloop \aw= \atToggle Loop the Current Chain.", script)
    MyUI_Utils.PrintOutput('MyUI', nil, "\ay[\at%s\ax] \agOptions: \aychainadd [normal|reverse|loop|pingpong] [path] \aw= \atadds path to chain in current zone", script)
    MyUI_Utils.PrintOutput('MyUI', nil, "\ay[\at%s\ax] \agOptions: \aychainadd [normal|reverse|loop|pingpong] [zone] [path] \aw= \atadds zone/path to chain", script)
    MyUI_Utils.PrintOutput('MyUI', nil, "\ay[\at%s\ax] \agOptions: \aylist \aw= \atLists all Paths in the current Zone.", script)
    MyUI_Utils.PrintOutput('MyUI', nil, "\ay[\at%s\ax] \agOptions: \aylist zone \aw= \atlist all zones that have paths", script)
    MyUI_Utils.PrintOutput('MyUI', nil, "\ay[\at%s\ax] \agOptions: \aylist [zone] \aw= \atlist all paths in specified zone", script)
    MyUI_Utils.PrintOutput('MyUI', nil, "\ay[\at%s\ax] \agOptions: \ayquit or exit \aw= \atExits the script.", script)
    MyUI_Utils.PrintOutput('MyUI', nil, "\ay[\at%s\ax] \agOptions: \aysave \aw= \atSave the current Paths to lua file.", script)
    MyUI_Utils.PrintOutput('MyUI', nil, "\ay[\at%s\ax] \agOptions: \ayreload \aw= \atReload Paths File.", script)
    MyUI_Utils.PrintOutput('MyUI', nil, "\ay[\at%s\ax] \agOptions: \ayhelp \aw= \atPrints out this help list.", script)
    MyUI_Utils.PrintOutput('MyUI', nil, "\ay[\at%s\ax] \agArguments: \ayloop \aw= \atLoops the path, \ayrloop \aw= \atLoop in reverse.", script)
    MyUI_Utils.PrintOutput('MyUI', nil, "\ay[\at%s\ax] \agArguments: \ayclosest \aw= \atstart at closest wp, \ayrclosest \aw= \atstart at closest wp and go in reverse.", script)
    MyUI_Utils.PrintOutput('MyUI', nil, "\ay[\at%s\ax] \agArguments: \aystart \aw= \atstarts the path normally, \ayreverse \aw= \atrun the path backwards.", script)
    MyUI_Utils.PrintOutput('MyUI', nil, "\ay[\at%s\ax] \agArguments: \aypingpong \aw= \atstart in ping pong mode.", script)
    MyUI_Utils.PrintOutput('MyUI', nil, "\ay[\at%s\ax] \agExample: \ay/mypaths \aogo \ayloop \am\"Loop A\"", script)
    MyUI_Utils.PrintOutput('MyUI', nil, "\ay[\at%s\ax] \agExample: \ay/mypaths \aostop", script)
    MyUI_Utils.PrintOutput('MyUI', nil, "\ay[\at%s\ax] \agCommands: \ay/mypaths [\atcombat\ax|\atxtarg\ax] [\aton\ax|\atoff\ax] \ay- \atToggle Combat or Xtarget.", script)
    MyUI_Utils.PrintOutput('MyUI', nil, "\ay[\at%s\ax] \agCommands: \ay/mypaths [\atdointerrupts\ax] [\aton\ax|\atoff\ax] \ay- \atToggle Interrupts.", script)
end

local function bind(...)
    local args = { ..., }
    local key = args[1]
    local action = args[2]
    local path = args[3]
    local zone = mq.TLO.Zone.ShortName()

    if #args == 1 then
        if key == 'stop' then
            NavSet.doNav = false
            mq.cmdf("/nav stop log=off")
            NavSet.ChainStart = false
            NavSet.SelectedPath = 'None'
            -- loadPaths()
        elseif key == 'help' then
            displayHelp()
        elseif key == 'debug' then
            DEBUG = not DEBUG
        elseif key == 'hud' then
            showHUD = not showHUD
        elseif key == 'show' then
            showMainGUI = not showMainGUI
        elseif key == 'pause' then
            NavSet.doPause = true
        elseif key == 'xtarg' then
            InterruptSet.stopForXtar = not InterruptSet.stopForXtar
            if not InterruptSet.stopForXtar then
                InterruptSet.stopForAll = false
            end
        elseif key == 'combat' then
            InterruptSet.stopForCombat = not InterruptSet.stopForCombat
            if not InterruptSet.stopForCombat then
                InterruptSet.stopForAll = false
            end
        elseif key == 'resume' then
            NavSet.doPause = false
        elseif key == 'quit' or key == 'exit' then
            -- mq.exit()
            mq.cmd("/nav stop log=off")
            mq.TLO.Me.Stand()
            mq.delay(1)
            NavSet.doNav = false
            Module.IsRunning = false
        elseif key == 'list' then
            MyUI_Utils.PrintOutput('MyUI', nil, "\ay[\at%s\ax] \agZones: ", script)
            for name, data in pairs(Paths) do
                MyUI_Utils.PrintOutput('MyUI', nil, "\ay[\at%s\ax] \ay%s", script, name)
            end
        elseif key == 'chainclear' then
            ChainedPaths = {}
        elseif key == 'chainloop' then
            if #ChainedPaths > 0 then
                NavSet.ChainLoop = not NavSet.ChainLoop
            end
        elseif key == 'reload' then
            loadPaths()
        elseif key == 'save' then
            mq.pickle(pathsFile, Paths)
        else
            MyUI_Utils.PrintOutput('MyUI', nil, "\ay[\at%s\ax] \arInvalid Command!", script)
        end
    elseif #args == 2 then
        if key == 'resume' then
            if action == 'next' then
                NavSet.CurrentStepIndex = NavSet.CurrentStepIndex + 1
                NavSet.doPause = false
            elseif action == 'back' then
                NavSet.CurrentStepIndex = NavSet.CurrentStepIndex - 1
                NavSet.doPause = false
            end
        elseif key == 'xtarg' then
            if action == 'on' then
                InterruptSet.stopForXtar = true
            elseif action == 'off' then
                InterruptSet.stopForXtar = false
                InterruptSet.stopForAll = false
            end
        elseif key == 'combat' then
            if action == 'on' then
                InterruptSet.stopForCombat = true
            elseif action == 'off' then
                InterruptSet.stopForCombat = false
                InterruptSet.stopForAll = false
            end
        elseif key == 'dointerrupts' then
            if action == 'on' then
                InterruptSet.interruptsOn = true
                MyUI_Utils.PrintOutput('MyUI', nil, "\ay[\at%s\ax] \agPausing for Interrupts: \atON", script)
            elseif action == 'off' then
                InterruptSet.interruptsOn = false
                MyUI_Utils.PrintOutput('MyUI', nil, "\ay[\at%s\ax] \agPausing for Interrupts: \arOFF", script)
            end
        elseif key == 'list' then
            if action == 'zones' then
                MyUI_Utils.PrintOutput('MyUI', nil, "\ay[\at%s\ax] \agZone: \atZones With Paths: ", script)
                for name, data in pairs(Paths) do
                    if name ~= nil and name ~= '' then MyUI_Utils.PrintOutput('MyUI', nil, "\ay[\at%s\ax] \ay%s", script, name) end
                end
            else
                if Paths[action] == nil then
                    MyUI_Utils.PrintOutput('MyUI', nil, "\ay[\at%s\ax] \arNo Paths Found!", script)
                    return
                end
                MyUI_Utils.PrintOutput('MyUI', nil, "\ay[\at%s\ax] \agZone: \at%s \agPaths: ", script, action)
                for name, data in pairs(Paths[action]) do
                    MyUI_Utils.PrintOutput('MyUI', nil, "\ay[\at%s\ax] \ay%s", script, name)
                end
            end
        elseif key == "gpause" and tonumber(action) ~= nil then
            settings[script].PauseStops = tonumber(action)
            mq.pickle(configFile, settings)
            NavSet.WpPause = settings[script].PauseStops
        end
    elseif #args == 3 then
        if Paths[zone]["'" .. path .. "'"] ~= nil then
            MyUI_Utils.PrintOutput('MyUI', nil, "\ay[\at%s\ax] \arInvalid Path!", script)
            return
        end
        if key == 'go' then
            if action == 'loop' then
                NavSet.SelectedPath = path
                NavSet.doReverse = false
                NavSet.doNav = true
                NavSet.doLoop = true
                PathStartClock, PathStartTime = os.date("%I:%M:%S %p"), os.time()
            end
            if action == 'rloop' then
                NavSet.SelectedPath = path
                NavSet.doReverse = true
                NavSet.doNav = true
                NavSet.doLoop = true
                PathStartClock, PathStartTime = os.date("%I:%M:%S %p"), os.time()
            end
            if action == 'start' then
                NavSet.SelectedPath = path
                NavSet.doReverse = false
                NavSet.doNav = true
                NavSet.doLoop = false
                PathStartClock, PathStartTime = os.date("%I:%M:%S %p"), os.time()
            end
            if action == 'reverse' then
                NavSet.SelectedPath = path
                NavSet.doReverse = true
                NavSet.doNav = true
                PathStartClock, PathStartTime = os.date("%I:%M:%S %p"), os.time()
            end
            if action == 'pingpong' then
                NavSet.SelectedPath = path
                NavSet.doPingPong = true
                NavSet.doNav = true
                PathStartClock, PathStartTime = os.date("%I:%M:%S %p"), os.time()
            end
            if action == 'closest' then
                NavSet.SelectedPath = path
                NavSet.doNav = true
                NavSet.doReverse = false
                NavSet.CurrentStepIndex = FindIndexClosestWaypoint(Paths[zone][path])
                PathStartClock, PathStartTime = os.date("%I:%M:%S %p"), os.time()
            end
            if action == 'rclosest' then
                NavSet.SelectedPath = path
                NavSet.doNav = true
                NavSet.doReverse = true
                NavSet.CurrentStepIndex = FindIndexClosestWaypoint(Paths[zone][path])
                PathStartClock, PathStartTime = os.date("%I:%M:%S %p"), os.time()
            end
        end
        if key == 'chainadd' then
            if action == 'loop' then
                if not ChainedPaths then ChainedPaths = {} end
                table.insert(ChainedPaths, { Zone = zone, Path = path, Type = 'Loop', })
            end
            if action == 'normal' then
                if not ChainedPaths then ChainedPaths = {} end
                table.insert(ChainedPaths, { Zone = zone, Path = path, Type = 'Normal', })
            end
            if action == 'reverse' then
                if not ChainedPaths then ChainedPaths = {} end
                table.insert(ChainedPaths, { Zone = zone, Path = path, Type = 'Reverse', })
            end
            if action == 'pingpong' then
                if not ChainedPaths then ChainedPaths = {} end
                table.insert(ChainedPaths, { Zone = zone, Path = path, Type = 'PingPong', })
            end
        end
    elseif #args == 4 then
        action = args[2]
        zone = args[3]
        path = args[4]
        if key == 'chainadd' then
            if action == 'loop' then
                if not ChainedPaths then ChainedPaths = {} end
                table.insert(ChainedPaths, { Zone = zone, Path = path, Type = 'Loop', })
            end
            if action == 'normal' then
                if not ChainedPaths then ChainedPaths = {} end
                table.insert(ChainedPaths, { Zone = zone, Path = path, Type = 'Normal', })
            end
            if action == 'reverse' then
                if not ChainedPaths then ChainedPaths = {} end
                table.insert(ChainedPaths, { Zone = zone, Path = path, Type = 'Reverse', })
            end
            if action == 'pingpong' then
                if not ChainedPaths then ChainedPaths = {} end
                table.insert(ChainedPaths, { Zone = zone, Path = path, Type = 'PingPong', })
            end
        end
    else
        MyUI_Utils.PrintOutput('MyUI', nil, "\ay[\at%s\ax] \arInvalid Arguments!", script)
    end
end

local args = { ..., }
local function processArgs()
    if #args == 0 then
        displayHelp()
        return
    end
    if #args == 2 then
        if (args[1] == 'debug' and args[2] == 'hud') or (args[2] == 'debug' and args[1] == 'hud') then
            DEBUG = not DEBUG
            showHUD = not showHUD
            return
        end
    end
    if args[1] == 'debug' then
        DEBUG = not DEBUG
        return
    end
    if args[1] == 'hud' then
        showHUD = not showHUD
        return
    end
end

function Module.Unload()
    mq.unbind('/mypaths')
end

local function Init()
    processArgs()
    -- Get Character Name
    configFile = string.format('%s/MyUI/%s/%s/%s_Configs.lua', mq.configDir, script, MyUI_Server, MyUI_CharLoaded)
    -- Load Settings
    loadSettings()
    loadPaths()
    mq.bind('/mypaths', bind)

    -- Check if ThemeZ exists
    if MyUI_Utils.File.Exists(themezDir) then
        hasThemeZ = true
    end
    currZone = mq.TLO.Zone.ShortName()
    lastZone = currZone
    displayHelp()
    Module.IsRunning = true
    if not loadedExeternally then
        mq.imgui.init(script, Module.RenderGUI)
        Module.LocalLoop()
    end
end

function Module.MainLoop()
    if loadedExeternally then
        ---@diagnostic disable-next-line: undefined-global
        if not MyUI_LoadModules.CheckRunning(Module.IsRunning, Module.Name) then return end
    end

    local justZoned = false
    local cTime = os.time()
    currZone = mq.TLO.Zone.ShortName()

    if (InterruptSet.stopForDist and InterruptSet.stopForCharm and InterruptSet.stopForCombat and InterruptSet.stopForFear and InterruptSet.stopForGM and
            InterruptSet.stopForLoot and InterruptSet.stopForMez and InterruptSet.stopForRoot and InterruptSet.stopForSitting and InterruptSet.stopForXtar and InterruptSet.stopForInvis and InterruptSet.stopForDblInvis) then
        InterruptSet.stopForAll = true
    else
        InterruptSet.stopForAll = false
    end

    if currZone ~= lastZone then
        MyUI_Utils.PrintOutput('MyUI', nil, "\ay[\at%s\ax] \agZone Changed Last: \at%s Current: \ay%s", script, lastZone, currZone)
        lastZone = currZone
        NavSet.SelectedPath = 'None'
        NavSet.doNav = false
        NavSet.autoRecord = false
        NavSet.doLoop = false
        NavSet.doReverse = false
        NavSet.doPingPong = false
        NavSet.doPause = false

        intPauseTime = 0
        InterruptSet.PauseStart = 0
        NavSet.PauseStart = 0
        NavSet.PreviousDoNav = false
        -- Reset navigation state for new zone
        NavSet.CurrentStepIndex = 1
        status = 'Idle'
        NavSet.CurChain = NavSet.CurChain + 1
        if NavSet.ChainStart then
            InterruptSet.interruptFound = false
            -- Start navigation for the new zone if a chain path exists
            if NavSet.CurChain <= #ChainedPaths then
                if ChainedPaths[NavSet.CurChain].Zone == currZone then
                    NavSet.SelectedPath = ChainedPaths[NavSet.CurChain].Path
                    NavSet.CurrentStepIndex = 1
                    if ChainedPaths[NavSet.CurChain].Type == 'Loop' then
                        NavSet.doLoop = true
                        NavSet.doReverse = false
                    elseif ChainedPaths[NavSet.CurChain].Type == 'PingPong' then
                        NavSet.doPingPong = true
                        NavSet.doLoop = true
                    elseif ChainedPaths[NavSet.CurChain].Type == 'Normal' then
                        NavSet.doLoop = false
                        NavSet.doReverse = false
                        NavSet.doPingPong = false
                    elseif ChainedPaths[NavSet.CurChain].Type == 'Reverse' then
                        NavSet.doReverse = true
                        NavSet.doLoop = false
                        NavSet.doPingPong = false
                    end
                    NavSet.doChainPause = false
                    NavSet.doNav = true
                    PathStartClock, PathStartTime = os.date("%I:%M:%S %p"), os.time()
                    status = 'Navigating'
                    MyUI_Utils.PrintOutput('MyUI', nil, '\ay[\at%s\ax] \agStarting navigation for path: \ay%s \agin zone: \ay%s', script, NavSet.SelectedPath, currZone)
                end
            else
                ChainedPaths = {}
                NavSet.CurChain = 0
                NavSet.ChainStart = false
                NavSet.ChainZone = 'Select Zone...'
                NavSet.ChainPath = 'Select Path...'
                PathStartClock, PathStartTime = nil, nil
                NavSet.doNav = false
                NavSet.SelectedPath = 'None'
                NavSet.CurrentStepIndex = 1
            end
        end
        justZoned = true
    end

    if justZoned then return end

    if NavSet.doNav and NavSet.ChainStart and not NavSet.doChainPause then NavSet.ChainPath = NavSet.SelectedPath end

    if NavSet.ChainStart and NavSet.doChainPause then
        for i = 1, #ChainedPaths do
            if i == NavSet.CurChain then
                if ChainedPaths[i].Path == NavSet.ChainPath then
                    if ChainedPaths[i].Zone == currZone then
                        NavSet.doChainPause = false
                        NavSet.SelectedPath = ChainedPaths[i].Path
                        NavSet.ChainPath = NavSet.SelectedPath
                    end
                end
            end
        end
    end

    -- start the chain path
    if NavSet.doNav and not NavSet.ChainStart and #ChainedPaths > 0 then
        NavSet.SelectedPath = ChainedPaths[1].Path
        if ChainedPaths[1].Type == 'Loop' then
            NavSet.doLoop = true
            NavSet.doReverse = false
        elseif ChainedPaths[1].Type == 'PingPong' then
            NavSet.doPingPong = true
            NavSet.doReverse = false
        elseif ChainedPaths[1].Type == 'Normal' then
            NavSet.doLoop = false
            NavSet.doReverse = false
            NavSet.doPingPong = false
        elseif ChainedPaths[1].Type == 'Reverse' then
            NavSet.doReverse = true
            NavSet.doLoop = false
            NavSet.doPingPong = false
        end
        NavSet.ChainStart = true
        NavSet.CurChain = 1
        -- mq.delay(500)
    end

    if not mq.TLO.Me.Sitting() then
        lastHP, lastMP = 0, 0
    end

    if NavSet.SelectedPath == 'None' then
        NavSet.LastPath = nil
        NavSet.doNav = false
        NavSet.doChainPause = false
        NavSet.doPause = false
        NavSet.LoopCount = 0
        NavSet.CurrentStepIndex = 1
        status = 'Idle'
        PathStartClock, PathStartTime = nil, nil
    elseif NavSet.LastPath == nil then
        NavSet.LastPath = NavSet.SelectedPath
        NavSet.CurrentStepIndex = 1
    end

    if NavSet.SelectedPath ~= NavSet.LastPath and NavSet.LastPath ~= nil then
        NavSet.LastPath = NavSet.SelectedPath
        NavSet.LoopCount = 0
        NavSet.CurrentStepIndex = 1
        status = 'Idle'
        PathStartClock, PathStartTime = nil, nil
    end

    -- check interrupts
    InterruptSet.interruptFound = CheckInterrupts()
    if NavSet.doNav and not NavSet.doPause and not justZoned then
        mq.delay(1)
        cTime = os.time()
        local checkTime = InterruptSet.interruptCheck
        -- MyUI_Utils.PrintOutput('MyUI',nil,"interrupt Checked: %s", checkTime)
        -- if cTime - checkTime >= 1 then
        InterruptSet.interruptFound = CheckInterrupts()
        InterruptSet.interruptCheck = os.time()
        if mq.TLO.SpawnCount('gm')() > 0 and InterruptSet.stopForGM and not NavSet.PausedActiveGN then
            MyUI_Utils.PrintOutput('MyUI', nil, "\ay[\at%s\ax] \arGM Detected, \ayPausing Navigation...", script)
            NavSet.doNav = false
            mq.cmdf("/nav stop log=off")
            NavSet.ChainStart = false
            mq.cmd("/multiline ; /squelch /beep; /timed  3, /beep ; /timed 2, /beep ; /timed 1, /beep")
            mq.delay(1)
            status = 'Paused: GM Detected'
            NavSet.PausedActiveGN = true
        end
        if status == 'Paused for Invis.' or status == 'Paused for Double Invis.' then
            if settings[script].InvisAction ~= '' then
                mq.cmd(settings[script].InvisAction)
                -- local iDelay = settings[script].InvisDelay * 1000
                -- mq.delay(iDelay)
            end
        end
        -- end
    end

    if not InterruptSet.interruptFound and not NavSet.doPause and not NavSet.doChainPause then
        if NavSet.doNav and NavSet.PreviousDoNav ~= NavSet.doNav then
            -- Reset the coroutine since doNav changed from false to true
            co = coroutine.create(NavigatePath)
        end
        curTime = os.time()

        -- If the coroutine is not dead, resume it
        if coroutine.status(co) ~= "dead" then
            -- Check if we need to pause
            if InterruptSet.PauseStart > 0 and NavSet.PauseStart == 0 then
                curTime = os.time()

                local diff = curTime - InterruptSet.PauseStart
                if diff > intPauseTime then
                    -- Time is up, resume the coroutine and reset the timer values

                    -- MyUI_Utils.PrintOutput('MyUI',nil,"Pause time: %s Start Time %s Current Time: %s Difference: %s", pauseTime, InterruptSet.PauseStart, curTime, diff)
                    intPauseTime = 0
                    InterruptSet.PauseStart = 0
                    local success, message = coroutine.resume(co, NavSet.SelectedPath)
                    if not success then
                        MyUI_Utils.PrintOutput('MyUI', nil, "Error: " .. message)
                        -- Reset coroutine on error
                        co = coroutine.create(NavigatePath)
                    end
                end
            elseif InterruptSet.PauseStart > 0 and NavSet.PauseStart > 0 then
                curTime = os.time()
                local diff = curTime - InterruptSet.PauseStart
                if diff > intPauseTime then
                    -- Interrupt is over, reset the values
                    intPauseTime = 0
                    InterruptSet.PauseStart = 0
                    --reset wp pause timer
                    NavSet.PauseStart = os.time()
                    status = string.format('Paused: Interrupt over Restarting WP %s delay', curWpPauseTime)
                end
            elseif InterruptSet.PauseStart == 0 and NavSet.PauseStart > 0 then
                curTime = os.time()
                local diff = curTime - NavSet.PauseStart
                if diff > curWpPauseTime then
                    -- Time is up, resume the coroutine and reset the timer values
                    -- MyUI_Utils.PrintOutput('MyUI',nil,"Pause time: %s Start Time %s Current Time: %s Difference: %s", pauseTime, InterruptSet.PauseStart, curTime, diff)
                    curWpPauseTime = 0
                    NavSet.PauseStart = 0
                    local success, message = coroutine.resume(co, NavSet.SelectedPath)
                    if not success then
                        MyUI_Utils.PrintOutput('MyUI', nil, "Error: " .. message)
                        -- Reset coroutine on error
                        co = coroutine.create(NavigatePath)
                    end
                end
            else
                -- Resume the coroutine we are do not need to pause
                local success, message = coroutine.resume(co, NavSet.SelectedPath)
                if not success then
                    MyUI_Utils.PrintOutput('MyUI', nil, "Error: " .. message)
                    -- Reset coroutine on error
                    co = coroutine.create(NavigatePath)
                end
            end
        else
            -- If the coroutine is dead, create a new one
            co = coroutine.create(NavigatePath)
        end
    elseif not NavSet.doNav and not NavSet.autoRecord then
        -- Reset state when doNav is false
        NavSet.LoopCount = 0
        if not NavSet.ChainStart then
            NavSet.doPause = false
            status = 'Idle'
        end
        NavSet.CurrentStepIndex = 1

        PathStartClock, PathStartTime = nil, nil
    end

    -- Update previousDoNav to the current state
    NavSet.PreviousDoNav = NavSet.doNav

    if #ChainedPaths > 0 and not NavSet.doNav and NavSet.ChainStart then
        -- for i = 1, #Chain do
        if ChainedPaths[NavSet.CurChain].Path == NavSet.ChainPath and NavSet.CurChain < #ChainedPaths then
            if ChainedPaths[NavSet.CurChain + 1].Zone ~= currZone then
                status = 'Next Path Waiting to Zone: ' .. ChainedPaths[NavSet.CurChain + 1].Zone
                NavSet.doPause = true
            else
                NavSet.SelectedPath = ChainedPaths[NavSet.CurChain + 1].Path
                NavSet.CurrentStepIndex = 1
                NavSet.ChainPath = NavSet.SelectedPath
                NavSet.doChainPause = false
                if ChainedPaths[NavSet.CurChain + 1].Type == 'Loop' then
                    NavSet.doLoop = true
                    NavSet.doReverse = false
                elseif ChainedPaths[NavSet.CurChain + 1].Type == 'PingPong' then
                    NavSet.doPingPong = true
                    NavSet.doLoop = true
                elseif ChainedPaths[NavSet.CurChain + 1].Type == 'Normal' then
                    NavSet.doLoop = false
                    NavSet.doReverse = false
                    NavSet.doPingPong = false
                elseif ChainedPaths[NavSet.CurChain + 1].Type == 'Reverse' then
                    NavSet.doReverse = true
                    NavSet.doLoop = false
                    NavSet.doPingPong = false
                end
                NavSet.CurChain = NavSet.CurChain + 1
                NavSet.doNav = true
                PathStartClock, PathStartTime = os.date("%I:%M:%S %p"), os.time()
            end
        elseif ChainedPaths[NavSet.CurChain].Path == NavSet.ChainPath and NavSet.CurChain == #ChainedPaths then
            if not NavSet.ChainLoop then
                NavSet.ChainStart = false
                if ChainedPaths[NavSet.CurChain].Type == 'Normal' or ChainedPaths[NavSet.CurChain].Type == 'Reverse' then
                    NavSet.doNav = false
                    NavSet.doChainPause = false
                    NavSet.ChainStart = false
                    NavSet.ChainPath = 'Select...'
                    ChainedPaths = {}
                end
            else
                NavSet.CurChain = 0
                NavSet.ChainStart = false
                NavSet.doChainPause = false
                NavSet.doNav = true
            end
        end
        -- end
    end

    if NavSet.autoRecord then
        AutoRecordPath(NavSet.SelectedPath)
    end

    if deleteWP then
        RemoveWaypoint(NavSet.SelectedPath, deleteWPStep)
        if DEBUG then
            table.insert(debugMessages,
                {
                    Time = os.date("%H:%M:%S"),
                    Zone = mq.TLO.Zone.ShortName(),
                    Path = NavSet.SelectedPath,
                    WP = 'Delete  #' .. deleteWPStep,
                    Status = 'Waypoint #' ..
                        deleteWPStep .. ' Removed Successfully!',
                })
        end
        deleteWPStep = 0
        deleteWP = false
    end

    if DEBUG then
        if lastStatus ~= status then
            local statTxt = status
            if status:find("Distance") then
                statTxt = statTxt:gsub("Distance:", "Dist:")
            end
            table.insert(debugMessages,
                { Time = os.date("%H:%M:%S"), WP = NavSet.CurrentStepIndex, Status = statTxt, Path = NavSet.SelectedPath, Zone = mq.TLO.Zone.ShortName(), })
            lastStatus = status
        end
        while #debugMessages > 100 do
            table.remove(debugMessages, 1)
        end
    else
        debugMessages = {}
    end
    -- Process ImGui Window Flag Changes
    winFlags = locked and bit32.bor(ImGuiWindowFlags.NoMove, ImGuiWindowFlags.MenuBar) or bit32.bor(ImGuiWindowFlags.None, ImGuiWindowFlags.MenuBar)
    winFlags = aSize and bit32.bor(winFlags, ImGuiWindowFlags.AlwaysAutoResize, ImGuiWindowFlags.MenuBar) or winFlags
end

function Module.LocalLoop()
    while Module.IsRunning do
        Module.MainLoop()
        mq.delay(1)
    end
end

if mq.TLO.EverQuest.GameState() ~= "INGAME" then
    printf("\aw[\at%s\ax] \arNot in game, \ayTry again later...", script)
    mq.exit()
end

Init()

return Module
