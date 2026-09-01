# JFC macOS VM E2E runbook

This runbook records the reproducible VM environment for JFC. The virtual HID
input transport and 12-scenario automated matrix are qualified on macOS 14.6.1.
Automated input supplements, but never replaces, the physical regression test
in `AGENTS.md`.

## Qualified baseline

`E2E/VM_MANIFEST.json` is the machine-readable inventory for this snapshot. It
pins installer URLs, package integrity values, upstream commits, and the
machine-independent UTM configuration. Do not copy UTM UUIDs, MAC addresses,
Apple hardware-model blobs, credentials, or TCC databases into the repository.

- Host hypervisor: UTM using Apple Virtualization.framework.
- Guest: macOS 14.6.1, build 23G93, Apple silicon.
- Guest displays: one UTM display plus two BetterDisplay virtual displays.
- Guest automation: Appium 3.7.0 with Mac2 driver 4.3.0.
- Guest input: Karabiner DriverKit VirtualHIDDevice 8.2.0.
- Test applications: JFC, Brave Browser, and Visual Studio Code.

The exact qualified versions are:

| Component | Version |
| --- | --- |
| UTM | 4.7.5 (118) |
| macOS | 14.6.1 (23G93) |
| Xcode | 16.2 (16C5032a) |
| Swift | 6.0.3 |
| Homebrew | 6.0.20 |
| Node.js / npm | 26.8.1 / 11.19.0 |
| FFmpeg | 9.0.1_1 |
| XcodeGen | 2.46.0 |
| Appium / Mac2 | 3.7.0 / 4.3.0 |
| BetterDisplay | 4.3.6 (50119) |
| Brave | 152.1.94.117 (194.117) |
| Visual Studio Code | 1.135.0 |
| JFC | 0.1.1 (2), commit `f96718f` |
| Karabiner DriverKit VirtualHIDDevice | package 8.2.0, extension 1.8.0 |

The qualified guest display geometry is:

| Display | NSScreen ID | Frame |
| --- | ---: | --- |
| D1, UTM | 1 | 1450×906 at `(0, 0)` |
| D2, BetterDisplay | 10 | 2560×1440 at `(1450, -534)` |
| D3, BetterDisplay | 11 | 2560×1440 at `(4010, -534)` |

Core Graphics uses these bounds for input targeting:

| Display | CGDirectDisplayID | Bounds |
| --- | ---: | --- |
| D1, UTM | 1 | 1450×906 at `(0, 0)` |
| D2, BetterDisplay | 2 | 2560×1440 at `(1450, 0)` |
| D3, BetterDisplay | 3 | 2560×1440 at `(4010, 0)` |

Do not use macOS Screen Sharing for this setup. Connecting Screen Sharing
removes or replaces BetterDisplay's guest displays.

## Reproducibility contract

The repository is the source of truth; a VM or snapshot is never the only copy
of test infrastructure. Before taking a qualified snapshot:

- Check in the source and build configuration for every custom diagnostic,
  fixture, input client, runner, and assertion tool.
- Record every guest dependency with an exact version and a repeatable install
  command or authoritative download location.
- Pin third-party source used during a build to an immutable release or commit,
  and record its signature or checksum when one is available.
- Record required macOS permissions and the command that verifies each one.
- Keep generated applications, build products, credentials, and VM images out
  of the repository.

A fresh VM for the same macOS version must be reproducible from the checked-in
files and this runbook. Snapshot restoration is only a time-saving path.

## One canonical scenario matrix

The scenario matrix is version-independent. Every supported macOS version must
pass the entire matrix; macOS versions are coverage rows, not separate test
definitions.

The original multi-window regression supplies these required placements. VSC
is VS Code, C1 is a non-target Brave window, and C2 is the target Brave window:

| Initially active | C1 display | C2 display | Required result with JFC running |
| --- | --- | --- | --- |
| VSC on D2 | D2 | D3 | C2 activates and operates once; C1 stays behind VSC |
| VSC on D2 | D2 | D2 | C2 activates and operates once |
| VSC on D2 | D1 | D3 | C2 activates and operates once |
| VSC on D2 | D1 | D1 | C2 activates and operates once |
| VSC on D2 | D2 | D1 | C2 activates and operates once; C1 stays behind VSC |
| VSC on D2 | D3 | D1 | C2 activates and operates once |
| C1 on D2 | D2 | D3 | Only C2 becomes the focused Brave window and operates once |

Run every placement as an A/B pair:

- JFC stopped: the first click activates C2 but does not operate its control.
- JFC running: that same single click activates C2 and operates the control
  exactly once.

The matrix also keeps JFC's control window visible while VS Code is active and
clicks C2 from another display. This guards the app lifecycle regression in
which a regular activation policy caused the first click to be swallowed. Four
multi-action recipes cover repeated C2 clicks, alternation between two Brave
windows, and repeated VS Code ↔ C2 transitions in two display arrangements.
Run all 12 recipes with:

```sh
./scripts/run-e2e-matrix.sh mac-vm
```

For the whole matrix, also verify no focus change occurs without a left click,
C1 is not raised accidentally, mouse-up is unchanged, double-click and hold
semantics remain intact, and title-bar dragging and resizing are unaffected.
Repeat the core VS Code ↔ C2 transition at least 20 times during the physical
acceptance test required by `AGENTS.md`.

## One-time VM provisioning

1. Create an Apple Virtualization UTM VM with 6 CPUs, 8192 MiB RAM, a 64 GiB
   disk, shared networking, Mac keyboard, Trackpad pointer, and one dynamic
   1920×1200 display at 80 PPI. Install the exact Apple restore image recorded
   in `E2E/VM_MANIFEST.json` and verify its SHA-256 before use.
2. Complete Setup Assistant and create an administrator account with a
   non-empty password. Never store that password in this repository.
3. Enable Remote Login and install the host SSH key. Add a host alias:

   ```sshconfig
   Host mac-vm
     HostName <guest-ip>
     User <guest-user>
   ```

4. Install BetterDisplay inside the guest and create D2 and D3. Verify all
   three frames using `NSScreen.screens` or the Appium display query.
5. Install Xcode 16.2 from Apple Developer Downloads and verify the XIP against
   the manifest. Install Homebrew, then the pinned guest tools:

   ```sh
   brew install node xcodegen ffmpeg
   brew install --cask brave-browser visual-studio-code
   npm install --global appium@3.7.0
   appium driver install mac2@4.3.0
   ```

   Homebrew formula and cask definitions move over time. Verify the resulting
   versions against the manifest; it records the qualified tap commits,
   immutable download URLs, and integrity values needed to recover the exact
   artifacts. Install BetterDisplay from the pinned DMG in the manifest.
   Build JFC from the recorded commit with `scripts/build-app.sh release`.
6. Grant Xcode Helper the Automation permission required by Mac2. Verify a
   Mac2 session can launch and control TextEdit and reports all three displays.
7. Build `JFC Input Diagnostic.app` from repository source:

   ```sh
   scripts/build-input-diagnostic-app.sh release
   ```

   Deploy the resulting `.build/JFC Input Diagnostic.app`, grant that app Input
   Monitoring in the guest, and relaunch it. A valid launch must report
   `cgListenEventAccess: true` and `ioHIDListenAccess: "granted"`.
8. Take a clean stopped-VM snapshot after provisioning and record `sw_vers` in
   the snapshot notes.

## Install the virtual HID input transport

Pin the package and client source to the same release. The qualified release is
8.2.0:

```sh
curl -fLO \
  https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice/releases/download/v8.2.0/Karabiner-DriverKit-VirtualHIDDevice-8.2.0.pkg
pkgutil --check-signature Karabiner-DriverKit-VirtualHIDDevice-8.2.0.pkg
open Karabiner-DriverKit-VirtualHIDDevice-8.2.0.pkg
```

Signature verification must report Developer ID Installer team `G43BCU2T37`
and a trusted Apple notarization ticket.

Activate the installed extension:

```sh
'/Applications/.Karabiner-VirtualHIDDevice-Manager.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Manager' activate
```

Approve `Karabiner-DriverKit-VirtualHIDDevice` under System Settings → General
→ Login Items → Driver Extensions. Verify both enabled and active markers:

```sh
systemextensionsctl list | grep Karabiner-DriverKit-VirtualHIDDevice
```

The qualified result is `activated enabled`. This installs a privileged
virtual keyboard and mouse capability in the isolated test VM. The daemon only
accepts root clients.

## Build the bounded click client

The upstream example sends keyboard input and pointer movement; do not run it
unchanged. Replace its `src/main.cpp` with this repository's bounded
left-click-only client:

```sh
brew install xcodegen
git clone --depth 1 --branch v8.2.0 \
  https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice.git
cp E2E/VirtualHIDClick/main.cpp \
  Karabiner-DriverKit-VirtualHIDDevice/examples/virtual-hid-device-service-client/src/main.cpp
cp E2E/VirtualHIDClick/project.yml \
  Karabiner-DriverKit-VirtualHIDDevice/examples/virtual-hid-device-service-client/project.yml
cd Karabiner-DriverKit-VirtualHIDDevice/examples/virtual-hid-device-service-client
make
```

The resulting `build/Release/virtual-hid-device-service-client` accepts no
arguments, sends one button-1 down report at the current pointer, waits 120 ms,
sends button-up, and exits. It sends no keyboard or pointer-movement report.
The scenario executor positions and verifies the pointer in the logged-in user
session before invoking this root-only click client.

Do not call Core Graphics display or cursor APIs from the root client. A client
launched by `sudo` over SSH blocked in `CGGetActiveDisplayList` on macOS 14 and
wedged WindowServer until the VM was rebooted. Keeping display lookup and pointer
positioning in the logged-in session avoids that invalid process/session mix.

## Manual input-transport qualification

For a one-off diagnostic capture before installing the automated runner, start
the root daemon in an attached terminal:

```sh
sudo '/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice/Applications/Karabiner-VirtualHIDDevice-Daemon.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Daemon'
```

Arm the diagnostic for one click, then run the bounded client as root:

```sh
open -n 'JFC Input Diagnostic.app' --args \
  --clicks 1 --output "$HOME/jfc-e2e-artifacts/guest-virtual-hid-click.jsonl"

sudo ./build/Release/virtual-hid-device-service-client
```

The capture passes only if it contains:

- HID primary-button down and up from the Karabiner virtual pointing device.
- Core Graphics down and up at `hid`, `session`, and `annotatedSession`.
- `eventSourceUnixProcessID = 0`, `eventSourceStateID = 1`, user data `0`,
  flags `0`, subtype `0`, and pressure `1` then `0`.
- One event number shared by that down/up pair.

The qualified macOS 14 capture met every condition. The virtual click did not
require UTM to be active and did not use the host cursor or host focus.

### Install the bounded runner privilege

The upstream daemon and its clients require root. Do not grant passwordless
access to a user-writable executable. After building the bounded client, install
one root-owned copy and checksum-pinned sudo rules:

```sh
sudo E2E/VirtualHIDClick/install-privileges.sh \
  ./build/Release/virtual-hid-device-service-client
```

The installer verifies the signed Karabiner daemon bundle, installs the bounded
client and a root-owned on-demand LaunchDaemon definition, and authorizes only
these checksum-pinned commands:

- `/usr/local/libexec/jfc-e2e-virtual-hid-click`, which accepts no arguments and
  sends only one left click at the current pointer.
- `/bin/launchctl kickstart
  system/io.e10n.jfc.e2e.virtual-hid`, which starts only the
  installed VirtualHID job.
- `/bin/launchctl kill SIGTERM
  system/io.e10n.jfc.e2e.virtual-hid`, which stops only that job.

It does not authorize a shell, interpreter, general process-management command,
arbitrary `launchctl` arguments, or the user-writable build output. The rules
stop matching if the installed client or `/bin/launchctl` changes. Re-run the
installer after a deliberate upgrade.
Remove the complete privilege boundary with:

```sh
sudo E2E/VirtualHIDClick/uninstall-privileges.sh
```

The scenario runner starts and stops the on-demand job around its actions and
also attempts the exact stop command from its host-side cleanup trap. The job
remains loaded but `state = not running` between tests. The Driver Extension may
remain installed and enabled in the isolated VM.

## Deterministic click fixture

`E2E/Fixture/index.html` is the browser fixture. It has no network or package
dependency. Opening or reloading it resets its accepted-click count to zero.
Its stable accessibility labels are `JFC click target` for the button and
`JFC accepted click count` for the read-only counter. Each DOM `click` increments
the visible counter and the number in the window title exactly once.

Copy the fixture into the guest and open it as a local file in Brave. Before
each case, reload it and verify the counter and window-title suffix are both
zero. Input must come from the qualified virtual-HID client; do not invoke the
button through JavaScript or Appium.

### Qualified single-window A/B result

On macOS 14.6.1 (23G93), Brave displayed the fixture while TextEdit was the
active application. One qualified virtual-HID click was sent to the fixture
button in each case:

| JFC state | Accepted-click count | Result |
| --- | ---: | --- |
| Stopped | 0 | macOS activated Brave and swallowed the first click |
| Running with `--launch-at-login` | 1 | JFC activated Brave and the original click operated the button once |

Mac2 read the final accessibility value `1` and the Brave window title
`JFC Click Fixture — 1 - Brave`. Mac2 was used only for setup and assertion;
the tested input came from the virtual-HID client.

## JSON scenario setup executor

Scenarios are ordinary JSON. The outer `windows` array is D1, D2, D3; each
inner array is back-to-front window order; and exactly one `*` marks the
initially active window. Application, window, and control identities are
encoded directly in tokens such as `brave.2.play`:

```json
{
  "windows": [
    [],
    ["brave.1", "vscode*"],
    ["brave.2"]
  ],
  "actions": [
    {
      "click": "brave.2.play",
      "expect": {
        "windows": [
          [],
          ["brave.1", "vscode"],
          ["brave.2*"]
        ],
        "brave.2.counter": 1
      }
    }
  ]
}
```

Run the scenario from the host:

```sh
./scripts/setup-e2e-scenario.sh E2E/Scenarios/setup-smoke.json
```

The placement suite contains all seven recipes from the original matrix:

| Recipe | Initial state | Target |
| --- | --- | --- |
| `setup-smoke.json` | VSC D2, C1 D2 | C2 D3 |
| `vscode-d2-c1-d2-c2-d2.json` | VSC D2, C1 D2 | C2 D2 |
| `vscode-d2-c1-d1-c2-d3.json` | VSC D2, C1 D1 | C2 D3 |
| `vscode-d2-c1-d1-c2-d1.json` | VSC D2, C1 D1 | C2 D1 |
| `vscode-d2-c1-d2-c2-d1.json` | VSC D2, C1 D2 | C2 D1 |
| `vscode-d2-c1-d3-c2-d1.json` | VSC D2, C1 D3 | C2 D1 |
| `c1-active-d2-c2-d3.json` | C1 D2 | C2 D3 |

All seven require the clicked C2 control to operate once and become focused
without raising C1 above an unrelated window. JFC-stopped control runs and
multi-action sequences are separate coverage described below.

Four additional recipes exercise action sequences:

| Recipe | Actions | Measured purpose |
| --- | --- | --- |
| `repeat-c2-three-clicks.json` | C2 → C2 → C2 | Counter advances `1`, `2`, `3`; active-window pass-through stays exact |
| `alternate-brave-windows.json` | C2 → C1 → C2 | Same-application window focus, ordering, and both counters after every click |
| `repeat-vscode-c2-transitions.json` | C2 → VSC → C2 → VSC → C2 | Repeated cross-application activation while C1 remains behind VSC |
| `repeat-vscode-d1-d3-transitions.json` | C2 → VSC → C2 → VSC → C2 | Three repetitions of the fixed primary-display C1 / cross-display C2 regression |

One regression recipe keeps JFC's own control window visibly open on D1 while
VS Code is active on D2 and the target Brave window is on D3. It verifies that
the target operates once and that the JFC window does not alter the declared
ordering. Run all seven placements, this visible-window regression, and all
four multi-action recipes with:

```sh
./scripts/run-e2e-matrix.sh
```

`vscode.surface` is a deterministic point one quarter across and halfway down
the VS Code window frame obtained through Accessibility. Appium/System Events
only resolves that frame; the qualified VirtualHID client performs the click.
The point lies in the exposed left portion of the canonical VS Code geometry,
so it remains clickable even when a Brave window on D2 is above the overlapping
right portion.

The script copies the checked-in executor, scenario, and fixture to the guest;
starts Appium when needed; builds, places, and stacks the requested windows;
selects the starred window; resolves every referenced control through Mac2
Accessibility; executes the JSON actions with the VirtualHID client; asserts
the declared post-action state; records all displays; and writes the complete
artifact set beneath an ignored `E2E/Artifacts/scenario-*` directory. Appium is
the setup, assertion, and recording channel. It does not perform scenario
clicks.

`result.json` is deliberately compact. The scenario is the source of truth for
setup, actions, and expected values, so the result contains only the scenario
name and hash, overall status, total run duration, and the normalized observed
state at each action that declares expectations. It does not repeat setup,
actions, expectations, artifact paths, Appium element identifiers, pointer
coordinates, or raw Core Graphics window records. Setup verification remains a
fail-fast precondition and is not reported as a test result. The fixture
publishes its accepted-click count in both its control and window title, so the
final read-only machine-state snapshot supplies both window order and
`brave.N.counter` without activating an application or retaining an expiring
Appium element handle.

An expectation mismatch still writes the compact observed state, marks its
assertion and overall result `failed`, collects the recordings and screenshots,
regenerates the report, and makes the host runner exit nonzero. This lets the
report derive a focused expected-versus-actual diff from the unchanged scenario
recipe without duplicating expectations in `result.json`. Failures that occur
before the initial setup is verified remain setup failures and do not produce a
test result.

Brave starts with a fresh temporary profile on every run so session restoration
cannot add stale windows. The guest must grant the Mac2/Xcode helper Automation
access to System Events, Brave Browser, and Visual Studio Code. Screen Recording
must be enabled for `sshd-keygen-wrapper` so the verifier can inspect global
Core Graphics window order and capture all displays.

Before constructing a scenario, the executor dismisses a visible login-window
power dialog only through its non-destructive `Cancel` button and hides a fixed
allowlist of ordinary setup applications. Setup then fails if any undeclared
layer-zero application window remains on screen. This prevents a stale dialog
or window from contaminating the click result while avoiding broad process
termination.

Setup verification fails unless all of these measurable conditions hold:

- The VM display count equals the number of JSON display arrays.
- Every declared window exists exactly once and its center lies on its declared
  display.
- All declared Brave windows belong to one process.
- Each display's measured front-to-back order equals the reverse of its JSON
  back-to-front array.
- The starred application's bundle ID is frontmost and the app's direct
  `AXFocusedWindow` value identifies the starred window.
- Every control referenced by an action or expectation resolves to exactly one
  Accessibility element.

The `setup-smoke.json` scenario passed end-to-end twice consecutively on the
qualified macOS 14.6.1 VM. Both initial setups passed 15 of 15 checks. The
executor positioned the pointer at the center of `brave.2.play`, measured a
0.5-point x-axis error and zero y-axis error, and sent one VirtualHID click. The
counter changed from `0` to `1`. Both post-action verifications passed 15 of 15
checks: Brave was frontmost, `brave.2` was the AX-focused window, and D2
remained `vscode`, `brave.1` front-to-back. After each run, the LaunchDaemon
reported `state = not running` and last exit code `0`.

The original activation sequence passed six placements but repeatedly failed
`vscode-d2-c1-d1-c2-d3.json`: `brave.2` became frontmost and AX-focused on D3,
but its accepted-click counter remained `0`. Input and window-server traces
showed that AppKit's activation transaction temporarily selected `brave.1` on
the primary display after JFC's initial raise. JFC now reasserts the target
window's `AXMain` and `AXRaise` immediately after requesting application
activation. The fixed sequence passed all seven placements, ten consecutive
VS Code → C2 transitions in the former failure layout, and all four
multi-action recipes. Physical three-display hardware verification remains
required before release.

The control-window activation-policy regression has a separate unchanged
red/green recipe, `jfc-window-open.json`. Against the previous build, which
became a regular application while its window was visible, setup and final
window placement succeeded but the fixture counter remained `0`. Against the
accessory-only build, the same recipe and SHA-256
`ac86d3eca5cc8354f8191d2855f6a031191adac75125de7c451b0d75a5dc9bf5`
passed with the counter at `1`. The visible JFC window remained on D1, VS Code
began active over C1 on D2, and C2 became active on D3.

After deployment, one complete back-to-back matrix run had an isolated miss in
`vscode-d2-c1-d1-c2-d1.json`: C2 became active but its counter remained `0`.
The unchanged recipe then passed three consecutive isolated reruns and passed
again in a complete clean 12-of-12 matrix run. Preserve the failed artifact as
an intermittent observation; it has not been treated as a product regression
or used to loosen the assertion.

### Clean product qualification

Run the complete fail-fast product lifecycle from the host with:

```sh
./scripts/run-clean-e2e-matrix.sh mac-vm
```

The runner clones the immutable preinstall baseline, proves the signed build is
initially untrusted, enables the single `JFC Click Agent` Accessibility row,
runs all 12 positive scenarios, and verifies Stop, Start, and forced agent-crash
recovery. It then enables Start at Login, performs a normal macOS reboot,
verifies hidden operation and click delivery, disables Start at Login, reboots,
and verifies both absence and the expected swallowed-click control. Finally it
runs all seven JFC-off controls, verifies final status, captures artifacts,
proves product cleanup, and deletes the exact disposable clone.

The release command supplies `JFC_E2E_DMG_PATH` automatically:

```sh
scripts/release.sh
```

In this mode the installer transfers the exact notarized DMG, verifies its
SHA-256 digest on both hosts, validates its staple and Gatekeeper assessment in
both environments, mounts it read-only, and compares the installed app's code
identity with the image. The release remains untagged unless this entire clean
lifecycle passes. `scripts/release.sh --no-test` is the explicit bypass.

The Start-at-Login lifecycle passed independently on macOS 14.6.1. One
integrated run then passed all functional gates but exposed a missing Appium
restart before the final status assertion; the runner now establishes that
precondition explicitly. Three subsequent clean runs produced pass, fail,
pass. The complete passes took 1009.52 and 954.71 seconds. The failed run took
615.55 seconds and stopped after 11 of 12 positives: `jfc-window-open.json`
focused the expected C2 window but left its counter at `0`. That unchanged
scenario passed in the runs immediately before and after it, so the failure is
retained as intermittent release-gate evidence rather than accommodated by the
scenario.

### JFC-off negative controls

Run the unchanged positive recipes with JFC deliberately stopped:

```sh
./scripts/verify-e2e-jfc-off.sh
```

The control runner records under `E2E/Artifacts/jfc-off`, leaving the normal
latest-run report untouched. It remembers whether JFC was initially running,
stops it, runs all seven positive recipes, and restores it from
`/Applications/JFC.app` on every exit path. A control passes only when the
ordinary scenario result fails for one exact reason: C2 becomes active with the
expected window order, but its accepted-click counter remains `0` instead of
the positive expectation `1`. Setup failures, unexpected window changes, an
accepted click, stale scenario contents, and extra observed fields all reject
the control.

All seven JFC-off controls passed this qualification on the macOS 14.6.1 VM.
For six placements, the paired JFC-running recipe accepts one click while the
JFC-stopped control accepts none, proving that those tests exercise JFC's
behavior. In the pre-fix positive run,
`vscode-d2-c1-d1-c2-d3.json` accepted no click in either state; the fixed
JFC-running sequence now accepts the click while the unchanged JFC-off result
remains the expected negative control.

All four multi-action recipes passed with JFC running. The repeated-target
recipe accepted three clicks exactly once each. The Brave alternation recipe
preserved the asserted per-display order while its counters advanced C2 `1`,
C1 `1`, then C2 `2`. The cross-application recipe completed five physical HID
actions with C2 advancing `1`, `2`, `3` and VS Code regaining focus between
them without raising C1. The D1/D3 variant repeated that cross-application
transition three times in the formerly failing layout with the same result.

## Capture visual evidence of every display

From the repository root on the host, run:

```sh
./scripts/capture-vm-displays.sh
```

The default SSH host is `mac-vm`. An alternate host and output directory can
be passed as the first and second arguments. The script queries `NSScreen` in
the guest, runs the built-in `screencapture` command once for every reported
display, and copies the results into an ignored `E2E/Artifacts/display-dump-*`
directory. Each dump contains `display-1.png`, `display-2.png`, and so on, plus
`displays.json` with names, IDs, frames, scale factors, and pixel dimensions.
The guest must have a logged-in GUI session. Screen Recording must be enabled
for the guest SSH process (`sshd-keygen-wrapper`); the script checks this before
capturing and refuses to produce wallpaper-only screenshots when it is absent.

## Record every display through Mac2

Mac2's FFmpeg recorder accepts one AVFoundation screen device per Appium
session. `scripts/record-vm-displays.sh` creates one session per reported screen,
starts all recordings together, retrieves each H.264 MP4, and mosaics the files
on the host with FFmpeg:

```sh
./scripts/record-vm-displays.sh mac-vm 5
```

The second argument is the recording duration in seconds. Output is written to
an ignored `E2E/Artifacts/recording-*` directory containing `display-1.mp4`,
`display-2.mp4`, `display-3.mp4`, `recordings.json`, and `mosaic.mp4`. The raw
files preserve full Retina resolution; the mosaic scales each display to 720
pixels high and arranges D1, D2, and D3 left-to-right. Recording is evidence
only and never supplies test input or assertions.

`scripts/setup-e2e-scenario.sh` uses the same recorder around scenario actions.
Its artifact directory contains the three raw display MP4s, `recordings.json`,
`mosaic.mp4`, `result.json`, and final per-display screenshots. The qualified
action recording was 7.151 seconds at 10 FPS; its 3712×720 mosaic visibly
showed `brave.2.counter` changing from `0` to `1`.

After every completed test scenario, the runner regenerates
`E2E/Artifacts/report.html`. This dependency-free static page embeds the latest
valid recipe and compact result for each scenario. The page header reports the
aggregate duration of the displayed runs. Each scenario is a collapsed
accordion row whose title contains a human-readable test name, duration, and
pass/fail status; opening it shows the initial state, action, expected output
state, result, and mosaic video. Other recordings and final screenshots are
collapsed under `All artifacts…`. Failed assertions show their
expected-versus-actual differences in red. The HTML keeps media at relative
artifact paths. Serve the artifact root so the browser can load those files:

```sh
python3 -m http.server 8765 --bind 127.0.0.1 --directory E2E/Artifacts
```

Then open `http://127.0.0.1:8765/<run-directory>/report.html`. Rebuild a report
manually with:

```sh
node scripts/generate-e2e-report.mjs
```

The qualified macOS 14.6.1 probe reported these AVFoundation mappings:

| Display | Device ID | Raw video | FPS | Verified duration |
| --- | ---: | --- | ---: | ---: |
| D1 | 0 | 2900×1812 | 10 | 5.1 s |
| D2 | 1 | 5120×2880 | 10 | 5.1 s |
| D3 | 2 | 5120×2880 | 10 | 5.6 s |

The resulting mosaic was 3712×720, 10 FPS, and 5.1 seconds. A second recording
of `setup-smoke.json` visibly showed VS Code over `brave.1` on D2 and
`brave.2` on D3 in the expected left-to-right order.
The standard macOS `Automation Running` overlay is part of the recording while
Mac2 sessions are active. Scenario assertions must not depend on video pixels.

## Rejected input paths

Do not regress to these approaches:

- Appium Mac2 `macos: click` enters at the guest session layer. It does not
  produce a guest HID-stage event.
- Posting a global host `CGEvent` into UTM reaches the guest HID stage, but UTM
  must own host focus. Requiring exclusive host control is unacceptable.
- `CGEvent.postToPid(UTM_PID)` preserves host focus and cursor, but UTM forwards
  no guest event.
- Direct guest `IOHIDUserDeviceCreateWithProperties` fails without Apple's
  restricted `com.apple.developer.hid.virtual.device` entitlement.

## Supported-macOS coverage

Use a separate clean VM or immutable clone for each supported major macOS
version. Do not upgrade the only known-good VM in place. Each row must run the
same canonical scenario matrix defined above.

| Guest macOS | Provisioning | Virtual HID | Entire canonical matrix | Physical acceptance |
| --- | --- | --- | --- | --- |
| 14.6.1 (23G93) | Passed | Passed | 12 of 12 passed | Pending |
| 15.x | Pending | Pending | Pending | Pending |
| 26.x | Pending | Pending | Pending | Pending |

For each OS row, record these measurable prerequisites before running the
matrix:

| Check | Pass condition |
| --- | --- |
| OS identity | `sw_vers` matches the intended version and build |
| Displays | D1, D2, and D3 have the required count and non-overlapping frames |
| Mac2 smoke | TextEdit launches and a deterministic control can be queried |
| Virtual HID | The diagnostic satisfies every input-qualification assertion |

Store JSONL captures and matrix results under an artifact directory named with
the guest version, build, JFC commit, and timestamp. Never publish captures
without review because they can contain device information, coordinates, and
process identifiers.

## Pending work

- Run the same canonical scenarios on macOS 15 and macOS 26 before expanding
  into fuzzing.
