import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import '../models/expense.dart';

class CloudSyncPayload {
  final List<Expense> expenses;
  final Set<String> deletedIds;
  final int? lastClearAllEpochMs;

  const CloudSyncPayload({
    required this.expenses,
    required this.deletedIds,
    this.lastClearAllEpochMs,
  });
}

class AutoSyncService {
  static const String webAppBaseUrl =
      'https://royraihen.github.io/roy-shany-expenses/';

  /// Derives a private, unguessable channel topic from the shared secret password.
  static String deriveTopic(String pairingPassword) {
    final normalized = pairingPassword.trim();
    final digest = sha256
        .convert(utf8.encode('roy_shany_p2p_channel_v2::$normalized'))
        .toString();
    return 'rs_p2p_${digest.substring(0, 40)}';
  }

  static String _ntfyUrlForPassword(String pairingPassword) {
    final topic = deriveTopic(pairingPassword);
    return 'https://ntfy.sh/$topic';
  }

  /// Encrypts and authenticates a JSON string using the shared [pairingPassword].
  static String encryptPayload(String plainJson, String pairingPassword) {
    final pwdBytes = utf8.encode('roy_shany_p2p_key_v2::${pairingPassword.trim()}');
    final encKey = sha256.convert(pwdBytes).bytes;
    final macKey = Hmac(sha256, encKey).convert(utf8.encode('mac_subkey')).bytes;

    final rng = Random.secure();
    final iv = Uint8List.fromList(List<int>.generate(16, (_) => rng.nextInt(256)));
    final plainBytes = utf8.encode(plainJson);
    final cipherBytes = _xorKeystream(plainBytes, encKey, iv);

    final ivB64 = base64Url.encode(iv);
    final ctB64 = base64Url.encode(cipherBytes);
    final mac = Hmac(sha256, macKey)
        .convert(utf8.encode('$ivB64.$ctB64'))
        .toString();

    return json.encode({
      'v': 2,
      'iv': ivB64,
      'ct': ctB64,
      'mac': mac,
    });
  }

  /// Verifies HMAC and decrypts an encrypted payload using the shared [pairingPassword].
  static String? decryptPayload(String rawEnvelopeJson, String pairingPassword) {
    try {
      final map = json.decode(rawEnvelopeJson);
      if (map is! Map<String, dynamic>) return null;
      if (map['v'] != 2) return null;

      final ivB64 = map['iv']?.toString();
      final ctB64 = map['ct']?.toString();
      final macHex = map['mac']?.toString();
      if (ivB64 == null || ctB64 == null || macHex == null) return null;

      final pwdBytes =
          utf8.encode('roy_shany_p2p_key_v2::${pairingPassword.trim()}');
      final encKey = sha256.convert(pwdBytes).bytes;
      final macKey =
          Hmac(sha256, encKey).convert(utf8.encode('mac_subkey')).bytes;

      final expectedMac = Hmac(sha256, macKey)
          .convert(utf8.encode('$ivB64.$ctB64'))
          .toString();
      if (expectedMac != macHex) return null;

      final iv = base64Url.decode(base64Url.normalize(ivB64));
      final cipherBytes = base64Url.decode(base64Url.normalize(ctB64));
      final plainBytes = _xorKeystream(cipherBytes, encKey, iv);
      return utf8.decode(plainBytes);
    } catch (_) {
      return null;
    }
  }

  static Uint8List _xorKeystream(
    List<int> input,
    List<int> key,
    List<int> iv,
  ) {
    final out = Uint8List(input.length);
    final hmac = Hmac(sha256, key);
    int blockIndex = 0;
    List<int> keystreamBlock = const [];
    int ksOffset = 0;

    for (int i = 0; i < input.length; i++) {
      if (ksOffset >= keystreamBlock.length) {
        final counterBytes = <int>[
          ...iv,
          (blockIndex >> 24) & 0xFF,
          (blockIndex >> 16) & 0xFF,
          (blockIndex >> 8) & 0xFF,
          blockIndex & 0xFF,
        ];
        keystreamBlock = hmac.convert(counterBytes).bytes;
        blockIndex++;
        ksOffset = 0;
      }
      out[i] = input[i] ^ keystreamBlock[ksOffset];
      ksOffset++;
    }
    return out;
  }

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

  /// Broadcasts an encrypted "Clear All" command so both paired devices wipe all existing expenses.
  static Future<int> pushClearAll({
    required String? pairingPassword,
    required Iterable<String> currentIdsToWipe,
  }) async {
    final nowEpochMs = DateTime.now().millisecondsSinceEpoch;
    if (pairingPassword == null || pairingPassword.trim().isEmpty) {
      return nowEpochMs;
    }

    try {
      final plainBody = json.encode({
        'format': 'rasb_clear_all',
        'clearedAtEpochMs': nowEpochMs,
        'deletedIds': currentIdsToWipe.toList(),
      });
      final encryptedBody = encryptPayload(plainBody, pairingPassword);

      await http
          .post(
            Uri.parse(_ntfyUrlForPassword(pairingPassword)),
            headers: {'Content-Type': 'application/json'},
            body: encryptedBody,
          )
          .timeout(const Duration(seconds: 8));
    } catch (_) {}
    return nowEpochMs;
  }

  /// Pushes encrypted expenses and/or deleted IDs in compact chunks (<= 6 expenses per message)
  /// so encrypted messages always stay well under ntfy.sh's 4KB inline JSON limit.
  static Future<void> pushExpenses({
    required String? pairingPassword,
    required List<Expense> expenses,
    required Set<String> deletedIds,
  }) async {
    if (pairingPassword == null || pairingPassword.trim().isEmpty) return;

    final targetUrl = _ntfyUrlForPassword(pairingPassword);

    try {
      if (expenses.isEmpty && deletedIds.isNotEmpty) {
        final plainBody = json.encode({
          'format': 'rasb_sync',
          'timestamp': DateTime.now().toIso8601String(),
          'expenses': const [],
          'deletedIds': deletedIds.toList(),
        });
        final encryptedBody = encryptPayload(plainBody, pairingPassword);
        await http
            .post(
              Uri.parse(targetUrl),
              headers: {'Content-Type': 'application/json'},
              body: encryptedBody,
            )
            .timeout(const Duration(seconds: 8));
        return;
      }

      const int chunkSize = 6;
      for (int i = 0; i < expenses.length; i += chunkSize) {
        final chunk = expenses.skip(i).take(chunkSize).toList();
        final plainBody = json.encode({
          'format': 'rasb_sync',
          'timestamp': DateTime.now().toIso8601String(),
          'expenses': chunk.map((e) => e.toMap()).toList(),
          'deletedIds': i == 0 ? deletedIds.toList() : const [],
        });
        final encryptedBody = encryptPayload(plainBody, pairingPassword);

        await http
            .post(
              Uri.parse(targetUrl),
              headers: {'Content-Type': 'application/json'},
              body: encryptedBody,
            )
            .timeout(const Duration(seconds: 8));
      }
    } catch (_) {
      // Offline or network timeout; local DB still holds all data and will sync next time.
    }
  }

  /// Pulls all cached messages from the private channel, decrypts them with [pairingPassword],
  /// and merges expenses & deletions.
  static Future<CloudSyncPayload?> pullFromCloud({
    required String? pairingPassword,
  }) async {
    if (pairingPassword == null || pairingPassword.trim().isEmpty) return null;

    final targetUrl = _ntfyUrlForPassword(pairingPassword);

    try {
      final response = await http
          .get(Uri.parse('$targetUrl/json?poll=1&since=all'))
          .timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) return null;
      final rawText = utf8.decode(response.bodyBytes).trim();
      if (rawText.isEmpty) {
        return const CloudSyncPayload(expenses: [], deletedIds: {});
      }

      final Map<String, Expense> mergedExpenses = {};
      final Set<String> deletedIds = {};
      int? lastClearAllEpochMs;

      final lines = const LineSplitter().convert(rawText);
      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        try {
          final envelope = json.decode(line) as Map<String, dynamic>;
          if (envelope['event'] != 'message') continue;
          final encryptedMsgStr = envelope['message']?.toString();
          if (encryptedMsgStr == null || encryptedMsgStr.isEmpty) continue;

          final decryptedStr = decryptPayload(encryptedMsgStr, pairingPassword);
          if (decryptedStr == null) continue;

          final decodedMsg = json.decode(decryptedStr);
          if (decodedMsg is Map<String, dynamic>) {
            if (decodedMsg['format'] == 'rasb_clear_all') {
              deletedIds.addAll(mergedExpenses.keys);
              if (decodedMsg['deletedIds'] is List) {
                for (final id in (decodedMsg['deletedIds'] as List)) {
                  deletedIds.add(id.toString());
                }
              }
              mergedExpenses.clear();
              final rawEpoch = decodedMsg['clearedAtEpochMs'];
              if (rawEpoch is int) {
                lastClearAllEpochMs = rawEpoch;
              } else if (envelope['time'] is int) {
                lastClearAllEpochMs = (envelope['time'] as int) * 1000;
              }
              continue;
            }

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
        lastClearAllEpochMs: lastClearAllEpochMs,
      );
    } catch (_) {
      return null;
    }
  }
}
