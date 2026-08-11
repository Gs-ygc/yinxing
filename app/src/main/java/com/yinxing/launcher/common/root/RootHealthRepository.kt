package com.yinxing.launcher.common.root

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runInterruptible

internal data class RootRecoveryResult(
    val actionSucceeded: Boolean,
    val snapshot: RootHealthSnapshot,
    val actionFailureReason: RootFailureReason? = null,
    val actionFailureExitCode: Int? = null
)

internal class RootHealthRepository(
    private val runner: RootCommandRunner
) {
    suspend fun query(): RootHealthSnapshot = runInterruptible(Dispatchers.IO) {
        readSnapshot()
    }

    suspend fun recoverAndQuery(): RootRecoveryResult = runInterruptible(Dispatchers.IO) {
        val actionResult = runCommand(RootCommand.RECOVER)
        RootRecoveryResult(
            actionSucceeded = actionResult.isSuccessful,
            snapshot = readSnapshot(),
            actionFailureReason = actionResult
                .takeUnless { it.isSuccessful }
                ?.failureReason,
            actionFailureExitCode = actionResult
                .takeUnless { it.isSuccessful }
                ?.exitCode
                ?.takeIf { it >= 0 }
        )
    }

    private fun readSnapshot(): RootHealthSnapshot {
        val result = runCommand(RootCommand.STATUS)
        if (!result.isSuccessful) {
            return RootHealthSnapshot.unavailable(
                reason = result.failureReason ?: RootFailureReason.UNKNOWN,
                exitCode = result.exitCode.takeIf { it >= 0 }
            )
        }
        return RootHealthSnapshot.parse(result.output)
            ?: RootHealthSnapshot.unavailable(RootFailureReason.STATUS_FORMAT_INVALID)
    }

    private fun runCommand(command: RootCommand): RootCommandResult {
        return try {
            runner.run(command)
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (_: Exception) {
            RootCommandResult(
                exitCode = -1,
                output = "",
                failureReasonOverride = RootFailureReason.UNKNOWN
            )
        }
    }
}
