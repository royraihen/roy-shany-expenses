package com.royandshany.expense_tracker

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.database.Cursor
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.BufferedReader
import java.io.InputStreamReader
import kotlin.random.Random

class MainActivity : FlutterActivity() {
    private val channelName = "com.royandshany.expense_tracker/rasb"
    private val notificationChannelId = "roy_shany_expenses_alerts"
    private var methodChannel: MethodChannel? = null
    private var pendingPayload: Map<String, String>? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setupNotificationChannel()
        requestNotificationPermissionIfNeeded()
        handleIncomingIntent(intent, notifyImmediately = false)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        methodChannel = channel

        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialRasbContent" -> {
                    val payload = pendingPayload
                    pendingPayload = null
                    result.success(payload)
                }
                "showExpenseNotification" -> {
                    val title = call.argument<String>("title") ?: "Roy & Shany ₪"
                    val body = call.argument<String>("body") ?: "Expenses updated"
                    showSystemNotification(title, body)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun setupNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val channel = NotificationChannel(
                notificationChannelId,
                "Expense Updates",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Notifications when Roy or Shany adds or updates expenses"
                enableVibration(true)
            }
            manager.createNotificationChannel(channel)
        }
    }

    private fun requestNotificationPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1001)
            }
        }
    }

    private fun showSystemNotification(title: String, body: String) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                    return
                }
            }
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val openIntent = Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val pendingFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }
            val pendingIntent = PendingIntent.getActivity(this, 0, openIntent, pendingFlags)

            val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(this, notificationChannelId)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(this)
            }

            val notification = builder
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle(title)
                .setContentText(body)
                .setStyle(Notification.BigTextStyle().bigText(body))
                .setContentIntent(pendingIntent)
                .setAutoCancel(true)
                .build()

            manager.notify(Random.nextInt(1000, 999999), notification)
        } catch (_: Exception) {
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIncomingIntent(intent, notifyImmediately = true)
    }

    private fun handleIncomingIntent(intent: Intent?, notifyImmediately: Boolean) {
        if (intent == null) return

        val action = intent.action ?: return
        var fileUri: Uri? = null

        if (action == Intent.ACTION_VIEW) {
            fileUri = intent.data
        } else if (action == Intent.ACTION_SEND) {
            fileUri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
            } else {
                @Suppress("DEPRECATION")
                intent.getParcelableExtra(Intent.EXTRA_STREAM) as? Uri
            }
            if (fileUri == null) {
                val sharedText = intent.getStringExtra(Intent.EXTRA_TEXT)
                if (!sharedText.isNullOrBlank()) {
                    deliverPayload(
                        mapOf("fileName" to "shared.rasb", "content" to sharedText),
                        notifyImmediately
                    )
                    intent.action = null
                    return
                }
            }
        }

        if (fileUri != null) {
            val payload = readUriPayload(fileUri)
            if (payload != null) {
                deliverPayload(payload, notifyImmediately)
            }
            intent.data = null
            intent.action = null
        }
    }

    private fun deliverPayload(payload: Map<String, String>, notifyImmediately: Boolean) {
        val channel = methodChannel
        if (notifyImmediately && channel != null) {
            channel.invokeMethod("onRasbFileOpened", payload)
        } else {
            pendingPayload = payload
        }
    }

    private fun readUriPayload(uri: Uri): Map<String, String>? {
        return try {
            if ((uri.scheme == "https" || uri.scheme == "http") && uri.toString().contains("sync=")) {
                return mapOf("fileName" to "1-Tap Sync Link", "content" to uri.toString())
            }
            val fileName = resolveDisplayName(uri) ?: "expense.rasb"
            val inputStream = contentResolver.openInputStream(uri) ?: return null
            val content = inputStream.use { stream ->
                BufferedReader(InputStreamReader(stream, Charsets.UTF_8)).readText()
            }
            if (content.isBlank()) null else mapOf("fileName" to fileName, "content" to content)
        } catch (e: Exception) {
            null
        }
    }

    private fun resolveDisplayName(uri: Uri): String? {
        if (uri.scheme == "content") {
            var cursor: Cursor? = null
            try {
                cursor = contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
                if (cursor != null && cursor.moveToFirst()) {
                    val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (index >= 0) {
                        val name = cursor.getString(index)
                        if (!name.isNullOrBlank()) return name
                    }
                }
            } catch (_: Exception) {
            } finally {
                cursor?.close()
            }
        }
        return uri.lastPathSegment
    }
}
