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
            try {
                requestPermission(contact)
            } catch (_: Exception) {
                pendingContact = null
                openDialerOrFallback(contact, number, directCallFailed = false)
            }
            return
        }

        launchDirectCall(contact, number)
    }

    fun onPermissionResult(granted: Boolean) {
        val contact = pendingContact ?: return
        pendingContact = null
        val number = contact.phoneNumber?.takeIf { it.isNotBlank() } ?: return
        if (granted) {
            launchDirectCall(contact, number)
        } else {
            openDialerOrFallback(contact, number, directCallFailed = false)
        }
    }

    fun restorePendingContact(contact: Contact) {
        if (!contact.phoneNumber.isNullOrBlank()) {
            pendingContact = contact
        }
    }

    private fun launchDirectCall(contact: Contact, number: String) {
        if (!gate.tryAcquire(number)) return
        try {
            launchIntent(PhoneCallIntentFactory.direct(number))
        } catch (_: Exception) {
            openDialerOrFallback(contact, number, directCallFailed = true)
            return
        }
        onCallLaunched(contact)
    }

    private fun openDialerOrFallback(
        contact: Contact,
        number: String,
        directCallFailed: Boolean
    ) {
        try {
            launchIntent(PhoneCallIntentFactory.dialer(number))
        } catch (_: Exception) {
            showFallback(contact, directCallFailed)
        }
    }
}
