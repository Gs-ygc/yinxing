package com.yinxing.launcher.feature.home

import android.app.Activity
import android.content.Intent
import android.view.View
import android.view.ViewGroup
import android.widget.LinearLayout
import androidx.recyclerview.widget.ConcatAdapter
import androidx.recyclerview.widget.RecyclerView
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry

import com.yinxing.launcher.R
import com.yinxing.launcher.data.contact.Contact
import com.yinxing.launcher.feature.phone.PhoneContactActivity

import com.yinxing.launcher.feature.videocall.VideoCallActivity
import com.yinxing.launcher.testutil.InstrumentationTestEnvironment
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class MainActivityInstrumentedTest {
    @Before
    fun setUp() {
        InstrumentationTestEnvironment.resetAppState()
        InstrumentationTestEnvironment.primeLauncherRepositoryWithBuiltInOnlyHome()
    }

    @Test
    fun launchShowsBuiltInHomeItemsAndClock() {
        launchMainActivityScenario().use { scenario ->
            InstrumentationTestEnvironment.waitUntil(scenario, message = "主页未加载出内置入口") {
                homeAppItemCount(it.findViewById(R.id.recycler_home)) == 3
            }

            scenario.onActivity { activity ->
                val recyclerView = activity.findViewById<RecyclerView>(R.id.recycler_home)
                val timeText = activity.findViewById<android.widget.TextView>(R.id.tv_time).text
                val dateText = activity.findViewById<android.widget.TextView>(R.id.tv_date).text
                assertEquals(3, homeAppItemCount(recyclerView))
                assertTrue(timeText.isNotBlank())
                assertTrue(dateText.isNotBlank())
            }
        }
    }


    @Test
    fun clickPhoneEntryOpensPhoneContactActivity() {
        launchAndOpenHomeEntry(
            labelResId = R.string.home_item_phone,
            expectedActivity = PhoneContactActivity::class.java,
            failureMessage = "点击电话簿入口后未进入电话联系人页"
        )
    }


    @Test
    fun clickWechatVideoEntryOpensUnifiedContactActivity() {
        launchAndOpenHomeEntry(
            labelResId = R.string.home_item_wechat_video,
            expectedActivity = VideoCallActivity::class.java,
            failureMessage = "点击微信视频入口后未进入统一联系人页"
        )
    }

    @Test
    fun trustedContactsShowTwoShortcutsAndKeepFullListRoute() {
        InstrumentationTestEnvironment.seedPhoneContacts(
            Contact(
                id = "mother",
                name = "妈妈",
                phoneNumber = "13800138000",
                isPinned = true
            ),
            Contact(id = "father", name = "爸爸", phoneNumber = "13900139000")
        )

        launchMainActivityScenario().use { scenario ->
            InstrumentationTestEnvironment.waitUntil(
                scenario,
                message = "首页未显示两个常用电话快捷入口"
            ) { activity ->
                activity.findViewById<LinearLayout>(R.id.layout_trusted_call_items).childCount == 2
            }

            scenario.onActivity { activity ->
                val items = activity.findViewById<LinearLayout>(R.id.layout_trusted_call_items)
                assertEquals(
                    3,
                    homeAppItemCount(activity.findViewById(R.id.recycler_home))
                )
                assertEquals("拨打 妈妈", items.getChildAt(0).contentDescription.toString())
                assertEquals("拨打 爸爸", items.getChildAt(1).contentDescription.toString())
                activity.findViewById<View>(R.id.btn_trusted_calls_all).performClick()
            }
            InstrumentationTestEnvironment.waitForActivityInAnyStage(
                expectedActivity = PhoneContactActivity::class.java,
                message = "常用电话区域的全部电话按钮未进入联系人页"
            )
        }
    }

    private fun launchAndOpenHomeEntry(
        labelResId: Int,
        expectedActivity: Class<out Activity>,
        failureMessage: String
    ) {
        launchMainActivityScenario().use { scenario ->
            InstrumentationTestEnvironment.waitUntil(scenario, message = "主页入口未准备完成") {
                homeAppItemCount(it.findViewById(R.id.recycler_home)) == 3
            }

            val label = InstrumentationRegistry.getInstrumentation().targetContext.getString(labelResId)
            scenario.onActivity { activity ->
                activity.findViewById<RecyclerView>(R.id.recycler_home).scrollToPosition(1)
            }
            InstrumentationTestEnvironment.waitUntil(
                scenario,
                message = "首页入口未进入可见区域：$label"
            ) { activity ->
                findViewWithContentDescription(
                    activity.findViewById(R.id.recycler_home),
                    label
                ) != null
            }
            scenario.onActivity { activity ->
                val recyclerView = activity.findViewById<RecyclerView>(R.id.recycler_home)
                val clickableView = findViewWithContentDescription(recyclerView, label)
                assertNotNull("未找到首页入口：$label", clickableView)
                checkNotNull(clickableView).performClick()
            }
            InstrumentationTestEnvironment.waitForActivityInAnyStage(
                expectedActivity = expectedActivity,
                message = failureMessage
            )
        }
    }


    private fun launchMainActivityScenario(): ActivityScenario<MainActivity> {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val intent = Intent(context, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
        }
        return ActivityScenario.launch(intent)
    }


    private fun findViewWithContentDescription(root: View, description: String): View? {
        if (root.contentDescription?.toString() == description) {
            return root
        }
        if (root is ViewGroup) {
            for (index in 0 until root.childCount) {
                findViewWithContentDescription(root.getChildAt(index), description)?.let { found ->
                    return found
                }
            }
        }
        return null
    }

    private fun homeAppItemCount(recyclerView: RecyclerView): Int? =
        (recyclerView.adapter as? ConcatAdapter)
            ?.adapters
            ?.filterIsInstance<HomeAppAdapter>()
            ?.singleOrNull()
            ?.itemCount
}
