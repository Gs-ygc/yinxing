package com.yinxing.launcher.feature.videocall

import android.content.Context
import com.yinxing.launcher.R

internal fun Context.videoCallOverlayTitle(rawContactName: String): String {
    val contactName = rawContactName.trim().ifBlank {
        getString(R.string.contact_name_placeholder)
    }
    return getString(R.string.video_call_overlay_contact_title, contactName)
}
