import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'package:share_plus/share_plus.dart';
import 'package:web/web.dart' as web;

const String _storageKey = 'roy_shany_expenses_v1';

Future<String?> loadWebStorageExpensesJson() async {
  return web.window.localStorage.getItem(_storageKey);
}

Future<void> saveWebStorageExpensesJson(String jsonStr) async {
  web.window.localStorage.setItem(_storageKey, jsonStr);
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
    // Fallback to sharing the text if file sharing is blocked by the browser
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
    ..accept = '.rasb,.json,application/json,application/octet-stream,text/plain,*/*';

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
