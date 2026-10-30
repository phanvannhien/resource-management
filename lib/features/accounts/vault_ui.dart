import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/vault.dart';
import '../../widgets/common.dart';

/// Đảm bảo kho mật khẩu đã mở. Trả về true nếu mở được.
/// Lần đầu sẽ yêu cầu tạo master password.
Future<bool> requireVault(BuildContext context, WidgetRef ref) async {
  final vault = ref.read(vaultProvider.notifier);
  if (ref.read(vaultProvider) != null) return true;

  final bool setUp;
  try {
    setUp = await vault.isSetUp();
  } catch (e) {
    if (context.mounted) showSnack(context, 'Không kết nối được: $e');
    return false;
  }

  if (setUp && await vault.hasRememberedKey()) {
    if (await vault.unlockWithBiometrics()) return true;
  }
  if (!context.mounted) return false;

  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _VaultDialog(setup: !setUp),
  );
  return ok ?? false;
}

class _VaultDialog extends ConsumerStatefulWidget {
  const _VaultDialog({required this.setup});
  final bool setup;

  @override
  ConsumerState<_VaultDialog> createState() => _VaultDialogState();
}

class _VaultDialogState extends ConsumerState<_VaultDialog> {
  final _pw = TextEditingController();
  final _pw2 = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _pw.dispose();
    _pw2.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final vault = ref.read(vaultProvider.notifier);
    if (widget.setup) {
      if (_pw.text.length < 8) return setState(() => _error = 'Tối thiểu 8 ký tự');
      if (_pw.text != _pw2.text) return setState(() => _error = 'Hai lần nhập không khớp');
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (widget.setup) {
        await vault.setup(_pw.text);
      } else if (!await vault.unlockWithPassword(_pw.text)) {
        setState(() {
          _busy = false;
          _error = 'Sai master password';
        });
        return;
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _busy = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.setup ? 'Tạo master password' : 'Mở khoá kho mật khẩu'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.setup)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text(
                  'Mật khẩu VPS, hosting... được mã hoá bằng master password trước khi lưu lên server.\n\n'
                  '⚠ Quên master password = mất toàn bộ mật khẩu đã lưu. Hãy ghi lại ở nơi an toàn.',
                ),
              ),
            TextField(
              controller: _pw,
              autofocus: true,
              obscureText: _obscure,
              enabled: !_busy,
              decoration: InputDecoration(
                labelText: 'Master password',
                suffixIcon: IconButton(
                  icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              onSubmitted: widget.setup ? null : (_) => _submit(),
            ),
            if (widget.setup) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _pw2,
                obscureText: _obscure,
                enabled: !_busy,
                decoration: const InputDecoration(labelText: 'Nhập lại'),
                onSubmitted: (_) => _submit(),
              ),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!, style: const TextStyle(color: kRed)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: const Text('Huỷ'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(widget.setup ? 'Tạo' : 'Mở khoá'),
        ),
      ],
    );
  }
}
