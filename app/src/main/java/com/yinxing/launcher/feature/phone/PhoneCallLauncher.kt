package com.yinxing.launcher.feature.phone

import android.content.Intent
import com.yinxing.launcher.data.contact.Contact

internal class PhoneCallLauncher(
    private val hasCallPermission: () -> Boolean,
    private val requestPermission: (Contact) -> Unit,
    private val launchIntent: (Intent) -> Unit,
    private val showFallback: (Contact, Boolean) -> Unit,
    private val onCallLaunched: (Contact) -> Unit,
    private val gate: PhoneCallLaunchGate = PhoneCallLaunchGate()
) {
    private var pendingContact: Contact? = null

    val pendingContactOrNull: Contact?
        get() = pendingContact

    fun makeCall(contact: Contact) {
        val number = contact.phoneNumber?.takeIf { it.isNotBlank() } ?: return
        if (pendingContact != null) return

        if (!hasCallPermission()) {
            pendingContact = contact
            runCatching { requestPermission(contact) }
                .onFailure {
                    pendingContact = null
                    showFallback(contact, false)
                }
            return
        }

        launchDirectCall(contact, number)
    }

    fun onPermissionResult(granted: Boolean) {
        val contact = pendingContact ?: return
        pendingContact = null
        if (granted) {
            val number = contact.phoneNumber?.takeIf { it.isNotBlank() } ?: return
            launchDirectCall(contact, number)
        } else {
            showFallback(contact, false)
        }
    }

    fun restorePendingContact(contact: Contact) {
        if (!contact.phoneNumber.isNullOrBlank()) {
            pendingContact = contact
        }
    }

    private fun launchDirectCall(contact: Contact, number: String) {
        if (!gate.tryAcquire(number)) return
        runCatching { launchIntent(PhoneCallIntentFactory.direct(number)) }
            .onSuccess { onCallLaunched(contact) }
            .onFailure { showFallback(contact, true) }
    }
}
