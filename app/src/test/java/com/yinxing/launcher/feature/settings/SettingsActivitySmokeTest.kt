package com.yinxing.launcher.feature.settings

import android.content.Context
import android.content.Intent
import android.content.pm.ActivityInfo
import android.content.pm.ApplicationInfo
import android.content.pm.ResolveInfo
import android.os.Looper
import android.provider.Settings
import android.view.View
import android.widget.LinearLayout
import android.widget.TextView
import androidx.test.core.app.ApplicationProvider
import com.yinxing.launcher.R
import com.yinxing.launcher.common.root.RootCommand
import com.yinxing.launcher.common.root.RootCommandResult
import com.yinxing.launcher.common.root.RootCommandRunner
import com.yinxing.launcher.common.root.RootFailureEvidence
import com.yinxing.launcher.common.root.RootFailureReason
import com.yinxing.launcher.common.root.RootFailureStage
import com.yinxing.launcher.common.root.RootHealthRepository
import com.yinxing.launcher.common.root.RootHealthSnapshot
import com.yinxing.launcher.common.root.RootHealthState
import com.yinxing.launcher.data.home.LauncherPreferences
import com.yinxing.launcher.data.settings.LauncherSettingsDataStore
import com.yinxing.launcher.feature.incoming.IncomingCallDiagnostics
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowDialog

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class SettingsActivitySmokeTest {
    private lateinit var context: Context

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        resetLauncherPreferencesSingleton()
        context.getSharedPreferences("launcher_prefs", Context.MODE_PRIVATE).edit().clear().commit()
        LauncherSettingsDataStore.getInstance(context).clear()
        IncomingCallDiagnostics.clear(context)
        registerSettingsActivity()
        registerHomeActivity(packageName = "com.android.launcher3")
    }

    // ═══════════════════════════════════════════════════════════════════════
    // 布局：hub 卡片视图存在性
    // ═══════════════════════════════════════════════════════════════════════

    @Test
    fun incomingGuardCardExists() {
        val activity = buildActivity()
        idle()
        assertNotNull(activity.findViewById(R.id.btn_card_incoming_guard))
    }

    @Test
    fun autoAnswerCardExists() {
        val activity = buildActivity()
        idle()
        assertNotNull(activity.findViewById(R.id.btn_card_auto_answer))
    }

    @Test
    fun contactsCardExists() {
        val activity = buildActivity()
        idle()
        assertNotNull(activity.findViewById(R.id.btn_card_contacts))
    }

    @Test
    fun permissionsCardExists() {
        val activity = buildActivity()
        idle()
        assertNotNull(activity.findViewById(R.id.btn_card_permissions))
    }

    @Test
    fun deviceCardExists() {
        val activity = buildActivity()
        idle()
        assertNotNull(activity.findViewById(R.id.btn_card_device))
    }

    @Test
    fun systemCardExists() {
        val activity = buildActivity()
        idle()
        assertNotNull(activity.findViewById(R.id.btn_card_system))
    }

    @Test
    fun rootHealthCardExistsWithoutRoot() {
        val activity = buildActivity()
        idle()
        assertNotNull(activity.findViewById<View>(R.id.btn_card_root))
        assertTrue(activity.findViewById<TextView>(R.id.tv_root_hub_summary).text.isNotEmpty())
    }

    @Test
    fun rootHealthCardStartsUncheckedWithoutInvokingRoot() {
        val activity = buildActivity()
        idle()
        assertEquals(
            activity.getString(R.string.settings_root_status_unchecked),
            activity.findViewById<TextView>(R.id.tv_root_hub_status).text.toString()
        )
        assertEquals(
            activity.getString(R.string.settings_root_hub_summary_unchecked),
            activity.findViewById<TextView>(R.id.tv_root_hub_summary).text.toString()
        )
    }

    @Test
    fun rootHealthStatusSummaryIncludesHomeOwnershipAndForegroundConfirmation() {
        val activity = buildActivity()
        val schemaThree = checkNotNull(RootHealthSnapshot.parse(schemaThreeRootHealth()))
        val otherHome = checkNotNull(
            RootHealthSnapshot.parse(
                schemaThreeRootHealth()
                    .replace("home=owned", "home=other")
                    .replace("home_foreground=verified", "home_foreground=unknown")
            )
        )
        val schemaOne = checkNotNull(
            RootHealthSnapshot.parse(
                schemaThreeRootHealth()
                    .replace("schema=3", "schema=1")
                    .lineSequence()
                    .filterNot { it.startsWith("home=") || it.startsWith("home_foreground=") }
                    .joinToString("\n")
            )
        )

        assertEquals(RootHealthState.HEALTHY, schemaThree.state)
        assertEquals(RootHealthState.DEGRADED, schemaOne.state)
        assertTrue(activity.rootHealthStatusSummary(schemaThree).contains("桌面 正常"))
        assertTrue(activity.rootHealthStatusSummary(schemaThree).contains("前台确认 正常"))
        assertTrue(activity.rootHealthStatusSummary(otherHome).contains("桌面 待处理"))
        assertTrue(activity.rootHealthStatusSummary(otherHome).contains("前台确认 未知"))
        assertTrue(activity.rootHealthStatusSummary(schemaOne).contains("桌面 未知"))
        assertTrue(activity.rootHealthStatusSummary(schemaOne).contains("前台确认 未知"))
    }

    @Test
    fun rootUnavailableSummaryNamesTheActualFailureAndNextAction() {
        val activity = buildActivity()
        val cases = listOf(
            RootHealthSnapshot.unavailable(RootFailureReason.SU_NOT_FOUND) to "找不到 /system/bin/su",
            RootHealthSnapshot.unavailable(RootFailureReason.SU_EXECUTION_BLOCKED) to "系统拒绝启动它",
            RootHealthSnapshot.unavailable(RootFailureReason.SU_START_FAILED) to "su 进程启动失败",
            RootHealthSnapshot.unavailable(RootFailureReason.SCRIPT_NOT_FOUND) to "Root Guard 模块目录或固定脚本不存在",
            RootHealthSnapshot.unavailable(RootFailureReason.SCRIPT_UNAVAILABLE, 127) to "不可访问或不存在",
            RootHealthSnapshot.unavailable(RootFailureReason.SCRIPT_EXECUTION_BLOCKED) to "Root Guard 脚本无法执行",
            RootHealthSnapshot.unavailable(RootFailureReason.COMMAND_PERMISSION_DENIED, 13) to "退出码 13",
            RootHealthSnapshot.unavailable(RootFailureReason.COMMAND_TIMEOUT) to "Root 脚本响应超时",
            RootHealthSnapshot.unavailable(RootFailureReason.COMMAND_FAILED, 42) to "退出码 42",
            RootHealthSnapshot.unavailable(RootFailureReason.OUTPUT_LIMIT_EXCEEDED) to "状态输出异常过长",
            RootHealthSnapshot.unavailable(RootFailureReason.STATUS_FORMAT_INVALID) to "状态格式不完整"
        )

        cases.forEach { (snapshot, expectedText) ->
            assertTrue(
                "missing '$expectedText' in '${activity.rootHealthStatusSummary(snapshot)}'",
                activity.rootHealthStatusSummary(snapshot).contains(expectedText)
            )
        }
        assertTrue(
            activity.rootHealthStatusSummary(
                RootHealthSnapshot.unavailable(RootFailureReason.SU_NOT_FOUND)
            ).contains(android.os.Process.myUid().toString())
        )
    }

    @Test
    fun rootHubShowsSuEntryFailureInsteadOfGenericUnavailable() {
        val activity = buildActivity()
        activity.rootHealthSnapshot = RootHealthSnapshot.unavailable(
            RootFailureReason.SU_NOT_FOUND
        )

        activity.updateRootHubCard()

        assertEquals(
            activity.getString(R.string.settings_root_status_su_not_found),
            activity.findViewById<TextView>(R.id.tv_root_hub_status).text.toString()
        )
        assertTrue(
            activity.findViewById<TextView>(R.id.tv_root_hub_summary).text
                .contains("找不到 /system/bin/su")
        )
    }

    @Test
    fun rootFailureEvidenceSummaryShowsSuStartBoundaryWithoutCollapsingDetails() {
        val activity = buildActivity()
        val evidence = RootFailureEvidence.create(
            command = RootCommand.STATUS,
            stage = RootFailureStage.SU_START,
            detail = "IOException: Cannot run program /system/bin/su: error=2, No such file or directory"
        )

        val summary = activity.rootFailureEvidenceSummary(evidence)

        assertTrue(summary.contains("启动 su"))
        assertTrue(summary.contains(android.os.Process.myUid().toString()))
        assertTrue(
            summary.contains(
                "/system/bin/su -c \"/system/bin/sh /data/adb/modules/yinxing_guard/bin/status.sh\""
            )
        )
        assertTrue(summary.contains("未启动"))
        assertTrue(summary.contains("IOException"))
        assertTrue(summary.contains("error=2"))
    }

    @Test
    fun rootUnavailableStatusAppendsExit126CommandAndOriginalSystemText() {
        val activity = buildActivity()
        val evidence = RootFailureEvidence.create(
            command = RootCommand.STATUS,
            stage = RootFailureStage.COMMAND_RUN,
            exitCode = 126,
            detail = "/system/bin/sh: status.sh: Permission denied"
        )
        val snapshot = RootHealthSnapshot.unavailable(
            reason = RootFailureReason.SCRIPT_EXECUTION_BLOCKED,
            exitCode = 126,
            evidence = evidence
        )

        val summary = activity.rootHealthStatusSummary(snapshot)

        assertTrue(summary.contains("执行状态脚本"))
        assertTrue(summary.contains("退出码：126"))
        assertTrue(summary.contains("/data/adb/modules/yinxing_guard/bin/status.sh"))
        assertTrue(summary.contains("/system/bin/sh: status.sh: Permission denied"))
    }

    @Test
    fun rootFailureEvidenceSummaryNamesEmptySystemOutput() {
        val activity = buildActivity()
        val evidence = RootFailureEvidence.create(
            command = RootCommand.RECOVER,
            stage = RootFailureStage.COMMAND_RUN,
            exitCode = 126
        )

        val summary = activity.rootFailureEvidenceSummary(evidence)

        assertTrue(summary.contains("执行修复脚本"))
        assertTrue(summary.contains("系统原文：无输出"))
    }

    @Test
    fun rootSheetKeepsFailedActionEvidenceBesideHealthyRefresh() {
        val activity = buildActivity()
        val evidence = RootFailureEvidence.create(
            command = RootCommand.RECOVER,
            stage = RootFailureStage.COMMAND_RUN,
            exitCode = 126,
            detail = "/system/bin/sh: /data/adb/modules/yinxing_guard/action.sh: Permission denied"
        )
        val commands = mutableListOf<RootCommand>()
        activity.rootHealthRepository = RootHealthRepository(
            RootCommandRunner { command ->
                synchronized(commands) { commands += command }
                when (command) {
                    RootCommand.RECOVER -> RootCommandResult(
                        exitCode = 126,
                        output = evidence.detail,
                        evidence = evidence
                    )
                    RootCommand.STATUS -> RootCommandResult(
                        exitCode = 0,
                        output = schemaThreeRootHealth()
                    )
                    RootCommand.KIOSK_HOME -> error("unexpected Kiosk HOME command")
                }
            }
        )

        activity.findViewById<View>(R.id.btn_card_root).performClick()
        awaitRootHealth(activity)
        val dialog = requireNotNull(ShadowDialog.getLatestDialog())
        val entries = requireNotNull(
            dialog.findViewById<LinearLayout>(R.id.layout_permission_items)
        )
        val statusEntry = entries.getChildAt(0)
        val recoveryEntry = entries.getChildAt(1)

        recoveryEntry.performClick()
        awaitRootHealth(activity)

        val statusSummary = statusEntry.findViewById<TextView>(R.id.tv_permission_item_summary).text
        val recoverySummary = recoveryEntry.findViewById<TextView>(R.id.tv_permission_item_summary).text

        assertEquals(RootHealthState.HEALTHY, activity.rootHealthSnapshot.state)
        assertTrue(statusSummary.contains("模块 正常"))
        assertTrue(recoverySummary.contains("action.sh"))
        assertTrue(recoverySummary.contains("退出码：126"))
        assertTrue(recoverySummary.contains("Permission denied"))
        assertEquals(
            listOf(RootCommand.STATUS, RootCommand.RECOVER, RootCommand.STATUS),
            synchronized(commands) { commands.toList() }
        )
    }

    // ═══════════════════════════════════════════════════════════════════════
    // 来电守卫 — summary 反映当前阻断项
    // ═══════════════════════════════════════════════════════════════════════

    @Test
    fun incomingGuardSummaryIsNotEmpty() {
        val activity = buildActivity()
        idle()
        val summaryView = activity.findViewById<TextView>(R.id.tv_incoming_guard_summary)
        assertNotNull(summaryView)
        assertTrue("来电守卫摘要不应为空", summaryView.text.isNotEmpty())
    }

    @Test
    fun incomingGuardActionTextIsNotEmpty() {
        val activity = buildActivity()
        idle()
        val actionView = activity.findViewById<TextView>(R.id.tv_incoming_guard_action)
        assertNotNull(actionView)
        assertTrue("来电守卫操作按钮文本不应为空", actionView.text.isNotEmpty())
    }

    @Test
    fun incomingGuardStatusBadgeIsNotEmpty() {
        val activity = buildActivity()
        idle()
        val statusView = activity.findViewById<TextView>(R.id.tv_incoming_guard_status)
        assertNotNull(statusView)
        assertTrue("来电守卫状态徽章不应为空", statusView.text.isNotEmpty())
    }

    // ═══════════════════════════════════════════════════════════════════════
    // 自动接听 hub — 默认开启时摘要包含延迟秒数
    // ═══════════════════════════════════════════════════════════════════════

    @Test
    fun autoAnswerHubSummaryWhenEnabledContainsDelaySummary() {
        val activity = buildActivity()
        idle()
        val summaryView = activity.findViewById<TextView>(R.id.tv_auto_answer_hub_summary)
        assertNotNull(summaryView)
        val expected = activity.getString(
            R.string.settings_auto_answer_delay_summary,
            LauncherPreferences.DEFAULT_AUTO_ANSWER_DELAY_SECONDS
        )
        assertTrue(
            "自动接听开启时摘要应包含延迟描述，实际: ${summaryView.text}",
            summaryView.text.toString() == expected
        )
    }

    @Test
    fun autoAnswerHubSummaryWhenDisabledShowsOffText() {
        LauncherPreferences.getInstance(context).setAutoAnswerEnabled(false)
        val activity = buildActivity()
        idle()
        val summaryView = activity.findViewById<TextView>(R.id.tv_auto_answer_hub_summary)
        assertNotNull(summaryView)
        val expected = activity.getString(R.string.settings_auto_answer_summary_off)
        assertTrue(
            "自动接听关闭时摘要应为关闭描述，实际: ${summaryView.text}",
            summaryView.text.toString() == expected
        )
    }

    @Test
    fun autoAnswerHubStatusBadgeIsNotEmpty() {
        val activity = buildActivity()
        idle()
        val statusView = activity.findViewById<TextView>(R.id.tv_auto_answer_hub_status)
        assertNotNull(statusView)
        assertTrue("自动接听状态徽章不应为空", statusView.text.isNotEmpty())
    }

    // ═══════════════════════════════════════════════════════════════════════
    // 诊断链 — 最新通话链路显示在来电守卫摘要区域
    // ═══════════════════════════════════════════════════════════════════════

    @Test
    fun incomingTraceDiagnosticsDoNotCrashOnLaunch() {
        IncomingCallDiagnostics.recordBroadcastReceived(
            context = context,
            callerLabel = "张阿姨",
            incomingNumber = "13812345678",
            autoAnswer = true
        )
        IncomingCallDiagnostics.recordServiceStarted(context, "张阿姨", autoAnswer = true)
        IncomingCallDiagnostics.recordActivityShown(context, "张阿姨")
        IncomingCallDiagnostics.recordAcceptSuccess(
            context,
            context.getString(R.string.incoming_call_status_accept_sent)
        )
        val activity = buildActivity()
        idle()
        assertNotNull(activity.findViewById<TextView>(R.id.tv_incoming_guard_summary))
    }

    // ═══════════════════════════════════════════════════════════════════════
    // 权限 hub — 视图存在且文本非空
    // ═══════════════════════════════════════════════════════════════════════

    @Test
    fun permissionHubSummaryIsNotEmpty() {
        val activity = buildActivity()
        idle()
        val summaryView = activity.findViewById<TextView>(R.id.tv_permission_hub_summary)
        assertNotNull(summaryView)
        assertTrue("权限摘要不应为空", summaryView.text.isNotEmpty())
    }

    @Test
    fun permissionHubStatusBadgeIsNotEmpty() {
        val activity = buildActivity()
        idle()
        val statusView = activity.findViewById<TextView>(R.id.tv_permission_hub_status)
        assertNotNull(statusView)
        assertTrue("权限状态徽章不应为空", statusView.text.isNotEmpty())
    }


    // ═══════════════════════════════════════════════════════════════════════
    // 生命周期 — 不崩溃
    // ═══════════════════════════════════════════════════════════════════════

    @Test
    fun onResumeDoesNotCrash() {
        val controller = Robolectric.buildActivity(SettingsActivity::class.java).setup()
        idle()
        runCatching {
            controller.pause()
            controller.resume()
        }
        idle()
        assertFalse(controller.get().isFinishing)
    }

    @Test
    fun onDestroyDoesNotCrash() {
        val controller = Robolectric.buildActivity(SettingsActivity::class.java).setup()
        idle()
        runCatching { controller.destroy() }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // 辅助
    // ═══════════════════════════════════════════════════════════════════════

    private fun buildActivity() =
        Robolectric.buildActivity(SettingsActivity::class.java).setup().get()

    private fun idle() = shadowOf(Looper.getMainLooper()).idle()

    private fun awaitRootHealth(activity: SettingsActivity) {
        val deadlineNanos = System.nanoTime() + 5_000_000_000L
        while (activity.rootHealthJob != null && System.nanoTime() < deadlineNanos) {
            idle()
            Thread.yield()
        }
        idle()
        assertTrue("Root health coroutine did not finish", activity.rootHealthJob == null)
    }

    private fun schemaThreeRootHealth(): String = """
        schema=3
        version=1.10.0-root-preview.14
        module=active
        guard=running
        accessibility=enabled
        home=owned
        home_foreground=verified
        doze=owned
        cleanup=ready
        last_repair=ok
    """.trimIndent()

    @Suppress("DEPRECATION")
    private fun registerSettingsActivity() {
        val intent = Intent(Settings.ACTION_SETTINGS)
        val applicationInfo = ApplicationInfo().apply {
            packageName = "com.android.settings"
            nonLocalizedLabel = "Settings"
        }
        val activityInfo = ActivityInfo().apply {
            packageName = "com.android.settings"
            name = "com.android.settings.Settings"
            this.applicationInfo = applicationInfo
        }
        val resolveInfo = ResolveInfo().apply { this.activityInfo = activityInfo }
        shadowOf(context.packageManager).addResolveInfoForIntent(intent, resolveInfo)
    }

    @Suppress("DEPRECATION")
    private fun registerHomeActivity(packageName: String) {
        val intent = Intent(Intent.ACTION_MAIN).apply { addCategory(Intent.CATEGORY_HOME) }
        val applicationInfo = ApplicationInfo().apply {
            this.packageName = packageName
            nonLocalizedLabel = "OldLauncher"
        }
        val activityInfo = ActivityInfo().apply {
            this.packageName = packageName
            name = "$packageName.feature.home.MainActivity"
            this.applicationInfo = applicationInfo
        }
        val resolveInfo = ResolveInfo().apply { this.activityInfo = activityInfo }
        shadowOf(context.packageManager).addResolveInfoForIntent(intent, resolveInfo)
    }

    private fun resetLauncherPreferencesSingleton() {
        val field = Class.forName("com.yinxing.launcher.data.home.LauncherPreferences")
            .getDeclaredField("instance")
        field.isAccessible = true
        field.set(null, null)
    }
}
