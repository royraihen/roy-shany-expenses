import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:expense_tracker/models/expense.dart';
import 'package:expense_tracker/utils/formatters.dart';

void main() {
  test('Expense .rasb envelope and JSON serialization with Shekel formatting work properly', () {
    final now = DateTime(2026, 11, 10, 14, 30);
    final expense = Expense(
      id: '123e4567-e89b-12d3-a456-426614174000',
      spenderName: Expense.spenderRoy,
      amount: 150.5,
      timestamp: now,
      reason: 'Groceries',
      creditCardUsed: Expense.cardRoy,
    );

    final rasbContent = json.encode({
      'format': 'rasb',
      'version': 1,
      'app': 'Roy & Shany Budget',
      'exportedAt': now.toIso8601String(),
      'expenses': [expense.toMap()],
    });

    final parsed = Expense.parseFlexibleJson(rasbContent);

    expect(parsed.length, 1);
    expect(parsed.first.id, expense.id);
    expect(parsed.first.spenderName, 'Roy');
    expect(parsed.first.amount, 150.5);
    expect(parsed.first.reason, 'Groceries');
    expect(parsed.first.creditCardUsed, "Roy's Card");

    final formatted = AppFormatters.formatShekel(expense.amount);
    expect(formatted.contains('₪'), isTrue);
  });
}
