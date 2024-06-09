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

-- Variables
local script = 'MyPaths' -- Change this to the name of your script
local meName -- Character Name
local themeName = 'Default'
local gIcon = Icon.MD_SETTINGS -- Gear Icon for Settings
local rIcon -- resize icon variable holder
local lIcon -- lock icon variable holder
local upIcon = Icon.FA_CHEVRON_UP -- Up Arrow Icon
local downIcon = Icon.FA_CHEVRON_DOWN -- Down Arrow Icon
local themeID = 1
local theme, defaults, settings, debugMessages = {}, {}, {}, {}
local Paths = {}
local selectedPath = 'None'
local newPath = ''
local curTime = os.time()
local lastTime = curTime
local autoRecord, doNav, doSingle, doLoop, doReverse, doPingPong = false, false, false, false, false, false
local recordDelay, stopDist, wpPause = 5, 30, 1
local currentStepIndex = 1
local deleteWP, deleteWPStep = false, 0
local status, lastStatus = 'Idle', ''
local wpLoc = ''
local currZone, lastZone = '', ''
local lastHP, lastMP, pauseTime = 0, 0, 0
local pauseStart = 0
local previousDoNav = false
local zoningHideGUI = false
local ZoningPause

-- GUI Settings
local winFlags = bit32.bor(ImGuiWindowFlags.None, ImGuiWindowFlags.MenuBar)
local RUNNING, DEBUG = true, false
local showMainGUI, showConfigGUI, showDebugGUI, showHUD = true, false, false, false
local scale = 1
local aSize, locked, hasThemeZ = false, false, false
local hudTransparency = 0.5

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
	RecordDlay = 5,
	HeadsUpTransparency = 0.5,
	StopDistance = 30,
	PauseStops = 1,
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
	locked = settings[script].locked
	scale = settings[script].Scale
	themeName = settings[script].LoadTheme
	recordDelay = settings[script].RecordDelay

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
	if tmp[index] ~= nil then
		if tmp[index].loc == loc then return end
		table.insert(tmp, {step = index + 1, loc = loc, delay = 0, cmd = ''})
		index = index + 1
	else
		table.insert(tmp, {step = 1, loc = loc, delay = 0, cmd = ''})
		index = 1
	end
	Paths[zone][name] = tmp
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

local function ScanXtar()
	if mq.TLO.Me.XTarget() > 0 then
		for i = 1, mq.TLO.Me.XTargetSlots() do
			local xTarg = mq.TLO.Me.XTarget(i)
			local xCount = mq.TLO.Me.XTarget() or 0
			local xName, xType = xTarg.Name(), xTarg.Type()
			if (xCount > 0) then
				if ((xTarg.Name() ~= 'NULL' and xTarg.ID() ~= 0) and (xType ~= 'Corpse') and (xType ~= 'Chest') and (xTarg.Master.Type() ~= 'PC')) then
					return true
				end
			end
		end
	end
	return false
end

local function CheckInterrupts()
	if mq.TLO.Window('LootWnd').Open() or mq.TLO.Window('AdvancedLootWnd').Open() then return true end
	if mq.TLO.Me.Combat() or ScanXtar() or mq.TLO.Me.Sitting() or mq.TLO.Me.Rooted() or mq.TLO.Me.Feared() or mq.TLO.Me.Mezzed() or mq.TLO.Me.Charmed() then
		return true
	end
	return false
end

--------- Navigation Functions --------



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
				local function processDelay()
					-- coroutine.yield()  -- Yield here to allow updates
					while mq.TLO.Window('LootWnd').Open() do
						status = 'Paused for Looting.'
						if not doNav then
							return
						end
						mq.delay(1)
						coroutine.yield()  -- Yield here to allow updates
					end
					while mq.TLO.Window('AdvancedLootWnd').Open() do
						status = 'Paused for Looting.'
						if not doNav then
							return
						end
						mq.delay(1)
						coroutine.yield()  -- Yield here to allow updates
					end
					while mq.TLO.Me.Combat() do
						status = 'Paused for Combat.'
						if not doNav then
							return
						end
						mq.delay(1)
						coroutine.yield()  -- Yield here to allow updates
					end
					while mq.TLO.Me.Sitting() == true do
						local curHP, curMP = mq.TLO.Me.PctHPs(), mq.TLO.Me.PctMana()
						if curHP - lastHP > 10 or curMP - lastMP > 10 then
							lastHP, lastMP = curHP, curMP
							status = string.format('Paused for Sitting. HP %s MP %s', curHP, curMP)
						end
						-- status = string.format('Paused for Sitting. HP %s MP %s', curHP, curMP)
						if not doNav then
							return
						end
						mq.delay(1)
						coroutine.yield()  -- Yield here to allow updates
					end
					while mq.TLO.Me.Rooted() do
						status = 'Paused for Rooted.'
						if not doNav then
							return
						end
						mq.delay(1)
						coroutine.yield()  -- Yield here to allow updates
					end
					while mq.TLO.Me.Feared() do
						status = 'Paused for Feared.'
						if not doNav then
							return
						end
						mq.delay(1)
						coroutine.yield()  -- Yield here to allow updates
					end
					while mq.TLO.Me.Mezzed() do
						status = 'Paused for Mezzed.'
						if not doNav then
							return
						end
						mq.delay(1)
						coroutine.yield()  -- Yield here to allow updates
					end
					while mq.TLO.Me.Charmed() do
						status = 'Paused for Charmed.'
						if not doNav then
							return
						end
						mq.delay(1)
						coroutine.yield()  -- Yield here to allow updates
					end
					if ScanXtar() then
						status = string.format('Paused for XTarget. XTarg Count %s', mq.TLO.Me.XTarget())
						if not doNav then
							return
						end
						mq.delay(1)
						coroutine.yield()  -- Yield here to allow updates
					end
				end


				if CheckInterrupts() then
					-- mq.cmdf("/squelch /nav stop")
					status = "Paused Interrupt detected."
					mq.delay(10)

					while CheckInterrupts() do
						processDelay()
					end

					mq.delay(1)
					mq.cmdf("/squelch /nav locyxz %s | distance %s", tmpLoc, stopDist)
					tmpLoc = string.format("%s:%s", tmp[i].loc, mq.TLO.Me.LocYXZ())
					tmpLoc = tmpLoc:gsub(",", " ")
					tmpDist = mq.TLO.Math.Distance(tmpLoc)() or 0
					status = "Nav to WP #: "..tmp[i].step.." Distance: "..string.format("%.2f",tmpDist)
					coroutine.yield()
				end

				if mq.TLO.Me.Speed() == 0 then
					mq.delay(1)
					coroutine.yield()
					if CheckInterrupts() then processDelay()
					elseif mq.TLO.Me.Speed() == 0 then
						status = "Paused because we have Stopped!"
						mq.delay(100,  function () return mq.TLO.Me.Speed() > 0 end)
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

			coroutine.yield()
			mq.cmdf("/squelch /nav stop")
			status = "Arrived at WP #: "..tmp[i].step
			if doSingle then
				doNav = false
				doSingle = false
				status = 'Idle - Arrived at Destination!'
				return
			end
			-- Check for Commands to execute at Waypoint
			if tmp[i].cmd ~= '' then
				mq.cmdf(tmp[i].cmd)
				mq.delay(1)
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
				pauseTime = 0
				pauseStart = 0
			end
		end
		-- Check if we need to loop
		if not doLoop then
			doNav = false
			status = 'Idle - Arrived at Destination!'
			break
		else
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
-------- GUI Functions --------
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
			-- Set Window Font Scal
			ImGui.SetWindowFontScale(scale)
			if ImGui.BeginMenuBar() then
				
				ImGui.Text(gIcon)
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
				rIcon = aSize and Icon.FA_EXPAND or Icon.FA_COMPRESS
				ImGui.Text(rIcon)
				if ImGui.IsItemHovered() then
					-- Set Tooltip
					ImGui.SetTooltip("Toggle Auto Size")
					-- Check if the Gear Icon is clicked
					if ImGui.IsMouseReleased(0) then
						-- Toggle Config Window
						aSize = not aSize
					end
				end
				ImGui.SameLine()
				lIcon = locked and Icon.FA_LOCK or Icon.FA_UNLOCK
				ImGui.Text(lIcon)
				if ImGui.IsItemHovered() then
					-- Set Tooltip
					ImGui.SetTooltip("Toggle Lock Window")
					-- Check if the Gear Icon is clicked
					if ImGui.IsMouseReleased(0) then
						-- Toggle Config Window
						locked = not locked
					end
				end
				if DEBUG then
					ImGui.SameLine()
					ImGui.Text(Icon.FA_BUG)
					if ImGui.IsItemHovered() then
						ImGui.SetTooltip("Debug")
						if ImGui.IsMouseReleased(0) then
							showDebugGUI = not showDebugGUI
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

				if ImGui.Button('Delete Path') then
					DeletePath(selectedPath)
					selectedPath = 'None'
				end
				ImGui.SameLine()
				if ImGui.Button('Save Paths') then
					SavePaths()
				end
			end

			local tmpTable = sortPathsTable(currZone, selectedPath) or {}
			local closestWaypointIndex = FindIndexClosestWaypoint(tmpTable)
			
			if selectedPath ~= 'None' then
				if ImGui.CollapsingHeader("Waypoints##") then
						
					if ImGui.Button('Add Waypoint') then
						RecordWaypoint(selectedPath)
					end
					ImGui.SameLine()
					if ImGui.Button('Clear Waypoints') then
						ClearWaypoints(selectedPath)
					end
					ImGui.SameLine()
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
					ImGui.SetNextItemWidth(100)
					recordDelay = ImGui.InputInt("Auto Record Delay##"..script, recordDelay, 1, 10)
				end

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
				local curWPTxt = 1
				if tmpTable[currentStepIndex] ~= nil then
					curWPTxt = tmpTable[currentStepIndex].step or 0
				end
				if doNav then
					ImGui.Text("Current Destination Waypoint: ")
					ImGui.SameLine()
					ImGui.TextColored(0,1,0,1,"%s", curWPTxt)
					ImGui.Text("Distance to Waypoint: ")
					ImGui.SameLine()
					ImGui.TextColored(0,1,1,1,"%.2f", mq.TLO.Math.Distance(string.format("%s:%s", tmpTable[currentStepIndex].loc:gsub(",", " "), mq.TLO.Me.LocYXZ()))())
				end
				ImGui.Separator()
				ImGui.Text("Status: ")
				
				ImGui.SameLine()
				if status:find("Idle") then
					ImGui.TextColored(ImVec4(0, 1, 1, 1), status)
				elseif status:find("Paused") then
					ImGui.TextColored(ImVec4(0.9, 0.4, 0.4, 1), status)
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
					-- tmpStatus = tmpStatus:sub(1, tmpStatus:find("Distance") - 1)
					-- tmpStatus = string.format("%s Distance: %s",status,dist)
					-- ImGui.TextColored(ImVec4(1,1,0,1), tmpStatus)
				end
				ImGui.Separator()

				-- Waypoint Table
				if ImGui.BeginTable('PathTable', 5, bit32.bor(ImGuiTableFlags.Borders, ImGuiTableFlags.RowBg, ImGuiTableFlags.ScrollY, ImGuiTableFlags.Resizable, ImGuiTableFlags.Reorderable, ImGuiTableFlags.Hideable), -1, -1) then
					ImGui.TableSetupColumn('WP#', ImGuiTableColumnFlags.None, -1)
					ImGui.TableSetupColumn('Loc', ImGuiTableColumnFlags.None, -1)
					ImGui.TableSetupColumn('Delay', ImGuiTableColumnFlags.None, -1)
					ImGui.TableSetupColumn('Actions', ImGuiTableColumnFlags.None, -1)
					ImGui.TableSetupColumn('Move', ImGuiTableColumnFlags.None, -1)
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
						ImGui.TableSetColumnIndex(4)
						if not doNav then
							if ImGui.Button(Icon.FA_TRASH .. "##_" .. i) then
								deleteWP = true
								deleteWPStep = tmpTable[i].step
							end
							ImGui.SameLine(0,0)
							if i > 1 and ImGui.Button(upIcon .. "##up_" .. i) then
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
							if i < #tmpTable and ImGui.Button(downIcon .. "##down_" .. i) then
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

				-- Configure ThemeZ --
				ImGui.SeparatorText("Theme##"..script)
				ImGui.Text("Cur Theme: %s", themeName)

				-- Combo Box Load Theme
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

				ImGui.SeparatorText("MyPaths Settings##"..script)
				-- HUD Transparency --
				hudTransparency = ImGui.SliderFloat("HUD Transparency##"..script, hudTransparency, 0.0, 1)

				-- Set RecordDley
				recordDelay = ImGui.InputInt("Record Delay##"..script, recordDelay, 1, 5)
				-- Set Stop Distance
				stopDist = ImGui.InputInt("Stop Distance##"..script, stopDist, 1, 50)
				-- Set Waypoint Pause time
				wpPause = ImGui.InputInt("Waypoint Pause##"..script, wpPause, 1, 5)

				-- Save & Close Button --
				if ImGui.Button("Save & Close") then
					settings = dofile(configFile)
					settings[script].HeadsUpTransparency = hudTransparency
					settings[script].Scale = scale
					settings[script].LoadTheme = themeName
					settings[script].locked = locked
					settings[script].AutoSize = aSize
					settings[script].RecordDelay = recordDelay
					settings[script].StopDistance = stopDist
					settings[script].PauseStops = wpPause
					mq.pickle(configFile, settings)
					showConfigGUI = false
				end
			end
			LoadTheme.EndTheme(ColCntConf, StyCntConf)
			ImGui.End()
	end

	if showDebugGUI then
		if mq.TLO.Me.Zoning() then return end
		local ColorCount, StyleCount = LoadTheme.StartTheme(theme.Theme[themeID])
		local openDebug, showDebug = ImGui.Begin("Debug Messages", true, bit32.bor(ImGuiWindowFlags.NoCollapse, ImGuiWindowFlags.NoFocusOnAppearing))
		if not openDebug then
			showDebugGUI = false
		end
		if showDebug then
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
		end
		LoadTheme.EndTheme(ColorCount, StyleCount)
		ImGui.End()
	end

	if showHUD then
		if mq.TLO.Me.Zoning() then return end
		ImGui.PushStyleColor(ImGuiCol.WindowBg, ImVec4(0.0, 0.0, 0.0, hudTransparency))
		local openHUDWin, showHUDWin = ImGui.Begin("MyPaths HUD##HUD", true, bit32.bor(ImGuiWindowFlags.NoCollapse, ImGuiWindowFlags.AlwaysAutoResize, ImGuiWindowFlags.NoTitleBar))
		if not openHUDWin then
			ImGui.PopStyleColor()
			showHUD = false
		end
		if showHUDWin then
			if ImGui.IsWindowHovered() then
				if ImGui.IsMouseDoubleClicked(0) then
					showMainGUI = not showMainGUI
				end
				ImGui.SetTooltip("Double Click to Toggle Main GUI")
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
				ImGui.TextColored(ImVec4(0, 1, 0, 1), "Idle")
			else
				
				if doPingPong then
					ImGui.TextColored(ImVec4(0, 1, 0, 1), "Ping Pong")
				elseif doLoop then
					ImGui.TextColored(ImVec4(0, 1, 0, 1), "Loop")
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
				ImGui.TextColored(ImVec4(0.9, 0.4, 0.4, 1), status)
			elseif status:find("Arrived") then
				ImGui.Text("Status: ")
				ImGui.SameLine()
				ImGui.TextColored(ImVec4(0, 1, 0, 1), status)
			end
		end
		ImGui.PopStyleColor()
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
		elseif key == 'help' then
			displayHelp()
		elseif key == 'debug' then
			DEBUG = not DEBUG
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
	if args[1] == 'debug' then
		DEBUG = not DEBUG
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
	-- Create the coroutine for NavigatePath
	
	-- Main Loop
	while RUNNING do
		currZone = mq.TLO.Zone.ShortName()
		if mq.TLO.Me.Zoning() == true then
			printf("\ay[\at%s\ax] \agZoning, \ayPausing Navigation...", script)
			ZoningPause()
		end
		if currZone ~= lastZone then
			selectedPath = 'None'
			doNav = false
			lastZone = currZone
			currentStepIndex = 1
			pauseTime = 0
			status = 'Idle'
			pauseStart = 0
			printf("\ay[\at%s\ax] \agZone Changed Last: \at%s Current: \ay%s", script, lastZone, currZone)
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

			if previousDoNav ~= doNav then
				-- Reset the coroutine since doNav changed from false to true
				co = coroutine.create(NavigatePath)
			end

			local curTime = os.time()
				
			-- If the coroutine is not dead, resume it
			if coroutine.status(co) ~= "dead" then
				-- Check if we need to pause
				if pauseStart > 0 then
					if curTime - pauseStart >= pauseTime then
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
		else
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

		mq.delay(1)
	end
end

-- Make sure we are in game before running the script
if mq.TLO.EverQuest.GameState() ~= "INGAME" then printf("\aw[\at%s\ax] \arNot in game, \ayTry again later...", script) mq.exit() end
Init()
Loop()