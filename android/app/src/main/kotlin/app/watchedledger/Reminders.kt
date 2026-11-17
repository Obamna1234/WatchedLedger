package app.watchedledger

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import org.json.JSONArray
import org.json.JSONObject

/**
 * "New episode" reminders, scheduled by the phone for itself (no server,
 * no account, no push token). The app hands over a list of air times;
 * they are kept here so they survive a restart of the phone.
 */
object Reminders {
    private const val PREFS = "watchedledger_reminders"
    private const val CHANNEL = "episodes"

    fun schedule(context: Context, list: List<Map<*, *>>) {
        cancelAll(context)
        val now = System.currentTimeMillis()
        val kept = JSONArray()
        for (r in list.take(64)) {
            val id = (r["id"] as? Number)?.toInt() ?: continue
            val at = (r["at"] as? Number)?.toLong() ?: continue
            val title = (r["title"] as? String)?.take(120) ?: continue
            val body = (r["body"] as? String)?.take(200) ?: ""
            if (at <= now) continue
            kept.put(JSONObject().put("id", id).put("at", at).put("title", title).put("body", body))
        }
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString("list", kept.toString()).apply()
        arm(context)
    }

    /** (Re)sets the alarms for everything saved. Also used after a reboot. */
    fun arm(context: Context) {
        val alarms = context.getSystemService(AlarmManager::class.java) ?: return
        val now = System.currentTimeMillis()
        for (r in saved(context)) {
            if (r.getLong("at") <= now) continue
            // Inexact on purpose: no "exact alarm" permission needed.
            alarms.setAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP, r.getLong("at"), pending(context, r)
            )
        }
    }

    fun cancelAll(context: Context) {
        val alarms = context.getSystemService(AlarmManager::class.java)
        for (r in saved(context)) alarms?.cancel(pending(context, r))
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().clear().apply()
    }

    private fun saved(context: Context): List<JSONObject> {
        val raw = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString("list", null) ?: return emptyList()
        return try {
            val arr = JSONArray(raw)
            List(arr.length()) { arr.getJSONObject(it) }
        } catch (e: Exception) {
            emptyList()
        }
    }

    private fun pending(context: Context, r: JSONObject): PendingIntent {
        val intent = Intent(context, ReminderReceiver::class.java)
            .putExtra("id", r.getInt("id"))
            .putExtra("title", r.getString("title"))
            .putExtra("body", r.optString("body"))
        return PendingIntent.getBroadcast(
            context, r.getInt("id"), intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
    }

    @Suppress("DEPRECATION")
    private fun newBuilder(context: Context): Notification.Builder =
        if (Build.VERSION.SDK_INT >= 26) Notification.Builder(context, CHANNEL)
        else Notification.Builder(context)

    fun show(context: Context, id: Int, title: String, body: String) {
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL, "New episodes", NotificationManager.IMPORTANCE_DEFAULT)
            )
        }
        val open = PendingIntent.getActivity(
            context, 0, Intent(context, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        val builder = newBuilder(context)
        // On a locked screen show only "New episode", not the show name.
        val public = newBuilder(context)
            .setSmallIcon(R.drawable.ic_stat_episode)
            .setContentTitle("New episode")
            .build()
        val n = builder
            .setSmallIcon(R.drawable.ic_stat_episode)
            .setContentTitle(title)
            .setContentText(body)
            .setAutoCancel(true)
            .setContentIntent(open)
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .setPublicVersion(public)
            .build()
        try {
            manager.notify(id, n)
        } catch (e: SecurityException) {
            // Notification permission was taken away: nothing to show.
        }
    }
}

class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        Reminders.show(
            context,
            intent.getIntExtra("id", 0),
            intent.getStringExtra("title") ?: return,
            intent.getStringExtra("body") ?: "",
        )
    }
}

/** Alarms are wiped when the phone restarts; put them back. */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED) Reminders.arm(context)
    }
}
