package com.yinxing.launcher.common.root

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

internal data class RootRecoveryResult(
    val actionSucceeded: Boolean,
    val snapshot: RootHealthSnapshot
)

internal class RootHealthRepository(
    private val runner: RootCommandRunner
) {
    suspend fun query(): RootHealthSnapshot = withContext(Dispatchers.IO) {
        readSnapshot()
    }

    suspend fun recoverAndQuery(): RootRecoveryResult = withContext(Dispatchers.IO) {
        val actionResult = runCommand(RootCommand.RECOVER)
        RootRecoveryResult(
            actionSucceeded = actionResult?.isSuccessful == true,
            snapshot = readSnapshot()
        )
    }

    private fun readSnapshot(): RootHealthSnapshot {
        val result = runCommand(RootCommand.STATUS) ?: return RootHealthSnapshot.unavailable()
        if (!result.isSuccessful) {
            return RootHealthSnapshot.unavailable()
        }
        return RootHealthSnapshot.parse(result.output) ?: RootHealthSnapshot.unavailable()
    }

    private fun runCommand(command: RootCommand): RootCommandResult? {
        return try {
            runner.run(command)
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (_: Exception) {
            null
        }
    }

    private val RootCommandResult.isSuccessful: Boolean
        get() = exitCode == 0 && !timedOut && !outputLimitExceeded
}
