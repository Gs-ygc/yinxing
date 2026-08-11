package com.yinxing.launcher.feature.incoming

import android.content.Context
import android.content.res.Configuration
import android.text.TextUtils
import android.view.ContextThemeWrapper
import android.view.LayoutInflater
import android.view.MotionEvent
import android.view.View
import android.widget.FrameLayout
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import androidx.core.widget.NestedScrollView
import androidx.test.core.app.ApplicationProvider
import com.google.android.material.button.MaterialButton
import com.yinxing.launcher.R
import kotlin.math.roundToInt
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class IncomingCallFailureDialogTest {

    @Test
    fun acceptFailureShowsCallerAndTwoLargeAccessibleActions() {
        val controller = Robolectric.buildActivity(IncomingCallFailureDialogTestActivity::class.java).setup()
        val activity = controller.get()

        val dialog = activity.showIncomingCallFailureDialog(
            callerName = "王大爷",
            action = IncomingCallFailedAction.ACCEPT,
            reason = reason(IncomingCallFailureCategory.CallAction),
            onOpenSystemCall = { SystemCallUiRequestResult.Requested },
            onRetry = {}
        )

        val title = dialog.requireView<TextView>(R.id.tv_incoming_call_failure_title)
        val message = dialog.requireView<TextView>(R.id.tv_incoming_call_failure_message)
        val systemCall = dialog.requireView<MaterialButton>(R.id.btn_incoming_call_system_ui)
        val retry = dialog.requireView<MaterialButton>(R.id.btn_incoming_call_retry)
        assertEquals("还没有接通 王大爷", title.text.toString())
        assertEquals(
            activity.getString(R.string.incoming_call_failure_action_message),
            message.text.toString()
        )
        assertEquals("打开系统电话", systemCall.text.toString())
        assertEquals("重新接听", retry.text.toString())
        assertTrue(systemCall.minimumHeight >= activity.dp(68))
        assertTrue(retry.minimumHeight >= activity.dp(68))
        assertEquals(systemCall.text, systemCall.contentDescription)
        assertEquals(retry.text, retry.contentDescription)
        controller.close()
    }

    @Test
    fun declineFailureUsesDeclineSpecificTitleAndRetry() {
        val controller = Robolectric.buildActivity(IncomingCallFailureDialogTestActivity::class.java).setup()
        val activity = controller.get()

        val dialog = activity.showIncomingCallFailureDialog(
            callerName = "李阿姨",
            action = IncomingCallFailedAction.DECLINE,
            reason = reason(IncomingCallFailureCategory.CallAction),
            onOpenSystemCall = { SystemCallUiRequestResult.Requested },
            onRetry = {}
        )

        assertEquals(
            "还没有挂断 李阿姨",
            dialog.requireView<TextView>(R.id.tv_incoming_call_failure_title).text.toString()
        )
        assertEquals(
            "重新挂断",
            dialog.requireView<MaterialButton>(R.id.btn_incoming_call_retry).text.toString()
        )
        controller.close()
    }

    @Test
    fun blankCallerUsesUnknownCallerLabel() {
        val controller = Robolectric.buildActivity(IncomingCallFailureDialogTestActivity::class.java).setup()
        val activity = controller.get()

        val dialog = activity.showIncomingCallFailureDialog(
            callerName = "   ",
            action = IncomingCallFailedAction.ACCEPT,
            reason = reason(IncomingCallFailureCategory.CallAction),
            onOpenSystemCall = { SystemCallUiRequestResult.Requested },
            onRetry = {}
        )

        assertEquals(
            "还没有接通 ${activity.getString(R.string.incoming_call_unknown_caller)}",
            dialog.requireView<TextView>(R.id.tv_incoming_call_failure_title).text.toString()
        )
        controller.close()
    }

    @Test
    fun failureCategorySelectsElderReadableMessage() {
        val controller = Robolectric.buildActivity(IncomingCallFailureDialogTestActivity::class.java).setup()
        val activity = controller.get()
        val expectations = listOf(
            IncomingCallFailureCategory.PhonePermission to
                R.string.incoming_call_failure_permission_message,
            IncomingCallFailureCategory.UnsupportedPlatform to
                R.string.incoming_call_failure_unsupported_message,
            IncomingCallFailureCategory.CallAction to
                R.string.incoming_call_failure_action_message
        )

        expectations.forEach { (category, messageRes) ->
            val dialog = activity.showIncomingCallFailureDialog(
                callerName = "测试来电",
                action = IncomingCallFailedAction.ACCEPT,
                reason = reason(category),
                onOpenSystemCall = { SystemCallUiRequestResult.Requested },
                onRetry = {}
            )
            assertEquals(
                activity.getString(messageRes),
                dialog.requireView<TextView>(R.id.tv_incoming_call_failure_message).text.toString()
            )
            dialog.dismiss()
        }
        controller.close()
    }

    @Test
    fun requestedSystemCallUiDismissesDialog() {
        val controller = Robolectric.buildActivity(IncomingCallFailureDialogTestActivity::class.java).setup()
        val activity = controller.get()
        var requests = 0
        val dialog = activity.showIncomingCallFailureDialog(
            callerName = "王大爷",
            action = IncomingCallFailedAction.ACCEPT,
            reason = reason(IncomingCallFailureCategory.CallAction),
            onOpenSystemCall = {
                requests += 1
                SystemCallUiRequestResult.Requested
            },
            onRetry = {}
        )

        dialog.requireView<View>(R.id.btn_incoming_call_system_ui).performClick()

        assertEquals(1, requests)
        assertFalse(dialog.isShowing)
        controller.close()
    }

    @Test
    fun failedSystemCallUiRequestKeepsDialogAndReplacesMessage() {
        val controller = Robolectric.buildActivity(IncomingCallFailureDialogTestActivity::class.java).setup()
        val activity = controller.get()
        val dialog = activity.showIncomingCallFailureDialog(
            callerName = "王大爷",
            action = IncomingCallFailedAction.ACCEPT,
            reason = reason(IncomingCallFailureCategory.PhonePermission),
            onOpenSystemCall = {
                SystemCallUiRequestResult.Failed(SecurityException("show denied"))
            },
            onRetry = {}
        )

        dialog.requireView<View>(R.id.btn_incoming_call_system_ui).performClick()

        assertTrue(dialog.isShowing)
        assertEquals(
            activity.getString(R.string.incoming_call_failure_system_ui_failed_message),
            dialog.requireView<TextView>(R.id.tv_incoming_call_failure_message).text.toString()
        )
        controller.close()
    }

    @Test
    fun retryDismissesDialogBeforeInvokingCallback() {
        val controller = Robolectric.buildActivity(IncomingCallFailureDialogTestActivity::class.java).setup()
        val activity = controller.get()
        var callbackSawDialogShowing = true
        lateinit var dialog: androidx.appcompat.app.AlertDialog
        dialog = activity.showIncomingCallFailureDialog(
            callerName = "王大爷",
            action = IncomingCallFailedAction.ACCEPT,
            reason = reason(IncomingCallFailureCategory.CallAction),
            onOpenSystemCall = { SystemCallUiRequestResult.Requested },
            onRetry = { callbackSawDialogShowing = dialog.isShowing }
        )

        dialog.requireView<View>(R.id.btn_incoming_call_retry).performClick()

        assertFalse(callbackSawDialogShowing)
        assertFalse(dialog.isShowing)
        controller.close()
    }

    @Test
    fun backCancelsButOutsideTouchDoesNot() {
        val controller = Robolectric.buildActivity(IncomingCallFailureDialogTestActivity::class.java).setup()
        val activity = controller.get()
        val outsideSafeDialog = activity.showIncomingCallFailureDialog(
            callerName = "王大爷",
            action = IncomingCallFailedAction.ACCEPT,
            reason = reason(IncomingCallFailureCategory.CallAction),
            onOpenSystemCall = { SystemCallUiRequestResult.Requested },
            onRetry = {}
        )
        val outside = MotionEvent.obtain(0L, 0L, MotionEvent.ACTION_OUTSIDE, -1f, -1f, 0)
        outsideSafeDialog.window?.decorView?.dispatchTouchEvent(outside)
        outside.recycle()
        assertTrue(outsideSafeDialog.isShowing)

        outsideSafeDialog.onBackPressed()

        assertFalse(outsideSafeDialog.isShowing)
        controller.close()
    }

    @Test
    fun largeTextLayoutStaysBoundedAndActionsRemainReachableByScrolling() {
        val baseContext: Context = ApplicationProvider.getApplicationContext()
        val largeTextContext = ContextThemeWrapper(
            baseContext.createConfigurationContext(
                Configuration(baseContext.resources.configuration).apply { fontScale = 2f }
            ),
            R.style.Theme_OldLauncher
        )
        val root = LayoutInflater.from(largeTextContext).inflate(
            R.layout.dialog_incoming_call_failure,
            FrameLayout(largeTextContext),
            false
        )
        val titleText = "还没有接通 住在上海负责照护和联系的女儿小王以及紧急备用联系人小王家属"
        val messageText = largeTextContext.getString(R.string.incoming_call_failure_permission_message)
        val title = root.findViewById<TextView>(R.id.tv_incoming_call_failure_title)
        val message = root.findViewById<TextView>(R.id.tv_incoming_call_failure_message)
        val scroll = root.findViewById<NestedScrollView>(R.id.scroll_incoming_call_failure)
        val systemCall = root.findViewById<MaterialButton>(R.id.btn_incoming_call_system_ui)
        val retry = root.findViewById<MaterialButton>(R.id.btn_incoming_call_retry)
        title.text = titleText
        message.text = messageText

        val phoneWidth = largeTextContext.dp(360)
        val availableHeight = largeTextContext.dp(540)
        root.measure(
            View.MeasureSpec.makeMeasureSpec(phoneWidth, View.MeasureSpec.AT_MOST),
            View.MeasureSpec.makeMeasureSpec(availableHeight, View.MeasureSpec.AT_MOST)
        )
        root.layout(0, 0, root.measuredWidth, root.measuredHeight)
        scroll.fullScroll(View.FOCUS_DOWN)

        assertEquals(2f, largeTextContext.resources.configuration.fontScale, 0f)
        assertEquals(2, title.maxLines)
        assertEquals(TextUtils.TruncateAt.END, title.ellipsize)
        assertEquals(titleText, title.createAccessibilityNodeInfo().text.toString())
        assertEquals(messageText, message.createAccessibilityNodeInfo().text.toString())
        assertTrue(root.measuredWidth <= phoneWidth)
        assertTrue(root.measuredHeight <= availableHeight)
        assertTrue(systemCall.minimumHeight >= largeTextContext.dp(68))
        assertTrue(retry.minimumHeight >= largeTextContext.dp(68))
        assertTrue(retry.bottom - scroll.scrollY <= scroll.height)
    }

    private fun reason(category: IncomingCallFailureCategory): IncomingCallFailureReason {
        return IncomingCallFailureReason(category, "technical detail")
    }

    private fun Context.dp(value: Int): Int =
        (value * resources.displayMetrics.density).roundToInt()

    private inline fun <reified T : View> androidx.appcompat.app.AlertDialog.requireView(id: Int): T {
        return requireNotNull(findViewById(id))
    }
}

class IncomingCallFailureDialogTestActivity : AppCompatActivity()
