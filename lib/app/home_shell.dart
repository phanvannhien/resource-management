import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/repository.dart';
import '../data/storage_switch.dart';
import '../data/sync.dart';
import '../data/vault.dart';
import '../widgets/common.dart';
import '../widgets/glass_nav_bar.dart';

/// Khung 5 tab dưới. Mỗi lần app quay lại foreground thì tải lại dữ liệu
/// (= kiểm tra lại hạn), và khoá kho mật khẩu nếu rời app quá 5 phút.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  static const _autoLockAfter = Duration(minutes: 5);
  late final AppLifecycleListener _lifecycle;
  DateTime? _pausedAt;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onHide: () => _pausedAt = DateTime.now(),
      onShow: () {
        final paused = _pausedAt;
        _pausedAt = null;
        if (paused != null && DateTime.now().difference(paused) > _autoLockAfter) {
          ref.read(vaultProvider.notifier).lock();
        }
        ref.invalidate(appDataProvider);
        ref.invalidate(accountsProvider);
        _sync();
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _afterOpen());
  }

  /// Sau khi vào app: chép dữ liệu trên máy lên Supabase nếu đang chờ, rồi đồng bộ WebDAV.
  Future<void> _afterOpen() async {
    try {
      final n = await uploadPendingLocal(ref);
      if (n != null && mounted) showSnack(context, 'Đã chép dữ liệu trên máy lên Supabase ($n dịch vụ)');
    } catch (e) {
      if (mounted) showSnack(context, 'Chưa chép được dữ liệu lên Supabase: $e');
    }
    await _sync();
  }

  /// Chế độ lưu trên máy + đã bật WebDAV: lấy bản mới nhất từ máy chủ.
  Future<void> _sync() async {
    if (ref.read(syncProvider).phase == SyncPhase.off) return;
    if (await ref.read(syncProvider.notifier).syncNow() && mounted) refreshAllData(ref);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: widget.shell,
      bottomNavigationBar: GlassNavBar(
        currentIndex: widget.shell.currentIndex,
        onSelect: (i) => widget.shell.goBranch(i, initialLocation: i == widget.shell.currentIndex),
      ),
    );
  }
}
