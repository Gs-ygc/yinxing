package com.yinxing.launcher.feature.home

import android.util.TypedValue
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import com.google.android.material.button.MaterialButton
import com.yinxing.launcher.R
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class HomeAppFailureDialogTest {
    @Test
    fun dialogShowsElderFriendlyRecoveryActionsAndDismissesAfterRetry() {
        val controller = Robolectric.buildActivity(HomeAppFailureDialogTestActivity::class.java).setup()
        val activity = controller.get()
        var retryCount = 0
        var settingsCount = 0

        val dialog = activity.showHomeAppFailureDialog(
            item = HomeAppItem(
                packageName = "com.example.camera",
                appName = "相机",
                type = HomeAppItem.Type.APP
            ),
            onRetry = { retryCount++ },
            onOpenSettings = { settingsCount++ }
        )

        val title = dialog.findViewById<TextView>(R.id.tv_home_app_failure_title)!!
        val message = dialog.findViewById<TextView>(R.id.tv_home_app_failure_message)!!
        val retry = dialog.findViewById<MaterialButton>(R.id.btn_home_app_retry)!!
        val settings = dialog.findViewById<MaterialButton>(R.id.btn_home_app_settings)!!

        assertEquals("无法打开相机", title.text.toString())
        assertEquals(activity.getString(R.string.home_app_failure_message), message.text.toString())
        assertEquals(activity.getString(R.string.home_app_failure_retry), retry.text.toString())
        assertEquals(activity.getString(R.string.home_app_failure_settings), settings.text.toString())
        assertTrue(retry.minimumHeight >= activity.dp(68))
        assertTrue(settings.minimumHeight >= activity.dp(68))
        assertEquals(retry.text, retry.contentDescription)
        assertEquals(settings.text, settings.contentDescription)

        retry.performClick()

        assertEquals(1, retryCount)
        assertEquals(0, settingsCount)
        assertFalse(dialog.isShowing)
        controller.close()
    }

    @Test
    fun dialogDismissesAfterOpeningSettings() {
        val controller = Robolectric.buildActivity(HomeAppFailureDialogTestActivity::class.java).setup()
        val activity = controller.get()
        var retryCount = 0
        var settingsCount = 0

        val dialog = activity.showHomeAppFailureDialog(
            item = HomeAppItem(
                packageName = "com.example.camera",
                appName = "相机",
                type = HomeAppItem.Type.APP
            ),
            onRetry = { retryCount++ },
            onOpenSettings = { settingsCount++ }
        )

        dialog.findViewById<MaterialButton>(R.id.btn_home_app_settings)!!.performClick()

        assertEquals(0, retryCount)
        assertEquals(1, settingsCount)
        assertFalse(dialog.isShowing)
        controller.close()
    }

    private fun AppCompatActivity.dp(value: Int): Int = TypedValue.applyDimension(
        TypedValue.COMPLEX_UNIT_DIP,
        value.toFloat(),
        resources.displayMetrics
    ).toInt()
}

class HomeAppFailureDialogTestActivity : AppCompatActivity()
