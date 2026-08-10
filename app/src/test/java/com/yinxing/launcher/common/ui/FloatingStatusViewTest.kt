package com.yinxing.launcher.common.ui

import android.content.Context
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

    private fun Context.dp(value: Int): Int =
        (value * resources.displayMetrics.density).roundToInt()
}
