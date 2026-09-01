# JFC end-to-end roadmap

This is the stable task list for the macOS end-to-end effort. Keep task
numbers stable; add sub-tasks rather than renumbering existing work.

Status legend: complete, in progress, pending.

1. **Complete** — Select the E2E architecture: a real macOS VM, Appium/Mac2,
   VirtualHID clicks, AX assertions, and recordings.
   Verification: the toolchain can arrange windows, issue a click, inspect the
   resulting state, and record all displays.
2. **Complete** — Provision and boot the macOS 14 UTM VM.
   Verification: macOS 14.6.1 boots successfully under Apple Virtualization.
3. **Complete** — Configure SSH, automatic login, and remote execution.
   Verification: the host can run unattended guest commands through `mac-vm`.
4. **Complete** — Configure three virtual displays using BetterDisplay.
   Verification: AppKit reports D1, D2, and D3 with the expected geometry.
5. **Complete** — Install and document the guest toolchain and test apps.
   Verification: Xcode, Appium/Mac2, Brave, VS Code, ffmpeg, and supporting
   tools run in the guest.
6. **Complete** — Implement VirtualHID mouse-click injection.
   Verification: the guest receives left-button down/up through the virtual HID
   device.
7. **Complete** — Verify VirtualHID against the deterministic counter fixture.
   Verification: one injected click increments the intended counter once.
8. **Complete** — Create the static HTML fixture and deterministic state oracle.
   Verification: test state is readable without OCR or foregrounding the app.
9. **Complete** — Define the JSON scenario DSL.
   Verification: display assignment, window stacking, initial focus, actions,
   and per-action expectations are represented in JSON.
10. **Complete** — Implement deterministic setup and pre-test cleanup.
    Verification: setup is inspected and must pass before any test action runs.
11. **Complete** — Implement action execution and assertions.
    Verification: each action yields a compact pass/fail result and state diff.
12. **Complete** — Record all displays and produce mosaic videos.
    Verification: each recorded run has synchronized D1/D2/D3 recordings and a
    viewable mosaic.
13. **Complete** — Generate the human-readable report.
    Verification: the report shows status, duration, expected state, failure
    diffs, mosaic video, and expandable artifacts.
14. **Complete** — Build the 12-scenario matrix.
    Verification: the matrix includes multiple displays, same-app windows,
    repeated transitions, multi-action cases, and the JFC-window-open case.
15. **Complete** — Add JFC-off negative controls.
    Verification: scenarios that require JFC fail when JFC is stopped.
16. **Complete** — Add opt-in forensic tracing.
    Verification: tracing is disabled by default and available explicitly for
    investigation.
17. **Complete** — Create the immutable macOS 14 preinstall baseline.
    Verification: the stopped baseline contains the E2E toolchain and
    BetterDisplay but no installed JFC product or JFC Accessibility decision.
18. **Complete** — Implement checksum-pinned signed install/uninstall helpers.
    Verification: the installed guest bundle has the same CDHash as the signed
    host build.
19. **Complete** — Prove that a fresh installation begins untrusted.
    Verification: JFC displays onboarding and reports neither Granted nor
    Running.
20. **Complete** — Automate the real Accessibility permission grant.
    Verification: System Settings enables JFC and JFC subsequently reports both
    Granted and Running.
21. **Complete** — Add a three-display boot-readiness gate.
    Verification: the runner waits for the exact D1/D2/D3 geometry and fails
    with a bounded timeout if it never appears.
22. **Complete** — Implement disposable cloning from the immutable baseline.
    Verification: each matrix run creates and boots a uniquely named clone
    without modifying the baseline.
23. **Complete** — Implement the complete `beforeAll` lifecycle.
    Verification: boot clone, wait for displays, build, sign, install, prove
    untrusted, grant Accessibility, and prove JFC running.
24. **Complete** — Implement the complete `afterAll` lifecycle.
    Verification: artifacts are collected before the disposable clone is shut
    down and deleted by its exact UUID.
25. **Complete** — Run the full matrix against a clean installation of the
    current one-process JFC.
    Verification: all 12 scenario results and recordings come from one clean,
    disposable run.
26. **Complete** — Preserve the current architecture as the behavioral baseline.
    Verification: the clean run is reproducible and its report is retained for
    comparison with the architecture change.
27. **Complete** — Design and implement the two-process architecture.
    Verification: a regular UI controls a headless `LSUIElement` AppKit
    event-tap helper while an open JFC window cannot interfere with
    inactive-window clicks.
28. **Complete** — Define agent lifecycle and IPC using Service Management,
    `NSWorkspace`, and a token-scoped local message port.
    Verification: start, stop, enable, crash recovery, login behavior, and
    status reporting work without a root daemon.
29. **Complete** — Update clean-install and TCC onboarding for the final process
    ownership model.
    Verification: a pristine clone grants only the required Accessibility
    permission to the correct executable identity.
30. **Complete** — Run the full matrix and negative controls against the final
    architecture.
    Verification: all required scenarios pass with JFC on and the designated
    controls fail with JFC off.
31. **Complete** — Investigate any remaining three-display regressions.
    Verification: each failure has a reproducible scenario and an evidence-led
    fix or an explicitly documented platform limitation.
32. **Pending** — Repeat the same matrix on every supported macOS version.
    Verification: the shared matrix passes on each supported version beginning
    with macOS 14.
33. **Pending** — Run the physical 20-click regression test.
    Verification: a person confirms no lost/double clicks, reversal, dragging
    regression, or noticeable delay.
34. **Pending** — Prepare and publish the release.
    Verification: documentation and version are updated, and the signed,
    notarized release artifact passes installation and launch checks.
    - **Complete:** install, validate, onboard, and uninstall the exact
      notarized DMG in a disposable pristine clone. This path was verified with
      the existing notarized 0.1.2 artifact.
    - **Complete:** enable Start at Login, reboot, verify hidden click delivery,
      disable it, reboot, and verify absence plus the JFC-off control.
    - **Pending:** run the complete integrated lifecycle against the final 0.2.0
      notarized DMG and create the release tag only after it passes.

The active order is 32–34. The final status runner bug is fixed. Three clean
macOS 14.6.1 runs then produced pass, fail, pass. Both complete passes covered
installation/onboarding, all 12 positives, lifecycle/recovery, both Start at
Login reboots, all seven controls, final status, cleanup, and clone deletion.
The middle run passed 11 positives but swallowed the click in
`jfc-window-open.json`; the identical scenario passed immediately before and
after. The release workflow will treat any such intermittent miss as a failed
gate.
