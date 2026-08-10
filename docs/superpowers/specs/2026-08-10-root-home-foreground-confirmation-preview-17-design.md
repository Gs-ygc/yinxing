# Root HOME Foreground Confirmation Preview 17 Design

## Goal

Make the fixed Root Guard prove that the Yinxing HOME activity is the
foreground activity after a Root launch. A successful \`am start\` exit status
is only a dispatch acknowledgement; it is not evidence that ColorOS 16
actually resumed the launcher.

## Scope and constraints

- Target remains the managed OnePlus 15 China ColorOS 16 device, user 0, and
  the existing KernelSU module.
- The only new Android operation is the fixed, read-only diagnostic command
  \`dumpsys activity activities\`, executed through the existing bounded
  \`run_guard_command\` wrapper.
- The APK Root allowlist remains the same three fixed, no-argument paths:
  \`status.sh\`, \`action.sh\`, and \`kiosk-home.sh\`. No arbitrary shell,
  arguments, coordinates, process killing, package input, component input, or
  private ColorOS API is introduced.
- Existing schema 2 is retained. The \`home\` field becomes \`owned\` only
  when role ownership, resolver routing, and foreground confirmation all
  agree. Older schema 1/2 APKs remain parseable; no new status line is added.
- Unknown, failed, timed-out, empty, or malformed foreground output is
  fail-closed. It never triggers an additional launch or a route mutation.

## Alternatives considered

1. Keep treating \`am start\` exit code 0 as success. This leaves a
   false-healthy path on OEMs that acknowledge the request but do not resume
   the activity.
2. Add a new public schema field. That would require a protocol migration and
   leave older APKs unable to display the distinction.
3. Add a fixed foreground probe behind the existing \`home\` state and verify
   it after each launch (chosen). This closes the user-visible gap with one
   bounded read-only command while preserving the existing APK contract.

## Foreground parser

\`read_home_foreground_state()\` runs exactly \`dumpsys activity activities\`
and captures output with the existing command-status sentinel pattern. It
scans only explicit \`mResumedActivity:\` and \`mFocusedActivity:\` records. A
record is accepted as the target only when its component token is exactly the
fixed \`com.yinxing.launcher/.feature.home.MainActivity\` (or the equivalent
fully qualified class form). A known record for another component returns
\`other\`. No recognized record, conflicting resumed/focused records, command
failure, extra sentinel data, or malformed component returns \`unknown\`.

The parser does not search arbitrary text for the package name. It never
accepts a target mention in a task history, stack trace, or unrelated activity
record. If both fields are present they must agree; a resumed target plus a
focused non-target is \`unknown\`, not \`owned\`.

## Launch and retry flow

\`launch_home()\` keeps the existing module-active check and fixed
\`am start\` invocation. After dispatch it polls the foreground probe at most
three times with a one-second interval (defaults are sanitized to positive
bounded values).

- \`target\`: log \`home_launch_verified\` and return success.
- \`other\`: log \`home_launch_foreground_other\` and return failure. The Guard
  may make one further launch attempt in a later health cycle, bounded to two
  attempts per process.
- \`unknown\`: log \`home_launch_unverified\` and return failure. The Guard
  does not retry in the same process based only on unknown evidence, preventing
  a diagnostic outage from causing a launch storm.

\`guard.sh\` sets \`HOME_LAUNCHED=1\` only after verified success. It tracks the
bounded attempt count and never exceeds two \`am start\` calls for one process.
\`action.sh\` also returns failure when the foreground postcondition is not
verified, so it records \`last_repair=failed\` and cannot report a false
healthy repair. Existing role/resolver transaction and rollback behavior is
unchanged.

## Status behavior

\`status.sh\` keeps its nine schema-2 lines. When role and resolver identify
Yinxing, it calls the read-only foreground probe:

- target -> \`home=owned\`;
- known other -> \`home=other\`;
- unknown/unavailable -> \`home=unknown\`.

Non-Yinxing role holders keep the existing \`other\`/\`none\` behavior without
a foreground query. The status path performs no writes and remains bounded by
the existing command timeout.

## Safety and lifecycle

- The probe is diagnostic only; it never starts an arbitrary component and
  never changes the HOME role or resolver.
- Foreground confirmation is performed after module-active checks and after
  \`am start\`; if the module is disabled or removed, the result is failure.
- Existing uninstall cleanup, HOME ownership markers, accessibility
  transactions, Doze ownership, and command allowlist semantics remain
  unchanged. The foreground probe is not persisted as mutable state, so there
  is no new marker to restore or delete.

## Test matrix

The host and standalone BusyBox harness will cover:

1. Exact resumed target and exact focused target are accepted.
2. Fully qualified target class is accepted; target text in unrelated output
   is rejected.
3. Known other foreground, missing records, conflicting records, malformed
   output, command failure, and timeout are fail-closed.
4. \`launch_home()\` requires the target postcondition and polls at most three
   times.
5. Guard retries one known-other launch failure but never exceeds two attempts;
   unknown evidence does not create a retry storm.
6. Status reports \`home=owned|other|unknown\` through the existing schema 2.
7. Existing HOME resolver, accessibility, Doze, uninstall, lock, packaging,
   APK, and UI parser regressions remain green in host and BusyBox modes.

Preview 17 is ready for packaging only after shell syntax checks, the complete
shell suite, the Android JVM suite, a forced Debug build, deterministic module
packaging, APK metadata/signature checks, and fresh GitHub asset verification.
