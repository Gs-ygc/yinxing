package com.yinxing.launcher.common.root

import java.io.ByteArrayOutputStream
import java.io.IOException
import java.nio.charset.StandardCharsets
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference
import kotlin.concurrent.thread

internal enum class RootCommand {
    STATUS,
    RECOVER;

    val shellPath: String
        get() = when (this) {
            STATUS -> "/data/adb/modules/yinxing_guard/bin/status.sh"
            RECOVER -> "/data/adb/modules/yinxing_guard/action.sh"
        }
}

internal data class RootCommandResult(
    val exitCode: Int,
    val output: String,
    val timedOut: Boolean = false,
    val outputLimitExceeded: Boolean = false
)

internal fun interface RootCommandRunner {
    fun run(command: RootCommand): RootCommandResult
}

internal class SuRootCommandRunner(
    private val timeoutMillis: Long = DEFAULT_TIMEOUT_MILLIS,
    private val maxOutputBytes: Int = MAX_OUTPUT_BYTES
) : RootCommandRunner {

    override fun run(command: RootCommand): RootCommandResult {
        val process = try {
            ProcessBuilder("su", "-c", command.shellPath)
                .redirectErrorStream(true)
                .start()
        } catch (_: IOException) {
            return RootCommandResult(exitCode = -1, output = "")
        } catch (_: SecurityException) {
            return RootCommandResult(exitCode = -1, output = "")
        }

        val readResult = AtomicReference(BoundedReadResult())
        val reader = thread(name = "YinxingRootOutput", isDaemon = true) {
            readResult.set(readBoundedOutput(process, maxOutputBytes))
        }

        val finished = try {
            process.waitFor(timeoutMillis, TimeUnit.MILLISECONDS)
        } catch (_: InterruptedException) {
            Thread.currentThread().interrupt()
            false
        }
        if (!finished) {
            process.destroy()
            if (!waitForExit(process, 250L)) {
                process.destroy()
            }
        }
        closeAndJoin(process, reader)

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
                        process.destroy()
                        break
                    }
                    val copied = minOf(count, remaining)
                    output.write(buffer, 0, copied)
                    if (copied != count) {
                        limitExceeded = true
                        process.destroy()
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

    private fun waitForExit(process: Process, timeout: Long): Boolean {
        return try {
            process.waitFor(timeout, TimeUnit.MILLISECONDS)
        } catch (_: InterruptedException) {
            Thread.currentThread().interrupt()
            false
        }
    }

    private fun closeAndJoin(process: Process, reader: Thread) {
        try {
            process.inputStream.close()
        } catch (_: IOException) {
        }
        try {
            reader.join(500L)
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
        const val DEFAULT_TIMEOUT_MILLIS = 3_000L
        const val MAX_OUTPUT_BYTES = 16 * 1024
    }
}
