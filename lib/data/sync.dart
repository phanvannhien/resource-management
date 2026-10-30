import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'local_repository.dart';
import 'repository.dart';
import 'storage_config.dart';

/// Client WebDAV tối giản: chỉ cần GET / PUT / MKCOL một file.
/// Dùng được với cPanel "Web Disk", Nextcloud, Synology, Koofr, pCloud…
class WebDavClient {
  WebDavClient(this.config, {http.Client? client}) : _http = client ?? http.Client();
  final WebDavConfig config;
  final http.Client _http;

  Uri get _folder {
    final u = config.url.trim();
    return Uri.parse(u.endsWith('/') ? u : '$u/');
  }

  Uri get fileUri => _folder.resolve(LocalRepository.fileName);

  Map<String, String> get _headers => {
        'Authorization':
            'Basic ${base64.encode(utf8.encode('${config.username}:${config.password}'))}',
      };

  String _err(http.Response r) => switch (r.statusCode) {
        401 || 403 => 'Sai tài khoản hoặc không có quyền (${r.statusCode})',
        404 => 'Không tìm thấy đường dẫn (404)',
        _ => 'Máy chủ trả về lỗi ${r.statusCode}',
      };

  /// Tải nội dung file; null nếu chưa có file trên máy chủ.
  Future<String?> download() async {
    final r = await _http.get(fileUri, headers: _headers).timeout(const Duration(seconds: 20));
    if (r.statusCode == 404) return null;
    if (r.statusCode != 200) throw Exception(_err(r));
    return utf8.decode(r.bodyBytes);
  }

  Future<void> upload(String body) async {
    Future<http.Response> put() => _http
        .put(fileUri,
            headers: {..._headers, 'Content-Type': 'application/json; charset=utf-8'},
            body: utf8.encode(body))
        .timeout(const Duration(seconds: 30));
    var r = await put();
    if (r.statusCode == 404 || r.statusCode == 409) {
      // Thư mục chưa có → tạo rồi ghi lại
      final req = http.Request('MKCOL', _folder)..headers.addAll(_headers);
      await _http.send(req).timeout(const Duration(seconds: 20));
      r = await put();
    }
    if (r.statusCode < 200 || r.statusCode >= 300) throw Exception(_err(r));
  }

  /// Kiểm tra đăng nhập & quyền ghi (ghi thử 1 file nhỏ).
  Future<void> test() async {
    final probe = _folder.resolve('.amv-test');
    Future<http.Response> put() =>
        _http.put(probe, headers: _headers, body: 'ok').timeout(const Duration(seconds: 20));
    var r = await put();
    if (r.statusCode == 404 || r.statusCode == 409) {
      final req = http.Request('MKCOL', _folder)..headers.addAll(_headers);
      await _http.send(req).timeout(const Duration(seconds: 20));
      r = await put();
    }
    if (r.statusCode < 200 || r.statusCode >= 300) throw Exception(_err(r));
    await _http.delete(probe, headers: _headers);
  }
}

enum SyncPhase { off, idle, syncing, ok, error }

class SyncState {
  const SyncState(this.phase, {this.lastSync, this.message});
  final SyncPhase phase;
  final DateTime? lastSync;
  final String? message;
}

/// Đồng bộ file dữ liệu trên máy với WebDAV (chỉ dùng ở chế độ lưu trên máy).
///
/// - Mỗi lần sửa dữ liệu: đợi 2 giây (gom nhiều thay đổi) rồi đẩy file lên.
/// - Khi mở app / bấm "Đồng bộ ngay": tải bản trên máy chủ về so sánh, bản nào
///   `updated_at` mới hơn thì dùng bản đó (bản trên máy cũ được giữ ở *.prev.json).
class SyncController extends Notifier<SyncState> {
  Timer? _debounce;

  @override
  SyncState build() {
    ref.onDispose(() => _debounce?.cancel());
    final cfg = ref.watch(storageConfigProvider);
    return _enabled(cfg) ? const SyncState(SyncPhase.idle) : const SyncState(SyncPhase.off);
  }

  bool _enabled(StorageConfig cfg) =>
      cfg.mode == StorageMode.local && cfg.webdav.enabled && cfg.webdav.isComplete;

  WebDavClient? get _client {
    final cfg = ref.read(storageConfigProvider);
    return _enabled(cfg) ? WebDavClient(cfg.webdav) : null;
  }

  LocalRepository? get _local {
    final repo = ref.read(repositoryProvider);
    return repo is LocalRepository ? repo : null;
  }

  void scheduleUpload() {
    if (_client == null) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), () => upload());
  }

  Future<void> upload() async {
    final client = _client;
    final local = _local;
    if (client == null || local == null) return;
    state = SyncState(SyncPhase.syncing, lastSync: state.lastSync);
    try {
      await local.ensureLoaded();
      await client.upload(local.snapshotJson());
      state = SyncState(SyncPhase.ok, lastSync: DateTime.now(), message: 'Đã tải lên');
    } catch (e) {
      state = SyncState(SyncPhase.error, lastSync: state.lastSync, message: '$e');
    }
  }

  /// Đồng bộ 2 chiều. Trả về true nếu dữ liệu trên máy vừa được thay bằng bản từ máy chủ.
  Future<bool> syncNow() async {
    final client = _client;
    final local = _local;
    if (client == null || local == null) return false;
    _debounce?.cancel();
    state = SyncState(SyncPhase.syncing, lastSync: state.lastSync);
    try {
      await local.ensureLoaded();
      final remoteText = await client.download();
      if (remoteText == null) {
        await client.upload(local.snapshotJson());
        state = SyncState(SyncPhase.ok, lastSync: DateTime.now(), message: 'Đã tải lên lần đầu');
        return false;
      }
      final remote = jsonDecode(remoteText) as Map<String, dynamic>;
      final remoteAt = remote['updated_at'] as String? ?? '';
      final localAt = local.updatedAt;
      if (remoteAt.compareTo(localAt) > 0) {
        await local.replaceWith(remote);
        state = SyncState(SyncPhase.ok, lastSync: DateTime.now(), message: 'Đã lấy bản mới từ máy chủ');
        return true;
      }
      if (localAt.compareTo(remoteAt) > 0) {
        await client.upload(local.snapshotJson());
        state = SyncState(SyncPhase.ok, lastSync: DateTime.now(), message: 'Đã tải lên');
      } else {
        state = SyncState(SyncPhase.ok, lastSync: DateTime.now(), message: 'Đã khớp');
      }
      return false;
    } catch (e) {
      state = SyncState(SyncPhase.error, lastSync: state.lastSync, message: '$e');
      return false;
    }
  }
}

final syncProvider = NotifierProvider<SyncController, SyncState>(SyncController.new);
