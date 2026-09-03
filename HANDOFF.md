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
2. **Pending — Capture comparable host and VM conditions during every run.**
   Verification: each run records the agreed CPU, memory, paging, swap, I/O,
   thermal, process, and per-action timing data at a configurable interval that
   defaults to two seconds.
3. **Pending — Reproduce and isolate the inconsistent failure.**
   Verification: passing and failing runs contain enough comparable evidence to
   identify which condition changes click delivery.
4. **Pending — Fix the responsible test infrastructure.**
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
