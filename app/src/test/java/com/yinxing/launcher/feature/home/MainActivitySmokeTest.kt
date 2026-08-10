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
import androidx.recyclerview.widget.ConcatAdapter
import androidx.recyclerview.widget.GridLayoutManager
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
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowToast

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
        waitUntil {
            homeAppItemCount(recyclerView) == 3 &&
                activity.findViewById<View>(R.id.card_home_status)?.visibility == View.GONE
        }
        val statusCard = requireNotNull(activity.findViewById<View>(R.id.card_home_status))
        val timeView = requireNotNull(activity.findViewById<TextView>(R.id.tv_time))

        assertEquals(3, homeAppItemCount(recyclerView))
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
        waitUntil {
            homeAppItemCount(recyclerView) == 5 &&
                activity.findViewById<View>(R.id.card_home_status)?.visibility == View.GONE
        }

        val adapter = requireNotNull(homeAppAdapter(recyclerView))
        val statusCard = requireNotNull(activity.findViewById<View>(R.id.card_home_status))
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
        waitUntil { activity.findViewById<View>(R.id.card_weather) != null }
        requireNotNull(activity.findViewById<View>(R.id.card_weather)).performClick()

        val startedIntent = shadowOf(activity).nextStartedActivity
        assertNotNull(startedIntent)
        assertEquals(Intent.ACTION_VIEW, startedIntent.action)
        assertEquals(activity.getString(R.string.weather_fallback_url), startedIntent.dataString)
    }

    @Test
    fun noPhoneContactsKeepTrustedCallsSectionHidden() {
        val activity = Robolectric.buildActivity(MainActivity::class.java).setup().get()
        val recyclerView = activity.findViewById<RecyclerView>(R.id.recycler_home)
        waitUntil { homeAppItemCount(recyclerView) == 3 }

        assertEquals(
            View.GONE,
            requireNotNull(activity.findViewById<View>(R.id.layout_trusted_calls)).visibility
        )
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
        waitUntil {
            homeAppItemCount(recyclerView) == 3 &&
                activity.findViewById<View>(R.id.layout_trusted_calls)?.visibility == View.VISIBLE &&
                activity.findViewById<LinearLayout>(R.id.layout_trusted_call_items)?.childCount == 2
        }
        val section = requireNotNull(activity.findViewById<View>(R.id.layout_trusted_calls))
        val items = requireNotNull(activity.findViewById<LinearLayout>(R.id.layout_trusted_call_items))

        assertEquals(3, homeAppItemCount(recyclerView))
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
    fun homeUsesVirtualizedRecyclerWithFullSpanHeaderOnCompactScreens() {
        val activity = Robolectric.buildActivity(MainActivity::class.java).setup().get()
        val recyclerView = activity.findViewById<RecyclerView>(R.id.recycler_home)

        assertEquals(ViewGroup.LayoutParams.MATCH_PARENT, recyclerView.layoutParams.height)
        assertTrue(recyclerView.isNestedScrollingEnabled)
        assertTrue(recyclerView.adapter is ConcatAdapter)
        val layoutManager = recyclerView.layoutManager as GridLayoutManager
        assertEquals(2, layoutManager.spanCount)
        assertEquals(2, layoutManager.spanSizeLookup.getSpanSize(0))
        assertEquals(1, layoutManager.spanSizeLookup.getSpanSize(1))
    }

    @Test
    fun manySelectedAppsOnlyBindVisibleRowsAndLastAppRemainsReachable() {
        val selectedPackages = (1..40).map { index -> "pkg.app$index" }
        selectedPackages.forEachIndexed { index, packageName ->
            registerLauncherApp(packageName, "应用 ${index + 1}")
        }
        LauncherPreferences(context).apply {
            selectedPackages.forEach { packageName ->
                setPackageSelected(packageName, true)
            }
            saveAppOrder(selectedPackages)
        }

        val activity = Robolectric.buildActivity(MainActivity::class.java).setup().get()
        val recyclerView = activity.findViewById<RecyclerView>(R.id.recycler_home)
        waitUntil { homeAppItemCount(recyclerView) == 43 }
        val totalRows = requireNotNull(recyclerView.adapter).itemCount

        assertEquals(44, totalRows)
        assertTrue(recyclerView.childCount < totalRows)

        recyclerView.scrollToPosition(totalRows - 1)
        shadowOf(Looper.getMainLooper()).idle()
        recyclerView.measure(
            View.MeasureSpec.makeMeasureSpec(1080, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(1920, View.MeasureSpec.EXACTLY)
        )
        recyclerView.layout(0, 0, 1080, 1920)

        assertNotNull(recyclerView.findViewHolderForAdapterPosition(totalRows - 1))
        assertTrue(recyclerView.childCount < totalRows)
    }

    @Test
    fun homeStartsWithoutEntryAnimationDelay() {
        val activity = Robolectric.buildActivity(MainActivity::class.java).setup().get()
        val recyclerView = activity.findViewById<RecyclerView>(R.id.recycler_home)

        assertEquals(1f, recyclerView.alpha)
        assertEquals(0f, recyclerView.translationY)
        assertEquals(null, recyclerView.itemAnimator)
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
        waitUntil {
            activity.findViewById<LinearLayout>(R.id.layout_trusted_call_items)?.childCount == 1
        }
        val items = requireNotNull(activity.findViewById<LinearLayout>(R.id.layout_trusted_call_items))

        items.getChildAt(0).performClick()

        val startedIntent = shadowOf(activity).nextStartedActivity
        assertEquals(Intent.ACTION_CALL, startedIntent.action)
        assertEquals("tel:13800138000", startedIntent.dataString)
    }

    @Test
    fun deniedHomeCallPermissionHandsNumberToDialerWithoutRecordingCall() {
        val contact = Contact(id = "mother", name = "妈妈", phoneNumber = "13800138000")
        runBlocking {
            PhoneContactManager.getInstance(context).addContact(contact)
        }
        val activity = Robolectric.buildActivity(MainActivity::class.java).setup().get()
        val launcherField = MainActivity::class.java.getDeclaredField("phoneCallLauncher").apply {
            isAccessible = true
        }
        val launcher = launcherField.get(activity) as PhoneCallLauncher

        launcher.restorePendingContact(contact)
        launcher.onPermissionResult(granted = false)

        val startedIntent = shadowOf(activity).nextStartedActivity
        assertEquals(Intent.ACTION_DIAL, startedIntent.action)
        assertEquals("tel:13800138000", startedIntent.dataString)
        assertEquals(0, PhoneContactManager.getInstance(context).getContacts().single().callCount)
    }

    @Test
    fun sameExternalAppTouchBurstStartsOnlyOneActivity() {
        registerLauncherApp(packageName = "pkg.camera", appLabel = "相机")
        LauncherPreferences(context).setPackageSelected("pkg.camera", true)
        val activity = Robolectric.buildActivity(MainActivity::class.java).setup().get()
        val recyclerView = activity.findViewById<RecyclerView>(R.id.recycler_home)
        waitUntil { homeAppItemCount(recyclerView) == 4 }
        val item = requireNotNull(homeAppAdapter(recyclerView))
            .currentList
            .single { it.packageName == "pkg.camera" }
        val navigatorField = MainActivity::class.java.getDeclaredField("navigator").apply {
            isAccessible = true
        }
        val navigator = navigatorField.get(activity) as HomeNavigator

        navigator.openHomeItem(item)
        navigator.openHomeItem(item)

        val firstIntent = shadowOf(activity).nextStartedActivity
        val duplicateIntent = shadowOf(activity).nextStartedActivity
        assertEquals("pkg.camera", firstIntent.component?.packageName)
        assertNull(duplicateIntent)
    }

    @Test
    fun unavailableExternalAppShowsFailureWithoutStartingActivity() {
        val activity = Robolectric.buildActivity(MainActivity::class.java).setup().get()
        val item = HomeAppItem(
            packageName = "com.example.missing",
            appName = "相机",
            type = HomeAppItem.Type.APP
        )

        HomeNavigator(activity).openHomeItem(item)

        assertNull(shadowOf(activity).nextStartedActivity)
        assertEquals(
            activity.getString(R.string.open_app_failed, "相机"),
            ShadowToast.getTextOfLatestToast()
        )
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
        shadowOf(context.packageManager).apply {
            addResolveInfoForIntent(launcherIntent, resolveInfo)
            addResolveInfoForIntent(Intent(launcherIntent).setPackage(packageName), resolveInfo)
        }
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

    private fun homeAppItemCount(recyclerView: RecyclerView): Int? =
        homeAppAdapter(recyclerView)?.itemCount

    private fun homeAppAdapter(recyclerView: RecyclerView): HomeAppAdapter? =
        (recyclerView.adapter as? ConcatAdapter)
            ?.adapters
            ?.filterIsInstance<HomeAppAdapter>()
            ?.singleOrNull()

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
