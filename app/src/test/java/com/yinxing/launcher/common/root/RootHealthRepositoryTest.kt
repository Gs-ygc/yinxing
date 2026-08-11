package com.yinxing.launcher.common.root

import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class RootHealthRepositoryTest {

    @Test
    fun nonZeroStatusCommandMapsToRootUnavailable() = runBlocking {
        val repository = RootHealthRepository(
            FakeRunner(status = RootCommandResult(exitCode = 127, output = "not found"))
        )

        val snapshot = repository.query()
        assertEquals(RootHealthState.ROOT_UNAVAILABLE, snapshot.state)
        assertEquals(RootFailureReason.SCRIPT_NOT_FOUND, snapshot.failureReason)
        assertEquals(127, snapshot.failureExitCode)
    }

    @Test
    fun timedOutStatusCommandMapsToRootUnavailable() = runBlocking {
        val repository = RootHealthRepository(
            FakeRunner(status = RootCommandResult(exitCode = -1, output = "", timedOut = true))
        )

        val snapshot = repository.query()
        assertEquals(RootHealthState.ROOT_UNAVAILABLE, snapshot.state)
        assertEquals(RootFailureReason.COMMAND_TIMEOUT, snapshot.failureReason)
    }

    @Test
    fun validStatusCommandReturnsParsedSnapshot() = runBlocking {
        val repository = RootHealthRepository(
            FakeRunner(status = RootCommandResult(exitCode = 0, output = healthyOutput()))
        )

        assertEquals(RootHealthState.HEALTHY, repository.query().state)
    }

    @Test
    fun malformedSuccessfulStatusIsReportedAsFormatFailure() = runBlocking {
        val repository = RootHealthRepository(
            FakeRunner(status = RootCommandResult(exitCode = 0, output = "schema=3\n"))
        )

        val snapshot = repository.query()

        assertEquals(RootHealthState.ROOT_UNAVAILABLE, snapshot.state)
        assertEquals(RootFailureReason.STATUS_FORMAT_INVALID, snapshot.failureReason)
    }

    @Test
    fun failedRecoveryStillReturnsFreshStatus() = runBlocking {
        val runner = FakeRunner(
            status = RootCommandResult(exitCode = 0, output = healthyOutput()),
            recover = RootCommandResult(exitCode = 1, output = "")
        )
        val result = RootHealthRepository(runner).recoverAndQuery()

        assertFalse(result.actionSucceeded)
        assertEquals(RootHealthState.HEALTHY, result.snapshot.state)
        assertTrue(runner.commands.contains(RootCommand.RECOVER))
        assertTrue(runner.commands.contains(RootCommand.STATUS))
    }

    @Test
    fun failedRecoveryPreservesActionFailureReasonAndExitCode() = runBlocking {
        val runner = FakeRunner(
            status = RootCommandResult(exitCode = 0, output = healthyOutput()),
            recover = RootCommandResult(exitCode = 42, output = "script failed")
        )

        val result = RootHealthRepository(runner).recoverAndQuery()

        assertFalse(result.actionSucceeded)
        assertEquals(RootFailureReason.COMMAND_FAILED, result.actionFailureReason)
        assertEquals(42, result.actionFailureExitCode)
    }

    @Test
    fun successfulRecoveryReturnsFreshStatus() = runBlocking {
        val runner = FakeRunner(
            status = RootCommandResult(exitCode = 0, output = healthyOutput()),
            recover = RootCommandResult(exitCode = 0, output = "repaired")
        )
        val result = RootHealthRepository(runner).recoverAndQuery()

        assertTrue(result.actionSucceeded)
        assertEquals(RootHealthState.HEALTHY, result.snapshot.state)
    }

    private class FakeRunner(
        private val status: RootCommandResult,
        private val recover: RootCommandResult = RootCommandResult(0, "")
    ) : RootCommandRunner {
        val commands = mutableListOf<RootCommand>()

        override fun run(command: RootCommand): RootCommandResult {
            commands += command
            return when (command) {
                RootCommand.STATUS -> status
                RootCommand.RECOVER -> recover
                RootCommand.KIOSK_HOME -> RootCommandResult(0, "")
            }
        }
    }

    private fun healthyOutput(): String = """
        schema=3
        version=1.10.0-root-preview.3
        module=active
        guard=running
        accessibility=enabled
        home=owned
        home_foreground=verified
        doze=owned
        cleanup=ready
        last_repair=ok
    """.trimIndent() + "\n"
}
