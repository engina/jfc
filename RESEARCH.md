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

Deliberate launches register as a normal application, ensuring the control
window opens in front and remains reachable through the Dock and Cmd-Tab. When
the window closes, the application changes to accessory mode while leaving the
event tap running. Reopening the app restores regular-app presence and presents
the same window through the normal AppKit reopen callback. There is no menu-bar
item.

Start at Login uses `SMAppService.loginItem(identifier:)`, available on macOS 13
and later. JFC continues to target macOS 14 and later. Login launches remain
hidden; deliberate activation from Finder, Spotlight, or another launcher
presents the control window.

The helper lives in `Contents/Library/LoginItems`. Registration was verified to
reach the `enabled` state. A direct helper launch simulating login produced one
main JFC process with both an argument and environment launch marker; it settled
as a UI element with no windows. Reopening JFC reused that PID, changed it to a
foreground application, and restored one control window. The helper exited
cleanly in both registration and simulation tests. An actual logout/login or
reboot remains the final manual acceptance test.

## Reproducing the event-path experiment

Stop the app first so only one event tap is active, then run the preserved CLI:

```sh
swift build
.build/debug/jfc
```

For resolver-only diagnostics, use `.build/debug/jfc --observe --verbose`.

Focus VS Code, then click Play/Pause in an inactive Chrome/YouTube window. The
control should operate on that first physical click. Alternate between the two
apps for at least 20 clicks and check for lost or doubled clicks, play/pause
reversals, drag regressions, and noticeable delay. Synthetic input does not
substitute for this test.

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
