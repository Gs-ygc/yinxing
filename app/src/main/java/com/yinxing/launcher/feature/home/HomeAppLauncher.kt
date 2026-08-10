package com.yinxing.launcher.feature.home

import android.content.Intent

internal class HomeAppLauncher(
    private val resolveLaunchIntent: (String) -> Intent?,
    private val launchIntent: (Intent) -> Unit,
    private val onUnavailable: (HomeAppItem) -> Unit,
    private val gate: HomeAppLaunchGate = HomeAppLaunchGate()
) {
    fun open(item: HomeAppItem): Boolean {
        val packageName = item.packageName.trim()
        if (packageName.isEmpty()) {
            onUnavailable(item)
            return false
        }
        if (!gate.tryAcquire(packageName)) {
            return false
        }

        val intent = try {
            resolveLaunchIntent(packageName)
        } catch (_: Exception) {
            null
        }
        if (intent == null) {
            gate.release(packageName)
            onUnavailable(item)
            return false
        }

        return try {
            launchIntent(intent)
            true
        } catch (_: Exception) {
            gate.release(packageName)
            onUnavailable(item)
            false
        }
    }
}
