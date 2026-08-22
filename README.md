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

Stop any copy of the CLI experiment before testing the app so that only one JFC
event tap is running.

## Permissions

JFC requires **Accessibility**. The tested default event tap works while Input
Monitoring is not granted, so the app neither requests nor instructs the user
to grant Input Monitoring.

The packaged `JFC.app` has its own macOS privacy identity. A permission granted
to Terminal or `.build/debug/jfc` does not grant permission to the app bundle.

The local test bundle is not yet Developer ID signed or notarized. Those steps
belong to the distribution milestone.

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
