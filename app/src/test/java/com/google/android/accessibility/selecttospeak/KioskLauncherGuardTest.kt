package com.google.android.accessibility.selecttospeak

import android.content.Context
import android.content.Intent
import android.content.pm.ActivityInfo
import android.content.pm.ApplicationInfo
import android.content.pm.ResolveInfo
import android.view.accessibility.AccessibilityEvent
import androidx.test.core.app.ApplicationProvider
import com.yinxing.launcher.common.root.RootHomeLauncher
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

    @Test
    fun newerUserAppWindowSuppressesStaleLauncherRecovery() = runTest {
        val controller = Robolectric.buildService(SelectToSpeakService::class.java).create()
        val service = controller.get()
        val rootLauncher = RecordingRootHomeLauncher()
        LauncherPreferences.getInstance(service).setKioskModeEnabled(true)
        val guard = newGuard(service, rootLauncher, this)
        guard.init()

        assertTrue(guard.onWindowStateChanged(SYSTEM_HOME_PACKAGE, "Launcher"))
        assertFalse(guard.onWindowStateChanged("com.example.user", "UserActivity"))
        advanceTimeBy(450L)
        runCurrent()

        assertNull(shadowOf(service).nextStartedActivity)
        assertEquals(0, rootLauncher.calls)
        guard.shutdown()
        controller.destroy()
    }

    @Test
    fun rootHomeFallbackRunsOnceAfterNormalRecoveryStillShowsLauncher() = runTest {
        val controller = Robolectric.buildService(SelectToSpeakService::class.java).create()
        val service = controller.get()
        val rootLauncher = RecordingRootHomeLauncher()
        LauncherPreferences.getInstance(service).setKioskModeEnabled(true)
        val guard = newGuard(service, rootLauncher, this)
        guard.init()

        assertTrue(guard.onWindowStateChanged(SYSTEM_HOME_PACKAGE, "Launcher"))
        advanceTimeBy(450L + 350L + 600L)
        runCurrent()

        assertEquals(1, rootLauncher.calls)
        advanceTimeBy(2_000L)
        runCurrent()
        assertEquals(1, rootLauncher.calls)

        guard.shutdown()
        controller.destroy()
    }

    @Test
    fun shutdownCancelsPendingRootHomeFallback() = runTest {
        val controller = Robolectric.buildService(SelectToSpeakService::class.java).create()
        val service = controller.get()
        val rootLauncher = RecordingRootHomeLauncher()
        LauncherPreferences.getInstance(service).setKioskModeEnabled(true)
        val guard = newGuard(service, rootLauncher, this)
        guard.init()

        assertTrue(guard.onWindowStateChanged(SYSTEM_HOME_PACKAGE, "Launcher"))
        advanceTimeBy(450L + 350L)
        runCurrent()
        guard.shutdown()
        advanceTimeBy(600L)
        runCurrent()

        assertEquals(0, rootLauncher.calls)
        controller.destroy()
    }

    @Test
    fun serviceIsNotPublishedBeforeAccessibilityConnectionIsReady() {
        val controller = Robolectric.buildService(SelectToSpeakService::class.java).create()

        assertNull(SelectToSpeakService.getInstance())

        controller.destroy()
    }

    @Test
    fun accessibilityEventsBeforeConnectionAreIgnored() {
        val controller = Robolectric.buildService(SelectToSpeakService::class.java).create()
        val service = controller.get()
        val event = AccessibilityEvent.obtain(AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED).apply {
            packageName = SYSTEM_HOME_PACKAGE
            className = "Launcher"
        }

        service.onAccessibilityEvent(event)
        event.recycle()
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

    private fun newGuard(
        service: SelectToSpeakService,
        rootHomeLauncher: RootHomeLauncher,
        scope: kotlinx.coroutines.CoroutineScope
    ): KioskLauncherGuard = KioskLauncherGuard(
        service = service,
        scope = scope,
        launcherActivityClass = MainActivity::class.java,
        activeSession = { false },
        rootHomeLauncher = rootHomeLauncher
    )

    private class RecordingRootHomeLauncher : RootHomeLauncher {
        var calls = 0

        override suspend fun launchHome(): Boolean {
            calls += 1
            return true
        }
    }

    private companion object {
        const val SYSTEM_HOME_PACKAGE = "com.android.launcher3"
    }
}
