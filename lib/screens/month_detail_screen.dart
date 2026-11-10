import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/expense.dart';
import '../providers/expense_provider.dart';
import '../services/rasb_file_service.dart';
import '../utils/formatters.dart';
import '../widgets/expense_tile.dart';

class MonthDetailScreen extends StatelessWidget {
  final int year;
  final int month;

  const MonthDetailScreen({
    super.key,
    required this.year,
    required this.month,
  });

  @override
  Widget build(BuildContext context) {
    final monthDate = DateTime(year, month, 1);
    final monthTitle = AppFormatters.formatMonthYear(monthDate);

    return Consumer<ExpenseProvider>(
      builder: (context, provider, _) {
        final allMonthExpenses = provider.expensesForMonth(year, month);
        final royExpenses = provider.expensesForPersonInMonth(
          Expense.spenderRoy,
          year,
          month,
        );
        final shanyExpenses = provider.expensesForPersonInMonth(
          Expense.spenderShany,
          year,
          month,
        );

        final total = provider.totalForMonth(year, month);
        final royTotal = provider.personTotalForMonth(
          Expense.spenderRoy,
          year,
          month,
        );
        final shanyTotal = provider.personTotalForMonth(
          Expense.spenderShany,
          year,
          month,
        );
        final royCardTotal = provider.cardTotalForMonth(
          Expense.cardRoy,
          year,
          month,
        );
        final shanyCardTotal = provider.cardTotalForMonth(
          Expense.cardShany,
          year,
          month,
        );

        return DefaultTabController(
          length: 2,
          child: Scaffold(
            appBar: AppBar(
              title: Text(monthTitle),
              actions: [
                if (allMonthExpenses.isNotEmpty)
                  IconButton(
                    tooltip: 'Share all $monthTitle expenses as .rasb file',
                    icon: const Icon(Icons.ios_share),
                    onPressed: () async {
                      await RasbFileService.shareMultipleExpenses(
                        allMonthExpenses,
                        label: monthTitle,
                      );
                    },
                  ),
              ],
              bottom: TabBar(
                tabs: [
                  Tab(
                    text:
                        "Roy (${royExpenses.length}) • ${AppFormatters.formatShekel(royTotal, compactIfWhole: true)}",
                  ),
                  Tab(
                    text:
                        "Shany (${shanyExpenses.length}) • ${AppFormatters.formatShekel(shanyTotal, compactIfWhole: true)}",
                  ),
                ],
              ),
            ),
            body: Column(
              children: [
                // Monthly Breakdown Summary Header
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Total Month Spend',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.black54,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            AppFormatters.formatShekel(total),
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: _MiniBreakdownStat(
                              label: "Roy's Spend",
                              amount: royTotal,
                              color: const Color(0xFF2563EB),
                            ),
                          ),
                          Expanded(
                            child: _MiniBreakdownStat(
                              label: "Shany's Spend",
                              amount: shanyTotal,
                              color: const Color(0xFFDB2777),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _MiniBreakdownStat(
                              label: Expense.cardRoy,
                              amount: royCardTotal,
                              color: Colors.blueGrey.shade700,
                            ),
                          ),
                          Expanded(
                            child: _MiniBreakdownStat(
                              label: Expense.cardShany,
                              amount: shanyCardTotal,
                              color: Colors.purple.shade700,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _PersonPurchaseList(
                        spenderName: Expense.spenderRoy,
                        expenses: royExpenses,
                        monthTitle: monthTitle,
                      ),
                      _PersonPurchaseList(
                        spenderName: Expense.spenderShany,
                        expenses: shanyExpenses,
                        monthTitle: monthTitle,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MiniBreakdownStat extends StatelessWidget {
  final String label;
  final double amount;
  final Color color;

  const _MiniBreakdownStat({
    required this.label,
    required this.amount,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 28,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
              Text(
                AppFormatters.formatShekel(amount),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PersonPurchaseList extends StatelessWidget {
  final String spenderName;
  final List<Expense> expenses;
  final String monthTitle;

  const _PersonPurchaseList({
    required this.spenderName,
    required this.expenses,
    required this.monthTitle,
  });

  @override
  Widget build(BuildContext context) {
    if (expenses.isEmpty) {
      return Center(
        child: Text(
          "No purchases recorded for $spenderName in $monthTitle.",
          style: TextStyle(color: Colors.grey.shade600),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(top: 6, bottom: 24),
      itemCount: expenses.length,
      itemBuilder: (context, index) {
        return ExpenseTile(
          expense: expenses[index],
          showSpenderBadge: false,
        );
      },
    );
  }
}
