package com.yinxing.launcher.feature.home

import android.app.Activity
import android.content.Context
import android.graphics.Bitmap
import android.graphics.drawable.BitmapDrawable
import android.os.Looper
import android.view.ContextThemeWrapper
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.GridLayoutManager
import androidx.recyclerview.widget.RecyclerView
import androidx.test.core.app.ApplicationProvider
import com.google.android.material.card.MaterialCardView
import com.yinxing.launcher.R
import kotlinx.coroutines.CompletableDeferred
import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class HomeAppAdapterTest {
    private val context: Context = ApplicationProvider.getApplicationContext()
    private val themedContext = ContextThemeWrapper(context, R.style.Theme_OldLauncher)

    @Test
    fun firstBoundCardIsImmediatelyVisibleWithoutTranslation() {
        val owner = TestOwner()
        val adapter = HomeAppAdapter(
            scope = owner.lifecycleScope,
            lowPerformanceMode = false,
            onItemClick = {}
        )
        val parent = FrameLayout(themedContext)
        val holder = adapter.onCreateViewHolder(parent, HomeAppAdapter.VIEW_TYPE_APP)
        adapter.submitList(
            listOf(
                HomeAppItem(
                    packageName = "phone",
                    appName = "全部电话",
                    type = HomeAppItem.Type.PHONE,
                    iconResId = android.R.drawable.ic_menu_call
                )
            )
        )
        shadowOf(Looper.getMainLooper()).idle()

        adapter.onBindViewHolder(holder, 0)

        assertEquals(1f, holder.itemView.alpha, 0f)
        assertEquals(0f, holder.itemView.translationY, 0f)
    }

    @Test
    fun applicationCardLongPressIsAStableNoOp() {
        val owner = TestOwner()
        val adapter = HomeAppAdapter(
            scope = owner.lifecycleScope,
            lowPerformanceMode = false,
            onItemClick = {}
        )
        val parent = FrameLayout(themedContext)
        val holder = adapter.onCreateViewHolder(parent, HomeAppAdapter.VIEW_TYPE_APP)
        adapter.submitList(listOf(appItem("pkg.camera", "相机")))
        shadowOf(Looper.getMainLooper()).idle()
        adapter.onBindViewHolder(holder, 0)
        parent.addView(holder.itemView)

        assertTrue(!holder.itemView.performLongClick())
        assertTrue(!holder.itemView.findViewById<View>(R.id.icon).performLongClick())
    }

    @Test
    fun appCardUsesAdaptiveHeightWithStableMinimum() {
        val view = LayoutInflater.from(themedContext)
            .inflate(R.layout.item_home_app, FrameLayout(themedContext), false)
        val card = view.findViewById<MaterialCardView>(R.id.card_item)
        val content = card.getChildAt(0) as LinearLayout
        val name = view.findViewById<TextView>(R.id.name)

        assertEquals(ViewGroup.LayoutParams.WRAP_CONTENT, card.layoutParams.height)
        assertEquals(ViewGroup.LayoutParams.WRAP_CONTENT, content.layoutParams.height)
        assertTrue(card.minimumHeight >= 200.dp)
        assertTrue(content.minimumHeight >= 200.dp)
        assertEquals(2, name.maxLines)
    }

    @Test
    fun detachedCachedCardKeepsCompletedApplicationIcon() {
        val owner = TestOwner()
        val allowIconLoad = CompletableDeferred<Unit>()
        val loadedBitmap = Bitmap.createBitmap(2, 2, Bitmap.Config.ARGB_8888)
        val adapter = HomeAppAdapter(
            scope = owner.lifecycleScope,
            lowPerformanceMode = false,
            onItemClick = {},
            loadAppIcon = { _, _, _ ->
                allowIconLoad.await()
                loadedBitmap
            }
        )
        adapter.submitList(
            listOf(
                HomeAppItem(
                    packageName = context.packageName,
                    appName = "银杏",
                    type = HomeAppItem.Type.APP
                )
            )
        )
        waitUntil { adapter.currentList.size == 1 }
        val holder = adapter.onCreateViewHolder(
            FrameLayout(themedContext),
            HomeAppAdapter.VIEW_TYPE_APP
        ) as HomeAppAdapter.AppViewHolder
        adapter.onBindViewHolder(holder, 0)
        val placeholder = holder.icon.drawable
        val iconJob = requireNotNull(holder.iconJob)

        adapter.onViewDetachedFromWindow(holder)
        allowIconLoad.complete(Unit)
        waitUntil { iconJob.isCompleted }

        assertTrue(holder.icon.drawable !== placeholder)
        assertSame(loadedBitmap, (holder.icon.drawable as BitmapDrawable).bitmap)
    }

    @Test
    fun iconScaleChangeReloadsVisibleApplicationIconAtTheNewSize() {
        val requestedSizes = mutableListOf<Int>()
        val loadedBitmap = Bitmap.createBitmap(2, 2, Bitmap.Config.ARGB_8888)
        val adapter = HomeAppAdapter(
            scope = TestOwner().lifecycleScope,
            lowPerformanceMode = false,
            onItemClick = {},
            loadAppIcon = { _, _, size ->
                requestedSizes += size
                loadedBitmap
            }
        )
        val recyclerView = RecyclerView(themedContext).apply {
            layoutManager = GridLayoutManager(themedContext, 2)
            this.adapter = adapter
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
        }
        Robolectric.buildActivity(Activity::class.java).setup().get().setContentView(recyclerView)
        adapter.submitList(listOf(appItem("pkg.camera", "相机")))
        layout(recyclerView)
        waitUntil { requestedSizes.isNotEmpty() }
        val initialRequestCount = requestedSizes.size
        val initialSize = requestedSizes.last()

        adapter.setIconScale(150)
        layout(recyclerView)
        waitUntil { requestedSizes.size > initialRequestCount }

        assertTrue(requestedSizes.size > initialRequestCount)
        assertTrue(requestedSizes.last() > initialSize)
    }

    private class TestOwner : LifecycleOwner {
        private val registry = LifecycleRegistry(this)

        init {
            registry.currentState = Lifecycle.State.STARTED
        }

        override val lifecycle: Lifecycle
            get() = registry
    }

    private val Int.dp: Int
        get() = (this * context.resources.displayMetrics.density).toInt()

    private fun appItem(packageName: String, name: String) = HomeAppItem(
        packageName = packageName,
        appName = name,
        type = HomeAppItem.Type.APP
    )

    private fun layout(recyclerView: RecyclerView) {
        recyclerView.measure(
            View.MeasureSpec.makeMeasureSpec(1080, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(1920, View.MeasureSpec.EXACTLY)
        )
        recyclerView.layout(0, 0, 1080, 1920)
        shadowOf(Looper.getMainLooper()).idle()
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
}
