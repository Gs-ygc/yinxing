package com.yinxing.launcher.feature.home

import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.view.isVisible
import com.yinxing.launcher.R
import com.yinxing.launcher.data.contact.Contact

class HomeTrustedContactsController(
    private val root: View
) {
    private val itemContainer: LinearLayout = root.findViewById(R.id.layout_trusted_call_items)
    private val allButton: View = root.findViewById(R.id.btn_trusted_calls_all)
    private var onCallClick: (Contact) -> Unit = {}
    private var onOpenAllClick: () -> Unit = {}

    init {
        allButton.setOnClickListener { onOpenAllClick() }
    }

    fun setOnCallClick(listener: (Contact) -> Unit) {
        onCallClick = listener
    }

    fun setOnOpenAllClick(listener: () -> Unit) {
        onOpenAllClick = listener
    }

    fun render(contacts: List<Contact>) {
        val callableContacts = HomeTrustedContactPolicy.select(contacts)
        itemContainer.removeAllViews()
        root.isVisible = callableContacts.isNotEmpty()
        allButton.isVisible = callableContacts.isNotEmpty()
        if (callableContacts.isEmpty()) {
            return
        }

        callableContacts.forEachIndexed { index, contact ->
            val item = LayoutInflater.from(root.context)
                .inflate(R.layout.item_home_trusted_call, itemContainer, false)
            bindItem(item, contact)
            val params = item.layoutParams as LinearLayout.LayoutParams
            if (callableContacts.size == 1) {
                params.width = ViewGroup.LayoutParams.MATCH_PARENT
                params.weight = 0f
            } else {
                params.width = 0
                params.weight = 1f
            }
            params.marginEnd = if (index == callableContacts.lastIndex) 0 else dp(8)
            item.layoutParams = params
            itemContainer.addView(item)
        }
    }

    private fun bindItem(item: View, contact: Contact) {
        val displayName = contact.displayName.trim().ifEmpty {
            item.context.getString(R.string.contact_name_placeholder)
        }
        val description = item.context.getString(R.string.contact_call_description, displayName)
        item.contentDescription = description
        item.importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_YES
        item.isFocusable = true
        item.setOnClickListener { onCallClick(contact) }
        item.findViewById<ImageView>(R.id.iv_trusted_call_icon)
            .importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
        item.findViewById<TextView>(R.id.tv_trusted_call_name).apply {
            text = displayName
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
        }
        item.findViewById<TextView>(R.id.tv_trusted_call_number).apply {
            text = formatPhoneNumber(contact.phoneNumber.orEmpty())
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
        }
    }

    private fun dp(value: Int): Int = (value * root.resources.displayMetrics.density).toInt()

    private fun formatPhoneNumber(raw: String): String {
        val digits = raw.filter { it.isDigit() }
        return when {
            digits.length == 11 -> "${digits.substring(0, 3)} ${digits.substring(3, 7)} ${digits.substring(7)}"
            digits.length == 7 -> "${digits.substring(0, 3)}-${digits.substring(3)}"
            digits.length == 8 -> "${digits.substring(0, 4)}-${digits.substring(4)}"
            else -> raw
        }
    }
}
