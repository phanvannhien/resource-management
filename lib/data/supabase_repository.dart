import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/models.dart';
import 'repository.dart';

/// Lưu trên Supabase (Postgres + Row Level Security). Bảng & hàm xem supabase/schema.sql.
class SupabaseRepository implements Repository {
  SupabaseRepository(this.db);
  final SupabaseClient db;

  factory SupabaseRepository.current() => SupabaseRepository(Supabase.instance.client);

  @override
  Future<AppData> loadAll() async {
    final results = await Future.wait<List<Map<String, dynamic>>>([
      db.from('customers').select().order('name', ascending: true),
      db.from('providers').select().order('name', ascending: true),
      db.from('services').select().order('expiry_date', ascending: true),
    ]);
    return AppData(
      customers: results[0].map(Customer.fromJson).toList(),
      vendors: results[1].map(Vendor.fromJson).toList(),
      services: results[2].map(Service.fromJson).toList(),
    );
  }

  Future<String> _save(String table, String? id, Map<String, dynamic> data) async {
    if (id == null) {
      final row = await db.from(table).insert(data).select('id').single();
      return row['id'] as String;
    }
    await db.from(table).update(data).eq('id', id);
    return id;
  }

  Future<void> _delete(String table, String id) => db.from(table).delete().eq('id', id);

  @override
  Future<String> saveCustomer(Customer c) => _save('customers', c.id, c.toJson());
  @override
  Future<void> deleteCustomer(String id) => _delete('customers', id);
  @override
  Future<void> setCustomerActive(String id, bool active) =>
      db.from('customers').update({'is_active': active}).eq('id', id);

  @override
  Future<String> saveVendor(Vendor v) => _save('providers', v.id, v.toJson());
  @override
  Future<void> deleteVendor(String id) => _delete('providers', id);

  @override
  Future<String> saveService(Service s) => _save('services', s.id, s.toJson());
  @override
  Future<void> deleteService(String id) => _delete('services', id);
  @override
  Future<void> setServiceCancelled(String id, bool cancelled) =>
      db.from('services').update({'status': cancelled ? 'CANCELLED' : 'ACTIVE'}).eq('id', id);

  @override
  Future<List<Account>> loadAccounts() async {
    final rows = await db.from('accounts').select().order('label', ascending: true);
    return rows.map(Account.fromJson).toList();
  }

  @override
  Future<String> saveAccount(Account a) => _save('accounts', a.id, a.toJson());
  @override
  Future<void> deleteAccount(String id) => _delete('accounts', id);

  @override
  Future<List<Renewal>> loadRenewals(String serviceId) async {
    final rows = await db
        .from('renewals')
        .select()
        .eq('service_id', serviceId)
        .order('renewed_at', ascending: false);
    return rows.map(Renewal.fromJson).toList();
  }

  @override
  Future<List<Renewal>> loadAllRenewals() async {
    final rows = await db.from('renewals').select().order('renewed_at', ascending: true);
    return rows.map(Renewal.fromJson).toList();
  }

  /// Các lần gia hạn trong năm (để báo cáo số tiền đã thu thực tế).
  @override
  Future<List<Renewal>> loadRenewalsInYear(int year) async {
    final rows = await db
        .from('renewals')
        .select()
        .gte('renewed_at', '$year-01-01')
        .lt('renewed_at', '${year + 1}-01-01');
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
  }) =>
      db.rpc('renew_service', params: {
        'p_service_id': serviceId,
        'p_months': months,
        'p_amount': amount,
        'p_customer_paid': customerPaid,
        'p_provider_paid': providerPaid,
        'p_note': note,
      });

  /// Đổi lỗi "không có bảng" thành thông báo dễ hiểu.
  Future<T> _ledger<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST205' || e.code == '42P01' || e.message.contains('transactions')) {
        throw MissingLedgerTable();
      }
      rethrow;
    }
  }

  @override
  Future<List<Txn>> loadTransactions() => _ledger(() async {
        final rows = await db.from('transactions').select().order('paid_at', ascending: false);
        return rows.map(Txn.fromJson).toList();
      });

  @override
  Future<String> saveTransaction(Txn t) => _ledger(() => _save('transactions', t.id, t.toJson()));

  @override
  Future<void> addTransactions(List<Txn> list) => _ledger(() async {
        for (var i = 0; i < list.length; i += 200) {
          final chunk = list.sublist(i, i + 200 > list.length ? list.length : i + 200);
          await db.from('transactions').insert([for (final t in chunk) t.toJson()]);
        }
      });

  @override
  Future<void> deleteTransaction(String id) => _ledger(() => _delete('transactions', id));

  @override
  Future<Map<String, dynamic>?> loadSettings() =>
      db.from('user_settings').select().maybeSingle();

  @override
  Future<void> saveVaultSettings(String salt, String check) =>
      db.from('user_settings').upsert({
        'owner_id': db.auth.currentUser!.id,
        'vault_salt': salt,
        'vault_check': check,
      });

  @override
  Future<Tables> exportTables() async {
    final out = <String, List<Map<String, dynamic>>>{};
    for (final t in kTables) {
      try {
        final rows = await db.from(t).select();
        out[t] = [for (final r in rows) Map<String, dynamic>.from(r)..remove('owner_id')];
      } on PostgrestException {
        if (t != 'transactions') rethrow;
        out[t] = []; // chưa chạy accounting.sql
      }
    }
    return out;
  }

  /// Nhập theo thứ tự khoá ngoại; dịch vụ trỏ tới dịch vụ khác (VPS cha, hosting liên kết)
  /// được ghi 2 lượt: lượt đầu để trống liên kết, lượt sau mới gán.
  @override
  Future<void> importTables(Tables tables) async {
    List<Map<String, dynamic>> rows(String t) =>
        [for (final r in tables[t] ?? const <Map<String, dynamic>>[]) Map.of(r)..remove('owner_id')];

    Future<void> upsert(String t, List<Map<String, dynamic>> list) async {
      for (var i = 0; i < list.length; i += 200) {
        await db.from(t).upsert(list.sublist(i, i + 200 > list.length ? list.length : i + 200));
      }
    }

    await upsert('providers', rows('providers'));
    await upsert('customers', rows('customers'));
    final services = rows('services');
    await upsert('services', [
      for (final s in services) {...s, 'parent_vps_id': null, 'linked_hosting_id': null},
    ]);
    for (final s in services.where((s) => s['parent_vps_id'] != null || s['linked_hosting_id'] != null)) {
      await db.from('services').update({
        'parent_vps_id': s['parent_vps_id'],
        'linked_hosting_id': s['linked_hosting_id'],
      }).eq('id', s['id'] as Object);
    }
    await upsert('accounts', rows('accounts'));
    await upsert('renewals', rows('renewals'));
    if (rows('transactions').isNotEmpty) await _ledger(() => upsert('transactions', rows('transactions')));
    final settings = rows('user_settings');
    if (settings.isNotEmpty) {
      await db.from('user_settings').upsert({
        ...settings.first,
        'owner_id': db.auth.currentUser!.id,
      });
    }
  }
}
