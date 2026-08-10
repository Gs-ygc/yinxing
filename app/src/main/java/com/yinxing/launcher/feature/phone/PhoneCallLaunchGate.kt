package com.yinxing.launcher.feature.phone

import android.content.Intent
import android.net.Uri
import android.os.SystemClock

/**
 * Prevents an elderly user's repeated touch from creating duplicate call intents.
 * The gate is deliberately global to the call page and uses one short cooldown.
 */
internal class PhoneCallLaunchGate(
    private val nowMillis: () -> Long = SystemClock::elapsedRealtime,
    private val cooldownMillis: Long = DEFAULT_COOLDOWN_MILLIS
) {
    private var lastAcceptedAt: Long? = null

    fun tryAcquire(rawNumber: String): Boolean {
        val number = rawNumber.trim()
        if (number.isEmpty()) return false

        val now = nowMillis()
        val previous = lastAcceptedAt
        val withinCooldown = previous != null &&
            now >= previous &&
            now - previous < cooldownMillis
        if (withinCooldown) return false

        lastAcceptedAt = now
        return true
    }

    companion object {
        const val DEFAULT_COOLDOWN_MILLIS = 1_200L
    }
}

internal object PhoneCallIntentFactory {
    fun direct(number: String): Intent = Intent(
        Intent.ACTION_CALL,
        Uri.fromParts("tel", number, null)
    )

    fun dialer(number: String): Intent = Intent(
        Intent.ACTION_DIAL,
        Uri.fromParts("tel", number, null)
    )
}
