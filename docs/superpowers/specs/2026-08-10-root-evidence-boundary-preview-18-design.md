# Root Evidence Boundary Preview 18 Design

## Goal

Close two residual evidence risks left by Preview 17 on the managed OnePlus
15, China ColorOS 16, KernelSU baseline:

1. A missing boot-identity source must never make an old marker look current
   merely because both sides use the literal `unknown`.
2. The fixed foreground probe must cap `dumpsys activity activities` before
   the result enters a shell variable, instead of checking the limit only
   after an arbitrarily large command output has already been captured.

## Decision

Keep the existing fixed Root command surface and transaction state machines,
but make their evidence boundaries explicitly fail closed:

- `current_guard_boot_id` continues to provide a stable sanitized directory
  value for lock naming, but a new known-identity predicate rejects the
  literal unavailable value before publishing or trusting boot-scoped
  evidence.
- HOME foreground probing invokes a fixed internal shell pipeline that copies
  at most `65537` bytes from the fixed `dumpsys activity activities` command
  before the outer command substitution captures it. The extra byte preserves
  the existing `>65536` distinction, while the captured data is bounded.

The public status schema remains schema 3. No new APK Root route or status
field is required: unavailable boot identity yields `home_foreground=unknown`
and stale marker evidence is not trusted.

## Boot identity contract

`read_boot_id_from()` keeps its source order: the configured boot-id file,
`/proc/stat` `btime`, then fixed `getprop ro.runtime.firstboot`. A source is
usable only when it produces a non-empty value that is not the reserved
literal `unknown` after validation. If all sources fail, the sanitized
directory fallback remains `unknown` for lock compatibility, but
`current_guard_boot_id_is_known()` returns failure.

All boot-scoped marker readers and writers use that predicate before comparing
or publishing identity:

- HOME foreground evidence reports `unknown` and cannot be written.
- Accessibility binding-stall evidence cannot be observed as current or
  published under an unavailable identity.
- HOME/Doze pending state and uninstall comparisons do not treat two
  unavailable identities as the same boot.

Existing lock ownership and PID/start-time checks remain intact so a missing
identity does not create an arbitrary process-control path. Any recovery that
cannot prove its boot scope fails closed and remains retryable on the next
cycle.

## Bounded foreground capture

`read_home_foreground_activity_state()` retains the existing strict parser and
target aliases. Its command boundary changes to a fixed internal helper:

```text
dumpsys activity activities | head -c 65537
```

The helper is invoked only through `run_guard_command`, has no caller-provided
arguments, and remains inside the existing timeout/session cleanup boundary.
The parser rejects output with more than 65536 bytes, while normal output is
never larger than the captured bound. Timeout, pipe failure, `head` failure,
and malformed or truncated records remain `unknown`.

The cap is intentionally one byte above the accepted maximum. This preserves
the current fail-closed behavior for exactly-over-limit output without storing
or parsing unbounded data. A stalled producer is still terminated by the
existing timeout process group cleanup.

## Compatibility and safety

- No arbitrary shell input is accepted from the APK, settings UI, package
  names, components, coordinates, or the device user.
- The only fixed Android read remains `dumpsys activity activities`; all other
  command budgets and the three APK Root paths are unchanged.
- Existing schema 1/2 parsing and Preview 17 release/install ordering remain
  compatible.
- A device whose ColorOS output is larger than the cap or whose boot sources
  are unavailable reports unknown rather than mutating HOME, accessibility,
  Doze, or rollback state based on unverifiable evidence.

## Verification matrix

Host and standalone BusyBox tests will add red/green coverage for:

- every boot-id source failing, including a pre-existing `verified|unknown`
  marker and an `unknown` accessibility stall marker;
- a valid configured source recovering trust after an unavailable source;
- exact 65536-byte foreground output, 65537-byte output, and a producer that
  continues beyond the cap;
- timeout/pipe failure preserving the existing unknown and no-launch behavior;
- the fixed pipeline invocation and no arbitrary command expansion.

The existing full Shell/BusyBox matrix, JVM tests, forced Debug build,
deterministic module package checks, independent review, and fresh GitHub
asset verification remain release gates. The release note must clearly state
that physical ColorOS 16 behavior is still awaiting the user's device.
