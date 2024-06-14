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
local Paths = {}
local selectedPath = 'None'
local newPath = ''
local curTime = os.time()
local lastTime = curTime
local autoRecord, doNav, doSingle, doLoop, doReverse, doPingPong = false, false, false, false, false, false
local recordDelay, stopDist, wpPause = 5, 30, 1
local currentStepIndex, loopCount = 1, 0
local deleteWP, deleteWPStep = false, 0
local status, lastStatus = 'Idle', ''
local wpLoc = ''
local currZone, lastZone = '', ''
local lastHP, lastMP, pauseTime = 0, 0, 0
local pauseStart = 0
local previousDoNav = false
local zoningHideGUI = false
local interruptFound = false
local openDoor = false
local ZoningPause
local interruptDelay = 2
local lastRecordedWP = ''
local recordMinDist = 25
local reported = false
local interrupts = {stopForAll = true, stopForGM = true, stopForSitting = true, stopForCombat = true, stopForXtar = true, stopForFear = true, stopForCharm = true, stopForMez = true, stopForRoot = true, stopForLoot = true}

-- GUI Settings
local winFlags = bit32.bor(ImGuiWindowFlags.None, ImGuiWindowFlags.MenuBar)
local RUNNING, DEBUG = true, false
local showMainGUI, showConfigGUI, showDebugTab, showHUD = true, false, false, false
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
        settings[script].InterruptDelay = interruptDelay
        newSetting = true
    end

    if settings[script].stopForGM == nil then
        settings[script].stopForGM = interrupts.stopForGM
        newSetting = true
    end

    if settings[script].RecordMinDist == nil then
        settings[script].RecordMinDist = recordMinDist
        newSetting = true
    end

    if settings[script].RecordDelay == nil then
        settings[script].RecordDelay = recordDelay
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

    if settings[script].AutoSize == nil then
        settings[script].AutoSize = aSize
        newSetting = true
    end

    if settings[script].PauseStops == nil then
        settings[script].PauseStops = wpPause
        newSetting = true
    end

    if settings[script].HeadsUpTransparency == nil then
        settings[script].HeadsUpTransparency = hudTransparency
        newSetting = true
    end

    if settings[script].StopDistance == nil then
        settings[script].StopDistance = stopDist
        newSetting = true
    end

    -- Load the theme
    loadTheme()

    -- Set the settings to the variables
    hudTransparency = settings[script].HeadsUpTransparency
    stopDist = settings[script].StopDistance
    wpPause = settings[script].PauseStops
    aSize = settings[script].AutoSize
    recordMinDist = settings[script].RecordMinDist
    interrupts.stopForGM = settings[script].stopForGM
    locked = settings[script].locked
    scale = settings[script].Scale
    themeName = settings[script].LoadTheme
    recordDelay = settings[script].RecordDelay
    interruptDelay = settings[script].InterruptDelay

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
        if distToLast < recordMinDist and autoRecord then
            status = "Recording: Distance to Last WP is less than "..recordMinDist.."!"
            if DEBUG and not reported then
                table.insert(debugMessages, {Time = os.date("%H:%M:%S"), Zone = zone, Path = name, WP = 'Record WP', Status = 'Distance to Last WP is less than '..recordMinDist..' units!'})
                reported = true
            end
            return
        end
    end
    if tmp[index] ~= nil then
        if tmp[index].loc == loc then return end
        table.insert(tmp, {step = index + 1, loc = loc, delay = 0, cmd = ''})
        lastRecordedWP = loc
        index = index + 1
        reported = false
    else
        table.insert(tmp, {step = 1, loc = loc, delay = 0, cmd = ''})
        index = 1
        lastRecordedWP = loc
        reported = false
    end
    Paths[zone][name] = tmp
    if autoRecord then
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
    if curTime - lastTime > recordDelay then
        RecordWaypoint(name)
        lastTime = curTime
    end
    SavePaths()
end

local function groupWatch(type)
    if type == 'None' then return false end
    if type == "Self" then
        if mq.TLO.Me.PctHPs() < settings[script].WatchHealth then
            mq.TLO.Me.Sit()
            return true
        end
        if mq.TLO.Me.PctMana() < settings[script].WatchMana then
            mq.TLO.Me.Sit()
            return true
        end
    elseif mq.TLO.Me.GroupSize() > 0 then
        local member = mq.TLO.Group.Member
        local gsize = mq.TLO.Me.GroupSize() or 0
        
            if type == 'Healer' then
                for i = 1, gsize- 1 do
                    local class = member(i).Class.ShortName()
                    local myClass = mq.TLO.Me.Class.ShortName()
                    if class == 'CLR' or class == 'DRU' or class == 'SHM' or myClass == 'CLR' or myClass == 'DRU' or myClass == 'SHM'then
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
                    if mq.TLO.Me.PctMana() < settings[script].WatchMana then
                        mq.TLO.Me.Sit()
                        status = string.format('Paused for Mana Watch.')
                        return true
                    end
                end
            end
        mq.delay(1)
    end
    return false
end

local interruptInProcess = false
local function CheckInterrupts()
    if not doNav then return false end
    local xCount = mq.TLO.Me.XTarget() or 0
    local flag = false
    if mq.TLO.Window('LootWnd').Open() and interrupts.stopForLoot then
        if not interruptInProcess then mq.cmdf("/squelch /nav stop") interruptInProcess = true end
        status = 'Paused for Looting.'
        flag = true
    elseif mq.TLO.Window('AdvancedLootWnd').Open() and interrupts.stopForLoot then
        if not interruptInProcess then mq.cmdf("/squelch /nav stop") interruptInProcess = true end
        status = 'Paused for Looting.'
        flag = true
    elseif mq.TLO.Me.Combat() and interrupts.stopForCombat then
        if not interruptInProcess then mq.cmdf("/squelch /nav stop") interruptInProcess = true end
        status = 'Paused for Combat.'
        flag = true
    elseif xCount > 0 and interrupts.stopForXtar then
        for i = 1, mq.TLO.Me.XTargetSlots() do
            if mq.TLO.Me.XTarget(i) ~= nil then
                if (mq.TLO.Me.XTarget(i).ID() ~= 0 and mq.TLO.Me.XTarget(i).Type() ~= 'PC' and mq.TLO.Me.XTarget(i).Master.Type() ~= "PC") then
                    if not interruptInProcess then mq.cmdf("/squelch /nav stop") interruptInProcess = true end
                    status = string.format('Paused for XTarget. XTarg Count %s', mq.TLO.Me.XTarget())
                    flag = true
                end
            end
        end
    elseif mq.TLO.Me.Sitting() == true and interrupts.stopForSitting then
        if not interruptInProcess then mq.cmdf("/squelch /nav stop") interruptInProcess = true end
        mq.delay(30)
        local curHP, curMP = mq.TLO.Me.PctHPs(), mq.TLO.Me.PctMana() or 0
        if curHP - lastHP > 10 or curMP - lastMP > 10 then
            lastHP, lastMP = curHP, curMP
            status = string.format('Paused for Sitting. HP %s MP %s', curHP, curMP)
        end
        flag = true
    elseif mq.TLO.Me.Rooted() and interrupts.stopForRoot then
        if not interruptInProcess then mq.cmdf("/squelch /nav stop") interruptInProcess = true end
        status = 'Paused for Rooted.'
        flag = true
    elseif mq.TLO.Me.Feared() and interrupts.stopForFear then
        if not interruptInProcess then mq.cmdf("/squelch /nav stop") interruptInProcess = true end
        status = 'Paused for Feared.'
        flag = true
    elseif mq.TLO.Me.Mezzed() and interrupts.stopForMez then
        if not interruptInProcess then mq.cmdf("/squelch /nav stop") interruptInProcess = true end
        status = 'Paused for Mezzed.'
        flag = true
    elseif mq.TLO.Me.Charmed() and interrupts.stopForCharm then
        if not interruptInProcess then mq.cmdf("/squelch /nav stop") interruptInProcess = true end
        status = 'Paused for Charmed.'
        flag = true
    elseif mq.TLO.Me.Zoning() then
        if not interruptInProcess then mq.cmdf("/squelch /nav stop") interruptInProcess = true end
        status = 'Paused for Zoning.'
        flag = true
    elseif settings[script].GroupWatch == true then
        flag = groupWatch(settings[script].WatchType)
    end
    if flag then
        pauseStart = os.time()
        pauseTime = interruptDelay
    else
        interruptInProcess = false
    end

    return flag
end

--------- Navigation Functions --------

local function ToggleSwitches()
    mq.cmdf("/squelch /multiline ; /doortarget; /timed 10, /click left door")
    mq.delay(500)
    openDoor = not openDoor
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
    
    if doReverse then
        table.sort(tmp, function(a, b) return a.step > b.step end)
    else table.sort(tmp, function(a, b) return a.step < b.step end) end
    return tmp
end

local function NavigatePath(name)
    if not doNav then
        return
    end
    local zone = mq.TLO.Zone.ShortName()
    local startNum = 1
    if currentStepIndex ~= 1 then
        startNum = currentStepIndex
    end
    if doSingle then doNav = true end
    if doLoop then
        table.insert(debugMessages, {Time = os.date("%H:%M:%S"), Zone = zone, Path = name, WP = 'Loop Started', Status = 'Loop Started!'})
    end
    while doNav do
        local tmp = sortPathsTable(zone, name)
        if tmp == nil then
            doNav = false
            status = 'Idle'
            return
        end
        for i = startNum , #tmp do
            if doSingle then i = currentStepIndex end
            currentStepIndex = i
            if not doNav then
                return
            end
            local tmpLoc = string.format("%s:%s", tmp[i].loc, mq.TLO.Me.LocYXZ())
            wpLoc = tmp[i].loc
            tmpLoc = tmpLoc:gsub(",", " ")
            local tmpDist = mq.TLO.Math.Distance(tmpLoc)() or 0
            mq.cmdf("/squelch /nav locyxz %s | distance %s", tmpLoc, stopDist)
            status = "Nav to WP #: "..tmp[i].step.." Distance: "..string.format("%.2f",tmpDist)
            mq.delay(1)
            -- mq.delay(3000, function () return mq.TLO.Me.Speed() > 0 end)
            -- coroutine.yield()  -- Yield here to allow updates
            while mq.TLO.Math.Distance(tmpLoc)() > stopDist do
                if not doNav then
                    return
                end
                if currZone ~= lastZone then
                    selectedPath = 'None'
                    doNav = false
                    pauseTime = 0
                    pauseStart = 0

                    return
                end
                if CheckInterrupts() then
                    coroutine.yield()
                end
                if mq.TLO.Me.Speed() == 0 and not CheckInterrupts() then
                    mq.delay(20)
                    if not mq.TLO.Me.Sitting() then
                        mq.cmdf("/squelch /nav locyxz %s | distance %s", tmpLoc, stopDist)
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

            if doSingle then
                doNav = false
                doSingle = false
                status = 'Idle - Arrived at Destination!'
                loopCount = 0
                return
            end
            -- Check for Commands to execute at Waypoint
            if tmp[i].cmd ~= '' then
                table.insert(debugMessages, {Time = os.date("%H:%M:%S"), Zone = zone, Path = name, WP = 'Command', Status = 'Executing Command: '..tmp[i].cmd})
                if tmp[i].cmd:find("/mypaths stop") then doNav = false end
                mq.cmdf(tmp[i].cmd)
                mq.delay(1)
                coroutine.yield()
            end
            -- Check for Delay at Waypoint
            if tmp[i].delay > 0 then
                status = string.format("Paused %s seconds at WP #: %s", tmp[i].delay, tmp[i].step)
                pauseTime = tmp[i].delay
                pauseStart = os.time()
                coroutine.yield()
                -- coroutine.yield()  -- Yield here to allow updates
            elseif wpPause > 0 then
                status = string.format("Global Paused %s seconds at WP #: %s", wpPause, tmp[i].step)
                pauseTime = wpPause
                pauseStart = os.time()
                coroutine.yield()
                -- coroutine.yield()  -- Yield here to allow updates
            else
                if not interruptFound then
                    pauseTime = 0
                    pauseStart = 0
                end
            end
            -- Door Check
            if tmp[i].door and not doReverse then
                openDoor = true
                ToggleSwitches()
            elseif tmp[i].doorRev and doReverse then
                openDoor = true
                ToggleSwitches()
            end
        end
        -- Check if we need to loop
        if not doLoop then
            doNav = false
            status = 'Idle - Arrived at Destination!'
            loopCount = 0
            break
        else
            loopCount = loopCount + 1
            table.insert(debugMessages, {Time = os.date("%H:%M:%S"), Zone = zone, Path = name, WP = 'Loop #'..loopCount, Status = 'Loop #'..loopCount..' Completed!'})
            currentStepIndex = 1
            startNum = 1
            if doPingPong then
                doReverse = not doReverse
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
        doNav = false
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
        selectedPath = 'None'
        currentStepIndex = 1
        pauseStart = 0
        pauseTime = 0
        zoningHideGUI = true
        showMainGUI = false
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
    local ok, imported_paths = pcall(loadstring(decoded))
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
            local tmpTable = sortPathsTable(currZone, selectedPath) or {}
            local closestWaypointIndex = FindIndexClosestWaypoint(tmpTable)
            local curWPTxt = 1
            if tmpTable[currentStepIndex] ~= nil then
                curWPTxt = tmpTable[currentStepIndex].step or 0
            end
            -- Set Window Font Scale
            ImGui.SetWindowFontScale(scale)
            if ImGui.BeginMenuBar() then
                if ImGui.BeginMenu("Export") then
                    if ImGui.MenuItem("Export Path") then
                        if selectedPath ~= 'None' then
                            local exportData = export_paths(currZone, selectedPath, Paths[currZone][selectedPath])
                            ImGui.LogToClipboard()
                            ImGui.LogText(exportData)
                            ImGui.LogFinish()
        
                            print('\ayPath data copied to clipboard!\ax')
                        else
                            print('\arNo path selected for export!\ax')
                        end
                    end
                    ImGui.EndMenu()
                end

                ImGui.Text(Icon.FA_COG)
                if ImGui.IsItemHovered() then
                    -- Set Tooltip
                    ImGui.SetTooltip("Settings")
                    -- Check if the Gear Icon is clicked
                    if ImGui.IsMouseReleased(0) then
                        -- Toggle Config Window
                        showConfigGUI = not showConfigGUI
                    end
                end
                ImGui.SameLine()
                local lIcon = locked and Icon.FA_LOCK or Icon.FA_UNLOCK
                ImGui.Text(lIcon)
                if ImGui.IsItemHovered() then
                    -- Set Tooltip
                    ImGui.SetTooltip("Toggle Lock Window")
                    -- Check if the Gear Icon is clicked
                    if ImGui.IsMouseReleased(0) then
                        -- Toggle Config Window
                        locked = not locked
                        settings[script].locked = locked
                        mq.pickle(configFile, settings)
                    end
                end
                if DEBUG then
                    ImGui.SameLine()
                    ImGui.Text(Icon.FA_BUG)
                    if ImGui.IsItemHovered() then
                        ImGui.SetTooltip("Debug")
                        if ImGui.IsMouseReleased(0) then
                            showDebugTab = not showDebugTab
                        end
                    end
                end
                ImGui.SameLine()
                ImGui.Text(Icon.MD_TV)
                if ImGui.IsItemHovered() then
                    ImGui.SetTooltip("HUD")
                    if ImGui.IsMouseReleased(0) then
                        showHUD = not showHUD
                    end
                end
                ImGui.SameLine(ImGui.GetWindowWidth() - 30)
                ImGui.Text(Icon.FA_WINDOW_CLOSE)
                if ImGui.IsItemHovered() then
                    ImGui.SetTooltip("Exit\nThe Window Close button will only close the window.\nThis will exit the script completely.\nThe same as typing '/mypaths quit'.")
                    if ImGui.IsMouseReleased(0) then
                        RUNNING = false
                    end
                end
                ImGui.EndMenuBar()
            end
            -- Main Window Content 
            ImGui.Text("Current Zone: ")
            ImGui.SameLine()
            ImGui.TextColored(0,1,0,1,"%s", currZone)
            ImGui.SameLine()
            ImGui.Text("Selected Path: ")
            ImGui.SameLine()
            ImGui.TextColored(0,1,1,1,"%s", selectedPath)
            
            ImGui.Text("Current Loc: ")
            ImGui.SameLine()
            ImGui.TextColored(1,1,0,1,"%s", mq.TLO.Me.LocYXZ())
            if doNav then
                ImGui.Text("Current Destination Waypoint: ")
                ImGui.SameLine()
                ImGui.TextColored(0,1,0,1,"%s", curWPTxt)
                ImGui.Text("Distance to Waypoint: ")
                ImGui.SameLine()
                ImGui.TextColored(0,1,1,1,"%.2f", mq.TLO.Math.Distance(string.format("%s:%s", tmpTable[currentStepIndex].loc:gsub(",", " "), mq.TLO.Me.LocYXZ()))())
            end
            ImGui.Separator()

            if doNav then
                ImGui.PushStyleColor(ImGuiCol.Button, ImVec4(1.0, 0.4, 0.4, 0.4))
                if ImGui.Button('Stop') then
                    doNav = false
                    mq.cmdf("/squelch /nav stop")
                end
                ImGui.PopStyleColor()
                ImGui.SameLine()
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

            ImGui.Separator()
            if ImGui.BeginTabBar('MainTabBar') then
                if ImGui.BeginTabItem('Controls') then
                    if ImGui.CollapsingHeader("Paths##") then

                        ImGui.SetNextItemWidth(150)
                        if ImGui.BeginCombo("##SelectPath", selectedPath) then
                            if not Paths[currZone] then Paths[currZone] = {} end
                            for name, data in pairs(Paths[currZone]) do
                                local isSelected = name == selectedPath
                                if ImGui.Selectable(name, isSelected) then
                                    selectedPath = name
                                end
                            end
                            ImGui.EndCombo()
                        end
                        ImGui.SetNextItemWidth(150)
                        newPath = ImGui.InputText("##NewPathName", newPath)
                        ImGui.SameLine()
                        if ImGui.Button('Create Path') then
                            CreatePath(newPath)
                            selectedPath = newPath
                            newPath = ''
                        end
                        if selectedPath ~= 'None' then
                            ImGui.SameLine()
                            if ImGui.Button('Copy Path') then
                                CreatePath(newPath)
                                for i = 1, #Paths[currZone][selectedPath] do
                                    table.insert(Paths[currZone][newPath], Paths[currZone][selectedPath][i])
                                end
                                SavePaths()
                                selectedPath = newPath
                                newPath = ''
                            end
                        end

                        if ImGui.Button('Delete Path') then
                            DeletePath(selectedPath)
                            selectedPath = 'None'
                        end
                        ImGui.SameLine()
                        if ImGui.Button('Save Paths') then
                            SavePaths()
                        end
                        importString   = ImGui.InputText("##ImportString", importString)
                        ImGui.SameLine()
                        if ImGui.Button('Import Path') then
                            local imported = import_paths(importString)
                            if imported then
                                for zone, paths in pairs(imported) do
                                    if not Paths[zone] then Paths[zone] = {} end
                                    for pathName, pathData in pairs(paths) do
                                        Paths[zone][pathName] = pathData
                                        if currZone == zone then selectedPath = pathName end
                                    end
                                end
                                importString = ''
                                SavePaths()
                            end
                        end
    
                    end

                    if selectedPath ~= 'None' then

                        -- Navigation Controls

                        if ImGui.CollapsingHeader("Navigation##") then
                            if not doNav then doReverse = ImGui.Checkbox('Reverse Order', doReverse) ImGui.SameLine() end
                            
                            doLoop = ImGui.Checkbox('Loop Path', doLoop)
                            ImGui.SameLine()
                            doPingPong = ImGui.Checkbox('Ping Pong', doPingPong)
                            if doPingPong then
                                doLoop = true
                            end
                            ImGui.Separator()
                            if not Paths[currZone] then Paths[currZone] = {} end

                            local tmpLabel = doNav and 'Stop Navigation' or 'Start Navigation'
                            if doNav then
                                ImGui.PushStyleColor(ImGuiCol.Button, ImVec4(1.0, 0.4, 0.4, 0.4))
                            else
                                ImGui.PushStyleColor(ImGuiCol.Button, ImVec4(0.4, 1.0, 0.4, 0.4))
                            end
                            if ImGui.Button(tmpLabel) then
                                doNav = not doNav
                                if not doNav then
                                    mq.cmdf("/squelch /nav stop")
                                end
                            end
                            ImGui.PopStyleColor()
                            ImGui.SameLine()
                            if ImGui.Button("Start at Closest") then
                                currentStepIndex = closestWaypointIndex
                                doNav = true
                            end
                            ImGui.SetNextItemWidth(100)
                            stopDist = ImGui.InputInt("Stop Distance##"..script, stopDist, 1, 50)
                            ImGui.SetNextItemWidth(100)
                            wpPause = ImGui.InputInt("Global Pause##"..script, wpPause, 1,5 )
                        end

                    end
                    ImGui.EndTabItem()
                end
                if ImGui.BeginTabItem('Path Data') then
                    if selectedPath ~= 'None' then
                        if ImGui.CollapsingHeader("Manage Waypoints##") then
                                    
                            if ImGui.Button('Add Waypoint') then
                                RecordWaypoint(selectedPath)
                            end
                            ImGui.SameLine()
                            if ImGui.Button('Clear Waypoints') then
                                ClearWaypoints(selectedPath)
                            end
                            
                            local label = autoRecord and 'Stop Recording' or 'Start Recording'
                            if autoRecord then
                                ImGui.PushStyleColor(ImGuiCol.Button, ImVec4(1.0, 0.4, 0.4, 0.4))
                            else
                                ImGui.PushStyleColor(ImGuiCol.Button, ImVec4(0.4, 1.0, 0.4, 0.4))
                            end
                            if ImGui.Button(label) then
                                autoRecord = not autoRecord
                                if autoRecord then 
                                    if DEBUG then table.insert(debugMessages, {Time = os.date("%H:%M:%S"), Zone = mq.TLO.Zone.ShortName(), Path = selectedPath, WP = 'Start Recording', Status = 'Start Recording Waypoints!'}) end
                                else
                                    if DEBUG then table.insert(debugMessages, {Time = os.date("%H:%M:%S"), Zone = mq.TLO.Zone.ShortName(), Path = selectedPath, WP = 'Stop Recording', Status = 'Stop Recording Waypoints!'}) end
                                end
                            end
                            ImGui.PopStyleColor()
                            ImGui.SameLine()
                            ImGui.SetNextItemWidth(100)
                            recordDelay = ImGui.InputInt("Auto Record Delay##"..script, recordDelay, 1, 10)
                        end
                        ImGui.Separator()
                    end
                    if ImGui.CollapsingHeader("Waypoint Table##Header") then
                        -- Waypoint Table
                        if selectedPath ~= 'None' then

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
                                    ImGui.Text("%s", tmpTable[i].step)
                                    if i == closestWaypointIndex then
                                        ImGui.SameLine()
                                        ImGui.TextColored(ImVec4(1, 1, 0, 1), Icon.MD_STAR)
                                    end
                                    ImGui.TableSetColumnIndex(1)
                                    ImGui.Text(tmpTable[i].loc)
                                    if not doNav then
                                        if ImGui.BeginPopupContextItem("WP_" .. tmpTable[i].step) then
                                            
                                            if ImGui.MenuItem('Nav to WP ' .. tmpTable[i].step) then
                                                currentStepIndex = i
                                                doNav = true
                                                doLoop = false
                                                doSingle = true
                                            end
                                            
                                            if ImGui.MenuItem('Start Path Here: WP ' .. tmpTable[i].step) then
                                                currentStepIndex = i
                                                doNav = true
                                                doLoop = false
                                                doSingle = false
                                            end
                                            if ImGui.MenuItem('Start Loop Here: WP ' .. tmpTable[i].step) then
                                                currentStepIndex = i
                                                doNav = true
                                                doLoop = true
                                                doSingle = false
                                            end
                                        
                                            ImGui.EndPopup()
                                        end
                                    end
                                    ImGui.TableSetColumnIndex(2)
                                    ImGui.SetNextItemWidth(90)
                                    tmpTable[i].delay, changed = ImGui.InputInt("##delay_" .. i, tmpTable[i].delay, 1, 1)
                                    if changed then
                                        for k, v in pairs(Paths[currZone][selectedPath]) do
                                            if v.step == tmpTable[i].step then
                                                Paths[currZone][selectedPath][k].delay = tmpTable[i].delay
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
                                        for k, v in pairs(Paths[currZone][selectedPath]) do
                                            if v.step == tmpTable[i].step then
                                                Paths[currZone][selectedPath][k].cmd = tmpTable[i].cmd
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
                                        for k, v in pairs(Paths[currZone][selectedPath]) do
                                            if v.step == tmpTable[i].step then
                                                Paths[currZone][selectedPath][k].door = tmpTable[i].door
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
                                        for k, v in pairs(Paths[currZone][selectedPath]) do
                                            if v.step == tmpTable[i].step then
                                                Paths[currZone][selectedPath][k].doorRev = tmpTable[i].doorRev
                                                SavePaths()
                                            end
                                        end
                                    end
                                    if ImGui.IsItemHovered() then
                                        ImGui.SetTooltip("Door Reverse")
                                    end
                                    ImGui.TableSetColumnIndex(5)
                                    if not doNav then
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
                                            Paths[currZone][selectedPath][tmpTable[i].step].loc = mq.TLO.Me.LocYXZ()
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
                                            for k, v in pairs(Paths[currZone][selectedPath]) do
                                                if v.step == tmpTable[i].step then
                                                    Paths[currZone][selectedPath][k] = tmpTable[i]
                                                elseif v.step == tmpTable[i - 1].step then
                                                    Paths[currZone][selectedPath][k] = tmpTable[i - 1]
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
                                            for k, v in pairs(Paths[currZone][selectedPath]) do
                                                if v.step == tmpTable[i].step then
                                                    Paths[currZone][selectedPath][k] = tmpTable[i]
                                                elseif v.step == tmpTable[i + 1].step then
                                                    Paths[currZone][selectedPath][k] = tmpTable[i + 1]
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
                ImGui.EndTabItem()
                end
                if showDebugTab then
                    if ImGui.BeginTabItem('Debug Messages') then
                        if ImGui.Button('Clear Debug Messages') then
                            debugMessages = {}
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
                            for i = 1, #debugMessages do
                                ImGui.TableNextRow()
                                ImGui.TableSetColumnIndex(0)
                                ImGui.Text(debugMessages[i].Time)
                                ImGui.TableSetColumnIndex(1)
                                ImGui.Text(debugMessages[i].Zone)
                                ImGui.TableSetColumnIndex(2)
                                ImGui.Text(debugMessages[i].Path)
                                ImGui.TableSetColumnIndex(3)
                                ImGui.Text(debugMessages[i].WP)
                                ImGui.TableSetColumnIndex(4)
                                ImGui.Text(debugMessages[i].Status)
                            end
                            ImGui.EndTable()
                        end
                        ImGui.EndTabItem()
                    end
                end
                ImGui.EndTabBar()
            end
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
                    interrupts.stopForAll = ImGui.Checkbox("Stop for All##"..script, interrupts.stopForAll)
                    if interrupts.stopForAll then
                        
                        interrupts.stopForCharm = true
                        interrupts.stopForCombat = true
                        interrupts.stopForFear = true
                        interrupts.stopForGM = true
                        interrupts.stopForLoot = true
                        interrupts.stopForMez = true
                        interrupts.stopForRoot = true
                        interrupts.stopForSitting = true
                        interrupts.stopForXtar = true
                    end
                    if ImGui.BeginTable("##Interrupts", 2, bit32.bor(ImGuiTableFlags.Borders), -1,0) then
                        ImGui.TableNextRow()
                        ImGui.TableSetColumnIndex(0)
                        interrupts.stopForCharm = ImGui.Checkbox("Stop for Charmed##"..script, interrupts.stopForCharm)
                        if not interrupts.stopForCharm then interrupts.stopForAll = false end
                        ImGui.TableSetColumnIndex(1)
                        interrupts.stopForCombat = ImGui.Checkbox("Stop for Combat##"..script, interrupts.stopForCombat)
                        if not interrupts.stopForCombat then interrupts.stopForAll = false end
                        ImGui.TableNextRow()

                        ImGui.TableSetColumnIndex(0)
                        interrupts.stopForFear = ImGui.Checkbox("Stop for Fear##"..script, interrupts.stopForFear)
                        if not interrupts.stopForFear then interrupts.stopForAll = false end
                        ImGui.TableSetColumnIndex(1)
                        interrupts.stopForGM = ImGui.Checkbox("Stop for GM##"..script, interrupts.stopForGM)
                        if not interrupts.stopForGM then interrupts.stopForAll = false end
                        ImGui.TableNextRow()

                        ImGui.TableSetColumnIndex(0)
                        interrupts.stopForLoot = ImGui.Checkbox("Stop for Loot##"..script, interrupts.stopForLoot)
                        if not interrupts.stopForLoot then interrupts.stopForAll = false end
                        ImGui.TableSetColumnIndex(1)
                        interrupts.stopForMez = ImGui.Checkbox("Stop for Mez##"..script, interrupts.stopForMez)
                        if not interrupts.stopForMez then interrupts.stopForAll = false end
                        ImGui.TableNextRow()

                        ImGui.TableSetColumnIndex(0)
                        interrupts.stopForRoot = ImGui.Checkbox("Stop for Root##"..script, interrupts.stopForRoot)
                        if not interrupts.stopForRoot then interrupts.stopForAll = false end
                        ImGui.TableSetColumnIndex(1)
                        interrupts.stopForSitting = ImGui.Checkbox("Stop for Sitting##"..script, interrupts.stopForSitting)
                        if not interrupts.stopForSitting then interrupts.stopForAll = false end
                        ImGui.TableNextRow()

                        ImGui.TableSetColumnIndex(0)
                        interrupts.stopForXtar = ImGui.Checkbox("Stop for Xtarget##"..script, interrupts.stopForXtar)
                        if not interrupts.stopForXtar then interrupts.stopForAll = false end
                        ImGui.EndTable()
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
                recordDelay = ImGui.InputInt("Record Delay##"..script, recordDelay, 1, 5)
                -- Minimum Distance Between Waypoints
                ImGui.SetNextItemWidth(100)
                recordMinDist = ImGui.InputInt("Min Dist. Between WP##"..script, recordMinDist, 1, 50)

                ImGui.SeparatorText("Navigation Settings##"..script)
                -- Set Stop Distance
                ImGui.SetNextItemWidth(100)
                stopDist = ImGui.InputInt("Stop Distance##"..script, stopDist, 1, 50)
                -- Set Waypoint Pause time
                ImGui.SetNextItemWidth(100)
                wpPause = ImGui.InputInt("Waypoint Pause##"..script, wpPause, 1, 5)
                -- Set Interrupt Delay
                ImGui.SetNextItemWidth(100)
                interruptDelay = ImGui.InputInt("Interrupt Delay##"..script, interruptDelay, 1, 5)

                -- Save & Close Button --
                if ImGui.Button("Save & Close") then
                    settings[script].HeadsUpTransparency = hudTransparency
                    settings[script].Scale = scale
                    settings[script].LoadTheme = themeName
                    settings[script].locked = locked
                    settings[script].AutoSize = aSize
                    settings[script].RecordDelay = recordDelay
                    settings[script].StopForGM = interrupts.stopForGM
                    settings[script].StopDistance = stopDist
                    settings[script].RecordMinDist = recordMinDist
                    settings[script].PauseStops = wpPause
                    settings[script].InterruptDelay = interruptDelay
                    mq.pickle(configFile, settings)
                    showConfigGUI = false
                end
            end
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
            if ImGui.IsWindowHovered() then
                transFlag = true
                if ImGui.IsMouseDoubleClicked(0) then
                    showMainGUI = not showMainGUI
                end
                ImGui.SetTooltip("Double Click to Toggle Main GUI")
            else
                transFlag = false
            end
            ImGui.Text("Current Zone: ")
            ImGui.SameLine()
            ImGui.TextColored(0,1,0,1,"%s", currZone)
            ImGui.SameLine()
            ImGui.Text("Selected Path: ")
            ImGui.SameLine()
            ImGui.TextColored(0,1,1,1,"%s", selectedPath)
            ImGui.Text("Current Loc: ")
            ImGui.SameLine()
            ImGui.TextColored(1,1,0,1,"%s", mq.TLO.Me.LocYXZ())
            if doNav then
                ImGui.Text("Distance to Waypoint: ")
                ImGui.SameLine()
    
                local tmpTable = sortPathsTable(currZone, selectedPath) or {}
                ImGui.TextColored(0,1,1,1,"%.2f", mq.TLO.Math.Distance(string.format("%s:%s", tmpTable[currentStepIndex].loc:gsub(",", " "), mq.TLO.Me.LocYXZ()))())
            end

            ImGui.Text("Nav Type: ")
            ImGui.SameLine()
            if not doNav then
                ImGui.TextColored(ImVec4(0, 1, 0, 1), "None")
            else
                if doPingPong then
                    ImGui.TextColored(ImVec4(0, 1, 0, 1), "Ping Pong")
                elseif doLoop then
                    ImGui.TextColored(ImVec4(0, 1, 0, 1), "Loop ")
                    ImGui.SameLine()
                    ImGui.TextColored(ImVec4(0, 1, 1, 1), "(%s)", loopCount)
                elseif doSingle then
                    ImGui.TextColored(ImVec4(0, 1, 0, 1), "Single")
                else 
                    ImGui.TextColored(ImVec4(0, 1, 0, 1), "Normal")
                end
                ImGui.SameLine()
                ImGui.Text("Reverse: ")
                ImGui.SameLine()
                if doReverse then
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
            end
        end
        ImGui.PopStyleColor()
        ImGui.End()
    end

    -- Import Path Data Popup
    if ImGui.BeginPopup("Import Path Data") then
        local importData = ImGui.InputTextMultiline("Import Path Data", "", 2048)
        if importData ~= "" then
            local importedPaths = import_paths(importData)
            if importedPaths then
                Paths[currZone][selectedPath] = importedPaths
                SavePaths()
                print('\ayPath imported successfully!\ax')
            else
                print('\arFailed to import path data!\ax')
            end
        end
        ImGui.EndPopup()
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
end

local function bind(...)
    local args = {...}
    local key = args[1]
    local action = args[2]
    local path = args[3]
    local zone = mq.TLO.Zone.ShortName()

    if #args == 1 then
        if key == 'stop' then
            doNav = false
            mq.cmdf("/squelch /nav stop")
            selectedPath = 'None'
            loadPaths()
        elseif key == 'help' then
            displayHelp()
        elseif key == 'debug' then
            DEBUG = not DEBUG
        elseif key == 'hud' then
            showHUD = not showHUD
        elseif key == 'show' then
            showMainGUI = not showMainGUI
        elseif key == 'quit' or key == 'exit' then
            -- mq.exit()
            mq.cmd("/squelch /nav stop")
            mq.TLO.Me.Stand()
            mq.delay(1)
            doNav = false
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
    elseif #args  == 3 then
        if Paths[zone]["'"..path.."'"] ~= nil then
            printf("\ay[\at%s\ax] \arInvalid Path!", script)
            return
        end
        if key == 'go' then
            if action == 'loop' then
                selectedPath = path
                doReverse = false
                doNav = true
                doLoop = true
            end
            if action == 'rloop' then
                selectedPath = path
                doReverse = true
                doNav = true
                doLoop = true
            end
            if action == 'start' then
                selectedPath = path
                doReverse = false
                doNav = true
                doLoop = false
            end
            if action == 'reverse' then
                selectedPath = path
                doReverse = true
                doNav = true
            end
            if action == 'pingpong' then
                selectedPath = path
                doPingPong = true
                doNav = true
            end
            if action == 'closest' then
                selectedPath = path
                doNav = true
                doReverse = false
                currentStepIndex = FindIndexClosestWaypoint(Paths[zone][path])
            end
            if action == 'rclosest' then
                selectedPath = path
                doNav = true
                doReverse = true
                currentStepIndex = FindIndexClosestWaypoint(Paths[zone][path])
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
        currZone = mq.TLO.Zone.ShortName()
        if mq.TLO.Me.Zoning() == true then
            printf("\ay[\at%s\ax] \agZoning, \ayPausing Navigation...", script)
            ZoningPause()
        end
        -- if pauseStart > 0 then print("Pause Start: "..pauseStart) end
        if currZone ~= lastZone then
            selectedPath = 'None'
            doNav = false
            lastZone = currZone
            currentStepIndex = 1
            autoRecord = false
            pauseTime = 0
            status = 'Idle'
            pauseStart = 0
            printf("\ay[\at%s\ax] \agZone Changed Last: \at%s Current: \ay%s", script, lastZone, currZone)
        end

        if mq.TLO.SpawnCount('gm')() > 0 and interrupts.stopForGM then
            printf("\ay[\at%s\ax] \arGM Detected, \ayPausing Navigation...", script)
            doNav = false
            mq.cmdf("/squelch /nav stop")
            mq.cmd("/multiline ; /squelch /beep; /timed  3, /beep ; /timed 2, /beep ; /timed 1, /beep")
            mq.delay(1)
            status = 'Paused: GM Detected'
        end

        if zoningHideGUI then
            printf("\ay[\at%s\ax] \agZoning, \ayHiding GUI...", script)
            mq.delay(1)
            showMainGUI = true
            zoningHideGUI = false
            currentStepIndex = 1
            selectedPath = 'None'
            doNav = false
            table.insert(debugMessages, {Time = os.date("%H:%M:%S"), Zone = mq.TLO.Zone.ShortName(), Path = selectedPath, WP = 1, Status = 'Finished Zoning'})
            mq.delay(1)
            status = 'Idle'
            if currZone ~= lastZone then
                selectedPath = 'None'
                doNav = false
                lastZone = currZone
                pauseTime = 0
                pauseStart = 0
                printf("\ay[\at%s\ax] \agZone Changed Last: \at%s Current: \ay%s", script, lastZone, currZone)
            end
        end
        
        if not mq.TLO.Me.Sitting() then 
            lastHP, lastMP = 0,0
        end

        -- Make sure we are still in game or exit the script.
        if mq.TLO.EverQuest.GameState() ~= "INGAME" then
            printf("\aw[\at%s\ax] \arNot in game, \ayTry again later...", script)
            mq.exit()
        end

        if doNav then
            mq.delay(5)
            interruptFound = CheckInterrupts()
        end
        
        if doNav and not interruptFound then

            if previousDoNav ~= doNav then
                -- Reset the coroutine since doNav changed from false to true
                co = coroutine.create(NavigatePath)
            end

            local curTime = os.time()
                
            -- If the coroutine is not dead, resume it
            if coroutine.status(co) ~= "dead" then
                -- Check if we need to pause
                if pauseStart > 0 then
                    if curTime - pauseStart > pauseTime then
                        -- Time is up, resume the coroutine and reset the timer values
                        pauseTime = 0
                        pauseStart = 0
                        local success, message = coroutine.resume(co, selectedPath)
                        if not success then
                            print("Error: " .. message)
                            -- Reset coroutine on error
                            co = coroutine.create(NavigatePath)
                        end
                    end
                else
                    -- Resume the coroutine we are do not need to pause
                    local success, message = coroutine.resume(co, selectedPath)
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
        elseif not doNav and not autoRecord then
            -- Reset state when doNav is false
            currentStepIndex = 1
            status = 'Idle'
        end

        -- Update previousDoNav to the current state
        previousDoNav = doNav

        if autoRecord then
            AutoRecordPath(selectedPath)
        end

        if deleteWP then
            RemoveWaypoint(selectedPath, deleteWPStep)
            if DEBUG then table.insert(debugMessages, {Time = os.date("%H:%M:%S"), Zone = mq.TLO.Zone.ShortName(), Path = selectedPath, WP = 'Delete  #'..deleteWPStep, Status = 'Waypoint #'..deleteWPStep..' Removed Successfully!'}) end
            deleteWPStep = 0
            deleteWP = false
        end

        if DEBUG then
            if lastStatus ~= status then
                local statTxt = status
                if status:find("Distance") then
                    statTxt = statTxt:gsub("Distance:", "Dist:")
                end
                table.insert(debugMessages, {Time = os.date("%H:%M:%S"), WP = currentStepIndex, Status = statTxt, Path = selectedPath, Zone = mq.TLO.Zone.ShortName()})
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

        mq.delay(10)
    end
end

-- Make sure we are in game before running the script
if mq.TLO.EverQuest.GameState() ~= "INGAME" then 
    printf("\aw[\at%s\ax] \arNot in game, \ayTry again later...", script) 
    mq.exit() 
end
Init()
Loop()
