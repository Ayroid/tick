package com.ayroid.tick

import android.accessibilityservice.AccessibilityService
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.view.accessibility.AccessibilityEvent
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

/**
 * The whole of enforcement.
 *
 * Android has no API for preventing an app from launching. What it has is an
 * accessibility service, which is told when a window comes to the front and
 * can send the user back to the home screen — so that is what Tick does, and
 * the app says so plainly rather than implying a lock that does not exist. The
 * user can turn this service off in Settings at any time, and nothing here
 * tries to stop them: limits are freely editable by design, so guarding the
 * off switch would be incoherent.
 */
class GuardService : AccessibilityService() {

    private val handler = Handler(Looper.getMainLooper())
    private var current: String? = null
    private var pending: Runnable? = null
    private val lastNotified = HashMap<String, Long>()

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event?.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return
        val pkg = event.packageName?.toString() ?: return

        // A dialog, a keyboard or a toast inside the app we are already
        // watching fires this too. Only a genuine change of app matters, and
        // re-running on every one of them would re-query a day of events
        // several times a second.
        if (pkg == current) return
        current = pkg

        // Whatever the last app had queued is now irrelevant.
        pending?.let { handler.removeCallbacks(it) }
        pending = null

        if (pkg == packageName || isChrome(pkg)) return
        evaluate(pkg)
    }

    /**
     * Block [pkg], or arrange to block it the moment it runs out.
     *
     * The delayed re-check is not a nicety. A window event fires when an app
     * comes to the front and not again while you sit in it, so an app opened
     * at 29 minutes of a 30 minute budget would never be stopped — you would
     * scroll past the limit indefinitely and the feature would be theatre.
     */
    private fun evaluate(pkg: String) {
        val rules = Rules.load(this)
        val now = System.currentTimeMillis()

        if (Rules.inSession(rules, pkg, now)) {
            block(pkg, "Blocked right now")
            return
        }

        val minutes = Rules.limitMinutes(rules, pkg) ?: return
        val budget = minutes * 60_000L
        val used = Usage.todayMs(this, pkg, now)

        if (used >= budget) {
            block(pkg, "That's your ${minutes} minutes for today")
            return
        }

        val remaining = budget - used
        val check = object : Runnable {
            override fun run() {
                // Only if they are still in it. Leaving and coming back fires
                // a fresh event, which does its own arithmetic.
                if (current == pkg) evaluate(pkg)
            }
        }
        pending = check
        handler.postDelayed(check, remaining)
    }

    private fun block(pkg: String, message: String) {
        performGlobalAction(GLOBAL_ACTION_HOME)
        current = null

        // Reopening the app should say so again; a burst of window events from
        // one launch should not.
        val now = System.currentTimeMillis()
        if (now - (lastNotified[pkg] ?: 0) < 3_000) return
        lastNotified[pkg] = now
        notify(labelOf(pkg), message)
    }

    private fun notify(title: String, message: String) {
        val manager = NotificationManagerCompat.from(this)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL,
                    "Limits",
                    // Low: it lands in the shade with no sound. Being sent home
                    // is already the loud part; a chime on top of it nags.
                    NotificationManager.IMPORTANCE_LOW,
                )
            )
        }
        val notification = NotificationCompat.Builder(this, CHANNEL)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle(title)
            .setContentText(message)
            .setAutoCancel(true)
            .build()
        try {
            manager.notify(CHANNEL.hashCode(), notification)
        } catch (_: SecurityException) {
            // POST_NOTIFICATIONS not granted. The kick already happened, which
            // is the part that matters.
        }
    }

    private fun labelOf(pkg: String): String =
        try {
            packageManager.getApplicationLabel(
                packageManager.getApplicationInfo(pkg, 0)
            ).toString()
        } catch (_: Exception) {
            pkg
        }

    /**
     * The launcher, the system UI and the permission dialogs are windows, not
     * apps you spend time in. Blocking one would trap the phone.
     */
    private fun isChrome(pkg: String): Boolean =
        pkg == "com.android.systemui" ||
            pkg.startsWith("com.google.android.permissioncontroller") ||
            pkg == launcher

    private val launcher: String? by lazy {
        val intent = android.content.Intent(android.content.Intent.ACTION_MAIN)
            .addCategory(android.content.Intent.CATEGORY_HOME)
        packageManager.resolveActivity(intent, 0)?.activityInfo?.packageName
    }

    override fun onInterrupt() {}

    override fun onDestroy() {
        pending?.let { handler.removeCallbacks(it) }
        super.onDestroy()
    }

    companion object {
        private const val CHANNEL = "tick.limits"

        /**
         * Whether the user has switched the guard on.
         *
         * Read from the secure setting rather than kept as a flag of our own:
         * the user can turn the service off in Settings without the app ever
         * running, and a stale flag would have Tick claiming to be enforcing
         * limits it is not.
         */
        fun isEnabled(context: Context): Boolean {
            val enabled = Settings.Secure.getString(
                context.contentResolver,
                Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES,
            ) ?: return false
            val name = "${context.packageName}/${GuardService::class.java.name}"
            return enabled.split(':').any { it.equals(name, ignoreCase = true) }
        }
    }
}
