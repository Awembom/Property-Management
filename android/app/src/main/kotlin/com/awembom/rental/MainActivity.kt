package com.awembom.rental

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // The "Homedly" notification channel (Android 8+). Push messages from
        // the send-push Edge Function use it (channel_id "homedly"); people can
        // switch it off in the phone's settings.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                "homedly",
                "Rent, bills and messages",
                NotificationManager.IMPORTANCE_HIGH,
            )
            channel.description = "Rent reminders, new bills, receipts and messages from Homedly"
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }
}
