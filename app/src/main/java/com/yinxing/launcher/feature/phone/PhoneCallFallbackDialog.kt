package com.yinxing.launcher.feature.phone

import android.widget.TextView
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import com.google.android.material.card.MaterialCardView
import com.yinxing.launcher.R
import com.yinxing.launcher.data.contact.Contact

internal fun AppCompatActivity.showPhoneCallFallbackDialog(
    contact: Contact,
    directCallFailed: Boolean,
    onDialerFailure: (Throwable) -> Unit
): AlertDialog {
    val dialogView = layoutInflater.inflate(R.layout.dialog_call_permission_fallback, null)
    dialogView.findViewById<TextView>(R.id.tv_call_permission_title).text = getString(
        R.string.phone_call_permission_fallback_title,
        contact.displayName
    )
    dialogView.findViewById<TextView>(R.id.tv_call_permission_message).text = getString(
        if (directCallFailed) {
            R.string.phone_call_fallback_failed_message
        } else {
            R.string.phone_call_permission_fallback_message
        },
        contact.displayName
    )

    val dialog = AlertDialog.Builder(this).setView(dialogView).create()
    dialogView.findViewById<MaterialCardView>(R.id.btn_open_dialer).setOnClickListener {
        dialog.dismiss()
        val number = contact.phoneNumber?.takeIf { it.isNotBlank() } ?: return@setOnClickListener
        runCatching { startActivity(PhoneCallIntentFactory.dialer(number)) }
            .onFailure(onDialerFailure)
    }
    dialogView.findViewById<MaterialCardView>(R.id.btn_cancel_call).setOnClickListener {
        dialog.dismiss()
    }

    dialog.show()
    dialog.window?.setBackgroundDrawableResource(android.R.color.transparent)
    dialog.window?.setLayout(
        (resources.displayMetrics.widthPixels * 0.92f).toInt(),
        android.view.WindowManager.LayoutParams.WRAP_CONTENT
    )
    return dialog
}
