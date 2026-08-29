# JFC macOS VM E2E runbook

This runbook records the reproducible VM environment for JFC. The virtual HID
input transport is qualified on macOS 14.6.1; the complete automated scenario
matrix is not yet implemented. Automated input supplements, but never replaces,
the physical regression test in `AGENTS.md`.

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
   brew install node xcodegen
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

The resulting `build/Release/virtual-hid-device-service-client` sends one
button-1 down report, waits 120 ms, sends button-up, and exits. It sends no
keyboard report. With no arguments it clicks at the current pointer position.
`--move x y` targets a Core Graphics guest coordinate without clicking, and
`--target x y` targets that coordinate and clicks. Targeting uses only relative
HID reports and closes the loop by reading the resulting guest cursor position.

The macOS 14 qualification moved to each display center without clicking:

| Display | Requested | Reported final position | Relative reports |
| --- | --- | --- | ---: |
| D1 | `(725, 453)` | `(724.25, 452.324)` | 69 |
| D2 | `(2730, 720)` | `(2729.44, 719.426)` | 85 |
| D3 | `(5290, 720)` | `(5289.38, 719.426)` | 92 |

All three passed the per-axis tolerance of 0.75 Core Graphics points. This
qualifies cross-display pointer targeting; it does not yet qualify clicks on a
fixture or JFC behavior.

## Per-run startup and input qualification

Start the root daemon in an attached terminal. Do not install it as a permanent
launch service until the unattended privilege design is explicitly approved:

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

Stop the attached root daemon when the test session ends. The Driver Extension
may remain installed and enabled in the isolated VM, but no virtual-input
client should remain running between sessions.

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
| 14.6.1 (23G93) | Passed | Passed | Pending | Pending |
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

- Package daemon and client startup into a narrowly scoped, reviewable
  test-runner privilege design.
- Implement a deterministic fixture and machine-readable assertion.
- Automate window creation and placement for the canonical scenario matrix.
- Run JFC stopped/running A/B tests before expanding into fuzzing.
