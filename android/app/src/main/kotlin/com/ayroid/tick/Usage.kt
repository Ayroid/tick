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
 * [fold] is called from two places — the method channel, to draw the screens,
 * and GuardService, to decide whether an app is over its budget. There is
 * exactly one implementation of "how long was this app in front of you".
 */
object Usage {

    // Our own event vocabulary rather than UsageEvents' constants, so [fold]
    // is a pure function over data and can be tested without a device. The
    // translation happens in one place, in [between].
    const val RESUMED = 1
    const val PAUSED = 2
    const val UNLOCK = 3

    /** One row of the system's event stream, reduced to what the sum needs. */
    data class Moment(val pkg: String, val type: Int, val at: Long)

    /** One app's slice of a window of time. */
    data class Slice(var ms: Long = 0, var opens: Int = 0)

    data class Window(val byPackage: Map<String, Slice>, val unlocks: Int)

    /**
     * Sum foreground time from an ordered event stream.
     *
     * Exactly one app is in front at a time, so this tracks a single current
     * package and the instant it came forward, rather than a map of open
     * packages. That is not a simplification — it is what makes the sum
     * correct.
     *
     * The map version is how this was first written and it was wrong by four
     * orders of magnitude. Android fires ACTIVITY_PAUSED *and then*
     * ACTIVITY_STOPPED for the same activity. The PAUSED consumed the stored
     * open-time, the STOPPED found nothing, fell through to "then it must have
     * been open since the window began", and added the whole elapsed day —
     * once per app switch. A launcher opened 345 times reported 5144 hours.
     *
     * Two edges that genuinely do need handling:
     *
     *  - An app was already in front when the window opened. It has no RESUMED
     *    inside the window, so its first event is a PAUSED for a package
     *    nothing is tracking: counted from [start], and only ever once.
     *  - An app is still in front at [end] and has not paused yet. Its run is
     *    closed at [end], not dropped, or today's top app always reads short.
     */
    fun fold(moments: List<Moment>, start: Long, end: Long): Window {
        val slices = HashMap<String, Slice>()
        var unlocks = 0

        var current: String? = null
        var since = start

        // Whether anything has been attributed yet. Exactly one app can have
        // been in front when the window opened, so the credit for that run is
        // available exactly once, before the first RESUMED. Without this, a
        // background activity stopping mid-window takes the same credit and
        // is handed the whole elapsed day.
        var primed = false

        fun add(pkg: String, from: Long, to: Long) {
            val span = to - from
            if (span > 0) slices.getOrPut(pkg) { Slice() }.ms += span
        }

        for (moment in moments) {
            when (moment.type) {
                RESUMED -> {
                    // The same activity resuming again is a configuration
                    // change — a rotation, a theme switch — not the user
                    // reaching for the app.
                    if (current != moment.pkg) {
                        current?.let { add(it, since, moment.at) }
                        current = moment.pkg
                        since = moment.at
                        slices.getOrPut(moment.pkg) { Slice() }.opens++
                    }
                    primed = true
                }

                PAUSED -> {
                    if (moment.pkg == current) {
                        add(moment.pkg, since, moment.at)
                        current = null
                        since = moment.at
                    } else if (!primed && current == null) {
                        // The app that was in front when the window opened.
                        add(moment.pkg, start, moment.at)
                    }
                    // Anything else is a background activity stopping, or the
                    // STOPPED that trails a PAUSED we already closed. Ignored.
                    primed = true
                }

                UNLOCK -> unlocks++
            }
        }

        current?.let { add(it, since, end) }
        return Window(slices, unlocks)
    }

    /**
     * Foreground milliseconds per package between [start] and [end].
     *
     * Built from the raw event stream rather than `queryUsageStats`, whose
     * INTERVAL_DAILY buckets are not aligned to local midnight and whose
     * `totalTimeInForeground` is widely inconsistent between vendors. Summing
     * RESUMED -> PAUSED pairs is what Digital Wellbeing's own numbers agree
     * with, and agreeing with the number already on the phone is the whole
     * credibility of this app.
     */
    fun between(context: Context, start: Long, end: Long): Window {
        val manager =
            context.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val moments = ArrayList<Moment>()

        val events = manager.queryEvents(start, end)
        val event = UsageEvents.Event()
        while (events.hasNextEvent()) {
            events.getNextEvent(event)
            val pkg = event.packageName ?: continue
            val type = when (event.eventType) {
                UsageEvents.Event.ACTIVITY_RESUMED -> RESUMED
                // STOPPED trails PAUSED for the same activity; [fold] ignores
                // the second of the pair. It is mapped rather than dropped so
                // an activity that stops without pausing still closes.
                UsageEvents.Event.ACTIVITY_PAUSED,
                UsageEvents.Event.ACTIVITY_STOPPED -> PAUSED
                UsageEvents.Event.KEYGUARD_HIDDEN -> UNLOCK
                else -> continue
            }
            moments.add(Moment(pkg, type, event.timeStamp))
        }

        return fold(moments, start, end)
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
