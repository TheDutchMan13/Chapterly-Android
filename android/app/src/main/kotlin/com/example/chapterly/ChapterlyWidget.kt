package com.example.chapterly

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.view.View
import android.widget.RemoteViews
import java.security.MessageDigest
import java.security.SecureRandom

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

        /**
         * A random word only this app knows (kept in its private
         * preferences), put in the widget's play/pause button. MainActivity
         * has to be open to other apps for the launcher, so a play/pause
         * request without it (from another app) is ignored.
         */
        private const val EXTRA_TOKEN = "com.example.chapterly.TOGGLE_TOKEN"
        private const val TOKEN_KEY = "toggleToken"

        private fun token(context: Context): String {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            prefs.getString(TOKEN_KEY, null)?.let { return it }
            val bytes = ByteArray(16)
            SecureRandom().nextBytes(bytes)
            val made = bytes.joinToString("") { "%02x".format(it) }
            prefs.edit().putString(TOKEN_KEY, made).commit()
            return made
        }

        /** True for the widget's own play/pause button, and only for it. */
        fun isToggle(context: Context, intent: Intent?): Boolean {
            if (intent?.action != ACTION_TOGGLE) return false
            return try {
                val given = intent.getStringExtra(EXTRA_TOKEN) ?: return false
                MessageDigest.isEqual(
                    given.toByteArray(Charsets.UTF_8),
                    token(context).toByteArray(Charsets.UTF_8),
                )
            } catch (e: Exception) {
                // Extras another app made unreadable.
                false
            }
        }

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
            if (action == ACTION_TOGGLE) intent.putExtra(EXTRA_TOKEN, token(context))
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
