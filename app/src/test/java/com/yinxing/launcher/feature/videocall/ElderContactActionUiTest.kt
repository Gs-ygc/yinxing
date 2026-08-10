package com.yinxing.launcher.feature.videocall

import android.content.Context
import android.os.Looper
import android.view.ContextThemeWrapper
import android.view.LayoutInflater
import android.view.View
import android.widget.FrameLayout
import androidx.core.content.ContextCompat
import androidx.core.widget.NestedScrollView
import androidx.appcompat.widget.SwitchCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry
import androidx.lifecycle.lifecycleScope
import androidx.test.core.app.ApplicationProvider
import com.google.android.material.button.MaterialButton
import com.google.android.material.card.MaterialCardView
import com.yinxing.launcher.R
import com.yinxing.launcher.data.contact.Contact
import com.yinxing.launcher.feature.phone.PhoneContactAdapter
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Shadows.shadowOf
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class ElderContactActionUiTest {
    private val context: Context = ApplicationProvider.getApplicationContext()
    private val themedContext: Context = ContextThemeWrapper(context, R.style.Theme_OldLauncher)

    @Test
    fun phoneContactActionButtonUsesLargeGreenTouchTarget() {
        val view = LayoutInflater.from(themedContext)
            .inflate(R.layout.item_phone_contact, FrameLayout(themedContext), false)
        val button = view.findViewById<MaterialButton>(R.id.btn_call)

        assertTrue(button.minHeight >= 76.dp)
        assertTrue(button.textSize >= 22.sp)
        assertEquals(
            ContextCompat.getColor(context, R.color.launcher_phone_action),
            button.backgroundTintList?.defaultColor
        )
    }

    @Test
    fun phoneContactCardIsClickableByDefaultForOneStepCalling() {
        val owner = TestOwner()
        var callCount = 0
        val adapter = PhoneContactAdapter(
            scope = owner.lifecycleScope,
            onCallClick = { callCount += 1 },
            onEditClick = {}
        )
        val parent = FrameLayout(themedContext)
        val holder = adapter.onCreateViewHolder(parent, 0)
        adapter.submitList(
            listOf(
                Contact(
                    id = "phone-card",
                    name = "爸爸",
                    phoneNumber = "13800138000"
                )
            )
        )
        shadowOf(Looper.getMainLooper()).idle()

        adapter.onBindViewHolder(holder, 0)

        assertTrue(holder.itemView.isClickable)
        assertTrue(holder.itemView.performClick())
        assertEquals(1, callCount)
        assertEquals(1f, holder.itemView.alpha, 0f)
        assertEquals(View.IMPORTANT_FOR_ACCESSIBILITY_YES, holder.itemView.importantForAccessibility)
        assertEquals(View.IMPORTANT_FOR_ACCESSIBILITY_NO, holder.avatar.importantForAccessibility)
        assertEquals(View.IMPORTANT_FOR_ACCESSIBILITY_NO, holder.name.importantForAccessibility)
        assertEquals(View.IMPORTANT_FOR_ACCESSIBILITY_NO, holder.phone.importantForAccessibility)
        assertEquals(View.IMPORTANT_FOR_ACCESSIBILITY_NO, holder.btnCall.importantForAccessibility)
    }

    @Test
    fun phoneContactCardCanBeRestrictedToCallButtonByCaregiver() {
        val owner = TestOwner()
        var callCount = 0
        val adapter = PhoneContactAdapter(
            scope = owner.lifecycleScope,
            onCallClick = { callCount += 1 },
            onEditClick = {}
        )
        val parent = FrameLayout(themedContext)
        val holder = adapter.onCreateViewHolder(parent, 0)
        adapter.submitList(
            listOf(Contact(id = "phone-button", name = "妈妈", phoneNumber = "13900139000"))
        )
        shadowOf(Looper.getMainLooper()).idle()
        adapter.setFullCardTapEnabled(false)
        adapter.onBindViewHolder(holder, 0)

        assertTrue(!holder.itemView.isClickable)
        holder.btnCall.performClick()
        assertEquals(1, callCount)
        assertEquals(View.IMPORTANT_FOR_ACCESSIBILITY_NO, holder.itemView.importantForAccessibility)
        assertEquals(View.IMPORTANT_FOR_ACCESSIBILITY_YES, holder.btnCall.importantForAccessibility)
    }

    @Test
    fun callPermissionFallbackHasLargeDialerAction() {
        val view = LayoutInflater.from(themedContext)
            .inflate(R.layout.dialog_call_permission_fallback, FrameLayout(themedContext), false)
        val button = view.findViewById<MaterialCardView>(R.id.btn_open_dialer)

        assertTrue(button.minimumHeight >= 64.dp)
        assertTrue(button.isClickable)
        assertEquals(context.getString(R.string.phone_call_open_dialer), button.contentDescription)
    }

    @Test
    fun caregiverCallSettingsScrollAndExposeNamedSwitches() {
        val view = LayoutInflater.from(themedContext)
            .inflate(R.layout.sheet_settings_auto_answer, FrameLayout(themedContext), false)

        assertNotNull(view.findViewById<NestedScrollView>(R.id.scroll_auto_answer_sheet))
        assertEquals(
            context.getString(R.string.settings_phone_full_card_tap_title),
            view.findViewById<SwitchCompat>(R.id.switch_phone_full_card_tap_sheet).contentDescription
        )
        assertEquals(
            context.getString(R.string.settings_full_card_tap_title),
            view.findViewById<SwitchCompat>(R.id.switch_full_card_tap_sheet).contentDescription
        )
    }

    @Test
    fun videoContactPhoneFallbackUsesPhoneTextAndGreenAction() {
        val owner = TestOwner()
        val adapter = VideoCallContactAdapter(
            scope = owner.lifecycleScope,
            lowPerformanceMode = true,
            onContactClick = {},
            onWechatVideoClick = {}
        )
        val parent = FrameLayout(themedContext)
        val holder = adapter.onCreateViewHolder(parent, 0)
        adapter.submitList(
            listOf(
                Contact(
                    id = "phone",
                    name = "爸爸",
                    phoneNumber = "13800138000",
                    preferredAction = Contact.PreferredAction.PHONE
                )
            )
        )
        shadowOf(Looper.getMainLooper()).idle()

        adapter.onBindViewHolder(holder, 0)

        val button = holder.itemView.findViewById<MaterialButton>(R.id.btn_video_call)
        assertEquals(context.getString(R.string.contact_card_action_phone_v2), button.text.toString())
        assertEquals(
            ContextCompat.getColor(context, R.color.launcher_phone_action),
            button.backgroundTintList?.defaultColor
        )
    }

    @Test
    fun videoContactDefaultsToOneButtonActionAndOneAccessibilityTarget() {
        val owner = TestOwner()
        var callCount = 0
        val adapter = VideoCallContactAdapter(
            scope = owner.lifecycleScope,
            lowPerformanceMode = true,
            onContactClick = { callCount += 1 },
            onWechatVideoClick = { callCount += 1 }
        )
        val parent = FrameLayout(themedContext)
        val holder = adapter.onCreateViewHolder(parent, 0)
        adapter.submitList(
            listOf(
                Contact(
                    id = "video-button-only",
                    name = "女儿",
                    wechatId = "女儿",
                    preferredAction = Contact.PreferredAction.WECHAT_VIDEO
                )
            )
        )
        shadowOf(Looper.getMainLooper()).idle()

        adapter.onBindViewHolder(holder, 0)

        assertFalse(holder.card.isClickable)
        assertFalse(holder.photo.isClickable)
        assertFalse(holder.name.isClickable)
        assertEquals(View.IMPORTANT_FOR_ACCESSIBILITY_NO, holder.card.importantForAccessibility)
        assertEquals(View.IMPORTANT_FOR_ACCESSIBILITY_NO, holder.photo.importantForAccessibility)
        assertEquals(View.IMPORTANT_FOR_ACCESSIBILITY_NO, holder.name.importantForAccessibility)
        assertEquals(View.IMPORTANT_FOR_ACCESSIBILITY_YES, holder.btnVideoCall.importantForAccessibility)
        holder.btnVideoCall.performClick()
        assertEquals(1, callCount)
    }

    @Test
    fun videoContactFullCardModeStillExposesOnlyOneAccessibilityAction() {
        val owner = TestOwner()
        val adapter = VideoCallContactAdapter(
            scope = owner.lifecycleScope,
            lowPerformanceMode = true,
            onContactClick = {},
            onWechatVideoClick = {}
        )
        val parent = FrameLayout(themedContext)
        val holder = adapter.onCreateViewHolder(parent, 0)
        adapter.submitList(
            listOf(
                Contact(
                    id = "video-card",
                    name = "女儿",
                    wechatId = "女儿",
                    preferredAction = Contact.PreferredAction.WECHAT_VIDEO
                )
            )
        )
        shadowOf(Looper.getMainLooper()).idle()
        adapter.setFullCardTapEnabled(true)
        adapter.onBindViewHolder(holder, 0)

        assertTrue(holder.card.isClickable)
        assertEquals(View.IMPORTANT_FOR_ACCESSIBILITY_YES, holder.card.importantForAccessibility)
        assertEquals(View.IMPORTANT_FOR_ACCESSIBILITY_NO, holder.photo.importantForAccessibility)
        assertEquals(View.IMPORTANT_FOR_ACCESSIBILITY_NO, holder.name.importantForAccessibility)
        assertEquals(View.IMPORTANT_FOR_ACCESSIBILITY_NO, holder.btnVideoCall.importantForAccessibility)
    }

    @Test
    fun videoContactWechatActionUsesLargeBlueTouchTarget() {
        val view = LayoutInflater.from(themedContext)
            .inflate(R.layout.item_video_contact, FrameLayout(themedContext), false)
        val button = view.findViewById<MaterialButton>(R.id.btn_video_call)

        assertTrue(button.minHeight >= 76.dp)
        assertTrue(button.textSize >= 22.sp)
        assertEquals(
            ContextCompat.getColor(context, R.color.launcher_video_action),
            button.backgroundTintList?.defaultColor
        )
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

    private val Int.sp: Float
        get() = this * context.resources.displayMetrics.scaledDensity
}
