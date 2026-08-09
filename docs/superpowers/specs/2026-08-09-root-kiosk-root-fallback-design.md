# Root Kiosk Home Fallback Design

## Context

Preview 8 protects the KernelSU owner lock and repairs the fixed Yinxing accessibility component. The APK's Kiosk guard already tries an explicit activity launch and, on Android 14+, a background-activity-allowed `PendingIntent`. ColorOS can still reject or delay both paths while a system launcher remains the visible window. A fixed rooted appliance can provide a more reliable final handoff without granting the APK arbitrary shell access.

## Goal

When Kiosk mode is explicitly enabled, no automation session is active, and the system launcher is still observed after the normal foreground recovery attempts, issue one fixed Root command that starts Yinxing's home activity. The fallback must be optional, cancellable, bounded, and harmless on devices without Root or without the KernelSU module.

## Non-goals

- Do not change the user's default launcher or device role configuration.
- Do not use coordinates, UIAutomator, private ColorOS APIs, process killing, or arbitrary command strings.
- Do not run the fallback during an active WeChat automation session, when Kiosk mode is disabled, or after a user-app window becomes the latest observed window.
- Do not add periodic forced foreground launches to the KernelSU supervisor.

## Design

### Fixed Root command

Add `RootCommand.KIOSK_HOME`, mapped to the literal path `/data/adb/modules/yinxing_guard/bin/kiosk-home.sh`. The module script checks that the module directory is active, sources the existing shared helpers, and calls the existing parameterless `launch_home()` function. It accepts no arguments and emits no user-controlled data. The packager includes it with the same executable permissions and normalized timestamps as the other module scripts.

### APK bridge

Add a small `RootHomeLauncher` interface and `SuRootHomeLauncher` implementation. It reuses `SuRootCommandRunner` with a short fixed timeout and executes only `KIOSK_HOME` through `runInterruptible(Dispatchers.IO)`, so the service main thread never blocks and cancellation can terminate a stuck `su` process. A non-zero exit, timeout, output overflow, missing `su`, or missing module is simply a failed fallback; existing Android recovery remains the only required path.

### Kiosk lifecycle

`KioskLauncherGuard` records the latest window package for every window-state event. Its delayed confirmation uses the active accessibility root when available and otherwise the latest observed package, preventing a stale launcher trigger from winning after the user has opened another app. After the normal launch and one settle retry, a generation-bound Root fallback job waits a short additional settle window, rechecks Kiosk mode, active-session state, generation, and the latest/active package, then calls `RootHomeLauncher` only when a known system launcher is still visible. Shutdown, reconnect, user-app events, or a new launcher event cancel the pending fallback.

The command is attempted at most once per recovery generation. A successful command does not create another retry loop; the resulting window-state event will start a fresh generation if the launcher remains visible. This bounds Root prompts and prevents repeated `am start` storms.

## Error handling and security

All eligibility checks fail closed. If the active package cannot be established, the Root fallback is skipped. Root failure is logged only through the existing debug path and never changes the manual launcher or accessibility flow. The fixed command path is covered by the existing Root runner allowlist tests, and the module script cannot receive an arbitrary component or argument.

## Verification

- Add a module harness test for `kiosk-home.sh`: active module calls the fixed HOME component, disabled/removing/missing module does not call `am start`, and the package contains the script at archive root.
- Add JVM tests for the fixed command path, Root launcher success/failure, and cancellation-safe execution.
- Extend `KioskLauncherGuardTest` with latest-window suppression, Root fallback after a lingering system launcher, cancellation on shutdown, and no fallback for an active session/user app.
- Run host and BusyBox module suites, POSIX/Bash syntax checks, focused and full Android unit tests, and a forced Debug build. Publish APK, module ZIP, checksums, and rollback notes as Preview 9.
