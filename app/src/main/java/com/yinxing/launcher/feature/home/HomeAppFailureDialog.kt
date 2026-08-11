package com.yinxing.launcher.feature.home

import android.view.WindowManager
import android.widget.TextView
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import com.google.android.material.button.MaterialButton
import com.yinxing.launcher.R

internal fun AppCompatActivity.showHomeAppFailureDialog(
    item: HomeAppItem,
    onRetry: () -> Unit,
    onOpenSettings: () -> Unit
): AlertDialog {
    val dialogView = layoutInflater.inflate(R.layout.dialog_home_app_failure, null)
    dialogView.findViewById<TextView>(R.id.tv_home_app_failure_title).text = getString(
        R.string.home_app_failure_title,
        item.appName
    )
    dialogView.findViewById<TextView>(R.id.tv_home_app_failure_message).text = getString(
        R.string.home_app_failure_message
    )

    val dialog = AlertDialog.Builder(this)
        .setView(dialogView)
        .setCancelable(true)
        .create()
    dialogView.findViewById<MaterialButton>(R.id.btn_home_app_retry).setOnClickListener {
        dialog.dismiss()
        onRetry()
    }
    dialogView.findViewById<MaterialButton>(R.id.btn_home_app_settings).setOnClickListener {
        dialog.dismiss()
        onOpenSettings()
    }

    dialog.show()
    dialog.window?.setBackgroundDrawableResource(android.R.color.transparent)
    dialog.window?.setLayout(
        (resources.displayMetrics.widthPixels * 0.92f).toInt(),
        WindowManager.LayoutParams.WRAP_CONTENT
    )
    return dialog
}
