package com.yinxing.launcher.common.root

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class RootFailureEvidenceTest {

    @Test
    fun normalizesControlsAndBoundsDiagnosticDetail() {
        val prefix = "prefix-"
        val suffix = "-suffix"
        val detail = "  $prefix\n\t${'\u0000'}${"x".repeat(2_000)}$suffix  "

        val evidence = RootFailureEvidence.create(
            command = RootCommand.STATUS,
            stage = RootFailureStage.COMMAND_RUN,
            exitCode = 126,
            detail = detail
        )

        assertTrue(evidence.detail.startsWith(prefix))
        assertTrue(evidence.detail.contains("\n"))
        assertTrue(evidence.detail.contains("\t"))
        assertFalse(evidence.detail.contains('\u0000'))
        assertTrue(evidence.detail.contains('?'))
        assertTrue(evidence.detail.contains("[omitted "))
        assertTrue(evidence.detail.contains(suffix))
        assertTrue(evidence.detail.length <= 1_024)
    }
}
