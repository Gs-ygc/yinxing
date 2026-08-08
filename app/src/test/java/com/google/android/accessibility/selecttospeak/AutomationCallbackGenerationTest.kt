package com.google.android.accessibility.selecttospeak

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AutomationCallbackGenerationTest {

    @Test
    fun issuingANewGenerationInvalidatesThePreviousCallback() {
        val generation = AutomationCallbackGeneration()

        val first = generation.issue()
        val second = generation.issue()

        assertFalse(generation.isCurrent(first))
        assertTrue(generation.isCurrent(second))
    }

    @Test
    fun invalidatingTheGenerationStopsAQueuedCallback() {
        val generation = AutomationCallbackGeneration()
        val token = generation.issue()

        generation.invalidate()

        assertFalse(generation.isCurrent(token))
    }
}
