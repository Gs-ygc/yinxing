# Root Guard Accessibility Binding Recovery Preview 7

## Context

Preview 6 repairs the secure accessibility setting, package/component enabled
state, Doze ownership, and app-ops. Those checks can all be healthy while the
target `AccessibilityService` process has crashed: Android keeps the component
in the enabled setting, while the accessibility manager records the component
in its `Crashed services` state and stops dispatching events. In that state the
launcher appears configured but WeChat automation cannot receive events.

Android 16 AOSP exposes separate `Bound services`, `Binding services`, and
`Crashed services` sections in `dumpsys accessibility`. The module can use this
read-only, Root-only diagnostic without depending on a ColorOS private setting.

## Goals

- Detect an explicit crash state for Yinxing's fixed accessibility component.
- Rebind only that component by temporarily removing and restoring it in the
  existing colon-delimited secure setting, preserving every other service.
- Report `accessibility=stale` in the existing eight-line health snapshot when
  a crash is observable, so the APK's existing degraded/pending UI is truthful.
- Treat missing or unparseable `dumpsys` output as unknown evidence: do not
  toggle settings and do not make a healthy repair fail solely because the
  vendor omits the diagnostic.
- Prove the recovery and preservation behavior in Host and standalone BusyBox
  tests.

## Non-goals

- No arbitrary Root shell, command input, coordinate automation, foreground
  forcing, process killing, or ColorOS-private settings.
- No toggle when the service is merely `Bound` or `Binding`; those are healthy
  or transient states and must be left alone.
- No change to the existing module lock, Doze ownership, package allowlist, or
  APK Root command surface in Settings.
- No claim of OnePlus 15 success until the user exercises the module on-device.

## Design

### Module diagnostic

`bin/common.sh` adds `accessibility_service_binding_state()` with four outputs:

| State | Evidence | Repair behavior |
|---|---|---|
| `bound` | Target component appears in `Bound services` | No toggle |
| `binding` | Target component appears in `Binding services` | No toggle |
| `crashed` | Target component appears in `Crashed services` | Rebind target |
| `unknown` | `dumpsys` fails or has no recognizable target section | No toggle |

The parser scans only the named section in the command output and matches the
exact flattened component string. It never treats a generic occurrence in a
log line as proof of a crash.

### Repair flow

After the existing package/component and secure-setting checks succeed,
`repair_accessibility()` calls the binding diagnostic. On `crashed` only, it:

1. Reads the current service list again.
2. Removes only the exact Yinxing component using a colon-aware helper.
3. Writes the remaining services and waits one second for Android's service
   manager to clear the crashed connection.
4. Writes the original list with Yinxing restored and reasserts
   `accessibility_enabled=1`.

Any write failure returns a failed repair result; the next Guard cycle retries
from the persisted setting. If the initial removal succeeds but the restore
fails, unrelated services remain present and the normal missing-component
repair path restores Yinxing later.

### Health contract

The existing schema and eight lines remain unchanged. `accessibility` gains the
allowlisted value `stale`, emitted only for an explicit crashed target. The
APK parser accepts it and derives `DEGRADED`; existing UI mapping already shows
`stale` as a pending/problem value. `bound`, `binding`, and unknown diagnostics
do not trigger a new repair side effect.

## Safety and rollback

The module never clears all accessibility services and never changes another
component's value. A module disable/remove marker stops the supervisor before
the next repair. Preview 7 can be rolled back by disabling `yinxing_guard` or
reinstalling Preview 6's APK and module.

## Verification contract

- Add a red test for a crashed dump that preserves `talkback:other` while
  removing and restoring Yinxing exactly once.
- Add status coverage for `accessibility=stale` and a diagnostic-command
  failure that leaves settings untouched.
- Run host and standalone BusyBox full module suites, shell syntax checks,
  existing JVM tests, and a forced Debug build.
- Publish a Debug APK, deterministic KernelSU ZIP, basename-only checksums,
  acceptance notes, and fresh remote-download evidence.
