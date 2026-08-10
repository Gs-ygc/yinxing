package com.yinxing.launcher.feature.home

import android.content.Context
import android.os.Looper
import android.view.ContextThemeWrapper
import android.view.LayoutInflater
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry
import androidx.lifecycle.lifecycleScope
import androidx.test.core.app.ApplicationProvider
import com.google.android.material.card.MaterialCardView
import com.yinxing.launcher.R
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
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
            onItemClick = {},
            onOrderChanged = {}
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
}
