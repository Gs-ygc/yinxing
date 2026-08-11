# Preview 27 Root Path Recovery Design

## Context

Preview 26 did not restore the managed OnePlus 15 / China ColorOS 16 /
KernelSU device's app-initiated Root path. The caregiver panel still reports
either that `/system/bin/su` is invisible or that a command exits 126 with
permission denied. These are separate boundaries:

- an invisible `su` entry means Android cannot start the fixed KernelSU
  compatibility executable for the Yinxing app UID;
- exit 126 means `su` did start, but a later executable boundary was denied.

The released implementation throws away the `su` start exception text and
the failed command's bounded output before rendering the caregiver summary.
It also passes a module script path alone to `su -c`, which makes KernelSU's
default `/system/bin/sh` execute that file and unnecessarily requires the
module file itself to be executable.

## Goal

Restore the three app-initiated, allowlisted Root actions when module scripts
are readable but not executable, and make every remaining failure identify
its actual Root boundary without combining distinct causes.

The affected actions are:

1. Root health status;
2. explicit one-shot Root recovery;
3. managed HOME foreground recovery.

## Non-goals

- Do not discover `su` through `PATH` or try alternate Root providers.
- Do not bypass KernelSU's explicit per-UID Root authorization.
- Do not add an arbitrary command executor, user-provided shell text, or a
  fourth Root command.
- Do not add BusyBox use, module scripts, a daemon, service, receiver, timer,
  retry loop, polling, network access, wakelock, or power exemption.
- Do not change boot Guard behavior, Accessibility repair policy, HOME policy,
  contact behavior, calls, WeChat automation, or elderly-facing screens.
- Do not expose stack traces, secrets, environment variables, or unbounded
  process output.

## Considered Approaches

### Selected: fixed system-shell interpretation plus bounded evidence

Keep `/system/bin/su` as the only KernelSU entry. For each existing enum value,
pass one fixed command string to `su -c`:

```text
/system/bin/sh /data/adb/modules/yinxing_guard/bin/status.sh
/system/bin/sh /data/adb/modules/yinxing_guard/action.sh
/system/bin/sh /data/adb/modules/yinxing_guard/bin/kiosk-home.sh
```

This requires the script to be readable by the Root profile but does not
require the script file to be executable. It preserves the existing command
allowlist and timeout/output limits. Carry a bounded diagnostic record through
the repository to the existing caregiver Root sheet.

### Rejected: diagnostics only

Keeping direct script execution and only showing better errors would explain
126 but would retain the unnecessary executable-bit failure boundary. It does
not meet the recovery goal.

### Rejected: PATH search or multiple `su` locations

Trying `su`, `/system/xbin/su`, or module binaries would hide the KernelSU
authorization state, create provider ambiguity, and still could not authorize
an unapproved app UID. Current KernelSU uses `/system/bin/su`; that stays fixed.

### Deferred: privileged Binder or init bridge

A module-owned privileged bridge could remove the APK's direct `su`
dependency, but it introduces a new long-lived cross-SELinux interface and a
larger security/power/test surface. It is not justified until the shell-read
path and exact device evidence are tested.

## Command Contract

`RootCommand` continues to be an enum with only `STATUS`, `RECOVER`, and
`KIOSK_HOME`. Each value owns an absolute module script path and derives an
immutable `shellCommand` using the constant `/system/bin/sh`.

`SuRootCommandRunner` starts exactly:

```kotlin
ProcessBuilder(KERNEL_SU_EXECUTABLE, "-c", command.shellCommand)
```

No interpolation accepts external data. Paths contain no spaces or shell
metacharacters. Existing per-command timeouts remain 3 seconds, 20 seconds,
and 15 seconds. Combined stdout/stderr remains limited to 16 KiB, and existing
process termination behavior remains unchanged.

The module is unchanged. Preview 27 reuses the exact Preview 26 module asset;
the APK fix must also work when the installed fixed scripts are `0644`, because
Root's `/system/bin/sh` reads them instead of executing them.

## Diagnostic Model

Add a small immutable `RootFailureEvidence` value to the existing Root model.
It contains only:

- `command`: the attempted `RootCommand`;
- `stage`: `SU_START`, `COMMAND_RUN`, `STATUS_PARSE`, or `RUNNER_EXCEPTION`;
- `invocation`: the exact fixed executable/arguments rendered from constants;
- `exitCode`: a non-negative process exit code when one exists;
- `detail`: bounded process output or exception class/message.

The runner creates evidence for start failures, timeouts, output overflow, and
nonzero exits. `RootHealthRepository` preserves it when producing an
unavailable snapshot or a failed recovery result. A successful process with
an invalid health schema creates `STATUS_PARSE` evidence containing the
bounded invalid output. Repository exceptions create `RUNNER_EXCEPTION`
evidence rather than an empty `UNKNOWN` result.

Evidence detail is normalized before storage:

- keep line breaks and tabs;
- replace other control characters with spaces;
- trim surrounding whitespace;
- cap the rendered detail at 1,024 characters, preserving both the beginning
  and end with an explicit omitted-character marker;
- use the exception simple class name when the platform provides no message.

This model is diagnostic data, not a new classification source. Existing
specific `RootFailureReason` badges remain stable, while the exact evidence is
shown below the human-readable explanation.

## Failure Classification

The existing distinctions remain fail-closed:

- `SU_NOT_FOUND`: starting `/system/bin/su` returns ENOENT/error 2;
- `SU_EXECUTION_BLOCKED`: starting it returns EACCES/error 13 or a
  `SecurityException`;
- `SU_START_FAILED`: another start failure;
- `SCRIPT_NOT_FOUND` / `SCRIPT_UNAVAILABLE`: the fixed system shell cannot
  read the selected module script;
- `SCRIPT_EXECUTION_BLOCKED`: the fixed system shell reports permission or
  policy denial for the selected module script;
- other permission text: `COMMAND_PERMISSION_DENIED`;
- timeout, output overflow, nonzero command, invalid schema, and unknown remain
  separate.

Script-path classification accepts the common Android shell prefixes and
`can't open` / `can't execute` wording only when the same line also names the
selected fixed script path. A dependency failure inside a running script must
not be relabeled as a missing or blocked top-level script.

## Caregiver UI

The existing Root sheet remains the sole visible entry. Healthy summaries do
not become more technical. On failure, the status summary contains:

```text
<existing human explanation>

诊断阶段：启动 su | 执行状态脚本 | 解析状态 | 执行器异常
应用 UID：<android.os.Process.myUid()>
固定命令：<exact fixed invocation>
退出码：<number or “未启动”>
系统原文：<bounded detail or “无输出”>
```

Recovery failure Toasts stay concise; the fresh status entry retains its own
evidence. The current sheet also retains the latest recovery-action evidence
and renders it persistently in the recovery entry after the action finishes.
Therefore, if the recovery action fails but the subsequent status query
succeeds, the healthy status card remains truthful while the recovery row
still displays that action's stage, command, exit code, and original output.
Closing the sheet may discard this operation-local evidence; reopening always
runs a new explicit status query.

No diagnostic text appears on the elderly HOME, phone, or video screens. The
Root sheet remains an explicit caregiver action, so the change adds no startup
latency or idle work.

## Testing

### Runner tests

- RED: a readable non-executable fake module script fails under the released
  direct-path command but succeeds when the fake `su` receives the fixed
  `/system/bin/sh <path>` command.
- Assert all three enum values produce only their exact fixed shell command.
- Assert a missing/non-executable `su` retains its start exception evidence.
- Assert exit 126 retains command, stage, exact exit code, and raw bounded
  permission output.
- Assert common Android shell permission formats classify the selected script
  while a missing dependency inside it stays a generic command failure.
- Retain timeout, output-overflow, and process cleanup tests.

### Repository/model tests

- Nonzero status and invalid schema retain evidence in `RootHealthSnapshot`.
- Failed recovery retains action evidence and still performs one fresh status
  read.
- Thrown runner exceptions retain class/message as `RUNNER_EXCEPTION`.
- Detail normalization preserves useful first/last text and never exceeds
  1,024 characters.

### UI tests

- Every failure summary keeps its current reason-specific explanation.
- A `su` start failure displays UID, fixed command, `未启动`, and original
  ENOENT/EACCES text.
- Exit 126 displays the selected script, 126, and original permission line.
- A failed recovery followed by healthy status keeps the healthy status entry
  and displays the action evidence in the recovery entry until dismissal or a
  later recovery attempt.
- Missing detail renders `无输出`, never a generic replacement for reason/code.
- Root remains unchecked until the caregiver explicitly opens its sheet.

### Release gate

- Focused Root JVM/Robolectric tests pass.
- Complete Android unit suite and Debug APK assembly pass from final source.
- Complete Root Guard host and standalone BusyBox suites pass even though the
  module source is unchanged.
- APK metadata, signature, checksums, release notes, tag, and fresh GitHub
  downloads are verified.
- Device behavior is reported as unverified until the OnePlus 15 runs the new
  APK; the release requests the exact displayed diagnostic if Root still fails.

## Acceptance

Preview 27 is locally acceptable when all of the following are proved:

1. all three app Root actions use fixed `/system/bin/sh` interpretation and no
   script executable bit;
2. the Root command allowlist and bounds are unchanged;
3. every unavailable snapshot carries its specific reason plus bounded exact
   evidence when the platform supplied any;
4. the caregiver sheet displays the failing stage, UID, command, exit status,
   and system text without collapsing them;
5. no background, elderly UI, module behavior, or idle-power path changes;
6. the release is rollback-capable and does not claim device success before
   direct OnePlus 15 confirmation.
