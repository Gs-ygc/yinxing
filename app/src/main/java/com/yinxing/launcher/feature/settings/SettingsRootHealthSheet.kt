package com.yinxing.launcher.feature.settings

import android.view.View
import android.widget.TextView
import android.widget.Toast
import androidx.lifecycle.lifecycleScope
import com.yinxing.launcher.R
import com.yinxing.launcher.common.root.RootFailureReason
import com.yinxing.launcher.common.root.RootHealthSnapshot
import com.yinxing.launcher.common.root.RootHealthState
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch

/**
 * Root 专机入口只读取银杏固定模块的健康快照；普通进入设置页不会触发 su。
 * 修复按钮执行一次固定 action.sh，然后重新读取快照，便于家属确认结果。
 */
internal fun SettingsActivity.showRootHealthSheet() {
    val sessionId = beginRootHealthSession()
    val sheet = createListSheet(
        title = getString(R.string.settings_section_root_title),
        message = getString(R.string.settings_sheet_root_message)
    )
    var busy = false
    lateinit var statusEntry: View
    lateinit var recoveryEntry: View

    statusEntry = addSheetEntry(
        context = sheet,
        title = getString(R.string.settings_root_entry_status_title),
        summary = rootHealthStatusSummary(rootHealthSnapshot),
        badge = rootHealthBadge(rootHealthSnapshot)
    ) {
        queryRootHealth(
            sessionId = sessionId,
            statusEntry = statusEntry,
            recoveryEntry = recoveryEntry,
            isBusy = { busy },
            setBusy = { busy = it }
        )
    }
    recoveryEntry = addSheetEntry(
        context = sheet,
        title = getString(R.string.settings_root_entry_recover_title),
        summary = getString(R.string.settings_root_entry_recover_summary),
        badge = actionBadge(getString(R.string.settings_root_entry_recover))
    ) {
        recoverRootHealth(
            sessionId = sessionId,
            statusEntry = statusEntry,
            recoveryEntry = recoveryEntry,
            isBusy = { busy },
            setBusy = { busy = it }
        )
    }
    addSheetTip(
        context = sheet,
        title = getString(R.string.settings_root_tip_title),
        lines = listOf(
            getString(R.string.settings_root_tip_no_system),
            getString(R.string.settings_root_tip_rollback),
            getString(R.string.settings_root_tip_manual)
        )
    )
    sheet.dialog.setOnDismissListener {
        cancelRootHealthSession(sessionId)
    }
    sheet.dialog.show()

    // 只有用户打开此面板才执行一次显式 Root 查询。
    queryRootHealth(
        sessionId = sessionId,
        statusEntry = statusEntry,
        recoveryEntry = recoveryEntry,
        isBusy = { busy },
        setBusy = { busy = it }
    )
}

private fun SettingsActivity.beginRootHealthSession(): Long {
    rootHealthSessionId += 1
    rootHealthJob?.cancel()
    rootHealthJob = null
    return rootHealthSessionId
}

private fun SettingsActivity.cancelRootHealthSession(sessionId: Long) {
    if (rootHealthSessionId != sessionId) return
    rootHealthSessionId += 1
    rootHealthJob?.cancel()
    rootHealthJob = null
}

private fun SettingsActivity.isCurrentRootHealthSession(sessionId: Long): Boolean {
    return rootHealthSessionId == sessionId && !isFinishing && !isDestroyed
}

internal fun SettingsActivity.updateRootHubCard() {
    val snapshot = rootHealthSnapshot
    val badge = rootHealthBadge(snapshot)
    overviewController.applyInfoBadge(
        tv = tvRootHubStatus,
        text = badge.text,
        textColorResId = badge.textColorResId,
        backgroundColorResId = badge.backgroundColorResId
    )
    tvRootHubSummary.text = rootHealthHubSummary(snapshot)
}

private fun SettingsActivity.queryRootHealth(
    sessionId: Long,
    statusEntry: View,
    recoveryEntry: View,
    isBusy: () -> Boolean,
    setBusy: (Boolean) -> Unit
) {
    if (!isCurrentRootHealthSession(sessionId) || isBusy()) return
    setBusy(true)
    renderRootHealthEntries(statusEntry, recoveryEntry, rootHealthSnapshot, busy = true)
    val job = lifecycleScope.launch {
        try {
            val snapshot = rootHealthRepository.query()
            if (isCurrentRootHealthSession(sessionId)) {
                rootHealthSnapshot = snapshot
                renderRootHealthEntries(statusEntry, recoveryEntry, snapshot, busy = false)
            }
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (_: Throwable) {
            if (isCurrentRootHealthSession(sessionId)) {
                rootHealthSnapshot = RootHealthSnapshot.unavailable()
                renderRootHealthEntries(statusEntry, recoveryEntry, rootHealthSnapshot, busy = false)
            }
        } finally {
            if (isCurrentRootHealthSession(sessionId)) {
                setBusy(false)
                rootHealthJob = null
            }
        }
    }
    rootHealthJob = job
}

private fun SettingsActivity.recoverRootHealth(
    sessionId: Long,
    statusEntry: View,
    recoveryEntry: View,
    isBusy: () -> Boolean,
    setBusy: (Boolean) -> Unit
) {
    if (!isCurrentRootHealthSession(sessionId) || isBusy()) return
    Toast.makeText(this, getString(R.string.settings_root_recover_running), Toast.LENGTH_SHORT).show()
    setBusy(true)
    renderRootHealthEntries(statusEntry, recoveryEntry, rootHealthSnapshot, busy = true)
    val job = lifecycleScope.launch {
        try {
            val result = rootHealthRepository.recoverAndQuery()
            if (isCurrentRootHealthSession(sessionId)) {
                rootHealthSnapshot = result.snapshot
                Toast.makeText(
                    this@recoverRootHealth,
                    if (result.actionSucceeded) {
                        getString(R.string.settings_root_recover_success)
                    } else {
                        rootFailureSummary(
                            reason = result.actionFailureReason ?: RootFailureReason.UNKNOWN,
                            exitCode = result.actionFailureExitCode
                        )
                    },
                    Toast.LENGTH_LONG
                ).show()
                renderRootHealthEntries(statusEntry, recoveryEntry, result.snapshot, busy = false)
            }
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (_: Throwable) {
            if (isCurrentRootHealthSession(sessionId)) {
                rootHealthSnapshot = RootHealthSnapshot.unavailable()
                Toast.makeText(
                    this@recoverRootHealth,
                    rootFailureSummary(RootFailureReason.UNKNOWN),
                    Toast.LENGTH_LONG
                ).show()
                renderRootHealthEntries(statusEntry, recoveryEntry, rootHealthSnapshot, busy = false)
            }
        } finally {
            if (isCurrentRootHealthSession(sessionId)) {
                setBusy(false)
                rootHealthJob = null
            }
        }
    }
    rootHealthJob = job
}

private fun SettingsActivity.renderRootHealthEntries(
    statusEntry: View,
    recoveryEntry: View,
    snapshot: RootHealthSnapshot,
    busy: Boolean
) {
    val statusSummary = statusEntry.findViewById<TextView>(R.id.tv_permission_item_summary)
    val statusBadge = statusEntry.findViewById<TextView>(R.id.tv_permission_item_status)
    val recoverySummary = recoveryEntry.findViewById<TextView>(R.id.tv_permission_item_summary)
    val recoveryBadge = recoveryEntry.findViewById<TextView>(R.id.tv_permission_item_status)
    statusSummary.text = if (busy) {
        getString(R.string.settings_root_status_checking)
    } else {
        rootHealthStatusSummary(snapshot)
    }
    val statusStyle = if (busy) {
        actionBadge(getString(R.string.settings_root_status_checking))
    } else {
        rootHealthBadge(snapshot)
    }
    overviewController.applyInfoBadge(
        tv = statusBadge,
        text = statusStyle.text,
        textColorResId = statusStyle.textColorResId,
        backgroundColorResId = statusStyle.backgroundColorResId
    )
    recoverySummary.text = if (busy) {
        getString(R.string.settings_root_recover_running)
    } else {
        getString(R.string.settings_root_entry_recover_summary)
    }
    val recoveryStyle = actionBadge(
        getString(if (busy) R.string.settings_root_recover_running else R.string.settings_root_entry_recover)
    )
    overviewController.applyInfoBadge(
        tv = recoveryBadge,
        text = recoveryStyle.text,
        textColorResId = recoveryStyle.textColorResId,
        backgroundColorResId = recoveryStyle.backgroundColorResId
    )
    statusEntry.isEnabled = !busy
    recoveryEntry.isEnabled = !busy
    updateRootHubCard()
}

private fun SettingsActivity.rootHealthHubSummary(snapshot: RootHealthSnapshot): String {
    return when (snapshot.state) {
        RootHealthState.UNCHECKED -> getString(R.string.settings_root_hub_summary_unchecked)
        RootHealthState.ROOT_UNAVAILABLE -> rootFailureSummary(snapshot)
        RootHealthState.MODULE_MISSING -> getString(R.string.settings_root_hub_summary_missing)
        RootHealthState.DEGRADED -> getString(R.string.settings_root_hub_summary_degraded)
        RootHealthState.HEALTHY -> getString(R.string.settings_root_hub_summary_healthy)
    }
}

internal fun SettingsActivity.rootHealthStatusSummary(snapshot: RootHealthSnapshot): String {
    if (snapshot.state == RootHealthState.UNCHECKED || snapshot.state == RootHealthState.ROOT_UNAVAILABLE) {
        return rootHealthHubSummary(snapshot)
    }
    return getString(
        R.string.settings_root_entry_status_summary,
        rootValueLabel(snapshot.module),
        rootValueLabel(snapshot.guard),
        rootValueLabel(snapshot.accessibility),
        rootValueLabel(snapshot.home),
        rootValueLabel(snapshot.homeForeground),
        rootValueLabel(snapshot.doze),
        rootValueLabel(snapshot.cleanup),
        rootValueLabel(snapshot.lastRepair)
    )
}

private fun SettingsActivity.rootHealthBadge(snapshot: RootHealthSnapshot): BadgeStyle {
    return when (snapshot.state) {
        RootHealthState.UNCHECKED -> actionBadge(getString(R.string.settings_root_status_unchecked))
        RootHealthState.ROOT_UNAVAILABLE -> BadgeStyle(
            text = getString(rootFailureBadge(snapshot.failureReason)),
            textColorResId = R.color.launcher_danger,
            backgroundColorResId = R.color.launcher_danger_soft
        )
        RootHealthState.MODULE_MISSING -> BadgeStyle(
            text = getString(R.string.settings_root_status_missing),
            textColorResId = R.color.launcher_warning,
            backgroundColorResId = R.color.launcher_warning_soft
        )
        RootHealthState.DEGRADED -> BadgeStyle(
            text = getString(R.string.settings_root_status_degraded),
            textColorResId = R.color.launcher_warning,
            backgroundColorResId = R.color.launcher_warning_soft
        )
        RootHealthState.HEALTHY -> BadgeStyle(
            text = getString(R.string.settings_root_status_healthy),
            textColorResId = R.color.launcher_action_dark,
            backgroundColorResId = R.color.launcher_primary_soft
        )
    }
}

private fun SettingsActivity.rootFailureSummary(snapshot: RootHealthSnapshot): String {
    return rootFailureSummary(
        reason = snapshot.failureReason ?: RootFailureReason.UNKNOWN,
        exitCode = snapshot.failureExitCode
    )
}

internal fun SettingsActivity.rootFailureSummary(
    reason: RootFailureReason,
    exitCode: Int? = null
): String {
    return when (reason) {
        RootFailureReason.SU_NOT_FOUND -> getString(
            R.string.settings_root_failure_su_not_found,
            android.os.Process.myUid()
        )
        RootFailureReason.SU_EXECUTION_BLOCKED ->
            getString(R.string.settings_root_failure_su_execution_blocked)
        RootFailureReason.SU_START_FAILED -> getString(R.string.settings_root_failure_su_start_failed)
        RootFailureReason.SU_AUTHORIZATION_DENIED ->
            getString(R.string.settings_root_failure_authorization_denied)
        RootFailureReason.SCRIPT_NOT_FOUND -> getString(R.string.settings_root_failure_script_not_found)
        RootFailureReason.SCRIPT_EXECUTION_BLOCKED ->
            getString(R.string.settings_root_failure_script_execution_blocked)
        RootFailureReason.COMMAND_TIMEOUT -> getString(R.string.settings_root_failure_timeout)
        RootFailureReason.COMMAND_FAILED -> getString(
            R.string.settings_root_failure_command_failed,
            exitCode ?: -1
        )
        RootFailureReason.OUTPUT_LIMIT_EXCEEDED ->
            getString(R.string.settings_root_failure_output_too_large)
        RootFailureReason.STATUS_FORMAT_INVALID ->
            getString(R.string.settings_root_failure_status_invalid)
        RootFailureReason.UNKNOWN -> getString(R.string.settings_root_failure_unknown)
    }
}

private fun rootFailureBadge(reason: RootFailureReason?): Int {
    return when (reason ?: RootFailureReason.UNKNOWN) {
        RootFailureReason.SU_NOT_FOUND -> R.string.settings_root_status_su_not_found
        RootFailureReason.SU_EXECUTION_BLOCKED -> R.string.settings_root_status_su_execution_blocked
        RootFailureReason.SU_START_FAILED -> R.string.settings_root_status_su_start_failed
        RootFailureReason.SU_AUTHORIZATION_DENIED -> R.string.settings_root_status_authorization_denied
        RootFailureReason.SCRIPT_NOT_FOUND -> R.string.settings_root_status_script_not_found
        RootFailureReason.SCRIPT_EXECUTION_BLOCKED ->
            R.string.settings_root_status_script_execution_blocked
        RootFailureReason.COMMAND_TIMEOUT -> R.string.settings_root_status_timeout
        RootFailureReason.COMMAND_FAILED -> R.string.settings_root_status_command_failed
        RootFailureReason.OUTPUT_LIMIT_EXCEEDED -> R.string.settings_root_status_output_too_large
        RootFailureReason.STATUS_FORMAT_INVALID -> R.string.settings_root_status_format_invalid
        RootFailureReason.UNKNOWN -> R.string.settings_root_status_unavailable
    }
}

private fun SettingsActivity.rootValueLabel(value: String): String {
    return when (value) {
        "active", "running", "enabled", "owned", "verified", "present", "ready", "ok" -> getString(R.string.settings_root_value_ready)
        "disabled", "stale", "other", "none", "unverified", "absent", "failed" ->
            getString(R.string.settings_root_value_pending)
        "missing" -> getString(R.string.settings_root_value_missing)
        "removing", "invalid" -> getString(R.string.settings_root_value_problem)
        else -> getString(R.string.settings_root_value_unknown)
    }
}
