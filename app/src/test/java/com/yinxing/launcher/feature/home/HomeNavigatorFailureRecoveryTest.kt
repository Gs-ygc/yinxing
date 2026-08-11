package com.yinxing.launcher.feature.home

import android.app.Application
import android.content.Intent
import android.content.pm.ActivityInfo
import android.content.pm.ApplicationInfo
import android.content.pm.ResolveInfo
import androidx.test.core.app.ApplicationProvider
import com.yinxing.launcher.R
import com.yinxing.launcher.feature.settings.SettingsActivity
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowDialog

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class HomeNavigatorFailureRecoveryTest {
    private val context = ApplicationProvider.getApplicationContext<Application>()

    @Before
    fun setUp() {
        ShadowDialog.getLatestDialog()?.dismiss()
    }

    @Test
    fun unavailableAppShowsPersistentRecoveryDialog() {
        val activity = Robolectric.buildActivity(MainActivity::class.java).setup().get()
        val item = missingItem()
        val navigator = HomeNavigator(activity)
        navigator.openHomeItem(item)

        val dialog = ShadowDialog.getLatestDialog()
        assertNotNull(dialog)
        assertTrue(requireNotNull(dialog).isShowing)
        assertEquals(
            activity.getString(R.string.home_app_failure_title, item.appName),
            dialog.findViewById<android.widget.TextView>(R.id.tv_home_app_failure_title).text
                .toString()
        )
        assertEquals(
            activity.getString(R.string.home_app_failure_retry),
            dialog.findViewById<android.widget.TextView>(R.id.btn_home_app_retry).text.toString()
        )
        assertNull(shadowOf(activity).nextStartedActivity)
    }

    @Test
    fun caregiverSettingsActionOpensExistingSettingsActivity() {
        val activity = Robolectric.buildActivity(MainActivity::class.java).setup().get()
        HomeNavigator(activity).openHomeItem(missingItem())

        requireNotNull(ShadowDialog.getLatestDialog())
            .findViewById<android.view.View>(R.id.btn_home_app_settings)
            .performClick()

        assertEquals(
            SettingsActivity::class.java.name,
            shadowOf(activity).nextStartedActivity.component?.className
        )
        activity.finish()
    }

    @Test
    fun retryReusesLauncherAfterResolveFailureReleasesGate() {
        val activity = Robolectric.buildActivity(MainActivity::class.java).setup().get()
        val item = missingItem()
        val navigator = HomeNavigator(activity)

        navigator.openHomeItem(item)
        val dialog = requireNotNull(ShadowDialog.getLatestDialog())
        registerLauncherPackage(item.packageName)

        dialog.findViewById<android.view.View>(R.id.btn_home_app_retry).performClick()

        assertFalse(dialog.isShowing)
        assertEquals(item.packageName, shadowOf(activity).nextStartedActivity.component?.packageName)
        activity.finish()
    }

    @Test
    fun successfulAppLaunchDoesNotCreateFailureDialog() {
        val activity = Robolectric.buildActivity(MainActivity::class.java).setup().get()
        val item = HomeAppItem("pkg.camera", "相机", HomeAppItem.Type.APP)
        registerLauncherPackage(item.packageName)

        HomeNavigator(activity).openHomeItem(item)

        assertEquals(item.packageName, shadowOf(activity).nextStartedActivity.component?.packageName)
        assertFalse(ShadowDialog.getLatestDialog()?.isShowing == true)
        activity.finish()
    }

    @Test
    fun dismissTransientDialogsClosesFailureDialog() {
        val activity = Robolectric.buildActivity(MainActivity::class.java).setup().get()
        val navigator = HomeNavigator(activity)
        navigator.openHomeItem(missingItem())
        val dialog = requireNotNull(ShadowDialog.getLatestDialog())

        navigator.dismissTransientDialogs()

        assertFalse(dialog.isShowing)
        activity.finish()
    }

    private fun missingItem() = HomeAppItem(
        packageName = "com.example.missing",
        appName = "相机",
        type = HomeAppItem.Type.APP
    )

    @Suppress("DEPRECATION")
    private fun registerLauncherPackage(packageName: String) {
        val launcherIntent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        val applicationInfo = ApplicationInfo().apply {
            this.packageName = packageName
            nonLocalizedLabel = "相机"
        }
        val activityInfo = ActivityInfo().apply {
            this.packageName = packageName
            name = "$packageName.MainActivity"
            this.applicationInfo = applicationInfo
        }
        val resolveInfo = ResolveInfo().apply { this.activityInfo = activityInfo }
        shadowOf(context.packageManager).apply {
            addResolveInfoForIntent(launcherIntent, resolveInfo)
            addResolveInfoForIntent(Intent(launcherIntent).setPackage(packageName), resolveInfo)
        }
    }
}
