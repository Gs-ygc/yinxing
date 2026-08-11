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
    fun kernelSuCompatibilityEntryUsesTheSystemSuPath() {
        assertEquals("/system/bin/su", KERNEL_SU_EXECUTABLE)
    }

    @Test
    fun missingSuIsReportedAsExecutableUnavailable() {
        val result = SuRootCommandRunner(
            timeoutMillis = 1_000,
            suExecutable = "/tmp/yinxing-su-that-does-not-exist"
        ).run(RootCommand.STATUS)

        assertEquals(RootFailureReason.SU_NOT_FOUND, result.failureReason)
    }

    @Test
    fun nonExecutableSuIsReportedAsExecutionBlocked() {
        val directory = Files.createTempDirectory("yinxing-blocked-su")
        val executable = directory.resolve("su")
        Files.write(executable, "#!/bin/sh\nexit 0\n".toByteArray(StandardCharsets.UTF_8))
        check(executable.toFile().setExecutable(false))
        try {
            val result = SuRootCommandRunner(
                timeoutMillis = 1_000,
                suExecutable = executable.toString()
            ).run(RootCommand.STATUS)

            assertEquals(RootFailureReason.SU_EXECUTION_BLOCKED, result.failureReason)
        } finally {
            directory.toFile().deleteRecursively()
        }
    }

    @Test
    fun permissionDeniedOutputIsReportedAsAuthorizationFailure() {
        withFakeSu("printf 'Permission denied\\n'; exit 1") { executable ->
            val result = SuRootCommandRunner(
                timeoutMillis = 1_000,
                suExecutable = executable.toString()
            ).run(RootCommand.STATUS)

            assertEquals(RootFailureReason.SU_AUTHORIZATION_DENIED, result.failureReason)
            assertEquals(1, result.exitCode)
        }
    }

    @Test
    fun guardScriptPermissionFailureIsNotReportedAsKernelSuAuthorizationFailure() {
        withFakeSu(
            "printf '/data/adb/modules/yinxing_guard/bin/status.sh: Permission denied\\n'; exit 126"
        ) { executable ->
            val result = SuRootCommandRunner(
                timeoutMillis = 1_000,
                suExecutable = executable.toString()
            ).run(RootCommand.STATUS)

            assertEquals(RootFailureReason.SCRIPT_EXECUTION_BLOCKED, result.failureReason)
            assertEquals(126, result.exitCode)
        }
    }

    @Test
    fun missingScriptOutputIsReportedSeparatelyFromAuthorization() {
        withFakeSu("printf '/data/adb/modules/yinxing_guard/bin/status.sh: not found\\n'; exit 127") { executable ->
            val result = SuRootCommandRunner(
                timeoutMillis = 1_000,
                suExecutable = executable.toString()
            ).run(RootCommand.STATUS)

            assertEquals(RootFailureReason.SCRIPT_NOT_FOUND, result.failureReason)
        }
    }

    @Test
    fun ordinaryNonZeroExitRetainsExitCodeAsCommandFailure() {
        withFakeSu("printf 'script failed\\n'; exit 42") { executable ->
            val result = SuRootCommandRunner(
                timeoutMillis = 1_000,
                suExecutable = executable.toString()
            ).run(RootCommand.STATUS)

            assertEquals(RootFailureReason.COMMAND_FAILED, result.failureReason)
            assertEquals(42, result.exitCode)
        }
    }

    @Test
    fun usesOnlyTheFixedStatusRecoveryAndKioskPaths() {
        withFakeSu(
            """
            case "${'$'}2" in
                /data/adb/modules/yinxing_guard/bin/status.sh) printf 'status-ok\n' ;;
                /data/adb/modules/yinxing_guard/action.sh) printf 'recover-ok\n' ;;
                /data/adb/modules/yinxing_guard/bin/kiosk-home.sh) printf 'kiosk-ok\n' ;;
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
            val kiosk = runner.run(RootCommand.KIOSK_HOME)

            assertEquals(0, status.exitCode)
            assertEquals("status-ok\n", status.output)
            assertEquals(0, recovery.exitCode)
            assertEquals("recover-ok\n", recovery.output)
            assertEquals(0, kiosk.exitCode)
            assertEquals("kiosk-ok\n", kiosk.output)
        }
    }

    @Test
    fun defaultRecoveryTimeoutCoversBoundedRebindConfirmation() {
        withFakeSu(
            """
            case "${'$'}2" in
                /data/adb/modules/yinxing_guard/action.sh) /bin/sleep 4 ;;
                *) exit 64 ;;
            esac
            """.trimIndent()
        ) { executable ->
            val runner = SuRootCommandRunner(
                maxOutputBytes = 1_024,
                suExecutable = executable.toString()
            )

            val result = runner.run(RootCommand.RECOVER)

            assertFalse("recovery hit the shared three-second timeout", result.timedOut)
            assertTrue(result.isSuccessful)
        }
    }

    @Test
    fun defaultKioskTimeoutCoversBoundedForegroundConfirmation() {
        withFakeSu(
            """
            case "${'$'}2" in
                /data/adb/modules/yinxing_guard/bin/kiosk-home.sh) /bin/sleep 4 ;;
                *) exit 64 ;;
            esac
            """.trimIndent()
        ) { executable ->
            val runner = SuRootCommandRunner(
                maxOutputBytes = 1_024,
                suExecutable = executable.toString()
            )

            val result = runner.run(RootCommand.KIOSK_HOME)

            assertFalse("bounded foreground confirmation hit the old kiosk timeout", result.timedOut)
            assertTrue(result.isSuccessful)
        }
    }

    @Test
    fun defaultStatusTimeoutRemainsBounded() {
        withFakeSu(
            """
            case "${'$'}2" in
                /data/adb/modules/yinxing_guard/bin/status.sh) /bin/sleep 4 ;;
                *) exit 64 ;;
            esac
            """.trimIndent()
        ) { executable ->
            val runner = SuRootCommandRunner(
                maxOutputBytes = 1_024,
                suExecutable = executable.toString()
            )

            val result = runner.run(RootCommand.STATUS)

            assertTrue(result.timedOut)
            assertFalse(result.isSuccessful)
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
            assertEquals(RootFailureReason.COMMAND_TIMEOUT, result.failureReason)
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
            assertEquals(RootFailureReason.OUTPUT_LIMIT_EXCEEDED, result.failureReason)
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
