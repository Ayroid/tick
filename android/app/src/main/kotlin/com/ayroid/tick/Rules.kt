package com.ayroid.tick

import android.content.Context
import org.json.JSONObject
import java.util.Calendar

/**
 * The limits, schedules and focus sessions, as the native side sees them.
 *
 * Dart owns this data and is the only thing that writes it; every mutation of
 * the store mirrors the same JSON down the channel into a plain Android
 * SharedPreferences file. GuardService reads it here because by the time an
 * app is coming to the front there is usually no Flutter engine alive to ask.
 *
 * Deliberately NOT the `FlutterSharedPreferences` file. That is the
 * shared_preferences plugin's private storage format, it prefixes every key
 * with `flutter.`, and it is in the middle of migrating to DataStore — reading
 * it from Kotlin would be a bet on someone else's implementation detail.
 */
object Rules {

    private const val FILE = "tick"
    private const val KEY_RULES = "rules"
    private const val KEY_NOTIFICATIONS = "notifications"

    private fun prefs(context: Context) =
        context.getSharedPreferences(FILE, Context.MODE_PRIVATE)

    fun save(context: Context, json: String) {
        prefs(context).edit().putString(KEY_RULES, json).apply()
    }

    fun load(context: Context): JSONObject =
        try {
            JSONObject(prefs(context).getString(KEY_RULES, "{}") ?: "{}")
        } catch (_: Exception) {
            // A half-written blob must not take the guard down; with no rules
            // it simply blocks nothing, which is the safe direction to fail.
            JSONObject()
        }

    /** The app's daily budget in minutes, or null if it has none. */
    fun limitMinutes(rules: JSONObject, pkg: String): Int? {
        val limits = rules.optJSONObject("limits") ?: return null
        if (!limits.has(pkg)) return null
        val minutes = limits.optInt(pkg, -1)
        return if (minutes >= 0) minutes else null
    }

    /** A focus session or a schedule covering [pkg] right now. */
    fun inSession(rules: JSONObject, pkg: String, now: Long): Boolean {
        val focus = rules.optJSONObject("focus")
        if (focus != null && focus.optLong("until", 0) > now &&
            contains(focus.optJSONArray("packages"), pkg)
        ) {
            return true
        }

        val schedules = rules.optJSONArray("schedules") ?: return false
        for (i in 0 until schedules.length()) {
            val s = schedules.optJSONObject(i) ?: continue
            if (!s.optBoolean("enabled", true)) continue
            if (!contains(s.optJSONArray("packages"), pkg)) continue
            if (activeNow(s, now)) return true
        }
        return false
    }

    /**
     * Whether a schedule's window covers [now].
     *
     * A window whose end is before its start wraps midnight — 22:00 to 07:00
     * is the common case and the whole reason this is not a range check. When
     * it wraps, the half after midnight belongs to the *previous* day's
     * occurrence, so a Friday-only bedtime still ends at 07:00 on Saturday.
     */
    private fun activeNow(schedule: JSONObject, now: Long): Boolean {
        val from = minutesOf(schedule.optString("from", "00:00"))
        val to = minutesOf(schedule.optString("to", "00:00"))
        val days = schedule.optJSONArray("days")

        val calendar = Calendar.getInstance().apply { timeInMillis = now }
        val minutes =
            calendar.get(Calendar.HOUR_OF_DAY) * 60 + calendar.get(Calendar.MINUTE)
        // Calendar counts Sunday as 1; Dart's DateTime.weekday counts Monday
        // as 1, and the stored days are Dart's.
        val today = ((calendar.get(Calendar.DAY_OF_WEEK) + 5) % 7) + 1
        val yesterday = if (today == 1) 7 else today - 1

        if (from == to) return false
        return if (from < to) {
            minutes >= from && minutes < to && onDay(days, today)
        } else {
            (minutes >= from && onDay(days, today)) ||
                (minutes < to && onDay(days, yesterday))
        }
    }

    /** No days listed means every day. */
    private fun onDay(days: org.json.JSONArray?, day: Int): Boolean {
        if (days == null || days.length() == 0) return true
        for (i in 0 until days.length()) if (days.optInt(i) == day) return true
        return false
    }

    private fun contains(array: org.json.JSONArray?, value: String): Boolean {
        if (array == null) return false
        for (i in 0 until array.length()) if (array.optString(i) == value) return true
        return false
    }

    /** `HH:mm` -> minutes past midnight. A malformed value reads as midnight. */
    private fun minutesOf(text: String): Int {
        val parts = text.split(":")
        if (parts.size != 2) return 0
        val h = parts[0].toIntOrNull() ?: return 0
        val m = parts[1].toIntOrNull() ?: return 0
        return (h.coerceIn(0, 23) * 60) + m.coerceIn(0, 59)
    }

    // ── Notification counts ─────────────────────────────────────────────────
    // The one thing the native side writes rather than reads. Kept in the same
    // file, as { "2026-09-04": { "com.whatsapp": 12 } }.

    fun bumpNotification(context: Context, pkg: String, day: String) {
        val store = notifications(context)
        val today = store.optJSONObject(day) ?: JSONObject()
        today.put(pkg, today.optInt(pkg, 0) + 1)
        store.put(day, today)

        // Keep a month. Nothing reads further back, and this file is rewritten
        // on every single notification the phone receives.
        val keys = store.keys().asSequence().toList().sorted()
        for (old in keys.dropLast(31)) store.remove(old)

        prefs(context).edit().putString(KEY_NOTIFICATIONS, store.toString()).apply()
    }

    fun notifications(context: Context): JSONObject =
        try {
            JSONObject(prefs(context).getString(KEY_NOTIFICATIONS, "{}") ?: "{}")
        } catch (_: Exception) {
            JSONObject()
        }
}
