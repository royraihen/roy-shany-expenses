import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/expense.dart';
import '../providers/expense_provider.dart';
import '../services/rasb_file_service.dart';
import '../utils/formatters.dart';
import '../widgets/expense_tile.dart';
import '../widgets/pairing_dialog.dart';
import 'add_expense_screen.dart';
import 'history_screen.dart';
import 'person_expenses_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _promptedPairing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      RasbFileService.initialize(onRasbOpened: _handleIncomingRasbFile);
    });
  }

  Future<void> _handleIncomingRasbFile(RasbPayload payload) async {
    if (!mounted) return;
    final provider = context.read<ExpenseProvider>();

    try {
      final result = await provider.importFromJsonString(payload.content);
      if (!mounted) return;

      await showDialog<void>(
        context: context,
        builder: (ctx) {
          final hasNew = result.importedCount > 0;
          return AlertDialog(
            title: Row(
              children: [
                Icon(
                  hasNew ? Icons.check_circle : Icons.info_outline,
                  color: hasNew ? Colors.green.shade700 : Colors.blueGrey,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    hasNew
                        ? 'Synced .rasb File!'
                        : 'Already Synced (.rasb)',
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'File: ${payload.fileName}',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 10),
                if (hasNew) ...[
                  Text(
                    'Imported ${result.importedCount} new expense${result.importedCount == 1 ? '' : 's'}:',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  ...result.importedExpenses.take(5).map(
                        (e) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            '• ${e.spenderName}: ${AppFormatters.formatShekel(e.amount)} — ${e.reason} (${e.creditCardUsed})',
                            style: const TextStyle(fontSize: 13.5),
                          ),
                        ),
                      ),
                  if (result.importedExpenses.length > 5)
                    Text(
                      '...and ${result.importedExpenses.length - 5} more.',
                      style: const TextStyle(fontSize: 12.5),
                    ),
                ] else
                  Text(
                    'All ${result.duplicateCount} expense${result.duplicateCount == 1 ? '' : 's'} in this .rasb file already exist in your local database.',
                  ),
              ],
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Great'),
              ),
            ],
          );
        },
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not parse .rasb file (${payload.fileName}): $e'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _triggerOneTapSync(BuildContext context) async {
    final provider = context.read<ExpenseProvider>();
    if (!provider.isPaired) {
      await PairingDialog.show(context);
      return;
    }
    final added = await provider.syncWithCloudSilently();
    if (!context.mounted) return;

    final msg = added > 0
        ? 'Synced $added new expense${added == 1 ? '' : 's'}!'
        : 'Everything is synced and up to date!';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.green.shade700,
      ),
    );
  }

  Future<void> _confirmAndClearAllBothSides(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.delete_forever, color: Colors.red),
            SizedBox(width: 8),
            Expanded(child: Text('Clear All (Both Phones)?')),
          ],
        ),
        content: const Text(
          'This will permanently remove ALL expenses from both your Android phone and Shany\'s iPhone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete All on Both'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      await context.read<ExpenseProvider>().clearAllExpensesFromBothSides();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Cleared all expenses from both phones!',
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  void _openPersonDetails(BuildContext context, String spenderName) {
    final now = context.read<ExpenseProvider>().now;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PersonExpensesScreen(
          spenderName: spenderName,
          year: now.year,
          month: now.month,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ExpenseProvider>(
      builder: (context, provider, _) {
        if (!provider.isLoading && !provider.isPaired && !_promptedPairing) {
          _promptedPairing = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              PairingDialog.show(context, barrierDismissible: false);
            }
          });
        }

        final bannerMsg = provider.consumeNotificationBanner();
        if (bannerMsg != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Row(
                    children: [
                      const Icon(
                        Icons.notifications_active,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(bannerMsg)),
                    ],
                  ),
                  behavior: SnackBarBehavior.floating,
                  duration: const Duration(seconds: 5),
                  backgroundColor: const Color(0xFF0F766E),
                ),
              );
            }
          });
        }

        final now = provider.now;
        final currentMonthTitle = AppFormatters.formatMonthYear(now);
        final totalSpend = provider.currentMonthTotal;
        final roySpend = provider.royCurrentMonthTotal;
        final shanySpend = provider.shanyCurrentMonthTotal;
        final royCardSpend = provider.royCardCurrentMonthTotal;
        final shanyCardSpend = provider.shanyCardCurrentMonthTotal;
        final currentExpenses = provider.currentMonthExpenses;

        final maxPersonSpend = math.max(roySpend, shanySpend);
        final royRatio = maxPersonSpend > 0 ? (roySpend / maxPersonSpend) : 0.0;
        final shanyRatio =
            maxPersonSpend > 0 ? (shanySpend / maxPersonSpend) : 0.0;

        final roySharePct =
            totalSpend > 0 ? ((roySpend / totalSpend) * 100).round() : 0;
        final shanySharePct =
            totalSpend > 0 ? ((shanySpend / totalSpend) * 100).round() : 0;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Roy & Shany Expenses'),
            actions: [
              TextButton.icon(
                onPressed: () => _triggerOneTapSync(context),
                icon: const Icon(Icons.cloud_sync_outlined, size: 20),
                label: const Text(
                  'Sync Now',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                tooltip: 'Pairing Password (P2P Encryption)',
                icon: Icon(
                  provider.isPaired ? Icons.vpn_key : Icons.vpn_key_off_outlined,
                  color: provider.isPaired
                      ? const Color(0xFF0F766E)
                      : Colors.orange.shade700,
                ),
                onPressed: () => PairingDialog.show(context),
              ),
              IconButton(
                tooltip: 'All-Time History',
                icon: const Icon(Icons.history),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const HistoryScreen()),
                  );
                },
              ),
              if (!kIsWeb)
                IconButton(
                  tooltip: 'Clear All Expenses (Both Phones)',
                  icon: const Icon(
                    Icons.delete_forever_outlined,
                    color: Colors.redAccent,
                  ),
                  onPressed: () => _confirmAndClearAllBothSides(context),
                ),
            ],
          ),
          body: provider.isLoading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: provider.loadExpenses,
                  child: ListView(
                    padding: const EdgeInsets.only(bottom: 96),
                    children: [
                      // Total Current Month Spend Hero Card
                      Container(
                        margin: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                        padding: const EdgeInsets.all(22),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF0F766E), Color(0xFF115E59)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF0F766E)
                                  .withValues(alpha: 0.22),
                              blurRadius: 14,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '$currentMonthTitle Total Spending',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.16),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    '${currentExpenses.length} items',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              AppFormatters.formatShekel(totalSpend),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 36,
                                fontWeight: FontWeight.bold,
                                letterSpacing: -0.5,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: FilledButton.tonalIcon(
                                    style: FilledButton.styleFrom(
                                      backgroundColor:
                                          Colors.white.withValues(alpha: 0.18),
                                      foregroundColor: Colors.white,
                                    ),
                                    onPressed: () => _triggerOneTapSync(context),
                                    icon: const Icon(
                                      Icons.sync,
                                      size: 18,
                                    ),
                                    label: const Text('Sync Now'),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: FilledButton.tonalIcon(
                                    style: FilledButton.styleFrom(
                                      backgroundColor:
                                          Colors.white.withValues(alpha: 0.18),
                                      foregroundColor: Colors.white,
                                    ),
                                    onPressed: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => const HistoryScreen(),
                                        ),
                                      );
                                    },
                                    icon: const Icon(
                                      Icons.calendar_month_outlined,
                                      size: 18,
                                    ),
                                    label: const Text('History'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      // Interactive Visual Bars Section (Roy vs Shany)
                      Container(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 6,
                        ),
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Monthly Spending by Person',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  'Tap a bar for details',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),

                            // Roy's Interactive Bar
                            _InteractiveSpenderBar(
                              name: Expense.spenderRoy,
                              amount: roySpend,
                              fillRatio: royRatio,
                              sharePercentage: roySharePct,
                              color: const Color(0xFF2563EB),
                              onTap: () => _openPersonDetails(
                                context,
                                Expense.spenderRoy,
                              ),
                            ),
                            const SizedBox(height: 16),

                            // Shany's Interactive Bar
                            _InteractiveSpenderBar(
                              name: Expense.spenderShany,
                              amount: shanySpend,
                              fillRatio: shanyRatio,
                              sharePercentage: shanySharePct,
                              color: const Color(0xFFDB2777),
                              onTap: () => _openPersonDetails(
                                context,
                                Expense.spenderShany,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Credit Card Breakdown & Smart Split Summary
                      Container(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 6,
                        ),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Credit Cards & Balance Summary',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF334155),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: _CardTotalChip(
                                    cardName: Expense.cardRoy,
                                    amount: royCardSpend,
                                    color: Colors.blueGrey.shade700,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _CardTotalChip(
                                    cardName: Expense.cardShany,
                                    amount: shanyCardSpend,
                                    color: Colors.purple.shade700,
                                  ),
                                ),
                              ],
                            ),
                            if (totalSpend > 0) ...[
                              const SizedBox(height: 10),
                              _BalanceInsightBanner(
                                roySpend: roySpend,
                                shanySpend: shanySpend,
                              ),
                            ],
                          ],
                        ),
                      ),

                      // Recent Current Month Expenses Header
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 16, 12, 4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '$currentMonthTitle Expenses',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (currentExpenses.isNotEmpty)
                              TextButton.icon(
                                onPressed: () async {
                                  await RasbFileService.shareMultipleExpenses(
                                    currentExpenses,
                                    label: currentMonthTitle,
                                  );
                                },
                                icon: const Icon(Icons.ios_share, size: 16),
                                label: const Text('Share Month .rasb'),
                              ),
                          ],
                        ),
                      ),

                      if (currentExpenses.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 32,
                          ),
                          child: Column(
                            children: [
                              Icon(
                                Icons.receipt_long_outlined,
                                size: 48,
                                color: Colors.grey.shade400,
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'No expenses recorded for $currentMonthTitle yet.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 15,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Tap "+ Add Expense" to save & share a .rasb file, or tap any .rasb file in WhatsApp to auto-import!',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        ...currentExpenses.map(
                          (expense) => ExpenseTile(expense: expense),
                        ),
                    ],
                  ),
                ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AddExpenseScreen()),
              );
            },
            icon: const Icon(Icons.add),
            label: const Text(
              'Add Expense',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        );
      },
    );
  }
}

class _InteractiveSpenderBar extends StatelessWidget {
  final String name;
  final double amount;
  final double fillRatio;
  final int sharePercentage;
  final Color color;
  final VoidCallback onTap;

  const _InteractiveSpenderBar({
    required this.name,
    required this.amount,
    required this.fillRatio,
    required this.sharePercentage,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final clampedRatio = fillRatio.clamp(0.0, 1.0);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 15,
                    backgroundColor: color,
                    child: Text(
                      name[0],
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      "$name's Spending",
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Text(
                    AppFormatters.formatShekel(amount),
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.chevron_right, size: 20, color: color),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  height: 18,
                  width: double.infinity,
                  child: Stack(
                    children: [
                      Container(
                        color: color.withValues(alpha: 0.12),
                      ),
                      FractionallySizedBox(
                        widthFactor: clampedRatio == 0 ? 0.02 : clampedRatio,
                        child: Container(
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '$sharePercentage% of monthly total',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade700,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    "View $name's list",
                    style: TextStyle(
                      fontSize: 12,
                      color: color,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CardTotalChip extends StatelessWidget {
  final String cardName;
  final double amount;
  final Color color;

  const _CardTotalChip({
    required this.cardName,
    required this.amount,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.credit_card, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  cardName,
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
      ),
    );
  }
}

class _BalanceInsightBanner extends StatelessWidget {
  final double roySpend;
  final double shanySpend;

  const _BalanceInsightBanner({
    required this.roySpend,
    required this.shanySpend,
  });

  @override
  Widget build(BuildContext context) {
    final diff = (roySpend - shanySpend).abs();
    final halfDiff = diff / 2.0;

    String text;
    if (diff < 0.01) {
      text = 'Roy and Shany are completely even this month!';
    } else if (roySpend > shanySpend) {
      text =
          'Roy spent ${AppFormatters.formatShekel(diff)} more • 50/50 balance: ${AppFormatters.formatShekel(halfDiff)}';
    } else {
      text =
          'Shany spent ${AppFormatters.formatShekel(diff)} more • 50/50 balance: ${AppFormatters.formatShekel(halfDiff)}';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0F766E).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.balance,
            size: 16,
            color: Color(0xFF0F766E),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFF0F766E),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
