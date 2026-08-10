package com.yinxing.launcher.feature.home

import android.content.Intent
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class HomeAppLauncherTest {
    @Test
    fun resolvedDestinationLaunchesOnceAndSuppressesSameTouchBurst() {
        val fixture = Fixture()
        val item = appItem("com.example.camera", "相机")

        assertTrue(fixture.launcher.open(item))
        assertFalse(fixture.launcher.open(item))

        assertEquals(listOf("com.example.camera"), fixture.launchedPackages)
        assertTrue(fixture.unavailableItems.isEmpty())
    }

    @Test
    fun differentDestinationsCanLaunchInSameTouchBurst() {
        val fixture = Fixture()

        assertTrue(fixture.launcher.open(appItem("com.example.camera", "相机")))
        assertTrue(fixture.launcher.open(appItem("com.example.messages", "短信")))

        assertEquals(
            listOf("com.example.camera", "com.example.messages"),
            fixture.launchedPackages
        )
    }

    @Test
    fun unresolvedDestinationReportsUnavailableAndAllowsImmediateRetry() {
        var firstResolve = true
        val fixture = Fixture(resolveIntent = { packageName ->
            if (firstResolve) {
                firstResolve = false
                null
            } else {
                Intent(Intent.ACTION_MAIN).setPackage(packageName)
            }
        })
        val item = appItem("com.example.camera", "相机")

        assertFalse(fixture.launcher.open(item))
        assertTrue(fixture.launcher.open(item))

        assertEquals(listOf(item), fixture.unavailableItems)
        assertEquals(listOf("com.example.camera"), fixture.launchedPackages)
    }

    @Test
    fun launchFailureReportsUnavailableAndAllowsImmediateRetry() {
        var firstLaunch = true
        val successfulPackages = mutableListOf<String>()
        val fixture = Fixture(launchIntent = { intent ->
            if (firstLaunch) {
                firstLaunch = false
                throw IllegalStateException("blocked")
            }
            successfulPackages += intent.`package`.orEmpty()
        })
        val item = appItem("com.example.camera", "相机")

        assertFalse(fixture.launcher.open(item))
        assertTrue(fixture.launcher.open(item))

        assertEquals(listOf(item), fixture.unavailableItems)
        assertEquals(listOf("com.example.camera"), successfulPackages)
    }

    @Test
    fun blankDestinationReportsUnavailableWithoutResolvingOrLaunching() {
        var resolveCount = 0
        val fixture = Fixture(resolveIntent = { packageName ->
            resolveCount += 1
            Intent(Intent.ACTION_MAIN).setPackage(packageName)
        })
        val item = appItem("   ", "未知应用")

        assertFalse(fixture.launcher.open(item))

        assertEquals(0, resolveCount)
        assertTrue(fixture.launchedPackages.isEmpty())
        assertEquals(listOf(item), fixture.unavailableItems)
    }

    @Test
    fun resolverErrorPropagatesWithoutUnavailableFallback() {
        val fatalError = FatalLaunchError()
        val fixture = Fixture(resolveIntent = { throw fatalError })

        try {
            fixture.launcher.open(appItem("com.example.camera", "相机"))
            fail("Expected resolver Error to propagate")
        } catch (caught: FatalLaunchError) {
            assertSame(fatalError, caught)
        }

        assertTrue(fixture.unavailableItems.isEmpty())
    }

    @Test
    fun launcherErrorPropagatesWithoutUnavailableFallback() {
        val fatalError = FatalLaunchError()
        val fixture = Fixture(launchIntent = { throw fatalError })

        try {
            fixture.launcher.open(appItem("com.example.camera", "相机"))
            fail("Expected launcher Error to propagate")
        } catch (caught: FatalLaunchError) {
            assertSame(fatalError, caught)
        }

        assertTrue(fixture.unavailableItems.isEmpty())
    }

    private class Fixture(
        resolveIntent: (String) -> Intent? = { packageName ->
            Intent(Intent.ACTION_MAIN).setPackage(packageName)
        },
        launchIntent: ((Intent) -> Unit)? = null
    ) {
        val launchedPackages = mutableListOf<String>()
        val unavailableItems = mutableListOf<HomeAppItem>()

        val launcher = HomeAppLauncher(
            resolveLaunchIntent = resolveIntent,
            launchIntent = launchIntent ?: { intent ->
                launchedPackages += intent.`package`.orEmpty()
            },
            onUnavailable = { item: HomeAppItem -> unavailableItems += item },
            gate = HomeAppLaunchGate(nowMillis = { 100L })
        )
    }

    private fun appItem(packageName: String, appName: String) = HomeAppItem(
        packageName = packageName,
        appName = appName,
        type = HomeAppItem.Type.APP
    )

    private class FatalLaunchError : Error()
}
