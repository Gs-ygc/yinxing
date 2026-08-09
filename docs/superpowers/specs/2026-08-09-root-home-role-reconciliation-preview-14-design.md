# Root HOME Role Reconciliation Preview 14

## Context

Preview 13 prevents a stalled Android Binder command from permanently blocking
Root Guard. The remaining launcher-level gap is ownership rather than process
liveness: the module starts the fixed Yinxing HOME Activity once after repair,
but it never proves which launcher Android will resolve for a later Home key
press. The APK's standard `RoleManager` flow still requires caregiver approval,
and Kiosk mode refuses to enable until Yinxing is already the default launcher.

On a managed OnePlus 15, a ColorOS update, default-app reset, or accidental role
change can therefore leave Root, accessibility, and keepalive apparently healthy
while Home returns to the ColorOS launcher.

Current AOSP exposes an exact shell contract for this layer. `cmd role
get-role-holders --user 0 android.app.role.HOME` reports the role holder, and
`cmd package set-home-activity --user 0 <component>` delegates to RoleManager
and waits for the asynchronous result. Both commands can use Preview 13's
existing bounded BusyBox command supervisor.

## Goals

- Make the active Root module continuously prove that Yinxing owns the HOME
  role for user 0 and recover exact ownership when it does not.
- Persist enough root-only state before the first module-owned change to restore
  the prior HOME holder after module removal.
- Surface HOME ownership in the strict Root health snapshot and caregiver UI.
- Preserve the fixed APK Root paths and the bounded Android-command boundary.
- Keep role query, mutation, confirmation, and uninstall recovery testable in
  both host shell and standalone BusyBox `ash`.

## Non-Goals

- No arbitrary shell, APK-supplied package/component/user, input event,
  coordinate click, process selection, ColorOS private setting, or firmware
  signature integration.
- No automatic Kiosk preference change. Root HOME ownership makes the existing
  Kiosk prerequisite reliable but does not silently enable that product mode.
- No removal or replacement of the standard Android `RoleManager` UI. It
  remains the fallback for installations without the module.
- No attempt to support secondary Android users in this preview; the managed
  device contract remains fixed to user 0.

## Alternatives

### Exact role reconciliation and conditional rollback (selected)

Read the AOSP HOME role, save its prior holder before the first mutation, set
the fixed Yinxing component, confirm the result, and reconcile it on every
health cycle. This directly controls the Home-key contract and is observable
and reversible.

### More launch retries

Repeat `am start`, a PendingIntent, or accessibility global Home more often.
These can foreground Yinxing temporarily but cannot change the HOME resolver.
Preview 13 already contains bounded launch recovery, so this would not close
the identified gap.

### Privileged/system APK role management

Install Yinxing as a platform-signed privileged app and call hidden role APIs.
This couples the product to firmware signing and SELinux policy without
improving the fixed shell contract available on the rooted target. It remains a
future firmware option, not the next reliability slice.

## Design

### Exact HOME observation

Add fixed constants for `android.app.role.HOME` and the root-owned prior-holder
marker. A shared helper invokes only:

```text
cmd role get-role-holders --user 0 android.app.role.HOME
```

The result is classified as:

- `owned`: exactly one valid package line and it is `com.yinxing.launcher`;
- `other`: exactly one valid non-Yinxing package line;
- `none`: successful command with no holder output;
- `unknown`: command failure, malformed data, or multiple holders for this
  exclusive role.

Only `owned`, `other`, and `none` are actionable. Unknown evidence never changes
the role. Parsing is exact and line-based; no substring match or vendor dump
format is used.

### Reconciliation state machine

After package/accessibility enablement succeeds, every Guard/action repair
cycle reads HOME ownership.

If Yinxing already owns HOME, repair succeeds without creating a rollback
marker. This preserves a role that was granted manually before module use. If
a marker already exists it must still be valid; corrupted module-owned rollback
state fails repair even though current ownership is correct.

For `other` or `none`, reconciliation first writes
`$STATE_DIR/home_previous_holder` atomically with mode `0600`. The marker stores
the exact prior package or the literal `none`. An existing valid marker is never
overwritten, so repeated repairs retain the pre-takeover rollback target. An
invalid marker, including a marker that names Yinxing itself, blocks mutation
and fails repair.

After the marker is durable, the module invokes only the fixed command:

```text
cmd package set-home-activity --user 0 \
  com.yinxing.launcher/.feature.home.MainActivity
```

It then reruns the exact role query and succeeds only when the result is
`owned`. A set failure or unconfirmed result records the existing failed repair
state and leaves the marker for retry and rollback. Successful reconciliation
continues through the existing keepalive and fixed HOME launch flow.

While the module remains active, a deliberate or accidental switch to another
launcher is reclaimed on the next bounded Guard cycle. Disabling the module
stops enforcement; removing it activates the conditional restoration below.

### Conditional uninstall restoration

Extend the existing boot-completed uninstall helper because it survives until
KernelSU has actually removed the module. The helper remains scheduled when
either the Doze ownership marker or HOME prior-holder marker exists.

HOME cleanup first validates the marker and re-queries the current role:

- If current HOME is not Yinxing, a later caregiver/system choice wins. Remove
  only the module's marker and do not set another launcher.
- If current HOME is Yinxing and the saved holder is a package, verify that
  package is installed, set it through the same fixed package command, and
  confirm the exact holder before deleting the marker.
- If current HOME is Yinxing and the saved value is `none`, remove only Yinxing
  with `cmd role remove-role-holder`, then confirm Yinxing is no longer the
  holder before deleting the marker.
- On query, validation, package, mutation, or confirmation failure, leave both
  the marker and helper in place for a later boot retry.

The prior package is system-observed root-owned state, passed as one argv value
without shell evaluation. It is never supplied by the APK. Cleanup of HOME and
Doze markers is independent, so one successful rollback is not repeated when
the other needs a retry.

### Root status schema 2

`status.sh` emits schema 2 and adds one fixed field between accessibility and
Doze:

```text
home=owned|other|none|unknown
```

Schema 2 is healthy only when module is active, Guard is running,
accessibility is enabled, HOME is owned, Doze is owned/present, cleanup is
ready, and the last repair is successful.

The Preview 14 APK parser accepts both schemas exactly. Schema 1 retains its
eight-key grammar but maps HOME to `unknown` and cannot derive healthy, making
a staggered old-module installation visible as degraded rather than malformed
or falsely complete. Schema 2 requires exactly nine keys and the new HOME
allowlist. Extra, duplicate, missing, or contradictory values still fail
closed.

The Root sheet adds the HOME dimension to its existing compact status summary.
No automatic `su` query is added to ordinary settings-page rendering; the
explicit sheet/session lifecycle remains unchanged.

### Authority and failure boundaries

The APK still executes exactly three fixed no-argument module paths:
`status.sh`, `action.sh`, and `kiosk-home.sh`. HOME role commands exist only
inside the module and use the existing two-second BusyBox `setsid`/`timeout`
boundary. Status/query failures are non-mutating. Required HOME repair failures
produce the existing `last_repair=failed`; they do not fall back to an
unbounded command or OEM-private interface.

## Testing

Extend the shell harness with a stateful fake HOME holder and command failures.
The host and recursive BusyBox suites must prove:

1. already-owned HOME is idempotent and creates no rollback marker;
2. another holder and no holder are recorded before one fixed takeover;
3. takeover is confirmed and repeated health cycles do not rewrite state;
4. failed/malformed/multiple-holder queries make no mutation;
5. marker-write, set, and confirmation failures remain failed and retryable;
6. status reports all four HOME values with the exact schema-2 line contract;
7. uninstall restores an installed prior holder and removes Yinxing for a
   prior `none` state;
8. a newer non-Yinxing caregiver choice is preserved;
9. failed uninstall restoration retains marker/helper state; and
10. stalled role query/set/restore commands stay inside Preview 13's process
    and elapsed-time bounds.

Add JVM tests for exact schema-1 compatibility, strict schema-2 parsing,
HOME-driven health derivation, malformed/missing/duplicate HOME rejection, and
the settings summary label. Existing Root runner, accessibility, Kiosk,
supervisor, uninstall, and packaging coverage remains mandatory.

Final gates are shell syntax, BusyBox syntax, direct-command scanning,
`git diff --check`, all Android JVM tests, forced Debug build, APK metadata/v2
signature, deterministic module ZIP, basename-only checksums, independent code
review, and fresh GitHub Release download verification.

## Release Contract

Preview 14 will bump APK code/name to `30`/`1.10.0-root-preview.14` and module
code/name to `14`/`1.10.0-root-preview.14`. The prerelease will contain the
Debug APK, KernelSU ZIP, checksums, installation order, explicit managed-HOME
behavior, uninstall-before-downgrade rollback instructions, the fixed authority
statement, and the no-device caveat.

## Sources

- AOSP PackageManagerShellCommand `set-home-activity`:
  https://android.googlesource.com/platform/frameworks/base/+/21a5e8f7a13d7b7f60334116cbd3b5c5a07d1cb0/services/core/java/com/android/server/pm/PackageManagerShellCommand.java
- AOSP Role system guide and shell commands:
  https://android.googlesource.com/platform/packages/modules/Permission/+/refs/heads/main/PermissionController/src/com/android/permissioncontroller/role/Role.md
- AOSP CTS default-launcher query usage:
  https://android.googlesource.com/platform/cts/+/master/hostsidetests/devicepolicy/src/com/android/cts/devicepolicy/BaseDevicePolicyTest.java
