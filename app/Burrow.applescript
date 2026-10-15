-- Burrow.app: a menu for your Windows programs and Windows Steam.
-- `burrow app` compiles this on the Mac with osacompile and fills in the CLI path below.
-- Long jobs (setup, turbo, installers) open in Terminal so you can see their progress.

property cli : "__BURROW_CLI__"

on burrow(args)
	return do shell script quoted form of cli & " " & args
end burrow

-- Runs a command in the background; the menu doesn't wait for the program to close.
on burrowBackground(args)
	do shell script quoted form of cli & " " & args & " > /dev/null 2>&1 &"
end burrowBackground

on inTerminal(args)
	tell application "Terminal"
		activate
		do script quoted form of cli & " " & args
	end tell
end inTerminal

on splitTab(t)
	set saved to AppleScript's text item delimiters
	set AppleScript's text item delimiters to tab
	set parts to text items of t
	set AppleScript's text item delimiters to saved
	return parts
end splitTab

on run
	set status to burrow("status")
	set isSetUp to status contains "setup=1"
	set hasTurbo to status contains "turbo=1"
	set hasSteam to status contains "steam=1"

	if not isSetUp then
		display dialog "Burrow needs to download Wine and its graphics layer once (about 300 MB). A Terminal window will show the progress." buttons {"Not now", "Set up"} default button "Set up" with title "Burrow"
		if button returned of result is "Set up" then inTerminal("setup && " & quoted form of cli & " turbo")
		return
	end if

	set appIds to {}
	set appNames to {}
	repeat with line_ in paragraphs of burrow("apps --plain")
		if (length of line_) > 0 then
			set parts to splitTab(line_ as text)
			set end of appIds to item 1 of parts
			set end of appNames to "▶  " & (item 2 of parts)
		end if
	end repeat

	set steamItem to "Open Windows Steam"
	if not hasSteam then set steamItem to "Install Windows Steam"
	set actions to {steamItem, "Add my Steam games to this list", "Install a Windows program…", "Make a Dock shortcut…", "Quit all Windows programs", "Check everything", "Open Burrow's folder"}
	if not hasTurbo then set actions to {"Build turbo graphics (needed for 3D games)"} & actions

	set choices to appNames & {"——————————"} & actions
	set picked to choose from list choices with title "Burrow" with prompt "Pick a program or an action:" OK button name "Go" cancel button name "Close"
	if picked is false then return
	set picked to item 1 of picked

	repeat with i from 1 to count of appNames
		if item i of appNames is picked then
			burrowBackground("launch " & quoted form of (item i of appIds))
			return
		end if
	end repeat

	if picked is "Open Windows Steam" then
		burrowBackground("steam")
	else if picked is "Install Windows Steam" then
		inTerminal("steam")
	else if picked starts with "Build turbo" then
		inTerminal("turbo")
	else if picked is "Add my Steam games to this list" then
		display dialog burrow("steam sync") buttons {"OK"} default button "OK" with title "Burrow"
	else if picked is "Install a Windows program…" then
		set f to choose file with prompt "Pick a Windows installer (.exe or .msi):"
		inTerminal("install " & quoted form of POSIX path of f)
	else if picked is "Make a Dock shortcut…" then
		if (count of appNames) is 0 then
			display dialog "Your list is empty. Install a program or add your Steam games first." buttons {"OK"} default button "OK" with title "Burrow"
			return
		end if
		set which to choose from list appNames with title "Burrow" with prompt "Make a Mac app for:"
		if which is false then return
		repeat with i from 1 to count of appNames
			if item i of appNames is (item 1 of which) then
				display dialog burrow("shortcut " & quoted form of (item i of appIds)) buttons {"OK"} default button "OK" with title "Burrow"
				tell application "Finder" to open (POSIX file ((POSIX path of (path to home folder)) & "Applications/Burrow") as alias)
			end if
		end repeat
	else if picked is "Quit all Windows programs" then
		burrow("kill")
	else if picked is "Check everything" then
		inTerminal("doctor")
	else if picked is "Open Burrow's folder" then
		do shell script "open " & quoted form of ((POSIX path of (path to home folder)) & "Library/Application Support/Burrow")
	end if
end run
