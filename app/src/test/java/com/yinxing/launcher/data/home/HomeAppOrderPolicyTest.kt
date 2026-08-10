package com.yinxing.launcher.data.home

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Locale

class HomeAppOrderPolicyTest {
    @Test
    fun orderApps_keepsSavedOrderAndAppendsRemainingByName() {
        val apps = listOf(
            OrderedApp("pkg.weather", "Weather"),
            OrderedApp("pkg.calendar", "Calendar"),
            OrderedApp("pkg.browser", "Browser")
        )

        val orderedPackages = HomeAppOrderPolicy.orderApps(
            apps,
            listOf("pkg.calendar", "pkg.missing", "pkg.calendar")
        ).map { it.packageName }

        assertEquals(
            listOf("pkg.calendar", "pkg.browser", "pkg.weather"),
            orderedPackages
        )
    }

    @Test
    fun updateOrderForSelection_appendsNewSelectionOnce() {
        val updatedOrder = HomeAppOrderPolicy.updateOrderForSelection(
            listOf("pkg.alpha", "pkg.beta", "pkg.alpha"),
            "pkg.gamma",
            true
        )

        assertEquals(
            listOf("pkg.alpha", "pkg.beta", "pkg.gamma"),
            updatedOrder
        )
    }

    @Test
    fun updateOrderForSelection_removesDeselectedPackage() {
        val updatedOrder = HomeAppOrderPolicy.updateOrderForSelection(
            listOf("pkg.alpha", "pkg.beta", "pkg.gamma"),
            "pkg.beta",
            false
        )

        assertEquals(
            listOf("pkg.alpha", "pkg.gamma"),
            updatedOrder
        )
    }

    @Test
    fun retainSelectedPackages_filtersOutStalePackages() {
        val retainedOrder = HomeAppOrderPolicy.retainSelectedPackages(
            listOf("pkg.alpha", "pkg.beta", "pkg.gamma"),
            listOf("pkg.gamma", "pkg.alpha")
        )

        assertEquals(
            listOf("pkg.alpha", "pkg.gamma"),
            retainedOrder
        )
    }

    @Test
    fun orderApps_usesLocaleIndependentNameSort() {
        val originalLocale = Locale.getDefault()
        try {
            Locale.setDefault(Locale.forLanguageTag("tr"))
            val orderedPackages = HomeAppOrderPolicy.orderApps(
                listOf(
                    OrderedApp("pkg.zulu", "Zulu"),
                    OrderedApp("pkg.ibis", "Ibis")
                ),
                emptyList()
            ).map { it.packageName }

            assertEquals(listOf("pkg.ibis", "pkg.zulu"), orderedPackages)
        } finally {
            Locale.setDefault(originalLocale)
        }
    }

    @Test
    fun orderApps_emptyAppsReturnsEmpty() {
        val result = HomeAppOrderPolicy.orderApps(emptyList(), listOf("pkg.a"))
        assertTrue(result.isEmpty())
    }

    @Test
    fun orderManagementApps_keepsSelectedAppsInSavedOrderThenByName() {
        val result = HomeAppOrderPolicy.orderManagementApps(
            apps = listOf(
                OrderedApp("pkg.alpha", "Alpha"),
                OrderedApp("pkg.beta", "Beta"),
                OrderedApp("pkg.gamma", "Gamma")
            ),
            selectedPackages = setOf("pkg.alpha", "pkg.gamma"),
            savedOrder = listOf("pkg.gamma", "pkg.missing", "pkg.gamma")
        )

        assertEquals(
            listOf("pkg.gamma", "pkg.alpha", "pkg.beta"),
            result.map { it.packageName }
        )
    }

    @Test
    fun moveSelectedPackage_swapsWithPreviousPackage() {
        assertEquals(
            listOf("pkg.alpha", "pkg.gamma", "pkg.beta"),
            HomeAppOrderPolicy.moveSelectedPackage(
                currentOrder = listOf("pkg.alpha", "pkg.beta", "pkg.gamma"),
                packageName = "pkg.gamma",
                offset = -1
            )
        )
    }

    @Test
    fun moveSelectedPackage_swapsWithNextPackage() {
        assertEquals(
            listOf("pkg.beta", "pkg.alpha", "pkg.gamma"),
            HomeAppOrderPolicy.moveSelectedPackage(
                currentOrder = listOf("pkg.alpha", "pkg.beta", "pkg.gamma"),
                packageName = "pkg.alpha",
                offset = 1
            )
        )
    }

    @Test
    fun moveSelectedPackage_returnsNullForNoOpRequests() {
        val currentOrder = listOf("pkg.alpha", "pkg.beta", "pkg.gamma")

        assertEquals(
            null,
            HomeAppOrderPolicy.moveSelectedPackage(currentOrder, "pkg.alpha", -1)
        )
        assertEquals(
            null,
            HomeAppOrderPolicy.moveSelectedPackage(currentOrder, "pkg.gamma", 1)
        )
        assertEquals(
            null,
            HomeAppOrderPolicy.moveSelectedPackage(currentOrder, "pkg.beta", 0)
        )
        assertEquals(
            null,
            HomeAppOrderPolicy.moveSelectedPackage(currentOrder, "pkg.beta", 2)
        )
        assertEquals(
            null,
            HomeAppOrderPolicy.moveSelectedPackage(currentOrder, " ", 1)
        )
        assertEquals(
            null,
            HomeAppOrderPolicy.moveSelectedPackage(currentOrder, "pkg.missing", 1)
        )
    }

    @Test
    fun retainSelectedPackages_preservesSavedOrder() {
        val result = HomeAppOrderPolicy.retainSelectedPackages(
            listOf("pkg.c", "pkg.a", "pkg.b"),
            listOf("pkg.a", "pkg.c")
        )
        assertEquals(listOf("pkg.c", "pkg.a"), result)
    }

    @Test
    fun retainSelectedPackages_emptySelectionReturnsEmpty() {
        val result = HomeAppOrderPolicy.retainSelectedPackages(
            listOf("pkg.a", "pkg.b"),
            emptyList()
        )
        assertTrue(result.isEmpty())
    }

    @Test
    fun normalizeSavedOrder_trimsFiltersEmptyAndDeduplicates() {
        val result = HomeAppOrderPolicy.normalizeSavedOrder(listOf("  pkg.a  ", "", "  ", "pkg.a", "pkg.b"))
        assertEquals(listOf("pkg.a", "pkg.b"), result)
    }

    @Test
    fun normalizeSavedOrder_emptyInputReturnsEmpty() {
        val result = HomeAppOrderPolicy.normalizeSavedOrder(emptyList())
        assertTrue(result.isEmpty())
    }
}
