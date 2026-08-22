# macOS event/focus notes

The decisive Chrome/YouTube acceptance test passed with the default `both`
activation strategy and a zero-millisecond settle delay. Repeated use also
continued successfully across many sleep/wake cycles.

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

The focus experiment has three selectable paths:

- `ax`: set the target window's `kAXMainAttribute`, perform `kAXRaiseAction`,
  set the application's `kAXFrontmostAttribute`, and focus the window.
- `appkit`: call the current `NSRunningApplication.activate(options:)` API.
- `both`: AX first, then AppKit (the default experiment).

AX calls are synchronous messages, but a successful return does not constitute
proof that downstream event dispatch observes the new focus state. That is what
the physical-click test measures.

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

Start at Login uses `SMAppService.mainApp`, available on macOS 13 and later. JFC
continues to target macOS 14 and later. Login launches remain hidden; deliberate
activation from Finder, Spotlight, or another launcher presents the control
window.

## Primary references

- Apple, `CGEventTapCreate` and event-tap stages:
  <https://developer.apple.com/documentation/coregraphics/cgevent/tapcreate(tap:place:options:eventsofinterest:callback:userinfo:)>
- Apple, `CGEventTapCallBack` return semantics:
  <https://developer.apple.com/documentation/coregraphics/cgeventtapcallback>
- Apple, `AXUIElementCopyElementAtPosition` z-order hit-testing:
  <https://developer.apple.com/documentation/applicationservices/1462077-axuielementcopyelementatposition>
- Apple, `NSRunningApplication.activate(options:)`:
  <https://developer.apple.com/documentation/appkit/nsrunningapplication/activate(options:)>
- Apple, `kAXFrontmostAttribute`:
  <https://developer.apple.com/documentation/applicationservices/kaxfrontmostattribute>
- Apple, on-screen window ordering:
  <https://developer.apple.com/documentation/coregraphics/cgwindowlistoption/optiononscreenonly>
- Apple, `LSUIElement` agent applications:
  <https://developer.apple.com/documentation/bundleresources/information-property-list/lsuielement>
- Apple, main-app login registration:
  <https://developer.apple.com/documentation/servicemanagement/smappservice/mainapp>
