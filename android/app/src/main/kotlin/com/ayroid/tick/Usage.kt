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
    const val SCREEN_OFF = 4

    /** One row of the system's event stream, reduced to what the sum needs. */
    data class Moment(val pkg: String, val type: Int, val at: Long)

    /** One app's slice of a window of time. */
    data class Slice(var ms: Long = 0, var opens: Int = 0)

    data class Window(val byPackage: Map<String, Slice>, val unlocks: Int)

    /**
     * Sum foreground time from an ordered event stream.
     *
     * Exactly one app is in front at a time, so this tracks a single current
     * package and the instant it came forward. A session runs from an app
     * coming to the front until **another app comes to the front**, or the
     * screen goes off, or the window ends.
     *
     * A pause deliberately does NOT end a session. That is the whole
     * difference between agreeing with Digital Wellbeing and not: apps pause
     * constantly for things the user never perceives as leaving the app — a
     * system dialog, the notification shade, a sub-activity, a navigation
     * gesture that gets cancelled. Measured against Wellbeing on one real day,
     * ending sessions on pause lost 67 of WhatsApp's 97 minutes across 329
     * pause/resume cycles, and 18 of Instagram's 55 across 76, while apps with
     * no such churn matched to the minute.
     *
     * Sessions are disjoint by construction — `since` only ever moves forward,
     * to an event's own timestamp — so the total can never exceed the window.
     * That is a structural guarantee, not a test: an earlier version of this
     * function summed a map of open packages and reported 17756 hours in a
     * day, because Android fires ACTIVITY_PAUSED *and then* ACTIVITY_STOPPED
     * for the same activity and both were treated as a close.
     *
     * Two edges that do need handling:
     *
     *  - An app was already in front when the window opened. It has no RESUMED
     *    inside the window, so its first event is a pause for a package
     *    nothing is tracking: credited from [start], once, and then let go
     *    rather than left current — there is no way to know what took over.
     *  - An app is still in front at [end]. Its run is closed at [end], not
     *    dropped, or today's top app always reads short.
     */
    fun fold(moments: List<Moment>, start: Long, end: Long): Window {
        val slices = HashMap<String, Slice>()
        var unlocks = 0

        var current: String? = null
        var since = start

        // Whether anything has been attributed yet. Exactly one app can have
        // been in front when the window opened, so that credit is available
        // exactly once, before the first RESUMED.
        var primed = false

        fun add(pkg: String, from: Long, to: Long) {
            val span = to - from
            if (span > 0) slices.getOrPut(pkg) { Slice() }.ms += span
        }

        for (moment in moments) {
            when (moment.type) {
                RESUMED -> {
                    // The same package resuming again is a sub-activity or a
                    // configuration change — a rotation, a theme switch — not
                    // the user reaching for the app, and not a new session.
                    if (current != moment.pkg) {
                        current?.let { add(it, since, moment.at) }
                        current = moment.pkg
                        since = moment.at
                        slices.getOrPut(moment.pkg) { Slice() }.opens++
                    }
                    primed = true
                }

                PAUSED -> {
                    if (!primed && current == null) {
                        // The app that was in front when the window opened.
                        add(moment.pkg, start, moment.at)
                    }
                    // Otherwise ignored. See the note above: a pause is not
                    // the end of a session.
                    primed = true
                }

                SCREEN_OFF -> {
                    current?.let { add(it, since, moment.at) }
                    current = null
                    since = moment.at
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
                UsageEvents.Event.ACTIVITY_PAUSED,
                UsageEvents.Event.ACTIVITY_STOPPED -> PAUSED
                UsageEvents.Event.KEYGUARD_HIDDEN -> UNLOCK
                // What actually ends a session, along with another app
                // starting one. Without these a phone put down mid-app would
                // accrue time until the next thing was opened — the price of
                // not ending on a pause.
                UsageEvents.Event.SCREEN_NON_INTERACTIVE,
                UsageEvents.Event.KEYGUARD_SHOWN,
                UsageEvents.Event.DEVICE_SHUTDOWN -> SCREEN_OFF
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
