import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/expense.dart';
import '../providers/expense_provider.dart';
import '../services/rasb_file_service.dart';
import '../utils/formatters.dart';

class ExpenseTile extends StatelessWidget {
  final Expense expense;
  final bool showSpenderBadge;

  const ExpenseTile({
    super.key,
    required this.expense,
    this.showSpenderBadge = true,
  });

  bool get _isRoy =>
      expense.spenderName.toLowerCase() == Expense.spenderRoy.toLowerCase();

  Color get _personColor =>
      _isRoy ? const Color(0xFF2563EB) : const Color(0xFFDB2777);

  @override
  Widget build(BuildContext context) {
    final isRoyCard =
        expense.creditCardUsed.toLowerCase() == Expense.cardRoy.toLowerCase();

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: _personColor.withValues(alpha: 0.12),
              child: Text(
                expense.spenderName.isNotEmpty
                    ? expense.spenderName[0].toUpperCase()
                    : '?',
                style: TextStyle(
                  color: _personColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          expense.reason,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        AppFormatters.formatShekel(expense.amount),
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (showSpenderBadge)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: _personColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            expense.spenderName,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _personColor,
                            ),
                          ),
                        ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: isRoyCard
                              ? Colors.blueGrey.shade50
                              : Colors.purple.shade50,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.credit_card,
                              size: 13,
                              color: isRoyCard
                                  ? Colors.blueGrey.shade700
                                  : Colors.purple.shade700,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              expense.creditCardUsed,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: isRoyCard
                                    ? Colors.blueGrey.shade800
                                    : Colors.purple.shade800,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        AppFormatters.formatShortDate(expense.timestamp),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              icon: Icon(
                Icons.more_vert,
                size: 20,
                color: Colors.grey.shade600,
              ),
              onSelected: (value) async {
                if (value == 'share') {
                  await RasbFileService.shareSingleExpense(expense);
                } else if (value == 'copy') {
                  await Clipboard.setData(
                    ClipboardData(text: expense.toJson()),
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Expense JSON copied to clipboard'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                } else if (value == 'delete') {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Delete Expense?'),
                      content: Text(
                        'Remove "${expense.reason}" (${AppFormatters.formatShekel(expense.amount)}) from this device?',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.red,
                          ),
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Delete'),
                        ),
                      ],
                    ),
                  );
                  if (confirmed == true && context.mounted) {
                    await context
                        .read<ExpenseProvider>()
                        .deleteExpense(expense.id);
                  }
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'share',
                  child: ListTile(
                    leading: Icon(Icons.share_outlined),
                    title: Text('Share .rasb Sync File'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuItem(
                  value: 'copy',
                  child: ListTile(
                    leading: Icon(Icons.copy_outlined),
                    title: Text('Copy JSON'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: ListTile(
                    leading: Icon(Icons.delete_outline, color: Colors.red),
                    title: Text('Delete', style: TextStyle(color: Colors.red)),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
