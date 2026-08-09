# Root Command Timeout Budget Preview 11 Design

## Context

Preview 10 added bounded confirmation after Root Guard rebinds the fixed
Yinxing accessibility service. The persistent-crash path now intentionally
waits one second between removing and restoring the service, then waits four
more one-second intervals across five confirmation polls. Android package,
settings, diagnostic, Doze, app-op, and HOME commands add execution overhead.

The APK still constructs `RootHealthRepository(SuRootCommandRunner())`, whose
single default timeout is 3,000 milliseconds for every fixed Root command.
Consequently, the settings panel can terminate `action.sh` before Preview 10
finishes confirmation or records `last_repair`. This is a cross-layer timeout
contract defect, not a reason to shorten the recovery checks.

## Selected Approach

Bind a finite timeout budget to each existing `RootCommand` alongside its
literal allowlisted path:

| Command | Fixed path | Timeout |
| --- | --- | ---: |
| `STATUS` | `/data/adb/modules/yinxing_guard/bin/status.sh` | 3,000 ms |
| `RECOVER` | `/data/adb/modules/yinxing_guard/action.sh` | 12,000 ms |
| `KIOSK_HOME` | `/data/adb/modules/yinxing_guard/bin/kiosk-home.sh` | 1,200 ms |

Twelve seconds gives recovery more than twice its five seconds of intentional
default waits while retaining a finite bound for slow or stuck ColorOS shell
commands. Status remains fast because it is read-only and interactive. Kiosk
HOME remains tightly bounded because it runs in the delayed foreground-return
path and must not stall accessibility automation.

Two alternatives are rejected:

1. A global 12-second default would make status checks and Kiosk recovery wait
   too long on missing, denied, or stuck Root.
2. Reducing confirmation attempts or delays to fit the old three-second limit
   would undo Preview 10's recovery reliability.

The user's standing autonomous-design delegation is approval to proceed with
the selected approach without another interaction gate.

## Code Shape

`RootCommand` becomes an enum with constructor properties `shellPath` and
`timeoutMillis`. No caller can provide a path or argument; adding a timeout
property does not broaden execution authority.

`SuRootCommandRunner` changes its constructor timeout from a required default
value to an optional uniform override:

```kotlin
private val timeoutMillis: Long? = null
```

Production calls resolve the timeout as:

```kotlin
val commandTimeoutMillis = timeoutMillis ?: command.timeoutMillis
```

The existing positive-value validation applies when an override is supplied.
Tests retain short deterministic overrides. `SuRootHomeLauncher` uses a plain
`SuRootCommandRunner()` so the Kiosk budget has one authoritative definition in
the enum instead of a second constant.

The process lifecycle, output bound, interruption behavior, graceful/forced
termination, fixed `su -c <literal path>` argument list, and merged stderr
behavior remain unchanged.

## Data Flow And Failure Semantics

1. Settings recovery calls `RootHealthRepository.recoverAndQuery()`.
2. The repository runs only `RootCommand.RECOVER`.
3. The runner launches `su -c` with the enum's literal action path and waits up
   to 12 seconds.
4. A normal action result is evaluated exactly as before; timeout, nonzero
   exit, output overflow, process-start failure, or cancellation still fail
   closed.
5. The repository then runs the fixed status command with its independent
   three-second budget and parses the strict eight-line snapshot.

No background retry is added to the APK. KernelSU's module-local Guard remains
the automatic recovery owner, and its next health cycle remains the fallback
after a failed manual action.

## Test Strategy

`RootCommandRunnerTest` adds:

- exact assertions for all three literal paths and timeout budgets;
- a real fake-`su` recovery that sleeps four seconds, proving the production
  recovery budget outlives the former three-second cutoff;
- preservation of the existing short override timeout test, output bound, and
  three-command routing coverage.

The focused Root JVM suite must be red before implementation and green after
it. The complete Android unit suite, forced Debug APK build, host plus
standalone BusyBox module suite, shell syntax checks, deterministic module
packaging, APK metadata/signature checks, and fresh GitHub asset download checks
remain release gates.

## Release Scope

Preview 11 versions are APK `versionCode=27`, module `versionCode=11`, and
`versionName=1.10.0-root-preview.11`. The release includes the Debug APK,
KernelSU module ZIP, basename-only SHA-256 file, install order, Preview 10
rollback instructions, exact timings, and an explicit statement that no
OnePlus 15 was connected locally.

Out of scope: new Root commands or arguments, arbitrary shell input, process
killing policy, coordinate clicking, private ColorOS APIs, broader keepalive
settings, accessibility parser changes, Kiosk state-machine changes, and
elderly-launcher visual redesign.
