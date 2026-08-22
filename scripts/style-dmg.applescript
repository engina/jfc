on run arguments
  set mountPath to item 1 of arguments
  set backgroundName to item 2 of arguments
  set volumeFolder to POSIX file mountPath as alias
  set backgroundFile to POSIX file (mountPath & "/.background/" & backgroundName) as alias

  tell application "Finder"
    open volumeFolder
    delay 1

    set dmgWindow to container window of volumeFolder
    set current view of dmgWindow to icon view
    set toolbar visible of dmgWindow to false
    set statusbar visible of dmgWindow to false
    set pathbar visible of dmgWindow to false
    set bounds of dmgWindow to {200, 200, 860, 600}

    set viewOptions to icon view options of dmgWindow
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 128
    set text size of viewOptions to 14
    set shows item info of viewOptions to false
    set shows icon preview of viewOptions to true
    set background picture of viewOptions to backgroundFile

    set position of item "JFC.app" of volumeFolder to {151, 199}
    set position of item "Applications" of volumeFolder to {509, 199}
    set extension hidden of item "JFC.app" of volumeFolder to true

    update volumeFolder without registering applications
    delay 2
    close dmgWindow
  end tell
end run
