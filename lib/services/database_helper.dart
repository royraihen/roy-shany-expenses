import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/expense.dart';
import 'platform_helper.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._internal();
  static Database? _database;

  DatabaseHelper._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'roy_shany_expenses.db');

    return openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE expenses (
            id TEXT PRIMARY KEY,
            spenderName TEXT NOT NULL,
            amount REAL NOT NULL,
            timestamp TEXT NOT NULL,
            reason TEXT NOT NULL,
            creditCardUsed TEXT NOT NULL
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_expenses_timestamp ON expenses(timestamp)',
        );
        await db.execute(
          'CREATE INDEX idx_expenses_spender ON expenses(spenderName)',
        );
      },
    );
  }

  Future<List<Expense>> _getWebExpenses() async {
    final raw = await loadWebStorageExpensesJson();
    if (raw == null || raw.trim().isEmpty) return [];
    try {
      final decoded = json.decode(raw) as List<dynamic>;
      final list = decoded
          .whereType<Map<String, dynamic>>()
          .map(Expense.fromMap)
          .toList();
      list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return list;
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveWebExpenses(List<Expense> expenses) async {
    expenses.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final encoded = json.encode(expenses.map((e) => e.toMap()).toList());
    await saveWebStorageExpensesJson(encoded);
  }

  /// Checks if an expense with [id] already exists in the local database.
  Future<bool> expenseExists(String id) async {
    if (kIsWeb) {
      final list = await _getWebExpenses();
      return list.any((e) => e.id == id);
    }
    final db = await database;
    final result = await db.query(
      'expenses',
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return result.isNotEmpty;
  }

  /// Inserts an expense if its ID does not already exist.
  /// Returns true if inserted, false if it was a duplicate.
  Future<bool> insertExpense(Expense expense) async {
    if (await expenseExists(expense.id)) {
      return false;
    }
    if (kIsWeb) {
      final list = await _getWebExpenses();
      list.add(expense);
      await _saveWebExpenses(list);
      return true;
    }
    final db = await database;
    await db.insert(
      'expenses',
      expense.toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    return true;
  }

  /// Queries all expenses for a specific [year] and [month] (1-12), ordered newest first.
  Future<List<Expense>> getExpensesByMonth(int year, int month) async {
    if (kIsWeb) {
      final list = await _getWebExpenses();
      return list
          .where((e) => e.timestamp.year == year && e.timestamp.month == month)
          .toList();
    }
    final db = await database;
    final startOfMonth = DateTime(year, month, 1).toIso8601String();
    final startOfNextMonth = DateTime(year, month + 1, 1).toIso8601String();

    final maps = await db.query(
      'expenses',
      where: 'timestamp >= ? AND timestamp < ?',
      whereArgs: [startOfMonth, startOfNextMonth],
      orderBy: 'timestamp DESC',
    );
    return maps.map(Expense.fromMap).toList();
  }

  /// Queries expenses for a specific [spenderName] in a given [year] and [month].
  Future<List<Expense>> getExpensesByPersonAndMonth(
    String spenderName,
    int year,
    int month,
  ) async {
    if (kIsWeb) {
      final list = await _getWebExpenses();
      return list
          .where(
            (e) =>
                e.spenderName.toLowerCase() == spenderName.toLowerCase() &&
                e.timestamp.year == year &&
                e.timestamp.month == month,
          )
          .toList();
    }
    final db = await database;
    final startOfMonth = DateTime(year, month, 1).toIso8601String();
    final startOfNextMonth = DateTime(year, month + 1, 1).toIso8601String();

    final maps = await db.query(
      'expenses',
      where: 'spenderName = ? AND timestamp >= ? AND timestamp < ?',
      whereArgs: [spenderName, startOfMonth, startOfNextMonth],
      orderBy: 'timestamp DESC',
    );
    return maps.map(Expense.fromMap).toList();
  }

  /// Queries all expenses for a specific [spenderName] across all time.
  Future<List<Expense>> getExpensesByPerson(String spenderName) async {
    if (kIsWeb) {
      final list = await _getWebExpenses();
      return list
          .where((e) => e.spenderName.toLowerCase() == spenderName.toLowerCase())
          .toList();
    }
    final db = await database;
    final maps = await db.query(
      'expenses',
      where: 'spenderName = ?',
      whereArgs: [spenderName],
      orderBy: 'timestamp DESC',
    );
    return maps.map(Expense.fromMap).toList();
  }

  /// Queries all expenses across all time, ordered newest first.
  Future<List<Expense>> getAllExpenses() async {
    if (kIsWeb) {
      return _getWebExpenses();
    }
    final db = await database;
    final maps = await db.query('expenses', orderBy: 'timestamp DESC');
    return maps.map(Expense.fromMap).toList();
  }

  /// Deletes an expense by ID.
  Future<void> deleteExpense(String id) async {
    if (kIsWeb) {
      final list = await _getWebExpenses();
      list.removeWhere((e) => e.id == id);
      await _saveWebExpenses(list);
      return;
    }
    final db = await database;
    await db.delete('expenses', where: 'id = ?', whereArgs: [id]);
  }

  /// Deletes all expenses from the local database.
  Future<void> deleteAllExpenses() async {
    if (kIsWeb) {
      await _saveWebExpenses([]);
      return;
    }
    final db = await database;
    await db.delete('expenses');
  }
}
