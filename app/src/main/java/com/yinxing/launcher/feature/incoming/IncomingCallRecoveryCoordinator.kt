package com.yinxing.launcher.feature.incoming

internal enum class IncomingCallResumeDecision {
    NO_PENDING,
    KEEP_RINGING,
    KEEP_UNKNOWN,
    FINISH_ANSWERED,
    FINISH_ENDED
}

internal class IncomingCallRecoveryCoordinator(
    private val gateway: IncomingCallSystemUiGateway
) {
    internal var awaitingSystemUiReturn: Boolean = false
        private set

    fun requestSystemCallUi(): SystemCallUiRequestResult {
        return gateway.requestSystemCallUi().also { result ->
            awaitingSystemUiReturn = result is SystemCallUiRequestResult.Requested
        }
    }

    fun onHostResumed(): IncomingCallResumeDecision {
        if (!awaitingSystemUiReturn) return IncomingCallResumeDecision.NO_PENDING
        awaitingSystemUiReturn = false
        return when (gateway.currentCallState()) {
            IncomingDeviceCallState.RINGING -> IncomingCallResumeDecision.KEEP_RINGING
            IncomingDeviceCallState.OFFHOOK -> IncomingCallResumeDecision.FINISH_ANSWERED
            IncomingDeviceCallState.IDLE -> IncomingCallResumeDecision.FINISH_ENDED
            IncomingDeviceCallState.UNKNOWN -> IncomingCallResumeDecision.KEEP_UNKNOWN
        }
    }

    fun restoreAwaitingSystemUiReturn() {
        awaitingSystemUiReturn = true
    }

    fun reset() {
        awaitingSystemUiReturn = false
    }
}
