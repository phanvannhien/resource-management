import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import 'local_repository.dart';
import 'storage_config.dart';
import 'supabase_repository.dart';
import 'sync.dart';

/// Toàn bộ khách hàng, nhà cung cấp, dịch vụ. Dữ liệu ít nên tải hết rồi xử lý trên máy.
class AppData {
  AppData({required this.customers, required this.vendors, required this.services})
      : _customers = {for (final c in customers) c.id!: c},
        _vendors = {for (final v in vendors) v.id!: v},
        _services = {for (final s in services) s.id!: s};

  final List<Customer> customers;
  final List<Vendor> vendors;
  final List<Service> services; // đã sắp theo ngày hết hạn

  final Map<String, Customer> _customers;
  final Map<String, Vendor> _vendors;
  final Map<String, Service> _services;

  Customer? customer(String? id) => id == null ? null : _customers[id];
  Vendor? vendor(String? id) => id == null ? null : _vendors[id];
  Service? service(String? id) => id == null ? null : _services[id];

  String ownerName(Service s) => customer(s.customerId)?.name ?? 'Của tôi';

  List<Service> servicesOf(String customerId) =>
      services.where((s) => s.customerId == customerId).toList();

  /// Hosting đang chạy trên VPS (không tính hosting đã ngừng).
  List<Service> hostingsOn(String vpsId) =>
      services.where((s) => s.parentVpsId == vpsId && !s.cancelled).toList();

  List<Service> get activeVps =>
      services.where((s) => s.type == ServiceType.vps && !s.cancelled).toList();

  List<Service> get activeHostings =>
      services.where((s) => s.type == ServiceType.hosting && !s.cancelled).toList();
}

/// Các bảng dữ liệu (giống tên bảng trên Supabase).
const kTables = [
  'providers',
  'customers',
  'services',
  'accounts',
  'renewals',
  'transactions',
  'user_settings',
];

typedef Tables = Map<String, List<Map<String, dynamic>>>;

/// Lớp truy cập dữ liệu. Có 2 bản: [SupabaseRepository] (đám mây) và [LocalRepository] (trên máy).
abstract class Repository {
  Future<AppData> loadAll();

  Future<String> saveCustomer(Customer c);
  Future<void> deleteCustomer(String id);
  Future<void> setCustomerActive(String id, bool active);

  Future<String> saveVendor(Vendor v);
  Future<void> deleteVendor(String id);

  Future<String> saveService(Service s);
  Future<void> deleteService(String id);
  Future<void> setServiceCancelled(String id, bool cancelled);

  Future<List<Account>> loadAccounts();
  Future<String> saveAccount(Account a);
  Future<void> deleteAccount(String id);

  Future<List<Renewal>> loadRenewals(String serviceId);

  /// Toàn bộ lịch sử gia hạn (để nhập vào sổ thu chi).
  Future<List<Renewal>> loadAllRenewals();

  /// Các lần gia hạn trong năm (để báo cáo số tiền đã thu thực tế).
  Future<List<Renewal>> loadRenewalsInYear(int year);

  /// Gia hạn: hạn mới = hạn cũ + số tháng, ghi lịch sử.
  Future<void> renew({
    required String serviceId,
    required int months,
    int? amount,
    bool customerPaid = false,
    bool providerPaid = false,
    String? note,
  });

  /// Sổ thu chi (toàn bộ, sắp theo ngày mới nhất trước).
  Future<List<Txn>> loadTransactions();
  Future<String> saveTransaction(Txn t);
  Future<void> addTransactions(List<Txn> list);
  Future<void> deleteTransaction(String id);

  /// Cấu hình kho mật khẩu (vault_salt, vault_check).
  Future<Map<String, dynamic>?> loadSettings();
  Future<void> saveVaultSettings(String salt, String check);

  /// Toàn bộ dữ liệu thô (để sao lưu / chuyển nơi lưu).
  Future<Tables> exportTables();

  /// Nhập dữ liệu (ghi đè/gộp theo id).
  Future<void> importTables(Tables tables);
}

/// File sao lưu / đồng bộ: dùng chung cho cả 2 nơi lưu.
class BackupFile {
  static const format = 'amv-webmanage';

  static Map<String, dynamic> wrap(Tables tables, {int revision = 0, String? updatedAt}) => {
        'format': format,
        'version': 1,
        'revision': revision,
        'updated_at': updatedAt ?? DateTime.now().toUtc().toIso8601String(),
        'tables': tables,
      };

  /// Đọc file, ném FormatException nếu không đúng định dạng.
  static Tables tablesOf(Map<String, dynamic> json) {
    if (json['format'] != format) {
      // Bản sao lưu cũ (trước khi có định dạng này) là map tên bảng → danh sách.
      if (json.keys.any(kTables.contains)) return _cast(json);
      throw const FormatException('Không phải file sao lưu AMV-WebManage');
    }
    return _cast(json['tables'] as Map<String, dynamic>);
  }

  static Tables _cast(Map<String, dynamic> raw) => {
        for (final t in kTables)
          t: [
            for (final r in (raw[t] as List? ?? const []))
              Map<String, dynamic>.from(r as Map),
          ],
      };
}

/// Nơi lưu đang dùng; đổi nơi lưu thì mọi dữ liệu tự tải lại.
final repositoryProvider = Provider<Repository>((ref) {
  final cfg = ref.watch(storageConfigProvider);
  // Chưa chọn nơi lưu (màn chào mừng) cũng dùng file trên máy: không đụng tới Supabase.
  if (cfg.mode != StorageMode.cloud) {
    return LocalRepository(onChanged: () => ref.read(syncProvider.notifier).scheduleUpload());
  }
  return SupabaseRepository.current();
});

final appDataProvider = FutureProvider<AppData>((ref) => ref.watch(repositoryProvider).loadAll());

final accountsProvider =
    FutureProvider<List<Account>>((ref) => ref.watch(repositoryProvider).loadAccounts());

final yearRenewalsProvider = FutureProvider.family<List<Renewal>, int>(
    (ref, year) => ref.watch(repositoryProvider).loadRenewalsInYear(year));

final renewalsProvider = FutureProvider.family<List<Renewal>, String>(
    (ref, serviceId) => ref.watch(repositoryProvider).loadRenewals(serviceId));

/// Lỗi khi chưa tạo bảng sổ thu chi trên Supabase.
class MissingLedgerTable implements Exception {
  @override
  String toString() =>
      'Chưa có bảng sổ thu chi trên Supabase. Chạy file supabase/accounting.sql trong SQL Editor.';
}

final transactionsProvider = FutureProvider<List<Txn>>(
  (ref) => ref.watch(repositoryProvider).loadTransactions(),
  // Chưa có bảng thì thử lại cũng vô ích → báo lỗi ngay
  retry: (count, error) => error is MissingLedgerTable || count >= 3 ? null : Duration(seconds: 1 << count),
);
