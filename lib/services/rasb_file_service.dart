import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/expense.dart';
import '../utils/formatters.dart';
import 'platform_helper.dart';

class RasbPayload {
  final String fileName;
  final String content;

  const RasbPayload({
    required this.fileName,
    required this.content,
  });
}

class RasbFileService {
  static const String fileExtension = 'rasb';
  static const MethodChannel _channel = MethodChannel(
    'com.royandshany.expense_tracker/rasb',
  );

  /// Initializes listener for `.rasb` files opened while the app is running
  /// and fetches any `.rasb` file that launched the app.
  static Future<void> initialize({
    required Future<void> Function(RasbPayload payload) onRasbOpened,
  }) async {
    if (kIsWeb) return;

    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onRasbFileOpened') {
        final args = call.arguments;
        if (args is Map) {
          final fileName = (args['fileName'] ?? 'expense.rasb').toString();
          final content = (args['content'] ?? '').toString();
          if (content.trim().isNotEmpty) {
            await onRasbOpened(
              RasbPayload(fileName: fileName, content: content),
            );
          }
        }
      }
    });

    try {
      final initial = await _channel.invokeMethod<dynamic>(
        'getInitialRasbContent',
      );
      if (initial is Map) {
        final fileName = (initial['fileName'] ?? 'expense.rasb').toString();
        final content = (initial['content'] ?? '').toString();
        if (content.trim().isNotEmpty) {
          await onRasbOpened(
            RasbPayload(fileName: fileName, content: content),
          );
        }
      }
    } on MissingPluginException {
      // Ignore on platforms where the native channel is not registered
    } catch (_) {
      // Ignore initialization errors
    }
  }

  /// Creates a `.rasb` (Roy and Shany Budget) file for a single [Expense]
  /// and opens the native share sheet so it can be sent via WhatsApp, etc.
  static Future<void> shareSingleExpense(Expense expense) async {
    final safeReason = _sanitizeFileName(expense.reason);
    final safeSpender = _sanitizeFileName(expense.spenderName);
    final amountStr = expense.amount == expense.amount.roundToDouble()
        ? expense.amount.toInt().toString()
        : expense.amount.toStringAsFixed(2).replaceAll('.', '_');

    final fileName =
        '${safeSpender}_${amountStr}ILS_$safeReason.$fileExtension';

    final payloadMap = {
      'format': 'rasb',
      'version': 1,
      'app': 'Roy & Shany Budget',
      'exportedAt': DateTime.now().toIso8601String(),
      'expenses': [expense.toMap()],
    };

    final content = const JsonEncoder.withIndent('  ').convert(payloadMap);
    final subject =
        '${expense.spenderName}: ${AppFormatters.formatShekel(expense.amount)} - ${expense.reason}';

    await shareRasbBytes(
      fileName: fileName,
      content: content,
      subject: subject,
    );
  }

  /// Creates a `.rasb` (Roy and Shany Budget) file containing multiple [expenses]
  /// and opens the native share sheet.
  static Future<void> shareMultipleExpenses(
    List<Expense> expenses, {
    required String label,
  }) async {
    if (expenses.isEmpty) return;

    final safeLabel = _sanitizeFileName(label);
    final fileName = 'RoyShany_${safeLabel}_Sync.$fileExtension';

    final payloadMap = {
      'format': 'rasb',
      'version': 1,
      'app': 'Roy & Shany Budget',
      'exportedAt': DateTime.now().toIso8601String(),
      'expenses': expenses.map((e) => e.toMap()).toList(),
    };

    final content = const JsonEncoder.withIndent('  ').convert(payloadMap);
    await shareRasbBytes(
      fileName: fileName,
      content: content,
      subject: 'Roy & Shany Budget Sync ($label)',
    );
  }

  /// Allows picking a `.rasb` file directly on Web / iPhone PWA.
  static Future<RasbPayload?> pickRasbFile() async {
    final map = await pickRasbFileFromDevice();
    if (map == null) return null;
    final content = map['content'] ?? '';
    if (content.trim().isEmpty) return null;
    return RasbPayload(
      fileName: map['fileName'] ?? 'expense.rasb',
      content: content,
    );
  }

  static String _sanitizeFileName(String input) {
    final cleaned = input
        .trim()
        .replaceAll(RegExp(r'[^\w\u0590-\u05FF\-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    if (cleaned.isEmpty) return 'Expense';
    return cleaned.length > 24 ? cleaned.substring(0, 24) : cleaned;
  }
}
