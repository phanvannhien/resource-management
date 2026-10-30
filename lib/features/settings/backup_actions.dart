import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/repository.dart';
import '../../data/storage_switch.dart';
import '../../data/vault.dart';
import '../../widgets/common.dart';

String _stamp() {
  final n = DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${n.year}${two(n.month)}${two(n.day)}-${two(n.hour)}${two(n.minute)}';
}

/// Xuất file sao lưu rồi mở bảng chia sẻ của máy → lưu vào Google Drive / iCloud / Files…
Future<void> exportBackup(BuildContext context, WidgetRef ref) async {
  final tables = await ref.read(repositoryProvider).exportTables();
  final name = 'amv-webmanage-backup-${_stamp()}.json';
  final file = File('${(await getTemporaryDirectory()).path}/$name');
  await file.writeAsString(const JsonEncoder.withIndent('  ').convert(BackupFile.wrap(tables)));
  if (!context.mounted) return;
  // iPad / Mac cần vị trí gốc cho bảng chia sẻ
  final box = context.findRenderObject() as RenderBox?;
  await SharePlus.instance.share(ShareParams(
    files: [XFile(file.path, mimeType: 'application/json')],
    subject: name,
    sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size,
  ));
}

/// Chọn file sao lưu và nhập vào nơi lưu hiện tại (gộp theo id). Trả về true nếu đã nhập.
Future<bool> importBackup(BuildContext context, WidgetRef ref) async {
  final picked = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['json']);
  if (picked == null || !context.mounted) return false;
  final Tables tables;
  try {
    final json = jsonDecode(utf8.decode(await picked.readAsBytes())) as Map<String, dynamic>;
    tables = BackupFile.tablesOf(json);
  } catch (e) {
    if (context.mounted) showSnack(context, 'File không hợp lệ: $e');
    return false;
  }
  if (!context.mounted) return false;
  final ok = await confirm(
    context,
    'Khôi phục dữ liệu?',
    'File có ${tables['customers']!.length} khách hàng, ${tables['services']!.length} dịch vụ, '
        '${tables['accounts']!.length} tài khoản.\n\n'
        'Dữ liệu trùng sẽ được thay bằng bản trong file, dữ liệu khác giữ nguyên. '
        'Mật khẩu tài khoản trong file mở bằng master password của file đó.',
    ok: 'Khôi phục',
  );
  if (!ok || !context.mounted) return false;
  try {
    await ref.read(repositoryProvider).importTables(tables);
    ref.read(vaultProvider.notifier).lock();
    refreshAllData(ref);
    if (context.mounted) showSnack(context, 'Đã khôi phục dữ liệu');
    return true;
  } catch (e) {
    if (context.mounted) showSnack(context, 'Lỗi khôi phục: $e');
    return false;
  }
}
