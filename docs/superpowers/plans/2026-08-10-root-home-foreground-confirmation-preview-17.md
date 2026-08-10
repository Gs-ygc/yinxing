# Root HOME Foreground Confirmation Preview 17 Implementation Plan

**Goal:** Confirm a Root-dispatched HOME activity after launch without
mistaking a user who has opened Settings or another app for a launcher fault.

**Architecture:** `launch_home()` samples the fixed activity dump only after
the fixed launch command and persists a strict boot-scoped result. `status.sh`
emits schema 3 and reads that result rather than sampling the current UI.
Guard, action, cleanup, Kotlin parsing, Settings UI, and Root command budgets
consume the same contract.

## Constraints

- Target only the managed OnePlus 15 China ColorOS 16 device, KernelSU, Root,
  and Android user 0.
- Keep exactly three fixed no-argument Root paths and route Android commands
  through the bounded wrapper.
- Treat malformed, failed, timed-out, oversized, and ambiguous diagnostics as
  unverified. They must not create repeated launcher starts.
- Preserve HOME rollback transactions, accessibility restoration, Doze
  ownership, caregiver choices, and uninstall cleanup behavior.
- Release values: app versionCode 33, module versionCode 17, version
  `1.10.0-root-preview.17`.

## Work items

- [x] Add activity-dump fixtures and red host/BusyBox tests.
- [x] Implement exact resumed/focused parser and bounded confirmation polling.
- [x] Persist atomically verified or unverified current-boot evidence.
- [x] Integrate Guard two-attempt bound, unknown-evidence circuit breaker, and
  post-confirmation repair result recording.
- [x] Upgrade status to schema 3; update direct and deferred cleanup.
- [x] Upgrade Kotlin parser, health predicate, Settings summary, and Root
  command budgets.
- [x] Add focused JVM regressions for schema 3, legacy schema degradation, UI
  labels, and Kiosk confirmation budget.
- [ ] Run complete shell and Android verification, package reproducible assets,
  publish the prerelease, then record remote asset verification.

## Release order

1. Install the Preview 17 APK first so the schema 3 parser is present while
   an older module can still report schema 2 as degraded data.
2. Install and enable the Preview 17 KernelSU module, then reboot if KernelSU
   requests it.
3. Run one explicit Root repair, then verify `桌面` and `前台确认` in Settings.
4. Test Home, an automation entry, and one reboot on the controlled device.

The final release note must distinguish host/BusyBox evidence from real
ColorOS 16 device evidence and include the exact test/build times, checksums,
and remote-download verification results.
