package com.yinxing.launcher.common.root

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class RootHealthRepositoryTest {

    @Test
    fun nonZeroStatusCommandMapsToRootUnavailable() = runBlocking {
        val evidence = RootFailureEvidence.create(
            command = RootCommand.STATUS,
            stage = RootFailureStage.COMMAND_RUN,
            exitCode = 127,
            detail = "status.sh: not found"
        )
        val repository = RootHealthRepository(
            FakeRunner(
                status = RootCommandResult(
                    exitCode = 127,
                    output = "/data/adb/modules/yinxing_guard/bin/status.sh: not found",
                    evidence = evidence
                )
            )
        )

        val snapshot = repository.query()
        assertEquals(RootHealthState.ROOT_UNAVAILABLE, snapshot.state)
        assertEquals(RootFailureReason.SCRIPT_NOT_FOUND, snapshot.failureReason)
        assertEquals(127, snapshot.failureExitCode)
        assertEquals(evidence, snapshot.failureEvidence)
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
        assertEquals(RootFailureStage.STATUS_PARSE, snapshot.failureEvidence?.stage)
        assertEquals(RootCommand.STATUS, snapshot.failureEvidence?.command)
        assertTrue(snapshot.failureEvidence?.detail.orEmpty().contains("schema=3"))
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
        val actionEvidence = RootFailureEvidence.create(
            command = RootCommand.RECOVER,
            stage = RootFailureStage.COMMAND_RUN,
            exitCode = 42,
            detail = "script failed"
        )
        val runner = FakeRunner(
            status = RootCommandResult(exitCode = 0, output = healthyOutput()),
            recover = RootCommandResult(
                exitCode = 42,
                output = "script failed",
                evidence = actionEvidence
            )
        )

        val result = RootHealthRepository(runner).recoverAndQuery()

        assertFalse(result.actionSucceeded)
        assertEquals(RootFailureReason.COMMAND_FAILED, result.actionFailureReason)
        assertEquals(42, result.actionFailureExitCode)
        assertEquals(actionEvidence, result.actionFailureEvidence)
        assertEquals(RootHealthState.HEALTHY, result.snapshot.state)
        assertEquals(listOf(RootCommand.RECOVER, RootCommand.STATUS), runner.commands)
    }

    @Test
    fun runnerExceptionRetainsAttemptedCommandClassAndMessage() = runBlocking {
        val repository = RootHealthRepository(
            RootCommandRunner { throw IllegalStateException("runner exploded") }
        )

        val snapshot = repository.query()

        assertEquals(RootHealthState.ROOT_UNAVAILABLE, snapshot.state)
        assertEquals(RootFailureReason.UNKNOWN, snapshot.failureReason)
        assertEquals(RootFailureStage.RUNNER_EXCEPTION, snapshot.failureEvidence?.stage)
        assertEquals(RootCommand.STATUS, snapshot.failureEvidence?.command)
        assertEquals(null, snapshot.failureEvidence?.exitCode)
        assertTrue(snapshot.failureEvidence?.invocation.orEmpty().contains("/system/bin/su -c"))
        assertTrue(snapshot.failureEvidence?.detail.orEmpty().contains("IllegalStateException"))
        assertTrue(snapshot.failureEvidence?.detail.orEmpty().contains("runner exploded"))
    }

    @Test
    fun runnerCancellationIsRethrownWithoutMapping() = runBlocking {
        val cancellation = CancellationException("cancelled")
        val repository = RootHealthRepository(RootCommandRunner { throw cancellation })

        try {
            repository.query()
            fail("expected CancellationException")
        } catch (actual: CancellationException) {
            assertEquals(cancellation.message, actual.message)
        }
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
