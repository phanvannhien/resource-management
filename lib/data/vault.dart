import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import '../core/vault_crypto.dart';
import 'repository.dart';

/// Trạng thái kho mật khẩu: `null` = đang khoá, có giá trị = khoá giải mã đang mở.
class VaultController extends Notifier<SecretKey?> {
  static const _storageKey = 'vault_key';
  // macOS: dùng keychain thường vì Keychain Sharing cần ký bằng tài khoản Apple Developer
  final _storage = const FlutterSecureStorage(
    mOptions: MacOsOptions(usesDataProtectionKeychain: false),
  );
  final _localAuth = LocalAuthentication();

  @override
  SecretKey? build() => null;

  Repository get _repo => ref.read(repositoryProvider);

  /// Đã tạo master password chưa.
  Future<bool> isSetUp() async => (await _repo.loadSettings())?['vault_salt'] != null;

  Future<void> setup(String password) async {
    final salt = VaultCrypto.newSaltSpec();
    final key = await VaultCrypto.deriveKey(password, salt);
    await _repo.saveVaultSettings(salt, await VaultCrypto.makeCheck(key));
    state = key;
    await _rememberKey(key);
  }

  Future<bool> unlockWithPassword(String password) async {
    final s = await _repo.loadSettings();
    final salt = s?['vault_salt'] as String?;
    final check = s?['vault_check'] as String?;
    if (salt == null || check == null) return false;
    final key = await VaultCrypto.deriveKey(password, salt);
    if (!await VaultCrypto.verify(key, check)) return false;
    state = key;
    await _rememberKey(key);
    return true;
  }

  Future<bool> hasRememberedKey() => _storage.containsKey(key: _storageKey);

  Future<bool> unlockWithBiometrics() async {
    final stored = await _storage.read(key: _storageKey);
    if (stored == null) return false;
    try {
      if (!await _localAuth.authenticate(localizedReason: 'Mở khoá kho mật khẩu')) return false;
    } catch (_) {
      return false;
    }
    state = SecretKey(base64.decode(stored));
    return true;
  }

  /// Lưu khoá trong Keystore để lần sau mở bằng vân tay / khoá màn hình.
  Future<void> _rememberKey(SecretKey key) async {
    try {
      if (!await _localAuth.isDeviceSupported()) return;
      await _storage.write(key: _storageKey, value: base64.encode(await key.extractBytes()));
    } catch (_) {
      // Không lưu được thì lần sau nhập lại master password.
    }
  }

  void lock() => state = null;

  Future<void> forgetDevice() async {
    state = null;
    await _storage.delete(key: _storageKey);
  }

  Future<String> encrypt(String plain) => VaultCrypto.encrypt(state!, plain);
  Future<String> decrypt(String enc) => VaultCrypto.decrypt(state!, enc);
}

final vaultProvider = NotifierProvider<VaultController, SecretKey?>(VaultController.new);
