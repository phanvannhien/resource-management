import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../core/format.dart';
import '../models/models.dart';
import 'repository.dart';

/// Lưu toàn bộ dữ liệu trong 1 file JSON trên máy (cùng cấu trúc bảng với Supabase).
///
/// Dữ liệu nhỏ (vài trăm dòng) nên đọc hết vào bộ nhớ, ghi lại cả file sau mỗi thay đổi
/// (ghi ra file tạm rồi đổi tên → không hỏng file nếu tắt app giữa chừng).
/// Mỗi lần ghi tăng `revision` và cập nhật `updated_at` (dùng cho đồng bộ WebDAV).
class LocalRepository implements Repository {
  LocalRepository({this.onChanged, String? filePath}) : _fixedPath = filePath;

  static const fileName = 'amv-webmanage.json';

  /// Gọi sau mỗi lần dữ liệu thay đổi (để lên lịch đồng bộ).
  final void Function()? onChanged;
  final String? _fixedPath;

  static const _uuid = Uuid();

  Tables? _tables;
  int _revision = 0;
  String _updatedAt = '';
  Future<void>? _loading;

  Future<File> file() async {
    if (_fixedPath != null) return File(_fixedPath);
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$fileName');
  }

  Future<Tables> _db() async {
    if (_tables != null) return _tables!;
    await (_loading ??= _load());
    return _tables!;
  }

  Future<void> _load() async {
    final f = await file();
    if (await f.exists()) {
      final json = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      _tables = BackupFile.tablesOf(json);
      _revision = (json['revision'] as num?)?.toInt() ?? 0;
      _updatedAt = json['updated_at'] as String? ?? '';
    } else {
      _tables = {for (final t in kTables) t: <Map<String, dynamic>>[]};
    }
  }

  Future<void> _commit() async {
    _revision++;
    _updatedAt = DateTime.now().toUtc().toIso8601String();
    await _write();
    onChanged?.call();
  }

  Future<void> _write() async {
    final f = await file();
    await f.parent.create(recursive: true);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(snapshotJson());
    await tmp.rename(f.path);
  }

  /// Nội dung file hiện tại (định dạng [BackupFile]).
  String snapshotJson() => jsonEncode(
      BackupFile.wrap(_tables ?? {}, revision: _revision, updatedAt: _updatedAt));

  int get revision => _revision;
  String get updatedAt => _updatedAt;

  /// Thay toàn bộ dữ liệu bằng bản tải về từ đám mây (giữ revision/updated_at của bản đó).
  /// Bản trên máy trước đó được giữ lại ở `*.prev.json` để phòng khi cần khôi phục.
  Future<void> replaceWith(Map<String, dynamic> json) async {
    final tables = BackupFile.tablesOf(json);
    await _db();
    final f = await file();
    if (await f.exists()) await f.copy(f.path.replaceAll('.json', '.prev.json'));
    _tables = tables;
    _revision = (json['revision'] as num?)?.toInt() ?? _revision;
    _updatedAt = json['updated_at'] as String? ?? DateTime.now().toUtc().toIso8601String();
    await _write();
  }

  /// Đảm bảo đã đọc file (để lấy revision/updated_at trước khi đồng bộ).
  Future<void> ensureLoaded() => _db();

  // ---------------------------------------------------------------------------
  // Tiện ích
  // ---------------------------------------------------------------------------

  String _now() => DateTime.now().toUtc().toIso8601String();

  Future<String> _save(String table, String? id, Map<String, dynamic> data) async {
    final rows = (await _db())[table]!;
    if (id == null) {
      final newId = _uuid.v4();
      rows.add({...data, 'id': newId, 'created_at': _now(), 'updated_at': _now()});
      await _commit();
      return newId;
    }
    final i = rows.indexWhere((r) => r['id'] == id);
    if (i < 0) throw StateError('Không tìm thấy bản ghi $id');
    rows[i] = {...rows[i], ...data, 'updated_at': _now()};
    await _commit();
    return id;
  }

  Future<void> _patch(String table, String id, Map<String, dynamic> data) async {
    final rows = (await _db())[table]!;
    final i = rows.indexWhere((r) => r['id'] == id);
    if (i < 0) return;
    rows[i] = {...rows[i], ...data, 'updated_at': _now()};
    await _commit();
  }

  /// Gán null cho các cột khoá ngoại đang trỏ tới [id] (giống `on delete set null`).
  void _nullify(Tables db, String table, String column, String id) {
    for (final r in db[table]!) {
      if (r[column] == id) r[column] = null;
    }
  }

  int _byName(Map<String, dynamic> a, Map<String, dynamic> b, String col) =>
      (a[col] as String? ?? '').toLowerCase().compareTo((b[col] as String? ?? '').toLowerCase());

  // ---------------------------------------------------------------------------
  // Repository
  // ---------------------------------------------------------------------------

  @override
  Future<AppData> loadAll() async {
    final db = await _db();
    final customers = [...db['customers']!]..sort((a, b) => _byName(a, b, 'name'));
    final vendors = [...db['providers']!]..sort((a, b) => _byName(a, b, 'name'));
    final services = [...db['services']!]
      ..sort((a, b) => (a['expiry_date'] as String).compareTo(b['expiry_date'] as String));
    return AppData(
      customers: customers.map(Customer.fromJson).toList(),
      vendors: vendors.map(Vendor.fromJson).toList(),
      services: services.map(Service.fromJson).toList(),
    );
  }

  @override
  Future<String> saveCustomer(Customer c) => _save('customers', c.id, c.toJson());

  @override
  Future<void> deleteCustomer(String id) async {
    final db = await _db();
    db['customers']!.removeWhere((r) => r['id'] == id);
    _nullify(db, 'services', 'customer_id', id);
    _nullify(db, 'accounts', 'customer_id', id);
    _nullify(db, 'transactions', 'customer_id', id);
    await _commit();
  }

  @override
  Future<void> setCustomerActive(String id, bool active) =>
      _patch('customers', id, {'is_active': active});

  @override
  Future<String> saveVendor(Vendor v) => _save('providers', v.id, v.toJson());

  @override
  Future<void> deleteVendor(String id) async {
    final db = await _db();
    db['providers']!.removeWhere((r) => r['id'] == id);
    _nullify(db, 'services', 'provider_id', id);
    _nullify(db, 'accounts', 'provider_id', id);
    await _commit();
  }

  @override
  Future<String> saveService(Service s) => _save('services', s.id, s.toJson());

  @override
  Future<void> deleteService(String id) async {
    final db = await _db();
    db['services']!.removeWhere((r) => r['id'] == id);
    db['renewals']!.removeWhere((r) => r['service_id'] == id);
    _nullify(db, 'services', 'parent_vps_id', id);
    _nullify(db, 'services', 'linked_hosting_id', id);
    _nullify(db, 'accounts', 'service_id', id);
    _nullify(db, 'transactions', 'service_id', id);
    await _commit();
  }

  @override
  Future<void> setServiceCancelled(String id, bool cancelled) =>
      _patch('services', id, {'status': cancelled ? 'CANCELLED' : 'ACTIVE'});

  @override
  Future<List<Account>> loadAccounts() async {
    final rows = [...(await _db())['accounts']!]..sort((a, b) => _byName(a, b, 'label'));
    return rows.map(Account.fromJson).toList();
  }

  @override
  Future<String> saveAccount(Account a) => _save('accounts', a.id, a.toJson());

  @override
  Future<void> deleteAccount(String id) async {
    (await _db())['accounts']!.removeWhere((r) => r['id'] == id);
    await _commit();
  }

  @override
  Future<List<Renewal>> loadRenewals(String serviceId) async {
    final rows = (await _db())['renewals']!.where((r) => r['service_id'] == serviceId).toList()
      ..sort((a, b) => (b['renewed_at'] as String).compareTo(a['renewed_at'] as String));
    return rows.map(Renewal.fromJson).toList();
  }

  @override
  Future<List<Renewal>> loadAllRenewals() async =>
      (await _db())['renewals']!.map(Renewal.fromJson).toList();

  @override
  Future<List<Renewal>> loadRenewalsInYear(int year) async {
    final rows = (await _db())['renewals']!.where((r) {
      final d = DateTime.parse(r['renewed_at'] as String).toLocal();
      return d.year == year;
    });
    return rows.map(Renewal.fromJson).toList();
  }

  @override
  Future<void> renew({
    required String serviceId,
    required int months,
    int? amount,
    bool customerPaid = false,
    bool providerPaid = false,
    String? note,
  }) async {
    if (months <= 0) throw ArgumentError('months must be > 0');
    final db = await _db();
    final i = db['services']!.indexWhere((r) => r['id'] == serviceId);
    if (i < 0) throw StateError('Không tìm thấy dịch vụ');
    final row = db['services']![i];
    final oldExpiry = parseDbDate(row['expiry_date'])!;
    final newExpiry = addMonths(oldExpiry, months);
    db['services']![i] = {
      ...row,
      'expiry_date': toDbDate(newExpiry),
      'status': 'ACTIVE',
      'updated_at': _now(),
    };
    db['renewals']!.add({
      'id': _uuid.v4(),
      'service_id': serviceId,
      'renewed_at': _now(),
      'old_expiry': toDbDate(oldExpiry),
      'new_expiry': toDbDate(newExpiry),
      'months': months,
      'amount': amount,
      'customer_paid': customerPaid,
      'provider_paid': providerPaid,
      'note': note,
    });
    await _commit();
  }

  @override
  Future<List<Txn>> loadTransactions() async {
    final rows = [...(await _db())['transactions']!]
      ..sort((a, b) => (b['paid_at'] as String).compareTo(a['paid_at'] as String));
    return rows.map(Txn.fromJson).toList();
  }

  @override
  Future<String> saveTransaction(Txn t) => _save('transactions', t.id, t.toJson());

  @override
  Future<void> addTransactions(List<Txn> list) async {
    final rows = (await _db())['transactions']!;
    for (final t in list) {
      rows.add({...t.toJson(), 'id': _uuid.v4(), 'created_at': _now(), 'updated_at': _now()});
    }
    await _commit();
  }

  @override
  Future<void> deleteTransaction(String id) async {
    (await _db())['transactions']!.removeWhere((r) => r['id'] == id);
    await _commit();
  }

  @override
  Future<Map<String, dynamic>?> loadSettings() async {
    final rows = (await _db())['user_settings']!;
    return rows.isEmpty ? null : rows.first;
  }

  @override
  Future<void> saveVaultSettings(String salt, String check) async {
    final rows = (await _db())['user_settings']!;
    final current = rows.isEmpty ? <String, dynamic>{} : rows.first;
    rows
      ..clear()
      ..add({...current, 'vault_salt': salt, 'vault_check': check, 'updated_at': _now()});
    await _commit();
  }

  @override
  Future<Tables> exportTables() async {
    final db = await _db();
    return {for (final t in kTables) t: [for (final r in db[t]!) Map<String, dynamic>.of(r)]};
  }

  /// Gộp theo id: bản ghi trùng id được thay bằng bản nhập vào.
  @override
  Future<void> importTables(Tables tables) async {
    final db = await _db();
    for (final t in kTables) {
      final incoming = tables[t] ?? const [];
      if (t == 'user_settings') {
        if (incoming.isNotEmpty) {
          db[t]!
            ..clear()
            ..add(Map.of(incoming.first)..remove('owner_id'));
        }
        continue;
      }
      final byId = {for (final r in db[t]!) r['id']: r};
      for (final r in incoming) {
        byId[r['id']] = Map.of(r)..remove('owner_id');
      }
      db[t] = byId.values.toList();
    }
    await _commit();
  }
}
