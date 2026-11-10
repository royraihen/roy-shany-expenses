import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/expense.dart';

class CloudSyncPayload {
  final List<Expense> expenses;
  final Set<String> deletedIds;

  const CloudSyncPayload({
    required this.expenses,
    required this.deletedIds,
  });
}

class AutoSyncService {
  static const String webAppBaseUrl =
      'https://royraihen.github.io/roy-shany-expenses/';
  static const String _syncTopic = 'roy_shany_expenses_sync_v1_9f8e7d6c5b4a';
  static const String _ntfyBaseUrl = 'https://ntfy.sh/$_syncTopic';

  /// Encodes one or more expenses into a 1-tap sync URL (`?sync=...`).
  static String buildOneTapSyncUrl(List<Expense> expenses) {
    final payload = {
      'format': 'rasb',
      'version': 1,
      'expenses': expenses.map((e) => e.toMap()).toList(),
    };
    final jsonBytes = utf8.encode(json.encode(payload));
    final encoded = base64Url.encode(jsonBytes);
    return '$webAppBaseUrl?sync=$encoded';
  }

  /// Extracts and decodes expenses if [urlOrParam] contains a `?sync=...` parameter
  /// or is a raw base64url string.
  static List<Expense>? tryDecodeSyncUrlOrParam(String urlOrParam) {
    final trimmed = urlOrParam.trim();
    if (trimmed.isEmpty) return null;

    String? syncParam;
    if (trimmed.contains('sync=')) {
      final uri = Uri.tryParse(trimmed);
      syncParam = uri?.queryParameters['sync'];
      if (syncParam == null) {
        final idx = trimmed.indexOf('sync=');
        if (idx != -1) {
          syncParam = trimmed.substring(idx + 5).split('&').first;
        }
      }
    } else {
      syncParam = trimmed;
    }

    if (syncParam == null || syncParam.isEmpty) return null;

    try {
      final normalized = base64Url.normalize(syncParam);
      final decodedStr = utf8.decode(base64Url.decode(normalized));
      return Expense.parseFlexibleJson(decodedStr);
    } catch (_) {
      return null;
    }
  }

  /// Pushes the current state (expenses + deleted IDs) to the background sync channel.
  static Future<void> pushExpenses({
    required List<Expense> expenses,
    required Set<String> deletedIds,
  }) async {
    try {
      final body = json.encode({
        'format': 'rasb_sync',
        'timestamp': DateTime.now().toIso8601String(),
        'expenses': expenses.map((e) => e.toMap()).toList(),
        'deletedIds': deletedIds.toList(),
      });

      await http
          .post(
            Uri.parse(_ntfyBaseUrl),
            headers: {'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      // Offline or network timeout; local DB still holds all data and will sync next time.
    }
  }

  /// Pulls all cached messages from the background sync channel and merges expenses & deletions.
  static Future<CloudSyncPayload?> pullFromCloud() async {
    try {
      final response = await http
          .get(Uri.parse('$_ntfyBaseUrl/json?poll=1&since=all'))
          .timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) return null;
      final rawText = utf8.decode(response.bodyBytes).trim();
      if (rawText.isEmpty) {
        return const CloudSyncPayload(expenses: [], deletedIds: {});
      }

      final Map<String, Expense> mergedExpenses = {};
      final Set<String> deletedIds = {};

      final lines = const LineSplitter().convert(rawText);
      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        try {
          final envelope = json.decode(line) as Map<String, dynamic>;
          if (envelope['event'] != 'message') continue;
          final msgStr = envelope['message']?.toString();
          if (msgStr == null || msgStr.isEmpty) continue;

          final decodedMsg = json.decode(msgStr);
          if (decodedMsg is Map<String, dynamic>) {
            if (decodedMsg['deletedIds'] is List) {
              for (final id in (decodedMsg['deletedIds'] as List)) {
                deletedIds.add(id.toString());
              }
            }
            if (decodedMsg['expenses'] is List) {
              for (final item in (decodedMsg['expenses'] as List)) {
                if (item is Map<String, dynamic>) {
                  final expense = Expense.fromMap(item);
                  mergedExpenses[expense.id] = expense;
                }
              }
            } else if (decodedMsg.containsKey('id')) {
              final expense = Expense.fromMap(decodedMsg);
              mergedExpenses[expense.id] = expense;
            }
          }
        } catch (_) {
          // Ignore malformed message line
        }
      }

      // Remove any expense that was explicitly deleted
      for (final delId in deletedIds) {
        mergedExpenses.remove(delId);
      }

      return CloudSyncPayload(
        expenses: mergedExpenses.values.toList(),
        deletedIds: deletedIds,
      );
    } catch (_) {
      return null;
    }
  }
}
