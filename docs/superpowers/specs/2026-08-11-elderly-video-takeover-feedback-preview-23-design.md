# Preview 23 Elderly Video Takeover Feedback Design

## Objective

Make the repeated path from a video contact to WeChat immediately actionable, continuously understandable, and easy to cancel without changing the existing automation engine or claiming unmeasured ColorOS behavior.

Preview 22 already validates network, WeChat availability, Accessibility, overlay permission, contact search data, concurrent requests, terminal callbacks, and a 130-second watchdog. The remaining local product gap is visible feedback: the takeover overlay names no contact, exposes diagnostic step counts, and offers only a low-contrast 36dp `x` that silently requires a long press. The video contact list also retains staggered entry and item animations that the phone and Home paths intentionally removed.

## Selected Approach

Treat the existing overlay as a small elderly-facing task controller:

- The title stays stable as `正在联系 %1$s` for the active contact.
- The secondary line shows the existing plain-language current action, such as opening WeChat or finding the contact.
- One explicit `取消` button cancels on a normal tap. Cancellation is recoverable, so a hidden long-press safety gesture adds more risk than it removes.
- The button has a stable touch target of at least 56dp, high-contrast text, and one localized accessibility description.
- The existing service cancellation path remains authoritative: clear timers/session state, report terminal cancellation, and request that Yinxing return to the foreground.
- Video contact rows have no entry animation and the RecyclerView has no item animator, so a bound contact is immediately actionable.

This is preferred over app-management search because takeover is a daily elderly workflow while app selection is occasional caregiver setup. It is preferred over incoming-call recovery UI or more Root-driven HOME work because those require OnePlus 15 failure evidence to choose the correct behavior.

## Interaction Contract

### Video Contact Page

- Contact ordering, card sizes, phone-versus-WeChat action colors, full-card caregiver option, and click callbacks remain unchanged.
- `VideoCallActivity` always disables RecyclerView item animation and adapter entry animation, independent of low-performance mode.
- Low-performance mode still controls icon cache size and image loading dimensions; this change does not redefine the mode.

### Active WeChat Takeover

- Starting a valid request shows a compact top-end overlay before WeChat is launched.
- The overlay title identifies the target contact and remains stable across automation steps.
- The status line updates through the existing `updateProgress` calls. It does not expose `stepNumber`, total-step counts, enum names, request IDs, or other diagnostic detail.
- The cancel action responds to one ordinary tap and invokes the registered listener exactly once per tap.
- The overlay stays non-focus-stealing so WeChat and Accessibility automation keep their current window behavior.
- Success retains the current terminal message and delayed hide behavior. Failure and cancellation retain the current hide, diagnostics, TTS/Toast callback, and launcher-return behavior.

## Components

### `floating_status.xml`

Replace the 36dp glyph target with an explicit text action. Keep the existing status card and two-line information hierarchy. Bound the text column so long status text wraps instead of pushing the action off screen. The action must be visible, enabled, at least 56dp high, and expose `video_call_overlay_cancel_description`.

### `FloatingStatusView`

Rename the stored listener to describe a cancel request rather than a long click. Bind it with `setOnClickListener`; remove the long-click-only contract. Keep all `WindowManager` flags, main-thread posting, add/remove error containment, and update behavior unchanged.

The cancel-binding method remains an internal, Android-local boundary so a Robolectric test can bind an inflated view without adding a real overlay window.

### `SelectToSpeakService`

Format one localized contact title and pass it as the first line to both initial `show` and subsequent `updateMessage` calls. Pass the current progress message as the second line. Remove only the visible `stepLabel` formatter; keep `stepNumber` and `stepName` for logs, timeout metrics, and diagnostics.

### `VideoCallActivity`

Set the RecyclerView item animator to `null` and disable adapter animations whenever performance settings are applied. No new setting is added.

## Failure Handling And Safety

- The cancel button does not issue a shell or Root command. It reuses `cancelSession(true)`.
- A cancellation remains terminal for that request, clears callbacks/watchdogs through the existing coordinator path, and allows a later retry.
- Missing overlay permission still follows the existing caregiver prompt before takeover, so the new control is never treated as a substitute for permission readiness.
- No network request, timer, service, receiver, polling loop, wake lock, or persistent setting is added.
- No automation selector, adaptive delay, timeout, retry budget, WeChat navigation decision, Root module, or BusyBox file changes.

## Accessibility And Large Text

- The visible action label is `取消`; its content description is `取消联系`.
- The cancel target is at least 56dp in both dimensions and uses high-contrast overlay colors.
- Contact and status text allow two lines and have bounded width so increased font scale cannot overlap the cancel action.
- The overlay exposes a clear outcome and current action rather than a six-step implementation sequence.
- A single tap replaces the undiscoverable long-press gesture, reducing motor and memory demands.

## Verification

Focused tests must prove:

- the inflated overlay has the exact cancel label/description, a minimum 56dp target, and an explicit text action;
- binding a cancel listener makes one ordinary click invoke it once;
- title/status binding preserves both lines and hides only a blank status;
- the video Activity has no RecyclerView item animator and its adapter animation flag is disabled;
- the service source uses the localized contact title as the stable first line while retaining diagnostic step helpers for logs;
- existing video call, Accessibility task engine, phone, Home, incoming-call, and settings tests remain green.

Release verification includes focused RED/GREEN evidence, full forced unit tests, Debug APK and androidTest compilation, lint classification, changed-file review, APK metadata/signature/hash checks, GitHub prerelease publication, and fresh remote asset verification. Since Root/BusyBox files are unchanged, verification proves that fact rather than rerunning an unrelated compatibility matrix.

## Explicit Non-Goals

- No change to WeChat selectors, navigation, timeouts, retries, or adaptive delays.
- No new retry button or automated retry after a terminal failure.
- No new Activity, service, overlay permission flow, Root command, or KernelSU module asset.
- No app-management search in this release.
- No incoming-call UI change.
- No claim that ColorOS 16 returns Home, launches WeChat faster, or consumes less power until measured on the fixed OnePlus 15.
