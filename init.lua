--[[
	Title: Generic Script Template
	Author: Grimmier
	Includes: 
	Description: Generic Script Template with ThemeZ Suppport
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
local theme, defaults, settings = {}, {}, {}
local Paths = {}
local selectedPath = 'None'
local newPath = ''
local curTime = os.time()
local lastTime = curTime
local aRecord, doNav, doLoop, doReverse, doPingPong = false, false, false, false, false
local rDelay, stopDist = 5, 30
local currentStep = 1
local delWP, delWPStep = false, 0

-- GUI Settings
local winFlags = bit32.bor(ImGuiWindowFlags.None, ImGuiWindowFlags.MenuBar)
local RUNNING = true
local showMainGUI, showConfigGUI = true, false
local scale = 1
local aSize, locked, hasThemeZ = false, false, false

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
	StopDistance = 30,
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
		settings[script].RecordDelay = rDelay
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

	if settings[script].StopDistance == nil then
		settings[script].StopDistance = stopDist
		newSetting = true
	end

	-- Load the theme
	loadTheme()

	-- Set the settings to the variables
	stopDist = settings[script].StopDistance
	aSize = settings[script].AutoSize
	locked = settings[script].locked
	scale = settings[script].Scale
	themeName = settings[script].LoadTheme
	rDelay = settings[script].RecordDelay

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

	table.insert(tmp, {step = #tmp + 1, loc = loc})
	Paths[zone][name] = tmp
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
	SavePaths()
end

local function DeletePath(name)
	local zone = mq.TLO.Zone.ShortName()
	if not Paths[zone] then return end
	if not Paths[zone][name] then return end
	Paths[zone][name] = nil
	SavePaths()
end

local function CreatePath(name)
	local zone = mq.TLO.Zone.ShortName()
	if not Paths[zone] then Paths[zone] = {} end
	if not Paths[zone][name] then Paths[zone][name] = {} end
	SavePaths()
end

local function AutoRecordPath(name)
	curTime = os.time()
	if curTime - lastTime > rDelay then
		RecordWaypoint(name)
		lastTime = curTime
	end
	SavePaths()
end

local function ScanXtar()
	if mq.TLO.Me.XTarget() > 0 then
		for i = 1, mq.TLO.Me.XTargetSlots() do
			local xTarg = mq.TLO.Me.XTarget(i)
			if not (xTarg.ID() > 0 and xTarg.Type() ~= 'Corpse' and xTarg.Type() ~= 'Chest') then
				local xCount = mq.TLO.Me.XTarget() or 0
				local xName, xType = xTarg.Name(), xTarg.Type()
				if (xCount > 0) then
					if ((xTarg.Name() ~= 'NULL' and xTarg.ID() ~= 0) and (xType ~= 'Corpse') and (xType ~= 'Chest') and (xTarg.Master.Type() ~= 'PC')) then
						return true
					end
				end
			end
		end
	end
	return false
end

--------- Navigation Functions --------

local function FindClosestWaypoint(path, table)
	local zone = mq.TLO.Zone.ShortName()
	local tmp = table
	local closest = 999999
	local closestLoc = 1
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

local function NavigatePath(name)
	if not doNav then
		return
	end

	local zone = mq.TLO.Zone.ShortName()
	if not Paths[zone] then return end
	if not Paths[zone][name] then return end
	local tmp = Paths[zone][name]
		table.sort(tmp, function(a, b) return a.step < b.step end)
	if doReverse then
		table.sort(tmp, function(a, b) return a.step > b.step end)
	end
	local startNum = 1
	if currentStep ~= 1 then
		startNum = currentStep
	end
	while doNav do
		for i = startNum , #tmp do
			currentStep = i
			if not doNav then
				return
			end
			local tmpLoc = string.format("%s:%s", tmp[i].loc, mq.TLO.Me.LocYXZ())
			tmpLoc = tmpLoc:gsub(",", " ")
			mq.cmdf("/squelch /nav locyxz %s | distance %s",tmpLoc, stopDist)
			mq.delay(10)
			-- printf("Navigating to WP #: %s", tmp[i].step)
			while mq.TLO.Math.Distance(tmpLoc)() > 30 and doNav do
				if not doNav then
					return
				end
				if mq.TLO.Me.Combat() or ScanXtar() then
					printf("\ay[\at%s\ax] \arIn Combat or Xtar Detected, Waiting...", script)
					printf("Combat: %s xTarg: %s", mq.TLO.Me.Combat(), ScanXtar())
					while mq.TLO.Me.Combat() or ScanXtar() do
						mq.delay(1000)
					end
					mq.cmdf("/squelch /nav locyxz %s | distance %s",tmpLoc, stopDist)
				end
				tmpLoc = string.format("%s:%s", tmp[i].loc, mq.TLO.Me.LocYXZ())
				tmpLoc = tmpLoc:gsub(",", " ")
				mq.delay(5)
			end
		end
		break
	end
	currentStep = 1
	if not doLoop then
		doNav = false
	else
		if doPingPong then
			doReverse = not doReverse
		end
		NavigatePath(name)
	end
end

-------- GUI Functions --------

local function Draw_GUI()

	-- Main Window
	if showMainGUI then
		local zone = mq.TLO.Zone.ShortName()
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

				ImGui.EndMenuBar()
			end

			-- Main Window Content	

			ImGui.Text("Current Zone: %s", zone)
			if ImGui.CollapsingHeader("Paths##") then
				
				ImGui.SetNextItemWidth(150)
				if ImGui.BeginCombo("##SelectPath", selectedPath) then
					if not Paths[zone] then Paths[zone] = {} end
					for name, data in pairs(Paths[zone]) do
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
					local label = aRecord and 'Stop Recording' or 'Start Recording'
					if ImGui.Button(label) then
						aRecord = not aRecord
					end
				end

				-- Navigation Controls
				local tmpTable = Paths[zone][selectedPath]
				local closestWaypoint = FindClosestWaypoint(selectedPath, tmpTable)

				if ImGui.CollapsingHeader("Navigation##") then
					doReverse = ImGui.Checkbox('Reverse Order', doReverse)
					ImGui.SameLine()
					doLoop = ImGui.Checkbox('Loop Path', doLoop)
					ImGui.SameLine()
					doPingPong = ImGui.Checkbox('Ping Pong', doPingPong)
					ImGui.Separator()
					if not Paths[zone] then Paths[zone] = {} end
					-- if not Paths[zone][selectedPath] then Paths[zone][selectedPath] = {} end

					ImGui.Text("Current Waypoint: %s", currentStep)
					ImGui.SameLine()
					ImGui.Text("Closest Waypoint: %s", closestWaypoint)

					local tmpLabel = doNav and 'Stop Navigation' or 'Start Navigation'
					if ImGui.Button(tmpLabel) then
						doNav = not doNav
						if not doNav then
							mq.cmdf("/squelch /nav stop")
						end
					end
					ImGui.SameLine()
					if ImGui.Button("Start at Closest") then
						currentStep = closestWaypoint
						doNav = true
					end
				end
				if ImGui.BeginTable('PathTable', 3, bit32.bor(ImGuiTableFlags.Borders, ImGuiTableFlags.RowBg, ImGuiTableFlags.ScrollY, ImGuiTableFlags.Resizable, ImGuiTableFlags.Reorderable, ImGuiTableFlags.Hideable), ImVec2(ImGui.GetContentRegionAvail() - 5, 0.0)) then
					ImGui.TableSetupColumn('#', ImGuiTableColumnFlags.None, 30)
					ImGui.TableSetupColumn('Loc', ImGuiTableColumnFlags.None, 106)
					ImGui.TableSetupColumn('Actions', ImGuiTableColumnFlags.None, 60)
					ImGui.TableSetupScrollFreeze(0, 1)
					ImGui.TableHeadersRow()
					
					for i = 1, #tmpTable do

						ImGui.TableNextRow()
						ImGui.TableSetColumnIndex(0)
						ImGui.Text("%s",tmpTable[i].step)
						if i == closestWaypoint then
							ImGui.SameLine()
							
							ImGui.TextColored(ImVec4(1,1,0,1),Icon.MD_STAR)
						end
						ImGui.TableSetColumnIndex(1)
						ImGui.Text(tmpTable[i].loc)
						ImGui.TableSetColumnIndex(2)
						
						if ImGui.Button(Icon.FA_TRASH.."##_"..i) then
							delWP = true
							delWPStep = tmpTable[i].step
						end
						
					end
					ImGui.EndTable()
				end
			
			end
			-- Reset Font Scale
			ImGui.SetWindowFontScale(1)

		end

		-- Unload Theme
		LoadTheme.EndTheme(ColorCount, StyleCount)
		ImGui.End()
	end

	-- Config Window
	if showConfigGUI then
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

				-- Set RecordDley
				rDelay = ImGui.SliderInt("Record Delay##"..script, rDelay, 1, 10)
				stopDist = ImGui.SliderInt("Stop Distance##"..script, stopDist, 10, 100)
				-- Save & Close Button --
				if ImGui.Button("Save & Close") then
					settings = dofile(configFile)
					settings[script].Scale = scale
					settings[script].LoadTheme = themeName
					settings[script].locked = locked
					settings[script].AutoSize = aSize
					settings[script].RecordDelay = rDelay
					settings[script].StopDistance = stopDist
					mq.pickle(configFile, settings)
					showConfigGUI = false
				end
			end
			LoadTheme.EndTheme(ColCntConf, StyCntConf)
			ImGui.End()
	end

end

-------- Main Functions --------
local function Init()
	-- Load Settings
	loadSettings()
	loadPaths()
	-- Get Character Name
	meName = mq.TLO.Me.Name()
	-- Check if ThemeZ exists
	if File_Exists(themezDir) then
		hasThemeZ = true
	end
	-- Initialize ImGui
	mq.imgui.init('MyPaths', Draw_GUI)
end

local function Loop()
	-- Main Loop
	while RUNNING do
		while mq.TLO.Me.Zoning() do
			selectedPath = 'None'
			doNav = false
			mq.delay(1000)
		end
		if aRecord then
			AutoRecordPath(selectedPath)
		end
		-- Make sure we are still in game or exit the script.
		if mq.TLO.EverQuest.GameState() ~= "INGAME" then printf("\aw[\at%s\ax] \arNot in game, \ayTry again later...", script) mq.exit() end

		if doNav then
			NavigatePath(selectedPath)
		else
			currentStep = 1
		end

		if delWP then
			RemoveWaypoint(selectedPath, delWPStep)
			delWPStep = 0
			delWP = false
		end
		-- Process ImGui Window Flag Changes
		winFlags = locked and bit32.bor(ImGuiWindowFlags.NoMove, ImGuiWindowFlags.MenuBar) or bit32.bor(ImGuiWindowFlags.None, ImGuiWindowFlags.MenuBar)
		winFlags = aSize and bit32.bor(winFlags, ImGuiWindowFlags.AlwaysAutoResize, ImGuiWindowFlags.MenuBar) or winFlags

		mq.delay(10)

	end
end
-- Make sure we are in game before running the script
if mq.TLO.EverQuest.GameState() ~= "INGAME" then printf("\aw[\at%s\ax] \arNot in game, \ayTry again later...", script) mq.exit() end
Init()
Loop()