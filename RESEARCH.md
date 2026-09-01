# macOS event/focus notes

The original decisive Chrome/YouTube acceptance test passed with combined AX
and AppKit activation and a zero-millisecond settle delay. Repeated use also
continued successfully across many sleep/wake cycles. A later isolation test
found that AppKit activation alone did not operate the target control in either
the working or failing multi-display arrangement. A hybrid path that selects
the target window through AX, activates the app through AppKit without
`activateAllWindows`, and then focuses the target window through AX passed the
previously failing multi-display arrangement.

## Why return the original event first

Apple documents a filtering `CGEventTap` callback as able to return the incoming
event, a newly created event, or `nil` to delete it. A session event tap runs
before the annotated-session stage, where events have been annotated for a
specific application. `jfc` therefore uses a head-insert session tap, performs
focus work synchronously on mouse-down, and returns the incoming object.

On the tested macOS system, the synchronous AX/AppKit focus work completes soon
enough for downstream dispatch to send the returned event to the newly active
application. The CLI retains `--settle-ms` as an experiment, but the product
uses zero delay. It is intentionally capped at 100 ms because slow event-tap
callbacks can be disabled by timeout.

## Permission result

The filtering event tap and AX focus path work with Accessibility granted while
Input Monitoring reports `NOT GRANTED`. The application therefore requests
Accessibility only. Asking for Input Monitoring would add an unnecessary
privacy permission to the onboarding flow.

The app bundle is a separate TCC identity from Terminal and the CLI executable,
so `JFC.app` must receive its own Accessibility grant.

## Window resolution and focus

`AXUIElementCopyElementAtPosition` uses top-left-relative screen coordinates and
performs hit-testing by z-order. From the hit element, `kAXWindowAttribute`
provides the containing window and `AXUIElementGetPid` provides the owner.

The inactive-app focus path sets the target window's `kAXMainAttribute`,
performs `kAXRaiseAction`, activates the application with
`NSRunningApplication.activate(options: [])`, and then sets the target window's
`kAXFocusedAttribute`. Omitting `activateAllWindows` keeps other visible windows
of the target application from being raised. AppKit activation alone did not
operate the target control; selecting the target window through AX first is
required by the tested path.

AX calls are synchronous messages, but a successful return does not constitute
proof that downstream event dispatch observes the new focus state. That is what
the physical-click test measures.

Application focus and window focus are separate. When the target application is
already frontmost, JFC compares the window beneath the pointer with the
application's `kAXFocusedWindowAttribute`. A click in the focused window passes
through without intervention. A click in another window uses only the AX
main/raise/focus operations; it does not reactivate the already-frontmost
application. If the focused-window lookup fails, JFC passes the click through
unchanged.

### Multi-window activation bug

The failing setup used three displays: D1 was the MacBook display, D2 the
primary external display, and D3 the secondary external display. With VS Code
active on D2, C1 (a Brave window) behind it on D2, and C2 (the Brave YouTube
window) on D3, clicking C2 did not operate the video. The old AX path selected
C2 but also raised C1 above VS Code. With JFC stopped, macOS raised and
activated only C2; VS Code remained above C1.

The old path's result depended on the location of the other visible Brave
window:

| Active window | C1 display | C2 display | First click operated C2 |
| --- | --- | --- | --- |
| VS Code on D2 | D2 | D3 | No |
| VS Code on D2 | D2 | D2 | Yes |
| VS Code on D2 | D1 | D3 | Yes |
| VS Code on D2 | D1 | D1 | Yes |
| VS Code on D2 | D2 | D1 | No |
| VS Code on D2 | D3 | D1 | Yes |

Verbose traces for a failing D2/D2/D3 click and a working D2/D1/D3 click were
otherwise equivalent: both resolved the same target PID, C2 window, and AX
element, and all four AX operations reported success. Disabling the
application-wide `kAXFrontmostAttribute` stopped C1 from being raised, but also
stopped the formerly working D2/D1/D3 case from operating C2. That case worked
again when C1 was minimized. This isolated the regression to app-wide
activation interacting with another visible window, rather than AX hit-testing
the wrong target.

AppKit activation alone was insufficient. The working replacement first makes
C2 main and raises it through AX, calls
`NSRunningApplication.activate(options: [])` without `activateAllWindows`, then
focuses C2 through AX. The previously failing D2/D2/D3 arrangement then
operated C2 on the first click without raising C1.

## Edge cases

- Multiple displays: Core Graphics event locations and AX hit-testing use the
  global display coordinate space, so no AppKit coordinate flip is performed.
- Spaces: a window physically under the pointer is already on the visible Space.
  There is no supported public API here for moving arbitrary windows between
  Spaces, and this prototype does not try.
- Minimized windows: they cannot be under the pointer, so they are out of scope.
- Sheets/drawers: Apple's `kAXWindowAttribute` contract returns the containing
  `AXWindow`, not the sheet/drawer itself. Raising that parent should preserve
  modal behavior, but it needs manual coverage.
- Popovers/child windows: AX exposure varies by application. If no containing AX
  window is exposed, the click is passed through without intervention.
- Unsupported/protected apps: AX can report `notImplemented`, `cannotComplete`,
  or missing attributes. The safe behavior is pass-through.
- Secure Event Input: Apple's public contract describes protection of keyboard
  input. JFC observes no keyboard event types. Accessibility permission and
  application-specific AX restrictions are the practical blockers for this
  mouse-only utility.

## App lifecycle

JFC remains an accessory application for its entire lifetime. A deliberate
launch presents the control window, and closing it leaves the event tap running.
Reopening JFC reuses the process and presents the same window through AppKit's
reopen callback. JFC intentionally has no Dock or Cmd-Tab presence because a
regular activation policy breaks first-click delivery while its window is
visible. There is no menu-bar item.

Start at Login uses `SMAppService.loginItem(identifier:)`, available on macOS 13
and later. JFC continues to target macOS 14 and later. Login launches remain
hidden; deliberate activation from Finder, Spotlight, or another launcher
presents the control window.

The helper lives in `Contents/Library/LoginItems`. Registration was verified to
reach the `enabled` state. A direct helper launch simulating login produced one
main JFC process with both an argument and environment launch marker; it settled
as a UI element with no windows. Reopening JFC reused that PID and restored one
control window while retaining accessory policy. The helper exited cleanly in
both registration and simulation tests. An actual logout/login or reboot
remains the final manual acceptance test.

## Reproducing the event-path experiment

Stop the app first so only one event tap is active, then run the preserved CLI:

```sh
swift build
.build/debug/jfc
```

### Control-window activation-policy regression

A physical-host observation linked first-click behavior to the JFC control
window: VS Code → YouTube worked while the window was closed but failed while
it was open, whereas JFC → YouTube worked in both states. The app changed two
variables together: showing the window set JFC's activation policy to
`regular`, while closing it set the policy to `accessory`. The event tap was
not restarted during this transition.

A physical A/B test kept the control window visible and changed only JFC's
activation policy. The VS Code → YouTube first click worked in `accessory` mode
and failed in `regular` mode unless JFC itself was the active application. This
isolated the regression to JFC's regular-app activation state rather than mere
window visibility. JFC now remains an accessory application for its entire
lifetime, including while the control window is visible.

The automated VM reproduced that result with an unchanged scenario. The old
regular-policy build placed and focused every declared window correctly but
left the target fixture counter at `0`. The accessory-only build advanced it to
`1`, and its complete clean macOS 14.6.1 run passed all 12 recipes spanning
placement, visible-window, and multi-action coverage. An earlier run had one
intermittent miss in the separate D2/D1/D1 placement; that recipe subsequently
passed three isolated reruns and the clean matrix rerun without changing its
expectation.

For resolver-only diagnostics, use `.build/debug/jfc --observe --verbose`.

For an intermittent focus or first-click failure, stop the menu-bar app so only
one event tap is active, then run the CLI's opt-in forensic capture:

```sh
.build/debug/jfc --verbose --trace-jsonl /tmp/jfc-focus.jsonl
```

The JSON Lines trace includes both incoming left-down and left-up events (raw
Core Graphics fields, serialized event bytes, AppKit's `NSEvent` view, and
source metadata), the resolved AX target, the decision JFC made, and exact
timings/results for every AX and application-activation call. A lightweight
WindowServer z-order checkpoint follows each activation call so transient
selection of a sibling window remains visible even if a later call repairs the
final state. Further snapshots scheduled for 0, 1, 5, 10, 20, 50, 100, and 250
ms after the callback returns contain the frontmost app, on-screen windows, and
relevant AX application/window/control state; every record includes its actual
start delay in case earlier inspection work delayed the queue. The final
snapshot enumerates all public AX attributes and actions exposed by the target
objects.

This mode uses the same session event tap and still returns the incoming event;
it does not synthesize or repost input and does not require Input Monitoring.
It is intentionally CLI-only. Its output contains private window titles,
control values, bundle and executable paths, cursor positions, and raw event
metadata. Review it before sharing. File serialization and state inspection can
perturb a timing-sensitive failure, so compare the observed behavior with and
without forensic mode and do not treat a traced run as a performance result.

For physical-versus-synthetic input analysis, use the separate diagnostic:

```sh
swift build --product jfc-input-diagnostic
.build/debug/jfc-input-diagnostic --clicks 1 > click.jsonl
```

When LaunchServices must own the process identity—for example, when driving a
VM over SSH—place the executable in an app bundle and launch it with
`--output <path>`. This preserves structured capture output even though the app
has no terminal.

It emits JSON Lines for the matched pointing device and its HID element
catalog, primary-button values, every decoded value sharing the button report's
timestamp, the raw HID report bytes, and the corresponding left down/up at the
HID, session, and annotated-session Core Graphics taps. The Core Graphics
records also include the serialized event, documented mouse and source fields,
and the AppKit `NSEvent` view of the same event.

The diagnostic deliberately observes only left mouse down/up. It requires
Input Monitoring because raw `IOHIDManager` reports are the evidence needed to
distinguish an input framework's click from a physical HID click. This does not
change JFC's Accessibility-only permission model. Captures may contain device
identifiers, raw HID bytes, pointer coordinates, and source process identifiers
and should be treated as private.

Focus VS Code, then click Play/Pause in an inactive Chrome/YouTube window. The
control should operate on that first physical click. Alternate between the two
apps for at least 20 clicks and check for lost or doubled clicks, play/pause
reversals, drag regressions, and noticeable delay. Synthetic input does not
substitute for this test.

The VM automation environment, JSON scenario setup executor, concurrent Mac2
multi-display recording, canonical cross-version scenario matrix, rejected
input paths, and qualified guest virtual-HID transport are recorded in
`E2E_RUNBOOK.md`.

Keep Core Graphics display and cursor calls out of an SSH-launched root
VirtualHID client. On the macOS 14 VM, `CGGetActiveDisplayList` blocked while
initializing the root process's SkyLight connection and wedged WindowServer
until reboot. The automated design positions and verifies the pointer from the
logged-in test-user process, then uses the root-only client solely for the HID
button-down/button-up reports.

The original three-display JSON setup-smoke scenario passes end-to-end with JFC running:
VS Code starts active above `brave.1` on D2, one VirtualHID click targets
`brave.2` on D3, the fixture counter changes from zero to one, `brave.2`
becomes the focused Brave window, and `brave.1` remains behind VS Code. Mac2
records every display around the action; the fixture's Core Graphics window
title supplies the accepted-click count while Core Graphics independently
verifies display placement and global z-order.

Before the cross-display activation fix, the completed seven-placement VM suite
passed six placements and repeatedly failed one: with VS Code active on D2,
`brave.1` on D1, and `brave.2` on D3, the click made `brave.2` frontmost and
AX-focused but left its counter at `0`. The same result persisted after a
deterministic pre-test cleanup dismissed a stale shutdown dialog and verified
that no undeclared layer-zero window was visible.

The same seven positive recipes were then rerun unchanged with JFC stopped.
Every recipe produced the qualified negative-control signature: macOS activated
and focused `brave.2` with the expected window order, but the fixture counter
remained `0` instead of `1`. The six JFC-running passes therefore distinguish
JFC-on from JFC-off behavior. In that pre-fix run, the D2/D1/D3 regression
remained at `0` in both states. Control artifacts and their separate report live
below the ignored `E2E/Artifacts/jfc-off` directory, and the runner restores JFC
on exit.

Input and window-server traces isolated the failure after Core Graphics had
already annotated the original event for `brave.2`. The original activation
sequence raised `brave.2` before requesting application activation, but AppKit's
later activation transaction temporarily selected `brave.1` on the primary
display. Chromium then treated the event arriving at `brave.2` as an activation
click and emitted no DOM mouse sequence. Reasserting `AXMain` and `AXRaise` on
the target window immediately after `NSRunningApplication.activate` prevents
that intermediate window selection. Setting the application's
`AXFocusedWindow` after activation did not fix the regression.

The post-activation reassertion passed ten consecutive VS Code → `brave.2`
transitions in the formerly failing D1/D3 layout and all placement and
multi-action recipes on the macOS 14 VM. It adds no settle delay
and still returns the same incoming `CGEvent`. The corresponding physical
three-display regression remains a required acceptance test before release.

Four JFC-running multi-action recipes also pass. Three consecutive clicks on
the focused C2 fixture advance its counter exactly `1`, `2`, `3`. A C2 → C1 →
C2 sequence advances both Brave counters while verifying the focused window and
global order after every action. A five-action C2 → VS Code → C2 → VS Code → C2
sequence advances C2 `1`, `2`, `3`, restores VS Code focus between target
clicks, and keeps C1 behind VS Code. The same five-action sequence also passes
with C1 on D1 and the target C2 on D3, covering the fixed regression three times
per run. The VS Code target is an AX-derived point in its exposed window body;
all action input still comes from VirtualHID.

## Direct distribution

JFC is distributed outside the Mac App Store as a compressed UDIF disk image.
The app and embedded login helper are signed inside-out with a Developer ID
Application identity, Hardened Runtime, and secure timestamps. No hardened
runtime exception entitlements are currently required. Release binaries are
universal `arm64` and `x86_64` so the macOS 14 deployment target works on both
supported processor families.

The disk image contains only the app and an Applications shortcut. An optional
660×400 background supplies a fixed Finder window layout without adding runtime
dependencies to JFC. Packaging mounts a writable image, addresses its root by
an absolute POSIX alias, and asks Finder to persist the background and icon-view
settings. The writable image has a unique temporary volume name so AppleScript
cannot resolve an unrelated mounted or cached `JFC` volume. After Finder creates
a nonempty root `.DS_Store`, the same filesystem is renamed to `JFC`, detached,
and converted to compressed UDIF. Packaging fails if the metadata is not written.

The image is signed with the same Developer ID Application identity, submitted
through `notarytool` using credentials stored in the Keychain, and stapled after
acceptance. The release script validates the ticket and asks Gatekeeper to assess
the final DMG. A Developer ID Installer certificate is unnecessary because JFC
does not ship an installer package.

The complete path has been exercised on the distributable artifact: Apple's
notary service returned `Accepted`, `stapler validate` succeeded, `hdiutil`
verified the image, and Gatekeeper reported `accepted` with source
`Notarized Developer ID`. See `RELEASING.md` for the reproducible operator
procedure. The DMG must not be changed after stapling; rebuilding or modifying
it requires a new notarization submission.

## Primary references

- Apple, `CGEventTapCreate` and event-tap stages:
  <https://developer.apple.com/documentation/coregraphics/cgevent/tapcreate(tap:place:options:eventsofinterest:callback:userinfo:)>
- Apple, `CGEventTapCallBack` return semantics:
  <https://developer.apple.com/documentation/coregraphics/cgeventtapcallback>
- Apple, AppleScript absolute POSIX file specifiers:
  <https://developer.apple.com/library/archive/documentation/AppleScript/Conceptual/AppleScriptLangGuide/conceptual/ASLR_fundamentals.html#//apple_ref/doc/uid/TP40000983-CH218-SW28>
- Apple, Finder icon-view scripting example:
  <https://developer.apple.com/library/archive/documentation/AppleScript/Conceptual/AppleScriptLangGuide/reference/ASLR_cmds.html>
- Apple, the installed Finder scripting dictionary and `hdiutil(1)` manual.
- Apple, `AXUIElementCopyElementAtPosition` z-order hit-testing:
  <https://developer.apple.com/documentation/applicationservices/1462077-axuielementcopyelementatposition>
- Apple, `NSRunningApplication.activate(options:)`:
  <https://developer.apple.com/documentation/appkit/nsrunningapplication/activate(options:)>
- Apple, `NSApplication.ActivationOptions` window-ordering behavior:
  <https://developer.apple.com/documentation/appkit/nsapplication/activationoptions>
- Apple, `kAXFrontmostAttribute`:
  <https://developer.apple.com/documentation/applicationservices/kaxfrontmostattribute>
- Apple, on-screen window ordering:
  <https://developer.apple.com/documentation/coregraphics/cgwindowlistoption/optiononscreenonly>
- Apple, `LSUIElement` agent applications:
  <https://developer.apple.com/documentation/bundleresources/information-property-list/lsuielement>
- Apple, main-app login registration:
  <https://developer.apple.com/documentation/servicemanagement/smappservice/mainapp>
- Apple, notarizing macOS software before distribution:
  <https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution>
- Apple, customizing the notarization workflow:
  <https://developer.apple.com/documentation/security/customizing-the-notarization-workflow>
- Apple, creating distribution-signed code for the Mac:
  <https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac>
- Apple, Developer ID certificates:
  <https://developer.apple.com/help/account/certificates/create-developer-id-certificates>
