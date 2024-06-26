# MyPaths

By Grimmier

## Description

MyPaths was inspired by the farm mode in RGMercs Lua.

I love the idea of setting loops or circuits to run around to and hunt.  I wanted a way to save the loops so I could change them without having to re-recode a new one.

Thus MyPaths was born. MyPaths allows you to record /save and load Custom Waypoint paths in a zone. 

## HUD

* You can Toggle a HUD from the menu bar to display your status.
* You can set the transparency from inside the config window.
* Double Clicking on the HUD will toggle the main window.

## Paths

Paths are the series of waypoints you want to string to gether. You can create, edit, and delete custom paths per zone. 

* Load saved paths from the drop down list for that zone.
* You can record them one point at a time with the add waypoint button.
* You can use the Start Recording button to have the points Auto Record for you at a customizable interval. Checks are made so we can't duplicate a waypoint when creating the Path.
* Auto Recording Paths has an extra threshold as well, you can delare a minimum distance from the last WP recorded. Set in the settings window
* Copy a path to save it as a new name with all of the same waypoints and settings. 
  * This can be useful for renaming paths. 
  * Also if you have multiple paths that use the same start point/starting path before branching out.

## Navigating Paths

* You can navigate the path in both forwards and reverse order.
* Start from Nearest waypoint. (Marked with a Star on the GUI Table)
* Right click to start from a specific waypoint from the GUI Table. (will follow Navigation mode set)
* Right Click Nav to a specific waypoint and stop there.
* You can now set custom delays per waypoint. These will override the global delay if set.
* You can also set custom commands to execute at each waypoint.
  * PRO Tip! you can add something like ```/multiline ; /mypaths stop; /timed 5, /mypaths go loop "Loop A"```  at the last waypoint for the command to execute and it will load up the Path "Loop A" next in Loop Mode.
* Doors!!! you can toggle if this way point has a door and we will attempt to open it. 
  * There are toggles for both forward direction and reverse directions.

## Navigation Modes

There are 4 Navigation modes you can choose between with checkboxes. 

* Normal run from A to B following the path.
* Reverse run from B to A following the path.
* Loop mode start over when reaching the end. (follows either Normal or Reverse order)
* Ping Pong run from A to B following the path then flip and go from B to A. rinse and repeat as a loop. (forces loop on)

Loop mode will try and navigate directly from the end point to the start point, if they are set far apart you will follow whatever route nav decides to take. Recommend if you know the path is supposed to be a loop, that you set the start and end points closer together.

## Auto Pause and Resume

Auto Pause and Resume navigating upon Interruptions: 

* sitting, combat, xtarget, looting, stopped moving (stuck), status effects (Rooted, Mezzed, Charmed, Feared)
* You can customize a delay for how long to wait after the above interruptions, incase you need time to loot or sit and med.
* GM Detection (togglable), shuts down Navigation if a GM is detected.
* Group Watch Toggle (default off)
  * Group Watch Settings Select from (All, Healer, Self, None)
  * Set thresholds for HP and Mana percentages. 

If we detect any of the above we will pause navigation until the issue is resolved, then resume. This allows us to pair MyPaths with automation like KA and RGMercs. For Aggressive zones you can just face pull as you run around. For non-Aggressive areas you will want to use a delay at the WP to give the automation time to pull those spawns.

Stopped Moving interruptions will attempt to restart if you start moving again or after a few seconds. This check happens after checking for sitting and rooted.

## Sharing

* You can Export your selected Path and the import code will be copied to clipboard.
  * Exporting is found in the menubar
* You can Import shared Paths by pasting the code into the field and clicking Import. 

## Debug Mode

You can enable Debug mode with 

```/mypaths debug ``` Toggle debug mode on or off

```/lua run mypaths debug``` Start Script with debug on.

Debug mode will log status updates to a table you can toggle on and off from the GUI using the BUG icon in the menu bar. (Icon only shows in debug mode)

The table is set with a 100 row buffer limit.

## Config Options

* Theme Change.
* Text Scaling slider.
* Set delay between recording points for Auto Recording.
* Set the minimum distance from last recorded WP before recording another. (Recording mode only!)
* Set delay to pause at the waypoints 0 for no delay keep running.
* Set desired distance from waypoint count as arriving.
* Adjust the transparency of the HUD
* GM Detection (togglable), shuts down Navigation if a GM is detected.
* Set desired delay to enact after an interrupt is over.
 * This is so your automation has time to sit you down after fighting basically. 
 * Otherwise you may get stuck trying to sit while running, which won't trigger is sitting.

## Startup Ooptions

* ```/lua run mypaths``` Start the script normally.
* ```/lua run mypaths debug``` Start the script with Debug enabled.
* ```/lua run mypaths hud``` Start the script with the HUD display on.
* ```/lua run mypaths debug hud``` Start the script with Debug enabled and the HUD display on

## Commands 

```
Command Line Commands:

	/mypaths [go|stop|list|show|quit|debug|hud|help] [loop|rloop|start|reverse|pingpong|closest|rclosest] [path]
  /mypaths [combat|xtarg] [on|off] Toggles combat and xtarget interrupts on or off respectivly.
  /mypaths [resume] [back|next] Resumes paused path, optional back and next arguments if blank we resume on same step where we left off.

Command: go = REQUIRES arguments and Path name see below for Arguments.
Command: stop = Stops the current Navigation.
Command: show = Toggles Main GUI.
Command: debug = Enable Debug logging of status updates to a table.
Command: list = Lists all Paths in the current Zone.
Command: quit or exit = Exits the script.
Command: hud = Toggles the HUD Display
Command: pause = Pauses Current Path
Command: resume = Resumes Current Path Accepts [back|next] arguments to resume back a step or forward a step.
Command: help = Prints out this help list.

Arguments: loop = Loops the path, rloop = Loop in reverse.
Arguments: closest = start at closest wp, rclosest = start at closest wp and go in reverse.
Arguments: start = starts the path normally, reverse = run the path backwards.
Arguments: pingpong = start in ping pong mode. (TOGGLES LOOP ON AS WELL)

Usage:
Example: /mypaths go loop "Loop A"
Example: /mypaths stop

```

## Media

https://vimeo.com/952971990?share=copy

https://vimeo.com/953059474?share=copy

https://vimeo.com/manage/videos/955375540

https://github.com/grimmier378/MyPaths/assets/124466615/31f1fc97-75ba-46cf-87d2-c880a9b260d0

https://www.youtube.com/watch?v=aWhSqgmPP6s

https://www.youtube.com/watch?v=0Pkyd54W8yA&t=2s

https://www.youtube.com/watch?v=HlgoaLkNPNo&t=6s