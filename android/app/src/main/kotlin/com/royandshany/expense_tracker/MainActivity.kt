package com.royandshany.expense_tracker

import android.content.Intent
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

class MainActivity : FlutterActivity() {
    private val channelName = "com.royandshany.expense_tracker/rasb"
    private var methodChannel: MethodChannel? = null
    private var pendingPayload: Map<String, String>? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleIncomingIntent(intent, notifyImmediately = false)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        methodChannel = channel

        channel.setMethodCallHandler { call, result ->
            if (call.method == "getInitialRasbContent") {
                val payload = pendingPayload
                pendingPayload = null
                result.success(payload)
            } else {
                result.notImplemented()
            }
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
