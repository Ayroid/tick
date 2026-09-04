package com.ayroid.tick

import android.content.Context
import android.provider.Settings
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Per-app notification counts — the one number the system will not hand over.
 *
 * Screen time and unlocks come out of the usage event stream for free.
 * Notifications do not: `UsageEvents` has an interruption event but it is not
 * delivered to ordinary apps, so counting them means being a notification
 * listener, which is a third thing to grant. It is opt-in from the Insights
 * screen rather than asked for in onboarding, and it can only ever count
 * forward — there is no history to backfill.
 */
class NotifService : NotificationListenerService() {

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        val notification = sbn?.notification ?: return
        val pkg = sbn.packageName ?: return

        // A group summary is the header over notifications already counted,
        // and an ongoing notification is a music player or a download sitting
        // in the shade rather than something that asked for attention.
        val flags = notification.flags
        if (flags and android.app.Notification.FLAG_GROUP_SUMMARY != 0) return
        if (flags and android.app.Notification.FLAG_ONGOING_EVENT != 0) return

        Rules.bumpNotification(this, pkg, today())
    }

    private fun today(): String =
        SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())

    companion object {
        fun isEnabled(context: Context): Boolean {
            val enabled = Settings.Secure.getString(
                context.contentResolver,
                "enabled_notification_listeners",
            ) ?: return false
            val name = "${context.packageName}/${NotifService::class.java.name}"
            return enabled.split(':').any { it.equals(name, ignoreCase = true) }
        }
    }
}
