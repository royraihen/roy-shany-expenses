import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'package:share_plus/share_plus.dart';
import 'package:web/web.dart' as web;

const String _storageKey = 'roy_shany_expenses_v1';
const String _pairingKey = 'roy_shany_pairing_password_v1';

Future<String?> loadWebStorageExpensesJson() async {
  return web.window.localStorage.getItem(_storageKey);
}

Future<void> saveWebStorageExpensesJson(String jsonStr) async {
  web.window.localStorage.setItem(_storageKey, jsonStr);
}

Future<String?> loadWebPairingPassword() async {
  return web.window.localStorage.getItem(_pairingKey);
}

Future<void> saveWebPairingPassword(String password) async {
  web.window.localStorage.setItem(_pairingKey, password);
}

String? consumeInitialWebSyncParam() {
  try {
    final search = web.window.location.search;
    if (search.isEmpty || !search.contains('sync=')) return null;
    final uri = Uri.tryParse('https://example.com/$search');
    final syncVal = uri?.queryParameters['sync'];
    if (syncVal != null && syncVal.isNotEmpty) {
      web.window.history.replaceState(
        null,
        '',
        web.window.location.pathname,
      );
      return 'sync=$syncVal';
    }
  } catch (_) {}
  return null;
}

Future<void> triggerWebNotification({
  required String title,
  required String body,
}) async {
  try {
    final permission = web.Notification.permission;
    if (permission == 'granted') {
      web.Notification(
        title,
        web.NotificationOptions(
          body: body,
          icon: 'icons/Icon-192.png',
        ),
      );
    } else if (permission != 'denied') {
      final result = (await web.Notification.requestPermission().toDart).toDart;
      if (result == 'granted') {
        web.Notification(
          title,
          web.NotificationOptions(
            body: body,
            icon: 'icons/Icon-192.png',
          ),
        );
      }
    }
  } catch (_) {
    // Ignore on browsers where Notification API is restricted
  }
}

Future<void> shareRasbBytes({
  required String fileName,
  required String content,
  required String subject,
}) async {
  final bytes = utf8.encode(content);
  try {
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(
            bytes,
            name: fileName,
            mimeType: 'application/octet-stream',
          ),
        ],
        fileNameOverrides: [fileName],
        subject: subject,
      ),
    );
  } catch (_) {
    await SharePlus.instance.share(
      ShareParams(
        text: content,
        subject: subject,
      ),
    );
  }
}

Future<Map<String, String>?> pickRasbFileFromDevice() async {
  final completer = Completer<Map<String, String>?>();
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept =
        '.rasb,.json,application/json,application/octet-stream,text/plain,*/*';

  input.onchange = ((web.Event _) {
    final files = input.files;
    if (files == null || files.length == 0) {
      if (!completer.isCompleted) completer.complete(null);
      return;
    }
    final file = files.item(0);
    if (file == null) {
      if (!completer.isCompleted) completer.complete(null);
      return;
    }

    final reader = web.FileReader();
    reader.onload = ((web.Event _) {
      final result = reader.result;
      final text = (result as JSString?)?.toDart ?? '';
      if (!completer.isCompleted) {
        completer.complete({
          'fileName': file.name,
          'content': text,
        });
      }
    }).toJS;
    reader.onerror = ((web.Event _) {
      if (!completer.isCompleted) completer.complete(null);
    }).toJS;
    reader.readAsText(file);
  }).toJS;

  input.click();
  return completer.future;
}
