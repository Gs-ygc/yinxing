# Task 2 Report: Asynchronous Home Contact State

## RED

Added three `HomeViewModelTest` cases covering callable contact selection, replacing the list after a caregiver edit, and preserving a successful list after a failed refresh.

The requested focused command was attempted:

```bash
bash gradlew :app:testDebugUnitTest --tests '*HomeViewModelTest.refreshTrustedContacts*' --no-daemon --console=plain
```

The run could not reach compilation because the Gradle wrapper attempted to download Gradle 9.3.1 in this environment.

## Implementation

- Added injectable `HomeTrustedContactSource` with `suspend fun getContacts()`.
- Added `trustedContacts: StateFlow<List<Contact>>` initialized to an empty list.
- Added cancellable `refreshTrustedContacts()`; successful loads are filtered and capped by `HomeTrustedContactPolicy`, cancellation propagates, and other failures preserve the current list.
- Added `AndroidHomeTrustedContactSource`, which reads `PhoneContactManager.getInstance(appContext).getContacts()` inside `withContext(Dispatchers.IO)` and wires it through `HomeViewModel.Factory`.
- Extended the existing test fake to support caregiver edits and simulated failures.

## Verification

`git diff --check` passed.

The focused and full `HomeViewModelTest` Gradle commands were also attempted with the locally installed Gradle 9.0.0. Both were blocked before compilation because the project requests a Java 21 toolchain and the Foojay/GitHub JDK download is unavailable from this environment.

## Commit

The implementation commit is created after this report is reviewed; its hash is included in the task handoff.

## Concerns

- Gradle/JDK toolchain availability prevented test execution in this environment.
- `MainActivity.onResume()` wiring is intentionally left to the Activity/UI task owner per the parent task instruction.
