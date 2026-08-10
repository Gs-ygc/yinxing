package com.yinxing.launcher.feature.home

import android.app.Activity
import android.content.Context
import android.os.Looper
import android.view.ContextThemeWrapper
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.ConcatAdapter
import androidx.recyclerview.widget.GridLayoutManager
import androidx.recyclerview.widget.RecyclerView
import androidx.test.core.app.ApplicationProvider
import com.yinxing.launcher.R
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class ItemMoveCallbackTest {
    private val context: Context = ApplicationProvider.getApplicationContext()
    private val themedContext = ContextThemeWrapper(context, R.style.Theme_OldLauncher)

    @Test
    fun headerCannotStartOrReceiveApplicationDrag() {
        val owner = TestOwner()
        val appAdapter = HomeAppAdapter(
            scope = owner.lifecycleScope,
            lowPerformanceMode = false,
            onItemClick = {},
            onOrderChanged = {}
        )
        appAdapter.submitList(
            listOf(
                HomeAppItem(
                    packageName = "pkg.camera",
                    appName = "相机",
                    type = HomeAppItem.Type.APP
                )
            )
        )
        shadowOf(Looper.getMainLooper()).idle()

        val headerAdapter = HomeHeaderAdapter({}, {}, {}, {}, {})
        val activity = Robolectric.buildActivity(Activity::class.java).setup().get()
        val recyclerView = RecyclerView(themedContext).apply {
            layoutManager = GridLayoutManager(themedContext, 2)
            adapter = ConcatAdapter(headerAdapter, appAdapter)
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
        }
        activity.setContentView(recyclerView)
        recyclerView.measure(
            View.MeasureSpec.makeMeasureSpec(1080, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(1920, View.MeasureSpec.EXACTLY)
        )
        recyclerView.layout(0, 0, 1080, 1920)
        shadowOf(Looper.getMainLooper()).idle()
        val headerHolder = requireNotNull(recyclerView.findViewHolderForAdapterPosition(0))
        val appHolder = requireNotNull(recyclerView.findViewHolderForAdapterPosition(1))
        val callback = ItemMoveCallback(appAdapter, animateDrag = true)

        assertEquals(0, callback.getMovementFlags(recyclerView, headerHolder))
        assertTrue(callback.getMovementFlags(recyclerView, appHolder) != 0)
        assertFalse(callback.onMove(recyclerView, appHolder, headerHolder))
        assertFalse(callback.onMove(recyclerView, headerHolder, appHolder))
    }

    private class TestOwner : LifecycleOwner {
        private val registry = LifecycleRegistry(this)

        init {
            registry.currentState = Lifecycle.State.STARTED
        }

        override val lifecycle: Lifecycle
            get() = registry
    }
}
