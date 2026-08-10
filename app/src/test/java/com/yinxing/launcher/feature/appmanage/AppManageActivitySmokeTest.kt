package com.yinxing.launcher.feature.appmanage

import android.content.Context
import android.content.Intent
import android.content.pm.ActivityInfo
import android.content.pm.ApplicationInfo
import android.content.pm.ResolveInfo
import android.os.Looper
import android.view.View
import android.widget.TextView
import androidx.test.core.app.ApplicationProvider
import com.yinxing.launcher.data.home.HomeAppConfig
import com.yinxing.launcher.data.home.LauncherAppRepository
import com.yinxing.launcher.data.home.LauncherPreferences
import com.yinxing.launcher.data.settings.LauncherSettingsDataStore
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import androidx.recyclerview.widget.RecyclerView

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class AppManageActivitySmokeTest {
    private lateinit var context: Context
    private lateinit var preferences: LauncherPreferences

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        resetLauncherPreferencesSingleton()
        resetLauncherSettingsDataStoreSingleton()
        context.getSharedPreferences("launcher_prefs", Context.MODE_PRIVATE).edit().clear().commit()
        HomeAppConfig(context).clear()
        LauncherAppRepository.getInstance(context).invalidateInstalledApps()
        LauncherAppRepository.getInstance(context).invalidateSelections()
        preferences = LauncherPreferences(context)
    }

    @Test
    fun movingSelectedApplicationPersistsAndRefreshesVisibleOrder() {
        registerLauncherApp("pkg.zebra", "Zebra")
        registerLauncherApp("pkg.alpha", "Alpha")
        registerLauncherApp("pkg.beta", "Beta")
        preferences.setPackageSelected("pkg.zebra", true)
        preferences.setPackageSelected("pkg.alpha", true)
        preferences.saveAppOrder(listOf("pkg.zebra", "pkg.alpha"))

        val controller = Robolectric.buildActivity(AppManageActivity::class.java).setup()
        val activity = controller.get()
        val adapter = activityAdapter(activity)
        waitUntil { adapter.currentList.map { it.packageName } == listOf("pkg.zebra", "pkg.alpha", "pkg.beta") }

        waitUntil {
            activity.recyclerView().findViewHolderForAdapterPosition(0)
                ?.itemView
                ?.findViewById<TextView>(com.yinxing.launcher.R.id.app_name)
                ?.text == "Zebra" &&
                activity.recyclerView().findViewHolderForAdapterPosition(0)
                    ?.itemView
                ?.findViewById<View>(com.yinxing.launcher.R.id.btn_app_move_down)
                ?.isEnabled == true
        }
        val firstHolder = requireNotNull(activity.recyclerView().findViewHolderForAdapterPosition(0))
        val firstDown = firstHolder.itemView.findViewById<View>(com.yinxing.launcher.R.id.btn_app_move_down)
        assertTrue(firstDown.performClick())
        waitUntil {
            preferences.getAppOrder() == listOf("pkg.alpha", "pkg.zebra") &&
                adapter.currentList.filter { it.isSelected }.map { it.packageName } ==
                listOf("pkg.alpha", "pkg.zebra")
        }

        assertEquals(listOf("pkg.alpha", "pkg.zebra"), preferences.getAppOrder())
        assertEquals(
            listOf("pkg.alpha", "pkg.zebra"),
            adapter.currentList.filter { it.isSelected }.map { it.packageName }
        )
        controller.destroy()
    }

    @Test
    fun rapidMovesUseLatestOrderAndSelectionRegroupsImmediately() {
        registerLauncherApp("pkg.alpha", "Alpha")
        registerLauncherApp("pkg.beta", "Beta")
        registerLauncherApp("pkg.gamma", "Gamma")
        registerLauncherApp("pkg.unselected", "未选应用")
        preferences.setPackageSelected("pkg.alpha", true)
        preferences.setPackageSelected("pkg.beta", true)
        preferences.setPackageSelected("pkg.gamma", true)
        preferences.saveAppOrder(listOf("pkg.alpha", "pkg.beta", "pkg.gamma"))

        val controller = Robolectric.buildActivity(AppManageActivity::class.java).setup()
        val activity = controller.get()
        val adapter = activityAdapter(activity)
        waitUntil { adapter.currentList.filter { it.isSelected }.map { it.packageName } == listOf("pkg.alpha", "pkg.beta", "pkg.gamma") }

        waitUntil {
            activity.recyclerView().findViewHolderForAdapterPosition(0)
                ?.itemView
                ?.findViewById<TextView>(com.yinxing.launcher.R.id.app_name)
                ?.text == "Alpha" &&
                activity.recyclerView().findViewHolderForAdapterPosition(0)
                    ?.itemView
                ?.findViewById<View>(com.yinxing.launcher.R.id.btn_app_move_down)
                ?.isEnabled == true
        }
        val firstDown = requireNotNull(activity.recyclerView().findViewHolderForAdapterPosition(0))
            .itemView.findViewById<View>(com.yinxing.launcher.R.id.btn_app_move_down)
        assertTrue(firstDown.performClick())
        assertTrue(firstDown.performClick())
        assertEquals(listOf("pkg.beta", "pkg.gamma", "pkg.alpha"), preferences.getAppOrder())
        waitUntil {
            adapter.currentList.filter { it.isSelected }.map { it.packageName } ==
                listOf("pkg.beta", "pkg.gamma", "pkg.alpha")
        }

        val unselectedPackage = adapter.currentList.first { !it.isSelected }.packageName
        val unselectedIndex = adapter.currentList.indexOfFirst { it.packageName == unselectedPackage }
        waitUntil {
            activity.recyclerView().findViewHolderForAdapterPosition(unselectedIndex)
                ?.itemView
                ?.findViewById<TextView>(com.yinxing.launcher.R.id.app_name)
                ?.text == adapter.currentList[unselectedIndex].appName
        }
        requireNotNull(activity.recyclerView().findViewHolderForAdapterPosition(unselectedIndex))
            .itemView
            .findViewById<View>(com.yinxing.launcher.R.id.app_checkbox)
            .performClick()
        waitUntil {
            preferences.isPackageSelected(unselectedPackage) &&
                adapter.currentList.firstOrNull()?.packageName == "pkg.beta" &&
                activity.recyclerView()
                    .findViewHolderForAdapterPosition(adapter.currentList.indexOfFirst { it.packageName == unselectedPackage })
                    ?.itemView
                    ?.findViewById<android.widget.CheckBox>(com.yinxing.launcher.R.id.app_checkbox)
                    ?.isChecked == true
        }
        assertEquals(
            listOf("pkg.beta", "pkg.gamma", "pkg.alpha", unselectedPackage),
            preferences.getAppOrder()
        )

        val selectedIndex = adapter.currentList.indexOfFirst { it.packageName == unselectedPackage }
        waitUntil {
            activity.recyclerView().findViewHolderForAdapterPosition(selectedIndex)
                ?.itemView
                ?.findViewById<android.widget.CheckBox>(com.yinxing.launcher.R.id.app_checkbox)
                ?.isChecked == true
        }
        requireNotNull(activity.recyclerView().findViewHolderForAdapterPosition(selectedIndex))
            .itemView
            .findViewById<View>(com.yinxing.launcher.R.id.app_checkbox)
            .performClick()
        waitUntil { !preferences.isPackageSelected(unselectedPackage) }
        assertEquals(listOf("pkg.beta", "pkg.gamma", "pkg.alpha"), preferences.getAppOrder())
        controller.destroy()
    }

    private fun activityAdapter(activity: AppManageActivity): AppListAdapter {
        val field = AppManageActivity::class.java.getDeclaredField("adapter")
        field.isAccessible = true
        return field.get(activity) as AppListAdapter
    }

    private fun AppManageActivity.recyclerView(): RecyclerView = findViewById(com.yinxing.launcher.R.id.recycler_view)

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
        val resolveInfo = ResolveInfo().apply { this.activityInfo = activityInfo }
        shadowOf(context.packageManager).apply {
            addResolveInfoForIntent(launcherIntent, resolveInfo)
            addResolveInfoForIntent(Intent(launcherIntent).setPackage(packageName), resolveInfo)
        }
    }

    private fun waitUntil(timeoutMs: Long = 5_000L, predicate: () -> Boolean) {
        val deadline = System.currentTimeMillis() + timeoutMs
        while (System.currentTimeMillis() < deadline) {
            shadowOf(Looper.getMainLooper()).idle()
            if (predicate()) return
            Thread.sleep(25)
        }
        shadowOf(Looper.getMainLooper()).idle()
    }

    private fun resetLauncherPreferencesSingleton() {
        val field = LauncherPreferences::class.java.getDeclaredField("instance")
        field.isAccessible = true
        field.set(null, null)
    }

    private fun resetLauncherSettingsDataStoreSingleton() {
        val field = LauncherSettingsDataStore::class.java.getDeclaredField("instance")
        field.isAccessible = true
        field.set(null, null)
    }
}
