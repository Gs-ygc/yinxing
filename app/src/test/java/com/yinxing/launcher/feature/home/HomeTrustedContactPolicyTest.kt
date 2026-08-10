package com.yinxing.launcher.feature.home

import com.yinxing.launcher.data.contact.Contact
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HomeTrustedContactPolicyTest {
    @Test
    fun selectFiltersMissingNumbersSortsAndCapsAtTwo() {
        val result = HomeTrustedContactPolicy.select(
            listOf(
                Contact("old", "旧", phoneNumber = "100", isPinned = true),
                Contact("missing", "无号"),
                Contact("recent", "最近", phoneNumber = "200", lastCallTime = 20),
                Contact("count", "次数", phoneNumber = "300", callCount = 5)
            )
        )

        assertEquals(listOf("old", "count"), result.map { it.id })
    }

    @Test
    fun selectUsesProvidedMaximum() {
        val result = HomeTrustedContactPolicy.select(
            listOf(
                Contact("pinned", "置顶", phoneNumber = "100", isPinned = true),
                Contact("recent", "最近", phoneNumber = "200", lastCallTime = 20)
            ),
            maxContacts = 1
        )

        assertEquals(listOf("pinned"), result.map { it.id })
    }

    @Test
    fun selectReturnsEmptyForNegativeMaximum() {
        val result = HomeTrustedContactPolicy.select(
            listOf(Contact("callable", "可拨打", phoneNumber = "100")),
            maxContacts = -1
        )

        assertTrue(result.isEmpty())
    }
}
