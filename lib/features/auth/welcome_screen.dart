import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../data/storage_config.dart';
import '../../data/storage_switch.dart';
import '../../widgets/common.dart';
import '../../widgets/ui.dart';
import '../settings/backup_actions.dart';
import '../settings/storage_screen.dart';

/// Màn đầu tiên khi cài app: chọn lưu dữ liệu trên máy hay trên Supabase.
class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  StorageMode _mode = StorageMode.local;
  bool _busy = false;

  Future<void> _continue({bool restore = false}) async {
    setState(() => _busy = true);
    try {
      if (_mode == StorageMode.local) {
        // Khôi phục vào file trên máy trước, rồi mới vào app (router chuyển màn ngay khi đổi nơi lưu).
        if (restore && !await importBackup(context, ref)) return;
        await switchToLocal(ref, copy: false);
      } else {
        final cfg = ref.read(storageConfigProvider);
        final counts = await localDataCount();
        if (!mounted) return;
        final r = await showModalBottomSheet<({String url, String key, bool copy})>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          builder: (_) => SupabaseConnectSheet(
            initialUrl: cfg.supabaseUrl,
            initialKey: cfg.supabaseKey,
            localCustomers: counts.customers,
            localServices: counts.services,
          ),
        );
        if (r != null) await switchToCloud(ref, url: r.url, key: r.key, copyLocal: r.copy);
      }
    } catch (e) {
      if (mounted) showSnack(context, 'Lỗi: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
          children: [
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Image.asset('assets/icon/icon.png', width: 88, height: 88),
              ),
            ),
            const SizedBox(height: 18),
            const Text('Chào mừng đến AMV-WebManage',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text('Chọn nơi lưu dữ liệu. Bạn có thể đổi lại bất cứ lúc nào trong Cài đặt.',
                textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 24),
            _OptionCard(
              selected: _mode == StorageMode.local,
              icon: Icons.phone_iphone_rounded,
              title: 'Lưu trên máy này',
              points: const [
                'Không cần tài khoản, dùng được khi không có mạng',
                'Đồng bộ qua WebDAV (cPanel Web Disk, Nextcloud…)',
                'Sao lưu file lên Google Drive / iCloud',
              ],
              onTap: () => setState(() => _mode = StorageMode.local),
            ),
            const SizedBox(height: 12),
            _OptionCard(
              selected: _mode == StorageMode.cloud,
              icon: Icons.cloud_rounded,
              title: 'Supabase (đám mây)',
              points: const [
                'Đồng bộ tức thì giữa điện thoại, Mac, iPhone',
                'Đăng nhập bằng email, bảo mật theo tài khoản',
                'Dùng Supabase của bạn (gói miễn phí)',
              ],
              onTap: () => setState(() => _mode = StorageMode.cloud),
            ),
            const SizedBox(height: 24),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              onPressed: _busy ? null : () => _continue(),
              child: _busy
                  ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Tiếp tục', style: TextStyle(fontSize: 16)),
            ),
            if (_mode == StorageMode.local)
              TextButton(
                onPressed: _busy ? null : () => _continue(restore: true),
                child: const Text('Đã có file sao lưu? Khôi phục từ file'),
              ),
          ],
        ),
      ),
    );
  }
}

class _OptionCard extends StatelessWidget {
  const _OptionCard({
    required this.selected,
    required this.icon,
    required this.title,
    required this.points,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String title;
  final List<String> points;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? scheme.primary.withValues(alpha: 0.14) : scheme.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(
          color: selected ? scheme.primary : scheme.outlineVariant,
          width: selected ? 1.6 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconTile(icon, color: Brand.accent, size: 46, gradient: selected ? Brand.tileGradient : null),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    for (final p in points)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.check_rounded, size: 16, color: Brand.mint.withValues(alpha: 0.9)),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(p,
                                  style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              Icon(
                selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                color: selected ? scheme.primary : scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
