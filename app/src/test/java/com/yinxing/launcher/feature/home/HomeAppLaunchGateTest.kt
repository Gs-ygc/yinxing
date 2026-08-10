package com.yinxing.launcher.feature.home

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class HomeAppLaunchGateTest {
    @Test
    fun sameDestinationIsSuppressedUntilCooldownExpires() {
        var now = 100L
        val gate = HomeAppLaunchGate(nowMillis = { now })

        assertTrue(gate.tryAcquire("com.example.camera"))
        now += 1_199L
        assertFalse(gate.tryAcquire("com.example.camera"))
        now += 1L
        assertTrue(gate.tryAcquire("com.example.camera"))
    }

    @Test
    fun differentDestinationsDoNotBlockEachOther() {
        val gate = HomeAppLaunchGate(nowMillis = { 100L })

        assertTrue(gate.tryAcquire("com.example.camera"))
        assertTrue(gate.tryAcquire("com.example.messages"))
    }

    @Test
    fun failedDestinationCanBeReleasedForImmediateRetry() {
        val gate = HomeAppLaunchGate(nowMillis = { 100L })

        assertTrue(gate.tryAcquire("com.example.camera"))
        gate.release("com.example.camera")

        assertTrue(gate.tryAcquire("com.example.camera"))
    }

    @Test
    fun blankDestinationIsNeverAccepted() {
        val gate = HomeAppLaunchGate(nowMillis = { 100L })

        assertFalse(gate.tryAcquire("   "))
    }
}
