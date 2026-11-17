package app.watchedledger

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.view.View
import android.widget.RemoteViews

/**
 * Home screen widget: the next few To Watch / To Read / To Listen items and
 * a "+" button. The app writes the lines (only while a widget exists);
 * when the app lock is on the widget just says "Locked".
 */
class NextUpWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        ids.forEach { render(context, manager, it) }
    }

    override fun onDisabled(context: Context) {
        // Last widget removed: forget the titles.
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().clear().apply()
    }

    companion object {
        const val PREFS = "watchedledger_widget"
        const val ACTION_QUICK_ADD = "app.watchedledger.QUICK_ADD"
        private val ROWS = intArrayOf(
            R.id.widget_item1, R.id.widget_item2, R.id.widget_item3,
            R.id.widget_item4, R.id.widget_item5,
        )

        fun hasWidgets(context: Context): Boolean {
            val manager = AppWidgetManager.getInstance(context)
            return manager.getAppWidgetIds(
                ComponentName(context, NextUpWidget::class.java)
            ).isNotEmpty()
        }

        /** Saves what to show and redraws every widget. */
        fun save(context: Context, lines: List<String>, locked: Boolean) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                .putString("lines", lines.take(ROWS.size).joinToString("\n") { it.take(80) })
                .putBoolean("locked", locked)
                .putBoolean("filled", true)
                .apply()
            val manager = AppWidgetManager.getInstance(context)
            manager.getAppWidgetIds(ComponentName(context, NextUpWidget::class.java))
                .forEach { render(context, manager, it) }
        }

        private fun render(context: Context, manager: AppWidgetManager, id: Int) {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val locked = prefs.getBoolean("locked", false)
            val filled = prefs.getBoolean("filled", false)
            val lines = (prefs.getString("lines", "") ?: "")
                .split('\n').filter { it.isNotBlank() }
            val views = RemoteViews(context.packageName, R.layout.widget_next_up)
            val message = when {
                locked -> "Locked"
                !filled -> "Open WatchedLedger to fill this"
                lines.isEmpty() -> "Nothing on your lists yet"
                else -> null
            }
            ROWS.forEachIndexed { i, row ->
                val text = if (message != null) (if (i == 0) message else "") else lines.getOrNull(i) ?: ""
                views.setTextViewText(row, text)
                views.setViewVisibility(row, if (text.isEmpty()) View.GONE else View.VISIBLE)
            }
            val flags = PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            val open = Intent(context, MainActivity::class.java).setAction(Intent.ACTION_MAIN)
            views.setOnClickPendingIntent(
                R.id.widget_root, PendingIntent.getActivity(context, 0, open, flags)
            )
            val add = Intent(context, MainActivity::class.java).setAction(ACTION_QUICK_ADD)
            views.setOnClickPendingIntent(
                R.id.widget_add, PendingIntent.getActivity(context, 1, add, flags)
            )
            manager.updateAppWidget(id, views)
        }
    }
}
