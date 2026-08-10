package com.yinxing.launcher.feature.phone

import android.content.Context
import android.os.Bundle
import android.os.Looper
import android.view.View
import android.widget.TextView
import androidx.test.core.app.ApplicationProvider
import androidx.recyclerview.widget.RecyclerView
import com.google.android.material.card.MaterialCardView
import com.yinxing.launcher.R
import com.yinxing.launcher.data.contact.Contact
import com.yinxing.launcher.data.contact.ContactSqliteStore
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class PhoneContactActivitySmokeTest {
    private val context: Context = ApplicationProvider.getApplicationContext()

    @Before
    fun setUp() {
        resetPhoneContactManager()
        ContactSqliteStore.deleteDatabase(context)
    }

    @After
    fun tearDown() {
        resetPhoneContactManager()
    }

    @Test
    fun homeCallEntryHidesCaregiverManagementAction() {
        val controller = Robolectric.buildActivity(
            PhoneContactActivity::class.java,
            PhoneContactActivity.createIntent(context)
        ).setup()
        val activity = controller.get()
        shadowOf(Looper.getMainLooper()).idle()

        assertEquals(View.GONE, activity.findViewById<MaterialCardView>(R.id.btn_mode_action).visibility)
        assertEquals(
            activity.getString(R.string.phone_contact_call_summary),
            activity.findViewById<TextView>(R.id.tv_mode_summary).text.toString()
        )
        assertNull(activity.findViewById<RecyclerView>(R.id.recycler_phone_contacts).itemAnimator)
        controller.close()
    }

    @Test
    fun caregiverEntryKeepsAddActionVisible() {
        val controller = Robolectric.buildActivity(
            PhoneContactActivity::class.java,
            PhoneContactActivity.createIntent(context, startInManageMode = true)
        ).setup()
        val activity = controller.get()
        shadowOf(Looper.getMainLooper()).idle()

        assertEquals(View.VISIBLE, activity.findViewById<MaterialCardView>(R.id.btn_mode_action).visibility)
        assertEquals(
            activity.getString(R.string.action_add),
            activity.findViewById<TextView>(R.id.tv_mode_action).text.toString()
        )
        controller.close()
    }

    @Test
    fun pendingPermissionContactKeepsExistingSavedStateContract() {
        val controller = Robolectric.buildActivity(
            PhoneContactActivity::class.java,
            PhoneContactActivity.createIntent(context)
        ).setup()
        val activity = controller.get()
        val launcherField = PhoneContactActivity::class.java.getDeclaredField("phoneCallLauncher")
        launcherField.isAccessible = true
        val launcher = launcherField.get(activity) as PhoneCallLauncher
        launcher.restorePendingContact(
            Contact(
                id = "trusted-1",
                name = "妈妈",
                phoneNumber = "13800138000"
            )
        )
        val savedState = Bundle()

        controller.saveInstanceState(savedState)

        assertEquals("trusted-1", savedState.getString("state_pending_call_id"))
        assertEquals("妈妈", savedState.getString("state_pending_call_name"))
        assertEquals("13800138000", savedState.getString("state_pending_call_number"))
        controller.close()
    }

    private fun resetPhoneContactManager() {
        val field = PhoneContactManager::class.java.getDeclaredField("instance")
        field.isAccessible = true
        (field.get(null) as? PhoneContactManager)?.close()
        field.set(null, null)
    }
}
