import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/format.dart';
import '../data/repository.dart';
import '../models/models.dart';
import 'ui.dart';

// Màu trạng thái: đủ sáng để nổi trên nền tối, vẫn đọc được trên nền sáng
const kRed = Color(0xFFF05463);
const kOrange = Color(0xFFFF9838);
const kGreen = Color(0xFF12B886); // xanh ngọc theo màu icon
const kGrey = Color(0xFF8B93B3);

/// Màu riêng cho từng loại dịch vụ (biểu đồ, ô icon).
Color typeColor(ServiceType t) => switch (t) {
      ServiceType.domain => const Color(0xFF38BDF8),
      ServiceType.hosting => const Color(0xFF4C82FF),
      ServiceType.vps => const Color(0xFFA78BFA),
      ServiceType.other => const Color(0xFFFF9838),
    };

Color stateColor(ExpiryState s) => switch (s) {
      ExpiryState.expired => kRed,
      ExpiryState.expiring => kOrange,
      ExpiryState.ok => kGreen,
      ExpiryState.cancelled => kGrey,
    };

/// Chip màu hiển thị số ngày còn lại.
class ExpiryChip extends StatelessWidget {
  const ExpiryChip(this.service, {super.key});
  final Service service;

  @override
  Widget build(BuildContext context) {
    final color = stateColor(service.state);
    final text = service.cancelled ? 'Đã ngừng' : daysLeftLabel(service.daysLeft);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text,
          style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12)),
    );
  }
}

class ServiceTile extends StatelessWidget {
  const ServiceTile({
    super.key,
    required this.service,
    required this.data,
    this.showOwner = true,
    this.trailing,
    this.dense = false,
    this.daysInSubtitle = false,
  });

  final Service service;
  final AppData data;
  final bool showOwner;
  final Widget? trailing;
  final bool dense;

  /// Hiện "Còn x ngày" ở dòng phụ thay vì chip bên phải (nhường chỗ cho tên dài).
  final bool daysInSubtitle;

  @override
  Widget build(BuildContext context) {
    final s = service;
    final color = stateColor(s.state);
    final where = s.parentVpsId != null
        ? 'trên ${data.service(s.parentVpsId)?.name ?? 'VPS'}'
        : data.vendor(s.vendorId)?.name;
    final parts = [
      if (showOwner) data.ownerName(s),
      ?where,
      'HH ${fmtDate(s.expiryDate)}',
    ];
    final hostings = s.type == ServiceType.vps ? data.hostingsOn(s.id!).length : 0;

    return ListTile(
      dense: dense,
      visualDensity: dense ? VisualDensity.compact : null,
      contentPadding: dense ? const EdgeInsets.only(left: 12, right: 12) : null,
      leading: IconTile(s.type.icon, color: color, size: dense ? 40 : 44),
      // Tên + nhãn loại (để phân biệt domain / hosting cùng tên)
      title: Row(
        children: [
          Flexible(
            child: Text(s.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: dense ? const TextStyle(fontSize: 15, fontWeight: FontWeight.w500) : null),
          ),
          const SizedBox(width: 6),
          TypeBadge(s.type),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(children: [
              TextSpan(text: parts.join(' · ')),
              if (daysInSubtitle)
                TextSpan(
                  text: '  ${s.cancelled ? 'Đã ngừng' : daysLeftLabel(s.daysLeft)}',
                  style: TextStyle(color: color, fontWeight: FontWeight.w600),
                ),
            ]),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (hostings > 0 && s.needsRenewal)
            Text('⚠ Ảnh hưởng $hostings hosting',
                style: const TextStyle(color: kRed, fontWeight: FontWeight.w600)),
        ],
      ),
      trailing: trailing ?? (daysInSubtitle ? null : ExpiryChip(s)),
      onTap: () => context.push('/service/${s.id}'),
    );
  }
}

/// Một dòng dữ liệu: nhãn bên trái, giá trị bên phải. Không hiện gì nếu [value] rỗng.
/// Nhãn nhỏ ghi loại dịch vụ: DOMAIN / HOSTING / VPS / KHÁC.
class TypeBadge extends StatelessWidget {
  const TypeBadge(this.type, {super.key});
  final ServiceType type;

  @override
  Widget build(BuildContext context) {
    final color = typeColor(type);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.45), width: 0.8),
      ),
      child: Text(
        type.label.toUpperCase(),
        style: TextStyle(
            fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.4, color: color),
      ),
    );
  }
}

class InfoRow extends StatelessWidget {
  const InfoRow(this.label, this.value, {super.key, this.onTap, this.copyable = false, this.valueColor});
  final String label;
  final String? value;
  final VoidCallback? onTap;
  final bool copyable;
  final Color? valueColor;

  bool get isEmpty => value == null || value!.isEmpty;

  @override
  Widget build(BuildContext context) {
    if (isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap ?? (copyable ? () => copyText(context, value!) : null),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant)),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                value!,
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: valueColor ?? (onTap != null ? scheme.primary : scheme.onSurface),
                ),
              ),
            ),
            if (copyable) ...[
              const SizedBox(width: 8),
              Icon(Icons.copy_rounded, size: 16, color: scheme.onSurfaceVariant),
            ] else if (onTap != null) ...[
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, size: 18, color: scheme.onSurfaceVariant),
            ],
          ],
        ),
      ),
    );
  }
}

/// Khối thông tin bo góc: tiêu đề có ô icon + các dòng nội dung ngăn bằng đường kẻ.
/// Các [InfoRow] rỗng tự bị bỏ; nếu không còn dòng nào thì hiện [empty] (hoặc ẩn cả khối).
class InfoSection extends StatelessWidget {
  const InfoSection({
    super.key,
    required this.title,
    required this.icon,
    required this.color,
    required this.children,
    this.action,
    this.empty,
  });

  final String title;
  final IconData icon;
  final Color color;
  final List<Widget> children;
  final Widget? action;
  final String? empty;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final items = children.where((w) => !(w is InfoRow && w.isEmpty)).toList();
    if (items.isEmpty && empty == null) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(14, 12, action == null ? 14 : 4, 12),
            child: Row(
              children: [
                IconTile(icon, color: color, size: 34),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(title,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
                ?action,
              ],
            ),
          ),
          Divider(height: 1, color: scheme.outlineVariant),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(empty!, style: TextStyle(color: scheme.onSurfaceVariant)),
            )
          else
            for (var i = 0; i < items.length; i++) ...[
              items[i],
              if (i < items.length - 1)
                Divider(height: 1, indent: 16, endIndent: 16, color: scheme.outlineVariant),
            ],
        ],
      ),
    );
  }
}

/// Nút "+ Thêm" nhỏ đặt ở góc phải tiêu đề section.
class SectionAddButton extends StatelessWidget {
  const SectionAddButton({super.key, required this.onPressed, this.label = 'Thêm'});
  final VoidCallback onPressed;
  final String label;

  @override
  Widget build(BuildContext context) => TextButton.icon(
        style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
        icon: const Icon(Icons.add_rounded, size: 18),
        label: Text(label),
        onPressed: onPressed,
      );
}

/// Ghi chú hiển thị, bỏ nhãn đánh dấu của lần nhập Excel.
String? displayNote(String? note) => emptyToNull(note?.replaceAll('[import VPS_Hosting.xlsx]', ''));

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.action});
  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(title,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(color: Theme.of(context).colorScheme.primary)),
          ),
          ?action,
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState(this.text, {super.key, this.icon = Icons.inbox_outlined});
  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 36, color: kGrey),
          const SizedBox(height: 8),
          Text(text, textAlign: TextAlign.center, style: const TextStyle(color: kGrey)),
        ],
      ),
    );
  }
}

/// Hiển thị AsyncValue: loading / lỗi (có nút thử lại) / dữ liệu.
class AsyncView<T> extends StatelessWidget {
  const AsyncView({super.key, required this.value, required this.builder, this.onRetry});
  final AsyncValue<T> value;
  final Widget Function(T data) builder;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return value.when(
      skipLoadingOnRefresh: true,
      skipLoadingOnReload: true,
      data: builder,
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 48, color: kGrey),
              const SizedBox(height: 8),
              Text('Không tải được dữ liệu\n$e', textAlign: TextAlign.center),
              if (onRetry != null) ...[
                const SizedBox(height: 12),
                FilledButton(onPressed: onRetry, child: const Text('Thử lại')),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

void showSnack(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

Future<bool> confirm(BuildContext context, String title, String message,
    {String ok = 'Đồng ý', bool danger = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Huỷ')),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: kRed) : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(ok),
        ),
      ],
    ),
  );
  return r ?? false;
}

/// Copy, tự xoá clipboard sau [clearAfter] nếu là dữ liệu nhạy cảm.
Future<void> copyText(BuildContext context, String text,
    {String message = 'Đã copy', Duration? clearAfter}) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) showSnack(context, message);
  if (clearAfter != null) {
    Future.delayed(clearAfter, () async {
      final current = await Clipboard.getData(Clipboard.kTextPlain);
      if (current?.text == text) await Clipboard.setData(const ClipboardData(text: ''));
    });
  }
}

Future<void> openUrl(BuildContext context, String url) async {
  final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) showSnack(context, 'Không mở được $url');
}

String _digits(String phone) => phone.replaceAll(RegExp(r'[^0-9+]'), '');

/// Nút gọi / SMS / Zalo cho khách hàng.
class ContactButtons extends StatelessWidget {
  const ContactButtons(this.customer, {super.key});
  final Customer customer;

  @override
  Widget build(BuildContext context) {
    final c = customer;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (c.phone != null)
          IconButton(
            tooltip: 'Gọi',
            icon: const Icon(Icons.call_outlined),
            onPressed: () => openUrl(context, 'tel:${_digits(c.phone!)}'),
          ),
        if (c.zaloPhone != null)
          IconButton(
            tooltip: 'Zalo',
            icon: const Icon(Icons.chat_bubble_outline),
            onPressed: () => openUrl(context, 'https://zalo.me/${_digits(c.zaloPhone!)}'),
          ),
      ],
    );
  }
}

/// Soạn tin nhắn nhắc gia hạn cho khách.
String buildReminderMessage(Customer c, List<Service> services) {
  final buf = StringBuffer('Chào ${c.name},\n');
  buf.writeln('Các dịch vụ sau sắp đến hạn gia hạn:');
  var total = 0;
  for (final s in services) {
    final price = s.sellPrice;
    if (price != null) total += price;
    buf.write('- ${s.type.label} ${s.name}: hết hạn ${fmtDate(s.expiryDate)}');
    if (price != null) buf.write(', phí ${fmtCycle(s.cycleMonths)}: ${fmtMoney(price)}');
    buf.writeln();
  }
  if (total > 0) buf.writeln('Tổng phí gia hạn: ${fmtMoney(total)}');
  buf.write('Anh/chị xác nhận giúp em để em gia hạn, tránh gián đoạn website nhé. Cảm ơn!');
  return buf.toString();
}

/// Copy tin nhắn nhắc gia hạn rồi mở Zalo của khách để dán.
Future<void> sendReminder(BuildContext context, Customer c, List<Service> services) async {
  final msg = buildReminderMessage(c, services);
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Tin nhắn nhắc gia hạn', style: Theme.of(ctx).textTheme.titleMedium),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(msg),
            ),
            const SizedBox(height: 12),
            if (c.zaloPhone != null)
              FilledButton.icon(
                icon: const Icon(Icons.chat_bubble_outline),
                label: const Text('Copy & mở Zalo'),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: msg));
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (context.mounted) {
                    showSnack(context, 'Đã copy tin nhắn, dán vào Zalo');
                    await openUrl(context, 'https://zalo.me/${_digits(c.zaloPhone!)}');
                  }
                },
              ),
            if (c.phone != null)
              OutlinedButton.icon(
                icon: const Icon(Icons.sms_outlined),
                label: const Text('Gửi SMS'),
                onPressed: () {
                  Navigator.pop(ctx);
                  openUrl(context, 'sms:${_digits(c.phone!)}?body=${Uri.encodeComponent(msg)}');
                },
              ),
            TextButton.icon(
              icon: const Icon(Icons.copy),
              label: const Text('Chỉ copy'),
              onPressed: () {
                Navigator.pop(ctx);
                copyText(context, msg, message: 'Đã copy tin nhắn');
              },
            ),
          ],
        ),
      ),
    ),
  );
}
