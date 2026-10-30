import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/repository.dart';
import 'common.dart';

/// Khoảng trống cần chừa ở cuối danh sách để nội dung không bị thanh menu che.
const kNavBarSpace = 120.0;

/// Nút nổi (FAB) trong các tab nằm trong khung chính không tự né thanh menu,
/// nên bọc bằng widget này để đẩy lên phía trên thanh menu.
class NavBarFab extends StatelessWidget {
  const NavBarFab({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.only(bottom: 92), child: child);
}

class _Tab {
  const _Tab(this.path, this.label, this.icon, this.activeIcon);
  final String path;
  final String label;
  final IconData icon;
  final IconData activeIcon;
}

const _tabs = [
  _Tab('/dashboard', 'Tổng quan', Icons.dashboard_outlined, Icons.dashboard_rounded),
  _Tab('/services', 'Dịch vụ', Icons.dns_outlined, Icons.dns_rounded),
  _Tab('/customers', 'Khách', Icons.people_outline_rounded, Icons.people_rounded),
  _Tab('/accounts', 'Tài khoản', Icons.key_outlined, Icons.key_rounded),
  _Tab('/reports', 'Kế toán', Icons.account_balance_wallet_outlined, Icons.account_balance_wallet_rounded),
];

/// Thanh menu dưới dạng khối kính mờ bo tròn (kiểu liquid glass), nổi trên nội dung.
///
/// Dùng trong `Scaffold(extendBody: true, bottomNavigationBar: GlassNavBar(...))`.
/// [currentIndex] null = không tab nào được chọn (vd: màn cài đặt).
/// [onSelect] null = chuyển tab bằng `context.go` (dùng ở các màn chi tiết).
class GlassNavBar extends ConsumerWidget {
  const GlassNavBar({super.key, this.currentIndex, this.onSelect});
  final int? currentIndex;
  final ValueChanged<int>? onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final due = ref.watch(appDataProvider).value?.services.where((s) => s.needsRenewal).length ?? 0;
    const radius = BorderRadius.all(Radius.circular(30));

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
        child: DecoratedBox(
          // Bóng đổ nằm ngoài vùng cắt để không bị mất
          decoration: BoxDecoration(
            borderRadius: radius,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: dark ? 0.45 : 0.15),
                blurRadius: 30,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: radius,
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
              child: Container(
                height: 70,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  borderRadius: radius,
                  // Lớp kính: trong suốt, hơi sáng hơn ở trên
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: dark
                        ? [const Color(0x3A2A3566), const Color(0x661A2040)]
                        : [const Color(0xCCFFFFFF), const Color(0x99F1F4FB)],
                  ),
                  border: Border.all(
                    color: dark ? Colors.white.withValues(alpha: 0.14) : Colors.white,
                    width: 1,
                  ),
                ),
                child: Stack(
                  children: [
                    // Ánh phản quang mảnh ở mép trên
                    Positioned(
                      left: 24,
                      right: 24,
                      top: 0,
                      height: 1.2,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [
                            Colors.white.withValues(alpha: 0),
                            Colors.white.withValues(alpha: dark ? 0.45 : 0.9),
                            Colors.white.withValues(alpha: 0),
                          ]),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        for (var i = 0; i < _tabs.length; i++)
                          Expanded(
                            child: _NavItem(
                              tab: _tabs[i],
                              selected: i == currentIndex,
                              badge: i == 0 ? due : 0,
                              dark: dark,
                              primary: scheme.primary,
                              muted: scheme.onSurfaceVariant,
                              onTap: () {
                                if (onSelect != null) {
                                  onSelect!(i);
                                } else {
                                  context.go(_tabs[i].path);
                                }
                              },
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.tab,
    required this.selected,
    required this.badge,
    required this.dark,
    required this.primary,
    required this.muted,
    required this.onTap,
  });

  final _Tab tab;
  final bool selected;
  final int badge;
  final bool dark;
  final Color primary;
  final Color muted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? primary : muted;
    return Semantics(
      button: true,
      selected: selected,
      label: tab.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
            margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              // "Viên" sáng cho tab đang chọn
              gradient: selected
                  ? LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        primary.withValues(alpha: dark ? 0.30 : 0.18),
                        primary.withValues(alpha: dark ? 0.16 : 0.08),
                      ],
                    )
                  : null,
              border: Border.all(
                color: selected
                    ? Colors.white.withValues(alpha: dark ? 0.16 : 0.7)
                    : Colors.transparent,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Badge(
                  isLabelVisible: badge > 0,
                  label: Text('$badge'),
                  backgroundColor: kRed,
                  child: AnimatedScale(
                    scale: selected ? 1.1 : 1,
                    duration: const Duration(milliseconds: 260),
                    child: Icon(selected ? tab.activeIcon : tab.icon, color: color, size: 22),
                  ),
                ),
                const SizedBox(height: 3),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    tab.label,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
