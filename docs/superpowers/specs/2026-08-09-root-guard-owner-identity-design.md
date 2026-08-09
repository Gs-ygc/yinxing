# Root Guard Owner Identity Recovery Preview 8

## Context

Preview 7's Root Guard lock is keyed by the current boot ID and stores a PID.
When another Guard sees that PID alive, it returns the owner-active status `76`
and the supervisor waits before checking again. A PID can be reused during the
same boot after the original Guard exits. In that case `kill -0` succeeds for an
unrelated process and the supervisor can wait indefinitely instead of reclaiming
the stale lock and restoring the launcher.

## Goals

- Persist a kernel process start-time token alongside every newly created Guard
  owner PID.
- Treat a live PID with a different start-time token as a stale lock owner and
  reclaim the lock without signaling or killing that unrelated process.
- Make the health snapshot report `guard=stale` for the same identity mismatch.
- Keep the current conservative behavior when `/proc` cannot be read or when a
  legacy lock has no token: do not reclaim a live PID on incomplete evidence.
- Preserve the existing exit contract (`0`, `75`, `76`, and other failures),
  boot isolation, module disable/remove checks, and fixed Root command surface.

## Non-goals

- No process termination, `kill` beyond the existing `kill -0` liveness probe,
  command-line matching, arbitrary shell input, or new APK Root commands.
- No migration of old locks by deleting them solely because they lack a token.
- No changes to accessibility binding recovery, Doze policy, or the elderly
  launcher UI in this preview.

## Design

### Owner token

`common.sh` adds `process_start_time(pid)` that reads field 22 from
`/proc/<pid>/stat`, removing the parenthesized command name before tokenizing.
The proc root is overridable by `YINXING_GUARD_PROC_ROOT` for deterministic host
tests and defaults to `/proc` on Android.

When `guard.sh` creates a lock, it writes the boot ID, the start-time token, and
then the PID. The PID is published last so another process never accepts a PID
whose identity file is still being written. If the token cannot be read, the
lock retains the Preview 7 legacy shape and liveness-only behavior.

### Identity checks

For a live owner PID:

1. If no stored token exists, treat it as an older lock and conservatively keep
   the owner-active result.
2. If a stored token exists but the current token cannot be read, keep the
   owner-active result to avoid a duplicate Guard under restricted `/proc`.
3. If both tokens exist and differ, treat the lock as stale and enter the
   existing exclusive reclaim path.
4. If both tokens match, return `76` as before.

The same helper is used by `status.sh`: a mismatch is `guard=stale`; missing or
unreadable identity evidence remains `guard=running` for a live PID. Reclaiming
an identity-mismatched lock removes only the lock directory after obtaining the
existing reclaim directory; it never kills the live unrelated PID.

### Compatibility and safety

Preview 7 locks without `start_time` remain readable and conservative. A failed
write of the new token aborts lock publication before the PID is visible and
leaves the incomplete-lock retry behavior intact. Cleanup removes `start_time`
with the existing PID/boot files.

## Verification contract

- Add a red test where a live PID has a mismatched stored start time; the old
  implementation must return `76` while Preview 8 must reclaim and run one
  health cycle.
- Add coverage that newly acquired locks contain a token, matching tokens keep
  the active-owner result, unreadable tokens stay conservative, and status
  reports stale only for a confirmed mismatch.
- Run Host and standalone BusyBox module suites, POSIX/Bash/BusyBox syntax
  checks, full Android unit tests, and a forced Debug build.
- Publish APK/module/checksums and verify them from a fresh GitHub download.
