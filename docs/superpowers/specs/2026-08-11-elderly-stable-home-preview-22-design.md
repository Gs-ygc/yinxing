# Preview 22 Stable Elderly Home Design

## Objective

Keep the elder-facing Home stable during repeated daily use while preserving complete caregiver control over which applications appear and in what order.

Preview 21 exposes two configuration mechanisms on the daily Home: an always-present `ADD` card and long-press drag on third-party application icons. The caregiver settings surface already has a protected `首页应用` route, so those Home mechanisms duplicate configuration and allow accidental layout changes.

## Selected Approach

Use one explicit ownership boundary:

- Home is an action surface. It contains the fixed phone/video actions and applications already chosen by the caregiver.
- `家属设置 -> 首页应用` is the configuration surface. It owns both application selection and application ordering.

This is preferred over confirmation dialogs around Home configuration because confirmations still advertise configuration to the older user and leave drag as a hidden mode. It is preferred over more Root/Kiosk work because Back interception, launcher ownership, and Root HOME recovery already exist, while further ColorOS behavior requires device evidence.

## Elder-Facing Home Contract

- Do not append the `ADD` item to static or loaded Home items.
- Do not attach `ItemTouchHelper` to the Home RecyclerView.
- Do not register Home application long-click listeners for ordering.
- Keep normal application taps, the Preview 21 same-target launch gate, fixed phone/video entries, trusted contacts, weather, and family-settings entry unchanged.
- A long press on a Home application has no side effect and does not persist a new order.
- A fresh Home with no selected third-party applications still shows phone, WeChat video, and the family-settings route in the header.

## Caregiver Application Management

The existing `AppManageActivity` remains the only application-management Activity.

### Ordering

- Selected applications appear first in the exact saved Home order.
- Installed applications not selected for Home follow in locale-independent name order.
- Each selected row exposes 48dp up and down icon buttons with localized TalkBack descriptions containing the application name.
- The first selected row has its up button disabled. The last selected row has its down button disabled.
- Unselected rows do not expose ordering buttons.
- An accepted move swaps one adjacent selected package, persists the complete selected order through `LauncherPreferences.saveAppOrder`, invalidates the Home selection cache, and refreshes the management list.
- A blank, missing, unselected, first-up, or last-down request is a no-op and does not rewrite preferences.

### Selection

- Existing checkbox and whole-row selection behavior remains.
- Selecting an application appends it once to the existing saved order, after the previously selected applications.
- Deselecting an application removes it from saved order.
- The list refreshes after selection so the selected group and arrow boundaries immediately reflect the persisted Home layout.

### Presentation

- Rename the page from `选择应用` to `首页应用`.
- The subtitle states the result, not a tutorial: selected applications are shown first in Home order.
- Keep the existing large row height, icon, application name, and checkbox.
- Add two stable icon-button slots between the application name and checkbox. Selected rows show them; unselected rows hide them without exposing meaningless accessibility nodes.
- Use familiar platform arrow icons and localized content descriptions rather than text buttons.

## Components

### `HomeAppOrderPolicy`

Add pure functions that:

- order management records as selected-in-saved-order followed by unselected-by-name;
- move one selected package by exactly one adjacent position while preserving all other packages.

The policy has no Android dependency and is the authoritative edge-case boundary.

### `LauncherAppRepository`

`getInstalledApps` maps installed records to `AppInfo`, then applies the management ordering policy using `getAppOrder`. Home item loading stops appending the secondary `ADD` item.

### `AppListAdapter`

The adapter receives `onMoveUp` and `onMoveDown` callbacks. Binding derives arrow visibility and enabled state from the immutable current list. Recycled holders clear listeners and icon jobs as before.

### `AppManageActivity`

Selection and move callbacks persist through `LauncherPreferences`, invalidate repository selections, and request one fresh list. Rapid move requests operate on the latest persisted order; invalid boundary requests produce no UI error because the corresponding control is disabled.

### `MainActivity` and `HomeAppAdapter`

Remove Home ordering wiring and drag-only state. Keep application click, icon loading, adaptive sizing, list differ behavior, and Preview 21 launch suppression intact. This is a simplification, not a new Home mode.

## Failure Handling

- Missing/uninstalled packages are already filtered by the installed application source and normalized order synchronization.
- Repository refresh failure retains the existing empty-state behavior; ordering does not introduce a second persistence store.
- A move never changes application selection.
- Selection and ordering remain local operations with no service, network call, timer, Root command, or background wakeup.
- No migration is needed because the existing selected package set and saved order remain authoritative.

## Accessibility And Large Text

- Ordering buttons have app-specific descriptions: `上移 %1$s` and `下移 %1$s`.
- Disabled boundary buttons remain discoverable as disabled only for selected rows; unselected row buttons are `GONE` and not focusable.
- Each ordering button is at least 48dp and does not reduce the checkbox target.
- Application names retain two-line wrapping. The row remains wrap-content so large font can increase height rather than overlap controls.
- Home cards retain one click target and no long-click action, reducing TalkBack ambiguity.

## Verification

Unit and Robolectric coverage must prove:

- management ordering follows saved Home order and appends unselected applications by name;
- adjacent movement, first/last bounds, missing packages, duplicate/stale saved values, and selection preservation;
- repository Home items contain no `ADD` item;
- management rows expose correctly enabled arrows and localized descriptions only when selected;
- activity arrow actions persist order and refresh the visible list;
- checkbox selection still appends/removes packages and updates groups;
- Home application long press cannot start a drag or persist order;
- existing application tap, duplicate-launch suppression, calling, Home virtualization, large-font sizing, and settings navigation remain green.

Release verification includes forced unit tests, main APK and androidTest compilation, lint classification, independent review, APK metadata/signature/hash checks, GitHub prerelease publication, and fresh remote download comparison. Root files are out of scope; prove they are unchanged rather than spending a release on another BusyBox-only matrix.

## Explicit Non-Goals

- No caregiver PIN or authentication system.
- No new edit mode, Activity, overlay, service, receiver, or Root command.
- No application install/uninstall support.
- No changes to HOME ownership, boot recovery, Accessibility recovery, Doze, calling, or external application launch behavior.
- No claims about ColorOS task switching, latency, or power without the fixed OnePlus 15.
