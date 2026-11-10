import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../models/expense.dart';
import '../providers/expense_provider.dart';
import '../services/rasb_file_service.dart';
import '../utils/formatters.dart';

class AddExpenseScreen extends StatefulWidget {
  const AddExpenseScreen({super.key});

  @override
  State<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends State<AddExpenseScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _reasonController = TextEditingController();

  String _selectedSpender = Expense.spenderRoy;
  String? _selectedCreditCard;
  bool _showCreditCardValidationError = false;
  DateTime _selectedDate = DateTime.now();
  bool _isSaving = false;

  static const List<String> _quickReasons = [
    'Groceries',
    'Supermarket',
    'Restaurant / Dining',
    'Fuel / Gas',
    'Bills & Utilities',
    'Pharmacy',
    'Coffee',
    'Household',
  ];

  @override
  void dispose() {
    _amountController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime() async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (pickedDate == null || !mounted) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_selectedDate),
    );
    if (!mounted) return;

    setState(() {
      _selectedDate = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        pickedTime?.hour ?? _selectedDate.hour,
        pickedTime?.minute ?? _selectedDate.minute,
      );
    });
  }

  Future<void> _saveExpense({
    required bool openShareWindow,
    bool shareAsRasbFile = false,
  }) async {
    final isFormValid = _formKey.currentState?.validate() ?? false;
    final isCardSelected =
        _selectedCreditCard != null && _selectedCreditCard!.isNotEmpty;

    setState(() {
      _showCreditCardValidationError = !isCardSelected;
    });

    if (!isFormValid || !isCardSelected) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final parsedAmount = double.parse(
        _amountController.text.trim().replaceAll(',', '.'),
      );
      final expense = Expense(
        id: const Uuid().v4(),
        spenderName: _selectedSpender,
        amount: parsedAmount,
        timestamp: _selectedDate,
        reason: _reasonController.text.trim(),
        creditCardUsed: _selectedCreditCard!,
      );

      // 1. Save locally and automatically sync in the background to the other phone
      final provider = context.read<ExpenseProvider>();
      await provider.addExpense(expense);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Saved & auto-synced: ${expense.spenderName} spent ${AppFormatters.formatShekel(expense.amount)} on ${expense.reason}',
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.green.shade700,
        ),
      );
      Navigator.of(context).pop(expense);

      // 2. Optionally open the native share window for WhatsApp
      if (openShareWindow) {
        if (shareAsRasbFile) {
          await RasbFileService.shareSingleExpense(expense);
        } else {
          await RasbFileService.shareOneTapWhatsAppSync(expense);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving expense: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add New Expense'),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              // Spender selection (Roy vs Shany)
              const Text(
                'Spender',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment<String>(
                    value: Expense.spenderRoy,
                    label: Text('Roy'),
                    icon: Icon(Icons.person),
                  ),
                  ButtonSegment<String>(
                    value: Expense.spenderShany,
                    label: Text('Shany'),
                    icon: Icon(Icons.person_outline),
                  ),
                ],
                selected: {_selectedSpender},
                onSelectionChanged: (selection) {
                  setState(() {
                    _selectedSpender = selection.first;
                  });
                },
              ),
              const SizedBox(height: 22),

              // Amount field with Shekel symbol (₪)
              const Text(
                'Amount (${AppFormatters.shekelSymbol})',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
                decoration: InputDecoration(
                  prefixText: '${AppFormatters.shekelSymbol} ',
                  prefixStyle: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F766E),
                  ),
                  hintText: '0.00',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter an amount in ${AppFormatters.shekelSymbol}.';
                  }
                  final normalized = value.trim().replaceAll(',', '.');
                  final parsed = double.tryParse(normalized);
                  if (parsed == null || parsed <= 0) {
                    return 'Please enter a valid amount greater than 0.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 22),

              // Reason field (MANDATORY)
              const Text(
                'Reason *',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _reasonController,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: 'What was this expense for? (Mandatory)',
                  prefixIcon: const Icon(Icons.receipt_long_outlined),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Reason is mandatory. You cannot save without entering a reason.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: _quickReasons.map((suggestion) {
                  return ActionChip(
                    label: Text(
                      suggestion,
                      style: const TextStyle(fontSize: 12.5),
                    ),
                    onPressed: () {
                      setState(() {
                        _reasonController.text = suggestion;
                      });
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 22),

              // Credit Card Used (Radio buttons - MANDATORY)
              const Text(
                'Credit Card Used *',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: _showCreditCardValidationError
                        ? Theme.of(context).colorScheme.error
                        : Colors.grey.shade400,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: RadioGroup<String>(
                  groupValue: _selectedCreditCard,
                  onChanged: (value) {
                    setState(() {
                      _selectedCreditCard = value;
                      _showCreditCardValidationError = false;
                    });
                  },
                  child: Column(
                    children: [
                      RadioListTile<String>(
                        value: Expense.cardRoy,
                        title: const Text(
                          Expense.cardRoy,
                          style: TextStyle(fontWeight: FontWeight.w500),
                        ),
                        secondary: const Icon(
                          Icons.credit_card,
                          color: Color(0xFF2563EB),
                        ),
                      ),
                      const Divider(height: 1),
                      RadioListTile<String>(
                        value: Expense.cardShany,
                        title: const Text(
                          Expense.cardShany,
                          style: TextStyle(fontWeight: FontWeight.w500),
                        ),
                        secondary: const Icon(
                          Icons.credit_card,
                          color: Color(0xFFDB2777),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_showCreditCardValidationError)
                Padding(
                  padding: const EdgeInsets.only(top: 6, left: 12),
                  child: Text(
                    'Please select which credit card was used (mandatory).',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              const SizedBox(height: 22),

              // Date & Time selector
              ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 4,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.grey.shade300),
                ),
                leading: const Icon(Icons.calendar_today_outlined),
                title: const Text(
                  'Date & Time',
                  style: TextStyle(fontSize: 13, color: Colors.black54),
                ),
                subtitle: Text(
                  AppFormatters.formatDateTime(_selectedDate),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                trailing: TextButton(
                  onPressed: _pickDateTime,
                  child: const Text('Change'),
                ),
              ),
              const SizedBox(height: 30),

              // Primary Save & Auto-Sync button (0 extra steps needed!)
              SizedBox(
                height: 54,
                child: FilledButton.icon(
                  onPressed: _isSaving
                      ? null
                      : () => _saveExpense(openShareWindow: false),
                  icon: _isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.cloud_done_outlined),
                  label: const Text(
                    'Save Expense (Auto-Syncs)',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isSaving
                          ? null
                          : () => _saveExpense(
                                openShareWindow: true,
                                shareAsRasbFile: false,
                              ),
                      icon: const Icon(Icons.link, size: 18),
                      label: const Text('Save & WhatsApp Link'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isSaving
                          ? null
                          : () => _saveExpense(
                                openShareWindow: true,
                                shareAsRasbFile: true,
                              ),
                      icon: const Icon(Icons.attach_file, size: 18),
                      label: const Text('Save & .rasb File'),
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
