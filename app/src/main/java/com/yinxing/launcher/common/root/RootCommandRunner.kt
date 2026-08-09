package com.yinxing.launcher.common.root

import java.io.ByteArrayOutputStream
import java.io.IOException
import java.nio.charset.StandardCharsets
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference
import kotlin.concurrent.thread

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
        timeoutMillis = 12_000L
    ),
    KIOSK_HOME(
        shellPath = "/data/adb/modules/yinxing_guard/bin/kiosk-home.sh",
        timeoutMillis = 1_200L
    )
}

internal data class RootCommandResult(
    val exitCode: Int,
    val output: String,
    val timedOut: Boolean = false,
    val outputLimitExceeded: Boolean = false
)

internal val RootCommandResult.isSuccessful: Boolean
    get() = exitCode == 0 && !timedOut && !outputLimitExceeded

internal fun interface RootCommandRunner {
    fun run(command: RootCommand): RootCommandResult
}

internal class SuRootCommandRunner(
    private val timeoutMillis: Long? = null,
    private val maxOutputBytes: Int = MAX_OUTPUT_BYTES,
    private val suExecutable: String = "su"
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
        } catch (_: IOException) {
            return RootCommandResult(exitCode = -1, output = "")
        } catch (_: SecurityException) {
            return RootCommandResult(exitCode = -1, output = "")
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
