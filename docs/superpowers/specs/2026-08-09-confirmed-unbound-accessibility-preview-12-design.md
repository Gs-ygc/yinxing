# Confirmed-Unbound Accessibility Recovery Preview 12

## Context

The KernelSU Root Guard already repairs a target AccessibilityService listed in
`Crashed services` and confirms a later `Bound` or `Binding` state. It treats
missing, failed, or unrecognized `dumpsys accessibility` output as `unknown`,
which must remain side-effect free. The current parser does not distinguish
that unknown case from a structurally complete dump whose `Bound services`,
`Binding services`, and `Crashed services` sections are all present but do not
contain the enabled Yinxing component. On a fixed rooted ColorOS 16 device,
that is useful evidence that the service is enabled but currently unbound.

## Goals

- Make a structurally complete, target-absent diagnostic visible as the existing
  `accessibility=stale` health state.
- Reuse the existing exact remove/restore rebind for a target that was already
  fully enabled before the repair cycle.
- Confirm `unbound` after rebind with the same bounded polling and fail-closed
  result used for persistent `crashed`.
- Leave normal first enable asynchronous: do not immediately toggle settings a
  second time merely because the service has not bound yet.
- Preserve the fixed, no-argument Root command allowlist and all existing
  unknown-output safety behavior.

## Non-goals

- No new Root command, shell argument, package/component input, coordinate
  automation, process killing, private ColorOS API, or Android UI redesign.
- No change to the APK Root bridge or its command-specific timeout budgets.
- No attempt to start or force-stop the application process based only on this
  diagnostic.

## State Contract

`accessibility_service_binding_state()` remains an internal shell contract with
five values:

| State | Evidence | Repair behavior |
| --- | --- | --- |
| `bound` | target appears in `Bound services` | preserve settings |
| `binding` | target appears in `Binding services` | preserve settings |
| `crashed` | target appears in `Crashed services` | existing exact rebind |
| `unbound` | all three named sections are present and target appears in none | exact rebind only if already fully enabled before this cycle |
| `unknown` | command failure, empty output, or any missing expected section | no settings side effects |

The parser records structural markers for all three named sections separately
from target matches. It retains the existing precedence `crashed` > `binding` >
`bound`; only when no target match exists and all structural markers are set
does it return `unbound`. Truncated or vendor-renamed output therefore remains
`unknown`.

`status.sh` maps both `crashed` and `unbound` to the existing external
`accessibility=stale` value. No new status line or APK parser value is needed.

## Repair Flow

Before changing settings, `repair_accessibility()` records whether the target
was already present in `enabled_accessibility_services` and whether
`accessibility_enabled` was already `1`. It performs the existing package,
component, service-list, and global-enable repairs unchanged.

- `crashed` continues to invoke the exact remove/restore helper regardless of
  whether another setting was repaired in the same cycle.
- `unbound` invokes the helper only when the pre-repair target membership and
  global enabled flag were both already true. This prevents a normal first
  enable from immediately being toggled a second time while Android is still
  binding it.
- `bound`, `binding`, and `unknown` keep their existing non-destructive paths.

The post-rebind confirmation loop treats both `crashed` and `unbound` as
retryable failure evidence. `bound` and `binding` confirm success. `unknown`
remains a bounded non-fatal `unverified` result. A final persistent `unbound`
or `crashed` result records failure, so `action.sh` will not launch HOME.

## Test Matrix

The existing host and standalone BusyBox harness will add observable behavior
tests for:

1. A complete empty binding dump reports `accessibility=stale`.
2. An already-enabled target with an initial `unbound` dump transitions to
   `binding`, performs exactly one remove/restore pair, and confirms recovery.
3. A persistent `unbound` target exhausts the bounded confirmation attempts,
   records `last_repair=failed`, and suppresses HOME launch.
4. A first-enable cycle with the target absent from settings enables it once
   without an immediate second remove/restore pair.
5. A partial or failed diagnostic remains unknown/non-destructive.

Existing crashed, bound, binding, unknown, missing-package, timeout, lifecycle,
and module supervisor tests remain unchanged and must continue to pass in both
shell implementations.

## Safety and Acceptance

The only new side effect is reuse of the already-reviewed exact component
remove/restore sequence under a stronger structural diagnostic and a previously
fully-enabled precondition. No command authority expands. Preview 12 is ready
for packaging only after shell syntax checks, host/BusyBox tests, the complete
Android JVM suite, a Debug build, deterministic module packaging, APK metadata
and v2 signature checks, and fresh GitHub asset verification all pass.
