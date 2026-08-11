package com.yinxing.launcher.common.root

import java.io.ByteArrayOutputStream
import java.io.IOException
import java.nio.charset.StandardCharsets
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference
import kotlin.concurrent.thread

internal const val KERNEL_SU_EXECUTABLE = "/system/bin/su"

internal enum class RootCommand(
    val shellPath: String,
    val timeoutMillis: Long
) {
    STATUS(
        shellPath = "/data/adb/modules/yinxing_guard/bin/status.sh",
        timeoutMillis = 3_000L
    ),
    RECOVER(
        shellPath = "/data/adb/modules/yinxing_guard/action.sh",
        timeoutMillis = 20_000L
    ),
    KIOSK_HOME(
        shellPath = "/data/adb/modules/yinxing_guard/bin/kiosk-home.sh",
        timeoutMillis = 15_000L
    )
}

internal enum class RootFailureReason {
    SU_NOT_FOUND,
    SU_EXECUTION_BLOCKED,
    SU_START_FAILED,
    SU_AUTHORIZATION_DENIED,
    SCRIPT_NOT_FOUND,
    SCRIPT_EXECUTION_BLOCKED,
    COMMAND_TIMEOUT,
    COMMAND_FAILED,
    OUTPUT_LIMIT_EXCEEDED,
    STATUS_FORMAT_INVALID,
    UNKNOWN
}

internal data class RootCommandResult(
    val exitCode: Int,
    val output: String,
    val timedOut: Boolean = false,
    val outputLimitExceeded: Boolean = false,
    internal val failureReasonOverride: RootFailureReason? = null
) {
    val failureReason: RootFailureReason?
        get() = failureReasonOverride ?: classifyRootFailure(
            exitCode = exitCode,
            output = output,
            timedOut = timedOut,
            outputLimitExceeded = outputLimitExceeded
        )
}

internal val RootCommandResult.isSuccessful: Boolean
    get() = exitCode == 0 && !timedOut && !outputLimitExceeded

internal fun interface RootCommandRunner {
    fun run(command: RootCommand): RootCommandResult
}

internal class SuRootCommandRunner(
    private val timeoutMillis: Long? = null,
    private val maxOutputBytes: Int = MAX_OUTPUT_BYTES,
    private val suExecutable: String = KERNEL_SU_EXECUTABLE
) : RootCommandRunner {

    init {
        require(timeoutMillis == null || timeoutMillis > 0) { "timeoutMillis must be positive" }
        require(maxOutputBytes > 0) { "maxOutputBytes must be positive" }
        require(suExecutable.isNotBlank()) { "suExecutable must not be blank" }
    }

    override fun run(command: RootCommand): RootCommandResult {
        val process = try {
            ProcessBuilder(suExecutable, "-c", command.shellPath)
                .redirectErrorStream(true)
                .start()
        } catch (error: IOException) {
            return RootCommandResult(
                exitCode = -1,
                output = "",
                failureReasonOverride = classifySuStartFailure(error.message)
            )
        } catch (_: SecurityException) {
            return RootCommandResult(
                exitCode = -1,
                output = "",
                failureReasonOverride = RootFailureReason.SU_EXECUTION_BLOCKED
            )
        }

        val readResult = AtomicReference(BoundedReadResult())
        val reader = thread(name = "YinxingRootOutput", isDaemon = true) {
            readResult.set(readBoundedOutput(process, maxOutputBytes))
        }

        val commandTimeoutMillis = timeoutMillis ?: command.timeoutMillis
        val finished = try {
            process.waitFor(commandTimeoutMillis, TimeUnit.MILLISECONDS)
        } catch (_: InterruptedException) {
            Thread.currentThread().interrupt()
            false
        }
        if (!finished) {
            terminateProcess(process)
        }
        closeAndJoin(process, reader, waitForReader = finished)

        val output = readResult.get()
        return RootCommandResult(
            exitCode = if (finished) process.exitValueSafely() else -1,
            output = output.text,
            timedOut = !finished,
            outputLimitExceeded = output.limitExceeded
        )
    }

    private fun readBoundedOutput(process: Process, limit: Int): BoundedReadResult {
        val buffer = ByteArray(1024)
        val output = ByteArrayOutputStream()
        var limitExceeded = false
        try {
            process.inputStream.use { stream ->
                while (true) {
                    val count = stream.read(buffer)
                    if (count < 0) {
                        break
                    }
                    val remaining = limit - output.size()
                    if (remaining <= 0) {
                        limitExceeded = true
                        terminateProcess(process)
                        break
                    }
                    val copied = minOf(count, remaining)
                    output.write(buffer, 0, copied)
                    if (copied != count) {
                        limitExceeded = true
                        terminateProcess(process)
                        break
                    }
                }
            }
        } catch (_: IOException) {
            // A process timeout or forced stop can close the stream while it is being read.
        }
        return BoundedReadResult(
            text = output.toString(StandardCharsets.UTF_8.name()),
            limitExceeded = limitExceeded
        )
    }

    private fun terminateProcess(process: Process) {
        process.destroy()
        if (waitForExit(process, TERMINATION_GRACE_MILLIS)) {
            return
        }
        forceDestroy(process)
        waitForExit(process, TERMINATION_GRACE_MILLIS)
    }

    /** destroyForcibly was added after the app's minSdk; use it when available. */
    private fun forceDestroy(process: Process) {
        try {
            Process::class.java.getMethod("destroyForcibly").invoke(process)
        } catch (_: ReflectiveOperationException) {
            process.destroy()
        } catch (_: SecurityException) {
            process.destroy()
        } catch (_: LinkageError) {
            process.destroy()
        }
    }

    private fun waitForExit(process: Process, timeout: Long): Boolean {
        return try {
            process.waitFor(timeout, TimeUnit.MILLISECONDS)
        } catch (_: InterruptedException) {
            Thread.currentThread().interrupt()
            false
        }
    }

    private fun closeAndJoin(process: Process, reader: Thread, waitForReader: Boolean) {
        if (waitForReader) {
            joinReader(reader, READER_JOIN_MILLIS)
        }
        listOf(process.inputStream, process.errorStream, process.outputStream).forEach { stream ->
            try {
                stream.close()
            } catch (_: IOException) {
            }
        }
        if (reader.isAlive) {
            joinReader(reader, READER_JOIN_AFTER_CLOSE_MILLIS)
        }
        if (reader.isAlive) {
            reader.interrupt()
        }
    }

    private fun joinReader(reader: Thread, timeout: Long) {
        try {
            reader.join(timeout)
        } catch (_: InterruptedException) {
            Thread.currentThread().interrupt()
        }
    }

    private fun Process.exitValueSafely(): Int {
        return try {
            exitValue()
        } catch (_: IllegalThreadStateException) {
            -1
        }
    }

    private data class BoundedReadResult(
        val text: String = "",
        val limitExceeded: Boolean = false
    )

    private companion object {
        const val MAX_OUTPUT_BYTES = 16 * 1024
        const val TERMINATION_GRACE_MILLIS = 100L
        const val READER_JOIN_MILLIS = 250L
        const val READER_JOIN_AFTER_CLOSE_MILLIS = 100L
    }
}

private fun classifyRootFailure(
    exitCode: Int,
    output: String,
    timedOut: Boolean,
    outputLimitExceeded: Boolean
): RootFailureReason? {
    if (timedOut) return RootFailureReason.COMMAND_TIMEOUT
    if (outputLimitExceeded) return RootFailureReason.OUTPUT_LIMIT_EXCEEDED
    if (exitCode == 0) return null

    val normalizedOutput = output.lowercase()
    val guardPathMentioned = normalizedOutput.contains("/data/adb/modules/yinxing_guard/")
    val accessDenied = listOf(
        "permission denied",
        "not allowed",
        "not granted",
        "unauthorized",
        "access denied"
    ).any(normalizedOutput::contains)
    if (guardPathMentioned && accessDenied) {
        return RootFailureReason.SCRIPT_EXECUTION_BLOCKED
    }
    if (accessDenied) {
        return RootFailureReason.SU_AUTHORIZATION_DENIED
    }
    if (exitCode == 127 || normalizedOutput.contains("not found")) {
        return RootFailureReason.SCRIPT_NOT_FOUND
    }
    return RootFailureReason.COMMAND_FAILED
}

private fun classifySuStartFailure(message: String?): RootFailureReason {
    val normalizedMessage = message.orEmpty().lowercase()
    return when {
        normalizedMessage.contains("no such file") || normalizedMessage.contains("error=2") ->
            RootFailureReason.SU_NOT_FOUND
        normalizedMessage.contains("permission denied") ||
            normalizedMessage.contains("operation not permitted") ||
            normalizedMessage.contains("error=13") -> RootFailureReason.SU_EXECUTION_BLOCKED
        else -> RootFailureReason.SU_START_FAILED
    }
}
