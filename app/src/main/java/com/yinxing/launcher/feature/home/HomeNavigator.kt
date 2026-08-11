package com.yinxing.launcher.feature.home

import android.content.Intent
import android.net.Uri
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import com.yinxing.launcher.R
import com.yinxing.launcher.common.lobster.LobsterClient
import com.yinxing.launcher.feature.phone.PhoneContactActivity
import com.yinxing.launcher.feature.settings.SettingsActivity
import com.yinxing.launcher.feature.videocall.VideoCallActivity

class HomeNavigator(
    private val activity: AppCompatActivity
) {
    private var appFailureDialog: AlertDialog? = null

    private val appLauncher = HomeAppLauncher(
        resolveLaunchIntent = activity.packageManager::getLaunchIntentForPackage,
        launchIntent = activity::startActivity,
        onUnavailable = ::showAppFailure
    )

    fun openWeatherEntry() {
        val vendorIntent = listOf(
            "com.miui.weather2",
            "com.huawei.android.totemweather",
            "com.oppo.weather",
            "com.vivo.weather"
        ).asSequence().mapNotNull { activity.packageManager.getLaunchIntentForPackage(it) }.firstOrNull()
        if (vendorIntent != null) {
            activity.startActivity(vendorIntent)
            return
        }
        val browserIntent = Intent(Intent.ACTION_VIEW, Uri.parse(activity.getString(R.string.weather_fallback_url)))
        runCatching { activity.startActivity(browserIntent) }
            .onSuccess {
                Toast.makeText(activity, activity.getString(R.string.weather_fallback_notice), Toast.LENGTH_SHORT).show()
            }
            .onFailure {
                Toast.makeText(activity, activity.getString(R.string.weather_not_available), Toast.LENGTH_SHORT).show()
            }
    }

    fun showCaregiverEntryDialog() {
        val dialogView = activity.layoutInflater.inflate(R.layout.dialog_accessibility_prompt, null)
        dialogView.findViewById<TextView>(R.id.tv_dialog_title).text =
            activity.getString(R.string.home_caregiver_dialog_title)
        dialogView.findViewById<TextView>(R.id.tv_dialog_message).text =
            activity.getString(R.string.home_caregiver_dialog_message)
        dialogView.findViewById<TextView>(R.id.tv_cancel_label).text =
            activity.getString(R.string.home_caregiver_dialog_cancel)
        dialogView.findViewById<TextView>(R.id.tv_primary_label).text =
            activity.getString(R.string.home_caregiver_dialog_confirm)
        val dialog = AlertDialog.Builder(activity)
            .setView(dialogView)
            .create()
        dialog.window?.setBackgroundDrawableResource(android.R.color.transparent)
        dialogView.findViewById<android.view.View>(R.id.btn_cancel).setOnClickListener { dialog.dismiss() }
        dialogView.findViewById<android.view.View>(R.id.btn_open_settings).setOnClickListener {
            dialog.dismiss()
            activity.startActivity(Intent(activity, SettingsActivity::class.java))
        }
        dialog.show()
    }

    fun openHomeItem(item: HomeAppItem) {
        when (item.type) {
            HomeAppItem.Type.APP -> openApp(item)
            HomeAppItem.Type.PHONE -> openPhoneContacts()
            HomeAppItem.Type.WECHAT_VIDEO -> {
                LobsterClient.log("[首页] 点击微信视频卡片")
                activity.startActivity(
                    Intent(activity, VideoCallActivity::class.java)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                )
            }
        }
    }

    fun openPhoneContacts() {
        activity.startActivity(PhoneContactActivity.createIntent(activity))
    }

    fun dismissTransientDialogs() {
        appFailureDialog?.setOnDismissListener(null)
        appFailureDialog?.dismiss()
        appFailureDialog = null
    }

    private fun openApp(item: HomeAppItem) {
        appLauncher.open(item)
    }

    private fun showAppFailure(item: HomeAppItem) {
        if (activity.isFinishing || activity.isDestroyed) return
        appFailureDialog?.dismiss()
        appFailureDialog = null

        val dialog = activity.showHomeAppFailureDialog(
            item = item,
            onRetry = { appLauncher.open(item) },
            onOpenSettings = {
                runCatching {
                    activity.startActivity(Intent(activity, SettingsActivity::class.java))
                }.onFailure {
                    Toast.makeText(
                        activity,
                        activity.getString(R.string.open_settings_failed),
                        Toast.LENGTH_SHORT
                    ).show()
                }
            }
        )
        dialog.setOnDismissListener {
            if (appFailureDialog === dialog) {
                appFailureDialog = null
            }
        }
        appFailureDialog = dialog
    }
}
