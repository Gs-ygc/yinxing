package com.yinxing.launcher.feature.incoming

import android.view.WindowManager
import android.widget.TextView
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.ViewCompat
import com.google.android.material.button.MaterialButton
import com.yinxing.launcher.R

internal enum class IncomingCallFailedAction {
    ACCEPT,
    DECLINE
}

internal fun AppCompatActivity.showIncomingCallFailureDialog(
    callerName: String,
    action: IncomingCallFailedAction,
    reason: IncomingCallFailureReason,
    systemUiRequestPreviouslyFailed: Boolean = false,
    onOpenSystemCall: () -> SystemCallUiRequestResult,
    onRetry: () -> Unit
): AlertDialog {
    val displayName = callerName.trim().ifEmpty {
        getString(R.string.incoming_call_unknown_caller)
    }
    val titleRes = when (action) {
        IncomingCallFailedAction.ACCEPT -> R.string.incoming_call_failure_accept_title
        IncomingCallFailedAction.DECLINE -> R.string.incoming_call_failure_decline_title
    }
    val retryRes = when (action) {
        IncomingCallFailedAction.ACCEPT -> R.string.incoming_call_failure_retry_accept
        IncomingCallFailedAction.DECLINE -> R.string.incoming_call_failure_retry_decline
    }
    val messageRes = if (systemUiRequestPreviouslyFailed) {
        R.string.incoming_call_failure_system_ui_failed_message
    } else {
        when (reason.category) {
            IncomingCallFailureCategory.PhonePermission ->
                R.string.incoming_call_failure_permission_message
            IncomingCallFailureCategory.UnsupportedPlatform ->
                R.string.incoming_call_failure_unsupported_message
            else -> R.string.incoming_call_failure_action_message
        }
    }
    val dialogView = layoutInflater.inflate(R.layout.dialog_incoming_call_failure, null)
    val messageView = dialogView.findViewById<TextView>(R.id.tv_incoming_call_failure_message)
    val systemCallButton = dialogView.findViewById<MaterialButton>(
        R.id.btn_incoming_call_system_ui
    )
    val retryButton = dialogView.findViewById<MaterialButton>(R.id.btn_incoming_call_retry)
    val titleView = dialogView.findViewById<TextView>(R.id.tv_incoming_call_failure_title)
    val titleText = getString(titleRes, displayName)
    titleView.text = titleText
    messageView.setText(messageRes)
    retryButton.setText(retryRes)
    retryButton.contentDescription = retryButton.text
    ViewCompat.setAccessibilityPaneTitle(dialogView, titleText)
    ViewCompat.setAccessibilityHeading(titleView, true)

    val dialog = AlertDialog.Builder(this)
        .setView(dialogView)
        .setCancelable(true)
        .create()
    dialog.setCanceledOnTouchOutside(false)
    systemCallButton.setOnClickListener {
        when (onOpenSystemCall()) {
            SystemCallUiRequestResult.Requested -> dialog.dismiss()
            is SystemCallUiRequestResult.Failed -> {
                messageView.setText(R.string.incoming_call_failure_system_ui_failed_message)
            }
        }
    }
    retryButton.setOnClickListener {
        dialog.dismiss()
        onRetry()
    }

    dialog.show()
    dialog.window?.setBackgroundDrawableResource(android.R.color.transparent)
    dialog.window?.setLayout(
        (resources.displayMetrics.widthPixels * 0.92f).toInt(),
        WindowManager.LayoutParams.WRAP_CONTENT
    )
    return dialog
}
