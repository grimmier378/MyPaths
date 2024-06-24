--[[
    Title: My Paths
    Author: Grimmier
    Includes: 
    Description: This script is a simple pathing script that allows you to record and navigate paths in the game. 
                You can create, save, and edit paths in a zone and load them for navigation.
]]

-- Load Libraries
local mq = require('mq')
local ImGui = require('ImGui')
local LoadTheme = require('lib.theme_loader')
local Icon = require('mq.ICONS')
local base64 = require('base64') -- Ensure you have a base64 module available

-- Variables
local script = 'MyPaths' -- Change this to the name of your script
local meName -- Character Name
local themeName = 'Default'
local themeID = 1
local theme, defaults, settings, debugMessages = {}, {}, {}, {}
local Paths, ChainedPaths = {}, {}
local newPath = ''
local curTime = os.time()
local lastTime = curTime
local deleteWP, deleteWPStep = false, 0
local status, lastStatus = 'Idle', ''
local wpLoc = ''
local currZone, lastZone = '', ''
local lastHP, lastMP, pauseTime = 0, 0, 0
local zoningHideGUI = false
local ZoningPause
local lastRecordedWP = ''
local PathStartClock,PathStartTime = nil, nil
local NavSet = {
    ChainPath = '',
    ChainStart = false,
    SelectedPath = 'None',
    ChainZone = '',
    LastPath = nil,
    CurChain = 0,
    doChainPause = false,
    autoRecord = false,
    doNav = false,
    doSingle = false,
    doLoop = false,
    doReverse = false,
    doPingPong = false,
    doPause = false,
    RecordDelay = 5,
    StopDist = 30,
    WpPause = 1,
    CurrentStepIndex = 1,
    LoopCount = 0,
    RecordMinDist = 25,
    PreviousDoNav = false,
    PausedActiveGN = false,
}

local InterruptSet = {
    interruptFound = false,
    reported = false,
    interruptDelay = 2,
    PauseStart = 0,
    openDoor = false,
    stopForAll = true,
    stopForGM = true,
    stopForSitting = true,
    stopForCombat = true,
    stopForGoupDist = 100,
    stopForDist = false,
    stopForXtar = true,
    stopForFear = true,
    stopForCharm = true,
    stopForMez = true,
    stopForRoot = true,
    stopForLoot = true,
    interruptCheck = 0,
}

-- GUI Settings
local winFlags = bit32.bor(ImGuiWindowFlags.None, ImGuiWindowFlags.MenuBar)
local RUNNING, DEBUG = true, false
local showMainGUI, showConfigGUI, showDebugTab, showHUD = true, false, true, false
local scale = 1
local aSize, locked, hasThemeZ = false, false, false
local hudTransparency = 0.5
local hudMouse = true

-- File Paths
local themeFile = string.format('%s/MyUI/MyThemeZ.lua', mq.configDir)
local configFile = string.format('%s/MyUI/%s/%s_Configs.lua', mq.configDir, script, script)
local pathsFile = string.format('%s/MyUI/%s/%s_Paths.lua', mq.configDir, script, script)
local themezDir = mq.luaDir .. '/themez/init.lua'

-- Default Settings
defaults = {
    Scale = 1.0,
    LoadTheme = 'Default',
    locked = false,
    AutoSize = false,
    stopForGM = true,
    RecordDlay = 5,
    WatchMana = 60,
    WatchType = 'None',
    WatchHealth = 90,
    GroupWatch = false,
    HeadsUpTransparency = 0.5,
    StopDistance = 30,
    PauseStops = 1,
    InterruptDelay = 1,
    RecordMinDist = 25,
}

local manaClass = {
    'WIZ',
    'MAG',
    'NEC',
    'ENC',
    'DRU',
    'SHM',
    'CLR',
    'BST',
    'BRD',
    'PAL',
    'RNG',
    'SHD',
}

-------- Helper Functions --------
---comment Check to see if the file we want to work on exists.
---@param name string -- Full Path to file
---@return boolean -- returns true if the file exists and false otherwise
local function File_Exists(name)
    local f=io.open(name,"r")
    if f~=nil then io.close(f) return true else return false end
end

local function loadTheme()
    -- Check for the Theme File
    if File_Exists(themeFile) then
        theme = dofile(themeFile)
    else
        -- Create the theme file from the defaults
        theme = require('themes') -- your local themes file incase the user doesn't have one in config folder
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

local function loadPaths()
    -- Check for the Paths File
    Paths = {} -- Reset the Paths Table
    if File_Exists(pathsFile) then
        Paths = dofile(pathsFile)
    else
        -- Create the paths file from the defaults
        Paths = require('paths') -- your local paths file incase the user doesn't have one in config folder
        mq.pickle(pathsFile, Paths)
    end
    local needsUpdate = false
    for zone, data in pairs(Paths) do
        for path, wp in pairs(data) do
            for i, wData in pairs(wp) do
                if wData.delay == nil then
                    wData.delay = 0
                    needsUpdate = true
                end
                if wData.cmd == nil then
                    wData.cmd = ''
                    needsUpdate = true
                end
                if wData.door == nil then
                    wData.door = false
                    needsUpdate = true
                end
                if wData.doorRev == nil then
                    wData.doorRev = false
                    needsUpdate = true
                end
            end
        end
    end
    if needsUpdate then mq.pickle(pathsFile, Paths) end
end

local function SavePaths()
    mq.pickle(pathsFile, Paths)
end

local function loadSettings()
    local newSetting = false -- Check if we need to save the settings file

    -- Check Settings File_Exists
    if not File_Exists(configFile) then
        -- Create the settings file from the defaults
        settings[script] = defaults
        mq.pickle(configFile, settings)
        loadSettings()
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

    if settings[script].locked == nil then
        settings[script].locked = false
        newSetting = true
    end

    if settings[script].InterruptDelay == nil then
        settings[script].InterruptDelay = InterruptSet.interruptDelay
        newSetting = true
    end

    if settings[script].stopForGM == nil then
        settings[script].stopForGM = InterruptSet.stopForGM
        newSetting = true
    end

    if settings[script].RecordMinDist == nil then
        settings[script].RecordMinDist = NavSet.RecordMinDist
        newSetting = true
    end

    if settings[script].RecordDelay == nil then
        settings[script].RecordDelay = NavSet.RecordDelay
        newSetting = true
    end

    if settings[script].Scale == nil then
        settings[script].Scale = 1
        newSetting = true
    end

    if not settings[script].LoadTheme then
        settings[script].LoadTheme = 'Default'
        newSetting = true
    end

    if settings[script].WatchMana == nil then
        settings[script].WatchMana = 60
        newSetting = true
    end

    if settings[script].WatchHealth == nil then
        settings[script].WatchHealth = 90
        newSetting = true
    end

    if settings[script].WatchType == nil then
        settings[script].WatchType = 'None'
        newSetting = true
    end

    if settings[script].GroupWatch == nil then
        settings[script].GroupWatch = false
        newSetting = true
    end

    if settings[script].MouseHUD == nil then
        settings[script].MouseHUD = hudMouse
        newSetting = true
    end

    if settings[script].AutoSize == nil then
        settings[script].AutoSize = aSize
        newSetting = true
    end

    if settings[script].PauseStops == nil then
        settings[script].PauseStops = NavSet.WpPause
        newSetting = true
    end

    if settings[script].HeadsUpTransparency == nil then
        settings[script].HeadsUpTransparency = hudTransparency
        newSetting = true
    end

    if settings[script].StopDistance == nil then
        settings[script].StopDistance = NavSet.StopDist
        newSetting = true
    end

    if settings[script].Interrupts == nil then
        settings[script].Interrupts = InterruptSet
        newSetting = true
    end

    if settings[script].Interrupts.stopForGoupDist == nil then
        settings[script].Interrupts.stopForGoupDist = 100
        newSetting = true
    end

    if settings[script].Interrupts.stopForDist == nil then
        settings[script].Interrupts.stopForDist = false
        newSetting = true
    end
    -- Load the theme
    loadTheme()
    InterruptSet = settings[script].Interrupts
    -- Set the settings to the variables
    NavSet.StopDist = settings[script].StopDistance
    NavSet.WpPause = settings[script].PauseStops
    NavSet.RecordMinDist = settings[script].RecordMinDist
    InterruptSet.stopForGM = settings[script].stopForGM
    InterruptSet.stopForDist = settings[script].Interrupts.stopForDist
    InterruptSet.interruptDelay = settings[script].InterruptDelay
    hudTransparency = settings[script].HeadsUpTransparency
    aSize = settings[script].AutoSize
    hudMouse = settings[script].MouseHUD
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
        distToLast = mq.TLO.Math.Distance(string.format("%s:%s", lastRecordedWP, loc))()
        if distToLast < NavSet.RecordMinDist and NavSet.autoRecord then
            status = "Recording: Distance to Last WP is less than "..NavSet.RecordMinDist.."!"
            if DEBUG and not InterruptSet.reported then
                table.insert(debugMessages, {Time = os.date("%H:%M:%S"), Zone = zone, Path = name, WP = 'Record WP', Status = 'Distance to Last WP is less than '..NavSet.RecordMinDist..' units!'})
                InterruptSet.reported = true
            end
            return
        end
    end
    if tmp[index] ~= nil then
        if tmp[index].loc == loc then return end
        table.insert(tmp, {step = index + 1, loc = loc, delay = 0, cmd = ''})
        lastRecordedWP = loc
        index = index + 1
        InterruptSet.reported = false
    else
        table.insert(tmp, {step = 1, loc = loc, delay = 0, cmd = ''})
        index = 1
        lastRecordedWP = loc
        InterruptSet.reported = false
    end
    Paths[zone][name] = tmp
    if NavSet.autoRecord then
        status = "Recording: Waypoint #"..index.." Added!"
    end
    if DEBUG then table.insert(debugMessages, {Time = os.date("%H:%M:%S"), Zone = zone, Path = name, WP = "Add WP#"..index, Status = 'Waypoint #'..index..' Added Successfully!'}) end
    SavePaths()
end

local function RemoveWaypoint(name, step)
    local zone = mq.TLO.Zone.ShortName()
    if not Paths[zone] then return end
    if not Paths[zone][name] then return end
    local tmp = Paths[zone][name]
    if not tmp then return end
    for i, data in pairs(tmp) do
        if data.step == step then
            table.remove(tmp, i)
        end
    end
    for i, data in pairs(tmp) do
        data.step = i
    end
    Paths[zone][name] = tmp
    SavePaths()
end

local function ClearWaypoints(name)
    local zone = mq.TLO.Zone.ShortName()
    if not Paths[zone] then return end
    if not Paths[zone][name] then return end
    Paths[zone][name] = {}
    if DEBUG then table.insert(debugMessages, {Time = os.date("%H:%M:%S"), Zone = zone, Path = name, WP = 'All Waypoints', Status = 'All Waypoints Cleared Successfully!'}) end
    SavePaths()
end

local function DeletePath(name)
    local zone = mq.TLO.Zone.ShortName()
    if not Paths[zone] then return end
    if not Paths[zone][name] then return end
    Paths[zone][name] = nil
    if DEBUG then table.insert(debugMessages, {Time = os.date("%H:%M:%S"), Zone = zone, Path = name, WP = 'Path Deleted', Status = 'Path ['..name..'] Deleted Successfully!'}) end
    SavePaths()
end

local function CreatePath(name)
    local zone = mq.TLO.Zone.ShortName()
    if not Paths[zone] then Paths[zone] = {} end
    if not Paths[zone][name] then Paths[zone][name] = {} end
    if DEBUG then table.insert(debugMessages, {Time = os.date("%H:%M:%S"), Zone = zone, Path = name, WP = 'Path Created', Status = 'Path ['..name..'] Created Successfully!'}) end
    SavePaths()
end

local function AutoRecordPath(name)
    curTime = os.time()
    if curTime - lastTime > NavSet.RecordDelay then
        RecordWaypoint(name)
        lastTime = curTime
    end
    SavePaths()
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
        for x = 1 , #manaClass do
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
                for i = 1, gsize- 1 do
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
                for i = 1, gsize- 1 do
                    if member(i).Present() then
                        if member(i).PctHPs() < settings[script].WatchHealth then
                            status = string.format('Paused for Health Watch.')
                            return true
                        end
                        for x = 1 , #manaClass do
                            if member(i).Class.ShortName() == manaClass[x] then
                                if member(i).PctMana() < settings[script].WatchMana then
                                    status = string.format('Paused for Mana Watch.')
                                    return true
                                end
                            end
                        end
                    end
                    if mq.TLO.Me.PctHPs() < settings[script].WatchHealth then
                        status = string.format('Paused for Health Watch.')
                        mq.TLO.Me.Sit()
                        return true
                    end
                    for x = 1 , #manaClass do
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

local interruptInProcess = false
local function CheckInterrupts()
    if not NavSet.doNav then return false end
    local xCount = mq.TLO.Me.XTarget() or 0
    local flag = false
    if mq.TLO.Window('LootWnd').Open() and InterruptSet.stopForLoot then
        if not interruptInProcess then mq.cmdf("/squelch /nav stop") interruptInProcess = true end
        status = 'Paused for Looting.'
        flag = true
    elseif mq.TLO.Window('AdvancedLootWnd').Open() and InterruptSet.stopForLoot then
        if not interruptInProcess then mq.cmdf("/squelch /nav stop") interruptInProcess = true end
        status = 'Paused for Looting.'
        flag = true
    elseif mq.TLO.Me.Combat() and InterruptSet.stopForCombat then
        if not interruptInProcess then mq.cmdf("/squelch /nav stop") interruptInProcess = true end
        status = 'Paused for Combat.'
        flag = true
    elseif xCount > 0 and InterruptSet.stopForXtar then
        for i = 1, mq.TLO.Me.XTargetSlots() do
            if mq.TLO.Me.XTarget(i) ~= nil then
                if (mq.TLO.Me.XTarget(i).ID() ~= 0 and mq.TLO.Me.XTarget(i).Type() ~= 'PC' and mq.TLO.Me.XTarget(i).Master.Type() ~= "PC") then
                    if not interruptInProcess then mq.cmdf("/squelch /nav stop") interruptInProcess = true end
                    status = string.format('Paused for XTarget. XTarg Count %s', mq.TLO.Me.XTarget())
                    flag = true
                end
            end
        end
    elseif mq.TLO.Me.Sitting() == true and InterruptSet.stopForSitting then
        if not interruptInProcess then mq.cmdf("/squelch /nav stop") interruptInProcess = true end
        mq.delay(30)
        local curHP, curMP = mq.TLO.Me.PctHPs(), mq.TLO.Me.PctMana() or 0
        if curHP - lastHP > 10 or curMP - lastMP > 10 then
            lastHP, lastMP = curHP, curMP
            status = string.format('Paused for Sitting. HP %s MP %s', curHP, curMP)
        end
        flag = true
    elseif mq.TLO.Me.Rooted() and InterruptSet.stopForRoot then
        if not interruptInProcess then mq.cmdf("/squelch /nav stop") interruptInProcess = true end
        status = 'Paused for Rooted.'
        flag = true
    elseif mq.TLO.Me.Feared() and InterruptSet.stopForFear then
        if not interruptInProcess then mq.cmdf("/squelch /nav stop") interruptInProcess = true end
        status = 'Paused for Feared.'
        flag = true
    elseif mq.TLO.Me.Mezzed() and InterruptSet.stopForMez then
        if not interruptInProcess then mq.cmdf("/squelch /nav stop") interruptInProcess = true end
        status = 'Paused for Mezzed.'
        flag = true
    elseif mq.TLO.Me.Charmed() and InterruptSet.stopForCharm then
        if not interruptInProcess then mq.cmdf("/squelch /nav stop") interruptInProcess = true end
        status = 'Paused for Charmed.'
        flag = true
    elseif mq.TLO.Me.Zoning() then
        if not interruptInProcess then mq.cmdf("/squelch /nav stop") interruptInProcess = true end
        status = 'Paused for Zoning.'
        lastZone = ''
        flag = true
    elseif settings[script].GroupWatch == true and groupWatch(settings[script].WatchType) then
        flag =  true
        if flag and not interruptInProcess then mq.cmdf("/squelch /nav stop") interruptInProcess = true end
    elseif InterruptSet.stopForDist == true and groupDistance() then
        flag = true
        if flag and not interruptInProcess then mq.cmdf("/squelch /nav stop") interruptInProcess = true end
    end
    if flag then
        InterruptSet.PauseStart = os.time()
        pauseTime = InterruptSet.interruptDelay
    else
        interruptInProcess = false
    end

    return flag
end

--------- Navigation Functions --------

local function ToggleSwitches()
    mq.cmdf("/squelch /multiline ; /doortarget; /timed 15, /click left door; /timed 25, /doortarget clear")
    mq.delay(750)
    InterruptSet.openDoor = not InterruptSet.openDoor
end

local function FindIndexClosestWaypoint(table)
    local tmp = table
    local closest = 999999
    local closestLoc = 1
    if tmp == nil then return closestLoc end
    for i = 1,  #tmp do
        local tmpLoc = string.format("%s:%s", tmp[i].loc, mq.TLO.Me.LocYXZ())
        tmpLoc = tmpLoc:gsub(",", " ")
        local dist = mq.TLO.Math.Distance(tmpLoc)()
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
    else table.sort(tmp, function(a, b) return a.step < b.step end) end
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
        table.insert(debugMessages, {Time = os.date("%H:%M:%S"), Zone = zone, Path = name, WP = 'Loop Started', Status = 'Loop Started!'})
    end
    if #ChainedPaths > 0 and not NavSet.ChainStart then NavSet.ChainPath = NavSet.SelectedPath NavSet.ChainStart = true end
    while NavSet.doNav do
        local tmp = sortPathsTable(zone, name)
        if tmp == nil then
            NavSet.doNav = false
            status = 'Idle'
            return
        end
        for i = startNum , #tmp do
            if NavSet.doSingle then i = NavSet.CurrentStepIndex end
            NavSet.CurrentStepIndex = i
            if not NavSet.doNav then
                return
            end
            local tmpLoc = string.format("%s:%s", tmp[i].loc, mq.TLO.Me.LocYXZ())
            wpLoc = tmp[i].loc
            tmpLoc = tmpLoc:gsub(",", " ")
            -- Find the position of the last comma
            local comma_pos = tmpLoc:match(".*(),") 

            -- Extract the substring up to the last comma
            if comma_pos then
                tmpLoc = tmpLoc:sub(1, comma_pos - 1)
            end
            local tmpDist = mq.TLO.Math.Distance(tmpLoc)() or 0
            mq.cmdf("/squelch /nav locyx %s | distance %s", tmpLoc, NavSet.StopDist)
            status = "Nav to WP #: "..tmp[i].step.." Distance: "..string.format("%.2f",tmpDist)
            mq.delay(1)
            -- mq.delay(3000, function () return mq.TLO.Me.Speed() > 0 end)
            -- coroutine.yield()  -- Yield here to allow updates
            while mq.TLO.Math.Distance(tmpLoc)() > NavSet.StopDist do
                if not NavSet.doNav then
                    return
                end
                if currZone ~= lastZone then
                    NavSet.SelectedPath = 'None'
                    NavSet.doNav = false
                    pauseTime = 0
                    InterruptSet.PauseStart = 0

                    return
                end
                if interruptInProcess then
                    coroutine.yield()
                elseif mq.TLO.Me.Speed() == 0 then
                    mq.delay(1)
                    if not mq.TLO.Me.Sitting() then
                        mq.cmdf("/squelch /nav locyx %s | distance %s", tmpLoc, NavSet.StopDist)
                        tmpLoc = string.format("%s:%s", tmp[i].loc, mq.TLO.Me.LocYXZ())
                        tmpLoc = tmpLoc:gsub(",", " ")
                        tmpDist = mq.TLO.Math.Distance(tmpLoc)() or 0
                        status = "Nav to WP #: "..tmp[i].step.." Distance: "..string.format("%.2f",tmpDist)
                        coroutine.yield()
                    end
                end
                mq.delay(1)
                tmpLoc = string.format("%s:%s", wpLoc, mq.TLO.Me.LocYXZ())
                tmpLoc = tmpLoc:gsub(",", " ")
                coroutine.yield()  -- Yield here to allow updates
            end
            mq.cmdf("/squelch /nav stop")
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
                table.insert(debugMessages, {Time = os.date("%H:%M:%S"), Zone = zone, Path = name, WP = 'Command', Status = 'Executing Command: '..tmp[i].cmd})
                if tmp[i].cmd:find("/mypaths stop") then NavSet.doNav = false end
                mq.delay(1)
                mq.cmdf(tmp[i].cmd)
                mq.delay(1)
                coroutine.yield()
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
                pauseTime = tmp[i].delay
                InterruptSet.PauseStart = os.time()
                coroutine.yield()
                -- coroutine.yield()  -- Yield here to allow updates
            elseif NavSet.WpPause > 0 then
                status = string.format("Global Paused %s seconds at WP #: %s", NavSet.WpPause, tmp[i].step)
                pauseTime = NavSet.WpPause
                InterruptSet.PauseStart = os.time()
                coroutine.yield()
                -- coroutine.yield()  -- Yield here to allow updates
            else
                if not InterruptSet.interruptFound then
                    pauseTime = 0
                    InterruptSet.PauseStart = 0
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
            table.insert(debugMessages, {Time = os.date("%H:%M:%S"), Zone = zone, Path = name, WP = 'Loop #'..NavSet.LoopCount, Status = 'Loop #'..NavSet.LoopCount..' Completed!'})
            NavSet.CurrentStepIndex = 1
            startNum = 1
            if NavSet.doPingPong then
                NavSet.doReverse = not NavSet.doReverse
            end
        end
    end
end

local co = coroutine.create(NavigatePath)

function ZoningPause()
    status = 'Zoning'
    print("Zoning")
    table.insert(debugMessages, {Time = os.date("%H:%M:%S"), Zone = 'Zoning', Path = "Zoning", WP = 'Zoning', Status = 'Zoning'})
    mq.delay(1)
    while mq.TLO.Me.Zoning() == true do
        NavSet.doNav = false
        if coroutine.status(co) ~= "dead" then
            local success, message = coroutine.close(co)
            if not success then
                print("Error: " .. message)
                break
            end
        else
            -- If the coroutine is dead, create a new one
            co = coroutine.create(NavigatePath)
        end
        NavSet.SelectedPath = 'None'
        NavSet.CurrentStepIndex = 1
        InterruptSet.PauseStart = 0
        pauseTime = 0
        zoningHideGUI = true
        showMainGUI = false
        lastZone = ''
        mq.delay(1000, function () return mq.TLO.Me.Zoning() == false end)
    end
end

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
    local serialized_paths = serialize_table({[zone] = {[pathname] = paths}})
    return base64.enc('return ' .. serialized_paths)
end

local function import_paths(import_string)
    if not import_string or import_string == '' then return end
    local decoded = base64.dec(import_string)
    if not decoded or decoded == '' then return end
    local ok, imported_paths = pcall(load(decoded))
    if not ok or type(imported_paths) ~= 'table' then
        print('\arERROR: Failed to import paths\ax')
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
    end
    SavePaths()
    return imported_paths
end

-------- GUI Functions --------
local transFlag = false
local importString = ''
local tmpCmd = ''
local exportZone, exportPathName = '', ''

local function Draw_GUI()
    -- Main Window
    if showMainGUI then
        if mq.TLO.Me.Zoning() then return end
        -- local currZone = mq.TLO.Zone.ShortName()
        -- Set Window Name
        local winName = string.format('%s##Main_%s', script, meName)
        -- Load Theme
        local ColorCount, StyleCount = LoadTheme.StartTheme(theme.Theme[themeID])
        -- Create Main Window
        local openMain, showMain = ImGui.Begin(winName,true,winFlags)
        -- Check if the window is open
        if not openMain then
            showMainGUI = false
        end
        -- Check if the window is showing
        if showMain then
            local tmpTable = sortPathsTable(currZone, NavSet.SelectedPath) or {}
            local closestWaypointIndex = FindIndexClosestWaypoint(tmpTable)
            local curWPTxt = 1
            if tmpTable[NavSet.CurrentStepIndex] ~= nil then
                curWPTxt = tmpTable[NavSet.CurrentStepIndex].step or 0
            end

            if ImGui.BeginMenuBar() then
                if ImGui.MenuItem(Icon.FA_COG) then
                    -- Toggle Config Window
                    showConfigGUI = not showConfigGUI
                end
                if ImGui.IsItemHovered() then
                    ImGui.SetTooltip("Settings")
                end
                ImGui.SameLine()
                local lIcon = locked and Icon.FA_LOCK or Icon.FA_UNLOCK
                
                if ImGui.MenuItem(lIcon) then
                        -- Toggle Config Window
                    locked = not locked
                    settings[script].locked = locked
                    mq.pickle(configFile, settings)
                end
                if ImGui.IsItemHovered() then
                    ImGui.SetTooltip("Toggle Lock Window")
                end
                if DEBUG then
                    ImGui.SameLine()
                    
                    if ImGui.MenuItem(Icon.FA_BUG) then
                        showDebugTab = not showDebugTab
                    end
                    if ImGui.IsItemHovered() then
                        ImGui.SetTooltip("Debug")
                    end
                end
                ImGui.SameLine()
                
                if ImGui.MenuItem(Icon.MD_TV) then
                    showHUD = not showHUD
                end
                if ImGui.IsItemHovered() then
                    ImGui.SetTooltip("Toggle Heads Up Display")
                end
                ImGui.SameLine(ImGui.GetWindowWidth() - 30)
                
                if ImGui.MenuItem(Icon.FA_WINDOW_CLOSE) then
                    RUNNING = false
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
                ImGui.TextColored(1,0,0,1,"!!%s GM in Zone %s!!", Icon.FA_BELL,Icon.FA_BELL)
                end
            end
            if not showHUD then
            -- Main Window Content 
            ImGui.Text("Current Zone: ")
            ImGui.SameLine()
            ImGui.TextColored(0,1,0,1,"%s", currZone)
            ImGui.SameLine()
            ImGui.Text("Selected Path: ")
            ImGui.SameLine()
            ImGui.TextColored(0,1,1,1,"%s", NavSet.SelectedPath)
            
            ImGui.Text("Current Loc: ")
            ImGui.SameLine()
            ImGui.TextColored(1,1,0,1,"%s", mq.TLO.Me.LocYXZ())
            if NavSet.doNav then
                ImGui.Text("Current Destination Waypoint: ")
                ImGui.SameLine()
                ImGui.TextColored(0,1,0,1,"%s", curWPTxt)
                ImGui.Text("Distance to Waypoint: ")
                ImGui.SameLine()
                if tmpTable[NavSet.CurrentStepIndex] ~= nil then
                    ImGui.TextColored(0,1,1,1,"%.2f", mq.TLO.Math.Distance(string.format("%s:%s", tmpTable[NavSet.CurrentStepIndex].loc:gsub(",", " "), mq.TLO.Me.LocYXZ()))())
                end
            end
            ImGui.Separator()
        end
            if NavSet.SelectedPath ~= 'None' or #ChainedPaths > 0 then
                if NavSet.doPause and NavSet.doNav then
                    ImGui.PushStyleColor(ImGuiCol.Button, ImVec4(0.4, 1, 0.4, 0.4))
                    if ImGui.Button('Resume') then
                        NavSet.doPause = false
                        NavSet.PausedActiveGN = false
                        table.insert(debugMessages, {Time = os.date("%H:%M:%S"), Zone = currZone, Path = NavSet.SelectedPath, WP = 'Resume', Status = 'Resumed Navigation!'})
                    end
                    ImGui.PopStyleColor()
                    if ImGui.IsItemHovered() then
                        ImGui.SetTooltip("Resume Navigation")
                    end
                    ImGui.SameLine()
                elseif not NavSet.doPause and NavSet.doNav then
                    ImGui.PushStyleColor(ImGuiCol.Button, ImVec4(1, 0.4, 0.4, 0.4))
                    if ImGui.Button(Icon.FA_PAUSE) then
                        NavSet.doPause = true
                        mq.cmd("/squelch /nav stop")
                        table.insert(debugMessages, {Time = os.date("%H:%M:%S"), Zone = currZone, Path = NavSet.SelectedPath, WP = 'Pause', Status = 'Paused Navigation!'})
                    end
                    ImGui.PopStyleColor()
                    if ImGui.IsItemHovered() then
                        ImGui.SetTooltip("Pause Navigation")
                    end
                    
                    ImGui.SameLine()
                end
                if NavSet.doNav then
                    ImGui.PushStyleColor(ImGuiCol.Button, ImVec4(1.0, 0.4, 0.4, 0.4))
                    if ImGui.Button(Icon.FA_STOP) then
                        NavSet.doNav = false
                        NavSet.ChainStart = false
                        mq.cmdf("/squelch /nav stop")
                        PathStartClock,PathStartTime = nil, nil
                    end
                    ImGui.PopStyleColor()

                    if ImGui.IsItemHovered() then
                        ImGui.SetTooltip("Stop Navigation")
                    end
                    ImGui.SameLine()
                else
                    ImGui.PushStyleColor(ImGuiCol.Button, ImVec4(0.4, 1, 0.4, 0.4))
                    if ImGui.Button(Icon.FA_PLAY) then
                        NavSet.PausedActiveGN = false
                        NavSet.doNav = true
                        PathStartClock,PathStartTime = os.date("%I:%M:%S %p"), os.time()
                    end
                    ImGui.PopStyleColor()
                    if ImGui.IsItemHovered() then
                        ImGui.SetTooltip("Start Navigation")
                    end
                    ImGui.SameLine()
                end

            end
        
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
                local tmpDist = mq.TLO.Math.Distance(string.format("%s:%s", wpLoc:gsub(",", " "), mq.TLO.Me.LocYXZ()))() or 0
                local dist = string.format("%.2f",tmpDist)
                local tmpStatus = status
                if tmpStatus:find("Distance") then
                    tmpStatus = tmpStatus:sub(1, tmpStatus:find("Distance:") - 1)
                    tmpStatus = string.format("%s Distance: %s",tmpStatus,dist)
                    ImGui.TextColored(ImVec4(1,1,0,1), tmpStatus)
                end
            end
            if PathStartClock ~= nil then
                ImGui.Text("Start Time: ")
                ImGui.SameLine()
                ImGui.TextColored(0,1,1,1,"%s", PathStartClock)
                ImGui.SameLine()
                ImGui.Text("Elapsed : ")
                ImGui.SameLine()
                local timeDiff = os.time() - PathStartTime
                local hours = math.floor(timeDiff / 3600)
                local minutes = math.floor((timeDiff % 3600) / 60)
                local seconds = timeDiff % 60
    
                ImGui.TextColored(0, 1, 0, 1, string.format("%02d:%02d:%02d", hours, minutes, seconds))
    

            end
            ImGui.Separator()
            -- Tabs
            -- ImGui.BeginChild("Tabs##MainTabs", -1, -1,ImGuiChildFlags.AutoResizeX)
            if ImGui.BeginTabBar('MainTabBar') then
                if ImGui.BeginTabItem('Controls') then
                    if ImGui.BeginChild("Tabs##Controls", -1, -1,ImGuiChildFlags.AutoResizeX) then
                    ImGui.SeparatorText("Select a Path")
                    ImGui.SetNextItemWidth(120)
                    if ImGui.BeginCombo("##SelectPath", NavSet.SelectedPath) then
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
                    ImGui.PushStyleColor(ImGuiCol.Button, ImVec4(1, 0.4, 0.4, 0.4))
                    if ImGui.Button(Icon.MD_DELETE) then
                        DeletePath(NavSet.SelectedPath)
                        NavSet.SelectedPath = 'None'
                    end
                    ImGui.PopStyleColor()
                    if ImGui.IsItemHovered() then
                        ImGui.SetTooltip("Delete Path")
                    end
                    ImGui.Dummy(10,5)
                    if ImGui.CollapsingHeader("Manage Paths##") then
                        ImGui.SetNextItemWidth(150)
                        newPath = ImGui.InputTextWithHint("##NewPathName", "New Path Name",newPath)
                        ImGui.SameLine()
                        ImGui.PushStyleColor(ImGuiCol.Button, ImVec4(0.4, 1, 0.4, 0.4))
                        if ImGui.Button(Icon.MD_CREATE) then
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
                            if ImGui.Button(Icon.MD_CONTENT_COPY) then
                                CreatePath(newPath)
                                for i = 1, #Paths[currZone][NavSet.SelectedPath] do
                                    table.insert(Paths[currZone][newPath], Paths[currZone][NavSet.SelectedPath][i])
                                end
                                SavePaths()
                                NavSet.SelectedPath = newPath
                                newPath = ''
                            end
                            ImGui.PopStyleColor()
                            if ImGui.IsItemHovered() then
                                ImGui.SetTooltip("Copy Path")
                            end
                        else
                            ImGui.PushStyleColor(ImGuiCol.Button, ImVec4(0.500, 0.500, 0.500, 1.000))
                            ImGui.Button(Icon.MD_CONTENT_COPY.."##Dummy")
                            ImGui.PopStyleColor()
                        end
                        ImGui.SameLine()
                        if NavSet.SelectedPath ~= 'None' then
                            ImGui.PushStyleColor(ImGuiCol.Button, ImVec4(0.911, 0.461, 0.085, 1.000))
                            if ImGui.Button(Icon.FA_SHARE.."##ExportSelected") then
                                local exportData = export_paths(currZone, NavSet.SelectedPath, Paths[currZone][NavSet.SelectedPath])
                                ImGui.LogToClipboard()
                                ImGui.LogText(exportData)
                                ImGui.LogFinish()
                                print('\ayPath data copied to clipboard!\ax')
                            end
                            ImGui.PopStyleColor()
                        else
                            ImGui.PushStyleColor(ImGuiCol.Button, ImVec4(0.500, 0.500, 0.500, 1.000))
                            ImGui.Button(Icon.FA_SHARE.."##Dummy")
                            ImGui.PopStyleColor()
                        end
                        if ImGui.IsItemHovered() then
                            ImGui.SetTooltip("Export: "..currZone.." : "..NavSet.SelectedPath)
                        end
                        ImGui.Dummy(10,5)
                        if ImGui.CollapsingHeader("Share Paths##") then
                            importString   = ImGui.InputTextWithHint("##ImportString","Paste Import String", importString)
                            ImGui.SameLine()
                            if importString ~= '' then
                                ImGui.PushStyleColor(ImGuiCol.Button, ImVec4(0.4, 1, 0.4, 0.4))
                                if ImGui.Button(Icon.FA_DOWNLOAD.."##ImportPath") then
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
                                        SavePaths()
                                    end
                                end
                                ImGui.PopStyleColor()
                            else
                                ImGui.PushStyleColor(ImGuiCol.Button, ImVec4(0.500, 0.500, 0.500, 1.000))
                                ImGui.Button(Icon.FA_DOWNLOAD.."##Dummy")
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
                            if exportZone ~= ''  then
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
                            if exportZone ~= '' and exportPathName ~= '' then
                                ImGui.PushStyleColor(ImGuiCol.Button, ImVec4(0.911, 0.461, 0.085, 1.000))
                                if ImGui.Button(Icon.FA_SHARE.."##ExportZonePath") then
                                    local exportData = export_paths(exportZone, exportPathName, Paths[exportZone][exportPathName])
                                    ImGui.LogToClipboard()
                                    ImGui.LogText(exportData)
                                    ImGui.LogFinish()
                                    print('\ayPath data copied to clipboard!\ax')
                                end
                                ImGui.PopStyleColor()
                            else
                                ImGui.PushStyleColor(ImGuiCol.Button, ImVec4(0.500, 0.500, 0.500, 1.000))
                                ImGui.Button(Icon.FA_SHARE.."##Dummy2")
                                ImGui.PopStyleColor()
                            end
                            if ImGui.IsItemHovered() then
                                ImGui.SetTooltip("Export:  "..exportZone.." : "..exportPathName)
                            end
                        end
                    end
                    ImGui.Dummy(10,5)
                    ImGui.Separator()
                    if ImGui.CollapsingHeader("Chain Paths##") then
                        if NavSet.SelectedPath ~= 'None' then
                            ImGui.PushStyleColor(ImGuiCol.Button, ImVec4(0.4, 1, 0.4, 0.4))
                            if ImGui.Button(Icon.MD_PLAYLIST_ADD.." ["..NavSet.SelectedPath.."]##") then
                                if not ChainedPaths then ChainedPaths = {} end
                                table.insert(ChainedPaths , {Zone = currZone, Path = NavSet.SelectedPath, Type = 'Normal'})
                            end
                            ImGui.PopStyleColor()
                            if ImGui.IsItemHovered() then
                                ImGui.SetTooltip("Add Selected Path to Chain")
                            end
                            
                        else
                            ImGui.PushStyleColor(ImGuiCol.Button, ImVec4(0.500, 0.500, 0.500, 1.000))
                            ImGui.Button(Icon.MD_PLAYLIST_ADD.."##Dummy")
                            ImGui.PopStyleColor()
                        end
                        local tmpCZ, tmpCP = {}, {}
                        for name, data in pairs(Paths) do
                            table.insert(tmpCZ , name)
                        end
                        table.sort(tmpCZ)
                                ImGui.SetNextItemWidth(120)

                        if ImGui.BeginCombo("Zone##SelectChainZone", NavSet.ChainZone) then
                            if not Paths[NavSet.ChainZone] then Paths[NavSet.ChainZone] = {} end
                            for k, name in pairs(tmpCZ) do
                                local isSelected = name == NavSet.ChainZone
                                if ImGui.Selectable(name, isSelected) then
                                    NavSet.ChainZone = name
                                end
                            end
                            ImGui.EndCombo()
                        end
                        if NavSet.ChainZone ~= '' then
                                    ImGui.SetNextItemWidth(120)

                            if ImGui.BeginCombo("Path##SelectChainPath", NavSet.ChainPath) then
                                if not Paths[NavSet.ChainZone] then Paths[NavSet.ChainZone] = {} end
                                for k, data in pairs(Paths[NavSet.ChainZone]) do
                                    table.insert(tmpCP , k)
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
                        ImGui.PushStyleColor(ImGuiCol.Button, ImVec4(0.4, 1, 0.4, 0.4))
                        if NavSet.ChainZone ~= '' and NavSet.ChainPath ~= '' then
                            if ImGui.Button(Icon.MD_PLAYLIST_ADD.." ["..NavSet.ChainPath .."]##") then
                                if not ChainedPaths then ChainedPaths = {} end
                                table.insert(ChainedPaths , {Zone = NavSet.ChainZone, Path = NavSet.ChainPath, Type = 'Normal'})
                            end
                            ImGui.PopStyleColor()
                        else
                            ImGui.PushStyleColor(ImGuiCol.Button, ImVec4(0.500, 0.500, 0.500, 1.000))
                            ImGui.Button(Icon.MD_PLAYLIST_ADD.."##Dummy2")
                            ImGui.PopStyleColor()
                        end
                        if ImGui.IsItemHovered() then
                            ImGui.SetTooltip("Add Path to Chain")
                        end
                        if #ChainedPaths > 0  then
                            ImGui.SameLine()
                            ImGui.PushStyleColor(ImGuiCol.Button, ImVec4(1, 0.4, 0.4, 0.4))
                            if ImGui.Button(Icon.MD_DELETE_SWEEP.."##") then
                                ChainedPaths = {}
                            end
                            ImGui.PopStyleColor()

                            if ImGui.IsItemHovered() then
                                ImGui.SetTooltip("Clear Chain")
                            end
                            ImGui.SeparatorText("Chain Paths:")
                            for i = 1, #ChainedPaths do
                                ImGui.SetNextItemWidth(100)
                                local chainType = {'Normal', 'Loop', 'PingPong', 'Reverse'}
                                if ImGui.BeginCombo("##PathType_"..i, ChainedPaths[i].Type) then
                                    if not Paths[currZone] then Paths[currZone] = {} end
                                    for k, v in pairs(chainType)  do
                                        local isSelected = v == ChainedPaths[i].Type
                                        if ImGui.Selectable(v, isSelected) then
                                            ChainedPaths[i].Type = v
                                        end
                                    end
                                    ImGui.EndCombo()
                                end
                                ImGui.SameLine()
                                ImGui.TextColored(0.0,1,1,1,"%s", ChainedPaths[i].Zone)
                                ImGui.SameLine()
                                if ChainedPaths[i].Path == NavSet.ChainPath then
                                    ImGui.TextColored(1,1,0,1,"%s", ChainedPaths[i].Path)
                                else
                                    ImGui.TextColored(0.0,1,0,1,"%s", ChainedPaths[i].Path)
                                end
                            end
                        end
                    end
                    ImGui.Dummy(10,5)
                    if NavSet.SelectedPath ~= 'None' or #ChainedPaths > 0 then
                        -- Navigation Controls
                        if ImGui.CollapsingHeader("Navigation##") then
                            if not NavSet.doNav then NavSet.doReverse = ImGui.Checkbox('Reverse Order', NavSet.doReverse) ImGui.SameLine() end
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
                                
                                if ImGui.Button(Icon.FA_PLAY_CIRCLE_O) then
                                    NavSet.doPause = false
                                    NavSet.PausedActiveGN = false
                                    table.insert(debugMessages, {Time = os.date("%H:%M:%S"), Zone = currZone, Path = NavSet.SelectedPath, WP = 'Resume', Status = 'Resumed Navigation!'})
                                end
                                ImGui.PopStyleColor()

                                if ImGui.IsItemHovered() then
                                    ImGui.SetTooltip("Resume Navigation")
                                end
                                ImGui.SameLine()
                            elseif not NavSet.doPause and NavSet.doNav then
                                ImGui.PushStyleColor(ImGuiCol.Button, ImVec4(1, 0.4, 0.4, 0.4))
                                
                                if ImGui.Button(Icon.FA_PAUSE) then
                                    NavSet.doPause = true
                                    mq.cmd("/squelch /nav stop")
                                    table.insert(debugMessages, {Time = os.date("%H:%M:%S"), Zone = currZone, Path = NavSet.SelectedPath, WP = 'Pause', Status = 'Paused Navigation!'})
                                end
                                ImGui.PopStyleColor()

                                if ImGui.IsItemHovered() then
                                    ImGui.SetTooltip("Pause Navigation")
                                end
                                ImGui.SameLine()
                            end
                            local tmpLabel = NavSet.doNav and Icon.FA_STOP or Icon.FA_PLAY
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
                                    mq.cmdf("/squelch /nav stop")
                                    NavSet.ChainStart = false
                                    PathStartClock,PathStartTime = nil, nil
                                else
                                    PathStartClock,PathStartTime = os.date("%I:%M:%S %p"), os.time()
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
                            if ImGui.Button(Icon.FA_PLAY.." Closest WP") then
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
                            NavSet.StopDist = ImGui.InputInt("Stop Distance##"..script, NavSet.StopDist, 1, 50)
                            ImGui.SetNextItemWidth(100)
                            NavSet.WpPause = ImGui.InputInt("Global Pause##"..script, NavSet.WpPause, 1,5 )
                        end
                    end
                    ImGui.EndChild()
                end
                ImGui.EndTabItem()
                end
                if ImGui.BeginTabItem('Path Data') then
                    if ImGui.BeginChild("Tabs##PathTab", -1, -1,ImGuiChildFlags.AutoResizeX) then
                    if NavSet.SelectedPath ~= 'None' then
                        if ImGui.CollapsingHeader("Manage Waypoints##") then
                            ImGui.PushStyleColor(ImGuiCol.Button, ImVec4(0.4, 1, 0.4, 0.4))
                            if ImGui.Button(Icon.MD_ADD_LOCATION) then
                                RecordWaypoint(NavSet.SelectedPath)
                            end
                            ImGui.PopStyleColor()
                            if ImGui.IsItemHovered() then
                                ImGui.SetTooltip("Add Waypoint")
                            end

                            ImGui.SameLine()
                            local label = Icon.MD_FIBER_MANUAL_RECORD
                            if NavSet.autoRecord then
                                label = Icon.FA_STOP_CIRCLE
                                ImGui.PushStyleColor(ImGuiCol.Button, ImVec4(1.0, 0.4, 0.4, 0.4))
                            else
                                ImGui.PushStyleColor(ImGuiCol.Button, ImVec4(0.4, 1.0, 0.4, 0.4))
                            end
                            if ImGui.Button(label) then
                                NavSet.autoRecord = not NavSet.autoRecord
                                if NavSet.autoRecord then 
                                    if DEBUG then table.insert(debugMessages, {Time = os.date("%H:%M:%S"), Zone = mq.TLO.Zone.ShortName(), Path = NavSet.SelectedPath, WP = 'Start Recording', Status = 'Start Recording Waypoints!'}) end
                                else
                                    if DEBUG then table.insert(debugMessages, {Time = os.date("%H:%M:%S"), Zone = mq.TLO.Zone.ShortName(), Path = NavSet.SelectedPath, WP = 'Stop Recording', Status = 'Stop Recording Waypoints!'}) end
                                end
                            end
                            ImGui.PopStyleColor()

                            if ImGui.IsItemHovered() then
                                ImGui.SetTooltip("Auto Record Waypoints")
                            end
                            ImGui.SameLine()
                            ImGui.PushStyleColor(ImGuiCol.Button, ImVec4(1.0, 0.4, 0.4, 0.4))
                            if ImGui.Button(Icon.MD_DELETE_SWEEP) then
                                ClearWaypoints(NavSet.SelectedPath)
                            end
                            ImGui.PopStyleColor()
                            if ImGui.IsItemHovered() then
                                ImGui.SetTooltip("Clear Waypoints")
                            end
                            ImGui.SameLine()
                            ImGui.SetNextItemWidth(80)
                            NavSet.RecordDelay = ImGui.InputInt("Record Delay##"..script, NavSet.RecordDelay, 1, 10)
                        end
                        ImGui.Separator()
                    end
                    ImGui.Dummy(10,5)
                    if ImGui.CollapsingHeader("Waypoint Table##Header") then
                        -- Waypoint Table
                        if NavSet.SelectedPath ~= 'None' then

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
                                        ImGui.TextColored(ImVec4(0, 1, 0, 1),"%s", tmpTable[i].step)
                                        if ImGui.IsItemHovered() then
                                            ImGui.SetTooltip("Current Waypoint")
                                        end
                                    else
                                        ImGui.Text("%s", tmpTable[i].step)
                                    end
                                    
                                    if i == closestWaypointIndex then
                                        ImGui.SameLine()
                                        ImGui.TextColored(ImVec4(1, 1, 0, 1), Icon.MD_STAR)
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
                                    tmpTable[i].delay, changed = ImGui.InputInt("##delay_" .. i, tmpTable[i].delay, 1, 1)
                                    if changed then
                                        for k, v in pairs(Paths[currZone][NavSet.SelectedPath]) do
                                            if v.step == tmpTable[i].step then
                                                Paths[currZone][NavSet.SelectedPath][k].delay = tmpTable[i].delay
                                                SavePaths()
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
                                                SavePaths()
                                            end
                                        end
                                    end
                                    if ImGui.IsItemHovered() then
                                        ImGui.SetTooltip("Command")
                                    end
                                    ImGui.TableSetColumnIndex(4)
                                    tmpTable[i].door, changedDoor = ImGui.Checkbox(Icon.FA_FORWARD.."##door_" .. i, tmpTable[i].door)
                                    if changedDoor then
                                        for k, v in pairs(Paths[currZone][NavSet.SelectedPath]) do
                                            if v.step == tmpTable[i].step then
                                                Paths[currZone][NavSet.SelectedPath][k].door = tmpTable[i].door
                                                SavePaths()
                                            end
                                        end
                                    end
                                    if ImGui.IsItemHovered() then
                                        ImGui.SetTooltip("Door Forward")
                                    end
                                    ImGui.SameLine(0,0)
                                    tmpTable[i].doorRev, changedDoorRev = ImGui.Checkbox(Icon.FA_BACKWARD.."##doorRev_" .. i, tmpTable[i].doorRev)
                                    if changedDoorRev then
                                        for k, v in pairs(Paths[currZone][NavSet.SelectedPath]) do
                                            if v.step == tmpTable[i].step then
                                                Paths[currZone][NavSet.SelectedPath][k].doorRev = tmpTable[i].doorRev
                                                SavePaths()
                                            end
                                        end
                                    end
                                    if ImGui.IsItemHovered() then
                                        ImGui.SetTooltip("Door Reverse")
                                    end
                                    ImGui.TableSetColumnIndex(5)
                                    if not NavSet.doNav then
                                        if ImGui.Button(Icon.FA_TRASH .. "##_" .. i) then
                                            deleteWP = true
                                            deleteWPStep = tmpTable[i].step
                                        end
                                        if ImGui.IsItemHovered() then
                                            ImGui.SetTooltip("Delete WP")
                                        end
                                        -- if not doReverse then
                                        ImGui.SameLine(0,0)
                                        if ImGui.Button(Icon.MD_UPDATE..'##Update_'..i) then
                                            tmpTable[i].loc = mq.TLO.Me.LocYXZ()
                                            -- Update Paths table
                                            for k, v in pairs(Paths[currZone][NavSet.SelectedPath]) do
                                                if v.step == tmpTable[i].step then
                                                    Paths[currZone][NavSet.SelectedPath][k] = tmpTable[i]
                                                end
                                            end
                                            -- Paths[currZone][selectedPath][tmpTable[i].step].loc = mq.TLO.Me.LocYXZ()
                                            SavePaths()
                                        end
                                        if ImGui.IsItemHovered() then
                                            ImGui.SetTooltip("Update Loc")
                                        end
                                    -- end
                                        ImGui.SameLine(0,0)
                                        if i > 1 and ImGui.Button(Icon.FA_CHEVRON_UP.. "##up_" .. i) then
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
                                            SavePaths()
                                        end
                                        ImGui.SameLine(0,0)
                                        if i < #tmpTable and ImGui.Button(Icon.FA_CHEVRON_DOWN .. "##down_" .. i) then
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
                                            SavePaths()
                                        end
                                    end
                                end
                                ImGui.EndTable()
                            end
                        else
                            ImGui.Text("No Path Selected")
                        end
                    end
                    ImGui.EndChild()
                end
                ImGui.EndTabItem()
                end
                if showDebugTab and DEBUG then
                    if ImGui.BeginTabItem('Debug Messages') then
                        if ImGui.BeginChild("Tabs##DebugTab", -1, -1,ImGuiChildFlags.AutoResizeX) then
                        if ImGui.Button('Clear Debug Messages') then
                            debugMessages = {}
                        end
                        if ImGui.IsItemHovered() then
                            ImGui.SetTooltip("Clear Debug Messages")
                        end
                        ImGui.Separator()
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
                        ImGui.EndChild()
                    end
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
        LoadTheme.EndTheme(ColorCount, StyleCount)
        ImGui.End()
    end

    -- Config Window
    if showConfigGUI then
        if mq.TLO.Me.Zoning() then return end
            local winName = string.format('%s Config##Config_%s',script, meName)
            local ColCntConf, StyCntConf = LoadTheme.StartTheme(theme.Theme[themeID])
            local openConfig, showConfig = ImGui.Begin(winName,true,bit32.bor(ImGuiWindowFlags.NoCollapse, ImGuiWindowFlags.AlwaysAutoResize))
            if not openConfig then
                showConfigGUI = false
            end
            if showConfig then
                -- Set Window Font Scale
                ImGui.SetWindowFontScale(scale)
                if ImGui.CollapsingHeader('Theme##Settings'..script) then
                    -- Configure ThemeZ --
                    ImGui.SeparatorText("Theme##"..script)
                    ImGui.Text("Cur Theme: %s", themeName)

                    -- Combo Box Load Theme
                    ImGui.SetNextItemWidth(100)
                    if ImGui.BeginCombo("Load Theme##"..script, themeName) then
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
                    scale = ImGui.SliderFloat("Scale##"..script, scale, 0.5, 2)
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
                ImGui.SeparatorText("MyPaths Settings##"..script)
                -- HUD Transparency --
                ImGui.SetNextItemWidth(100)
                hudTransparency = ImGui.SliderFloat("HUD Transparency##"..script, hudTransparency, 0.0, 1)
                
                hudMouse = ImGui.Checkbox("On Mouseover##"..script, hudMouse)
                if ImGui.CollapsingHeader("Interrupt Settings##"..script) then
                -- Set Interrupts we will stop for
                    InterruptSet.stopForAll = ImGui.Checkbox("Stop for All##"..script, InterruptSet.stopForAll)
                    if InterruptSet.stopForAll then
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
                    end
                    if ImGui.BeginTable("##Interrupts", 2, bit32.bor(ImGuiTableFlags.Borders), -1,0) then
                        ImGui.TableNextRow()
                        ImGui.TableSetColumnIndex(0)
                        InterruptSet.stopForCharm = ImGui.Checkbox("Stop for Charmed##"..script, InterruptSet.stopForCharm)
                        if not InterruptSet.stopForCharm then InterruptSet.stopForAll = false end
                        ImGui.TableSetColumnIndex(1)
                        InterruptSet.stopForCombat = ImGui.Checkbox("Stop for Combat##"..script, InterruptSet.stopForCombat)
                        if not InterruptSet.stopForCombat then InterruptSet.stopForAll = false end
                        ImGui.TableNextRow()

                        ImGui.TableSetColumnIndex(0)
                        InterruptSet.stopForFear = ImGui.Checkbox("Stop for Fear##"..script, InterruptSet.stopForFear)
                        if not InterruptSet.stopForFear then InterruptSet.stopForAll = false end
                        ImGui.TableSetColumnIndex(1)
                        InterruptSet.stopForGM = ImGui.Checkbox("Stop for GM##"..script, InterruptSet.stopForGM)
                        if not InterruptSet.stopForGM then InterruptSet.stopForAll = false end
                        ImGui.TableNextRow()

                        ImGui.TableSetColumnIndex(0)
                        InterruptSet.stopForLoot = ImGui.Checkbox("Stop for Loot##"..script, InterruptSet.stopForLoot)
                        if not InterruptSet.stopForLoot then InterruptSet.stopForAll = false end
                        ImGui.TableSetColumnIndex(1)
                        InterruptSet.stopForMez = ImGui.Checkbox("Stop for Mez##"..script, InterruptSet.stopForMez)
                        if not InterruptSet.stopForMez then InterruptSet.stopForAll = false end
                        ImGui.TableNextRow()

                        ImGui.TableSetColumnIndex(0)
                        InterruptSet.stopForRoot = ImGui.Checkbox("Stop for Root##"..script, InterruptSet.stopForRoot)
                        if not InterruptSet.stopForRoot then InterruptSet.stopForAll = false end
                        ImGui.TableSetColumnIndex(1)
                        InterruptSet.stopForSitting = ImGui.Checkbox("Stop for Sitting##"..script, InterruptSet.stopForSitting)
                        if not InterruptSet.stopForSitting then InterruptSet.stopForAll = false end
                        ImGui.TableNextRow()

                        ImGui.TableSetColumnIndex(0)
                        InterruptSet.stopForXtar = ImGui.Checkbox("Stop for Xtarget##"..script, InterruptSet.stopForXtar)
                        if not InterruptSet.stopForXtar then InterruptSet.stopForAll = false end
                        ImGui.TableSetColumnIndex(1)
                        InterruptSet.stopForDist = ImGui.Checkbox("Stop for Party Dist##"..script, InterruptSet.stopForDist)
                        if not InterruptSet.stopForDist then InterruptSet.stopForAll = false end
                        ImGui.EndTable()
                        if InterruptSet.stopForDist then
                            ImGui.SetNextItemWidth(100)
                            InterruptSet.stopForGoupDist = ImGui.InputInt("Party Distance##GroupDist", InterruptSet.stopForGoupDist, 1, 50)
                        end
                    end
                    settings[script].GroupWatch = ImGui.Checkbox("Group Watch##"..script, settings[script].GroupWatch)
                    if settings[script].GroupWatch then
                        if ImGui.CollapsingHeader("Group Watch Settings##"..script) then
                            settings[script].WatchHealth = ImGui.InputInt("Watch Health##"..script, settings[script].WatchHealth, 1, 5)
                            if settings[script].WatchHealth > 100 then settings[script].WatchHealth = 100 end
                            if settings[script].WatchHealth < 1 then settings[script].WatchHealth = 1 end
                            settings[script].WatchMana = ImGui.InputInt("Watch Mana##"..script, settings[script].WatchMana, 1, 5)
                            if settings[script].WatchMana > 100 then settings[script].WatchMana = 100 end
                            if settings[script].WatchMana < 1 then settings[script].WatchMana = 1 end

                            if ImGui.BeginCombo("Watch Type##"..script, settings[script].WatchType) then
                                local types = {"All", "Healer","Self", "None"}
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
                ImGui.Dummy(5,5)
                ImGui.SeparatorText("Recording Settings##"..script)
                -- Set RecordDley
                ImGui.SetNextItemWidth(100)
                NavSet.RecordDelay = ImGui.InputInt("Record Delay##"..script, NavSet.RecordDelay, 1, 5)
                -- Minimum Distance Between Waypoints
                ImGui.SetNextItemWidth(100)
                NavSet.RecordMinDist = ImGui.InputInt("Min Dist. Between WP##"..script, NavSet.RecordMinDist, 1, 50)

                ImGui.SeparatorText("Navigation Settings##"..script)
                -- Set Stop Distance
                ImGui.SetNextItemWidth(100)
                NavSet.StopDist = ImGui.InputInt("Stop Distance##"..script, NavSet.StopDist, 1, 50)
                -- Set Waypoint Pause time
                ImGui.SetNextItemWidth(100)
                NavSet.WpPause = ImGui.InputInt("Waypoint Pause##"..script, NavSet.WpPause, 1, 5)
                -- Set Interrupt Delay
                ImGui.SetNextItemWidth(100)
                InterruptSet.interruptDelay = ImGui.InputInt("Interrupt Delay##"..script, InterruptSet.interruptDelay, 1, 5)

                -- Save & Close Button --
                if ImGui.Button("Save & Close") then
                    settings[script].HeadsUpTransparency = hudTransparency
                    settings[script].Scale = scale
                    settings[script].LoadTheme = themeName
                    settings[script].locked = locked
                    settings[script].AutoSize = aSize
                    settings[script].MouseHUD = hudMouse
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
            LoadTheme.EndTheme(ColCntConf, StyCntConf)
            ImGui.End()
    end

    if showHUD then
        if mq.TLO.Me.Zoning() then return end
        
        if transFlag and hudMouse then
            ImGui.PushStyleColor(ImGuiCol.WindowBg, ImVec4(0.0, 0.0, 0.0, hudTransparency))
        elseif not hudMouse then
            ImGui.PushStyleColor(ImGuiCol.WindowBg, ImVec4(0.0, 0.0, 0.0, hudTransparency))
        else
            ImGui.PushStyleColor(ImGuiCol.WindowBg, ImVec4(0.0, 0.0, 0.0, 0.0))
        end
        local openHUDWin, showHUDWin = ImGui.Begin("MyPaths HUD##HUD", true, bit32.bor(ImGuiWindowFlags.NoCollapse, ImGuiWindowFlags.AlwaysAutoResize, ImGuiWindowFlags.NoTitleBar))
        if not openHUDWin then
            ImGui.PopStyleColor()
            showHUD = false
        end
        if showHUDWin then
            -- Set Window Font Scale
            ImGui.SetWindowFontScale(scale)
            if ImGui.IsWindowHovered() then
                transFlag = true
                if ImGui.IsMouseDoubleClicked(0) then
                    showMainGUI = not showMainGUI
                end
                ImGui.SetTooltip("Double Click to Toggle Main GUI")
            else
                transFlag = false
            end
            if NavSet.PausedActiveGN then
                if mq.TLO.SpawnCount('gm')() > 0 then
                ImGui.TextColored(1,0,0,1,"!!%s GM in Zone %s!!", Icon.FA_BELL,Icon.FA_BELL)
                end
            end
            ImGui.Text("Current Zone: ")
            ImGui.SameLine()
            ImGui.TextColored(0,1,0,1,"%s", currZone)
            ImGui.SameLine()
            ImGui.Text("Selected Path: ")
            ImGui.SameLine()
            ImGui.TextColored(0,1,1,1,"%s", NavSet.SelectedPath)
            ImGui.Text("Current Loc: ")
            ImGui.SameLine()
            ImGui.TextColored(1,1,0,1,"%s", mq.TLO.Me.LocYXZ())
            if NavSet.doNav then
                local tmpTable = sortPathsTable(currZone, NavSet.SelectedPath) or {}
                if tmpTable[NavSet.CurrentStepIndex] then
                    ImGui.Text("Current WP: ")
                    ImGui.SameLine()
                    ImGui.TextColored(1,1,0,1,"%s ",tmpTable[NavSet.CurrentStepIndex].step or 0)
                    ImGui.SameLine()
                    ImGui.Text("Distance: ")
                    ImGui.SameLine()
                    ImGui.TextColored(0,1,1,1,"%.2f", mq.TLO.Math.Distance(string.format("%s:%s", tmpTable[NavSet.CurrentStepIndex].loc:gsub(",", " "), mq.TLO.Me.LocYXZ()))())
                end
            end

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
                ImGui.TextColored(ImVec4(1,1,0,1), status)
            else
                ImGui.Text("Status: ")
                ImGui.SameLine()
                ImGui.TextColored(ImVec4(1,1,1,1), status)
            end
            if PathStartClock ~= nil then
                ImGui.Text("Start Time: ")
                ImGui.SameLine()
                ImGui.TextColored(0,1,1,1,"%s", PathStartClock)
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
        ImGui.PopStyleColor()
        -- Set Window Font Scale
        ImGui.SetWindowFontScale(1)
        ImGui.End()
    end
end

-------- Main Functions --------

local function displayHelp()
    printf("\ay[\at%s\ax] \agCommands: \ay/mypaths [go|stop|list|show|quit|help] [loop|rloop|start|reverse|pingpong|closest|rclosest] [path]", script)
    printf("\ay[\at%s\ax] \agOptions: \aygo \aw= \atREQUIRES arguments and Path name see below for Arguments.", script)
    printf("\ay[\at%s\ax] \agOptions: \aystop \aw= \atStops the current Navigation.", script)
    printf("\ay[\at%s\ax] \agOptions: \ayshow \aw= \atToggles Main GUI.", script)
    printf("\ay[\at%s\ax] \agOptions: \aylist \aw= \atLists all Paths in the current Zone.", script)
    printf("\ay[\at%s\ax] \agOptions: \ayquit or exit \aw= \atExits the script.", script)
    printf("\ay[\at%s\ax] \agOptions: \ayhelp \aw= \atPrints out this help list.", script)
    printf("\ay[\at%s\ax] \agArguments: \ayloop \aw= \atLoops the path, \ayrloop \aw= \atLoop in reverse.", script)    
    printf("\ay[\at%s\ax] \agArguments: \ayclosest \aw= \atstart at closest wp, \ayrclosest \aw= \atstart at closest wp and go in reverse.", script)    
    printf("\ay[\at%s\ax] \agArguments: \aystart \aw= \atstarts the path normally, \ayreverse \aw= \atrun the path backwards.", script)
    printf("\ay[\at%s\ax] \agArguments: \aypingpong \aw= \atstart in ping pong mode.", script)
    printf("\ay[\at%s\ax] \agExample: \ay/mypaths \aogo \ayloop \am\"Loop A\"", script)
    printf("\ay[\at%s\ax] \agExample: \ay/mypaths \aostop", script)
    printf("\ay[\at%s\ax] \agCommands: \ay/mypaths [\atcombat\ax|\atxtarg\ax] [\aton\ax|\atoff\ax] \ay- \atToggle Combat or Xtarget.", script)
end

local function bind(...)
    local args = {...}
    local key = args[1]
    local action = args[2]
    local path = args[3]
    local zone = mq.TLO.Zone.ShortName()

    if #args == 1 then
        if key == 'stop' then
            NavSet.doNav = false
            mq.cmdf("/squelch /nav stop")
            NavSet.ChainStart = false
            NavSet.SelectedPath = 'None'
            loadPaths()
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
            mq.cmd("/squelch /nav stop")
            mq.TLO.Me.Stand()
            mq.delay(1)
            NavSet.doNav = false
            RUNNING = false
        elseif key == 'list' then
            if Paths[zone] == nil then 
                printf("\ay[\at%s\ax] \arNo Paths Found!", script)
                return
            end
            printf("\ay[\at%s\ax] \agZone: \at%s \agPaths: ", script, zone)
            for name, data in pairs(Paths[zone]) do
                printf("\ay[\at%s\ax] \ay%s", script, name)
            end
        else
            printf("\ay[\at%s\ax] \arInvalid Command!", script)
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
        end
    elseif #args  == 3 then
        if Paths[zone]["'"..path.."'"] ~= nil then
            printf("\ay[\at%s\ax] \arInvalid Path!", script)
            return
        end
        if key == 'go' then
            if action == 'loop' then
                NavSet.SelectedPath = path
                NavSet.doReverse = false
                NavSet.doNav = true
                NavSet.doLoop = true
                PathStartClock,PathStartTime = os.date("%I:%M:%S %p"), os.time()
            end
            if action == 'rloop' then
                NavSet.SelectedPath = path
                NavSet.doReverse = true
                NavSet.doNav = true
                NavSet.doLoop = true
                PathStartClock,PathStartTime = os.date("%I:%M:%S %p"), os.time()
            end
            if action == 'start' then
                NavSet.SelectedPath = path
                NavSet.doReverse = false
                NavSet.doNav = true
                NavSet.doLoop = false
                PathStartClock,PathStartTime = os.date("%I:%M:%S %p"), os.time()
            end
            if action == 'reverse' then
                NavSet.SelectedPath = path
                NavSet.doReverse = true
                NavSet.doNav = true
                PathStartClock,PathStartTime = os.date("%I:%M:%S %p"), os.time()
            end
            if action == 'pingpong' then
                NavSet.SelectedPath = path
                NavSet.doPingPong = true
                NavSet.doNav = true
                PathStartClock,PathStartTime = os.date("%I:%M:%S %p"), os.time()
            end
            if action == 'closest' then
                NavSet.SelectedPath = path
                NavSet.doNav = true
                NavSet.doReverse = false
                NavSet.CurrentStepIndex = FindIndexClosestWaypoint(Paths[zone][path])
                PathStartClock,PathStartTime = os.date("%I:%M:%S %p"), os.time()
            end
            if action == 'rclosest' then
                NavSet.SelectedPath = path
                NavSet.doNav = true
                NavSet.doReverse = true
                NavSet.CurrentStepIndex = FindIndexClosestWaypoint(Paths[zone][path])
                PathStartClock,PathStartTime = os.date("%I:%M:%S %p"), os.time()
            end
        end
    else
        printf("\ay[\at%s\ax] \arInvalid Arguments!", script)
    end
end

local args = {...}
local function processArgs()
    if #args == 0 then
        displayHelp()
        return
    end
    if #args == 2 then
        if (args[1]== 'debug' and args[2] == 'hud') or (args[2]== 'debug' and args[1] == 'hud') then
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

local function Init()
    processArgs()
    -- Load Settings
    loadSettings()
    loadPaths()
    mq.bind('/mypaths', bind)
    -- Get Character Name
    meName = mq.TLO.Me.Name()
    -- Check if ThemeZ exists
    if File_Exists(themezDir) then
        hasThemeZ = true
    end
    currZone = mq.TLO.Zone.ShortName()
    lastZone = currZone
    -- Initialize ImGui
    mq.imgui.init('MyPaths', Draw_GUI)

    displayHelp()
end

local function Loop()
    -- Main Loop
    while RUNNING do
        local justZoned = false
        local cTime = os.time()
        currZone = mq.TLO.Zone.ShortName()
        if mq.TLO.Me.Zoning() == true then
            printf("\ay[\at%s\ax] \agZoning, \ayPausing Navigation...", script)
            ZoningPause()
        end

        if (InterruptSet.stopForDist and InterruptSet.stopForCharm and InterruptSet.stopForCombat and InterruptSet.stopForFear and InterruptSet.stopForGM and
            InterruptSet.stopForLoot and InterruptSet.stopForMez and InterruptSet.stopForRoot and InterruptSet.stopForSitting and InterruptSet.stopForXtar) then
            InterruptSet.stopForAll = true
        else
            InterruptSet.stopForAll = false
        end

        if currZone ~= lastZone then

            printf("\ay[\at%s\ax] \agZone Changed Last: \at%s Current: \ay%s", script, lastZone, currZone)
            lastZone = currZone
            NavSet.SelectedPath = 'None'
            NavSet.doNav = false
            NavSet.autoRecord = false
            NavSet.doLoop = false
            NavSet.doReverse = false
            NavSet.doPingPong = false
            NavSet.doPause = false
            
            pauseTime = 0
            InterruptSet.PauseStart = 0
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
                        status = 'Navigating'
                        printf('\ay[\at%s\ax] \agStarting navigation for path: \ay%s \agin zone: \ay%s', script, NavSet.SelectedPath, currZone)
                    end
                else
                    ChainedPaths = {}
                    NavSet.CurChain = 0
                    NavSet.ChainStart = false
                    NavSet.ChainZone = ''
                    NavSet.ChainPath = ''
                end
            end
            justZoned = true
        else justZoned = false end

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
            mq.delay(500)
        end

        if zoningHideGUI then
            printf("\ay[\at%s\ax] \agZoning, \ayHiding GUI...", script)
            mq.delay(1)
            showMainGUI = true
            NavSet.LoopCount = 0
            zoningHideGUI = false
            NavSet.CurrentStepIndex = 1
            NavSet.SelectedPath = 'None'
            NavSet.doNav = false
            table.insert(debugMessages, {Time = os.date("%H:%M:%S"), Zone = mq.TLO.Zone.ShortName(), Path = NavSet.SelectedPath, WP = 1, Status = 'Finished Zoning'})
            mq.delay(1)
            status = 'Idle'
            if currZone ~= lastZone then
                NavSet.SelectedPath = 'None'
                NavSet.doNav = false
                NavSet.doPause = false
                lastZone = currZone
                pauseTime = 0
                InterruptSet.PauseStart = 0
                printf('\ay[\at%s\ay]\ag Zone Changed Last:\at %s Current:\ay %s', script, lastZone, currZone)
            end
        end
        
        if not mq.TLO.Me.Sitting() then 
            lastHP, lastMP = 0,0
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
        -- Make sure we are still in game or exit the script.
        if mq.TLO.EverQuest.GameState() ~= "INGAME" then
            printf("\aw[\at%s\ax] \arNot in game, \ayTry again later...", script)
            mq.exit()
        end

        if NavSet.doNav and not NavSet.doPause and not justZoned then
            mq.delay(1)
            cTime = os.time()
            local checkTime = InterruptSet.interruptCheck or 1
            -- printf("interrupt Checked: %s", checkTime)
            if cTime - checkTime >= 1 then
                InterruptSet.interruptFound = CheckInterrupts()
                InterruptSet.interruptCheck = os.time()
                if mq.TLO.SpawnCount('gm')() > 0 and InterruptSet.stopForGM and not NavSet.PausedActiveGN then
                    printf("\ay[\at%s\ax] \arGM Detected, \ayPausing Navigation...", script)
                    NavSet.doNav = false
                    mq.cmdf("/squelch /nav stop")
                    NavSet.ChainStart = false
                    mq.cmd("/multiline ; /squelch /beep; /timed  3, /beep ; /timed 2, /beep ; /timed 1, /beep")
                    mq.delay(1)
                    status = 'Paused: GM Detected'
                    NavSet.PausedActiveGN = true
                end
            end

        end
        
        if NavSet.doNav and not InterruptSet.interruptFound and not NavSet.doPause and not NavSet.doChainPause then

            if NavSet.PreviousDoNav ~= NavSet.doNav then
                -- Reset the coroutine since doNav changed from false to true
                co = coroutine.create(NavigatePath)
            end

            local curTime = os.time()
                
            -- If the coroutine is not dead, resume it
            if coroutine.status(co) ~= "dead" then
                -- Check if we need to pause
                if InterruptSet.PauseStart > 0 then
                    if curTime - InterruptSet.PauseStart > pauseTime then
                        -- Time is up, resume the coroutine and reset the timer values
                        pauseTime = 0
                        InterruptSet.PauseStart = 0
                        local success, message = coroutine.resume(co, NavSet.SelectedPath)
                        if not success then
                            print("Error: " .. message)
                            -- Reset coroutine on error
                            co = coroutine.create(NavigatePath)
                        end
                    end
                else
                    -- Resume the coroutine we are do not need to pause
                    local success, message = coroutine.resume(co, NavSet.SelectedPath)
                    if not success then
                        print("Error: " .. message)
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
            mq.delay(100)
        end

        -- Update previousDoNav to the current state
        NavSet.PreviousDoNav = NavSet.doNav

        if #ChainedPaths > 0 and not NavSet.doNav and NavSet.ChainStart then
            -- for i = 1, #Chain do
                if ChainedPaths[NavSet.CurChain].Path == NavSet.ChainPath and NavSet.CurChain < #ChainedPaths then
                    if ChainedPaths[NavSet.CurChain+1].Zone ~= currZone then
                        status = 'Next Path Waiting to Zone: '..ChainedPaths[NavSet.CurChain+1].Zone
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
                        mq.delay(500)
                        NavSet.doNav = true
                    end
                    mq.delay(500)            
                elseif ChainedPaths[NavSet.CurChain].Path == NavSet.ChainPath and NavSet.CurChain == #ChainedPaths then
                    NavSet.ChainStart = false
                    if ChainedPaths[NavSet.CurChain].Type == 'Normal' or ChainedPaths[NavSet.CurChain].Type == 'Reverse' then
                        NavSet.doNav = false
                        NavSet.doChainPause = false
                        NavSet.ChainStart = false
                        NavSet.ChainPath = ''
                        ChainedPaths = {}
                    end
                end
            -- end
        end

        if NavSet.autoRecord then
            AutoRecordPath(NavSet.SelectedPath)
        end

        if deleteWP then
            RemoveWaypoint(NavSet.SelectedPath, deleteWPStep)
            if DEBUG then table.insert(debugMessages, {Time = os.date("%H:%M:%S"), Zone = mq.TLO.Zone.ShortName(), Path = NavSet.SelectedPath, WP = 'Delete  #'..deleteWPStep, Status = 'Waypoint #'..deleteWPStep..' Removed Successfully!'}) end
            deleteWPStep = 0
            deleteWP = false
        end

        if DEBUG then
            if lastStatus ~= status then
                local statTxt = status
                if status:find("Distance") then
                    statTxt = statTxt:gsub("Distance:", "Dist:")
                end
                table.insert(debugMessages, {Time = os.date("%H:%M:%S"), WP = NavSet.CurrentStepIndex, Status = statTxt, Path = NavSet.SelectedPath, Zone = mq.TLO.Zone.ShortName()})
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

        mq.delay(1)
    end
end

-- Make sure we are in game before running the script
if mq.TLO.EverQuest.GameState() ~= "INGAME" then 
    printf("\aw[\at%s\ax] \arNot in game, \ayTry again later...", script) 
    mq.exit() 
end
Init()
Loop()
