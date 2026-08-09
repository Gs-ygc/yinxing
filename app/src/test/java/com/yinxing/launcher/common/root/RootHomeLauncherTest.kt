package com.yinxing.launcher.common.root

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

@OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)
class RootHomeLauncherTest {

    @Test
    fun successfulCommandReturnsTrueAndUsesKioskPath() = runTest {
        val runner = RecordingRunner(RootCommandResult(exitCode = 0, output = "launched"))

        assertTrue(SuRootHomeLauncher(runner).launchHome())
        assertEquals(listOf(RootCommand.KIOSK_HOME), runner.commands)
    }

    @Test
    fun unsuccessfulCommandReturnsFalse() = runTest {
        val runner = RecordingRunner(RootCommandResult(exitCode = 1, output = ""))

        assertFalse(SuRootHomeLauncher(runner).launchHome())
        assertEquals(listOf(RootCommand.KIOSK_HOME), runner.commands)
    }

    @Test
    fun cancellationExceptionIsNotConvertedToRootFailure() = runTest {
        val runner = RootCommandRunner { throw CancellationException("cancelled") }

        try {
            SuRootHomeLauncher(runner).launchHome()
            throw AssertionError("expected cancellation")
        } catch (cancelled: CancellationException) {
            assertEquals("cancelled", cancelled.message)
        }
    }

    private class RecordingRunner(
        private val result: RootCommandResult
    ) : RootCommandRunner {
        val commands = mutableListOf<RootCommand>()

        override fun run(command: RootCommand): RootCommandResult {
            commands += command
            return result
        }
    }
}
