package com.yinxing.launcher.feature.incoming

import android.content.Context
import android.view.View
import android.widget.TextView
import androidx.test.core.app.ApplicationProvider
import com.yinxing.launcher.R
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class IncomingCallStatusSmokeTest {

    private lateinit var context: Context

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        context.getSharedPreferences("launcher_prefs", Context.MODE_PRIVATE).edit().clear().commit()
        IncomingCallDiagnostics.clear(context)
        resetLauncherPreferencesSingleton()
    }

    @Test
    fun newIntentWithoutAutoAnswerHidesCountdown() {
        val controller = Robolectric.buildActivity(
            IncomingCallActivity::class.java,
            IncomingCallActivity.buildLaunchIntent(context, "李阿姨", autoAnswer = true)
        ).setup()

        controller.newIntent(
            IncomingCallActivity.buildLaunchIntent(context, "李阿姨", autoAnswer = false)
        )
        shadowOf(android.os.Looper.getMainLooper()).idle()

        val countdownView = controller.get().findViewById<TextView>(R.id.tv_incoming_countdown)
        assertEquals(View.GONE, countdownView.visibility)
        assertTrue(countdownView.text.isEmpty())
    }

    @Test
    fun recoveredSystemCallAnsweredMarksAnsweredAndFinishes() {
        val activity = buildActivity("王大爷")

        activity.applyRecoveryResumeDecision(IncomingCallResumeDecision.FINISH_ANSWERED)

        assertTrue(IncomingCallSessionState.current() is IncomingCallState.Answered)
        assertTrue(activity.isFinishing)
        assertTrue(
            IncomingCallDiagnostics.getSummaryText(context).contains("系统电话已接通")
        )
    }

    @Test
    fun recoveredSystemCallEndedReturnsToIdleAndFinishes() {
        val activity = buildActivity("李阿姨")

        activity.applyRecoveryResumeDecision(IncomingCallResumeDecision.FINISH_ENDED)

        assertTrue(IncomingCallSessionState.current() is IncomingCallState.Idle)
        assertTrue(activity.isFinishing)
        assertTrue(
            IncomingCallDiagnostics.getSummaryText(context).contains("系统来电已结束")
        )
    }

    @Test
    fun nonTerminalRecoveryDecisionsKeepIncomingActivityOpen() {
        listOf(
            IncomingCallResumeDecision.NO_PENDING,
            IncomingCallResumeDecision.KEEP_RINGING,
            IncomingCallResumeDecision.KEEP_UNKNOWN
        ).forEach { decision ->
            val activity = buildActivity("仍在响铃")

            activity.applyRecoveryResumeDecision(decision)

            assertFalse("$decision 不应关闭来电页", activity.isFinishing)
            activity.finish()
        }
    }

    private fun buildActivity(callerName: String): IncomingCallActivity {
        return Robolectric.buildActivity(
            IncomingCallActivity::class.java,
            IncomingCallActivity.buildLaunchIntent(context, callerName, autoAnswer = false)
        ).setup().get()
    }

    private fun resetLauncherPreferencesSingleton() {
        val field = Class.forName("com.yinxing.launcher.data.home.LauncherPreferences")
            .getDeclaredField("instance")
        field.isAccessible = true
        field.set(null, null)
    }
}
