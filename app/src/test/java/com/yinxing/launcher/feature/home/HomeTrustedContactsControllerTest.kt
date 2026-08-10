package com.yinxing.launcher.feature.home

import android.content.Context
import android.view.LayoutInflater
import android.view.ContextThemeWrapper
import android.view.View
import android.widget.FrameLayout
import android.widget.LinearLayout
import androidx.test.core.app.ApplicationProvider
import com.yinxing.launcher.R
import com.yinxing.launcher.data.contact.Contact
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class HomeTrustedContactsControllerTest {
    private val context: Context = ApplicationProvider.getApplicationContext()
    private val themedContext: Context = ContextThemeWrapper(context, R.style.Theme_OldLauncher)

    @Test
    fun emptyContactsHideTheWholeSection() {
        val (root, controller) = createController()

        controller.render(emptyList())

        assertEquals(View.GONE, root.visibility)
        assertEquals(0, items(root).childCount)
    }

    @Test
    fun oneContactUsesOneLargeAccessibleAction() {
        val (root, controller) = createController()
        val contact = Contact("1", "妈妈", phoneNumber = "13800138000")
        var clicked: Contact? = null
        controller.setOnCallClick { clicked = it }

        controller.render(listOf(contact))

        assertEquals(View.VISIBLE, root.visibility)
        assertEquals(1, items(root).childCount)
        val item = items(root).getChildAt(0)
        assertEquals(root.resources.getString(R.string.contact_call_description, "妈妈"), item.contentDescription)
        assertTrue(item.isClickable)
        item.performClick()
        assertEquals(contact, clicked)
        assertEquals(View.VISIBLE, root.findViewById<View>(R.id.btn_trusted_calls_all).visibility)
    }

    @Test
    fun renderingTwoThenOneRemovesStaleAction() {
        val (root, controller) = createController()
        val first = Contact("1", "妈妈", phoneNumber = "13800138000")
        val second = Contact("2", "爸爸", phoneNumber = "13900139000")
        var openAllCount = 0
        controller.setOnOpenAllClick { openAllCount += 1 }

        controller.render(listOf(first, second))
        assertEquals(2, items(root).childCount)
        assertNotNull(items(root).getChildAt(1).contentDescription)

        controller.render(listOf(first))

        assertEquals(1, items(root).childCount)
        root.findViewById<View>(R.id.btn_trusted_calls_all).performClick()
        assertEquals(1, openAllCount)
    }

    private fun createController(): Pair<View, HomeTrustedContactsController> {
        val root = LayoutInflater.from(themedContext).inflate(
            R.layout.item_home_trusted_calls,
            FrameLayout(themedContext),
            false
        )
        return root to HomeTrustedContactsController(root)
    }

    private fun items(root: View): LinearLayout = root.findViewById(R.id.layout_trusted_call_items)
}
