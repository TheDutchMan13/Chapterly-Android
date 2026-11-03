package com.example.chapterly

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.view.View
import android.widget.RemoteViews

/**
 * The home-screen widget: the book you are reading or listening to, with a
 * play/pause button for an audiobook. Chapterly tells it what to show (the
 * "chapterly/home" channel in MainActivity); it keeps that in its own
 * preferences, so it still shows after the phone restarts.
 */
class ChapterlyWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        val views = views(context)
        for (id in ids) manager.updateAppWidget(id, views)
    }

    companion object {
        const val PREFS = "chapterly_home"
        const val ACTION_TOGGLE = "com.example.chapterly.TOGGLE_PLAY"

        fun save(
            context: Context,
            title: String,
            author: String,
            detail: String,
            audio: Boolean,
            playing: Boolean,
        ) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                .putString("title", title)
                .putString("author", author)
                .putString("detail", detail)
                .putBoolean("audio", audio)
                .putBoolean("playing", playing)
                .apply()
            updateAll(context)
        }

        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, ChapterlyWidget::class.java))
            if (ids.isEmpty()) return
            val views = views(context)
            for (id in ids) manager.updateAppWidget(id, views)
        }

        private fun activity(context: Context, code: Int, action: String?): PendingIntent {
            val intent = Intent(context, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            if (action != null) intent.action = action
            return PendingIntent.getActivity(
                context,
                code,
                intent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
        }

        private fun views(context: Context): RemoteViews {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val views = RemoteViews(context.packageName, R.layout.chapterly_widget)
            views.setTextViewText(R.id.widget_title, prefs.getString("title", null) ?: "Chapterly")
            val author = prefs.getString("author", "") ?: ""
            views.setTextViewText(R.id.widget_author, author)
            views.setViewVisibility(R.id.widget_author, if (author.isEmpty()) View.GONE else View.VISIBLE)
            views.setTextViewText(
                R.id.widget_detail,
                prefs.getString("detail", null) ?: "Open Chapterly to pick a book",
            )
            views.setOnClickPendingIntent(R.id.widget_root, activity(context, 0, null))
            val audio = prefs.getBoolean("audio", false)
            views.setViewVisibility(R.id.widget_play, if (audio) View.VISIBLE else View.GONE)
            if (audio) {
                val playing = prefs.getBoolean("playing", false)
                views.setImageViewResource(
                    R.id.widget_play,
                    if (playing) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play,
                )
                views.setContentDescription(R.id.widget_play, if (playing) "Pause" else "Play")
                views.setOnClickPendingIntent(R.id.widget_play, activity(context, 1, ACTION_TOGGLE))
            }
            return views
        }
    }
}
