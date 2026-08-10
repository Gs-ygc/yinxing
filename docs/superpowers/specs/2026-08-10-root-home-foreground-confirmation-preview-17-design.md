# Root HOME Foreground Confirmation Preview 17 Design

## Goal

Make the fixed Root Guard prove that the Yinxing HOME activity reached the
foreground after a Root launch. An `am start` exit status is only a dispatch
acknowledgement; it is not evidence that ColorOS 16 resumed the launcher.

## Decision

The Settings screen itself is an activity in the Yinxing app. Sampling the
live foreground from `status.sh` would therefore incorrectly report a healthy
user who opens Settings, WeChat, or another app as a failed launcher. Preview
17 instead records a boot-scoped postcondition at the time a Root launch is
performed:

- `home=owned|other|none|unknown` remains the HOME role and resolver result.
- `home_foreground=verified|unverified|unknown` records the most recent Root
  launch result for the current boot only.
- `status.sh` reads that durable evidence but never invokes an activity dump,
  so status remains observational and is not distorted by its caller.

The public status protocol is schema 3. Schema 1 and schema 2 remain
parseable by the new APK as degraded legacy data; only schema 3 with both
`home=owned` and `home_foreground=verified` can be healthy.

## Scope and constraints

- Target: managed OnePlus 15, China ColorOS 16, KernelSU, Root, Android user
  0.
- The only new Android operation is the fixed read-only command `dumpsys
  activity activities`, invoked through the existing bounded
  `run_guard_command` wrapper.
- The APK Root allowlist remains exactly `status.sh`, `action.sh`, and
  `kiosk-home.sh`, all fixed no-argument paths.
- No arbitrary shell, coordinates, package names, components, process kills,
  or private ColorOS API is exposed.

## Foreground confirmation

`read_home_foreground_activity_state()` accepts only explicit
`mResumedActivity:` and `mFocusedActivity:` records. Each recognized record
must contain exactly one syntactically valid Android component token. The only
accepted target aliases are:

- `com.yinxing.launcher/.feature.home.MainActivity`
- `com.yinxing.launcher/com.yinxing.launcher.feature.home.MainActivity`

Both records must agree after target normalization. Missing records, malformed
tokens, duplicate fields, conflict, command failure, timeout, oversized
output, and unrelated target text all become `unknown`. A known valid other
component becomes `other`.

`launch_home()` writes `unverified|<boot-id>` before the fixed `am start`,
then confirms the activity up to three times with a one-second default delay.
It writes `verified|<boot-id>` only after the target postcondition succeeds.
The marker is a regular non-symlink file, exact single-line canonical data,
mode 0600, atomically published, read back, and fsynced through the existing
Root command wrapper. Existing malformed or nonregular evidence is never
overwritten.

## Failure behavior

- `target`: `launch_home()` succeeds and the evidence becomes `verified`.
- `other`: `launch_home()` returns a distinct failure. A Guard process may
  make one later launch attempt, with at most two starts per process.
- `unknown`: `launch_home()` returns a distinct failure and blocks more HOME
  starts in that Guard process. A broken diagnostic cannot create a launch
  storm.
- `action.sh` records `last_repair=ok` only after confirmed launch success.
  Any launch evidence failure records `last_repair=failed`.

The Root bridge budgets are 3 seconds for status, 15 seconds for the bounded
Kiosk launch, and 20 seconds for explicit full recovery. These are finite
bounds, not background execution grants.

## Lifecycle

The foreground evidence has no rollback meaning. Both direct uninstall and
the deferred standalone cleanup remove its file and temporary publications
without changing the HOME role, resolver, Doze ownership, or accessibility
settings. Existing HOME rollback evidence remains independent.

## Verification matrix

The host and standalone BusyBox suite covers strict activity parsing,
bounded dumpsys timeout, atomic and boot-scoped evidence, verified and
unverified launch results, Guard retry limits, action status correctness,
status non-probing behavior, and evidence cleanup. JVM tests cover schema 3,
legacy parsing, healthy-state derivation, Settings summaries, and the new
Kiosk timeout budget. Release verification additionally runs full shell,
JVM, Debug build, deterministic module packaging, APK signature checks, and
fresh GitHub asset download checks.
