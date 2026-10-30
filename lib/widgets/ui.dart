import 'package:flutter/material.dart';

import '../app/theme.dart';

/// Ô icon bo vuông nền màu nhạt (hoặc gradient).
class IconTile extends StatelessWidget {
  const IconTile(this.icon, {super.key, required this.color, this.size = 44, this.gradient});
  final IconData icon;
  final Color color;
  final double size;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: gradient == null ? color.withValues(alpha: 0.16) : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Icon(icon, size: size * 0.5, color: gradient == null ? color : Colors.white),
    );
  }
}

/// Tiêu đề trang: ô icon gradient + tiêu đề lớn + dòng phụ. Dùng làm `title` của AppBar.
class PageTitle extends StatelessWidget {
  const PageTitle(this.title, {super.key, required this.icon, this.subtitle});
  final String title;
  final IconData icon;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        IconTile(icon, color: Brand.blue, size: 46, gradient: Brand.tileGradient),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title,
                  style: TextStyle(
                      fontSize: 24, fontWeight: FontWeight.w800, color: scheme.onSurface)),
              if (subtitle != null)
                Text(subtitle!,
                    style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ],
    );
  }
}

/// Nút icon dạng ô vuông viền mảnh (dùng ở góc phải tiêu đề).
class SquareIconButton extends StatelessWidget {
  const SquareIconButton({super.key, required this.icon, required this.onPressed, this.tooltip, this.badge});
  final IconData icon;
  final VoidCallback onPressed;
  final String? tooltip;
  final int? badge;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Badge(
        isLabelVisible: (badge ?? 0) > 0,
        label: Text('${badge ?? 0}'),
        child: Material(
          color: scheme.surfaceContainer,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: scheme.outlineVariant),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onPressed,
            child: Tooltip(
              message: tooltip ?? '',
              child: SizedBox(width: 46, height: 46, child: Icon(icon, size: 22)),
            ),
          ),
        ),
      ),
    );
  }
}

/// Thẻ số liệu: ô icon + số lớn + nhãn, viền và nền tô theo [color].
class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
    this.onTap,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const radius = BorderRadius.all(Radius.circular(22));
    return DecoratedBox(
      // Kính có ánh màu: đậm ở góc trên-trái, nhạt dần xuống dưới
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color.withValues(alpha: 0.24), color.withValues(alpha: 0.05)],
        ),
        border: Border.all(color: color.withValues(alpha: 0.42)),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconTile(icon, color: color, size: 36),
                const SizedBox(height: 10),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(value,
                      style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: color)),
                ),
                const SizedBox(height: 2),
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Lưới 2 cột cho các [StatCard].
class StatGrid extends StatelessWidget {
  const StatGrid({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += 2) {
      rows.add(Row(
        children: [
          Expanded(child: children[i]),
          const SizedBox(width: 10),
          Expanded(child: i + 1 < children.length ? children[i + 1] : const SizedBox()),
        ],
      ));
      if (i + 2 < children.length) rows.add(const SizedBox(height: 10));
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(children: rows),
    );
  }
}

/// Tiêu đề mục lớn (vd: "Cần gia hạn", "Theo loại dịch vụ").
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.action});
  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 12, 6),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          ),
          ?action,
        ],
      ),
    );
  }
}

/// Ô lọc gọn: icon + giá trị ▾. Nhãn ([label]) nằm ở đầu menu xổ xuống.
///
/// [expanded] = true khi đặt trong `Expanded` (vd: 3 ô chia đều một hàng):
/// chữ dài tự rút gọn bằng "…".
class FilterBox<T> extends StatelessWidget {
  const FilterBox({
    super.key,
    required this.label,
    required this.icon,
    required this.value,
    required this.options,
    required this.onSelected,
    this.isDefault = false,
    this.expanded = false,
    this.placeholder,
  });

  final String label;

  /// Chữ ngắn hiện trong ô khi đang ở giá trị mặc định (vd: "Loại"), để ô gọn.
  final String? placeholder;
  final IconData icon;
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onSelected;
  final bool isDefault;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final keys = options.keys.toList();
    final active = !isDefault;
    final fg = active ? scheme.primary : scheme.onSurface;
    final text = Text(
      isDefault && placeholder != null ? placeholder! : options[value]!,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: fg),
    );

    // Dùng index làm giá trị menu vì PopupMenuButton coi giá trị null là "huỷ".
    return PopupMenuButton<int>(
      position: PopupMenuPosition.under,
      tooltip: label,
      onSelected: (i) => onSelected(keys[i]),
      itemBuilder: (_) => [
        // Tiêu đề menu = nhãn của ô lọc
        PopupMenuItem<int>(
          enabled: false,
          height: 34,
          child: Row(
            children: [
              Icon(icon, size: 16, color: scheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Text(label.toUpperCase(),
                  style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 0.6,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
        const PopupMenuDivider(height: 1),
        for (var i = 0; i < keys.length; i++)
          PopupMenuItem<int>(
            value: i,
            height: 42,
            child: Row(
              children: [
                SizedBox(
                  width: 28,
                  child: keys[i] == value ? Icon(Icons.check, size: 18, color: scheme.primary) : null,
                ),
                Text(options[keys[i]]!),
              ],
            ),
          ),
      ],
      child: Container(
        height: 42,
        padding: const EdgeInsets.only(left: 8, right: 2),
        decoration: BoxDecoration(
          color: active ? scheme.primary.withValues(alpha: 0.16) : scheme.surfaceContainer,
          border: Border.all(color: active ? scheme.primary.withValues(alpha: 0.6) : scheme.outlineVariant),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: active ? scheme.primary : scheme.onSurfaceVariant),
            const SizedBox(width: 5),
            if (expanded) Expanded(child: text) else text,
            Icon(Icons.arrow_drop_down, size: 18, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

/// Nhóm cài đặt: tiêu đề nhỏ + thẻ chứa các [SettingsItem].
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({super.key, required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 18, 16, 8),
          child: Text(title,
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant)),
        ),
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(children: children),
          ),
        ),
      ],
    );
  }
}

class SettingsItem extends StatelessWidget {
  const SettingsItem({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    this.subtitle,
    this.value,
    this.trailing,
    this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String? subtitle;
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: IconTile(icon, color: color, size: 42),
      title: Text(title,
          style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: danger ? color : scheme.onSurface)),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: trailing ??
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (value != null)
                Text(value!, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 14)),
              if (onTap != null) Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
            ],
          ),
      onTap: onTap,
    );
  }
}
