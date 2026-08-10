package com.yinxing.launcher.feature.home

import com.yinxing.launcher.data.contact.Contact
import com.yinxing.launcher.data.contact.ContactStorage

object HomeTrustedContactPolicy {
    const val MAX_CONTACTS = 2

    fun select(
        contacts: List<Contact>,
        maxContacts: Int = MAX_CONTACTS
    ): List<Contact> {
        val limit = maxContacts.coerceAtLeast(0)
        return ContactStorage.sort(contacts.filter { it.phoneNumber?.isNotBlank() == true })
            .take(limit)
    }
}
