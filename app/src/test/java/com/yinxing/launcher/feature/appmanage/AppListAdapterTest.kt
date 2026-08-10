package com.yinxing.launcher.feature.appmanage

import android.app.Activity
import android.content.Context
import android.os.Looper
import android.view.ContextThemeWrapper
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.ImageButton
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.LinearLayoutManager
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
class AppListAdapterTest {
    private val context: Context = ApplicationProvider.getApplicationContext()
    private val themedContext = ContextThemeWrapper(context, R.style.Theme_OldLauncher)

    @Test
    fun selectedRowsExposeBoundedAccessibleMoveButtonsAndUnselectedRowsHideThem() {
        val movedUp = mutableListOf<AppInfo>()
        val movedDown = mutableListOf<AppInfo>()
        val adapter = AppListAdapter(
            scope = TestOwner().lifecycleScope,
            lowPerformanceMode = false,
            onCheckChanged = { _, _ -> },
            onMoveUp = { app -> movedUp += app },
            onMoveDown = { app -> movedDown += app }
        )
        val apps = listOf(
            AppInfo("pkg.camera", "相机", isSelected = true),
            AppInfo("pkg.gallery", "相册", isSelected = true),
            AppInfo("pkg.weather", "天气", isSelected = true),
            AppInfo("pkg.browser", "浏览器", isSelected = false)
        )
        val recyclerView = attachAndLayout(adapter, apps)
        val firstHolder = requireNotNull(recyclerView.findViewHolderForAdapterPosition(0))
        val secondHolder = requireNotNull(recyclerView.findViewHolderForAdapterPosition(1))
        val lastHolder = requireNotNull(recyclerView.findViewHolderForAdapterPosition(2))
        val unselectedHolder = requireNotNull(recyclerView.findViewHolderForAdapterPosition(3))

        val firstUp = firstHolder.itemView.findViewById<ImageButton>(R.id.btn_app_move_up)
        val firstDown = firstHolder.itemView.findViewById<ImageButton>(R.id.btn_app_move_down)
        val secondUp = secondHolder.itemView.findViewById<ImageButton>(R.id.btn_app_move_up)
        val lastDown = lastHolder.itemView.findViewById<ImageButton>(R.id.btn_app_move_down)
        val unselectedUp = unselectedHolder.itemView.findViewById<ImageButton>(R.id.btn_app_move_up)
        val unselectedDown = unselectedHolder.itemView.findViewById<ImageButton>(R.id.btn_app_move_down)

        assertEquals(View.VISIBLE, firstUp.visibility)
        assertFalse(firstUp.isEnabled)
        assertTrue(firstDown.isEnabled)
        assertEquals("下移 相机", firstDown.contentDescription.toString())
        assertEquals(View.GONE, unselectedUp.visibility)
        assertEquals(View.GONE, unselectedDown.visibility)

        assertTrue(firstDown.performClick())
        assertTrue(secondUp.performClick())
        firstUp.performClick()
        lastDown.performClick()

        assertEquals(listOf(apps[1]), movedUp)
        assertEquals(listOf(apps[0]), movedDown)
    }

    private fun attachAndLayout(adapter: AppListAdapter, apps: List<AppInfo>): RecyclerView {
        val activity = Robolectric.buildActivity(Activity::class.java).setup().get()
        val recyclerView = RecyclerView(themedContext).apply {
            layoutManager = LinearLayoutManager(themedContext)
            this.adapter = adapter
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
        }
        activity.setContentView(recyclerView)
        adapter.submitList(apps)
        waitUntil { adapter.currentList == apps }
        recyclerView.measure(
            View.MeasureSpec.makeMeasureSpec(1080, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(1920, View.MeasureSpec.EXACTLY)
        )
        recyclerView.layout(0, 0, 1080, 1920)
        shadowOf(Looper.getMainLooper()).idle()
        return recyclerView
    }

    private fun waitUntil(timeoutMs: Long = 5_000L, predicate: () -> Boolean) {
        val deadline = System.currentTimeMillis() + timeoutMs
        while (System.currentTimeMillis() < deadline) {
            shadowOf(Looper.getMainLooper()).idle()
            if (predicate()) return
            Thread.sleep(25)
        }
        shadowOf(Looper.getMainLooper()).idle()
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
