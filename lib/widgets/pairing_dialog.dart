import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/expense_provider.dart';

class PairingDialog extends StatefulWidget {
  final bool barrierDismissible;

  const PairingDialog({
    super.key,
    this.barrierDismissible = true,
  });

  static Future<void> show(
    BuildContext context, {
    bool barrierDismissible = true,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (_) => PairingDialog(barrierDismissible: barrierDismissible),
    );
  }

  @override
  State<PairingDialog> createState() => _PairingDialogState();
}

class _PairingDialogState extends State<PairingDialog> {
  late final TextEditingController _passwordController;
  bool _obscure = false;
  bool _isSaving = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    final existing = context.read<ExpenseProvider>().pairingPassword ?? '';
    _passwordController = TextEditingController(text: existing);
  }

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _savePassword() async {
    final pwd = _passwordController.text.trim();
    if (pwd.length < 4) {
      setState(() {
        _errorText = 'Please enter a secret password of at least 4 characters.';
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _errorText = null;
    });

    try {
      final provider = context.read<ExpenseProvider>();
      final syncedCount = await provider.setPairingPassword(pwd);
      if (!mounted) return;
      Navigator.of(context).pop();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            syncedCount > 0
                ? 'Paired & encrypted! Synced $syncedCount expense${syncedCount == 1 ? '' : 's'}.'
                : 'Paired! Your encrypted P2P sync channel is active.',
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.green.shade700,
        ),
      );
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
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.vpn_key, color: Color(0xFF0F766E)),
          SizedBox(width: 10),
          Expanded(child: Text('One-Time Pairing Password')),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Enter the same secret password on both your Android and Shany\'s iPhone once. '
              'This creates your private, end-to-end encrypted P2P sync channel so nobody else can ever see or join your budget.',
              style: TextStyle(fontSize: 13.5, color: Colors.black87),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              obscureText: _obscure,
              autofocus: true,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _savePassword(),
              decoration: InputDecoration(
                labelText: 'Shared Secret Password',
                hintText: 'e.g. RoyAndShany2026!',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscure ? Icons.visibility : Icons.visibility_off,
                  ),
                  onPressed: () {
                    setState(() {
                      _obscure = !_obscure;
                    });
                  },
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                errorText: _errorText,
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (widget.barrierDismissible)
          TextButton(
            onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        FilledButton.icon(
          onPressed: _isSaving ? null : _savePassword,
          icon: _isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.check),
          label: const Text('Save & Pair'),
        ),
      ],
    );
  }
}
