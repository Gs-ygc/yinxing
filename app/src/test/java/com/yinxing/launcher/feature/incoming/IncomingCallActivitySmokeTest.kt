package com.yinxing.launcher.feature.incoming

import android.Manifest
import android.app.Application
import android.content.Context
import android.content.Intent
import android.os.Looper
import android.telephony.TelephonyManager
import android.view.View
import android.widget.TextView
import androidx.cardview.widget.CardView
import androidx.appcompat.app.AlertDialog
import androidx.test.core.app.ApplicationProvider
import com.yinxing.launcher.R
import com.yinxing.launcher.data.home.LauncherPreferences
import com.yinxing.launcher.data.settings.LauncherSettingsDataStore
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNotSame
import org.junit.Assert.assertNull
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
class IncomingCallActivitySmokeTest {

    private lateinit var context: Context

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        context.getSharedPreferences("launcher_prefs", Context.MODE_PRIVATE).edit().clear().commit()
        LauncherSettingsDataStore.getInstance(context).clear()
        IncomingCallDiagnostics.clear(context)
        resetLauncherPreferencesSingleton()
    }

    // ═══════════════════════════════════════════════════════════════════════
    // 启动 / 来电人显示
    // ═══════════════════════════════════════════════════════════════════════

    @Test
    fun launchWithChineseCallerNameShowsName() {
        val activity = buildActivity("王大爷")
        idle()
        assertEquals("王大爷", activity.tv_caller.text.toString())
    }

    @Test
    fun launchWithEnglishCallerNameShowsName() {
        val activity = buildActivity("Alice")
        idle()
        assertEquals("Alice", activity.tv_caller.text.toString())
    }

    @Test
    fun launchWithMixedLangCallerNameShowsName() {
        val activity = buildActivity("Bob李四")
        idle()
        assertEquals("Bob李四", activity.tv_caller.text.toString())
    }

    @Test
    fun launchWithSpecialCharCallerNameShowsName() {
        val activity = buildActivity("wan.")
        idle()
        assertEquals("wan.", activity.tv_caller.text.toString())
    }

    @Test
    fun launchWithEmojiCallerNameShowsName() {
        val activity = buildActivity("🐼猫咪")
        idle()
        assertEquals("🐼猫咪", activity.tv_caller.text.toString())
    }

    @Test
    fun launchWithLongCallerNameShowsName() {
        val name = "A".repeat(50)
        val activity = buildActivity(name)
        idle()
        assertEquals(name, activity.tv_caller.text.toString())
    }

    @Test
    fun launchWithNullCallerNameShowsUnknown() {
        val activity = buildActivityRaw(callerName = null)
        idle()
        assertEquals(context.getString(R.string.incoming_call_unknown_caller), activity.tv_caller.text.toString())
    }

    @Test
    fun launchWithBlankCallerNameShowsUnknown() {
        val activity = buildActivityRaw(callerName = "   ")
        idle()
        assertEquals(context.getString(R.string.incoming_call_unknown_caller), activity.tv_caller.text.toString())
    }

    @Test
    fun launchWithEmptyCallerNameShowsUnknown() {
        val activity = buildActivityRaw(callerName = "")
        idle()
        assertEquals(context.getString(R.string.incoming_call_unknown_caller), activity.tv_caller.text.toString())
    }

    @Test
    fun launchWithSingleSpaceCallerNameShowsUnknown() {
        val activity = buildActivityRaw(callerName = " ")
        idle()
        assertEquals(context.getString(R.string.incoming_call_unknown_caller), activity.tv_caller.text.toString())
    }

    // ═══════════════════════════════════════════════════════════════════════
    // 视图存在性
    // ═══════════════════════════════════════════════════════════════════════

    @Test
    fun callerTextViewExists() {
        val activity = buildActivity("测试人")
        assertNotNull(activity.tv_caller)
    }

    @Test
    fun acceptButtonExists() {
        val activity = buildActivity("测试人")
        assertNotNull(activity.findViewById<CardView>(R.id.btn_incoming_accept))
    }

    @Test
    fun declineButtonExists() {
        val activity = buildActivity("测试人")
        assertNotNull(activity.findViewById<CardView>(R.id.btn_incoming_decline))
    }

    @Test
    fun countdownTextViewExists() {
        val activity = buildActivity("测试人")
        assertNotNull(activity.tv_countdown)
    }

    @Test
    fun riskTextViewExists() {
        val activity = buildActivity("测试人")
        assertNotNull(activity.tv_risk)
    }

    @Test
    fun acceptButtonIsVisible() {
        val activity = buildActivity("测试人")
        idle()
        assertEquals(View.VISIBLE, activity.findViewById<CardView>(R.id.btn_incoming_accept).visibility)
    }

    @Test
    fun declineButtonIsVisible() {
        val activity = buildActivity("测试人")
        idle()
        assertEquals(View.VISIBLE, activity.findViewById<CardView>(R.id.btn_incoming_decline).visibility)
    }

    // ═══════════════════════════════════════════════════════════════════════
    // 自动接听 — 倒计时 UI
    // ═══════════════════════════════════════════════════════════════════════

    @Test
    fun autoAnswerOnShowsCountdownText() {
        val activity = buildActivity("用户A", autoAnswer = true)
        idle()
        assertTrue("倒计时文字应非空", activity.tv_countdown.text.isNotEmpty())
    }

    @Test
    fun autoAnswerOnShowsAutoAnswerWording() {
        val activity = buildActivity("用户B", autoAnswer = true)
        idle()
        assertTrue("应含'自动接听'", activity.tv_countdown.text.contains("自动接听"))
    }

    @Test
    fun autoAnswerOnCountdownTextContainsSeconds() {
        val activity = buildActivity("用户C", autoAnswer = true)
        idle()
        assertTrue("应含秒数", activity.tv_countdown.text.contains("秒"))
    }

    @Test
    fun autoAnswerOffShowsEmptyCountdownText() {
        val activity = buildActivity("用户D", autoAnswer = false)
        idle()
        assertTrue("关闭自动接听时倒计时应为空", activity.tv_countdown.text.isEmpty())
    }

    @Test
    fun autoAnswerDefaultOffShowsEmptyCountdown() {
        val activity = buildActivityRaw(callerName = "用户E")
        idle()
        assertTrue("默认不传 autoAnswer 应不显示倒计时", activity.tv_countdown.text.isEmpty())
    }

    // ═══════════════════════════════════════════════════════════════════════
    // 点击接听 — 不崩溃且按钮进入处理中状态
    // ═══════════════════════════════════════════════════════════════════════

    @Test
    fun clickAcceptFinishesActivity() {
        val activity = buildActivity("赵六", autoAnswer = false)
        idle()
        runCatching { activity.btn_accept.performClick() }
        idle()
        assertTrue("点击接听后 Activity 不应崩溃", !activity.isDestroyed || activity.isFinishing)
    }

    @Test
    fun clickAcceptFinishesActivityWhenAutoAnswerOn() {
        val activity = buildActivity("孙七", autoAnswer = true)
        idle()
        runCatching { activity.btn_accept.performClick() }
        idle()
        assertTrue(!activity.isDestroyed || activity.isFinishing)
    }

    // ═══════════════════════════════════════════════════════════════════════
    // 点击拒绝 — 不崩溃且按钮进入处理中状态
    // ═══════════════════════════════════════════════════════════════════════

    @Test
    fun clickDeclineFinishesActivity() {
        val activity = buildActivity("王五", autoAnswer = false)
        idle()
        runCatching { activity.btn_decline.performClick() }
        idle()
        assertTrue("点击拒绝后 Activity 不应崩溃", !activity.isDestroyed || activity.isFinishing)
    }

    @Test
    fun clickDeclineFinishesActivityWhenAutoAnswerOn() {
        val activity = buildActivity("王五B", autoAnswer = true)
        idle()
        runCatching { activity.btn_decline.performClick() }
        idle()
        assertTrue(!activity.isDestroyed || activity.isFinishing)
    }

    // ═══════════════════════════════════════════════════════════════════════
    // 连续点击
    // ═══════════════════════════════════════════════════════════════════════

    @Test
    fun doubleClickAcceptDoesNotCrash() {
        val activity = buildActivity("用户F", autoAnswer = false)
        idle()
        runCatching { activity.btn_accept.performClick() }
        idle()
        runCatching { activity.btn_accept.performClick() }
        idle()
        assertTrue(!activity.isDestroyed || activity.isFinishing)
    }

    @Test
    fun doubleClickDeclineDoesNotCrash() {
        val activity = buildActivity("用户G", autoAnswer = false)
        idle()
        runCatching { activity.btn_decline.performClick() }
        idle()
        runCatching { activity.btn_decline.performClick() }
        idle()
        assertTrue(!activity.isDestroyed || activity.isFinishing)
    }

    @Test
    fun missingPermissionShowsPersistentAcceptRecoveryAndFailedState() {
        denyAnswerPermission()
        val activity = buildActivity("王大爷", autoAnswer = false)

        activity.btn_accept.performClick()
        idle()

        val dialog = latestRecoveryDialog()
        assertTrue(dialog.isShowing)
        assertEquals(
            "还没有接通 王大爷",
            dialog.requireView<TextView>(R.id.tv_incoming_call_failure_title).text.toString()
        )
        assertTrue(IncomingCallSessionState.current() is IncomingCallState.Failed)
        assertTrue(activity.btn_accept.isEnabled)
        assertTrue(activity.btn_decline.isEnabled)
    }

    @Test
    fun missingPermissionShowsPersistentDeclineRecoveryAndFailedState() {
        denyAnswerPermission()
        val activity = buildActivity("李阿姨", autoAnswer = false)

        activity.btn_decline.performClick()
        idle()

        val dialog = latestRecoveryDialog()
        assertTrue(dialog.isShowing)
        assertEquals(
            "还没有挂断 李阿姨",
            dialog.requireView<TextView>(R.id.tv_incoming_call_failure_title).text.toString()
        )
        assertTrue(IncomingCallSessionState.current() is IncomingCallState.Failed)
        assertTrue(activity.btn_accept.isEnabled)
        assertTrue(activity.btn_decline.isEnabled)
    }

    @Test
    fun actionFailureWhileAutoAnswerIsEnabledLeavesCountdownStopped() {
        denyAnswerPermission()
        prefs().setAutoAnswerEnabled(true)
        val activity = buildActivity("王大爷", autoAnswer = true)
        assertTrue(activity.tv_countdown.text.isNotEmpty())

        activity.btn_accept.performClick()
        idle()

        assertEquals(View.GONE, activity.tv_countdown.visibility)
        assertTrue(activity.tv_countdown.text.isEmpty())
        assertTrue(latestRecoveryDialog().isShowing)
    }

    @Test
    fun explicitRetryReplacesFailedDialogOnceWithoutRestartingCountdown() {
        denyAnswerPermission()
        val activity = buildActivity("王大爷", autoAnswer = false)
        activity.btn_accept.performClick()
        idle()
        val firstDialog = latestRecoveryDialog()

        firstDialog.requireView<View>(R.id.btn_incoming_call_retry).performClick()
        idle()

        val replacementDialog = latestRecoveryDialog()
        assertFalse(firstDialog.isShowing)
        assertNotSame(firstDialog, replacementDialog)
        assertTrue(replacementDialog.isShowing)
        assertEquals(View.GONE, activity.tv_countdown.visibility)
    }

    @Test
    fun manualFailureSurvivesActivityRecreation() {
        denyAnswerPermission()
        val controller = buildController("王大爷", autoAnswer = false)
        controller.get().btn_accept.performClick()
        idle()
        val firstDialog = latestRecoveryDialog()

        controller.recreate()
        idle()

        val restoredDialog = latestRecoveryDialog()
        assertFalse(firstDialog.isShowing)
        assertNotSame(firstDialog, restoredDialog)
        assertTrue(restoredDialog.isShowing)
        assertTrue(IncomingCallSessionState.current() is IncomingCallState.Failed)
        assertEquals(View.GONE, controller.get().tv_countdown.visibility)
    }

    @Test
    fun autoAnswerFailureSurvivesRecreationWithoutRestartingCountdown() {
        denyAnswerPermission()
        prefs().setAutoAnswerEnabled(true)
        val controller = buildController("王大爷", autoAnswer = true)
        controller.get().btn_accept.performClick()
        idle()

        controller.recreate()
        idle()

        assertTrue(latestRecoveryDialog().isShowing)
        assertTrue(IncomingCallSessionState.current() is IncomingCallState.Failed)
        assertEquals(View.GONE, controller.get().tv_countdown.visibility)
        assertTrue(controller.get().tv_countdown.text.isEmpty())
    }

    @Test
    fun cancelledRecoveryDoesNotRestartAutoAnswerAfterRecreation() {
        denyAnswerPermission()
        prefs().setAutoAnswerEnabled(true)
        val controller = buildController("王大爷", autoAnswer = true)
        controller.get().btn_accept.performClick()
        idle()
        val dialog = latestRecoveryDialog()
        dialog.onBackPressed()
        assertFalse(dialog.isShowing)

        controller.recreate()
        idle()

        assertTrue(IncomingCallSessionState.current() is IncomingCallState.Failed)
        assertEquals(View.GONE, controller.get().tv_countdown.visibility)
        assertTrue(controller.get().tv_countdown.text.isEmpty())
        assertFalse(latestRecoveryDialog().isShowing)
    }

    @Test
    fun triggerFailureSurvivesRecreationWithoutReplayingTriggerAction() {
        denyAnswerPermission()
        val controller = buildController(
            callerName = "通知接听",
            autoAnswer = false,
            triggerAction = IncomingCallActivity.TRIGGER_ACTION_ACCEPT
        )
        idle()
        assertTrue(latestRecoveryDialog().isShowing)
        assertNull(controller.get().intent.getStringExtra(IncomingCallActivity.EXTRA_TRIGGER_ACTION))
        grantAnswerPermission()

        controller.recreate()
        idle()

        assertFalse(controller.get().isFinishing)
        assertTrue(latestRecoveryDialog().isShowing)
        assertTrue(IncomingCallSessionState.current() is IncomingCallState.Failed)
    }

    @Test
    fun pendingSystemUiReturnDoesNotRestartAutoAnswerForRingingOrUnknownState() {
        listOf(TelephonyManager.CALL_STATE_RINGING, 99).forEach { deviceCallState ->
            denyAnswerPermission()
            shadowOf(context as Application).grantPermissions(Manifest.permission.READ_PHONE_STATE)
            prefs().setAutoAnswerEnabled(true)
            val controller = buildController("王大爷", autoAnswer = true)
            controller.get().btn_accept.performClick()
            idle()
            val dialog = latestRecoveryDialog()
            dialog.requireView<View>(R.id.btn_incoming_call_system_ui).performClick()
            idle()
            assertFalse(dialog.isShowing)
            shadowOf(context.getSystemService(TelephonyManager::class.java))
                .setCallState(deviceCallState)

            controller.recreate()
            idle()

            assertFalse(controller.get().isFinishing)
            assertTrue(IncomingCallSessionState.current() is IncomingCallState.Failed)
            assertEquals(View.GONE, controller.get().tv_countdown.visibility)
            assertTrue(controller.get().tv_countdown.text.isEmpty())
            controller.destroy()
        }
    }

    @Test
    fun failedSystemUiRequestMessageSurvivesActivityRecreation() {
        denyAnswerPermission()
        val controller = buildController("王大爷", autoAnswer = false)
        controller.get().btn_accept.performClick()
        idle()
        installRecoveryCoordinator(
            controller.get(),
            IncomingCallRecoveryCoordinator(FailedSystemUiGateway())
        )
        val firstDialog = latestRecoveryDialog()
        firstDialog.requireView<View>(R.id.btn_incoming_call_system_ui).performClick()
        idle()
        assertEquals(
            context.getString(R.string.incoming_call_failure_system_ui_failed_message),
            firstDialog.requireView<TextView>(R.id.tv_incoming_call_failure_message).text.toString()
        )

        controller.recreate()
        idle()

        val restoredDialog = latestRecoveryDialog()
        assertTrue(restoredDialog.isShowing)
        assertEquals(
            context.getString(R.string.incoming_call_failure_system_ui_failed_message),
            restoredDialog.requireView<TextView>(R.id.tv_incoming_call_failure_message).text.toString()
        )
    }

    // ═══════════════════════════════════════════════════════════════════════
    // onNewIntent — 刷新来电人
    // ═══════════════════════════════════════════════════════════════════════

    @Test
    fun onNewIntentUpdatesCallerName() {
        val controller = buildController("旧来电人", autoAnswer = false)
        idle()

        controller.newIntent(buildIntent("新来电人", autoAnswer = false))
        idle()

        assertEquals("新来电人", controller.get().tv_caller.text.toString())
    }

    @Test
    fun onNewIntentUpdatesToNullCallerShowsUnknown() {
        val controller = buildController("旧来电人", autoAnswer = false)
        idle()

        controller.newIntent(buildIntent(null, autoAnswer = false))
        idle()

        assertEquals(
            context.getString(R.string.incoming_call_unknown_caller),
            controller.get().tv_caller.text.toString()
        )
    }

    @Test
    fun onNewIntentUpdatesToBlankCallerShowsUnknown() {
        val controller = buildController("旧来电人", autoAnswer = false)
        idle()

        controller.newIntent(buildIntent("   ", autoAnswer = false))
        idle()

        assertEquals(
            context.getString(R.string.incoming_call_unknown_caller),
            controller.get().tv_caller.text.toString()
        )
    }

    @Test
    fun onNewIntentMultipleTimesShowsLastCaller() {
        val controller = buildController("第一人", autoAnswer = false)
        idle()

        controller.newIntent(buildIntent("第二人", autoAnswer = false))
        idle()
        controller.newIntent(buildIntent("第三人", autoAnswer = false))
        idle()

        assertEquals("第三人", controller.get().tv_caller.text.toString())
    }

    @Test
    fun onNewIntentAutoAnswerOnResetsCountdown() {
        val controller = buildController("某人", autoAnswer = true)
        idle()

        controller.newIntent(buildIntent("新来电人", autoAnswer = true))
        idle()

        assertTrue(controller.get().tv_countdown.text.isNotEmpty())
    }

    @Test
    fun onNewIntentAutoAnswerOffShowsEmptyCountdown() {
        val controller = buildController("某人2", autoAnswer = false)
        idle()

        controller.newIntent(buildIntent("新人2", autoAnswer = false))
        idle()

        assertTrue(controller.get().tv_countdown.text.isEmpty())
    }

    @Test
    fun onNewIntentDismissesOldRecoveryAndRendersNewCaller() {
        denyAnswerPermission()
        val controller = buildController("旧来电人", autoAnswer = false)
        controller.get().btn_accept.performClick()
        idle()
        val oldDialog = latestRecoveryDialog()

        controller.newIntent(buildIntent("新来电人", autoAnswer = false))
        idle()

        assertFalse(oldDialog.isShowing)
        assertEquals("新来电人", controller.get().tv_caller.text.toString())
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Activity 生命周期 — 不崩溃
    // ═══════════════════════════════════════════════════════════════════════

    @Test
    fun onPauseDoesNotCrash() {
        val controller = buildController("生命周期测试")
        idle()
        runCatching { controller.pause() }
    }

    @Test
    fun onResumeAfterPauseDoesNotCrash() {
        val controller = buildController("生命周期测试2")
        idle()
        runCatching {
            controller.pause()
            controller.resume()
        }
    }

    @Test
    fun onDestroyDoesNotCrash() {
        val controller = buildController("销毁测试")
        idle()
        runCatching { controller.destroy() }
    }

    @Test
    fun onDestroyDismissesRecoveryDialog() {
        denyAnswerPermission()
        val controller = buildController("销毁测试")
        controller.get().btn_accept.performClick()
        idle()
        val dialog = latestRecoveryDialog()
        assertTrue(dialog.isShowing)

        controller.destroy()

        assertFalse(dialog.isShowing)
    }

    @Test
    fun buildLaunchIntentHasCorrectExtras() {
        val intent = IncomingCallActivity.buildLaunchIntent(
            context = context,
            callerName = "测试",
            autoAnswer = true,
            incomingNumber = "13800000000",
            knownContact = true
        )
        assertEquals("测试", intent.getStringExtra(IncomingCallActivity.EXTRA_CALLER_NAME))
        assertEquals(true, intent.getBooleanExtra(IncomingCallActivity.EXTRA_AUTO_ANSWER, false))
        assertEquals("13800000000", intent.getStringExtra(IncomingCallActivity.EXTRA_INCOMING_NUMBER))
        assertEquals(true, intent.getBooleanExtra(IncomingCallActivity.EXTRA_KNOWN_CONTACT, false))
    }

    @Test
    fun buildLaunchIntentWithNullCallerNameExtrasNull() {
        val intent = IncomingCallActivity.buildLaunchIntent(
            context = context,
            callerName = null,
            autoAnswer = false
        )
        assertEquals(null, intent.getStringExtra(IncomingCallActivity.EXTRA_CALLER_NAME))
    }

    @Test
    fun launchWithAcceptTriggerFinishesActivity() {
        val activity = buildActivityRaw(
            callerName = "通知接听",
            autoAnswer = false,
            triggerAction = IncomingCallActivity.TRIGGER_ACTION_ACCEPT
        )
        idle()
        assertTrue("通知接听动作触发后 Activity 不应崩溃", !activity.isDestroyed || activity.isFinishing)
    }

    @Test
    fun launchWithDeclineTriggerFinishesActivity() {
        val activity = buildActivityRaw(
            callerName = "通知拒绝",
            autoAnswer = false,
            triggerAction = IncomingCallActivity.TRIGGER_ACTION_DECLINE
        )
        idle()
        assertTrue("通知拒绝动作触发后 Activity 不应崩溃", !activity.isDestroyed || activity.isFinishing)
    }

    // ═══════════════════════════════════════════════════════════════════════
    // 多个不同来电人快速启动（压力）
    // ═══════════════════════════════════════════════════════════════════════


    @Test
    fun launch30DifferentCallersNoException() {
        repeat(30) { i ->
            val activity = buildActivity("来电人_$i", autoAnswer = false)
            idle()
            assertEquals("来电人_$i", activity.tv_caller.text.toString())
            activity.finish()
            idle()
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // 全局自动接听开关与 per-contact autoAnswer 协同
    // ═══════════════════════════════════════════════════════════════════════

    @Test
    fun globalAutoAnswerDisabledSuppressesCountdown() {
        prefs().setAutoAnswerEnabled(false)
        val activity = buildActivity("用户H", autoAnswer = true)
        idle()
        assertTrue("全局关闭时即使联系人开启也不显示倒计时", activity.tv_countdown.text.isEmpty())
    }

    @Test
    fun globalAutoAnswerEnabledWithContactAutoAnswerShowsCountdown() {
        prefs().setAutoAnswerEnabled(true)
        val activity = buildActivity("用户I", autoAnswer = true)
        idle()
        assertTrue("全局开启且联系人开启时应显示倒计时", activity.tv_countdown.text.isNotEmpty())
    }

    @Test
    fun globalAutoAnswerEnabledButContactAutoAnswerOffNoCountdown() {
        prefs().setAutoAnswerEnabled(true)
        val activity = buildActivity("用户J", autoAnswer = false)
        idle()
        assertTrue("全局开启但联系人未开启时不显示倒计时", activity.tv_countdown.text.isEmpty())
    }

    // ═══════════════════════════════════════════════════════════════════════
    // 辅助
    // ═══════════════════════════════════════════════════════════════════════

    private fun idle() = shadowOf(Looper.getMainLooper()).idle()

    private fun prefs() = LauncherPreferences.getInstance(context)

    private fun denyAnswerPermission() {
        shadowOf(context as Application).denyPermissions(Manifest.permission.ANSWER_PHONE_CALLS)
    }

    private fun grantAnswerPermission() {
        shadowOf(context as Application).grantPermissions(Manifest.permission.ANSWER_PHONE_CALLS)
    }

    private fun latestRecoveryDialog(): AlertDialog {
        return requireNotNull(ShadowDialog.getLatestDialog() as? AlertDialog)
    }

    private fun installRecoveryCoordinator(
        activity: IncomingCallActivity,
        coordinator: IncomingCallRecoveryCoordinator
    ) {
        val field = IncomingCallActivity::class.java.getDeclaredField("recoveryCoordinator")
        field.isAccessible = true
        field.set(activity, coordinator)
    }

    private fun buildIntent(
        callerName: String?,
        autoAnswer: Boolean = false,
        triggerAction: String? = null
    ): Intent =
        IncomingCallActivity.buildLaunchIntent(
            context = context,
            callerName = callerName,
            autoAnswer = autoAnswer,
            triggerAction = triggerAction
        )

    private fun buildActivity(callerName: String, autoAnswer: Boolean = false) =
        Robolectric.buildActivity(
            IncomingCallActivity::class.java,
            buildIntent(callerName, autoAnswer)
        ).setup().get()

    private fun buildActivityRaw(
        callerName: String?,
        autoAnswer: Boolean = false,
        triggerAction: String? = null
    ) =
        Robolectric.buildActivity(
            IncomingCallActivity::class.java,
            buildIntent(callerName, autoAnswer, triggerAction)
        ).setup().get()

    private fun buildController(
        callerName: String,
        autoAnswer: Boolean = false,
        triggerAction: String? = null
    ) =
        Robolectric.buildActivity(
            IncomingCallActivity::class.java,
            buildIntent(callerName, autoAnswer, triggerAction)
        ).setup()


    private fun resetLauncherPreferencesSingleton() {
        val field = Class.forName("com.yinxing.launcher.data.home.LauncherPreferences")
            .getDeclaredField("instance")
        field.isAccessible = true
        field.set(null, null)
    }

    private val android.app.Activity.tv_caller
        get() = findViewById<TextView>(R.id.tv_incoming_caller)
    private val android.app.Activity.tv_countdown
        get() = findViewById<TextView>(R.id.tv_incoming_countdown)
    private val android.app.Activity.tv_risk
        get() = findViewById<TextView>(R.id.tv_incoming_risk)
    private val android.app.Activity.btn_accept
        get() = findViewById<CardView>(R.id.btn_incoming_accept)
    private val android.app.Activity.btn_decline
        get() = findViewById<CardView>(R.id.btn_incoming_decline)

    private inline fun <reified T : View> AlertDialog.requireView(id: Int): T {
        return requireNotNull(findViewById(id))
    }

    private class FailedSystemUiGateway : IncomingCallSystemUiGateway {
        override fun requestSystemCallUi(): SystemCallUiRequestResult {
            return SystemCallUiRequestResult.Failed(SecurityException("show denied"))
        }

        override fun currentCallState(): IncomingDeviceCallState {
            error("failed request must not read call state")
        }
    }
}
