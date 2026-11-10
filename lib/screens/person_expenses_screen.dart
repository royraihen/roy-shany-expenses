import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/expense.dart';
import '../providers/expense_provider.dart';
import '../services/rasb_file_service.dart';
import '../utils/formatters.dart';
import '../widgets/expense_tile.dart';

class PersonExpensesScreen extends StatelessWidget {
  final String spenderName;
  final int year;
  final int month;

  const PersonExpensesScreen({
    super.key,
    required this.spenderName,
    required this.year,
    required this.month,
  });

  bool get _isRoy =>
      spenderName.toLowerCase() == Expense.spenderRoy.toLowerCase();

  Color get _themeColor =>
      _isRoy ? const Color(0xFF2563EB) : const Color(0xFFDB2777);

  @override
  Widget build(BuildContext context) {
    final monthDate = DateTime(year, month, 1);
    final monthTitle = AppFormatters.formatMonthYear(monthDate);

    return Consumer<ExpenseProvider>(
      builder: (context, provider, _) {
        final expenses = provider.expensesForPersonInMonth(
          spenderName,
          year,
          month,
        );
        final total = provider.personTotalForMonth(spenderName, year, month);
        final royCardTotal = expenses
            .where(
              (e) =>
                  e.creditCardUsed.toLowerCase() ==
                  Expense.cardRoy.toLowerCase(),
            )
            .fold(0.0, (sum, e) => sum + e.amount);
        final shanyCardTotal = expenses
            .where(
              (e) =>
                  e.creditCardUsed.toLowerCase() ==
                  Expense.cardShany.toLowerCase(),
            )
            .fold(0.0, (sum, e) => sum + e.amount);

        return Scaffold(
          appBar: AppBar(
            title: Text("$spenderName's Spending • $monthTitle"),
            actions: [
              if (expenses.isNotEmpty)
                IconButton(
                  tooltip:
                      "Share $spenderName's .rasb budget file for $monthTitle",
                  icon: const Icon(Icons.ios_share),
                  onPressed: () async {
                    await RasbFileService.shareMultipleExpenses(
                      expenses,
                      label: '${spenderName}_$monthTitle',
                    );
                  },
                ),
            ],
          ),
          body: Column(
            children: [
              Container(
                width: double.infinity,
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      _themeColor,
                      _themeColor.withValues(alpha: 0.8),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "$spenderName's Total ($monthTitle)",
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      AppFormatters.formatShekel(total),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: _CardBreakdownPill(
                            label: Expense.cardRoy,
                            amount: royCardTotal,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _CardBreakdownPill(
                            label: Expense.cardShany,
                            amount: shanyCardTotal,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 4,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Transactions (${expenses.length})',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: expenses.isEmpty
                    ? Center(
                        child: Text(
                          'No expenses recorded for $spenderName in $monthTitle.',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 24, top: 4),
                        itemCount: expenses.length,
                        itemBuilder: (context, index) {
                          return ExpenseTile(
                            expense: expenses[index],
                            showSpenderBadge: false,
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CardBreakdownPill extends StatelessWidget {
  final String label;
  final double amount;

  const _CardBreakdownPill({
    required this.label,
    required this.amount,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            AppFormatters.formatShekel(amount),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}
