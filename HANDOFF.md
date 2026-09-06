# JFC E2E reliability handoff

## Goal

Make JFC's macOS E2E tests reliable. We observed one disposable VM run fail
repeatedly while equivalent fresh VM runs passed, so the immediate objective is
to identify the uncontrolled variable rather than assume the clone itself was
different.

## Task list

1. **Complete — Establish repeatable, isolated single-VM runs.**
   Verification: a selected scenario can run repeatedly in one disposable VM,
   and clean runs use only one VM at a time.
2. **Complete — Capture comparable host and VM conditions during every run.**
   Verification: each run records the agreed CPU, memory, paging, swap, I/O,
   thermal, process, and per-action timing data at a configurable interval that
   defaults to two seconds.
3. **In progress — Reproduce and isolate the inconsistent failure.**
   Verification: passing and failing runs contain enough comparable evidence to
   identify which condition changes click delivery.
4. **Pending — Fix the responsible component.**
   Verification: the isolated cause is corrected without masking missed clicks
   or weakening scenario assertions.
5. **Pending — Prove reliability across fresh VMs and the full matrix.**
   Verification: repeated clean runs and the complete E2E matrix pass without
   unexplained intermittent failures.
6. **Pending — Document the reliable procedure and findings.**
   Verification: the runbook explains the final workflow, recorded diagnostics,
   failure handling, and conclusions.

## Evidence behind the goal

- `repeat-vscode-d1-d3-transitions.json` passed in five separate fresh VM
  clones.
- A sixth clone failed five consecutive repetitions. Each repetition missed one
  Brave click, but the missed click occurred at different action positions.
- A seventh clone then passed three paired runs of the equivalent single-action
  scenario and the repeated scenario.
- Only one VM was running at a time.
- Therefore, "bad clone" is not an established explanation. The failure was
  temporally clustered, and the controlling condition remains unknown.

## Findings from the boundary capture

- The screen recorder now runs FFmpeg directly in the guest rather than through
  Mac2. It retains the 10 fps default, passes `-drop_late_frames 0` to the
  AVFoundation input, enables `-capture_mouse_clicks 1`, and uses output
  `-fps_mode passthrough` without `-r`. This removes both AVFoundation's default
  late-frame discard policy and FFmpeg output-rate conversion from the next
  experiment. The new recording path was subsequently used for the retained-VM
  comparisons below.
- FFmpeg's AVFoundation source sets
  `AVCaptureVideoDataOutput.alwaysDiscardsLateVideoFrames` from
  `-drop_late_frames`; its default is true. Mac2 does not expose that input
  option and adds an output `-r`, so it could not provide the no-drop recording
  contract required here.
- Mac2's `captureClicks: true` maps to FFmpeg's
  `-capture_mouse_clicks 1`, which uses
  `AVCaptureScreenInput.capturesMouseClicks`. Apple documents no minimum click
  circle duration, nearest-frame latching, or post-release animation; it only
  says the circle is drawn for the duration of the click. AVFoundation's
  implementation is closed, so the exact rule that causes the circle to be
  present in a delivered frame remains undocumented.
- Five 60 fps repetitions in one fresh VM produced four passes and one failure.
  FFprobe confirmed that all three recordings from the failed run were actually
  60 fps. In failed run `scenario-20260904T041235Z`, successful Brave actions 1
  and 5 had visible click circles, lasting approximately 67 ms and 233 ms
  respectively. Failed Brave action 3 had no circle in any 60 fps frame and no
  fixture DOM down/up/click, although the window activated. This is a useful
  correlation, but the old recorder's late-frame discard and output-rate
  conversion mean that absence of a circle is not yet conclusive boundary
  evidence.
- Only one disposable UTM VM ran, but the host also had Docker Desktop's Apple
  Virtualization VM running. It appeared in the host samples for both passing
  and failing repetitions and was not modified, so it does not distinguish the
  failure inside this five-run set; future host-condition comparisons must not
  describe this as literally a single-VM host.
- Fresh-VM stock-helper run `scenario-20260903T181437Z` reproduced the exact
  counter sequence `1, 1, 2, 2, 2`. A 1 ms
  `CGEventSource.buttonState(.combinedSessionState, button: .left)` sampler
  recorded all five down/up pairs, including a 98.2 ms down state for the
  failed fifth action. The fixture recorded no DOM down/up/click for that
  action.
- Under a three-stage listen-only Core Graphics observer, runs
  `scenario-20260903T181743Z` and `scenario-20260903T181838Z` passed, while
  `scenario-20260903T181933Z` failed. Every action in all three runs reached
  HID, session, and annotated-session taps at the intended coordinates. The
  annotated events named the correct target PID and window. In the failing
  run, the first Brave action reached the annotated-session boundary but the
  fixture received no DOM down/up/click. The loss is after Core Graphics target
  assignment and before Brave DOM delivery, not in the VirtualHID sender.
- The first Brave down took about 102-113 ms to reach annotated-session in the
  two passing runs and about 34 ms in the failing run. This, together with the
  AppKit contract that application activation is only a request and need not be
  immediate, points to activation readiness before the original event is
  returned.
- The previous uncommitted AX-frontmost candidate was removed before the next
  experiment so that only one variable changed. Packaged click-agent candidates
  held an inactive-window mouse-down after the existing focus/raise work, then
  returned the same incoming `CGEvent`; they added no retry or reinjection. The
  product override was removed after the controlled comparison rejected it.
- In the retained VM, ten 60 fps/no-drop repetitions of stock build 24 produced
  six passes, three runs with one missed Brave click, and one window-state-only
  failure. A notarized 50 ms candidate produced seven passes and three runs
  with one missed Brave click. A notarized 500 ms candidate also produced seven
  passes and three runs with one missed Brave click. No event-tap timeout was
  logged during the 500 ms set. The equal three-of-thirty missed-click count at
  0, 50, and 500 ms provided no evidence that a fixed post-focus hold improves
  delivery. The controlling condition remains unknown.
  Artifacts are under `E2E/Artifacts/ripple-60fps-nodrop`,
  `E2E/Artifacts/delay-50ms-60fps-nodrop`, and
  `E2E/Artifacts/delay-500ms-60fps-nodrop`.

Disposable VM `127D111D-5B97-48C6-BAB9-502EFC4A0B47` was created from the
immutable preinstall baseline. It first installed notarized JFC 0.2.0 build 24,
then received the notarized build 26 delay candidates in place for controlled
same-VM comparisons. Stock notarized build 24 was restored afterward from DMG
SHA-256 `d12d3814f2c78cb026b0df0c73b41db2b1a19d58e4b576f057c0da29cc4328db`,
and its click agent was verified running. The VM was left running at the user's
request; recheck its state before using it, and do not run `afterAll` or destroy
it without permission.

## Release decision — September 6, 2026

The maintainer reports that normal use of notarized 0.2.0 on their Mac works
well and explicitly chose to publish with `scripts/release.sh --no-test`.
Release preparation is separate from this unfinished investigation. Preserve
the artifacts and assertions; do not report the unresolved cause as isolated
or the release's automated qualification as passed.

## Constraints for the next session

- Do not run tests, start a VM, edit implementation code, or commit until the
  user explicitly says `go`.
- Use this task list for progress tracking; do not create a Codex Goal unless
  the user explicitly requests one.
- Keep tasks human-readable, chronological, and at macro level.
- Preserve the existing uncommitted E2E runner changes.
- Run only one disposable VM at a time.
- Do not weaken assertions, retry missed clicks, or hide failures to make the
  suite appear reliable.
