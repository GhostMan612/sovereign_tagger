// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

package com.sovereigntagger

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import android.graphics.Color

class SovereignWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        for (appWidgetId in appWidgetIds) {
            updateAppWidget(context, appWidgetManager, appWidgetId)
        }
    }

    private fun updateAppWidget(context: Context, appWidgetManager: AppWidgetManager, appWidgetId: Int) {
        val views = RemoteViews(context.packageName, R.layout.sovereign_widget_initial)
        
        // Set text
        views.setTextViewText(R.id.widget_title, "SOVEREIGN")
        views.setTextViewText(R.id.widget_track, "NO AUDIO LOADED")
        views.setTextViewText(R.id.widget_artist, "[ System Idle. Tap To Mount Media. ]")
        views.setTextViewText(R.id.widget_time, java.text.SimpleDateFormat("HH:mm", java.util.Locale.getDefault()).format(java.util.Date()))
        
        // Set click listeners for buttons
        val prevIntent = Intent(context, MainActivity::class.java).apply {
            action = "com.sovereign.tagger.WIDGET_PREV"
            putExtra("widget_id", appWidgetId)
        }
        val playIntent = Intent(context, MainActivity::class.java).apply {
            action = "com.sovereign.tagger.WIDGET_PLAY"
            putExtra("widget_id", appWidgetId)
        }
        val nextIntent = Intent(context, MainActivity::class.java).apply {
            action = "com.sovereign.tagger.WIDGET_NEXT"
            putExtra("widget_id", appWidgetId)
        }
        val queueIntent = Intent(context, MainActivity::class.java).apply {
            action = "com.sovereign.tagger.WIDGET_QUEUE"
            putExtra("widget_id", appWidgetId)
        }
        
        views.setOnClickPendingIntent(R.id.btn_prev, android.app.PendingIntent.getActivity(
            context, 0, prevIntent, android.app.PendingIntent.FLAG_IMMUTABLE or android.app.PendingIntent.FLAG_UPDATE_CURRENT
        ))
        views.setOnClickPendingIntent(R.id.btn_play, android.app.PendingIntent.getActivity(
            context, 0, playIntent, android.app.PendingIntent.FLAG_IMMUTABLE or android.app.PendingIntent.FLAG_UPDATE_CURRENT
        ))
        views.setOnClickPendingIntent(R.id.btn_next, android.app.PendingIntent.getActivity(
            context, 0, nextIntent, android.app.PendingIntent.FLAG_IMMUTABLE or android.app.PendingIntent.FLAG_UPDATE_CURRENT
        ))
        views.setOnClickPendingIntent(R.id.btn_queue, android.app.PendingIntent.getActivity(
            context, 0, queueIntent, android.app.PendingIntent.FLAG_IMMUTABLE or android.app.PendingIntent.FLAG_UPDATE_CURRENT
        ))
        
        appWidgetManager.updateAppWidget(appWidgetId, views)
    }
}