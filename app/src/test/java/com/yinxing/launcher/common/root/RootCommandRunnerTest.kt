package com.yinxing.launcher.common.root

import java.nio.charset.StandardCharsets
import java.nio.file.Files
import kotlin.system.measureTimeMillis
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class RootCommandRunnerTest {

    @Test
    fun usesOnlyTheFixedStatusAndRecoveryPaths() {
        withFakeSu(
            """
            case "${'$'}2" in
                /data/adb/modules/yinxing_guard/bin/status.sh) printf 'status-ok\n' ;;
                /data/adb/modules/yinxing_guard/action.sh) printf 'recover-ok\n' ;;
                *) exit 64 ;;
            esac
            """.trimIndent()
        ) { executable ->
            val runner = SuRootCommandRunner(
                timeoutMillis = 1_000,
                maxOutputBytes = 1_024,
                suExecutable = executable.toString()
            )

            val status = runner.run(RootCommand.STATUS)
            val recovery = runner.run(RootCommand.RECOVER)

            assertEquals(0, status.exitCode)
            assertEquals("status-ok\n", status.output)
            assertEquals(0, recovery.exitCode)
            assertEquals("recover-ok\n", recovery.output)
        }
    }

    @Test
    fun timeoutForciblyStopsAStuckSuProcessWithinBound() {
        withFakeSu("exec /bin/sleep 30") { executable ->
            val runner = SuRootCommandRunner(
                timeoutMillis = 100,
                maxOutputBytes = 1_024,
                suExecutable = executable.toString()
            )

            lateinit var result: RootCommandResult
            val elapsed = measureTimeMillis {
                result = runner.run(RootCommand.STATUS)
            }

            assertTrue(result.timedOut)
            assertEquals(-1, result.exitCode)
            assertTrue("timeout cleanup took ${elapsed}ms", elapsed < 1_500)
        }
    }

    @Test
    fun outputLimitStopsAnUnboundedSuProcess() {
        withFakeSu(
            """
            i=0
            while [ "${'$'}i" -lt 256 ]; do
                printf '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'
                i=${'$'}((i + 1))
            done
            """.trimIndent()
        ) { executable ->
            val runner = SuRootCommandRunner(
                timeoutMillis = 1_000,
                maxOutputBytes = 1_024,
                suExecutable = executable.toString()
            )

            val result = runner.run(RootCommand.STATUS)

            assertTrue(result.outputLimitExceeded)
            assertFalse(result.timedOut)
            assertTrue(result.output.toByteArray(StandardCharsets.UTF_8).size <= 1_024)
        }
    }

    private fun <T> withFakeSu(body: String, block: (java.nio.file.Path) -> T): T {
        val directory = Files.createTempDirectory("yinxing-su-runner")
        val executable = directory.resolve("su")
        val script = "#!/bin/sh\nset -u\n$body\n"
        Files.write(executable, script.toByteArray(StandardCharsets.UTF_8))
        check(executable.toFile().setExecutable(true))
        return try {
            block(executable)
        } finally {
            directory.toFile().deleteRecursively()
        }
    }
}
