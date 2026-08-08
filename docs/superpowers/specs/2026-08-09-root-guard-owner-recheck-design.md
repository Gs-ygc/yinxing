# Root Guard Owner Recheck Preview 6

## Context

Preview 5 made `service.sh` restart `bin/guard.sh` after unexpected non-zero
failures. It still exits on guard status `0`. In production, the status is
primarily returned when another same-boot Guard already owns the atomic lock.
That is normal during a module restart or overlapping late-start invocation,
but the supervisor then disappears. If the original owner is killed shortly
afterward by an update, process reclaim, or OEM lifecycle action, no watcher
remains to recover the lock and restart repair.

KernelSU documents module `service.sh` as a non-blocking late-start entry point
executed in its standalone BusyBox shell:
https://kernelsu.org/guide/module.html.

## Goals

- Keep the supervisor alive after a duplicate-owner (`guard.sh` status `0`)
  result while the module remains active.
- Re-attempt ownership after a bounded owner-recheck delay so a dead original
  Guard can be reclaimed without a reboot or manual KernelSU action.
- Preserve the existing lock protocol, repair allowlist, and Preview 5
  non-zero failure behavior.
- Stop immediately when the module directory is absent or has `disable` or
  `remove` markers.
- Prove the owner-disappearance path in host and standalone BusyBox tests.

## Non-goals

- No change to `guard.sh` exit codes or lock acquisition/reclamation rules.
- No arbitrary Root shell, new package/component, coordinate input, or
  firmware/system-app integration.
- No foreground-app forcing or repeated launcher launches while a user is
  intentionally using another app.
- No device-specific ColorOS private settings.

## Design

`service.sh` reads one additional numeric delay:

```text
YINXING_GUARD_OWNER_RETRY_SECONDS (default 30)
```

Blank or non-numeric values fall back to 30 seconds. The supervisor classifies
the existing Guard result as follows:

| Guard result | Supervisor behavior |
|---|---|
| `0` | Recheck module state, sleep the owner-recheck delay, then invoke Guard again. |
| `75` | Recheck module state, sleep the existing short lock retry delay, then invoke Guard again. |
| Any other non-zero | Recheck module state, log the fixed diagnostic, sleep the restart backoff, then invoke Guard again. |

The module-state check remains before every launch and after every Guard exit.
If the module is disabled, marked for removal, or removed, the loop exits
without another Guard invocation. The supervisor does not inspect or mutate
the lock itself; the existing Guard remains the sole owner of lock creation,
PID validation, and dead-owner reclamation.

## Test Contract

Add one observable harness case:

1. Create a current-boot lock whose PID belongs to a live helper process.
2. Start `service.sh` with a zero owner-recheck delay and a bounded Guard cycle.
3. Have the helper remove the lock while remaining alive briefly.
4. Assert the supervisor eventually launches HOME exactly once after it
   re-enters Guard and takes ownership.

The existing duplicate-lock test remains unchanged as a direct Guard contract;
all Preview 5 restart, disable/remove, health, uninstall, and package tests
must remain green in host and standalone BusyBox modes.

## Safety and Rollback

The change only keeps an existing module-local supervisor alive longer. It
does not add a privileged command or alter the module's state writes. Preview 6
can be rolled back by disabling `yinxing_guard` or reinstalling Preview 5's
module and APK.

