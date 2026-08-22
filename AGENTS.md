# JFC repository instructions

## Project intent

JFC ("just fucking click") is a tiny native macOS utility that makes one
physical left click both activate an inactive target app/window and operate the
control under the pointer. It must not implement focus-follows-mouse behavior.
Focus changes only in response to an actual left click.

Keep the implementation small, native, and understandable. Prefer Swift,
AppKit, Core Graphics, Accessibility, and Service Management APIs already
provided by macOS. Do not add Electron, a browser extension, a daemon requiring
root, or a large third-party dependency.

## Proven event path

The first physical-click experiment has passed on Chrome/YouTube with the
default configuration and no settle delay:

1. A head-insert `cgSessionEventTap` receives `leftMouseDown`.
2. AX resolves the element/window beneath the event location.
3. The target window is made main, raised, and focused; its app is made
   frontmost. AppKit activation is also requested.
4. The callback returns the same incoming `CGEvent`.
5. Chrome receives that original click and operates the YouTube control.

Treat returning the original physical event as a core invariant. Do not replace
it with a synthesized second click or a cancel/reinject path unless a concrete
regression proves the original-event path cannot work and the change is made
deliberately. Never add speculative reinjection “for reliability.”

Preserve the CLI experiment while the menu-bar app is being developed so the
event path can be isolated from application-lifecycle and packaging issues.

## Input and safety boundaries

- Observe only `leftMouseDown` and `leftMouseUp`.
- Do not observe or alter keyboard input, right click, scrolling, or movement.
- If the target application is already active, pass the event through without
  special handling.
- Pass `leftMouseUp` through unchanged.
- Preserve click count, timestamps, flags, pressure, device metadata,
  click-and-hold, and double-click semantics by returning the incoming event.
- Do not cancel an event unless implementing an explicitly approved reinjection
  experiment that correctly owns the entire down/up sequence.
- Continue bypassing window backgrounds, resize surfaces, traffic-light
  controls, the desktop, Dock, menu bar, non-activatable processes, and JFC.
- Avoid changes that interfere with title-bar dragging or window resizing.
- On AX lookup/focus failures, fail open: return the user's event unchanged.
- Keep event-tap callbacks bounded; recover if macOS disables the tap for a
  timeout or user input.
- Product Unified Logging must remain state-based and privacy-conscious. Never
  log individual clicks, cursor positions, target applications, window titles,
  or controls. Detailed click traces belong only to the explicit CLI experiment.

## Platform behavior

Target current macOS first; the Swift package currently has a macOS 14 minimum.
The proven event tap needs Accessibility but not Input Monitoring. Request only
Accessibility unless a concrete regression on a supported macOS version proves
that Input Monitoring is also necessary. Never request broader permissions such
as Full Disk Access.

Use public macOS APIs. Account for multiple displays and visible Spaces without
private Space-management APIs. Minimized windows are not under the pointer and
are out of scope. Treat sheets, popovers, child windows, protected apps, and AX
providers that return `cannotComplete` or `notImplemented` as explicit edge
cases with safe pass-through behavior.

For changing or uncertain macOS API behavior, consult current Apple developer
documentation and installed SDK headers. Prefer primary Apple sources over
third-party summaries.

## Build and verification

Before handing off code changes, run checks proportional to the change. The
normal baseline is:

```sh
xcrun swift-format lint --recursive Sources Package.swift
swift build
swift build -c release
```

If SwiftPM cannot use host cache paths in a sandbox, redirect module/cache paths
inside `.build` and use SwiftPM's `--disable-sandbox` only for that nested-build
limitation.

Event/focus changes require the physical regression test:

1. VS Code active on the left; Chrome/YouTube visible and inactive on the right.
2. Click YouTube Play/Pause once and confirm it operates immediately.
3. Alternate VS Code → YouTube → VS Code → YouTube for at least 20 clicks.
4. Confirm no lost clicks, double clicks, immediate play/pause reversal, drag
   regression, or noticeable delay.

Automated or synthetic mouse events do not substitute for this physical test.
Do not claim it passed unless a person actually performed it.

## Repository hygiene

- Do not commit build products, `.build`, `.swiftpm`, or `.DS_Store`.
- Preserve unrelated user changes and inspect the worktree before editing.
- Keep commits focused. Do not create, amend, or push commits unless the user
  explicitly asks.
- Update `README.md` and `RESEARCH.md` when behavior, permissions, packaging, or
  experimental conclusions materially change.
