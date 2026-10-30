import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Nơi lưu dữ liệu.
enum StorageMode {
  /// File dữ liệu trên chính thiết bị (có thể đồng bộ WebDAV / sao lưu file).
  local,

  /// Supabase (Postgres trên đám mây), cần đăng nhập.
  cloud,
}

// Giá trị Supabase gắn sẵn lúc build (--dart-define-from-file=env.json), dùng làm mặc định.
const kDefaultSupabaseUrl = String.fromEnvironment('SUPABASE_URL');
const kDefaultSupabaseKey = String.fromEnvironment('SUPABASE_KEY');

/// Cấu hình đồng bộ WebDAV cho chế độ lưu trên máy.
class WebDavConfig {
  const WebDavConfig({this.enabled = false, this.url = '', this.username = '', this.password = ''});
  final bool enabled;

  /// URL thư mục, vd: https://host:2078/amv/
  final String url;
  final String username;
  final String password;

  bool get isComplete => url.isNotEmpty && username.isNotEmpty;

  WebDavConfig copyWith({bool? enabled, String? url, String? username, String? password}) =>
      WebDavConfig(
        enabled: enabled ?? this.enabled,
        url: url ?? this.url,
        username: username ?? this.username,
        password: password ?? this.password,
      );
}

class StorageConfig {
  const StorageConfig({
    this.mode,
    this.supabaseUrl = kDefaultSupabaseUrl,
    this.supabaseKey = kDefaultSupabaseKey,
    this.webdav = const WebDavConfig(),
  });

  /// null = chưa chọn (lần đầu mở app).
  final StorageMode? mode;
  final String supabaseUrl;
  final String supabaseKey;
  final WebDavConfig webdav;

  bool get hasSupabase => supabaseUrl.isNotEmpty && supabaseKey.isNotEmpty;

  StorageConfig copyWith({
    StorageMode? Function()? mode,
    String? supabaseUrl,
    String? supabaseKey,
    WebDavConfig? webdav,
  }) =>
      StorageConfig(
        mode: mode != null ? mode() : this.mode,
        supabaseUrl: supabaseUrl ?? this.supabaseUrl,
        supabaseKey: supabaseKey ?? this.supabaseKey,
        webdav: webdav ?? this.webdav,
      );

  static const _kMode = 'storage_mode';
  static const _kUrl = 'supabase_url';
  static const _kKey = 'supabase_key';
  static const _kDavOn = 'webdav_enabled';
  static const _kDavUrl = 'webdav_url';
  static const _kDavUser = 'webdav_user';
  static const _kDavPass = 'webdav_password'; // lưu trong Keychain/Keystore

  static const secure = FlutterSecureStorage(
    mOptions: MacOsOptions(usesDataProtectionKeychain: false),
  );

  static Future<StorageConfig> load() async {
    final p = await SharedPreferences.getInstance();
    var modeName = p.getString(_kMode);
    // Bản cũ (trước khi có lựa chọn nơi lưu) luôn dùng Supabase:
    // nếu đã có phiên đăng nhập Supabase thì giữ nguyên chế độ đám mây.
    if (modeName == null && p.getKeys().any((k) => k.startsWith('sb-'))) {
      modeName = StorageMode.cloud.name;
      await p.setString(_kMode, modeName);
    }
    String? davPass;
    try {
      davPass = await secure.read(key: _kDavPass);
    } catch (_) {}
    return StorageConfig(
      mode: StorageMode.values.where((m) => m.name == modeName).firstOrNull,
      supabaseUrl: p.getString(_kUrl) ?? kDefaultSupabaseUrl,
      supabaseKey: p.getString(_kKey) ?? kDefaultSupabaseKey,
      webdav: WebDavConfig(
        enabled: p.getBool(_kDavOn) ?? false,
        url: p.getString(_kDavUrl) ?? '',
        username: p.getString(_kDavUser) ?? '',
        password: davPass ?? '',
      ),
    );
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    if (mode == null) {
      await p.remove(_kMode);
    } else {
      await p.setString(_kMode, mode!.name);
    }
    await p.setString(_kUrl, supabaseUrl);
    await p.setString(_kKey, supabaseKey);
    await p.setBool(_kDavOn, webdav.enabled);
    await p.setString(_kDavUrl, webdav.url);
    await p.setString(_kDavUser, webdav.username);
    try {
      await secure.write(key: _kDavPass, value: webdav.password);
    } catch (_) {}
  }
}

/// Trạng thái dùng để điều hướng: đã chọn nơi lưu chưa, đã đăng nhập Supabase chưa.
/// Là ChangeNotifier để go_router chạy lại `redirect` khi thay đổi.
class AppGate extends ChangeNotifier {
  AppGate._();
  static final instance = AppGate._();

  StorageMode? mode;
  bool supabaseReady = false;
  StreamSubscription<AuthState>? _authSub;

  bool get signedIn => supabaseReady && Supabase.instance.client.auth.currentSession != null;

  void setMode(StorageMode? m) {
    mode = m;
    notifyListeners();
  }

  /// Khởi tạo (hoặc khởi tạo lại) Supabase với URL/key mới.
  Future<void> initSupabase(String url, String key) async {
    if (supabaseReady) {
      await _authSub?.cancel();
      await Supabase.instance.dispose();
      supabaseReady = false;
    }
    await Supabase.initialize(url: url, publishableKey: key);
    supabaseReady = true;
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((_) => notifyListeners());
    notifyListeners();
  }
}

class StorageConfigController extends Notifier<StorageConfig> {
  @override
  StorageConfig build() => ref.watch(initialStorageConfigProvider);

  /// Đổi nơi lưu (và cấu hình Supabase nếu chuyển sang đám mây).
  Future<void> setMode(StorageMode mode, {String? supabaseUrl, String? supabaseKey}) async {
    final next = state.copyWith(
      mode: () => mode,
      supabaseUrl: supabaseUrl,
      supabaseKey: supabaseKey,
    );
    if (mode == StorageMode.cloud) {
      await AppGate.instance.initSupabase(next.supabaseUrl, next.supabaseKey);
    }
    await next.save();
    state = next;
    AppGate.instance.setMode(mode);
  }

  /// Quay về màn chọn nơi lưu (huỷ luôn việc chép dữ liệu lên Supabase đang chờ).
  Future<void> reset() async {
    (await SharedPreferences.getInstance()).setBool('pending_upload_local', false);
    final next = state.copyWith(mode: () => null);
    await next.save();
    state = next;
    AppGate.instance.setMode(null);
  }

  Future<void> setWebDav(WebDavConfig dav) async {
    final next = state.copyWith(webdav: dav);
    await next.save();
    state = next;
  }
}

/// Cấu hình đọc lúc khởi động (ghi đè trong ProviderScope ở main.dart).
final initialStorageConfigProvider = Provider<StorageConfig>((_) => const StorageConfig());

final storageConfigProvider =
    NotifierProvider<StorageConfigController, StorageConfig>(StorageConfigController.new);
