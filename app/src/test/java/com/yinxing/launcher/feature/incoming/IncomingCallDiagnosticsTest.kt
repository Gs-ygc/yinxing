package com.yinxing.launcher.feature.incoming

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import com.yinxing.launcher.R
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class IncomingCallDiagnosticsTest {

    private lateinit var context: Context

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        IncomingCallDiagnostics.clear(context)
    }

    @Test
    fun emptyTraceShowsPlaceholder() {
        assertEquals(
            context.getString(R.string.settings_incoming_trace_empty),
            IncomingCallDiagnostics.getDisplayText(context)
        )
    }

    @Test
    fun successfulChainBuildsReadableSummary() {
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
        IncomingCallDiagnostics.recordSpeakerEnabled(context)

        assertEquals(
            listOf(
                context.getString(R.string.incoming_call_trace_broadcast),
                context.getString(R.string.incoming_call_trace_service),
                context.getString(R.string.incoming_call_trace_activity),
                context.getString(R.string.incoming_call_trace_accept_success),
                context.getString(R.string.incoming_call_trace_speaker_on)
            ).joinToString(" · "),
            IncomingCallDiagnostics.getSummaryText(context)
        )
        assertTrue(IncomingCallDiagnostics.getDisplayText(context).contains("张阿姨"))
        assertTrue(
            IncomingCallDiagnostics.getDisplayText(context)
                .contains(context.getString(R.string.incoming_call_status_speaker_on))
        )
    }

    @Test
    fun serviceStartFailureAppendsAfterBroadcastReceived() {
        IncomingCallDiagnostics.recordBroadcastReceived(
            context = context,
            callerLabel = "孙大爷",
            incomingNumber = "13700000000",
            autoAnswer = false
        )
        IncomingCallDiagnostics.recordServiceStartFailure(
            context = context,
            callerLabel = "孙大爷",
            throwable = IllegalStateException("foreground denied")
        )

        assertEquals(
            listOf(
                context.getString(R.string.incoming_call_trace_broadcast),
                context.getString(R.string.incoming_call_trace_service_failed)
            ).joinToString(" · "),
            IncomingCallDiagnostics.getSummaryText(context)
        )
        assertTrue(IncomingCallDiagnostics.getDisplayText(context).contains("孙大爷"))
        assertTrue(IncomingCallDiagnostics.getDisplayText(context).contains("foreground denied"))
    }

    @Test
    fun broadcastFailureIsIncludedInSummaryAndDetail() {
        IncomingCallDiagnostics.recordBroadcastFailure(
            context = context,
            callerLabel = "李叔叔",
            incomingNumber = "13900001111",
            throwable = IllegalStateException("receiver failed")
        )

        assertEquals(
            context.getString(R.string.incoming_call_trace_broadcast_failed),
            IncomingCallDiagnostics.getSummaryText(context)
        )
        assertTrue(IncomingCallDiagnostics.getDisplayText(context).contains("李叔叔"))
        assertTrue(IncomingCallDiagnostics.getDisplayText(context).contains("receiver failed"))
    }

    @Test
    fun failedThenSuccessfulRetryKeepsStepsButClearsCurrentFailure() {
        IncomingCallDiagnostics.recordAcceptFailure(
            context = context,
            detail = "first attempt failed",
            failureReason = IncomingCallFailureReason(
                IncomingCallFailureCategory.CallAction,
                "OEM rejected"
            )
        )

        IncomingCallDiagnostics.recordAcceptSuccess(context, "retry sent")

        val summary = IncomingCallDiagnostics.getSummaryText(context)
        assertTrue(summary.contains(context.getString(R.string.incoming_call_trace_accept_failed)))
        assertTrue(summary.contains(context.getString(R.string.incoming_call_trace_accept_success)))
        assertFalse(IncomingCallDiagnostics.getDisplayText(context).contains("失败分类"))
    }

    @Test
    fun systemUiRequestIsNotLabeledSuccessAndKeepsOriginalFailure() {
        IncomingCallDiagnostics.recordDeclineFailure(
            context = context,
            detail = "decline failed",
            failureReason = IncomingCallFailureReason(
                IncomingCallFailureCategory.PhonePermission,
                "permission missing"
            )
        )

        IncomingCallDiagnostics.recordSystemCallUiRequested(context)

        assertTrue(
            IncomingCallDiagnostics.getSummaryText(context).contains(
                context.getString(R.string.incoming_call_trace_system_ui_requested)
            )
        )
        assertTrue(IncomingCallDiagnostics.getDisplayText(context).contains("失败分类：电话权限"))
    }

    @Test
    fun systemUiRequestFailureKeepsActionCategoryAndAddsObservedError() {
        IncomingCallDiagnostics.recordAcceptFailure(
            context = context,
            detail = "accept failed",
            failureReason = IncomingCallFailureReason(
                IncomingCallFailureCategory.CallAction,
                "telecom rejected"
            )
        )

        IncomingCallDiagnostics.recordSystemCallUiRequestFailure(
            context,
            SecurityException("show screen denied")
        )

        val display = IncomingCallDiagnostics.getDisplayText(context)
        assertTrue(
            IncomingCallDiagnostics.getSummaryText(context).contains(
                context.getString(R.string.incoming_call_trace_system_ui_failed)
            )
        )
        assertTrue(display.contains("SecurityException"))
        assertTrue(display.contains("show screen denied"))
        assertTrue(display.contains("失败分类：接听指令：telecom rejected"))
    }

    @Test
    fun observedSystemAnswerClearsFailureAndRecordsAnswer() {
        IncomingCallDiagnostics.recordAcceptFailure(
            context,
            "accept failed",
            IncomingCallFailureReason(IncomingCallFailureCategory.CallAction, "failed")
        )

        IncomingCallDiagnostics.recordSystemCallUiAnswered(context)

        assertTrue(
            IncomingCallDiagnostics.getSummaryText(context).contains(
                context.getString(R.string.incoming_call_trace_system_ui_answered)
            )
        )
        assertFalse(IncomingCallDiagnostics.getDisplayText(context).contains("失败分类"))
    }

    @Test
    fun observedSystemCallEndClearsFailureAndRecordsEnd() {
        IncomingCallDiagnostics.recordDeclineFailure(
            context,
            "decline failed",
            IncomingCallFailureReason(IncomingCallFailureCategory.CallAction, "failed")
        )

        IncomingCallDiagnostics.recordSystemCallUiEnded(context)

        assertTrue(
            IncomingCallDiagnostics.getSummaryText(context).contains(
                context.getString(R.string.incoming_call_trace_system_ui_ended)
            )
        )
        assertFalse(IncomingCallDiagnostics.getDisplayText(context).contains("失败分类"))
    }
}
