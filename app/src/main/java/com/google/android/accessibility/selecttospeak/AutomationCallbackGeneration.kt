package com.google.android.accessibility.selecttospeak

import java.util.concurrent.atomic.AtomicLong

/**
 * Small thread-safe generation gate for callbacks that may outlive their owner.
 *
 * A coroutine cancellation is cooperative and can race with a continuation that
 * is already queued. Issuing a new generation lets the continuation cheaply
 * prove that it still belongs to the current lifecycle before touching UI or
 * automation state.
 */
internal class AutomationCallbackGeneration {
    private val value = AtomicLong(0L)

    fun issue(): Long = value.incrementAndGet()

    fun invalidate(): Long = value.incrementAndGet()

    fun isCurrent(token: Long): Boolean = value.get() == token
}
