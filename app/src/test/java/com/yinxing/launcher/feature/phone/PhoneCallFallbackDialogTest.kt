package com.yinxing.launcher.feature.phone

import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import com.yinxing.launcher.R
import com.yinxing.launcher.data.contact.Contact
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class PhoneCallFallbackDialogTest {
    @Test
    fun blankContactNameUsesPlaceholder() {
        val controller = Robolectric.buildActivity(FallbackDialogTestActivity::class.java).setup()
        val activity = controller.get()
        val dialog = activity.showPhoneCallFallbackDialog(
            contact = Contact("legacy", "   ", phoneNumber = "13800138000"),
            directCallFailed = false,
            onDialerFailure = {}
        )
        val placeholder = activity.getString(R.string.contact_name_placeholder)

        assertEquals(
            activity.getString(R.string.phone_call_permission_fallback_title, placeholder),
            dialog.findViewById<TextView>(R.id.tv_call_permission_title)?.text.toString()
        )

        dialog.dismiss()
        controller.close()
    }
}

class FallbackDialogTestActivity : AppCompatActivity()
