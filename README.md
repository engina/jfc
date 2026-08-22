# jfc — just fucking click

JFC is a small native macOS utility for system-wide first-click behavior. It
listens only for left mouse down/up. When a mouse-down lands in an inactive
application's content window, it focuses that exact window and app, then
returns the **original `CGEvent`** to the event system.

It does not synthesize or repost a mouse event. The same-event path has passed
the physical Chrome/YouTube acceptance test with no settle delay.

## Build and launch the app

```sh
Scripts/build-app.sh
open .build/JFC.app
```

This produces a locally ad-hoc-signed application bundle. While its window is
open, JFC behaves like a normal app in the Dock and Cmd-Tab. Closing the window
returns it to invisible background operation; it never occupies the menu bar.
Its first launch presents a small Accessibility onboarding window. After
permission is granted, the same window provides:

- Running/stopped state
- Start and Stop controls
- Accessibility status
- Start at Login, using `SMAppService`
- Quit

Closing the window leaves JFC running. Open `JFC.app` again from Finder,
Spotlight, or another launcher to bring the window and its temporary Dock
presence back.

The small GitHub mark in the control window links to
<https://github.com/engina/jfc>. The bundled black and white marks come from
GitHub's official brand assets and are used only as a secondary social link.

Start at Login uses macOS Service Management and a tiny helper embedded inside
the app. The helper launches JFC without a window or Dock presence, then exits.
Opening JFC later restores the existing background process's control window.

Stop any copy of the CLI experiment before testing the app so that only one JFC
event tap is running.

## Permissions

JFC requires **Accessibility**. The tested default event tap works while Input
Monitoring is not granted, so the app neither requests nor instructs the user
to grant Input Monitoring.

The packaged `JFC.app` has its own macOS privacy identity. A permission granted
to Terminal or `.build/debug/jfc` does not grant permission to the app bundle.

Local builds are ad-hoc signed. Release builds use Developer ID signing and
Apple notarization as described below.

## Build a distributable DMG

Direct distribution requires a valid **Developer ID Application** certificate
with its private key in the login Keychain. A Developer ID Installer certificate
is not needed because JFC ships in a disk image rather than an installer package.

Store notarization credentials once in the Keychain. `notarytool` prompts
securely for the app-specific password when it is omitted:

```sh
xcrun notarytool store-credentials "JFC-notary" \
  --apple-id "you@example.com" \
  --team-id "YOURTEAMID"
```

Then build the release using the full identity name printed by
`security find-identity -v -p codesigning`:

```sh
JFC_CODE_SIGN_IDENTITY="Developer ID Application: Your Name (YOURTEAMID)" \
  Scripts/release.sh
```

The release script builds universal Apple silicon and Intel binaries, enables
Hardened Runtime, adds secure timestamps, signs the embedded login helper and
main app inside-out, creates and signs `dist/JFC-<version>.dmg`, submits it with
`notarytool`, staples the ticket, verifies it with Gatekeeper, and prints its
SHA-256 checksum. Credentials remain in the Keychain and are never stored in
the repository.

`Scripts/package-dmg.sh` can create an unnotarized local DMG independently. Its
minimal Finder surface contains only `JFC.app` and an Applications shortcut.
If `Resources/DMG/background.png` exists, the same script creates the polished
660×400 Finder layout described in `Resources/DMG/README.md`; otherwise it uses
the plain layout.

## Diagnostics

JFC writes small, structured lifecycle and health messages to macOS Unified
Logging. In Console.app, search for:

```text
subsystem:com.justfuckingclick.JFC
```

JFC logs permission transitions, event-tap health, application lifecycle, and
Start at Login outcomes. The packaged app never logs individual clicks, cursor
positions, target applications, window titles, or controls. Detailed click
traces remain exclusive to the CLI experiment.

## CLI experiment

```sh
swift build
.build/debug/jfc
```

The first run requests Accessibility. If the terminal prompt is not enough,
add the stable `.build/debug/jfc` executable in:

- System Settings > Privacy & Security > Accessibility

Restart `jfc` after changing the permission. For a resolver-only smoke test:

```sh
.build/debug/jfc --observe --verbose
```

## Key experiment

1. Put VS Code on the left and Chrome with YouTube on the right.
2. Make VS Code active.
3. Put the pointer directly over YouTube's Play/Pause control.
4. Click exactly once.

A successful log looks like:

```text
CLICK #1 (clickState=1)
cursor: 1432.0,812.0
target app: Google Chrome [pid ...]
target window: YouTube - ...
currently active app: Visual Studio Code
activating Google Chrome via both...
  AX main=success
  AX raise=success
  AX frontmost=success
  AX focused=success
  AppKit activate=accepted
forwarding SAME CGEvent (...)
```

If Chrome activates but YouTube does not receive the click, compare these one at
a time:

```sh
.build/debug/jfc --activation ax
.build/debug/jfc --activation appkit
.build/debug/jfc --activation both --settle-ms 10
.build/debug/jfc --activation both --settle-ms 20
```

`--settle-ms` holds the original event inside the tap callback; it still does
not generate a replacement click. Keep the smallest value that works reliably.
See all options with `.build/debug/jfc --help`.

## Current safety boundary

- Only `leftMouseDown` and `leftMouseUp` are tapped.
- Already-active target apps pass through untouched.
- Mouse-up always passes through untouched.
- Click count, timestamp, flags, pressure, and device metadata are preserved
  because the same event object is returned.
- Window backgrounds, resize areas, traffic-light controls, the menu bar, Dock,
  desktop, non-activatable processes, and jfc itself are bypassed.
- Dragged events, movement, scrolling, right-click, and keyboard events are not
  observed.

The CLI remains available so the event path can be tested independently of the
application lifecycle and packaging.
