package com.yinxing.launcher.feature.incoming

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.yinxing.launcher.common.util.DebugLog
import com.yinxing.launcher.common.util.PermissionUtil
import com.yinxing.launcher.data.home.LauncherPreferences
import com.yinxing.launcher.feature.home.MainActivity

internal object BootLaunchPolicy {
    fun shouldLaunchHome(
        autoStartConfirmed: Boolean,
        kioskModeEnabled: Boolean,
        defaultLauncher: Boolean
    ): Boolean = autoStartConfirmed || kioskModeEnabled || defaultLauncher
}

/**
 * 开机恢复入口。
 * 在系统开机完成或应用更新后，预创建来电通知通道，
 * 并在已确认自启动、承担桌面角色或开启防退出时尝试恢复到桌面首页。
 */
class BootReceiver : BroadcastReceiver() {
    private companion object {
        const val TAG = "BootReceiver"
    }

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        if (action != Intent.ACTION_BOOT_COMPLETED && action != Intent.ACTION_MY_PACKAGE_REPLACED) {
            return
        }

        IncomingCallForegroundService.ensureNotificationChannels(context)

        val prefs = LauncherPreferences.getInstance(context)
        val autoStartConfirmed = prefs.isAutoStartConfirmed()
        val kioskModeEnabled = prefs.isKioskModeEnabled()
        val defaultLauncher = if (autoStartConfirmed || kioskModeEnabled) {
            false
        } else {
            runCatching { PermissionUtil.isDefaultLauncher(context) }.getOrDefault(false)
        }
        if (!BootLaunchPolicy.shouldLaunchHome(autoStartConfirmed, kioskModeEnabled, defaultLauncher)) {
            return
        }

        val launch = Intent(context, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
        runCatching { context.startActivity(launch) }
            .onFailure { DebugLog.w(TAG, "ColorOS rejected boot home launch", it) }
    }
}
