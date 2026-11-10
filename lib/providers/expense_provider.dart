import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/expense.dart';
import '../services/database_helper.dart';

class MonthSummary {
  final int year;
  final int month;
  final double totalAmount;
  final double royTotal;
  final double shanyTotal;
  final int transactionCount;

  const MonthSummary({
    required this.year,
    required this.month,
    required this.totalAmount,
    required this.royTotal,
    required this.shanyTotal,
    required this.transactionCount,
  });

  DateTime get monthDate => DateTime(year, month, 1);
}

class SyncResult {
  final int importedCount;
  final int duplicateCount;
  final List<Expense> importedExpenses;

  const SyncResult({
    required this.importedCount,
    required this.duplicateCount,
    this.importedExpenses = const [],
  });
}

class ExpenseProvider extends ChangeNotifier {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  List<Expense> _allExpenses = [];
  bool _isLoading = true;

  List<Expense> get allExpenses => List.unmodifiable(_allExpenses);
  bool get isLoading => _isLoading;

  DateTime get now => DateTime.now();

  /// Loads all expenses from SQLite and notifies listeners.
  Future<void> loadExpenses() async {
    _isLoading = true;
    notifyListeners();

    try {
      _allExpenses = await _dbHelper.getAllExpenses();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Adds a new expense to the local SQLite database and refreshes state.
  Future<bool> addExpense(Expense expense) async {
    final inserted = await _dbHelper.insertExpense(expense);
    if (inserted) {
      await loadExpenses();
    }
    return inserted;
  }

  /// Deletes an expense by ID and refreshes state.
  Future<void> deleteExpense(String id) async {
    await _dbHelper.deleteExpense(id);
    await loadExpenses();
  }

  /// Imports one or multiple expenses from a JSON / .rasb string (checking for existing IDs).
  Future<SyncResult> importFromJsonString(String rawJson) async {
    final parsedExpenses = Expense.parseFlexibleJson(rawJson);
    int importedCount = 0;
    int duplicateCount = 0;
    final List<Expense> newlyImported = [];

    for (final expense in parsedExpenses) {
      final exists = await _dbHelper.expenseExists(expense.id);
      if (exists) {
        duplicateCount++;
      } else {
        await _dbHelper.insertExpense(expense);
        importedCount++;
        newlyImported.add(expense);
      }
    }

    if (importedCount > 0) {
      await loadExpenses();
    }

    return SyncResult(
      importedCount: importedCount,
      duplicateCount: duplicateCount,
      importedExpenses: newlyImported,
    );
  }

  /// Exports a list of expenses as a compact JSON array string for bulk syncing.
  String exportExpensesToJson(List<Expense> expenses) {
    return json.encode(expenses.map((e) => e.toMap()).toList());
  }

  /// Returns expenses for a given [year] and [month].
  List<Expense> expensesForMonth(int year, int month) {
    return _allExpenses
        .where((e) => e.timestamp.year == year && e.timestamp.month == month)
        .toList();
  }

  /// Returns current month's expenses.
  List<Expense> get currentMonthExpenses {
    final current = now;
    return expensesForMonth(current.year, current.month);
  }

  /// Returns expenses for a given person in a specific month.
  List<Expense> expensesForPersonInMonth(
    String spenderName,
    int year,
    int month,
  ) {
    return _allExpenses
        .where(
          (e) =>
              e.spenderName.toLowerCase() == spenderName.toLowerCase() &&
              e.timestamp.year == year &&
              e.timestamp.month == month,
        )
        .toList();
  }

  /// Total spending in a specific month.
  double totalForMonth(int year, int month) {
    return expensesForMonth(year, month)
        .fold(0.0, (sum, item) => sum + item.amount);
  }

  /// Person's total spending in a specific month.
  double personTotalForMonth(String spenderName, int year, int month) {
    return expensesForPersonInMonth(spenderName, year, month)
        .fold(0.0, (sum, item) => sum + item.amount);
  }

  /// Card total in a specific month.
  double cardTotalForMonth(String cardName, int year, int month) {
    return expensesForMonth(year, month)
        .where((e) => e.creditCardUsed.toLowerCase() == cardName.toLowerCase())
        .fold(0.0, (sum, item) => sum + item.amount);
  }

  double get currentMonthTotal => totalForMonth(now.year, now.month);

  double get royCurrentMonthTotal =>
      personTotalForMonth(Expense.spenderRoy, now.year, now.month);

  double get shanyCurrentMonthTotal =>
      personTotalForMonth(Expense.spenderShany, now.year, now.month);

  double get royCardCurrentMonthTotal =>
      cardTotalForMonth(Expense.cardRoy, now.year, now.month);

  double get shanyCardCurrentMonthTotal =>
      cardTotalForMonth(Expense.cardShany, now.year, now.month);

  /// Generates a chronological list of all months that have expenses (plus the current month).
  List<MonthSummary> get allMonthSummaries {
    final Map<String, List<Expense>> grouped = {};
    final current = now;
    final currentKey =
        '${current.year}-${current.month.toString().padLeft(2, '0')}';
    grouped[currentKey] = [];

    for (final expense in _allExpenses) {
      final key =
          '${expense.timestamp.year}-${expense.timestamp.month.toString().padLeft(2, '0')}';
      grouped.putIfAbsent(key, () => []).add(expense);
    }

    final List<MonthSummary> summaries = grouped.entries.map((entry) {
      final parts = entry.key.split('-');
      final year = int.parse(parts[0]);
      final month = int.parse(parts[1]);
      final items = entry.value;

      double total = 0;
      double roy = 0;
      double shany = 0;
      for (final e in items) {
        total += e.amount;
        if (e.spenderName.toLowerCase() == Expense.spenderRoy.toLowerCase()) {
          roy += e.amount;
        } else if (e.spenderName.toLowerCase() ==
            Expense.spenderShany.toLowerCase()) {
          shany += e.amount;
        }
      }

      return MonthSummary(
        year: year,
        month: month,
        totalAmount: total,
        royTotal: roy,
        shanyTotal: shany,
        transactionCount: items.length,
      );
    }).toList();

    summaries.sort((a, b) {
      final yearCmp = b.year.compareTo(a.year);
      if (yearCmp != 0) return yearCmp;
      return b.month.compareTo(a.month);
    });

    return summaries;
  }
}
