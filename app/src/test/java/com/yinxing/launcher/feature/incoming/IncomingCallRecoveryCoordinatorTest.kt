package com.yinxing.launcher.feature.incoming

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class IncomingCallRecoveryCoordinatorTest {

    @Test
    fun ordinaryResumeWithoutHandoffDoesNotReadCallState() {
        val gateway = FakeGateway()
        val coordinator = IncomingCallRecoveryCoordinator(gateway)

        assertEquals(IncomingCallResumeDecision.NO_PENDING, coordinator.onHostResumed())
        assertEquals(0, gateway.stateReads)
    }

    @Test
    fun failedSystemUiRequestDoesNotArmResumeRead() {
        val failure = SecurityException("show denied")
        val gateway = FakeGateway(
            requestResult = SystemCallUiRequestResult.Failed(failure)
        )
        val coordinator = IncomingCallRecoveryCoordinator(gateway)

        assertEquals(
            SystemCallUiRequestResult.Failed(failure),
            coordinator.requestSystemCallUi()
        )
        assertFalse(coordinator.awaitingSystemUiReturn)
        assertEquals(IncomingCallResumeDecision.NO_PENDING, coordinator.onHostResumed())
        assertEquals(0, gateway.stateReads)
    }

    @Test
    fun successfulRequestReadsExactlyOnceOnNextResume() {
        val gateway = FakeGateway(callState = IncomingDeviceCallState.OFFHOOK)
        val coordinator = IncomingCallRecoveryCoordinator(gateway)

        assertEquals(SystemCallUiRequestResult.Requested, coordinator.requestSystemCallUi())
        assertTrue(coordinator.awaitingSystemUiReturn)
        assertEquals(0, gateway.stateReads)
        assertEquals(IncomingCallResumeDecision.FINISH_ANSWERED, coordinator.onHostResumed())
        assertFalse(coordinator.awaitingSystemUiReturn)
        assertEquals(1, gateway.stateReads)
        assertEquals(IncomingCallResumeDecision.NO_PENDING, coordinator.onHostResumed())
        assertEquals(1, gateway.stateReads)
    }

    @Test
    fun nextResumeMapsEachObservedCallState() {
        val expectations = listOf(
            IncomingDeviceCallState.RINGING to IncomingCallResumeDecision.KEEP_RINGING,
            IncomingDeviceCallState.UNKNOWN to IncomingCallResumeDecision.KEEP_UNKNOWN,
            IncomingDeviceCallState.OFFHOOK to IncomingCallResumeDecision.FINISH_ANSWERED,
            IncomingDeviceCallState.IDLE to IncomingCallResumeDecision.FINISH_ENDED
        )

        expectations.forEach { (callState, expected) ->
            val coordinator = IncomingCallRecoveryCoordinator(FakeGateway(callState = callState))
            coordinator.requestSystemCallUi()
            assertEquals(expected, coordinator.onHostResumed())
        }
    }

    @Test
    fun resetDropsPendingResumeRead() {
        val gateway = FakeGateway(callState = IncomingDeviceCallState.IDLE)
        val coordinator = IncomingCallRecoveryCoordinator(gateway)
        coordinator.requestSystemCallUi()

        coordinator.reset()

        assertFalse(coordinator.awaitingSystemUiReturn)
        assertEquals(IncomingCallResumeDecision.NO_PENDING, coordinator.onHostResumed())
        assertEquals(0, gateway.stateReads)
    }

    @Test
    fun restoredPendingHandoffReadsOnNextResume() {
        val gateway = FakeGateway(callState = IncomingDeviceCallState.RINGING)
        val coordinator = IncomingCallRecoveryCoordinator(gateway)

        coordinator.restoreAwaitingSystemUiReturn()

        assertTrue(coordinator.awaitingSystemUiReturn)
        assertEquals(IncomingCallResumeDecision.KEEP_RINGING, coordinator.onHostResumed())
        assertEquals(1, gateway.stateReads)
    }

    private class FakeGateway(
        private val requestResult: SystemCallUiRequestResult = SystemCallUiRequestResult.Requested,
        private val callState: IncomingDeviceCallState = IncomingDeviceCallState.RINGING
    ) : IncomingCallSystemUiGateway {
        var stateReads: Int = 0
            private set

        override fun requestSystemCallUi(): SystemCallUiRequestResult = requestResult

        override fun currentCallState(): IncomingDeviceCallState {
            stateReads += 1
            return callState
        }
    }
}
