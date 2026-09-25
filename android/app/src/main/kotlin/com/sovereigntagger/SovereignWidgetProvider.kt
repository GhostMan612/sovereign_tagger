// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

package com.sovereigntagger

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.view.KeyEvent
import android.widget.RemoteViews

class SovereignWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        for (appWidgetId in appWidgetIds) {
            appWidgetManager.updateAppWidget(appWidgetId, buildViews(context))
        }
    }

    companion object {
        private const val PREFS = "sovereign_widget_state"

        fun pushState(context: Context, title: String, artist: String, playing: Boolean) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                .putString("title", title)
                .putString("artist", artist)
                .putBoolean("playing", playing)
                .apply()
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, SovereignWidgetProvider::class.java))
            if (ids.isEmpty()) return
            val views = buildViews(context)
            for (id in ids) manager.updateAppWidget(id, views)
        }

        private fun buildViews(context: Context): RemoteViews {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val title = prefs.getString("title", null)?.takeIf { it.isNotEmpty() } ?: "NO AUDIO LOADED"
            val artist = prefs.getString("artist", null)?.takeIf { it.isNotEmpty() } ?: "[ System Idle. Tap To Mount Media. ]"
            val playing = prefs.getBoolean("playing", false)

            val views = RemoteViews(context.packageName, R.layout.sovereign_widget_initial)
            views.setTextViewText(R.id.widget_title, "SOVEREIGN")
            views.setTextViewText(R.id.widget_track, title)
            views.setTextViewText(R.id.widget_artist, artist)
            views.setTextViewText(R.id.widget_time, if (playing) "▶ PLAYING" else "❚❚ PAUSED")
            views.setImageViewResource(R.id.btn_play, if (playing) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play)

            views.setOnClickPendingIntent(R.id.btn_prev, mediaButton(context, KeyEvent.KEYCODE_MEDIA_PREVIOUS, 11))
            views.setOnClickPendingIntent(R.id.btn_play, mediaButton(context, KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE, 12))
            views.setOnClickPendingIntent(R.id.btn_next, mediaButton(context, KeyEvent.KEYCODE_MEDIA_NEXT, 13))

            val openApp = Intent(context, MainActivity::class.java).apply {
                action = Intent.ACTION_MAIN
                addCategory(Intent.CATEGORY_LAUNCHER)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            }
            val openPending = PendingIntent.getActivity(context, 14, openApp, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
            views.setOnClickPendingIntent(R.id.btn_queue, openPending)
            views.setOnClickPendingIntent(R.id.widget_track, openPending)
            views.setOnClickPendingIntent(R.id.widget_title, openPending)
            return views
        }

        private fun mediaButton(context: Context, keyCode: Int, requestCode: Int): PendingIntent {
            val intent = Intent(Intent.ACTION_MEDIA_BUTTON).apply {
                component = ComponentName(context, "com.ryanheise.audioservice.MediaButtonReceiver")
                putExtra(Intent.EXTRA_KEY_EVENT, KeyEvent(KeyEvent.ACTION_DOWN, keyCode))
            }
            return PendingIntent.getBroadcast(context, requestCode, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        }
    }
}
