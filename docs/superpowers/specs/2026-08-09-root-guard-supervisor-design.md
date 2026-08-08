# Root Guard Supervisor Preview 5

## Context

The KernelSU module currently starts `bin/guard.sh` from `service.sh` and only retries when the guard reports the incomplete-lock code `75`. A transient non-lock failure during late boot, such as package-manager or secure-settings readiness, ends the background loop permanently. The launcher then has no Root repair attempt until the next reboot or a manual KernelSU action.

KernelSU documents module `service.sh` as a non-blocking late-start script executed in its BusyBox standalone shell. The module can therefore keep a small supervisor loop in that script without adding a second privileged command surface: https://kernelsu.org/guide/module.html.

## Goals

- Restart `bin/guard.sh` after an unexpected non-zero failure, including a transient first-boot repair failure.
- Preserve the existing lock protocol and fixed `repair_state`/`launch_home` allowlist.
- Stop promptly when the module directory is removed, disabled, or marked for removal.
- Apply a bounded, configurable delay so a persistent platform failure cannot cause a tight Root shell loop.
- Cover the restart and stop behavior in both host `sh` and standalone BusyBox tests.

## Non-goals

- No arbitrary Root shell entry point, coordinate automation, or new package allowlist.
- No replacement of the long-running health loop inside `guard.sh`.
- No attempt to force-enable unrelated accessibility providers.
- No firmware/system-app changes in this preview.

## Design

`service.sh` remains the only supervisor entry point. It starts `guard.sh` in the foreground of a detached background loop and classifies its exit:

| Guard result | Supervisor behavior |
|---|---|
| `0` | Exit; this indicates a deliberate/duplicate-owner stop or a bounded test run. |
| `75` | Sleep the existing short lock retry delay, then try again. |
| Any other non-zero result | Record one fixed diagnostic event, sleep the restart backoff, then try again. |

Before each retry, `module_is_active` checks that the module directory still exists and has neither `disable` nor `remove`. This makes uninstall/disable a terminal state even if the previous guard failed. The default unexpected-failure backoff is 30 seconds and accepts a numeric test/device override. Invalid values fall back to the default.

The supervisor itself does not call `su`, `settings`, `pm`, `am`, or any new command. All privileged effects remain inside the existing guarded scripts and lock. A failed guard releases its per-boot lock through the existing trap before the supervisor retries.

## Test Contract

- A fixture that makes the first `repair_accessibility` attempt fail and the next attempt succeed proves `service.sh` restarts a non-75 guard failure.
- A fixture that creates `disable` or `remove` after a failed attempt proves the supervisor does not restart a disabled/removing module.
- Existing incomplete-lock retry, duplicate-lock, health-cycle, uninstall, and packaging cases remain green.
- Run host and recursive `ASH_STANDALONE=1` BusyBox suites, shell syntax checks, Android unit tests, and a forced Debug build before release.

## Release and Rollback

Preview 5 increments the APK version code and KernelSU module version code. The Release includes the Debug APK, module ZIP, checksums, acceptance notes, and the exact rollback path to Preview 4. No device-specific success is claimed until the OnePlus 15/ColorOS 16 installation is exercised.
