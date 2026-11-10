import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/expense_provider.dart';
import '../services/rasb_file_service.dart';

class SyncDialog extends StatefulWidget {
  const SyncDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (_) => const SyncDialog(),
    );
  }

  @override
  State<SyncDialog> createState() => _SyncDialogState();
}

class _SyncDialogState extends State<SyncDialog> {
  final TextEditingController _jsonController = TextEditingController();
  String? _errorMessage;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _jsonController.dispose();
    super.dispose();
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && data!.text!.trim().isNotEmpty) {
      setState(() {
        _jsonController.text = data.text!.trim();
        _errorMessage = null;
      });
    }
  }

  Future<void> _pickRasbFile() async {
    final payload = await RasbFileService.pickRasbFile();
    if (payload != null && mounted) {
      setState(() {
        _jsonController.text = payload.content.trim();
        _errorMessage = null;
      });
      await _handleImport();
    }
  }

  Future<void> _handleImport() async {
    final raw = _jsonController.text.trim();
    if (raw.isEmpty) {
      setState(() {
        _errorMessage =
            'Please select a .rasb file or paste the JSON string received from Roy or Shany.';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final provider = context.read<ExpenseProvider>();
      final result = await provider.importFromJsonString(raw);

      if (!mounted) return;
      Navigator.of(context).pop();

      final String message;
      if (result.importedCount > 0 && result.duplicateCount == 0) {
        message =
            'Successfully imported ${result.importedCount} new expense${result.importedCount == 1 ? '' : 's'}!';
      } else if (result.importedCount > 0 && result.duplicateCount > 0) {
        message =
            'Imported ${result.importedCount} new expense${result.importedCount == 1 ? '' : 's'} (${result.duplicateCount} duplicate skipped).';
      } else {
        message =
            'Expense already exists in your database (${result.duplicateCount} duplicate skipped).';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor:
              result.importedCount > 0 ? Colors.green.shade700 : Colors.blueGrey,
        ),
      );
    } on FormatException catch (e) {
      setState(() {
        _errorMessage = 'Invalid .rasb / JSON format: ${e.message}';
      });
    } catch (e) {
      setState(() {
        _errorMessage =
            'Could not import .rasb / JSON. Please check the file or text.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.sync, color: Color(0xFF0F766E)),
          SizedBox(width: 10),
          Expanded(child: Text('Sync / Import (.rasb)')),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (kIsWeb) ...[
              FilledButton.icon(
                onPressed: _isSubmitting ? null : _pickRasbFile,
                icon: const Icon(Icons.upload_file),
                label: const Text('Select .rasb File from Phone'),
              ),
              const SizedBox(height: 12),
              const Center(
                child: Text(
                  '— OR paste JSON below —',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ),
              const SizedBox(height: 8),
            ] else
              const Text(
                'Tip: Tapping a .rasb file in WhatsApp opens & imports it automatically! You can also paste raw JSON below:',
                style: TextStyle(fontSize: 13, color: Colors.black87),
              ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _pasteFromClipboard,
                icon: const Icon(Icons.content_paste, size: 18),
                label: const Text('Paste from Clipboard'),
              ),
            ),
            TextField(
              controller: _jsonController,
              maxLines: 5,
              minLines: 3,
              decoration: InputDecoration(
                hintText:
                    '{"id":"...","spenderName":"Roy","amount":120.0,"timestamp":"...","reason":"Groceries","creditCardUsed":"Roy\'s Card"}',
                hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                errorText: _errorMessage,
                errorMaxLines: 3,
              ),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _isSubmitting ? null : _handleImport,
          icon: _isSubmitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.download_done),
          label: const Text('Import & Sync'),
        ),
      ],
    );
  }
}
