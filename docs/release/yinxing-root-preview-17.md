# Yinxing Root Preview 17

Preview 17 targets the managed OnePlus 15 China ColorOS 16 device with
KernelSU and Root. It closes a false-success path in HOME recovery: a
successful `am start` no longer means the launcher is assumed visible.

## Release contents

- `yinxing-1.10.0-root-preview.17-debug.apk`: Debug APK, `versionCode=33`.
- `yinxing-guard-1.10.0-root-preview.17.zip`: KernelSU Root Guard module,
  `versionCode=17`.
- `SHA256SUMS.txt`: SHA-256 checksums for both binary assets.

## What changed

After its fixed HOME launch, Root Guard now checks only explicit resumed and
focused records for the fixed Yinxing MainActivity. It writes a boot-scoped
confirmation record only after that postcondition succeeds.

The Root health protocol is now schema 3:

- `桌面` reports HOME role and resolver ownership.
- `前台确认` reports the most recent Root launch result in the current boot:
  `正常` means verified, `待处理` means unverified, and `未知` means no safe
  current-boot evidence.

This is intentionally not a live foreground indicator. Opening Settings,
WeChat, or another normal app must not turn a previously confirmed launcher
launch into a false alarm.

Known-other foreground evidence may receive one later Guard retry, with at
most two fixed HOME starts in one Guard process. Unknown, malformed, failed,
or timed-out diagnostics stop further starts in that process and leave the
health result degraded. Manual recovery records success only after foreground
confirmation.

The APK still grants Root only to the fixed `status.sh`, `action.sh`, and
`kiosk-home.sh` paths. No arbitrary shell, tap coordinates, package names,
components, process kills, or private ColorOS APIs were added. Kiosk launch is
bounded to 15 seconds and explicit recovery to 20 seconds.

## Install order

1. Cover-install `yinxing-1.10.0-root-preview.17-debug.apk` first.
2. Install and enable `yinxing-guard-1.10.0-root-preview.17.zip` in KernelSU.
   Reboot if KernelSU requests it.
3. In Silver Ginkgo Settings, run one Root repair and check that `桌面` and
   `前台确认` both show `正常`.
4. Press Home, enter one automation flow, and reboot once before relying on
   unattended use.

The module continues to keep Silver Ginkgo as HOME on the controlled device.
That is expected for this dedicated-device mode. This APK is Debug-signed, not
a production signing release.

## Rollback

1. Disable or uninstall the KernelSU module.
2. Reboot when KernelSU requests it so the deferred cleanup can restore the
   earlier HOME route and owned Doze/accessibility transactions.
3. Confirm Home returns to the desired launcher before installing an older
   module.
4. The APK can be covered by an older Debug build when the device allows it.

Preview 16 Release: <https://github.com/Gs-ygc/yinxing/releases/tag/v1.10.0-root-preview.16>

## Verification record

Final shell, JVM, Debug-build, package, APK-signature, checksum, and fresh
GitHub-download evidence is added immediately before publishing. This release
does not represent host fixtures as physical OnePlus 15 verification.

## SHA-256

Published values are added immediately before the GitHub Release is created.
