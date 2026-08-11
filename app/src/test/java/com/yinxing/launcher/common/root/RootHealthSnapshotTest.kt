package com.yinxing.launcher.common.root

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertNotNull
import org.junit.Test

class RootHealthSnapshotTest {

    @Test
    fun parsesHealthySnapshotAndDerivesHealthyState() {
        val snapshot = RootHealthSnapshot.parse(validSnapshot())

        assertNotNull(snapshot)
        assertEquals(RootHealthState.HEALTHY, snapshot?.state)
        assertEquals("1.10.0-root-preview.3", snapshot?.version)
        assertEquals("running", snapshot?.guard)
        assertEquals("enabled", snapshot?.accessibility)
        assertEquals("owned", snapshot?.home)
        assertEquals("verified", snapshot?.homeForeground)
        assertEquals("owned", snapshot?.doze)
    }

    @Test
    fun unavailableSnapshotRetainsExactFailureEvidence() {
        val evidence = RootFailureEvidence.create(
            command = RootCommand.STATUS,
            stage = RootFailureStage.SU_START,
            detail = "IOException: error=2"
        )

        val snapshot = RootHealthSnapshot.unavailable(
            reason = RootFailureReason.SU_NOT_FOUND,
            evidence = evidence
        )

        assertEquals(evidence, snapshot.failureEvidence)
    }

    @Test
    fun schemaThreeRequiresVerifiedForegroundForHealthy() {
        val snapshot = RootHealthSnapshot.parse(
            validSnapshot().replace("home_foreground=verified", "home_foreground=unverified")
        )

        assertNotNull(snapshot)
        assertEquals(RootHealthState.DEGRADED, snapshot?.state)
    }

    @Test
    fun schemaThreeOtherNoneAndUnknownHomeAreDegraded() {
        listOf("other", "none", "unknown").forEach { home ->
            val snapshot = RootHealthSnapshot.parse(
                validSnapshot().replace("home=owned", "home=$home")
            )

            assertNotNull(snapshot)
            assertEquals(home, snapshot?.home)
            assertEquals(RootHealthState.DEGRADED, snapshot?.state)
        }
    }

    @Test
    fun schemaThreeRejectsMissingDuplicateAndUnsupportedHomeForeground() {
        val missingHome = validSnapshot().trimEnd()
            .lineSequence()
            .filterNot { it.startsWith("home=") }
            .joinToString("\n", postfix = "\n")

        assertNull(RootHealthSnapshot.parse(missingHome))
        assertNull(RootHealthSnapshot.parse(validSnapshot() + "home=owned\n"))
        assertNull(RootHealthSnapshot.parse(validSnapshot().replace("home=owned", "home=default")))
        assertNull(
            RootHealthSnapshot.parse(
                validSnapshot().replace("home_foreground=verified", "home_foreground=recent")
            )
        )
    }

    @Test
    fun schemaOneRemainsParseableButDegradedWithUnknownHome() {
        val legacySnapshot = validSnapshot()
            .replace("schema=3", "schema=1")
            .trimEnd()
            .lineSequence()
            .filterNot { it.startsWith("home=") || it.startsWith("home_foreground=") }
            .joinToString("\n", postfix = "\n")

        val snapshot = RootHealthSnapshot.parse(legacySnapshot)

        assertNotNull(snapshot)
        assertEquals("unknown", snapshot?.home)
        assertEquals("unknown", snapshot?.homeForeground)
        assertEquals(RootHealthState.DEGRADED, snapshot?.state)
    }

    @Test
    fun schemaTwoRemainsParseableButIsDegradedWithoutForegroundEvidence() {
        val schemaTwo = validSnapshot()
            .replace("schema=3", "schema=2")
            .trimEnd()
            .lineSequence()
            .filterNot { it.startsWith("home_foreground=") }
            .joinToString("\n", postfix = "\n")

        val snapshot = RootHealthSnapshot.parse(schemaTwo)

        assertNotNull(snapshot)
        assertEquals("unknown", snapshot?.homeForeground)
        assertEquals(RootHealthState.DEGRADED, snapshot?.state)
    }

    @Test
    fun rejectsSchemaOneWithModernKeysSchemaTwoWithForegroundAndSchemaThreeWithoutForeground() {
        val schemaOneWithModernKeys = validSnapshot().replace("schema=3", "schema=1")
        val schemaTwoWithForeground = validSnapshot().replace("schema=3", "schema=2")
        val schemaThreeWithoutForeground = validSnapshot().trimEnd()
            .lineSequence()
            .filterNot { it.startsWith("home_foreground=") }
            .joinToString("\n", postfix = "\n")

        assertNull(RootHealthSnapshot.parse(schemaOneWithModernKeys))
        assertNull(RootHealthSnapshot.parse(schemaTwoWithForeground))
        assertNull(RootHealthSnapshot.parse(schemaThreeWithoutForeground))
    }

    @Test
    fun parsesDegradedSnapshotWithoutTreatingItAsHealthy() {
        val snapshot = RootHealthSnapshot.parse(
            validSnapshot().replace("guard=running", "guard=stale")
                .replace("last_repair=ok", "last_repair=failed")
        )

        assertNotNull(snapshot)
        assertEquals(RootHealthState.DEGRADED, snapshot?.state)
    }

    @Test
    fun parsesStaleAccessibilitySnapshotAsDegraded() {
        val snapshot = RootHealthSnapshot.parse(
            validSnapshot().replace("accessibility=enabled", "accessibility=stale")
        )

        assertNotNull(snapshot)
        assertEquals(RootHealthState.DEGRADED, snapshot?.state)
        assertEquals("stale", snapshot?.accessibility)
    }

    @Test
    fun mapsMissingModuleToModuleMissingState() {
        val snapshot = RootHealthSnapshot.parse(
            validSnapshot().replace("module=active", "module=missing")
        )

        assertNotNull(snapshot)
        assertEquals(RootHealthState.MODULE_MISSING, snapshot?.state)
    }

    @Test
    fun rejectsDuplicateKeys() {
        assertNull(RootHealthSnapshot.parse(validSnapshot() + "guard=running\n"))
    }

    @Test
    fun rejectsUnknownValues() {
        assertNull(RootHealthSnapshot.parse(validSnapshot().replace("guard=running", "guard=alive")))
    }

    @Test
    fun rejectsMissingRequiredKeys() {
        val missingDoze = validSnapshot().trimEnd()
            .lineSequence()
            .filterNot { it.startsWith("doze=") }
            .joinToString("\n", postfix = "\n")

        assertNull(RootHealthSnapshot.parse(missingDoze))
    }

    @Test
    fun rejectsOutputOverMaximumLength() {
        assertNull(RootHealthSnapshot.parse(validSnapshot() + "x".repeat(16_384)))
    }

    @Test
    fun contradictoryFieldsRemainDegraded() {
        val snapshot = RootHealthSnapshot.parse(
            validSnapshot()
                .replace("module=active", "module=missing")
                .replace("guard=running", "guard=running")
                .replace("accessibility=enabled", "accessibility=enabled")
        )

        assertNotNull(snapshot)
        assertEquals(RootHealthState.MODULE_MISSING, snapshot?.state)
    }

    private fun validSnapshot(): String = """
        schema=3
        version=1.10.0-root-preview.3
        module=active
        guard=running
        accessibility=enabled
        home=owned
        home_foreground=verified
        doze=owned
        cleanup=ready
        last_repair=ok
    """.trimIndent() + "\n"
}
