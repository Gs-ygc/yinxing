package com.yinxing.launcher.common.root

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runInterruptible

internal data class RootRecoveryResult(
    val actionSucceeded: Boolean,
    val snapshot: RootHealthSnapshot,
    val actionFailureReason: RootFailureReason? = null,
    val actionFailureExitCode: Int? = null,
    val actionFailureEvidence: RootFailureEvidence? = null
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
                ?.takeIf { it >= 0 },
            actionFailureEvidence = actionResult
                .takeUnless { it.isSuccessful }
                ?.failureEvidence(RootCommand.RECOVER)
        )
    }

    private fun readSnapshot(): RootHealthSnapshot {
        val result = runCommand(RootCommand.STATUS)
        if (!result.isSuccessful) {
            return RootHealthSnapshot.unavailable(
                reason = result.failureReason ?: RootFailureReason.UNKNOWN,
                exitCode = result.exitCode.takeIf { it >= 0 },
                evidence = result.failureEvidence(RootCommand.STATUS)
            )
        }
        return RootHealthSnapshot.parse(result.output)
            ?: RootHealthSnapshot.unavailable(
                reason = RootFailureReason.STATUS_FORMAT_INVALID,
                exitCode = result.exitCode.takeIf { it >= 0 },
                evidence = RootFailureEvidence.create(
                    command = RootCommand.STATUS,
                    stage = RootFailureStage.STATUS_PARSE,
                    exitCode = result.exitCode.takeIf { it >= 0 },
                    detail = result.output
                )
            )
    }

    private fun runCommand(command: RootCommand): RootCommandResult {
        return try {
            runner.run(command)
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (error: Exception) {
            RootCommandResult(
                exitCode = -1,
                output = "",
                evidence = RootFailureEvidence.create(
                    command = command,
                    stage = RootFailureStage.RUNNER_EXCEPTION,
                    detail = error.diagnosticText()
                ),
                failureReasonOverride = RootFailureReason.UNKNOWN
            )
        }
    }

    private fun RootCommandResult.failureEvidence(command: RootCommand): RootFailureEvidence {
        return evidence ?: RootFailureEvidence.create(
            command = command,
            stage = RootFailureStage.COMMAND_RUN,
            exitCode = exitCode.takeIf { it >= 0 },
            detail = output
        )
    }

    private fun Throwable.diagnosticText(): String = buildString {
        append(this@diagnosticText::class.java.simpleName)
        message?.takeIf(String::isNotBlank)?.let { append(": ").append(it) }
    }
}
