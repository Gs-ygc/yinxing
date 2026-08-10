package com.yinxing.launcher.feature.phone

import android.content.Intent
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class PhoneCallLaunchGateTest {
    @Test
    fun firstTapIsAccepted() {
        val gate = PhoneCallLaunchGate(nowMillis = { 100L })

        assertTrue(gate.tryAcquire("13800138000"))
    }

    @Test
    fun repeatedTapForSameNumberWithinCooldownIsIgnored() {
        var now = 100L
        val gate = PhoneCallLaunchGate(nowMillis = { now })

        assertTrue(gate.tryAcquire("13800138000"))
        now += 1_199L

        assertFalse(gate.tryAcquire("13800138000"))
    }

    @Test
    fun differentNumberIsAlsoIgnoredUntilCooldownEnds() {
        var now = 100L
        val gate = PhoneCallLaunchGate(nowMillis = { now })

        assertTrue(gate.tryAcquire("13800138000"))
        assertFalse(gate.tryAcquire("13900139000"))
        now += 1_200L
        assertTrue(gate.tryAcquire("13900139000"))
    }

    @Test
    fun blankNumberIsNeverAccepted() {
        val gate = PhoneCallLaunchGate(nowMillis = { 100L })

        assertFalse(gate.tryAcquire("  "))
    }

    @Test
    fun intentFactoryKeepsDirectAndFallbackActionsExplicit() {
        val direct = PhoneCallIntentFactory.direct("13800138000")
        val fallback = PhoneCallIntentFactory.dialer("13800138000")

        assertEquals(Intent.ACTION_CALL, direct.action)
        assertEquals(Intent.ACTION_DIAL, fallback.action)
        assertEquals("tel:13800138000", direct.dataString)
        assertEquals("tel:13800138000", fallback.dataString)
    }
}
