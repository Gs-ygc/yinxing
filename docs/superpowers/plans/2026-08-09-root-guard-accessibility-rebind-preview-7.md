# Root Guard Accessibility Binding Recovery Preview 7 Implementation Plan

> For agentic workers: execute this plan task by task, keeping the test and release evidence with the implementation.

## Goal

Detect when Yinxing remains enabled in Android's accessibility settings but its service is explicitly listed as crashed, then recover only Yinxing's binding while preserving all other services. Publish a reproducible Debug APK and KernelSU module as Preview 7.

## Architecture and constraints

- `root/kernelsu/yinxing_guard/bin/common.sh` owns the Root-only dump parser, colon-list helpers, and recovery side effect.
- `status.sh` keeps the existing eight-line schema and reports `accessibility=stale` only for an explicit crashed target.
- The APK accepts `stale` as an allowlisted health value and maps it to the existing degraded state.
- No arbitrary shell input, process killing, coordinate taps, private ColorOS settings, or changes to unrelated accessibility components.
- All edits remain isolated on branch `feat/root-guard-accessibility-rebind-preview-7` until verification is complete.

## Task 1: Add failing shell and parser coverage

1. Extend `tools/test-yinxing-guard.sh` with a fake `dumpsys accessibility` command and reset its fixture files between tests.
2. Add a crashed-service repair test proving `talkback:other` survives, Yinxing is removed and restored, `accessibility_enabled=1` is reasserted, and the rebound event is logged.
3. Add bound/binding coverage proving healthy or transient states are left untouched.
4. Add status coverage for `accessibility=stale` and a failed/empty diagnostic proving settings are not toggled when dump evidence is unavailable.
5. Register the new tests in focused and full dispatch paths.
6. Run Host and standalone BusyBox focused suites; the new crashed-service test must fail against the Preview 6 implementation.
7. Commit the red tests as `test: cover crashed accessibility service recovery`.

## Task 2: Implement binding-state parsing and targeted recovery

1. Add `accessibility_service_binding_state` to parse only `Bound services`, `Binding services`, and `Crashed services`, returning `bound`, `binding`, `crashed`, or `unknown`.
2. Add an exact colon-aware `remove_accessibility_service` helper.
3. Invoke the diagnostic after existing accessibility repair checks; on `crashed` only, remove the target, wait one second, restore the original list, reassert the enabled flag, and log `accessibility_service_rebound`.
4. Keep diagnostic failures and unrecognized vendor output non-fatal and side-effect free.
5. Make `status.sh` emit `stale` for an explicit crash while preserving `enabled` for bound, binding, and unknown states.
6. Run host, BusyBox, shell syntax, and focused tests; commit as `fix: rebind crashed accessibility service`.

## Task 3: Update APK/module versions and parser tests

1. Add `stale` to `RootHealthSnapshot`'s allowlist and add a JVM test proving it derives `DEGRADED`.
2. Bump APK to version code 23/name `1.10.0-root-preview.7` and module metadata to version code 7/name `1.10.0-root-preview.7`.
3. Update module cleanup/version assertions and run targeted JVM plus package tests.
4. Commit as `chore: bump root accessibility recovery preview 7`.

## Task 4: Build, package, and document the release

1. Run the full Host and BusyBox module suites, shell syntax checks, and the complete Android Debug unit-test plus assemble task with the configured Gradle proxy/cache.
2. Package `yinxing-1.10.0-root-preview.7-debug.apk` and `yinxing-guard-1.10.0-root-preview.7.zip`; generate basename-only `SHA256SUMS.txt`.
3. Verify APK metadata/signature, module layout/modes/timestamps, ZIP integrity, and checksum contents.
4. Record commands, timings, test counts, hashes, install order, rollback, and known Debug-build caveats in `docs/release/yinxing-root-preview-7.md`.
5. Commit release documentation, merge the feature branch into `main`, push `main`, create and push tag `v1.10.0-root-preview.7`, and publish a prerelease with `gh`.

## Task 5: Verify the remote release

1. Download the published assets into a fresh temporary directory.
2. Re-run checksum, ZIP, APK metadata/signature, and module layout checks on the downloaded files.
3. Verify the GitHub release state, remote branch, tag, and dereferenced tag commit.
4. Update `.planning/task_plan.md`, `.planning/progress.md`, and `.planning/findings.md` with the Preview 7 evidence while preserving the user's untracked planning files.

## Task 6: Device feedback loop

Leave the goal active after publication. The next iteration starts from the user's OnePlus 15 / ColorOS 16 / KernelSU result and prioritizes any observed binding, boot, battery, or automation failure.

## Self-review checklist

- No TODO/TBD/placeholders remain in this plan.
- Every implementation step has a corresponding test or inspection command.
- The release cannot be called complete until the local build and fresh remote download both verify successfully.
