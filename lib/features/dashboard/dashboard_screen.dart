import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/format.dart';
import '../../data/accounting.dart';
import '../../data/repository.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../../widgets/glass_nav_bar.dart';
import '../../widgets/ui.dart';
import '../services/renew_sheet.dart';
import '../services/services_screen.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(appDataProvider);
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 76,
        title: PageTitle('Tổng quan',
            icon: Icons.dashboard_rounded, subtitle: 'Hôm nay, ${fmtDate(today())}'),
        actions: [
          SquareIconButton(
            icon: Icons.settings_outlined,
            tooltip: 'Cài đặt',
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(appDataProvider.future),
        child: AsyncView(
          value: async,
          onRetry: () => ref.invalidate(appDataProvider),
          builder: (data) => _DashboardBody(data),
        ),
      ),
    );
  }
}

class _DashboardBody extends ConsumerWidget {
  const _DashboardBody(this.data);
  final AppData data;

  void _openFiltered(BuildContext context, WidgetRef ref, StateFilter f) {
    ref.read(serviceFilterProvider.notifier).set(ServiceFilter(state: f));
    context.go('/services');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = data.services.where((s) => !s.cancelled).toList();
    final expired = active.where((s) => s.state == ExpiryState.expired).length;
    final expiring = active.where((s) => s.state == ExpiryState.expiring).length;
    final ok = active.where((s) => s.state == ExpiryState.ok).length;
    final year = today().year;
    final txns = ref.watch(transactionsProvider).value ?? const <Txn>[];
    final revenue = LedgerReport.build(data, txns, year, Basis.accrual).income;

    // Nhóm dịch vụ cần gia hạn theo khách; "Của tôi" (customerId = null) luôn đứng đầu.
    final due = active.where((s) => s.needsRenewal).toList()
      ..sort((a, b) => a.expiryDate.compareTo(b.expiryDate));
    final groups = <String?, List<Service>>{};
    for (final s in due) {
      groups.putIfAbsent(s.customerId, () => []).add(s);
    }
    final keys = groups.keys.toList()
      ..sort((a, b) {
        if (a == null) return -1;
        if (b == null) return 1;
        return groups[a]!.first.expiryDate.compareTo(groups[b]!.first.expiryDate);
      });

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(top: 4, bottom: kNavBarSpace),
      children: [
        StatGrid(children: [
          StatCard(
            icon: Icons.error_outline_rounded,
            value: '$expired',
            label: 'Quá hạn',
            color: kRed,
            onTap: () => _openFiltered(context, ref, StateFilter.expired),
          ),
          StatCard(
            icon: Icons.schedule_rounded,
            value: '$expiring',
            label: 'Sắp hết hạn (≤ 15 ngày)',
            color: kOrange,
            onTap: () => _openFiltered(context, ref, StateFilter.expiring),
          ),
          StatCard(
            icon: Icons.check_circle_outline_rounded,
            value: '$ok',
            label: 'Đang hoạt động',
            color: kGreen,
            onTap: () => _openFiltered(context, ref, StateFilter.all),
          ),
          StatCard(
            icon: Icons.payments_outlined,
            value: fmtMoneyShort(revenue),
            label: 'Doanh thu $year',
            color: Brand.accent,
            onTap: () => context.go('/reports'),
          ),
        ]),
        const SectionTitle('Thống kê'),
        _Summary(data),
        const SectionTitle('Truy cập nhanh'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              for (final (i, t) in ServiceType.values.where((t) => t != ServiceType.other).indexed) ...[
                if (i > 0) const SizedBox(width: 10),
                Expanded(
                  child: _QuickAction(
                    icon: t.icon,
                    label: '+ ${t.label}',
                    color: typeColor(t),
                    onTap: () => context.push('/service/new?type=${t.db}'),
                  ),
                ),
              ],
              const SizedBox(width: 10),
              Expanded(
                child: _QuickAction(
                  icon: Icons.person_add_alt_1_rounded,
                  label: '+ Khách',
                  color: Brand.mint,
                  onTap: () => context.push('/customer/new'),
                ),
              ),
            ],
          ),
        ),
        SectionTitle('Cần gia hạn (${due.length})'),
        if (due.isEmpty)
          const Card(
            child: EmptyState('Không có dịch vụ nào cần gia hạn 🎉', icon: Icons.check_circle_outline),
          ),
        for (final k in keys) _GroupCard(data: data, customerId: k, services: groups[k]!),
      ],
    );
  }
}

/// Tổng số khách hàng + số dịch vụ đang dùng theo từng loại. Bấm để mở danh sách đã lọc.
class _Summary extends ConsumerWidget {
  const _Summary(this.data);
  final AppData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final active = data.services.where((s) => !s.cancelled).toList();
    final customers = data.customers.where((c) => c.isActive).length;
    int count(ServiceType t) => active.where((s) => s.type == t).length;

    void openType(ServiceType? t) {
      ref.read(serviceFilterProvider.notifier).set(ServiceFilter(type: t));
      context.go('/services');
    }

    return Card(
      child: Column(
        children: [
          // Hàng trên: khách hàng | tổng dịch vụ
          IntrinsicHeight(
            child: Row(
              children: [
                Expanded(
                  child: _SummaryTotal(
                    icon: Icons.people_alt_rounded,
                    color: Brand.mint,
                    value: customers,
                    label: 'Khách hàng',
                    onTap: () => context.go('/customers'),
                  ),
                ),
                VerticalDivider(width: 1, color: scheme.outlineVariant),
                Expanded(
                  child: _SummaryTotal(
                    icon: Icons.inventory_2_rounded,
                    color: Brand.accent,
                    value: active.length,
                    label: 'Dịch vụ',
                    onTap: () => openType(null),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: scheme.outlineVariant),
          // Hàng dưới: số dịch vụ theo loại
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                for (final t in ServiceType.values)
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => openType(t),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Column(
                          children: [
                            IconTile(t.icon, color: typeColor(t), size: 36),
                            const SizedBox(height: 6),
                            Text('${count(t)}',
                                style: TextStyle(
                                    fontSize: 20, fontWeight: FontWeight.w800, color: typeColor(t))),
                            Text(t == ServiceType.other ? 'Bảo trì/khác' : t.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryTotal extends StatelessWidget {
  const _SummaryTotal({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final int value;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            IconTile(icon, color: color, size: 42),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$value',
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: color)),
                  Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12.5, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({required this.icon, required this.label, required this.color, required this.onTap});
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            children: [
              IconTile(
                icon,
                color: color,
                size: 46,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color.lerp(color, Colors.white, 0.15)!, color],
                ),
              ),
              const SizedBox(height: 8),
              Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.data, required this.customerId, required this.services});
  final AppData data;
  final String? customerId;
  final List<Service> services;

  @override
  Widget build(BuildContext context) {
    final customer = data.customer(customerId);
    final theme = Theme.of(context);
    const compact = VisualDensity.compact;

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Tiêu đề khách: tên + gọi / Zalo / nhắn nhắc trên cùng 1 dòng
          InkWell(
            onTap: customer == null ? null : () => context.push('/customer/${customer.id}'),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 4, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      customer?.name ?? 'CỦA TÔI',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: customer == null ? kRed : theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                  if (customer != null) ...[
                    if (customer.phone != null)
                      IconButton(
                        visualDensity: compact,
                        tooltip: 'Gọi',
                        icon: const Icon(Icons.call_outlined, size: 20),
                        onPressed: () => openUrl(context, 'tel:${customer.phone}'),
                      ),
                    IconButton(
                      visualDensity: compact,
                      tooltip: 'Nhắn nhắc gia hạn',
                      icon: const Icon(Icons.send_outlined, size: 20),
                      onPressed: () => sendReminder(context, customer, services),
                    ),
                  ] else
                    const SizedBox(height: 40),
                ],
              ),
            ),
          ),
          for (final s in services)
            ServiceTile(
              service: s,
              data: data,
              showOwner: false,
              dense: true,
              daysInSubtitle: true,
              trailing: IconButton(
                visualDensity: compact,
                tooltip: 'Gia hạn',
                icon: const Icon(Icons.autorenew),
                onPressed: () => showRenewSheet(context, s),
              ),
            ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}
