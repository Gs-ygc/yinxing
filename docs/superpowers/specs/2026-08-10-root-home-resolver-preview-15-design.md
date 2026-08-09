# Root HOME Resolver Confirmation Preview 15 Design

## Goal

Make Root health and HOME recovery verify the Activity that actually resolves
the user-0 `MAIN` + `HOME` intent, not only the `android.app.role.HOME`
holder. This closes the remaining reliability gap where an OEM resolver can
route the Home key to a different launcher while the role database still lists
Yinxing.

## Scope and constraints

- Target remains the managed OnePlus 15 China ColorOS 16 device, user 0, and
  the existing KernelSU module.
- The only new Android operation is the fixed read-only command
  `cmd package resolve-activity --brief --components --user 0 -a
  android.intent.action.MAIN -c android.intent.category.HOME`.
- The APK Root allowlist, command timeout boundary, package/component constants,
  and transaction lock remain unchanged. No arbitrary shell, arguments,
  coordinates, process selection, or private ColorOS API is introduced.
- Unknown, malformed, multi-line, or timed-out resolver output is treated as
  unknown. It never becomes evidence for a takeover or rollback target.
- The existing schema-2 `home` field remains the public contract. `home=owned`
  now means both the role holder and the resolved HOME component are Yinxing.
  A role owned by Yinxing with a known different/empty resolver is degraded;
  an unrecognized resolver is unknown and remains fail-closed.

## Alternatives considered

1. Keep role-only observation. This is smallest, but cannot detect a resolver
   mismatch and can report a false healthy state.
2. Add a diagnostic export surface. This helps later feedback but does not
   repair a wrong Home route.
3. Add the fixed resolver probe to the existing HOME state and transaction
   confirmation (chosen). It directly validates the user-visible behavior,
   reuses the current strict parser and lock, and keeps the change bounded.

## Design

### Resolver parser

`read_home_resolved_component` runs the fixed command through
`run_guard_command`. It accepts exactly one terminated line. `No activity found`
is the explicit no-resolver result. A component line must contain one `/`, a
valid Android package prefix, and a non-empty class token; output with a second
line, a separator, a sentinel alias, or an invalid package is rejected.
The target is recognized in both AOSP short form
`com.yinxing.launcher/.feature.home.MainActivity` and the equivalent fully
qualified class form. The helper returns `none`, `target`, or `other`; command
failure and malformed evidence return failure.

`home_role_state` first reads the role holder. For another package or no holder
it preserves the existing `other`/`none` result without an unnecessary resolver
query. When Yinxing is the role holder it requires a successful resolver probe:
`target` becomes `owned`, `other` becomes `other`, and a failed probe becomes
`unknown`.

### Recovery and rollback

When Yinxing already owns the role, a known non-target resolver is repaired with
the existing fixed `set-home-activity` command, then both role and resolver are
re-read. No prior-holder marker is created because the module did not acquire
the role in this transaction. Unknown resolver evidence leaves state unchanged
and records a failed repair for the next bounded Guard cycle.

When the module is taking over another/no holder, the existing durable pending
and owned markers are unchanged. After `set-home-activity`, confirmation now
requires the role holder to be Yinxing and the resolver to be the target. A
failed or unknown resolver confirmation retains the pending evidence and helper
for retry; it never launches HOME as if ownership were confirmed.

The standalone uninstall helper uses the same strict resolver read after a
restore. Explicitly known non-target/none output retains rollback evidence for
retry. An unavailable or malformed resolver is conservative: the role restore
itself is not undone, but evidence remains so a later boot can verify it before
cleanup completes.

### Status and UI

`status.sh` continues emitting exactly nine schema-2 lines. Only the semantics
of `home` change as described above, so older Preview 14 APKs remain parseable.
The existing Root health sheet and summary need no new field; a resolver
mismatch naturally renders the existing degraded/unknown HOME value.

## Testing

- Extend the shell fixture with a deterministic HOME resolver component and
  fixed-command failure, stall, malformed, no-activity, and mismatch controls.
- RED tests cover strict component parsing, healthy target routing, known route
  mismatch repair, unknown/malformed/timeout safety, post-set confirmation, and
  retained rollback evidence.
- Preserve all existing role, accessibility, Doze, lock, uninstall, BusyBox,
  and deterministic packaging regressions.
- Run shell syntax and fixed-command scans, host plus recursive BusyBox suites,
  the full Android unit-test suite and forced Debug build, deterministic module
  packaging, APK metadata/signature checks, and remote release byte/checksum
  verification.

## Acceptance criteria

1. A role-owned Yinxing installation reports `home=owned` only when the fixed
   HOME intent resolves to the Yinxing activity.
2. A known resolver mismatch is repaired without creating a false rollback
   marker; an unknown/malformed/timeout probe performs no speculative mutation.
3. A takeover is not marked `owned` and HOME is not launched until both role
   and resolver confirmation succeed.
4. Uninstall rollback remains conditional, retryable, and caregiver-choice
   preserving.
5. Preview 15 is published as a rollback-capable Debug APK plus KernelSU ZIP
   and checksums, with no claim of physical-device validation before OnePlus 15
   feedback is supplied.
