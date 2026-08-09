# Root Accessibility Binding Stall Preview 16 Design

## Context

The Root Guard already enables Yinxing's AccessibilityService and can recover
an explicitly crashed or structurally unbound service. A ColorOS accessibility
manager can also leave the service in `Binding services` for multiple health
cycles. The current code treats one `binding` observation as success forever,
so it never retries the existing rebind operation and can report a misleading
healthy accessibility state.

Preview 16 closes that gap for the fixed managed device contract: OnePlus 15,
China ColorOS 16, KernelSU, Root, and Android user 0.

## Goals

- Detect a target service that remains in `Binding services` across health
  cycles, rather than relying on a single diagnostic snapshot.
- Reuse the already reviewed exact remove/restore rebind operation after a
  bounded observation threshold.
- Persist evidence atomically across Guard/action processes and across a
  reboot, while resetting the retry budget for a new boot.
- Bound destructive retries to two rebind attempts per boot and expose the
  persistent stall through the existing `accessibility=stale` status value.
- Keep the Root bridge, command timeout boundary, package/component constants,
  and all existing rollback semantics unchanged.

## Non-goals

- No new APK Root command, shell argument, arbitrary package/component, input
  injection, process selection, force-stop, private ColorOS API, or hidden
  framework API.
- No immediate toggle merely because a first-enable service is still binding.
- No change to the public schema-2 status line set or Kotlin parser values.
- No attempt to infer a binding from process existence when `dumpsys` is
  unavailable or malformed.

## Alternatives considered

1. **Leave `binding` as success.** This preserves the smallest behavior but
   leaves a persistent stall unrecoverable.
2. **Poll for several seconds in every health cycle.** This can reduce false
   positives, but it delays every cycle and still repeats settings writes each
   minute when ColorOS is stuck.
3. **Persist bounded stall evidence and retry (selected).** A small root-only
   marker distinguishes transient binding from a cross-cycle stall, triggers
   the existing targeted rebind only after two observations, and limits each
   boot to two attempts. It is deterministic, reversible, and testable without
   device-specific APIs.

## State contract

`bin/common.sh` adds the private marker
`$STATE_DIR/accessibility_binding_stall`. Its only valid value is one line:

```text
binding|<boot-id>|<observations>|<rebind-attempts>
```

`<boot-id>` is the same sanitized boot identifier used by the existing guard
state. `observations` is a canonical decimal count from 0 through 100000 (only
`0` or a non-zero digit followed by digits), and `rebind-attempts` follows the
same rule. The marker is written with the existing temporary-file, mode-0600,
read-back, and `sync` pattern. Symlinks, directories, malformed values, extra
lines, extra pipes, leading-zero counts, and failed read-back/sync are invalid
and never get overwritten.

The effective defaults are fixed and numeric:

- `YINXING_GUARD_BINDING_STALL_THRESHOLD=2`
- `YINXING_GUARD_BINDING_STALL_MAX_REBINDS=2`

Invalid, empty, zero, or non-numeric overrides fall back to those defaults.

## Repair state machine

After recovering any pre-existing accessibility transaction,
`repair_accessibility()` validates an existing stall marker before it enables
the package/component or writes either secure setting, then classifies the
target binding:

| Observation | Behavior |
| --- | --- |
| `bound` | Clear valid stall evidence; preserve settings. A clear failure fails the cycle. |
| `unknown` | Do not toggle settings. Clear valid stall evidence when possible; keep the diagnostic non-destructive. |
| `crashed` or `unbound` | Clear stall evidence, then run the existing exact rebind path. |
| `binding`, target not fully enabled before this cycle | Clear stale evidence and leave first-enable binding asynchronous. |
| `binding`, fully enabled, below threshold | Publish the next observation and return without a settings write. |
| `binding`, threshold reached and attempts below max | Publish the incremented attempt count, run one existing rebind, then re-read binding. If still `binding`, reset observations to 0 while retaining the attempt count for the next bounded window. If `bound`, clear evidence. |
| `binding`, max attempts reached | Log persistent stall, leave evidence intact, and fail the repair cycle without another settings write. |

The marker is reset to `observations=0,rebind-attempts=0` when its boot id is
not the current boot. A successful transition to `bound` clears it. A change to
`crashed`, `unbound`, or `unknown` also clears it before the existing path or
non-destructive return. If evidence cannot be safely written or cleared, the
code fails closed at the point where a mutation would otherwise occur.

The existing accessibility transaction marker remains the sole rollback record
for settings changes. Before a stall-triggered rebind, the same transaction is
created from the current enabled-services snapshot; all existing compensation
and caregiver-change checks therefore remain in force. If evidence clear or
post-rebind publication fails after that transaction has started, the repair
path invokes the existing compensation routine before returning, while
retaining malformed evidence for the next operator-visible recovery attempt.

## Status and uninstall

`status.sh` keeps emitting exactly the schema-2 nine-line contract. For a
fully-enabled target currently reported as `binding`, it emits
`accessibility=stale` only when a valid current-boot marker has reached the
observation threshold or the retry count is exhausted. A transient first
observation remains `enabled`; failed or malformed diagnostics remain
non-destructive and retain the existing `unknown` behavior where applicable.

The standalone uninstall script and its boot-completed cleanup helper remove
the diagnostic marker and temporary files as runtime state. They do not touch
the accessibility transaction marker or any user accessibility setting merely
because stall evidence exists.

## Testing

The shell fixture will add deterministic binding dumps and marker controls.
RED tests will prove:

1. the first binding observation publishes `binding|boot|1|0` without settings
   writes;
2. the second observation performs exactly one remove/restore pair and records
   one attempt;
3. a still-binding post-rebind state resets the observation window;
4. a third window performs the second and final attempt, after which another
   cycle fails without a third toggle;
5. a new boot resets the budget, a bound observation clears evidence, and
   malformed/symlink evidence fails closed;
6. status maps threshold evidence to `accessibility=stale` and transient
   evidence to `enabled`;
7. uninstall cleanup removes only the diagnostic marker.

All existing host and standalone BusyBox `ash` tests remain required, along
with syntax checks, fixed-command scans, Android unit tests, forced Debug
build, deterministic module packaging, APK metadata/signature checks, and
fresh GitHub release asset checksum verification.

## Acceptance criteria

1. A persistent target `Binding services` state receives at most two targeted
   rebinds per boot and never causes an unbounded settings-toggle loop.
2. A transient binding state does not receive an immediate second toggle.
3. A later `bound` observation clears evidence and returns the normal healthy
   path.
4. Unknown, malformed, stalled, or unsafe marker evidence never becomes a
   speculative mutation target.
5. Preview 16 is published as a rollback-capable Debug APK plus KernelSU ZIP
   and checksums, with no claim of physical-device validation before the user
   supplies OnePlus 15 evidence.
