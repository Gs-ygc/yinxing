# Preview 21 老年主路径接管可靠性 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans for inline execution, plus superpowers:test-driven-development and superpowers:verification-before-completion.

**Goal:** Reduce elderly handoff taps and duplicate external launches without changing Root authority or automatically placing calls.

**Architecture:** Keep `PhoneCallLauncher` as the shared phone state machine and reuse its existing generic Intent-launch boundary for the safe dialer fallback. Extract Home app launch resolution/gating into `HomeAppLauncher`, leaving `HomeNavigator` responsible only for navigation wiring and user-facing unavailable feedback. Both gates are small elapsed-time state holders with deterministic tests.

**Tech Stack:** Kotlin, Android Intent, RecyclerView click listeners, Robolectric/JUnit, Gradle Android plugin.

## Global Constraints

- Direct calls remain `ACTION_CALL` when `CALL_PHONE` is granted.
- Fallback is `ACTION_DIAL` only; the app never calls automatically after fallback.
- Duplicate suppression defaults to 1,200 ms and is destination-scoped.
- No Root, BusyBox, Accessibility command, manifest permission, or background-loop changes.
- Existing fallback dialog remains the last-resort path when no dialer can handle the intent.

---

### Task 1: Safe dialer handoff

**Files:**
- Modify: `app/src/main/java/com/yinxing/launcher/feature/phone/PhoneCallLauncher.kt`
- Test: `app/src/test/java/com/yinxing/launcher/feature/phone/PhoneCallLauncherTest.kt`

**Interfaces:**
- `PhoneCallLauncher` reuses `launchIntent: (Intent) -> Unit` for `ACTION_DIAL` and produces the existing fallback callback only when that operation also throws.

- [ ] Write tests for permission denial and direct-call failure automatically attempting `ACTION_DIAL`, and for dialer failure retaining the fallback callback.
- [ ] Run the focused launcher tests and confirm the new cases fail because failure paths do not launch `ACTION_DIAL`.
- [ ] Add one shared `openDialerOrFallback` path using `launchIntent`; keep `onCallLaunched` only on direct-call success.
- [ ] Run the focused tests again; no Activity constructor wiring change is required.
- [ ] Commit `feat: hand off failed calls to dialer`.

### Task 2: Same-target Home app launch gate

**Files:**
- Create: `app/src/main/java/com/yinxing/launcher/feature/home/HomeAppLaunchGate.kt`
- Create: `app/src/main/java/com/yinxing/launcher/feature/home/HomeAppLauncher.kt`
- Modify: `app/src/main/java/com/yinxing/launcher/feature/home/HomeNavigator.kt`
- Test: `app/src/test/java/com/yinxing/launcher/feature/home/HomeAppLaunchGateTest.kt`
- Test: `app/src/test/java/com/yinxing/launcher/feature/home/HomeAppLauncherTest.kt`

**Interfaces:**
- `HomeAppLaunchGate.tryAcquire(packageName: String): Boolean` accepts a destination when it has not succeeded inside the cooldown; `release(packageName: String)` removes a failed attempt.
- `HomeAppLauncher.open(item: HomeAppItem): Boolean` resolves/launches one app and invokes `onUnavailable` for blank or unresolved packages.

- [ ] Write gate tests for same-target suppression, independent different-target acceptance, expiry, and release after failure.
- [ ] Run the focused gate tests and confirm RED.
- [ ] Implement the minimal elapsed-realtime gate.
- [ ] Write launcher tests for intent resolution, one successful launch, duplicate suppression, and unavailable feedback.
- [ ] Run launcher tests RED, then implement the resolver/launch wrapper.
- [ ] Wire `HomeNavigator` to the wrapper without changing phone/WeChat/add routing; commit `feat: guard duplicate home app launches`.

### Task 3: Regression and release evidence

**Files:**
- Modify: `app/src/test/java/com/yinxing/launcher/feature/home/MainActivitySmokeTest.kt`
- Modify: `docs/release/yinxing-root-preview-21.md`
- Modify: `app/build.gradle.kts`

- [ ] Add a MainActivity smoke assertion that a selected external application is launched only once for a same-target touch burst.
- [ ] Bump version to `1.10.0-root-preview.21` / code 37.
- [ ] Run forced unit tests, APK and androidTest compilation, lint classification, and unchanged Root matrix.
- [ ] Package APK/checksum assets, verify metadata/signature/byte identity, and publish a prerelease with explicit device gaps.
- [ ] Fresh-download Release assets and verify checksums and remote refs before merging to `main`.
- [ ] Commit release evidence, fast-forward/push `main`, tag, and publish the GitHub Release.
