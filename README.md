<p align="center">
  <img src="Docs/jfc-app-icon.png" width="128" height="128" alt="JFC app icon">
</p>

<h1 align="center">jfc</h1>

JFC is a tiny native macOS utility that lets one physical click activate an
inactive app window and operate the control beneath the pointer.

[Download the latest release](https://github.com/engina/jfc/releases/latest) · macOS 14+

<p align="center">
  <img src="Docs/inactive-click.gif" width="800" alt="Without JFC, the first click only activates the video window. With JFC, it also pauses the video.">
</p>

## How it works

On a left mouse-down over inactive app content, JFC:

1. Resolves the target window with macOS Accessibility.
2. Focuses the window and activates its application.
3. Returns the original physical `CGEvent` unchanged.

There is no synthesized click, event reposting, or focus-follows-mouse. Clicks
in the active app pass through normally, and failures fail open. JFC observes
no keyboard input and requires Accessibility permission only.

## Build

```sh
scripts/build-app.sh
open .build/JFC.app
```

Closing the window leaves JFC running. Reopen the app to show its controls;
press `Cmd-Q` to quit.
