package com.yinxing.launcher.common.root

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runInterruptible

internal fun interface RootHomeLauncher {
    suspend fun launchHome(): Boolean
}

internal class SuRootHomeLauncher(
    private val runner: RootCommandRunner = SuRootCommandRunner()
) : RootHomeLauncher {

    override suspend fun launchHome(): Boolean = runInterruptible(Dispatchers.IO) {
        try {
            runner.run(RootCommand.KIOSK_HOME).isSuccessful
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (_: Exception) {
            false
        }
    }
}
