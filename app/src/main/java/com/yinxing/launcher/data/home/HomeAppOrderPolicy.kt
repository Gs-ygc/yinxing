package com.yinxing.launcher.data.home

import java.util.Locale

data class OrderedApp(
    val packageName: String,
    val appName: String
)

object HomeAppOrderPolicy {
    fun orderApps(apps: Collection<OrderedApp>, savedOrder: Collection<String>): List<OrderedApp> {
        val appsByPackage = apps.associateBy { it.packageName }.toMutableMap()
        val orderedApps = mutableListOf<OrderedApp>()

        normalizeSavedOrder(savedOrder).forEach { packageName ->
            appsByPackage.remove(packageName)?.let(orderedApps::add)
        }

        orderedApps += appsByPackage.values.sortedBy { it.appName.lowercase(Locale.ROOT) }
        return orderedApps
    }

    fun orderManagementApps(
        apps: Collection<OrderedApp>,
        selectedPackages: Collection<String>,
        savedOrder: Collection<String>
    ): List<OrderedApp> {
        val selected = selectedPackages.toSet()
        val selectedApps = orderApps(apps.filter { it.packageName in selected }, savedOrder)
        val unselectedApps = orderApps(apps.filterNot { it.packageName in selected }, emptyList())
        return selectedApps + unselectedApps
    }

    fun moveSelectedPackage(
        currentOrder: Collection<String>,
        packageName: String,
        offset: Int
    ): List<String>? {
        val normalizedOrder = normalizeSavedOrder(currentOrder)
        if (packageName.isBlank() || offset !in setOf(-1, 1)) return null
        val from = normalizedOrder.indexOf(packageName)
        val to = from + offset
        if (from < 0 || to !in normalizedOrder.indices) return null
        return normalizedOrder.toMutableList().apply { java.util.Collections.swap(this, from, to) }
    }

    fun updateOrderForSelection(
        savedOrder: Collection<String>,
        packageName: String,
        isSelected: Boolean
    ): List<String> {
        val updatedOrder = normalizeSavedOrder(savedOrder)
            .filter { it != packageName }
            .toMutableList()

        if (isSelected) {
            updatedOrder.add(packageName)
        }

        return updatedOrder
    }

    fun retainSelectedPackages(
        savedOrder: Collection<String>,
        selectedPackages: Collection<String>
    ): List<String> {
        val selectedPackageSet = selectedPackages.toSet()
        return normalizeSavedOrder(savedOrder).filter { it in selectedPackageSet }
    }

    fun normalizeSavedOrder(savedOrder: Collection<String>): List<String> {
        return savedOrder
            .asSequence()
            .map { it.trim() }
            .filter { it.isNotEmpty() }
            .distinct()
            .toList()
    }
}
