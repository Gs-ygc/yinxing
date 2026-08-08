package com.yinxing.launcher.common.root

internal enum class RootHealthState {
    UNCHECKED,
    ROOT_UNAVAILABLE,
    MODULE_MISSING,
    DEGRADED,
    HEALTHY
}

internal data class RootHealthSnapshot(
    val state: RootHealthState,
    val version: String? = null,
    val module: String = "unknown",
    val guard: String = "unknown",
    val accessibility: String = "unknown",
    val doze: String = "unknown",
    val cleanup: String = "unknown",
    val lastRepair: String = "unknown"
) {
    companion object {
        private const val MAX_OUTPUT_CHARS = 16 * 1024
        private val requiredKeys = setOf(
            "schema",
            "version",
            "module",
            "guard",
            "accessibility",
            "doze",
            "cleanup",
            "last_repair"
        )
        private val versionPattern = Regex("[A-Za-z0-9._-]{1,64}")
        private val allowedValues = mapOf(
            "schema" to setOf("1"),
            "module" to setOf("active", "disabled", "removing", "missing"),
            "guard" to setOf("running", "stale", "missing", "unknown"),
            "accessibility" to setOf("enabled", "disabled", "missing", "unknown"),
            "doze" to setOf("owned", "present", "absent", "unknown"),
            "cleanup" to setOf("ready", "missing", "invalid"),
            "last_repair" to setOf("ok", "failed", "unknown")
        )

        fun unchecked(): RootHealthSnapshot = RootHealthSnapshot(state = RootHealthState.UNCHECKED)

        fun unavailable(): RootHealthSnapshot = RootHealthSnapshot(state = RootHealthState.ROOT_UNAVAILABLE)

        fun parse(output: String): RootHealthSnapshot? {
            if (output.length > MAX_OUTPUT_CHARS) {
                return null
            }

            val normalizedOutput = output.removeSuffix("\n").removeSuffix("\r")
            if (normalizedOutput.isEmpty()) {
                return null
            }

            val values = linkedMapOf<String, String>()
            for (rawLine in normalizedOutput.split('\n')) {
                val line = rawLine.removeSuffix("\r")
                val separatorIndex = line.indexOf('=')
                if (separatorIndex <= 0 || separatorIndex != line.lastIndexOf('=')) {
                    return null
                }
                val key = line.substring(0, separatorIndex)
                val value = line.substring(separatorIndex + 1)
                if (key !in requiredKeys || values.put(key, value) != null) {
                    return null
                }
            }

            if (values.keys != requiredKeys || !versionPattern.matches(values.getValue("version"))) {
                return null
            }
            if (allowedValues.any { (key, allowed) -> values[key] !in allowed }) {
                return null
            }

            val module = values.getValue("module")
            val guard = values.getValue("guard")
            val accessibility = values.getValue("accessibility")
            val doze = values.getValue("doze")
            val cleanup = values.getValue("cleanup")
            val lastRepair = values.getValue("last_repair")
            val state = when {
                module == "missing" -> RootHealthState.MODULE_MISSING
                module == "active" &&
                    guard == "running" &&
                    accessibility == "enabled" &&
                    doze in setOf("owned", "present") &&
                    cleanup == "ready" &&
                    lastRepair == "ok" -> RootHealthState.HEALTHY
                else -> RootHealthState.DEGRADED
            }

            return RootHealthSnapshot(
                state = state,
                version = values.getValue("version"),
                module = module,
                guard = guard,
                accessibility = accessibility,
                doze = doze,
                cleanup = cleanup,
                lastRepair = lastRepair
            )
        }
    }
}
