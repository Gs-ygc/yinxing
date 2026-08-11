package com.yinxing.launcher.feature.incoming

import android.content.Context
import android.content.res.Configuration
import android.text.TextUtils
import android.view.MotionEvent
import android.view.View
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import androidx.core.graphics.ColorUtils
import androidx.core.view.ViewCompat
import androidx.core.widget.NestedScrollView
import com.google.android.material.button.MaterialButton
import com.google.android.material.card.MaterialCardView
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
        assertTrue(buttonContrast(systemCall) >= 4.5)
        controller.close()
    }

    @Test
    @Config(sdk = [34], qualifiers = "night")
    fun primaryActionKeepsHighContrastInNightMode() {
        val controller = Robolectric.buildActivity(IncomingCallFailureDialogTestActivity::class.java).setup()
        val activity = controller.get()
        val dialog = activity.showIncomingCallFailureDialog(
            callerName = "王大爷",
            action = IncomingCallFailedAction.ACCEPT,
            reason = reason(IncomingCallFailureCategory.CallAction),
            onOpenSystemCall = { SystemCallUiRequestResult.Requested },
            onRetry = {}
        )

        assertTrue(
            buttonContrast(
                dialog.requireView(R.id.btn_incoming_call_system_ui)
            ) >= 4.5
        )
        controller.close()
    }

    @Test
    fun dialogExposesPaneHeadingAndLiveFailureMessage() {
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
        val title = dialog.requireView<TextView>(R.id.tv_incoming_call_failure_title)
        val message = dialog.requireView<TextView>(R.id.tv_incoming_call_failure_message)
        val pane = requireNotNull(title.parent?.parent?.parent as? MaterialCardView)

        assertEquals(title.text, ViewCompat.getAccessibilityPaneTitle(pane))
        assertTrue(ViewCompat.isAccessibilityHeading(title))
        assertEquals(
            View.ACCESSIBILITY_LIVE_REGION_ASSERTIVE,
            message.accessibilityLiveRegion
        )
        dialog.requireView<View>(R.id.btn_incoming_call_system_ui).performClick()
        assertEquals(
            activity.getString(R.string.incoming_call_failure_system_ui_failed_message),
            message.text.toString()
        )
        assertEquals(
            View.ACCESSIBILITY_LIVE_REGION_ASSERTIVE,
            message.accessibilityLiveRegion
        )
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
    @Config(sdk = [34], qualifiers = "w360dp-h540dp")
    fun largeTextLayoutStaysBoundedAndActionsRemainReachableByScrolling() {
        val controller = Robolectric.buildActivity(
            LargeTextIncomingCallFailureDialogTestActivity::class.java
        ).setup()
        val activity = controller.get()
        val titleText =
            "住在上海负责照护和联系的女儿小王以及紧急备用联系人小王家属"
        val dialog = activity.showIncomingCallFailureDialog(
            callerName = titleText,
            action = IncomingCallFailedAction.ACCEPT,
            reason = reason(IncomingCallFailureCategory.PhonePermission),
            onOpenSystemCall = { SystemCallUiRequestResult.Requested },
            onRetry = {}
        )
        val title = dialog.requireView<TextView>(R.id.tv_incoming_call_failure_title)
        val message = dialog.requireView<TextView>(R.id.tv_incoming_call_failure_message)
        val scroll = dialog.requireView<NestedScrollView>(R.id.scroll_incoming_call_failure)
        val systemCall = dialog.requireView<MaterialButton>(R.id.btn_incoming_call_system_ui)
        val retry = dialog.requireView<MaterialButton>(R.id.btn_incoming_call_retry)
        val window = requireNotNull(dialog.window)
        val decor = window.decorView
        val phoneWidth = activity.resources.displayMetrics.widthPixels
        val availableHeight = activity.resources.displayMetrics.heightPixels
        val expectedDialogWidth = (phoneWidth * 0.92f).toInt()
        decor.measure(
            View.MeasureSpec.makeMeasureSpec(expectedDialogWidth, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(availableHeight, View.MeasureSpec.AT_MOST)
        )
        decor.layout(0, 0, decor.measuredWidth, decor.measuredHeight)
        scroll.fullScroll(View.FOCUS_DOWN)

        assertEquals(2f, activity.resources.configuration.fontScale, 0f)
        assertEquals(expectedDialogWidth, window.attributes.width)
        assertEquals(2, title.maxLines)
        assertEquals(TextUtils.TruncateAt.END, title.ellipsize)
        assertEquals(
            "还没有接通 $titleText",
            title.createAccessibilityNodeInfo().text.toString()
        )
        assertEquals(
            activity.getString(R.string.incoming_call_failure_permission_message),
            message.createAccessibilityNodeInfo().text.toString()
        )
        assertEquals("打开系统电话", systemCall.text.toString())
        assertEquals("重新接听", retry.text.toString())
        assertEquals(0, systemCall.totalEllipsisCount())
        assertEquals(0, retry.totalEllipsisCount())
        assertTrue(decor.measuredWidth <= phoneWidth)
        assertTrue(decor.measuredHeight <= availableHeight)
        assertTrue(systemCall.minimumHeight >= activity.dp(68))
        assertTrue(retry.minimumHeight >= activity.dp(68))
        assertTrue(retry.bottom - scroll.scrollY <= scroll.height)
        controller.close()
    }

    private fun reason(category: IncomingCallFailureCategory): IncomingCallFailureReason {
        return IncomingCallFailureReason(category, "technical detail")
    }

    private fun Context.dp(value: Int): Int =
        (value * resources.displayMetrics.density).roundToInt()

    private fun buttonContrast(button: MaterialButton): Double {
        val background = requireNotNull(button.backgroundTintList).defaultColor
        return ColorUtils.calculateContrast(button.currentTextColor, background)
    }

    private fun TextView.totalEllipsisCount(): Int {
        val textLayout = requireNotNull(layout)
        return (0 until textLayout.lineCount).sumOf(textLayout::getEllipsisCount)
    }

    private inline fun <reified T : View> androidx.appcompat.app.AlertDialog.requireView(id: Int): T {
        return requireNotNull(findViewById(id))
    }
}

class IncomingCallFailureDialogTestActivity : AppCompatActivity()

class LargeTextIncomingCallFailureDialogTestActivity : AppCompatActivity() {
    override fun attachBaseContext(newBase: Context) {
        val configuration = Configuration(newBase.resources.configuration).apply {
            fontScale = 2f
        }
        super.attachBaseContext(newBase.createConfigurationContext(configuration))
    }
}
