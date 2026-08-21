# jfc — just fucking click

`jfc` is a deliberately small command-line experiment for system-wide macOS
first-click behavior. It listens only for left mouse down/up. When a mouse-down
lands in an inactive application's content window, it tries to focus that exact
window and app, then returns the **original `CGEvent`** to the event system.

This milestone does not synthesize or repost a mouse event. It is designed to
answer the event-ordering question before building a menu-bar app.

## Build and run

```sh
swift build
.build/debug/jfc
```

The first run requests Accessibility and Input Monitoring access. If the
terminal prompt is not enough, add the stable `.build/debug/jfc` executable in:

- System Settings > Privacy & Security > Accessibility
- System Settings > Privacy & Security > Input Monitoring

Restart `jfc` after changing either permission. For a resolver-only smoke test:

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

This is not yet a polished utility. In particular, the pass/fail result must be
collected on a real desktop session before adding a reinjection fallback or a
menu-bar wrapper.
