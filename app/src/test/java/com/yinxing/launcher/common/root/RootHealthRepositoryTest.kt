package com.yinxing.launcher.common.root

import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.assertEquals
import org.junit.Test

class RootHealthRepositoryTest {

    @Test
    fun nonZeroStatusCommandMapsToRootUnavailable() = runBlocking {
        val repository = RootHealthRepository(
            FakeRunner(status = RootCommandResult(exitCode = 127, output = "not found"))
        )

        assertEquals(RootHealthState.ROOT_UNAVAILABLE, repository.query().state)
    }

    @Test
    fun timedOutStatusCommandMapsToRootUnavailable() = runBlocking {
        val repository = RootHealthRepository(
            FakeRunner(status = RootCommandResult(exitCode = -1, output = "", timedOut = true))
        )

        assertEquals(RootHealthState.ROOT_UNAVAILABLE, repository.query().state)
    }

    @Test
    fun validStatusCommandReturnsParsedSnapshot() = runBlocking {
        val repository = RootHealthRepository(
            FakeRunner(status = RootCommandResult(exitCode = 0, output = healthyOutput()))
        )

        assertEquals(RootHealthState.HEALTHY, repository.query().state)
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
        schema=2
        version=1.10.0-root-preview.3
        module=active
        guard=running
        accessibility=enabled
        home=owned
        doze=owned
        cleanup=ready
        last_repair=ok
    """.trimIndent() + "\n"
}
