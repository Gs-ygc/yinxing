package com.yinxing.launcher.feature.incoming

import android.content.Context
import android.telecom.TelecomManager
import android.telephony.TelephonyManager

internal sealed interface SystemCallUiRequestResult {
    data object Requested : SystemCallUiRequestResult
    data class Failed(val error: Exception) : SystemCallUiRequestResult
}

internal enum class IncomingDeviceCallState {
    IDLE,
    RINGING,
    OFFHOOK,
    UNKNOWN
}

internal interface IncomingCallSystemUiGateway {
    fun requestSystemCallUi(): SystemCallUiRequestResult
    fun currentCallState(): IncomingDeviceCallState
}

internal class AndroidIncomingCallSystemUiGateway(
    private val requestSystemUi: () -> Unit,
    private val readCallState: () -> Int
) : IncomingCallSystemUiGateway {

    constructor(context: Context) : this(
        requestSystemUi = {
            requireNotNull(context.getSystemService(TelecomManager::class.java))
                .showInCallScreen(false)
        },
        readCallState = {
            @Suppress("DEPRECATION")
            val callState = requireNotNull(
                context.getSystemService(TelephonyManager::class.java)
            ).callState
            callState
        }
    )

    override fun requestSystemCallUi(): SystemCallUiRequestResult {
        return try {
            requestSystemUi()
            SystemCallUiRequestResult.Requested
        } catch (error: Exception) {
            SystemCallUiRequestResult.Failed(error)
        }
    }

    override fun currentCallState(): IncomingDeviceCallState {
        return try {
            when (readCallState()) {
                TelephonyManager.CALL_STATE_IDLE -> IncomingDeviceCallState.IDLE
                TelephonyManager.CALL_STATE_RINGING -> IncomingDeviceCallState.RINGING
                TelephonyManager.CALL_STATE_OFFHOOK -> IncomingDeviceCallState.OFFHOOK
                else -> IncomingDeviceCallState.UNKNOWN
            }
        } catch (_: Exception) {
            IncomingDeviceCallState.UNKNOWN
        }
    }
}
