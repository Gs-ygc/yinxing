package com.google.android.accessibility.selecttospeak

import androidx.annotation.MainThread
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/**
 * 微信视频自动化的"时钟"管理器。
 *
 * 之所以从 [SelectToSpeakService] 抽出：
 * - 服务里同时有 [processJob]/[stepTimeoutJob]/[totalTimeoutJob] 三个并行 [Job]，
 *   彼此都要走 `xxJob?.cancel(); xxJob = ...launch {}` 的相同模板；
 * - 取消逻辑分散在 `cancelSession`、`transitionTo`、`rerouteTo`、`armTimeout` 等多处，
 *   一旦哪里漏一行 cancel 就会泄露 Job；
 * - 调用方只关心"现在请安排下一次推进，并设置一个可被取消的步骤超时"，与 Job 字段管理无关。
 *
 * 该 Clock **不持有** session 数据，仅通过回调与服务交互：
 * - [onProcessTick]：到点了，请推进一次状态机（即原 `processCurrentWindow`）。
 * - [onTimeoutFailure]：步骤或总流程超时，请按失败处理。
 * - [sessionStillActive]：作为最后一道全局保护，判断 "延迟到时之后是否仍有会话"。
 *
 * The supplied scope and all callbacks are main-thread confined in production.
 */
@MainThread
internal class VideoCallStepClock(
    private val scope: CoroutineScope,
    private val onProcessTick: () -> Unit,
    private val onTimeoutFailure: (message: String) -> Unit,
    private val sessionStillActive: () -> Boolean
) {
    private var processJob: Job? = null
    private var stepTimeoutJob: Job? = null
    private var totalTimeoutJob: Job? = null
    private val processGeneration = AutomationCallbackGeneration()
    private val stepTimeoutGeneration = AutomationCallbackGeneration()
    private val totalTimeoutGeneration = AutomationCallbackGeneration()

    /**
     * Schedules one state-machine tick owned by the caller's current session.
     *
     * Accessibility callbacks can be queued just as a session is cancelled. The
     * ownership predicate is checked at execution time so a late callback cannot
     * advance a replacement session.
     */
    fun scheduleProcess(delayMillis: Long, processStillCurrent: () -> Boolean) {
        val generation = processGeneration.issue()
        processJob?.cancel()
        processJob = scope.launch {
            delay(delayMillis)
            if (coroutineContext.isActive &&
                processGeneration.isCurrent(generation) &&
                processStillCurrent()
            ) {
                onProcessTick()
            }
        }
    }

    fun cancelProcess() {
        processGeneration.invalidate()
        processJob?.cancel()
        processJob = null
    }

    /**
     * @param stepStillCurrent 由调用方在到期时回答 "现在是否还卡在原 step"，由调用方持有 step 引用。
     */
    fun armStepTimeout(
        timeoutMillis: Long,
        failureMessage: String,
        stepStillCurrent: () -> Boolean
    ) {
        val generation = stepTimeoutGeneration.issue()
        stepTimeoutJob?.cancel()
        stepTimeoutJob = scope.launch {
            delay(timeoutMillis)
            if (coroutineContext.isActive &&
                stepTimeoutGeneration.isCurrent(generation) &&
                stepStillCurrent()
            ) {
                onTimeoutFailure(failureMessage)
            }
        }
    }

    fun cancelStepTimeout() {
        stepTimeoutGeneration.invalidate()
        stepTimeoutJob?.cancel()
        stepTimeoutJob = null
    }

    fun armTotalTimeout(
        timeoutMillis: Long,
        failureMessage: () -> String,
        sessionStillCurrent: () -> Boolean
    ) {
        val generation = totalTimeoutGeneration.issue()
        totalTimeoutJob?.cancel()
        totalTimeoutJob = scope.launch {
            delay(timeoutMillis)
            if (coroutineContext.isActive &&
                totalTimeoutGeneration.isCurrent(generation) &&
                sessionStillActive() &&
                sessionStillCurrent()
            ) {
                onTimeoutFailure(failureMessage())
            }
        }
    }

    fun cancelAll() {
        processGeneration.invalidate()
        stepTimeoutGeneration.invalidate()
        totalTimeoutGeneration.invalidate()
        processJob?.cancel()
        stepTimeoutJob?.cancel()
        totalTimeoutJob?.cancel()
        processJob = null
        stepTimeoutJob = null
        totalTimeoutJob = null
    }
}
