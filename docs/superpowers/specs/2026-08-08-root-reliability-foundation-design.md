# Root Reliability Foundation Design

## Context

Yinxing is an Android launcher for an elderly user. Its WeChat automation already relies on an `AccessibilityService` for UI events, semantic node trees, gestures, and global actions. The first managed-device target is a rooted China OnePlus 15 running ColorOS 16 with KernelSU.

The product direction includes four related but independently testable areas:

1. Root-backed availability and boot recovery.
2. Automatic recovery of Yinxing's accessibility service.
3. More reliable UI automation.
4. A better elderly launcher experience.

This design covers only the first release slice: Root-backed availability and automatic accessibility recovery. Automation behavior and launcher visual changes remain unchanged so failures can be attributed to the new foundation.

## Constraints

- The first target is a user-controlled OnePlus 15 with China ColorOS 16 and KernelSU.
- Reliability is more important than generic Android or app-store compatibility.
- The APK must remain usable without Root and must not crash or block the launcher when the KernelSU module is missing or disabled.
- `AccessibilityService` remains the primary automation backend. Root does not replace its event and node-tree contract.
- Existing enabled accessibility services must be preserved when Yinxing is enabled or repaired.
- Privileged operations must be fixed and reviewable. The app will not expose arbitrary shell execution or a general Root RPC surface.
- The first release must be recoverable by disabling or uninstalling the KernelSU module.
- No SELinux policy relaxation, system-security disabling, coordinate-click daemon, or hidden remote-control interface is in scope.

## Approaches Considered

### 1. Hybrid KernelSU Module and Updateable APK (Recommended)

A small KernelSU module owns boot-time provisioning and a low-frequency health loop. The normal APK keeps all launcher and accessibility business logic. The module repairs only an allowlisted set of device state: package/component enabled state, accessibility registration, Doze whitelist, background app-ops where supported, and launcher startup after boot.

This gives the strongest recovery behavior while keeping business releases easy to install and roll back. The module is device-specific, but the APK remains independently testable and does not become a monolithic privileged process.

### 2. Privileged/System APK Only

Mount the APK under `priv-app`, grant privileged permissions, and rely on Android boot receivers and services. This can reduce Root-shell calls, but it couples every app update to the system image/module mount and does not by itself defeat every ColorOS process-management path. It also increases signing, permission allowlist, and SELinux complexity.

### 3. Ordinary APK Calling `su` Directly

Let the app run fixed `su -c` repairs at startup or from Settings. This is simpler to package, but it depends on the app process already being alive and on KernelSU approval being available at the moment recovery is needed. It is useful as a later caregiver repair action, not as the primary watchdog.

## Recommended Architecture

### Main APK

The existing `com.yinxing.launcher` APK remains the HOME app and owns:

- Elderly launcher UI and caregiver settings.
- The existing `SelectToSpeakService` accessibility implementation.
- WeChat semantic recognition and actions.
- Existing boot/package-replaced recovery behavior.

The first release changes only version metadata and any minimal diagnostics needed to identify the Root-foundation build. It does not embed a generic Root executor.

### KernelSU Module

A repository-owned module named `yinxing_guard` contains:

- `module.prop`: stable module identity and version.
- `service.sh`: KernelSU late-start entry point.
- `action.sh`: caregiver-triggered one-shot repair from KernelSU Manager.
- `uninstall.sh`: removes only module-owned runtime state and the Doze whitelist entry.
- `bin/common.sh`: constants and deterministic state-repair functions.
- `bin/guard.sh`: boot wait, initial repair, and low-frequency health loop.

The module uses KernelSU's own BusyBox shell environment. It does not modify `/system` in the first release, so no metamodule is required.

### Privileged Policy

The module may perform only these operations for `com.yinxing.launcher` and its accessibility component:

1. Verify that the package is installed before doing work.
2. Ensure the package and accessibility component are enabled for Android user 0.
3. Read `enabled_accessibility_services`, append Yinxing's flattened component only when absent, and write the merged colon-delimited value back.
4. Set `accessibility_enabled=1` only when Yinxing has been added.
5. Add the package to the device-idle whitelist.
6. Set `RUN_IN_BACKGROUND` and `RUN_ANY_IN_BACKGROUND` app-ops to `allow` when those app-ops exist; unsupported commands are logged and do not terminate the loop.
7. Start the HOME activity after boot or after an explicit KernelSU Manager action.

It must never erase other accessibility components, clear all app-ops, kill unrelated processes, disable system updates, change lock-screen security, or accept command text from Intents/files/network input.

## State Flow

### Boot

1. KernelSU invokes `service.sh` during late start.
2. The guard waits until `sys.boot_completed=1` without a busy loop.
3. If Yinxing is not installed, it records one concise log entry and retries later.
4. If installed, it repairs the allowlisted state and starts the HOME activity once.
5. It rechecks the package/component, accessibility entry, and Doze whitelist at a low frequency. Writes occur only when state is missing or incorrect.

### Package Update

Android sends `MY_PACKAGE_REPLACED` to the existing `BootReceiver`, which restores the launcher UI. The guard's next health pass verifies that the component and accessibility registration still exist.

### Manual Repair

The KernelSU Manager action runs the same idempotent repair functions once and opens the launcher. There is no separate code path with broader privileges.

### Disable and Rollback

Disabling the KernelSU module prevents it from starting on the next boot. Uninstall removes the module runtime marker and its Doze whitelist entry, but deliberately does not disable Yinxing or remove its accessibility registration; destructive rollback remains an explicit caregiver choice in Android Settings.

## Error Handling and Observability

- All privileged commands are best-effort and independently checked; one unsupported ColorOS command cannot stop accessibility repair.
- Logs use a stable `YinxingGuard` tag and include module version, action name, and success/failure without contact names, phone numbers, tokens, or UI content.
- The loop uses a fixed low-frequency interval and a lock/pid guard so module entry points cannot create duplicate watchdogs.
- Missing package state is not treated as a boot failure.
- Shell functions quote package/component values and do not evaluate external input.
- A failed repair remains visible in logs and is retried; the APK continues in its existing non-Root mode.

## Packaging and Releases

The repository provides a deterministic module-packaging script that produces a KernelSU-installable ZIP without including development files. Each preview release contains:

- A versioned Debug APK signed by the workspace's stable debug key.
- A versioned `yinxing_guard` KernelSU module ZIP.
- SHA-256 checksums.
- Installation order, tested scope, limitations, rollback steps, and device acceptance checks.

The first tag is a prerelease so device feedback can change ColorOS-specific policy before a stable release.

## Verification

### Local Automated Checks

- Shell syntax validation for every module script.
- Host-side tests with fake `settings`, `pm`, `cmd`, `am`, and `getprop` commands.
- Tests prove that accessibility merging preserves existing services, is idempotent, handles an empty list, and refuses to run state changes when the package is absent.
- Tests prove one failed optional app-op does not block the remaining repair sequence.
- ZIP-content validation confirms required module files, permissions metadata expectations, and absence of test fixtures.
- Existing JVM tests and `:app:assembleDebug` must pass.

### OnePlus 15 Acceptance Checks

The release notes ask the caregiver to verify:

1. Install APK, grant KernelSU permission if requested, install module, and reboot.
2. Confirm Yinxing returns as HOME without opening Android accessibility settings manually.
3. Confirm Yinxing's accessibility service is enabled while any pre-existing service remains enabled.
4. Force-stop Yinxing, wait for the health interval, press Home, and confirm the launcher remains available.
5. Disable the accessibility service, wait for the interval, and confirm it is restored.
6. Disable the KernelSU module and reboot to confirm safe fallback to the APK's existing behavior.

Device-only acceptance is not claimed from the build host; results will be driven by user feedback.

## Iteration Order After This Release

1. Use OnePlus 15 logs and acceptance feedback to harden ColorOS-specific recovery.
2. Add an in-app caregiver health panel and a fixed one-shot Root repair command if device feedback shows it is useful.
3. Improve automation fallbacks while keeping semantic accessibility actions primary.
4. Iterate on the elderly launcher layout and recovery UX with device screenshots and usage feedback.
