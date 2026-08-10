package com.yinxing.launcher.common.ui

import android.content.Context
import android.content.res.Configuration
import android.text.TextUtils
import android.view.LayoutInflater
import android.view.View
import android.widget.FrameLayout
import android.widget.TextView
import androidx.test.core.app.ApplicationProvider
import com.yinxing.launcher.R
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import kotlin.math.roundToInt

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class FloatingStatusViewTest {
    private val context: Context = ApplicationProvider.getApplicationContext()

    @Test
    fun cancelActionIsExplicitLargeAndAccessible() {
        val root = LayoutInflater.from(context)
            .inflate(R.layout.floating_status, FrameLayout(context), false)
        val cancel = root.findViewById<TextView>(R.id.tv_cancel)

        assertEquals(context.getString(R.string.video_call_overlay_cancel), cancel.text.toString())
        assertEquals(
            context.getString(R.string.video_call_overlay_cancel_description),
            cancel.contentDescription.toString()
        )
        assertTrue(cancel.minimumWidth >= context.dp(56))
        assertTrue(cancel.minimumHeight >= context.dp(56))
        assertFalse(cancel.text.toString() == "×")
    }

    @Test
    fun ordinaryCancelTapInvokesListenerOnce() {
        val root = LayoutInflater.from(context)
            .inflate(R.layout.floating_status, FrameLayout(context), false)
        var cancellations = 0
        val statusView = FloatingStatusView(context)
        statusView.setOnCancelListener { cancellations += 1 }
        statusView.bindCancelAction(root)

        assertTrue(root.findViewById<View>(R.id.tv_cancel).performClick())
        assertEquals(1, cancellations)
    }

    @Test
    fun replacingCancelListenerUsesTheLatestCallback() {
        val root = LayoutInflater.from(context)
            .inflate(R.layout.floating_status, FrameLayout(context), false)
        var firstListenerCalls = 0
        var latestListenerCalls = 0
        val statusView = FloatingStatusView(context)
        statusView.setOnCancelListener { firstListenerCalls += 1 }
        statusView.bindCancelAction(root)
        statusView.setOnCancelListener { latestListenerCalls += 1 }

        assertTrue(root.findViewById<View>(R.id.tv_cancel).performClick())
        assertEquals(0, firstListenerCalls)
        assertEquals(1, latestListenerCalls)
    }

    @Test
    fun textBindingKeepsContactAndStatusSeparate() {
        val root = LayoutInflater.from(context)
            .inflate(R.layout.floating_status, FrameLayout(context), false)
        val statusView = FloatingStatusView(context)

        statusView.bindText(root, "正在联系 女儿", "正在打开微信")
        assertEquals("正在联系 女儿", root.findViewById<TextView>(R.id.tv_status).text.toString())
        assertEquals("正在打开微信", root.findViewById<TextView>(R.id.tv_status_step).text.toString())
        assertEquals(View.VISIBLE, root.findViewById<View>(R.id.tv_status_step).visibility)

        statusView.bindText(root, "正在联系 女儿", null)
        assertEquals(View.GONE, root.findViewById<View>(R.id.tv_status_step).visibility)
    }

    @Test
    fun largeTextAndLongCopyStayBoundedWithCancelReachable() {
        val largeTextContext = context.createConfigurationContext(
            Configuration(context.resources.configuration).apply { fontScale = 2f }
        )
        val root = LayoutInflater.from(largeTextContext)
            .inflate(R.layout.floating_status, FrameLayout(largeTextContext), false)
        val titleText = "正在联系 住在上海负责照护和联系的女儿小王以及紧急备用联系人小王家属"
        val statusText = "消息列表未找到，正在打开搜索并查找联系人，请稍候"
        FloatingStatusView(largeTextContext).bindText(root, titleText, statusText)

        val phoneWidth = largeTextContext.dp(360)
        val availableHeight = largeTextContext.dp(540)
        root.measure(
            View.MeasureSpec.makeMeasureSpec(phoneWidth, View.MeasureSpec.AT_MOST),
            View.MeasureSpec.makeMeasureSpec(availableHeight, View.MeasureSpec.AT_MOST)
        )
        root.layout(0, 0, root.measuredWidth, root.measuredHeight)

        val title = root.findViewById<TextView>(R.id.tv_status)
        val status = root.findViewById<TextView>(R.id.tv_status_step)
        val cancel = root.findViewById<View>(R.id.tv_cancel)
        val titleNode = title.createAccessibilityNodeInfo()
        val statusNode = status.createAccessibilityNodeInfo()
        assertEquals(2f, largeTextContext.resources.configuration.fontScale, 0f)
        assertEquals(3, title.maxLines)
        assertEquals(2, status.maxLines)
        assertEquals(TextUtils.TruncateAt.END, title.ellipsize)
        assertEquals(TextUtils.TruncateAt.END, status.ellipsize)
        assertEquals(titleText, title.text.toString())
        assertEquals(statusText, status.text.toString())
        assertEquals(titleText, titleNode.text.toString())
        assertEquals(statusText, statusNode.text.toString())
        assertTrue(root.measuredWidth <= phoneWidth)
        assertTrue(root.measuredHeight <= availableHeight)
        assertTrue(cancel.top >= 0)
        assertTrue(cancel.bottom <= root.measuredHeight)
    }

    private fun Context.dp(value: Int): Int =
        (value * resources.displayMetrics.density).roundToInt()
}
