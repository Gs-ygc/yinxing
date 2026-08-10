package com.yinxing.launcher.feature.phone

import android.content.Intent
import com.yinxing.launcher.data.contact.Contact
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class PhoneCallLauncherTest {
    @Test
    fun permissionGrantedLaunchesDirectCallAndRecordsSuccess() {
        val fixture = Fixture(hasPermission = true)
        val contact = contact("1", "妈妈", "13800138000")

        fixture.launcher.makeCall(contact)

        assertEquals(1, fixture.launchedIntents.size)
        assertEquals(Intent.ACTION_CALL, fixture.launchedIntents.single().action)
        assertEquals("tel:13800138000", fixture.launchedIntents.single().dataString)
        assertEquals(listOf(contact), fixture.recordedContacts)
        assertTrue(fixture.permissionRequests.isEmpty())
        assertTrue(fixture.fallbacks.isEmpty())
    }

    @Test
    fun missingPermissionWaitsForGrantBeforeLaunching() {
        val fixture = Fixture(hasPermission = false)
        val contact = contact("1", "妈妈", "13800138000")

        fixture.launcher.makeCall(contact)

        assertEquals(listOf(contact), fixture.permissionRequests)
        assertSame(contact, fixture.launcher.pendingContactOrNull)
        assertTrue(fixture.launchedIntents.isEmpty())

        fixture.hasPermission = true
        fixture.launcher.onPermissionResult(granted = true)

        assertNull(fixture.launcher.pendingContactOrNull)
        assertEquals(1, fixture.launchedIntents.size)
        assertEquals(listOf(contact), fixture.recordedContacts)
    }

    @Test
    fun deniedPermissionOpensDialerOnceWithoutRecordingCall() {
        val fixture = Fixture(hasPermission = false)
        val contact = contact("1", "妈妈", "13800138000")

        fixture.launcher.makeCall(contact)
        fixture.launcher.onPermissionResult(granted = false)
        fixture.launcher.onPermissionResult(granted = false)

        assertNull(fixture.launcher.pendingContactOrNull)
        assertEquals(listOf(Intent.ACTION_DIAL), fixture.attemptedActions)
        assertEquals(Intent.ACTION_DIAL, fixture.launchedIntents.single().action)
        assertTrue(fixture.fallbacks.isEmpty())
        assertTrue(fixture.recordedContacts.isEmpty())
    }

    @Test
    fun permissionRequestFailureOpensDialerWithoutRecordingCall() {
        val fixture = Fixture(
            hasPermission = false,
            permissionRequestFailure = IllegalStateException("permission launcher unavailable")
        )
        val contact = contact("1", "妈妈", "13800138000")

        fixture.launcher.makeCall(contact)

        assertNull(fixture.launcher.pendingContactOrNull)
        assertEquals(listOf(Intent.ACTION_DIAL), fixture.attemptedActions)
        assertEquals(Intent.ACTION_DIAL, fixture.launchedIntents.single().action)
        assertTrue(fixture.fallbacks.isEmpty())
        assertTrue(fixture.recordedContacts.isEmpty())
    }

    @Test
    fun duplicateTapInsideCooldownLaunchesOnlyOnce() {
        val fixture = Fixture(hasPermission = true)
        val first = contact("1", "妈妈", "13800138000")
        val second = contact("2", "爸爸", "13900139000")

        fixture.launcher.makeCall(first)
        fixture.nowMillis += 1_199L
        fixture.launcher.makeCall(second)

        assertEquals(1, fixture.launchedIntents.size)
        assertEquals(listOf(first), fixture.recordedContacts)
    }

    @Test
    fun directIntentFailureOpensDialerWithoutRecordingSuccess() {
        val fixture = Fixture(
            hasPermission = true,
            directLaunchFailure = IllegalStateException("blocked")
        )
        val contact = contact("1", "妈妈", "13800138000")

        fixture.launcher.makeCall(contact)

        assertEquals(listOf(Intent.ACTION_CALL, Intent.ACTION_DIAL), fixture.attemptedActions)
        assertEquals(Intent.ACTION_DIAL, fixture.launchedIntents.single().action)
        assertTrue(fixture.fallbacks.isEmpty())
        assertTrue(fixture.recordedContacts.isEmpty())
    }

    @Test
    fun unavailableDialerKeepsFallbackAfterDeniedPermission() {
        val fixture = Fixture(
            hasPermission = false,
            dialerLaunchFailure = IllegalStateException("no dialer")
        )
        val contact = contact("1", "妈妈", "13800138000")

        fixture.launcher.makeCall(contact)
        fixture.launcher.onPermissionResult(granted = false)

        assertEquals(listOf(Intent.ACTION_DIAL), fixture.attemptedActions)
        assertTrue(fixture.launchedIntents.isEmpty())
        assertEquals(listOf(Fallback(contact, directCallFailed = false)), fixture.fallbacks)
        assertTrue(fixture.recordedContacts.isEmpty())
    }

    @Test
    fun unavailableDialerKeepsFailureFallbackAfterDirectCallFailure() {
        val fixture = Fixture(
            hasPermission = true,
            directLaunchFailure = IllegalStateException("blocked"),
            dialerLaunchFailure = IllegalStateException("no dialer")
        )
        val contact = contact("1", "妈妈", "13800138000")

        fixture.launcher.makeCall(contact)

        assertEquals(listOf(Intent.ACTION_CALL, Intent.ACTION_DIAL), fixture.attemptedActions)
        assertTrue(fixture.launchedIntents.isEmpty())
        assertEquals(listOf(Fallback(contact, directCallFailed = true)), fixture.fallbacks)
        assertTrue(fixture.recordedContacts.isEmpty())
    }

    @Test
    fun restoredPendingContactContinuesAfterPermissionResult() {
        val fixture = Fixture(hasPermission = true)
        val contact = contact("1", "妈妈", "13800138000")

        fixture.launcher.restorePendingContact(contact)
        fixture.launcher.onPermissionResult(granted = true)

        assertEquals(1, fixture.launchedIntents.size)
        assertEquals(listOf(contact), fixture.recordedContacts)
    }

    @Test
    fun blankNumberIsIgnored() {
        val fixture = Fixture(hasPermission = false)

        fixture.launcher.makeCall(contact("1", "妈妈", "   "))

        assertNull(fixture.launcher.pendingContactOrNull)
        assertTrue(fixture.permissionRequests.isEmpty())
        assertTrue(fixture.launchedIntents.isEmpty())
        assertTrue(fixture.fallbacks.isEmpty())
    }

    @Test
    fun permissionRequestErrorPropagatesWithoutOpeningDialer() {
        val fatalError = FatalLaunchError()
        val fixture = Fixture(
            hasPermission = false,
            permissionRequestFailure = fatalError
        )
        val contact = contact("1", "妈妈", "13800138000")

        try {
            fixture.launcher.makeCall(contact)
            fail("Expected permission request Error to propagate")
        } catch (caught: FatalLaunchError) {
            assertSame(fatalError, caught)
        }

        assertTrue(fixture.attemptedActions.isEmpty())
        assertTrue(fixture.fallbacks.isEmpty())
    }

    @Test
    fun directCallErrorPropagatesWithoutOpeningDialer() {
        val fatalError = FatalLaunchError()
        val fixture = Fixture(
            hasPermission = true,
            directLaunchFailure = fatalError
        )
        val contact = contact("1", "妈妈", "13800138000")

        try {
            fixture.launcher.makeCall(contact)
            fail("Expected direct call Error to propagate")
        } catch (caught: FatalLaunchError) {
            assertSame(fatalError, caught)
        }

        assertEquals(listOf(Intent.ACTION_CALL), fixture.attemptedActions)
        assertTrue(fixture.fallbacks.isEmpty())
        assertTrue(fixture.recordedContacts.isEmpty())
    }

    @Test
    fun dialerErrorPropagatesWithoutShowingFallback() {
        val fatalError = FatalLaunchError()
        val fixture = Fixture(
            hasPermission = false,
            dialerLaunchFailure = fatalError
        )
        val contact = contact("1", "妈妈", "13800138000")

        fixture.launcher.makeCall(contact)
        try {
            fixture.launcher.onPermissionResult(granted = false)
            fail("Expected dialer Error to propagate")
        } catch (caught: FatalLaunchError) {
            assertSame(fatalError, caught)
        }

        assertEquals(listOf(Intent.ACTION_DIAL), fixture.attemptedActions)
        assertTrue(fixture.fallbacks.isEmpty())
    }

    private data class Fallback(
        val contact: Contact,
        val directCallFailed: Boolean
    )

    private class Fixture(
        hasPermission: Boolean,
        private val permissionRequestFailure: Throwable? = null,
        private val directLaunchFailure: Throwable? = null,
        private val dialerLaunchFailure: Throwable? = null
    ) {
        var hasPermission = hasPermission
        var nowMillis = 100L
        val permissionRequests = mutableListOf<Contact>()
        val attemptedActions = mutableListOf<String?>()
        val launchedIntents = mutableListOf<Intent>()
        val fallbacks = mutableListOf<Fallback>()
        val recordedContacts = mutableListOf<Contact>()

        val launcher = PhoneCallLauncher(
            hasCallPermission = { this.hasPermission },
            requestPermission = { contact ->
                permissionRequestFailure?.let { throw it }
                permissionRequests += contact
            },
            launchIntent = { intent ->
                attemptedActions += intent.action
                when (intent.action) {
                    Intent.ACTION_CALL -> directLaunchFailure?.let { throw it }
                    Intent.ACTION_DIAL -> dialerLaunchFailure?.let { throw it }
                }
                launchedIntents += intent
            },
            showFallback = { contact, failed -> fallbacks += Fallback(contact, failed) },
            onCallLaunched = recordedContacts::add,
            gate = PhoneCallLaunchGate(nowMillis = { nowMillis })
        )
    }

    private fun contact(id: String, name: String, phone: String) = Contact(
        id = id,
        name = name,
        phoneNumber = phone
    )

    private class FatalLaunchError : Error()
}
