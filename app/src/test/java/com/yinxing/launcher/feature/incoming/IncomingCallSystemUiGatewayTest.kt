package com.yinxing.launcher.feature.incoming

import android.telephony.TelephonyManager
import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Assert.assertThrows
import org.junit.Test

class IncomingCallSystemUiGatewayTest {

    @Test
    fun requestSystemCallUiInvokesPlatformRequestOnce() {
        var requests = 0
        val gateway = gateway(request = { requests += 1 })

        assertEquals(SystemCallUiRequestResult.Requested, gateway.requestSystemCallUi())
        assertEquals(1, requests)
    }

    @Test
    fun ordinaryRequestFailureIsReturnedWithOriginalError() {
        val failure = IllegalStateException("telecom unavailable")
        val gateway = gateway(request = { throw failure })

        val result = gateway.requestSystemCallUi()

        assertSame(failure, (result as SystemCallUiRequestResult.Failed).error)
    }

    @Test
    fun fatalRequestErrorPropagates() {
        val gateway = gateway(request = { throw AssertionError("fatal request") })

        val error = assertThrows(AssertionError::class.java) {
            gateway.requestSystemCallUi()
        }

        assertEquals("fatal request", error.message)
    }

    @Test
    fun currentCallStateMapsIdleRingingAndOffhook() {
        assertEquals(
            IncomingDeviceCallState.IDLE,
            gateway(state = { TelephonyManager.CALL_STATE_IDLE }).currentCallState()
        )
        assertEquals(
            IncomingDeviceCallState.RINGING,
            gateway(state = { TelephonyManager.CALL_STATE_RINGING }).currentCallState()
        )
        assertEquals(
            IncomingDeviceCallState.OFFHOOK,
            gateway(state = { TelephonyManager.CALL_STATE_OFFHOOK }).currentCallState()
        )
    }

    @Test
    fun unknownOrOrdinaryStateFailureFailsClosed() {
        assertEquals(
            IncomingDeviceCallState.UNKNOWN,
            gateway(state = { 99 }).currentCallState()
        )
        assertEquals(
            IncomingDeviceCallState.UNKNOWN,
            gateway(state = { throw SecurityException("phone state denied") }).currentCallState()
        )
    }

    @Test
    fun fatalStateReadErrorPropagates() {
        val gateway = gateway(state = { throw AssertionError("fatal state") })

        val error = assertThrows(AssertionError::class.java) {
            gateway.currentCallState()
        }

        assertEquals("fatal state", error.message)
    }

    private fun gateway(
        request: () -> Unit = {},
        state: () -> Int = { TelephonyManager.CALL_STATE_IDLE }
    ): AndroidIncomingCallSystemUiGateway {
        return AndroidIncomingCallSystemUiGateway(
            requestSystemUi = request,
            readCallState = state
        )
    }
}
