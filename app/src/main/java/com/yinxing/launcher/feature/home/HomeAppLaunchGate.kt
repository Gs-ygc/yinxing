package com.yinxing.launcher.feature.home

import android.os.SystemClock

internal class HomeAppLaunchGate(
    private val nowMillis: () -> Long = SystemClock::elapsedRealtime,
    private val cooldownMillis: Long = DEFAULT_COOLDOWN_MILLIS
) {
    private val lastAcceptedAt = mutableMapOf<String, Long>()

    fun tryAcquire(rawPackageName: String): Boolean {
        val packageName = rawPackageName.trim()
        if (packageName.isEmpty()) return false

        val now = nowMillis()
        val previous = lastAcceptedAt[packageName]
        val withinCooldown = previous != null &&
            now >= previous &&
            now - previous < cooldownMillis
        if (withinCooldown) return false

        lastAcceptedAt[packageName] = now
        return true
    }

    fun release(rawPackageName: String) {
        val packageName = rawPackageName.trim()
        if (packageName.isNotEmpty()) {
            lastAcceptedAt.remove(packageName)
        }
    }

    companion object {
        private const val DEFAULT_COOLDOWN_MILLIS = 1_200L
    }
}
