
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/theme.dart';
import '../../data/repository.dart';
import '../../data/storage_config.dart';
import '../../data/vault.dart';
import '../../widgets/common.dart';
import '../../widgets/glass_nav_bar.dart';
import '../../widgets/ui.dart';
import 'backup_actions.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _exporting = false;

  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      await exportBackup(context, ref);
    } catch (e) {
      if (mounted) showSnack(context, 'Lỗi xuất sao lưu: $e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _logout() async {
    if (!await confirm(context, 'Đăng xuất?', 'Bạn sẽ cần đăng nhập lại để dùng app.')) return;
    await ref.read(vaultProvider.notifier).forgetDevice();
    await Supabase.instance.client.auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final cloud = ref.watch(storageConfigProvider).mode == StorageMode.cloud;
    final user = cloud && AppGate.instance.supabaseReady ? Supabase.instance.client.auth.currentUser : null;
    final unlocked = ref.watch(vaultProvider) != null;
    final dark = ref.watch(themeModeProvider) == ThemeMode.dark;
    final vendorCount = ref.watch(appDataProvider).value?.vendors.length;

    return Scaffold(
      extendBody: true,
      bottomNavigationBar: const GlassNavBar(),
      appBar: AppBar(
        toolbarHeight: 76,
        title: const PageTitle('Cài đặt', icon: Icons.settings_rounded),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: kNavBarSpace),
        children: [
          SettingsGroup(title: 'Tài khoản', children: [
            SettingsItem(
              icon: cloud ? Icons.person_outline_rounded : Icons.phone_iphone_rounded,
              color: const Color(0xFF2DD4BF),
              title: cloud ? (user?.email ?? '') : 'Không dùng tài khoản',
              subtitle: cloud ? 'Đăng nhập Supabase' : 'Dữ liệu lưu trên máy này',
            ),
          ]),
          SettingsGroup(title: 'Dữ liệu', children: [
            SettingsItem(
              icon: Icons.storage_rounded,
              color: const Color(0xFF38BDF8),
              title: 'Lưu trữ dữ liệu',
              value: cloud ? 'Supabase' : 'Trên máy',
              onTap: () => context.push('/settings/storage'),
            ),
            SettingsItem(
              icon: Icons.business_rounded,
              color: Brand.accent,
              title: 'Nhà cung cấp',
              value: vendorCount?.toString(),
              onTap: () => context.push('/settings/vendors'),
            ),
            SettingsItem(
              icon: Icons.download_rounded,
              color: const Color(0xFFFBBF24),
              title: 'Xuất file sao lưu',
              subtitle: 'Lưu vào Google Drive / iCloud / Files',
              trailing: _exporting
                  ? const SizedBox.square(
                      dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : null,
              onTap: _exporting ? null : _export,
            ),
            SettingsItem(
              icon: Icons.settings_backup_restore_rounded,
              color: const Color(0xFF34D399),
              title: 'Khôi phục từ file',
              onTap: () => importBackup(context, ref),
            ),
          ]),
          SettingsGroup(title: 'Bảo mật', children: [
            SettingsItem(
              icon: unlocked ? Icons.lock_open_rounded : Icons.lock_outline_rounded,
              color: kRed,
              title: unlocked ? 'Khoá kho mật khẩu ngay' : 'Kho mật khẩu đang khoá',
              onTap: unlocked ? () => ref.read(vaultProvider.notifier).lock() : null,
            ),
            SettingsItem(
              icon: Icons.fingerprint_rounded,
              color: const Color(0xFFA78BFA),
              title: 'Quên khoá trên máy này',
              subtitle: 'Lần sau phải nhập master password',
              onTap: () async {
                await ref.read(vaultProvider.notifier).forgetDevice();
                if (context.mounted) showSnack(context, 'Đã xoá khoá lưu trên máy');
              },
            ),
          ]),
          SettingsGroup(title: 'Cài đặt ứng dụng', children: [
            SettingsItem(
              icon: Icons.dark_mode_rounded,
              color: const Color(0xFF22D3EE),
              title: 'Giao diện tối',
              trailing: Switch(
                value: dark,
                onChanged: (v) => ref.read(themeModeProvider.notifier).setDark(v),
              ),
            ),
          ]),
          SettingsGroup(title: 'Thông tin', children: [
            SettingsItem(
              icon: Icons.info_outline_rounded,
              color: const Color(0xFFC084FC),
              title: 'Về AMV-WebManage',
              value: 'v1.0.0',
            ),
          ]),
          if (cloud)
            SettingsGroup(title: 'Vùng nguy hiểm', children: [
              SettingsItem(
                icon: Icons.logout_rounded,
                color: kRed,
                title: 'Đăng xuất',
                danger: true,
                onTap: _logout,
              ),
            ]),
        ],
      ),
    );
  }
}
