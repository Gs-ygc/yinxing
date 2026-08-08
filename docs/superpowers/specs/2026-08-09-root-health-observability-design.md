# Root Health Observability and Controlled Recovery Design

## Goal

Preview 2 gives a caregiver a trustworthy answer to two questions on the managed OnePlus 15: "Is the KernelSU guard actually healthy?" and "Can I request one bounded repair now?" It does not change the existing AccessibilityService automation backend or expose a general-purpose Root shell.

## Scope and constraints

- Target baseline remains OnePlus 15, China ColorOS 16, KernelSU, already Rooted.
- Root is optional. An unrooted or disabled-module installation keeps the current manual permission flow and remains usable.
- The privileged policy remains fixed to the existing Yinxing package, accessibility component, HOME activity, Doze ownership marker, and module-owned cleanup helper.
- The APK may invoke only two hard-coded module paths: `bin/status.sh` for read-only diagnostics and `action.sh` for one-shot repair.
- Every Root process call has a small output limit and a finite timeout. Timeout, non-zero exit, malformed output, duplicate fields, or unknown values fail closed.
- The status output contains enumerated values only; it never forwards logcat text, shell stderr, paths supplied by the user, or arbitrary command output to the UI.

## Alternatives considered

### Module-only status and release instructions

This is the smallest change, but caregivers still need a terminal or KernelSU manager to distinguish a working guard from a stale one. It does not meet the observability goal in the launcher itself.

### APK fixed-command bridge (selected)

The module emits a strict key/value snapshot and keeps `action.sh` as the single repair entry point. The APK calls those exact paths through `su`, parses only the allowlisted schema, caches the last result for the settings card, and requires an explicit tap before requesting Root. This gives a useful UI while keeping the privilege boundary narrow and updateable.

### Firmware-level privileged service

A system/priv-app or Binder service could avoid repeated `su` calls, but it requires device signing, SELinux policy, and ColorOS image integration that are not available in this repository. It would also make rollback of the APK and Root policy less independent. It remains a later appliance-specific option, not Preview 2 scope.

## Architecture

### Module status contract

`root/kernelsu/yinxing_guard/bin/status.sh` prints exactly one line for each required key:

```text
schema=1
version=<module-version>
module=active|disabled|removing|missing
guard=running|stale|missing|unknown
accessibility=enabled|disabled|missing|unknown
doze=owned|present|absent|unknown
cleanup=ready|missing|invalid
last_repair=ok|failed|unknown
```

The script derives these values from the live secure settings, package state, current-boot lock, Doze list, cleanup helper, and the module-owned `last_repair` marker. It does not print free-form diagnostics. The module writes `last_repair` atomically after each guard/action repair cycle; an unavailable write leaves the value `unknown` rather than claiming success.

The APK derives the overall state instead of trusting a module-supplied aggregate:

- `HEALTHY`: module is active, guard is running, accessibility is enabled, Doze is present/owned, cleanup helper is ready, and the last repair is `ok`.
- `DEGRADED`: the module is active but one or more required checks are stale, disabled, missing, or unknown.
- `MODULE_MISSING`: the command completed with a valid snapshot whose module state is `missing`.
- `ROOT_UNAVAILABLE`: `su` cannot be started, times out, exits non-zero, or returns an invalid snapshot.
- `UNCHECKED`: no explicit health query has been made in this Activity instance.

### APK bridge

`RootCommandRunner` owns process execution and exposes only a `RootCommand` enum (`STATUS`, `RECOVER`). `SuRootCommandRunner` constructs `ProcessBuilder("su", "-c", fixedPath)`; it never accepts a caller-provided command string. It merges stderr into a bounded output stream, waits no longer than three seconds, destroys timed-out processes, and returns a structured result.

`RootHealthRepository` runs the blocking bridge on `Dispatchers.IO`, maps failures to `ROOT_UNAVAILABLE`, and parses valid snapshots with a pure parser. `recoverAndQuery()` invokes the fixed action, then performs a fresh status query; the UI reports both the action result and the post-repair state.

### Settings experience

The settings overview gains a `Root 专机状态` card. It shows `未检查`, `Root 不可用`, `模块未安装`, `需要处理`, or `运行正常` using the same existing badge treatment as other hub cards. Opening the card is the explicit consent point for the first `su` request. The sheet contains:

1. A read-only health summary with the enumerated component states.
2. A `立即修复并复查` action that runs the fixed module action once and then refreshes the summary.
3. A short rollback/safety note explaining that the operation does not alter `/system` and that disabling the KernelSU module restores the existing manual path.

No health query runs during launcher startup or ordinary settings-card refresh, so Root authorization UI cannot surprise the older user.

## Error handling and rollback

- Missing `su`, denied KernelSU permission, disabled/missing module, timeout, or malformed output is rendered as a non-blocking unavailable/degraded state.
- Recovery failure never retries in a tight loop. The existing module guard remains responsible for periodic retries.
- The APK does not write secure settings itself; it only requests the already-reviewed module action.
- The module status marker and cleanup helper use atomic replacement and preserve prior state on write failure.
- Removing or disabling the module leaves the APK's existing manual accessibility/settings actions intact.

## Testing strategy

- Extend `tools/test-yinxing-guard.sh` with behavior tests for healthy, stale, and missing-module status output; run under host `sh` and standalone BusyBox `ash`.
- Add JVM tests for strict parser acceptance/rejection, overall-state derivation, command-result mapping, and recovery-result handling using a fake command runner. No test relies on a mock's call count as the behavior assertion.
- Add a settings smoke test that the Root hub card exists and remains non-empty without Root.
- Run `sh -n`, `bash -n`, and BusyBox `ash -n` for every module script, `git diff --check`, the full module suite, `:app:testDebugUnitTest`, and a forced `:app:assembleDebug`.
- Package and verify the Preview 2 module ZIP, APK metadata, checksums, downloaded release assets, and rollback notes before publishing the prerelease tag.

## Deferred work

Coordinate/UIAutomator click fallback, system/priv-app placement, automatic Root authorization prompts, and full elderly-desktop redesign remain separate iterations. Preview 2 exists to establish an observable, testable foundation before those higher-risk changes.
