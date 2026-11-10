import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/expense.dart';
import '../services/auto_sync_service.dart';
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
  final Set<String> _deletedIds = {};
  int _lastAppliedClearAllEpochMs = 0;
  bool _isLoading = true;
  bool _isSyncingCloud = false;
  Timer? _autoSyncTimer;

  ExpenseProvider() {
    _autoSyncTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => syncWithCloudSilently(),
    );
  }

  @override
  void dispose() {
    _autoSyncTimer?.cancel();
    super.dispose();
  }

  List<Expense> get allExpenses => List.unmodifiable(_allExpenses);
  bool get isLoading => _isLoading;
  bool get isSyncingCloud => _isSyncingCloud;

  DateTime get now => DateTime.now();

  /// Loads all expenses from local storage and triggers automatic background cloud sync.
  Future<void> loadExpenses({bool syncCloud = true}) async {
    try {
      _allExpenses = await _dbHelper.getAllExpenses();
    } finally {
      _isLoading = false;
      notifyListeners();
    }

    if (syncCloud) {
      unawaited(syncWithCloudSilently());
    }
  }

  /// Automatically merges expenses between Roy's Android and Shany's iPhone in the background.
  Future<int> syncWithCloudSilently() async {
    if (_isSyncingCloud) return 0;
    _isSyncingCloud = true;

    try {
      final cloudState = await AutoSyncService.pullFromCloud();
      if (cloudState == null) return 0;

      int newlyImported = 0;
      bool localChanged = false;

      // If a Clear-All command was triggered more recently than our last applied clear-all, wipe local expenses
      if (cloudState.lastClearAllEpochMs != null &&
          cloudState.lastClearAllEpochMs! > _lastAppliedClearAllEpochMs) {
        _lastAppliedClearAllEpochMs = cloudState.lastClearAllEpochMs!;
        if (_allExpenses.isNotEmpty) {
          await _dbHelper.deleteAllExpenses();
          localChanged = true;
        }
      }

      // Apply any cloud deletions locally
      for (final delId in cloudState.deletedIds) {
        _deletedIds.add(delId);
        if (await _dbHelper.expenseExists(delId)) {
          await _dbHelper.deleteExpense(delId);
          localChanged = true;
        }
      }

      // Import any cloud expenses that we don't have locally yet
      for (final remoteExpense in cloudState.expenses) {
        if (_deletedIds.contains(remoteExpense.id)) continue;
        final exists = await _dbHelper.expenseExists(remoteExpense.id);
        if (!exists) {
          await _dbHelper.insertExpense(remoteExpense);
          newlyImported++;
          localChanged = true;
        }
      }

      if (localChanged) {
        _allExpenses = await _dbHelper.getAllExpenses();
        notifyListeners();
      }

      // Check if we have local expenses that aren't in the cloud yet; if so, push only the missing ones
      final remoteIds = cloudState.expenses.map((e) => e.id).toSet();
      final unpushedExpenses = _allExpenses
          .where((local) => !remoteIds.contains(local.id))
          .toList();
      final unpushedDeletions = _deletedIds.difference(cloudState.deletedIds);

      if (unpushedExpenses.isNotEmpty || unpushedDeletions.isNotEmpty) {
        await AutoSyncService.pushExpenses(
          expenses: unpushedExpenses,
          deletedIds: unpushedDeletions,
        );
      }

      return newlyImported;
    } finally {
      _isSyncingCloud = false;
    }
  }

  /// Adds a new expense to local storage and automatically pushes to the cloud sync channel.
  Future<bool> addExpense(Expense expense) async {
    final inserted = await _dbHelper.insertExpense(expense);
    if (inserted) {
      _allExpenses = await _dbHelper.getAllExpenses();
      notifyListeners();
      unawaited(
        AutoSyncService.pushExpenses(
          expenses: [expense],
          deletedIds: const {},
        ),
      );
    }
    return inserted;
  }

  /// Deletes an expense by ID locally and broadcasts the deletion to the cloud sync channel.
  Future<void> deleteExpense(String id) async {
    _deletedIds.add(id);
    await _dbHelper.deleteExpense(id);
    _allExpenses = await _dbHelper.getAllExpenses();
    notifyListeners();
    unawaited(
      AutoSyncService.pushExpenses(
        expenses: const [],
        deletedIds: {id},
      ),
    );
  }

  /// Wipes all expenses on this device AND broadcasts a Clear-All event so the other phone wipes them too.
  Future<void> clearAllExpensesFromBothSides() async {
    final idsToWipe = _allExpenses.map((e) => e.id).toSet();
    _deletedIds.addAll(idsToWipe);
    await _dbHelper.deleteAllExpenses();
    _allExpenses = [];
    notifyListeners();

    final epochMs = await AutoSyncService.pushClearAll(
      currentIdsToWipe: _deletedIds,
    );
    _lastAppliedClearAllEpochMs = epochMs;
  }

  /// Imports one or multiple expenses from a JSON / .rasb / ?sync= string (checking for existing IDs).
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
      _allExpenses = await _dbHelper.getAllExpenses();
      notifyListeners();
      unawaited(
        AutoSyncService.pushExpenses(
          expenses: newlyImported,
          deletedIds: const {},
        ),
      );
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
