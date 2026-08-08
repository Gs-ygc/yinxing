package com.google.android.accessibility.selecttospeak

import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Test

@OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)
class VideoCallStepClockTest {

    @Test
    fun processTickIsDroppedWhenTheOwningSessionIsNoLongerCurrent() = runTest {
        var sessionCurrent = true
        var processTicks = 0
        val clock = VideoCallStepClock(
            scope = this,
            onProcessTick = { processTicks++ },
            onTimeoutFailure = {},
            sessionStillActive = { sessionCurrent }
        )

        clock.scheduleProcess(100L) { sessionCurrent }
        sessionCurrent = false

        advanceTimeBy(100L)
        runCurrent()

        assertEquals(0, processTicks)
    }

    @Test
    fun processTickRunsWhenItsOwningSessionRemainsCurrent() = runTest {
        var sessionCurrent = true
        var processTicks = 0
        val clock = VideoCallStepClock(
            scope = this,
            onProcessTick = { processTicks++ },
            onTimeoutFailure = {},
            sessionStillActive = { sessionCurrent }
        )

        clock.scheduleProcess(100L) { sessionCurrent }
        advanceTimeBy(100L)
        runCurrent()

        assertEquals(1, processTicks)
    }

    @Test
    fun totalTimeoutIsDroppedWhenItsOwningSessionIsReplaced() = runTest {
        var sessionToken = 1
        var failures = 0
        val clock = VideoCallStepClock(
            scope = this,
            onProcessTick = {},
            onTimeoutFailure = { failures++ },
            sessionStillActive = { true }
        )

        clock.armTotalTimeout(100L, { "stale" }) { sessionToken == 1 }
        sessionToken = 2

        advanceTimeBy(100L)
        runCurrent()

        assertEquals(0, failures)
    }

    @Test
    fun stepTimeoutIsDroppedWhenItsOwningSessionIsReplaced() = runTest {
        var sessionToken = 1
        var failures = 0
        val clock = VideoCallStepClock(
            scope = this,
            onProcessTick = {},
            onTimeoutFailure = { failures++ },
            sessionStillActive = { true }
        )

        clock.armStepTimeout(100L, "stale") { sessionToken == 1 }
        sessionToken = 2

        advanceTimeBy(100L)
        runCurrent()

        assertEquals(0, failures)
    }
}
