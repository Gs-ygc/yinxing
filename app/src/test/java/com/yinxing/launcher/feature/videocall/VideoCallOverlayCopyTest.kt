package com.yinxing.launcher.feature.videocall

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class VideoCallOverlayCopyTest {
    private val context: Context = ApplicationProvider.getApplicationContext()

    @Test
    fun contactTitleTrimsAndNamesTheTarget() {
        assertEquals("正在联系 女儿", context.videoCallOverlayTitle("  女儿  "))
    }

    @Test
    fun blankContactTitleUsesExistingContactFallback() {
        assertEquals("正在联系 联系人", context.videoCallOverlayTitle("   "))
    }
}
