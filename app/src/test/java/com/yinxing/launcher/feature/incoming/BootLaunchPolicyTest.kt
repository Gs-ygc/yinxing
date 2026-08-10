package com.yinxing.launcher.feature.incoming

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class BootLaunchPolicyTest {
    @Test
    fun skipsHomeWhenNoBootOwnershipSignalExists() {
        assertFalse(
            BootLaunchPolicy.shouldLaunchHome(
                autoStartConfirmed = false,
                kioskModeEnabled = false,
                defaultLauncher = false
            )
        )
    }

    @Test
    fun confirmedColorOsAutoStartIsEnoughToRestoreHome() {
        assertTrue(
            BootLaunchPolicy.shouldLaunchHome(
                autoStartConfirmed = true,
                kioskModeEnabled = false,
                defaultLauncher = false
            )
        )
    }

    @Test
    fun defaultLauncherOrKioskModeStillRestoresHome() {
        assertTrue(
            BootLaunchPolicy.shouldLaunchHome(
                autoStartConfirmed = false,
                kioskModeEnabled = false,
                defaultLauncher = true
            )
        )
        assertTrue(
            BootLaunchPolicy.shouldLaunchHome(
                autoStartConfirmed = false,
                kioskModeEnabled = true,
                defaultLauncher = false
            )
        )
    }
}
