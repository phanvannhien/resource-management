import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

/// Mã hoá mật khẩu trong kho tài khoản.
///
/// Khoá AES-256-GCM sinh từ master password bằng PBKDF2-HMAC-SHA256.
/// Database chỉ lưu chuỗi đã mã hoá, salt và một chuỗi kiểm tra.
class VaultCrypto {
  static const _checkPlain = 'servicemanager-vault-ok';
  static const _iterations = 120000;
  static final _aes = AesGcm.with256bits();

  /// Định dạng: `pbkdf2-sha256:<iterations>:<salt base64>`.
  static String newSaltSpec() {
    final rnd = Random.secure();
    final salt = List<int>.generate(16, (_) => rnd.nextInt(256));
    return 'pbkdf2-sha256:$_iterations:${base64.encode(salt)}';
  }

  static Future<SecretKey> deriveKey(String password, String saltSpec) {
    final parts = saltSpec.split(':');
    if (parts.length != 3 || parts[0] != 'pbkdf2-sha256') {
      throw const FormatException('Salt không hợp lệ');
    }
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: int.parse(parts[1]),
      bits: 256,
    );
    return pbkdf2.deriveKeyFromPassword(password: password, nonce: base64.decode(parts[2]));
  }

  static Future<String> encrypt(SecretKey key, String plain) async {
    final box = await _aes.encrypt(utf8.encode(plain), secretKey: key);
    return 'v1:${base64.encode(box.concatenation())}';
  }

  /// Ném [SecretBoxAuthenticationError] nếu sai khoá.
  static Future<String> decrypt(SecretKey key, String encrypted) async {
    if (!encrypted.startsWith('v1:')) throw const FormatException('Dữ liệu mã hoá không hợp lệ');
    final box = SecretBox.fromConcatenation(
      base64.decode(encrypted.substring(3)),
      nonceLength: _aes.nonceLength,
      macLength: _aes.macAlgorithm.macLength,
    );
    return utf8.decode(await _aes.decrypt(box, secretKey: key));
  }

  static Future<String> makeCheck(SecretKey key) => encrypt(key, _checkPlain);

  static Future<bool> verify(SecretKey key, String check) async {
    try {
      return await decrypt(key, check) == _checkPlain;
    } on SecretBoxAuthenticationError {
      return false;
    }
  }
}
