package com.ayroid.tick

import android.app.AppOpsManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.os.Process

/**
 * Per-app foreground time, straight out of the system.
 *
 * Tick counts nothing itself. Android has been recording this since the phone
 * was first switched on, and a second counter running in our own process would
 * only ever be a less accurate copy that stops when we are killed.
 *
 * The one function here is called from two places — the method channel, to
 * draw the screens, and GuardService, to decide whether an app is over its
 * budget. There is exactly one implementation of "how long was this app in
 * front of you", which is the point.
 */
object Usage {

    /** One app's slice of a window of time. */
    data class Slice(var ms: Long = 0, var opens: Int = 0)

    data class Window(val byPackage: Map<String, Slice>, val unlocks: Int)

    /**
     * Foreground milliseconds per package between [start] and [end].
     *
     * Built from the raw event stream rather than `queryUsageStats`, whose
     * INTERVAL_DAILY buckets are not aligned to local midnight and whose
     * `totalTimeInForeground` is widely inconsistent between vendors. Summing
     * RESUMED -> PAUSED pairs is what Digital Wellbeing's own numbers agree
     * with, and agreeing with the number already on the phone is the whole
     * credibility of this app.
     *
     * Two edges the pairing has to handle, both of which happen constantly:
     *
     *  - An app RESUMED before [start] and is still in front. There is no
     *    opening event inside the window, so its time is counted from [start].
     *    Handled by seeding `openedAt` on the first PAUSED we see for a
     *    package we never saw open.
     *  - An app is still in front at [end] and has not PAUSED yet. Its run is
     *    closed at [end], not dropped, or today's top app always reads short.
     */
    fun between(context: Context, start: Long, end: Long): Window {
        val manager =
            context.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val slices = HashMap<String, Slice>()
        val openedAt = HashMap<String, Long>()
        var unlocks = 0

        val events = manager.queryEvents(start, end)
        val event = UsageEvents.Event()
        while (events.hasNextEvent()) {
            events.getNextEvent(event)
            val pkg = event.packageName ?: continue
            when (event.eventType) {
                UsageEvents.Event.ACTIVITY_RESUMED -> {
                    // Only count an open if it was not already open: a
                    // configuration change resumes the same activity again and
                    // is not the user reaching for the app.
                    if (openedAt.put(pkg, event.timeStamp) == null) {
                        slices.getOrPut(pkg) { Slice() }.opens++
                    }
                }
                UsageEvents.Event.ACTIVITY_PAUSED,
                UsageEvents.Event.ACTIVITY_STOPPED -> {
                    val from = openedAt.remove(pkg) ?: start
                    val span = event.timeStamp - from
                    if (span > 0) slices.getOrPut(pkg) { Slice() }.ms += span
                }
                UsageEvents.Event.KEYGUARD_HIDDEN -> unlocks++
            }
        }

        // Whatever is still in front when the window closes.
        for ((pkg, from) in openedAt) {
            val span = end - from
            if (span > 0) slices.getOrPut(pkg) { Slice() }.ms += span
        }

        return Window(slices, unlocks)
    }

    /** Milliseconds [pkg] has been in front since local midnight. */
    fun todayMs(context: Context, pkg: String, now: Long): Long =
        between(context, startOfDay(now), now).byPackage[pkg]?.ms ?: 0

    /**
     * Local midnight before [at].
     *
     * Built from a Calendar rather than `at - at % 86_400_000`: that arithmetic
     * is UTC midnight, which is the wrong hour in every timezone but one, and
     * is wrong by a further hour across a DST change.
     */
    fun startOfDay(at: Long): Long = java.util.Calendar.getInstance().run {
        timeInMillis = at
        set(java.util.Calendar.HOUR_OF_DAY, 0)
        set(java.util.Calendar.MINUTE, 0)
        set(java.util.Calendar.SECOND, 0)
        set(java.util.Calendar.MILLISECOND, 0)
        timeInMillis
    }

    /**
     * Whether the user has granted usage access.
     *
     * PACKAGE_USAGE_STATS is an appop, not a runtime permission: it cannot be
     * requested with a dialog, only granted by hand in Settings, and holding
     * it in the manifest means nothing on its own.
     */
    fun hasPermission(context: Context): Boolean {
        val ops = context.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = ops.unsafeCheckOpNoThrow(
            AppOpsManager.OPSTR_GET_USAGE_STATS,
            Process.myUid(),
            context.packageName,
        )
        return mode == AppOpsManager.MODE_ALLOWED
    }
}
