package com.yinxing.launcher.feature.home

import android.Manifest
import android.app.Application
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.ActivityInfo
import android.content.pm.ApplicationInfo
import android.content.pm.ResolveInfo
import android.net.Uri
import android.os.Bundle
import android.os.Looper
import android.view.View
import android.view.ViewGroup
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.widget.NestedScrollView
import androidx.recyclerview.widget.RecyclerView
import androidx.test.core.app.ApplicationProvider
import com.yinxing.launcher.R
import com.yinxing.launcher.data.contact.Contact
import com.yinxing.launcher.data.contact.ContactSqliteStore
import com.yinxing.launcher.data.home.LauncherAppRepository
import com.yinxing.launcher.data.home.LauncherPreferences
import com.yinxing.launcher.data.settings.LauncherSettingsDataStore
import com.yinxing.launcher.feature.phone.PhoneContactActivity
import com.yinxing.launcher.feature.phone.PhoneContactManager
import com.yinxing.launcher.feature.phone.PhoneCallLauncher
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals

import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class MainActivitySmokeTest {
    private lateinit var context: Context

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        resetLauncherPreferencesSingleton()
        resetLauncherSettingsDataStoreSingleton()
        context.getSharedPreferences("launcher_prefs", Context.MODE_PRIVATE).edit().clear().commit()
        context.getSharedPreferences("home_app_config", Context.MODE_PRIVATE).edit().clear().commit()
        resetPhoneContactManager()
        ContactSqliteStore.deleteDatabase(context)
        LauncherAppRepository.getInstance(context).invalidateInstalledApps()
        LauncherAppRepository.getInstance(context).invalidateSelections()
    }

    @Test
    fun launchShowsBuiltInHomeItemsAndClock() {
        val activity = Robolectric.buildActivity(MainActivity::class.java).setup().get()

        val recyclerView = activity.findViewById<RecyclerView>(R.id.recycler_home)
        val statusCard = activity.findViewById<View>(R.id.card_home_status)
        val timeView = activity.findViewById<TextView>(R.id.tv_time)
        waitUntil {
            recyclerView.adapter?.itemCount == 3 && statusCard.visibility == View.GONE
        }

        assertEquals(3, recyclerView.adapter?.itemCount)
        assertEquals(View.GONE, statusCard.visibility)
        assertTrue(timeView.text.isNotBlank())
    }

    @Test
    fun selectedAppsStillAppearAfterFixedPhoneAndWechatEntries() {
        registerLauncherApp(packageName = "pkg.camera", appLabel = "Camera")
        registerLauncherApp(packageName = "pkg.browser", appLabel = "Browser")

        val preferences = LauncherPreferences(context)
        preferences.setPackageSelected("pkg.camera", true)
        preferences.setPackageSelected("pkg.browser", true)
        preferences.saveAppOrder(listOf("pkg.browser", "pkg.camera"))

        val activity = Robolectric.buildActivity(MainActivity::class.java).setup().get()
        val recyclerView = activity.findViewById<RecyclerView>(R.id.recycler_home)
        val statusCard = activity.findViewById<View>(R.id.card_home_status)
        waitUntil {
            recyclerView.adapter?.itemCount == 5 && statusCard.visibility == View.GONE
        }

        val adapter = recyclerView.adapter as HomeAppAdapter
        assertEquals(
            listOf("phone", "wechat_video", "pkg.browser", "pkg.camera", "add"),
            adapter.currentList.map { it.packageName }
        )
        assertEquals(View.GONE, statusCard.visibility)
    }

    @Test
    fun clickingWeatherCardFallsBackToBrowserWhenNoVendorWeatherApp() {
        registerWeatherBrowser()

        val activity = Robolectric.buildActivity(MainActivity::class.java).setup().get()
        activity.findViewById<View>(R.id.card_weather).performClick()

        val startedIntent = shadowOf(activity).nextStartedActivity
        assertNotNull(startedIntent)
        assertEquals(Intent.ACTION_VIEW, startedIntent.action)
        assertEquals(activity.getString(R.string.weather_fallback_url), startedIntent.dataString)
    }

    @Test
    fun noPhoneContactsKeepTrustedCallsSectionHidden() {
        val activity = Robolectric.buildActivity(MainActivity::class.java).setup().get()
        val recyclerView = activity.findViewById<RecyclerView>(R.id.recycler_home)
        waitUntil { recyclerView.adapter?.itemCount == 3 }

        assertEquals(View.GONE, activity.findViewById<View>(R.id.layout_trusted_calls).visibility)
    }

    @Test
    fun trustedContactsAppearWithoutChangingGridAndOpenFullList() {
        runBlocking {
            PhoneContactManager.getInstance(context).addContacts(
                listOf(
                    Contact(
                        id = "mother",
                        name = "妈妈",
                        phoneNumber = "13800138000",
                        isPinned = true
                    ),
                    Contact(id = "father", name = "爸爸", phoneNumber = "13900139000")
                )
            )
        }

        val activity = Robolectric.buildActivity(MainActivity::class.java).setup().get()
        val recyclerView = activity.findViewById<RecyclerView>(R.id.recycler_home)
        val section = activity.findViewById<View>(R.id.layout_trusted_calls)
        val items = activity.findViewById<LinearLayout>(R.id.layout_trusted_call_items)
        waitUntil {
            recyclerView.adapter?.itemCount == 3 &&
                section.visibility == View.VISIBLE &&
                items.childCount == 2
        }

        assertEquals(3, recyclerView.adapter?.itemCount)
        assertEquals(View.VISIBLE, section.visibility)
        assertEquals(2, items.childCount)
        assertEquals("拨打 妈妈", items.getChildAt(0).contentDescription.toString())
        assertEquals("拨打 爸爸", items.getChildAt(1).contentDescription.toString())

        activity.findViewById<View>(R.id.btn_trusted_calls_all).performClick()
        val startedIntent = shadowOf(activity).nextStartedActivity
        assertEquals(PhoneContactActivity::class.java.name, startedIntent.component?.className)
    }

    @Test
    fun pendingHomeCallContactSurvivesActivityRecreation() {
        val controller = Robolectric.buildActivity(MainActivity::class.java).setup()
        val activity = controller.get()
        val launcherField = MainActivity::class.java.getDeclaredField("phoneCallLauncher")
        launcherField.isAccessible = true
        val launcher = launcherField.get(activity) as PhoneCallLauncher
        launcher.restorePendingContact(
            Contact(id = "mother", name = "妈妈", phoneNumber = "13800138000")
        )
        val savedState = Bundle()

        controller.saveInstanceState(savedState)
        controller.pause().stop().destroy()

        val recreatedController = Robolectric.buildActivity(MainActivity::class.java)
            .create(savedState)
            .start()
            .resume()
            .visible()
        val recreatedLauncher = launcherField.get(recreatedController.get()) as PhoneCallLauncher

        assertEquals("mother", savedState.getString("state_home_pending_call_id"))
        assertEquals("妈妈", savedState.getString("state_home_pending_call_name"))
        assertEquals("13800138000", savedState.getString("state_home_pending_call_number"))
        assertEquals("mother", recreatedLauncher.pendingContactOrNull?.id)
        assertEquals("13800138000", recreatedLauncher.pendingContactOrNull?.phoneNumber)
        recreatedController.destroy()
    }

    @Test
    @Suppress("DEPRECATION")
    fun manifestAllowsHomeCallStateToBeSaved() {
        val activityInfo = context.packageManager.getActivityInfo(
            ComponentName(context, MainActivity::class.java),
            0
        )

        assertFalse(activityInfo.flags and ActivityInfo.FLAG_STATE_NOT_NEEDED != 0)
    }

    @Test
    fun homeUsesOneScrollableSurfaceOnCompactScreens() {
        val activity = Robolectric.buildActivity(MainActivity::class.java).setup().get()
        val homeContent = activity.findViewById<View>(R.id.layout_home_root)
        val recyclerView = activity.findViewById<RecyclerView>(R.id.recycler_home)

        assertTrue(homeContent.parent is NestedScrollView)
        assertEquals(ViewGroup.LayoutParams.WRAP_CONTENT, recyclerView.layoutParams.height)
        assertFalse(recyclerView.isNestedScrollingEnabled)
    }

    @Test
    fun homeStartsWithoutEntryAnimationDelay() {
        val activity = Robolectric.buildActivity(MainActivity::class.java).setup().get()

        assertEquals(1f, activity.findViewById<View>(R.id.layout_home_root).alpha)
        assertEquals(0f, activity.findViewById<View>(R.id.layout_home_root).translationY)
    }

    @Test
    fun trustedContactTapStartsDirectCallWhenPermissionGranted() {
        shadowOf(context as Application).grantPermissions(Manifest.permission.CALL_PHONE)
        runBlocking {
            PhoneContactManager.getInstance(context).addContact(
                Contact(id = "mother", name = "妈妈", phoneNumber = "13800138000")
            )
        }
        val activity = Robolectric.buildActivity(MainActivity::class.java).setup().get()
        val items = activity.findViewById<LinearLayout>(R.id.layout_trusted_call_items)
        waitUntil { items.childCount == 1 }

        items.getChildAt(0).performClick()

        val startedIntent = shadowOf(activity).nextStartedActivity
        assertEquals(Intent.ACTION_CALL, startedIntent.action)
        assertEquals("tel:13800138000", startedIntent.dataString)
    }


    @Suppress("DEPRECATION")
    private fun registerWeatherBrowser() {
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(context.getString(R.string.weather_fallback_url)))
        val applicationInfo = ApplicationInfo().apply {
            packageName = "com.android.browser"
            nonLocalizedLabel = "Browser"
        }
        val activityInfo = ActivityInfo().apply {
            packageName = "com.android.browser"
            name = "com.android.browser.BrowserActivity"
            this.applicationInfo = applicationInfo
        }
        val resolveInfo = ResolveInfo().apply {
            this.activityInfo = activityInfo
        }
        shadowOf(context.packageManager).addResolveInfoForIntent(intent, resolveInfo)
    }

    @Suppress("DEPRECATION")
    private fun registerLauncherApp(packageName: String, appLabel: String) {
        val launcherIntent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        val applicationInfo = ApplicationInfo().apply {
            this.packageName = packageName
            nonLocalizedLabel = appLabel
        }
        val activityInfo = ActivityInfo().apply {
            this.packageName = packageName
            name = "$packageName.MainActivity"
            this.applicationInfo = applicationInfo
        }
        val resolveInfo = ResolveInfo().apply {
            this.activityInfo = activityInfo
        }
        shadowOf(context.packageManager).addResolveInfoForIntent(launcherIntent, resolveInfo)
    }


    private fun resetLauncherPreferencesSingleton() {
        val field = Class.forName("com.yinxing.launcher.data.home.LauncherPreferences").getDeclaredField("instance")
        field.isAccessible = true
        field.set(null, null)
    }

    private fun resetLauncherSettingsDataStoreSingleton() {
        val field = Class.forName("com.yinxing.launcher.data.settings.LauncherSettingsDataStore").getDeclaredField("instance")
        field.isAccessible = true
        field.set(null, null)
    }

    private fun resetPhoneContactManager() {
        val field = PhoneContactManager::class.java.getDeclaredField("instance")
        field.isAccessible = true
        (field.get(null) as? PhoneContactManager)?.close()
        field.set(null, null)
    }

    private fun waitUntil(timeoutMs: Long = 5_000L, predicate: () -> Boolean) {
        val deadline = System.currentTimeMillis() + timeoutMs
        while (System.currentTimeMillis() < deadline) {
            shadowOf(Looper.getMainLooper()).idle()
            if (predicate()) {
                return
            }
            Thread.sleep(50)
        }
        shadowOf(Looper.getMainLooper()).idle()
    }
}
