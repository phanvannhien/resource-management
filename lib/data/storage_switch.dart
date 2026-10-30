import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'local_repository.dart';
import 'repository.dart';
import 'storage_config.dart';
import 'vault.dart';

const _kPendingUpload = 'pending_upload_local';

/// Tải lại mọi dữ liệu đang hiển thị (sau khi nhập / đổi nơi lưu / đồng bộ).
void refreshAllData(WidgetRef ref) {
  ref.invalidate(appDataProvider);
  ref.invalidate(accountsProvider);
  ref.invalidate(renewalsProvider);
  ref.invalidate(yearRenewalsProvider);
  ref.invalidate(transactionsProvider);
}

/// Kiểm tra URL + key Supabase có dùng được không.
Future<String?> testSupabase(String url, String key) async {
  try {
    final uri = Uri.parse('${url.trim().replaceAll(RegExp(r'/+$'), '')}/auth/v1/settings');
    final r = await http.get(uri, headers: {'apikey': key.trim()}).timeout(const Duration(seconds: 15));
    if (r.statusCode == 200) return null;
    if (r.statusCode == 401) return 'Key không đúng (401)';
    return 'Máy chủ trả về lỗi ${r.statusCode}';
  } catch (e) {
    return 'Không kết nối được: $e';
  }
}

/// Số khách / dịch vụ đang có trong file trên máy (để hỏi có muốn chép lên Supabase không).
Future<({int customers, int services})> localDataCount() async {
  final t = await LocalRepository().exportTables();
  return (customers: t['customers']!.length, services: t['services']!.length);
}

/// Huỷ yêu cầu "chép dữ liệu trên máy lên Supabase" đang chờ (khi người dùng đổi ý).
Future<void> clearPendingUpload() async =>
    (await SharedPreferences.getInstance()).setBool(_kPendingUpload, false);

/// Chuyển sang lưu trên máy. [copy] = chép dữ liệu đang có (từ Supabase) xuống máy.
Future<void> switchToLocal(WidgetRef ref, {required bool copy}) async {
  await clearPendingUpload();
  Tables? tables;
  if (copy) tables = await ref.read(repositoryProvider).exportTables();
  await ref.read(storageConfigProvider.notifier).setMode(StorageMode.local);
  if (tables != null) await ref.read(repositoryProvider).importTables(tables);
  ref.read(vaultProvider.notifier).lock();
  refreshAllData(ref);
}

/// Chuyển sang Supabase. [copyLocal] = sau khi đăng nhập, chép dữ liệu trên máy lên Supabase.
Future<void> switchToCloud(
  WidgetRef ref, {
  required String url,
  required String key,
  required bool copyLocal,
}) async {
  final p = await SharedPreferences.getInstance();
  await p.setBool(_kPendingUpload, copyLocal);
  await ref.read(storageConfigProvider.notifier)
      .setMode(StorageMode.cloud, supabaseUrl: url.trim(), supabaseKey: key.trim());
  ref.read(vaultProvider.notifier).lock();
  if (AppGate.instance.signedIn) await uploadPendingLocal(ref);
  refreshAllData(ref);
}

/// Nếu đang chờ chép dữ liệu trên máy lên Supabase thì làm ngay (gọi sau khi đăng nhập).
/// Trả về số dịch vụ đã chép, hoặc null nếu không có gì phải làm.
Future<int?> uploadPendingLocal(WidgetRef ref) async {
  final p = await SharedPreferences.getInstance();
  if (p.getBool(_kPendingUpload) != true) return null;
  final tables = await LocalRepository().exportTables();
  await ref.read(repositoryProvider).importTables(tables);
  await p.setBool(_kPendingUpload, false);
  refreshAllData(ref);
  return tables['services']!.length;
}
