package com.google.android.accessibility.selecttospeak

import android.content.Context
import android.content.Intent
import android.content.pm.ActivityInfo
import android.content.pm.ApplicationInfo
import android.content.pm.ResolveInfo
import androidx.test.core.app.ApplicationProvider
import com.yinxing.launcher.data.home.LauncherPreferences
import com.yinxing.launcher.data.settings.LauncherSettingsDataStore
import com.yinxing.launcher.feature.home.MainActivity
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
@OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)
class KioskLauncherGuardTest {
    private lateinit var context: Context

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        resetLauncherPreferencesSingleton()
        LauncherSettingsDataStore.getInstance(context).clear()
        registerHomeActivity(SYSTEM_HOME_PACKAGE)
    }

    @Test
    fun transientSystemWindowDoesNotCancelPendingLauncherRecovery() = runTest {
        val controller = Robolectric.buildService(SelectToSpeakService::class.java).create()
        val service = controller.get()
        LauncherPreferences.getInstance(service).setKioskModeEnabled(true)
        val guard = KioskLauncherGuard(
            service = service,
            scope = this,
            launcherActivityClass = MainActivity::class.java,
            activeSession = { false }
        )
        guard.init()

        assertTrue(guard.onWindowStateChanged(SYSTEM_HOME_PACKAGE, "Launcher"))
        assertFalse(guard.onWindowStateChanged("com.android.systemui", "StatusBar"))
        advanceTimeBy(450L)
        runCurrent()

        val started = shadowOf(service).nextStartedActivity
        assertEquals(MainActivity::class.java.name, started.component?.className)

        guard.shutdown()
        controller.destroy()
    }

    @Test
    fun shutdownCancelsPendingLauncherRecovery() = runTest {
        val controller = Robolectric.buildService(SelectToSpeakService::class.java).create()
        val service = controller.get()
        LauncherPreferences.getInstance(service).setKioskModeEnabled(true)
        val guard = KioskLauncherGuard(
            service = service,
            scope = this,
            launcherActivityClass = MainActivity::class.java,
            activeSession = { false }
        )
        guard.init()

        assertTrue(guard.onWindowStateChanged(SYSTEM_HOME_PACKAGE, "Launcher"))
        guard.shutdown()
        advanceTimeBy(450L)
        runCurrent()

        assertNull(shadowOf(service).nextStartedActivity)

        controller.destroy()
    }

    @Suppress("DEPRECATION")
    private fun registerHomeActivity(packageName: String) {
        val intent = Intent(Intent.ACTION_MAIN).apply { addCategory(Intent.CATEGORY_HOME) }
        val applicationInfo = ApplicationInfo().apply { this.packageName = packageName }
        val activityInfo = ActivityInfo().apply {
            this.packageName = packageName
            name = "$packageName.HomeActivity"
            this.applicationInfo = applicationInfo
        }
        val resolveInfo = ResolveInfo().apply { this.activityInfo = activityInfo }
        shadowOf(context.packageManager).addResolveInfoForIntent(intent, resolveInfo)
    }

    private fun resetLauncherPreferencesSingleton() {
        val field = LauncherPreferences::class.java.getDeclaredField("instance")
        field.isAccessible = true
        field.set(null, null)
    }

    private companion object {
        const val SYSTEM_HOME_PACKAGE = "com.android.launcher3"
    }
}
