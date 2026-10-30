import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/format.dart';
import '../../data/repository.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../../widgets/glass_nav_bar.dart';
import '../../widgets/ui.dart';
import '../accounts/accounts_screen.dart';
import '../reports/reports_screen.dart';
import '../reports/txn_sheet.dart';
import 'renew_sheet.dart';

class ServiceDetailScreen extends ConsumerWidget {
  const ServiceDetailScreen({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(appDataProvider);
    final service = async.value?.service(id);

    return Scaffold(
      extendBody: true,
      bottomNavigationBar: const GlassNavBar(currentIndex: 1),
      appBar: AppBar(
        title: Text(service?.name ?? 'Dịch vụ'),
        actions: [
          if (service != null) ...[
            IconButton(
              tooltip: 'Sửa',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => context.push('/service/$id/edit'),
            ),
            _MoreMenu(service),
          ],
        ],
      ),
      body: AsyncView(
        value: async,
        onRetry: () => ref.invalidate(appDataProvider),
        builder: (data) {
          final s = data.service(id);
          if (s == null) return const EmptyState('Dịch vụ không tồn tại hoặc đã bị xoá');
          return _Body(data: data, service: s);
        },
      ),
    );
  }
}

class _MoreMenu extends ConsumerWidget {
  const _MoreMenu(this.service);
  final Service service;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(repositoryProvider);
    return PopupMenuButton<String>(
      onSelected: (v) async {
        try {
          switch (v) {
            case 'toggle':
              await repo.setServiceCancelled(service.id!, !service.cancelled);
              ref.invalidate(appDataProvider);
            case 'delete':
              final ok = await confirm(context, 'Xoá dịch vụ?',
                  'Xoá "${service.name}" và toàn bộ lịch sử gia hạn. Không thể khôi phục.\n'
                      'Nếu chỉ không dùng nữa, hãy chọn "Ngừng dịch vụ".',
                  ok: 'Xoá', danger: true);
              if (!ok) return;
              await repo.deleteService(service.id!);
              ref.invalidate(appDataProvider);
              if (context.mounted) context.pop();
          }
        } catch (e) {
          if (context.mounted) showSnack(context, 'Lỗi: $e');
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'toggle',
          child: Text(service.cancelled ? 'Dùng lại dịch vụ' : 'Ngừng dịch vụ (không nhắc nữa)'),
        ),
        const PopupMenuItem(value: 'delete', child: Text('Xoá', style: TextStyle(color: kRed))),
      ],
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.data, required this.service});
  final AppData data;
  final Service service;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = service;
    final customer = data.customer(s.customerId);
    final parent = data.service(s.parentVpsId);
    final linked = data.service(s.linkedHostingId);
    final hostings = s.type == ServiceType.vps ? data.hostingsOn(s.id!) : <Service>[];
    final domainsOnThis = s.type == ServiceType.hosting
        ? data.services.where((d) => d.linkedHostingId == s.id && !d.cancelled).toList()
        : <Service>[];
    final accounts =
        (ref.watch(accountsProvider).value ?? []).where((a) => a.serviceId == s.id).toList();
    final ledger =
        (ref.watch(transactionsProvider).value ?? const <Txn>[]).where((t) => t.serviceId == s.id).toList();
    final scheme = Theme.of(context).colorScheme;
    final color = stateColor(s.state);
    final profit = (s.sellPrice != null && s.costPrice != null) ? s.sellPrice! - s.costPrice! : null;
    final daysText = s.cancelled
        ? 'Đã ngừng'
        : s.daysLeft < 0
            ? 'Quá ${-s.daysLeft} ngày'
            : '${s.daysLeft} ngày';

    return ListView(
      padding: const EdgeInsets.only(top: 4, bottom: kNavBarSpace),
      children: [
        // Thẻ đầu trang: tên, loại, 3 ô số liệu, nút thao tác
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    IconTile(s.type.icon, color: color, size: 52),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.name,
                              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 2),
                          Text('${s.type.label} · ${data.ownerName(s)}',
                              style: TextStyle(color: scheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _MiniStat(label: 'Hết hạn', value: fmtDate(s.expiryDate), color: color),
                    const SizedBox(width: 8),
                    _MiniStat(label: s.daysLeft < 0 ? 'Trạng thái' : 'Còn lại', value: daysText, color: color),
                    const SizedBox(width: 8),
                    // Dịch vụ của mình: hiện chi phí; của khách: hiện giá bán
                    _MiniStat(
                      label: '${s.isMine ? 'Chi phí' : 'Giá'} / ${fmtCycle(s.cycleMonths)}',
                      value: switch (s.isMine ? s.costPrice : s.sellPrice) {
                        null => '—',
                        final v => fmtMoneyShort(v),
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        icon: const Icon(Icons.autorenew, size: 18),
                        label: const Text('Gia hạn'),
                        onPressed: () => showRenewSheet(context, s),
                      ),
                    ),
                    if (customer != null) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.send_outlined, size: 18),
                          label: const Text('Nhắn nhắc'),
                          onPressed: () => sendReminder(context, customer, [s]),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),

        // Cảnh báo: hosting có hạn dài hơn VPS cha
        if (parent != null && !s.cancelled && parent.expiryDate.isBefore(s.expiryDate))
          Card(
            color: Color.alphaBlend(kOrange.withValues(alpha: 0.12), scheme.surfaceContainer),
            child: ListTile(
              leading: const IconTile(Icons.warning_amber_rounded, color: kOrange, size: 38),
              title: Text('VPS ${parent.name} hết hạn ${fmtDate(parent.expiryDate)}, '
                  'trước hạn của hosting này'),
              onTap: () => context.push('/service/${parent.id}'),
            ),
          ),

        InfoSection(
          title: 'Thông tin chung',
          icon: Icons.info_outline_rounded,
          color: Brand.accent,
          children: [
            InfoRow('Khách hàng', customer?.name ?? 'Của tôi',
                onTap: customer == null ? null : () => context.push('/customer/${customer.id}')),
            InfoRow('Loại dịch vụ', s.type.label),
            InfoRow('Nhà cung cấp', data.vendor(s.vendorId)?.name),
            InfoRow('Chạy trên VPS', parent?.name,
                onTap: parent == null ? null : () => context.push('/service/${parent.id}')),
            InfoRow('Trỏ về hosting', linked?.name,
                onTap: linked == null ? null : () => context.push('/service/${linked.id}')),
            InfoRow('Trạng thái', s.cancelled ? 'Đã ngừng' : 'Đang dùng',
                valueColor: s.cancelled ? kGrey : kGreen),
            InfoRow('Ghi chú', displayNote(s.note)),
          ],
        ),

        InfoSection(
          title: 'Thời hạn & chi phí',
          icon: Icons.event_note_rounded,
          color: kOrange,
          children: [
            InfoRow('Ngày đăng ký', s.startDate == null ? null : fmtDate(s.startDate)),
            InfoRow('Ngày hết hạn', fmtDate(s.expiryDate), valueColor: color),
            InfoRow('Chu kỳ gia hạn', fmtCycle(s.cycleMonths)),
            InfoRow('Nhắc trước', '${s.notifyDays} ngày'),
            InfoRow('Giá vốn', s.costPrice == null ? null : fmtMoney(s.costPrice)),
            InfoRow('Giá bán', s.sellPrice == null ? null : fmtMoney(s.sellPrice)),
            InfoRow('Lợi nhuận / kỳ', profit == null ? null : fmtMoney(profit),
                valueColor: profit != null && profit < 0 ? kRed : kGreen),
          ],
        ),

        InfoSection(
          title: 'Thông số kỹ thuật',
          icon: Icons.memory_rounded,
          color: const Color(0xFFA78BFA),
          children: [
            InfoRow('IP', s.ip, copyable: true),
            InfoRow('Hệ điều hành', s.os),
            InfoRow('Cấu hình', _spec(s)),
            InfoRow('Panel', s.panel),
            InfoRow('Nameservers', s.nameservers, copyable: true),
          ],
        ),

        if (s.type == ServiceType.vps)
          InfoSection(
            title: 'Hosting trên VPS này (${hostings.length})',
            icon: Icons.dns_rounded,
            color: typeColor(ServiceType.hosting),
            empty: 'Chưa có hosting nào',
            action: SectionAddButton(
              onPressed: () => context.push('/service/new?type=HOSTING&parentVpsId=${s.id}'),
            ),
            children: [for (final h in hostings) ServiceTile(service: h, data: data, dense: true)],
          ),

        if (domainsOnThis.isNotEmpty)
          InfoSection(
            title: 'Domain trỏ về (${domainsOnThis.length})',
            icon: Icons.language_rounded,
            color: typeColor(ServiceType.domain),
            children: [for (final d in domainsOnThis) ServiceTile(service: d, data: data, dense: true)],
          ),

        InfoSection(
          title: 'Tài khoản (${accounts.length})',
          icon: Icons.key_rounded,
          color: Brand.mint,
          empty: 'Chưa lưu tài khoản nào (cPanel, SSH, FTP...)',
          action: SectionAddButton(
            onPressed: () => context.push(
                '/account/new?serviceId=${s.id}${s.customerId != null ? '&customerId=${s.customerId}' : ''}'),
          ),
          children: [for (final a in accounts) AccountTile(account: a, data: data)],
        ),

        InfoSection(
          title: 'Sổ thu chi (${ledger.length})',
          icon: Icons.account_balance_wallet_rounded,
          color: kGreen,
          empty: 'Chưa có khoản thu chi nào',
          action: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Nhập các kỳ trước',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.history_rounded, size: 20),
                onPressed: () => context.push('/accounting/backfill?serviceId=${s.id}'),
              ),
              SectionAddButton(onPressed: () => showTxnSheet(context, serviceId: s.id)),
            ],
          ),
          children: [for (final t in ledger) TxnTile(txn: t, data: data, showService: false)],
        ),

        InfoSection(
          title: 'Lịch sử gia hạn',
          icon: Icons.history_rounded,
          color: const Color(0xFF38BDF8),
          children: [_RenewalHistory(s.id!)],
        ),
      ],
    );
  }

  String? _spec(Service s) {
    final parts = [
      if (s.cpu != null) '${s.cpu} CPU',
      if (s.ramGb != null) '${_num(s.ramGb!)} GB RAM',
      if (s.diskGb != null) '${s.diskGb} GB disk',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  String _num(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();
}

class _RenewalHistory extends ConsumerWidget {
  const _RenewalHistory(this.serviceId);
  final String serviceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final async = ref.watch(renewalsProvider(serviceId));
    return async.when(
      loading: () => const Padding(
          padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
      error: (e, _) => Padding(padding: const EdgeInsets.all(16), child: Text('Lỗi: $e')),
      data: (list) {
        if (list.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Chưa gia hạn lần nào', style: TextStyle(color: scheme.onSurfaceVariant)),
          );
        }
        return Column(
          children: [
            for (var i = 0; i < list.length; i++) ...[
              ListTile(
                title: Text('${fmtDate(list[i].oldExpiry)} → ${fmtDate(list[i].newExpiry)}',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _Tag('+${fmtCycle(list[i].months)}', Brand.accent),
                      _Tag(list[i].customerPaid ? 'Khách đã trả' : 'Khách chưa trả',
                          list[i].customerPaid ? kGreen : kOrange),
                      _Tag(list[i].providerPaid ? 'Đã trả NCC' : 'Chưa trả NCC',
                          list[i].providerPaid ? kGreen : kOrange),
                    ],
                  ),
                ),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(list[i].amount == null ? '—' : fmtMoney(list[i].amount),
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text(fmtDate(list[i].renewedAt),
                        style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
              if (i < list.length - 1)
                Divider(height: 1, indent: 16, endIndent: 16, color: scheme.outlineVariant),
            ],
          ],
        );
      },
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, this.color);
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(text, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
      );
}

/// Ô số liệu nhỏ trong thẻ đầu trang.
class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value, this.color});
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value,
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w800, color: color ?? scheme.onSurface)),
            ),
          ],
        ),
      ),
    );
  }
}
