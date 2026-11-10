import 'dart:convert';

class Expense {
  static const String spenderRoy = 'Roy';
  static const String spenderShany = 'Shany';

  static const String cardRoy = "Roy's Card";
  static const String cardShany = "Shany's Card";

  final String id;
  final String spenderName;
  final double amount;
  final DateTime timestamp;
  final String reason;
  final String creditCardUsed;

  const Expense({
    required this.id,
    required this.spenderName,
    required this.amount,
    required this.timestamp,
    required this.reason,
    required this.creditCardUsed,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'spenderName': spenderName,
      'amount': amount,
      'timestamp': timestamp.toIso8601String(),
      'reason': reason,
      'creditCardUsed': creditCardUsed,
    };
  }

  factory Expense.fromMap(Map<String, dynamic> map) {
    final rawAmount = map['amount'];
    final double parsedAmount = rawAmount is num
        ? rawAmount.toDouble()
        : double.parse(rawAmount.toString());

    final rawTimestamp = map['timestamp'];
    final DateTime parsedTimestamp = rawTimestamp is int
        ? DateTime.fromMillisecondsSinceEpoch(rawTimestamp)
        : DateTime.parse(rawTimestamp.toString());

    return Expense(
      id: map['id'].toString().trim(),
      spenderName: map['spenderName'].toString().trim(),
      amount: parsedAmount,
      timestamp: parsedTimestamp,
      reason: map['reason'].toString().trim(),
      creditCardUsed: map['creditCardUsed'].toString().trim(),
    );
  }

  String toJson() => json.encode(toMap());

  factory Expense.fromJson(String source) =>
      Expense.fromMap(json.decode(source) as Map<String, dynamic>);

  /// Intelligently parses either a single JSON object, a JSON array of objects,
  /// or JSON embedded inside a chat message (e.g. forwarded from WhatsApp/SMS).
  static List<Expense> parseFlexibleJson(String rawInput) {
    final trimmed = rawInput.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Input is empty.');
    }

    // Support 1-Tap Magic Sync Links (?sync=<base64url>) directly
    if (trimmed.contains('sync=')) {
      final idx = trimmed.indexOf('sync=');
      if (idx != -1) {
        final rawParam = trimmed
            .substring(idx + 5)
            .split(RegExp(r'[\s&#]'))
            .first
            .trim();
        if (rawParam.isNotEmpty) {
          try {
            final normalized = base64Url.normalize(rawParam);
            final decodedJson = utf8.decode(base64Url.decode(normalized));
            return parseFlexibleJson(decodedJson);
          } catch (_) {
            // Fall through to normal JSON parsing if not base64url
          }
        }
      }
    }

    dynamic decoded;
    try {
      decoded = json.decode(trimmed);
    } catch (_) {
      // Try extracting a JSON array or object if surrounded by extra text
      final int firstBrace = trimmed.indexOf('{');
      final int lastBrace = trimmed.lastIndexOf('}');
      final int firstBracket = trimmed.indexOf('[');
      final int lastBracket = trimmed.lastIndexOf(']');

      if (firstBracket != -1 &&
          lastBracket > firstBracket &&
          (firstBrace == -1 || firstBracket < firstBrace)) {
        final candidate = trimmed.substring(firstBracket, lastBracket + 1);
        decoded = json.decode(candidate);
      } else if (firstBrace != -1 && lastBrace > firstBrace) {
        final candidate = trimmed.substring(firstBrace, lastBrace + 1);
        decoded = json.decode(candidate);
      } else {
        rethrow;
      }
    }

    final List<Expense> results = [];
    if (decoded is Map<String, dynamic>) {
      if (decoded.containsKey('expenses') && decoded['expenses'] is List) {
        for (final item in (decoded['expenses'] as List)) {
          if (item is Map<String, dynamic>) {
            results.add(_validateAndBuild(item));
          } else {
            throw const FormatException('Invalid item inside .rasb expenses list.');
          }
        }
      } else {
        results.add(_validateAndBuild(decoded));
      }
    } else if (decoded is List) {
      for (final item in decoded) {
        if (item is Map<String, dynamic>) {
          results.add(_validateAndBuild(item));
        } else {
          throw const FormatException('Invalid item inside JSON list.');
        }
      }
    } else {
      throw const FormatException('Unsupported JSON format.');
    }

    if (results.isEmpty) {
      throw const FormatException('No expenses found in the provided JSON.');
    }
    return results;
  }

  static Expense _validateAndBuild(Map<String, dynamic> map) {
    if (!map.containsKey('id') ||
        !map.containsKey('spenderName') ||
        !map.containsKey('amount') ||
        !map.containsKey('timestamp') ||
        !map.containsKey('reason') ||
        !map.containsKey('creditCardUsed')) {
      throw const FormatException(
        'Missing required fields (id, spenderName, amount, timestamp, reason, creditCardUsed).',
      );
    }
    final expense = Expense.fromMap(map);
    if (expense.id.isEmpty) {
      throw const FormatException('Expense ID cannot be empty.');
    }
    if (expense.reason.isEmpty) {
      throw const FormatException('Expense reason cannot be empty.');
    }
    if (expense.amount <= 0 || expense.amount.isNaN) {
      throw const FormatException('Expense amount must be greater than zero.');
    }
    return expense;
  }
}
