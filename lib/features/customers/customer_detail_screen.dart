import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/format.dart';
import '../../data/repository.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../../widgets/glass_nav_bar.dart';
import '../accounts/accounts_screen.dart';

class CustomerDetailScreen extends ConsumerWidget {
  const CustomerDetailScreen({super.key, required this.id});
  final String id;

  Future<void> _menu(BuildContext context, WidgetRef ref, String action, Customer c,
      List<Service> services) async {
    final repo = ref.read(repositoryProvider);
    try {
      switch (action) {
        case 'toggle':
          await repo.setCustomerActive(id, !c.isActive);
          ref.invalidate(appDataProvider);
        case 'delete':
          if (services.isNotEmpty) {
            showSnack(context, 'Khách còn ${services.length} dịch vụ. Hãy chọn "Ngừng khách hàng".');
            return;
          }
          if (!await confirm(context, 'Xoá khách hàng?', 'Xoá "${c.name}"? Không thể khôi phục.',
              ok: 'Xoá', danger: true)) {
            return;
          }
          await repo.deleteCustomer(id);
          ref.invalidate(appDataProvider);
          if (context.mounted) context.pop();
      }
    } catch (e) {
      if (context.mounted) showSnack(context, 'Lỗi: $e');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(appDataProvider);
    final data = async.value;
    final c = data?.customer(id);
    final services = data?.servicesOf(id) ?? [];

    return Scaffold(
      extendBody: true,
      bottomNavigationBar: const GlassNavBar(currentIndex: 2),
      appBar: AppBar(
        title: Text(c?.name ?? 'Khách hàng'),
        actions: [
          if (c != null) ...[
            IconButton(
              tooltip: 'Sửa',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => context.push('/customer/$id/edit'),
            ),
            PopupMenuButton<String>(
              onSelected: (v) => _menu(context, ref, v, c, services),
              itemBuilder: (_) => [
                PopupMenuItem(
                    value: 'toggle',
                    child: Text(c.isActive ? 'Ngừng khách hàng' : 'Kích hoạt lại')),
                const PopupMenuItem(
                    value: 'delete', child: Text('Xoá', style: TextStyle(color: kRed))),
              ],
            ),
          ],
        ],
      ),
      floatingActionButton: c == null
          ? null
          : FloatingActionButton.extended(
              icon: const Icon(Icons.add),
              label: const Text('Dịch vụ'),
              onPressed: () => context.push('/service/new?customerId=$id'),
            ),
      body: AsyncView(
        value: async,
        onRetry: () => ref.invalidate(appDataProvider),
        builder: (data) {
          if (c == null) return const EmptyState('Khách hàng không tồn tại');
          return _Body(data: data, customer: c, services: services);
        },
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.data, required this.customer, required this.services});
  final AppData data;
  final Customer customer;
  final List<Service> services;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = customer;
    final active = services.where((s) => !s.cancelled).toList();
    final due = active.where((s) => s.needsRenewal).toList();
    final yearly = active.fold<int>(
        0, (sum, s) => sum + ((s.sellPrice ?? 0) * 12 / s.cycleMonths).round());
    final accounts =
        (ref.watch(accountsProvider).value ?? []).where((a) => a.customerId == c.id).toList();

    final scheme = Theme.of(context).colorScheme;
    final color = due.isNotEmpty ? kOrange : Brand.accent;
    String digits(String p) => p.replaceAll(RegExp(r'[^0-9+]'), '');

    return ListView(
      padding: const EdgeInsets.only(top: 4, bottom: kNavBarSpace + 70),
      children: [
        // Thẻ đầu trang: avatar, tên, nút liên hệ nhanh
        Card(
          margin: const EdgeInsets.fromLTRB(16, 6, 16, 6),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [color.withValues(alpha: 0.18), Colors.transparent],
              ),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        gradient: Brand.tileGradient,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Text(c.name.isEmpty ? '?' : c.name.characters.first.toUpperCase(),
                          style: const TextStyle(
                              color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(c.name,
                              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 2),
                          Text(
                            [
                              if (c.company != null) c.company!,
                              '${active.length} dịch vụ',
                              if (!c.isActive) 'Đã ngừng',
                            ].join(' · '),
                            style: TextStyle(color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _ContactAction(
                      icon: Icons.call_rounded,
                      label: 'Gọi',
                      color: kGreen,
                      onTap: c.phone == null ? null : () => openUrl(context, 'tel:${digits(c.phone!)}'),
                    ),
                    const SizedBox(width: 8),
                    _ContactAction(
                      icon: Icons.chat_bubble_rounded,
                      label: 'Zalo',
                      color: Brand.accent,
                      onTap: c.zaloPhone == null
                          ? null
                          : () => openUrl(context, 'https://zalo.me/${digits(c.zaloPhone!)}'),
                    ),
                    const SizedBox(width: 8),
                    _ContactAction(
                      icon: Icons.mail_rounded,
                      label: 'Email',
                      color: const Color(0xFFA78BFA),
                      onTap: c.email == null ? null : () => openUrl(context, 'mailto:${c.email}'),
                    ),
                  ],
                ),
                if (due.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: kOrange),
                    icon: const Icon(Icons.send_rounded, size: 18),
                    label: Text('Nhắn nhắc gia hạn (${due.length} dịch vụ)'),
                    onPressed: () => sendReminder(context, c, due),
                  ),
                ],
              ],
            ),
          ),
        ),

        InfoSection(
          title: 'Thông tin liên hệ',
          icon: Icons.contact_phone_rounded,
          color: kGreen,
          empty: 'Chưa có thông tin liên hệ',
          children: [
            InfoRow('Điện thoại', c.phone, copyable: true),
            InfoRow('Zalo', c.zalo, copyable: true),
            InfoRow('Email', c.email, copyable: true),
            InfoRow('Công ty', c.company),
            InfoRow('Ghi chú', displayNote(c.note)),
          ],
        ),

        InfoSection(
          title: 'Tổng quan',
          icon: Icons.insights_rounded,
          color: Brand.accent,
          children: [
            InfoRow('Dịch vụ đang dùng', '${active.length}'),
            InfoRow('Cần gia hạn', '${due.length}', valueColor: due.isEmpty ? kGreen : kOrange),
            InfoRow('Doanh thu / năm', yearly > 0 ? fmtMoney(yearly) : null, valueColor: kGreen),
          ],
        ),

        InfoSection(
          title: 'Dịch vụ (${services.length})',
          icon: Icons.dns_rounded,
          color: typeColor(ServiceType.hosting),
          empty: 'Chưa có dịch vụ',
          action: SectionAddButton(onPressed: () => context.push('/service/new?customerId=${c.id}')),
          children: [
            for (final s in services) ServiceTile(service: s, data: data, showOwner: false, dense: true),
          ],
        ),

        InfoSection(
          title: 'Tài khoản (${accounts.length})',
          icon: Icons.key_rounded,
          color: Brand.mint,
          empty: 'Chưa lưu tài khoản nào',
          action: SectionAddButton(onPressed: () => context.push('/account/new?customerId=${c.id}')),
          children: [for (final a in accounts) AccountTile(account: a, data: data)],
        ),
      ],
    );
  }
}

class _ContactAction extends StatelessWidget {
  const _ContactAction({required this.icon, required this.label, required this.color, this.onTap});
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onTap != null;
    final c = enabled ? color : scheme.onSurfaceVariant.withValues(alpha: 0.5);
    return Expanded(
      child: Material(
        color: scheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              children: [
                Icon(icon, color: c, size: 22),
                const SizedBox(height: 4),
                Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
