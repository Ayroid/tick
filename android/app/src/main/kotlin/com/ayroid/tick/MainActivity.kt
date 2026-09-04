package com.ayroid.tick

import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.provider.Settings
import androidx.core.app.NotificationManagerCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

/**
 * The one channel between Dart and the parts of Android that Dart cannot see.
 *
 * Wick and Penny have no platform channels at all; Tick cannot avoid them,
 * because the two things it is for — reading the system's usage records and
 * reacting to an app coming to the front — have no pub package that does them
 * honestly. Everything here is a thin call through to Usage or Rules; no logic
 * lives in this file that is not about marshalling.
 */
class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)

        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "permissions" -> result.success(permissions())
                    "openUsageSettings" ->
                        result.success(open(Settings.ACTION_USAGE_ACCESS_SETTINGS))
                    "openAccessibilitySettings" ->
                        result.success(open(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                    "openNotificationSettings" ->
                        result.success(
                            open("android.settings.ACTION_NOTIFICATION_LISTENER_SETTINGS")
                        )
                    "usage" -> usage(call.argument("start"), call.argument("end"), result)
                    "apps" -> result.success(apps())
                    "setRules" -> {
                        Rules.save(this, call.arguments as? String ?: "{}")
                        result.success(true)
                    }
                    "notifications" ->
                        result.success(Rules.notifications(this).toString())
                    else -> result.notImplemented()
                }
            }
    }

    private fun permissions(): Map<String, Boolean> = mapOf(
        "usage" to Usage.hasPermission(this),
        "accessibility" to GuardService.isEnabled(this),
        "notifications" to NotifService.isEnabled(this),
        "postNotifications" to
            NotificationManagerCompat.from(this).areNotificationsEnabled(),
    )

    private fun open(action: String): Boolean = try {
        startActivity(Intent(action).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        true
    } catch (_: Exception) {
        // Some vendor ROMs ship without one of these screens. Better to tell
        // Dart it failed and have it say so than to crash on a settings link.
        false
    }

    private fun usage(start: Long?, end: Long?, result: MethodChannel.Result) {
        if (start == null || end == null) {
            result.error("range", "start and end are required", null)
            return
        }
        if (!Usage.hasPermission(this)) {
            // Not an error: it is the ordinary state before onboarding, and
            // the screens have a permission card for exactly this.
            result.success(mapOf("granted" to false))
            return
        }

        val window = Usage.between(this, start, end)
        result.success(
            mapOf(
                "granted" to true,
                "unlocks" to window.unlocks,
                "byPackage" to window.byPackage.mapValues {
                    mapOf("ms" to it.value.ms, "opens" to it.value.opens)
                },
            )
        )
    }

    /**
     * Every app with a launcher icon, with its label and icon.
     *
     * Needs QUERY_ALL_PACKAGES: since API 30 an app cannot see what else is
     * installed without it, and usage records come back as bare package names
     * that would otherwise be unresolvable to anything a person recognises.
     *
     * The icons are PNG bytes, sent once and cached in Dart. That is a few
     * hundred KB across the channel on a cold start, which is why Dart asks
     * for this list once rather than per screen.
     */
    private fun apps(): List<Map<String, Any>> {
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        val manager = packageManager
        return manager.queryIntentActivities(intent, 0)
            .mapNotNull { resolved ->
                val info = resolved.activityInfo?.applicationInfo ?: return@mapNotNull null
                if (info.packageName == packageName) return@mapNotNull null
                mapOf(
                    "package" to info.packageName,
                    "label" to manager.getApplicationLabel(info).toString(),
                    "icon" to png(manager.getApplicationIcon(info)),
                )
            }
            .distinctBy { it["package"] }
    }

    private fun png(drawable: Drawable): ByteArray {
        // 96px: the largest an icon is drawn at in Tick is 40dp, which is 120px
        // on a 3x screen — close enough that no one will see the difference,
        // and a fifth of the bytes of a full 432px adaptive icon.
        val size = 96
        val bitmap = if (drawable is BitmapDrawable && drawable.bitmap != null) {
            Bitmap.createScaledBitmap(drawable.bitmap, size, size, true)
        } else {
            Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888).also {
                val canvas = Canvas(it)
                drawable.setBounds(0, 0, size, size)
                drawable.draw(canvas)
            }
        }
        return ByteArrayOutputStream().use {
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)
            it.toByteArray()
        }
    }

    companion object {
        private const val CHANNEL = "com.ayroid.tick/native"
    }
}
