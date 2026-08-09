# Root Guard Command Stall Resilience Preview 13

## Context

Preview 12 correctly recovers an accessibility service that a complete
`dumpsys accessibility` report proves is unbound. The module supervisor only
restarts `guard.sh` after that process exits, while the health cycle invokes
Android Binder-backed commands directly. A stuck `pm`, `settings`, `dumpsys`,
`cmd`, `am`, or boot-readiness `getprop` call can therefore leave a live Guard
process that no longer repairs accessibility or keepalive state.

KernelSU documents that module scripts run in BusyBox `ash` standalone mode and
ships a complete BusyBox binary at `/data/adb/ksu/bin/busybox`. The module can
therefore use the fixed BusyBox `setsid`, `timeout`, and `kill` applets as an
internal containment boundary without adding a new Root command or depending
on a ROM-private API.

## Goals

- Bound every Android command that can block inside Root Guard or its fixed
  action/Kiosk/cleanup paths.
- Preserve existing observable semantics: a timed-out accessibility dump is
  `unknown` and non-destructive; timed-out reads/writes fail through their
  current error paths; a timed-out HOME launch remains a failed launch.
- Keep the APK bridge restricted to exactly the existing three fixed,
  no-argument module paths.
- Prove a command stall returns within a bounded test interval in both host
  shell execution and standalone BusyBox `ash` execution.

## Non-Goals

- No process killing outside the timeout wrapper's newly created command
  session; no existing app, system, or user-selected PID is targeted.
- No heartbeat file, watchdog kill policy, foreground Activity forcing, input
  injection, arbitrary shell arguments, package/component input, or new status
  schema value.
- No attempt to infer a live accessibility binding from process existence when
  the diagnostic is unavailable.

## Design

### Internal command boundary

Add one shared internal helper in `bin/common.sh` that invokes a fixed Android
command through explicit KernelSU BusyBox applets. It starts
`busybox timeout -k 1` in a new `busybox setsid` session, waits for the timeout
runner, and then kills only that newly allocated process group so a shell
wrapper's stalled descendant cannot keep a command-substitution pipe open. The
default bound is two seconds and a positive numeric test override is accepted
through the existing module-test environment convention. The helper is only
called at literal internal call sites; it is not exposed through the APK
bridge.

The production BusyBox path is fixed to `/data/adb/ksu/bin/busybox`. A
test-environment override and `command -v busybox` fallback allow the same
behavior suite to run on the host. If no BusyBox can be resolved, the helper
fails closed with a nonzero status instead of invoking the Android command
without a bound.

Wrap these existing calls without changing their arguments or result handling:

- `pm` package/component queries and enable operations;
- `settings` secure reads and writes;
- `dumpsys accessibility` binding diagnostics;
- `cmd deviceidle` and `cmd appops` keepalive operations;
- `am start` for the fixed Yinxing HOME component;
- `getprop` boot-readiness and fallback boot-id reads.

`uninstall-cleanup.sh` is intentionally standalone because it must survive
module removal; it gets the same local timeout helper for its fixed
`cmd deviceidle` cleanup call. The existing cleanup state machine remains
unchanged.

### Failure flow

- A timed-out `dumpsys accessibility` returns the same `unknown` state as a
  failed or empty diagnostic. Repair does not toggle settings because of it.
- A timed-out `pm` or `settings` operation returns failure through the current
  `repair_accessibility` path, records `last_repair=failed` in action/Guard
  callers, and leaves the supervisor eligible for its next cycle.
- A timed-out `cmd` keepalive operation remains an optional failure, as today.
- A timed-out fixed HOME launch returns failure and does not introduce a second
  launch mechanism.
- A timed-out boot `getprop` participates in the current bounded boot-wait
  configuration; no infinite command subprocess remains attached to Guard.

The outer APK command budgets remain unchanged in Preview 13. They still bound
the fixed `status.sh`, `action.sh`, and `kiosk-home.sh` processes, while the
module-side boundary prevents background Guard starvation between APK calls.

## Testing

Extend the existing `tools/test-yinxing-guard.sh` fixture so individual fake
Android commands can deliberately execute a real `/bin/sleep` longer than the
configured internal bound. Add behavior tests for:

1. a stalled accessibility dump producing a bounded, side-effect-free repair;
2. a stalled package/settings read producing bounded failed action state with
   no HOME launch;
3. a stalled HOME command producing a bounded failed fixed command; and
4. the standalone uninstall cleanup command retaining its existing state when
   its Doze removal command times out.

The same tests run in host `sh` and BusyBox `ash`. Existing bound/unbound,
unknown, first-enable, keepalive, lock, supervisor, and packaging tests remain
mandatory. Shell syntax, `git diff --check`, the Android JVM suite, Debug APK
build, deterministic module packaging, and fresh Release verification are the
Preview 13 gates.

## Release Contract

Preview 13 will bump APK code/name to `29`/`1.10.0-root-preview.13` and module
code/name to `13`/`1.10.0-root-preview.13`. The Release will include the Debug
APK, KernelSU ZIP, basename-only SHA-256 sums, installation order, Preview 12
rollback, the fixed authority statement, and the no-device caveat.

## Source

KernelSU module execution and BusyBox standalone-mode assumptions are based on
the official module guide: https://kernelsu.org/guide/module.html
