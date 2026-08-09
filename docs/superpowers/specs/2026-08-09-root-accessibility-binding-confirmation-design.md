# Root Accessibility Binding Confirmation Preview 10

## Context

Preview 7 taught the Root Guard to identify the fixed Yinxing accessibility component in `dumpsys accessibility` `Crashed services` and to rebind it by removing and restoring only that component in `enabled_accessibility_services`. Preview 9 preserves this recovery while adding a bounded Root Kiosk fallback.

The remaining accessibility recovery gap is the postcondition. After the secure-setting writes succeed, `rebind_accessibility_service()` immediately reports success. The Guard can therefore record `last_repair=ok` while ColorOS still reports the service as crashed, then wait for the next normal 60-second health cycle.

## Decision

Preview 10 adds bounded binding confirmation after one rebind. The Guard polls the existing read-only `accessibility_service_binding_state()` at most five times with a one-second interval between confirmed-crash observations.

- `bound` or `binding`: confirmation succeeds immediately.
- `crashed`: retry until the attempt limit; a crash on the final attempt fails the repair cycle.
- `unknown`: stop confirmation and preserve the existing non-destructive success behavior. Unknown vendor output is insufficient evidence to repeat settings changes or declare a persistent crash.

This is preferred over the current immediate-success behavior because it prevents false healthy markers, and over repeated remove/restore loops because those can flap accessibility state and disturb unrelated services.

## Module Behavior

`common.sh` gains a focused `confirm_accessibility_service_rebind()` helper. Its defaults are:

- `YINXING_GUARD_REBIND_CONFIRM_ATTEMPTS=5`
- `YINXING_GUARD_REBIND_CONFIRM_SECONDS=1`

Invalid values fall back to those defaults. Attempts must be greater than zero. Confirmation performs no writes and invokes no commands beyond the existing fixed `dumpsys accessibility` diagnostic and `sleep`.

`rebind_accessibility_service()` retains its existing sequence:

1. Remove only the exact Yinxing component while preserving TalkBack and other enabled services.
2. Wait one second.
3. Restore the exact merged service list.
4. Reassert `accessibility_enabled=1`.
5. Call the bounded confirmation helper.

The helper logs a fixed result:

- `accessibility_service_rebind_confirmed` for `bound` or `binding`.
- `accessibility_service_rebind_unverified` for `unknown`, while returning success.
- `accessibility_service_rebind_persisted` after the final confirmed `crashed` observation, while returning failure.

A persistent confirmed crash causes `repair_state()` to fail. `guard.sh` and `action.sh` already record `last_repair=failed`; `action.sh` must not launch HOME after that failed recovery. The next Guard health cycle may retry the single rebind sequence.

## Safety Boundaries

- The Root command allowlist remains unchanged: the APK can invoke only the existing fixed `status.sh`, `action.sh`, and `kiosk-home.sh` paths.
- No process kill, force-stop, private ColorOS API, coordinate input, package wildcard, arbitrary component, or arbitrary shell argument is added.
- A confirmation cycle never repeats the remove/restore writes. It only observes binding state after one rebind.
- `unknown` remains fail-safe and side-effect free so an unrecognized ColorOS diagnostic format cannot create a repair loop.
- Existing module disable/remove handling, owner lock identity, Doze ownership, uninstall cleanup, Kiosk eligibility, and normal unrooted APK behavior remain unchanged.

## Test Design

The host harness will support numbered accessibility dump responses so the real module functions see controlled state transitions under both host `sh` and standalone BusyBox `ash`.

Required regressions:

1. `crashed -> crashed -> binding` performs one remove/restore pair, polls until binding, and succeeds.
2. `crashed -> crashed -> crashed` with a bounded two-attempt confirmation fails, records `last_repair=failed` through `action.sh`, and does not launch HOME.
3. `crashed -> unknown` preserves the one remove/restore pair and succeeds without additional toggles.
4. Existing `bound`, `binding`, unavailable-diagnostic, unrelated-service, Kiosk, packaging, and lifecycle tests remain green in host and BusyBox modes.

Preview 10 versions are APK `versionCode=26`, module `versionCode=10`, and `versionName=1.10.0-root-preview.10`. Release verification includes the complete shell harness, shell syntax checks, all Android unit tests, a forced Debug APK build, APK metadata/signature checks, deterministic KernelSU ZIP checks, SHA-256 values, pushed source/tag equality, and fresh GitHub asset downloads.
