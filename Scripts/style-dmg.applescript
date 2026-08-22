on run arguments
  set volumeName to item 1 of arguments
  set backgroundName to item 2 of arguments

  tell application "Finder"
    set dmgDisk to disk (volumeName as text)
    tell dmgDisk
      open
      delay 1

      set current view of container window to icon view
      set toolbar visible of container window to false
      set statusbar visible of container window to false
      set pathbar visible of container window to false
      set bounds of container window to {200, 200, 860, 600}

      set viewOptions to icon view options of container window
      set arrangement of viewOptions to not arranged
      set icon size of viewOptions to 128
      set text size of viewOptions to 14
      set shows item info of viewOptions to false
      set shows icon preview of viewOptions to true
      set background picture of viewOptions to file (".background:" & backgroundName)

      set position of item "JFC.app" to {170, 205}
      set position of item "Applications" to {490, 205}
      set extension hidden of item "JFC.app" to true

      update without registering applications
      delay 2
      close
    end tell
  end tell
end run
