import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/theme.dart';
import '../../data/repository.dart';
import '../../data/storage_config.dart';
import '../../data/vault.dart';
import '../../widgets/common.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: _email.text.trim(),
        password: _password.text,
      );
      // Bỏ dữ liệu của phiên trước; router tự chuyển sang Tổng quan khi có session.
      ref.invalidate(appDataProvider);
      ref.invalidate(accountsProvider);
      ref.invalidate(vaultProvider);
    } on AuthException catch (e) {
      setState(
        () => _error = e.message == 'Invalid login credentials'
            ? 'Sai email hoặc mật khẩu'
            : e.message,
      );
    } catch (e) {
      setState(() => _error = 'Không kết nối được: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: Brand.gradient),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x55000000),
                              blurRadius: 24,
                              offset: Offset(0, 8),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(28),
                          child: Image.asset(
                            'assets/icon/icon.png',
                            width: 120,
                            height: 120,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Domain · Hosting · VPS',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 15,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 28),
                    Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: AutofillGroup(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'Đăng nhập',
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 16),
                              TextField(
                                controller: _email,
                                keyboardType: TextInputType.emailAddress,
                                autofillHints: const [AutofillHints.email],
                                decoration: const InputDecoration(
                                  labelText: 'Email',
                                  prefixIcon: Icon(Icons.mail_outline),
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _password,
                                obscureText: _obscure,
                                autofillHints: const [AutofillHints.password],
                                onSubmitted: (_) => _login(),
                                decoration: InputDecoration(
                                  labelText: 'Mật khẩu',
                                  prefixIcon: const Icon(Icons.lock_outline),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscure
                                          ? Icons.visibility
                                          : Icons.visibility_off,
                                    ),
                                    onPressed: () =>
                                        setState(() => _obscure = !_obscure),
                                  ),
                                ),
                              ),
                              if (_error != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child: Text(
                                    _error!,
                                    style: const TextStyle(color: kRed),
                                  ),
                                ),
                              const SizedBox(height: 20),
                              FilledButton(
                                onPressed: _busy ? null : _login,
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size.fromHeight(50),
                                ),
                                child: _busy
                                    ? const SizedBox.square(
                                        dimension: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Text(
                                        'Đăng nhập',
                                        style: TextStyle(fontSize: 16),
                                      ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Supabase: ${Uri.tryParse(ref.read(storageConfigProvider).supabaseUrl)?.host ?? ''}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white60, fontSize: 12),
                    ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => ref.read(storageConfigProvider.notifier).reset(),
                      child: const Text(
                        'Đổi nơi lưu dữ liệu',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
