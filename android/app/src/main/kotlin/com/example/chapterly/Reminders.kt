package com.example.chapterly

import android.Manifest
import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import java.util.Calendar

/**
 * The daily reading reminder. Each time Chapterly runs it works out whether
 * you are behind this year's goal and hands over the words (or none). At the
 * time you chose, this posts them as a notification. The alarm is set again
 * after the phone restarts or the app is updated.
 */
class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED -> Reminders.schedule(context)
            Reminders.ACTION_REMIND -> Reminders.post(context)
        }
    }
}

object Reminders {
    const val ACTION_REMIND = "com.example.chapterly.REMIND"
    private const val CHANNEL = "reading_reminder"
    private const val NOTIFICATION = 4201

    fun save(context: Context, on: Boolean, minutes: Int, text: String?) {
        context.getSharedPreferences(ChapterlyWidget.PREFS, Context.MODE_PRIVATE).edit()
            .putBoolean("reminderOn", on)
            .putInt("reminderMinutes", minutes)
            .putString("reminderText", text ?: "")
            .apply()
        schedule(context)
    }

    fun schedule(context: Context) {
        val prefs = context.getSharedPreferences(ChapterlyWidget.PREFS, Context.MODE_PRIVATE)
        val alarms = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val pending = PendingIntent.getBroadcast(
            context,
            2,
            Intent(context, ReminderReceiver::class.java).setAction(ACTION_REMIND),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        alarms.cancel(pending)
        if (!prefs.getBoolean("reminderOn", false)) return
        val minutes = prefs.getInt("reminderMinutes", 20 * 60)
        val next = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, minutes / 60)
            set(Calendar.MINUTE, minutes % 60)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
            if (timeInMillis <= System.currentTimeMillis()) add(Calendar.DAY_OF_YEAR, 1)
        }
        // Inexact: no special permission, and Android may batch it a little.
        alarms.setInexactRepeating(
            AlarmManager.RTC_WAKEUP,
            next.timeInMillis,
            AlarmManager.INTERVAL_DAY,
            pending,
        )
    }

    fun post(context: Context) {
        val prefs = context.getSharedPreferences(ChapterlyWidget.PREFS, Context.MODE_PRIVATE)
        val text = prefs.getString("reminderText", "") ?: ""
        if (!prefs.getBoolean("reminderOn", false) || text.isEmpty()) return
        if (Build.VERSION.SDK_INT >= 33 &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) return
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val builder = if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL, "Reading reminder", NotificationManager.IMPORTANCE_DEFAULT),
            )
            Notification.Builder(context, CHANNEL)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }
        val open = PendingIntent.getActivity(
            context,
            3,
            Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val notification = builder
            .setSmallIcon(R.drawable.ic_stat_book)
            .setContentTitle("Time to read?")
            .setContentText(text)
            .setStyle(Notification.BigTextStyle().bigText(text))
            .setContentIntent(open)
            .setAutoCancel(true)
            .build()
        manager.notify(NOTIFICATION, notification)
    }
}
