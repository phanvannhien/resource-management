import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../core/format.dart';

// ---------------------------------------------------------------------------
// Bộ thành phần form theo kiểu iOS (Settings / Contacts):
// - nhóm dòng bo góc, nhãn cố định bên trái, giá trị bên phải;
// - chọn từ danh sách bằng bảng trượt có tìm kiếm;
// - chọn ngày bằng bánh xe cuộn.
// ---------------------------------------------------------------------------

const _labelWidth = 116.0;
const _rowMinHeight = 48.0;

/// Thanh tiêu đề form: "Huỷ" | tiêu đề | "Lưu".
PreferredSizeWidget formAppBar(
  BuildContext context, {
  required String title,
  required VoidCallback? onSave,
  bool saving = false,
  String saveLabel = 'Lưu',
  List<Widget> extraActions = const [],
}) {
  final scheme = Theme.of(context).colorScheme;
  return AppBar(
    centerTitle: true,
    automaticallyImplyLeading: false,
    leadingWidth: 76,
    leading: TextButton(
      onPressed: () => Navigator.of(context).maybePop(),
      child: const Text('Huỷ', style: TextStyle(fontSize: 16)),
    ),
    title: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
    actions: [
      ...extraActions,
      Padding(
        padding: const EdgeInsets.only(right: 8),
        child: saving
            ? const Padding(
                padding: EdgeInsets.all(14),
                child: SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)),
              )
            : TextButton(
                onPressed: onSave,
                child: Text(saveLabel,
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700, color: scheme.primary)),
              ),
      ),
    ],
  );
}

/// Một nhóm dòng bo góc, có tiêu đề nhỏ phía trên và chú thích phía dưới.
class FormSection extends StatelessWidget {
  const FormSection({super.key, this.header, this.footer, required this.children});
  final String? header;
  final String? footer;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (header != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 18, 32, 6),
            child: Text(header!.toUpperCase(), style: muted.copyWith(letterSpacing: 0.4)),
          )
        else
          const SizedBox(height: 14),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: scheme.surfaceContainer,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: scheme.outlineVariant),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                children[i],
                if (i < children.length - 1)
                  Divider(height: 1, indent: 16, color: scheme.outlineVariant),
              ],
            ],
          ),
        ),
        if (footer != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 6, 32, 0),
            child: Text(footer!, style: muted),
          ),
      ],
    );
  }
}

InputDecoration _bareDecoration(BuildContext context, String? hint) {
  final scheme = Theme.of(context).colorScheme;
  const none = InputBorder.none;
  return InputDecoration(
    isDense: true,
    filled: false,
    hintText: hint,
    hintStyle: TextStyle(color: scheme.onSurfaceVariant.withValues(alpha: 0.7)),
    border: none,
    enabledBorder: none,
    focusedBorder: none,
    errorBorder: none,
    focusedErrorBorder: none,
    disabledBorder: none,
    contentPadding: const EdgeInsets.symmetric(vertical: 14),
    errorStyle: const TextStyle(fontSize: 11, height: 1),
  );
}

/// Dòng nhập chữ: nhãn cố định bên trái, ô nhập bên phải (không có nhãn nổi/nhảy).
class FormTextRow extends StatelessWidget {
  const FormTextRow({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.keyboardType,
    this.inputFormatters,
    this.validator,
    this.suffix,
    this.trailing,
    this.obscure = false,
    this.autofocus = false,
    this.textCapitalization = TextCapitalization.none,
    this.textAlign = TextAlign.right,
    this.onChanged,
    this.enabled = true,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final FormFieldValidator<String>? validator;

  /// Chữ đơn vị sau ô nhập (vd: "đ", "ngày", "GB").
  final String? suffix;

  /// Widget thêm ở cuối dòng (vd: nút hiện mật khẩu).
  final Widget? trailing;
  final bool obscure;
  final bool autofocus;
  final TextCapitalization textCapitalization;
  final TextAlign textAlign;
  final ValueChanged<String>? onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: _rowMinHeight),
      child: Padding(
        padding: EdgeInsets.only(left: 16, right: trailing == null ? 16 : 4),
        child: Row(
          children: [
            SizedBox(
              width: _labelWidth,
              child: Text(label, style: const TextStyle(fontSize: 15)),
            ),
            Expanded(
              child: TextFormField(
                controller: controller,
                enabled: enabled,
                autofocus: autofocus,
                obscureText: obscure,
                autocorrect: !obscure,
                enableSuggestions: !obscure,
                keyboardType: keyboardType,
                inputFormatters: inputFormatters,
                textCapitalization: textCapitalization,
                textAlign: textAlign,
                validator: validator,
                onChanged: onChanged,
                style: const TextStyle(fontSize: 15),
                decoration: _bareDecoration(context, hint),
              ),
            ),
            if (suffix != null)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Text(suffix!, style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant)),
              ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

/// Dòng nhập nhiều dòng chiếm cả chiều ngang (ghi chú, nameservers).
class FormNoteRow extends StatelessWidget {
  const FormNoteRow({super.key, required this.controller, this.hint = 'Ghi chú', this.minLines = 3});
  final TextEditingController controller;
  final String hint;
  final int minLines;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: TextFormField(
        controller: controller,
        minLines: minLines,
        maxLines: 8,
        style: const TextStyle(fontSize: 15),
        textCapitalization: TextCapitalization.sentences,
        decoration: _bareDecoration(context, hint),
      ),
    );
  }
}

/// Dòng hiển thị giá trị, bấm để chọn (mở bảng chọn / bánh xe ngày...).
class FormValueRow extends StatelessWidget {
  const FormValueRow({
    super.key,
    required this.label,
    required this.value,
    required this.onTap,
    this.placeholder = 'Chọn',
    this.valueColor,
    this.leading,
    this.errorText,
  });

  final String label;
  final String? value;
  final VoidCallback? onTap;
  final String placeholder;
  final Color? valueColor;
  final Widget? leading;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final empty = value == null || value!.isEmpty;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: _rowMinHeight),
        child: Padding(
          padding: const EdgeInsets.only(left: 16, right: 8),
          child: Row(
            children: [
              SizedBox(width: _labelWidth, child: Text(label, style: const TextStyle(fontSize: 15))),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (leading != null) ...[leading!, const SizedBox(width: 6)],
                        Flexible(
                          child: Text(
                            empty ? placeholder : value!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontSize: 15,
                              color: empty
                                  ? scheme.onSurfaceVariant.withValues(alpha: 0.7)
                                  : (valueColor ?? scheme.onSurfaceVariant),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (errorText != null)
                      Text(errorText!, style: TextStyle(fontSize: 11, color: scheme.error)),
                  ],
                ),
              ),
              if (onTap != null)
                Icon(Icons.chevron_right_rounded, size: 22, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dòng bật/tắt.
class FormSwitchRow extends StatelessWidget {
  const FormSwitchRow({super.key, required this.label, required this.value, required this.onChanged});
  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: _rowMinHeight),
      child: Padding(
        padding: const EdgeInsets.only(left: 16, right: 10),
        child: Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(fontSize: 15))),
            Switch.adaptive(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}

/// Thanh chọn trượt kiểu iOS (dùng cho 2–4 lựa chọn).
class FormSegmented<T extends Object> extends StatelessWidget {
  const FormSegmented({super.key, required this.value, required this.options, required this.onChanged});
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(8),
      child: SizedBox(
        width: double.infinity,
        child: CupertinoSlidingSegmentedControl<T>(
          groupValue: value,
          backgroundColor: scheme.surfaceContainerHigh,
          thumbColor: scheme.primary,
          padding: const EdgeInsets.all(3),
          children: {
            for (final e in options.entries)
              e.key: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  e.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: e.key == value ? FontWeight.w700 : FontWeight.w500,
                    color: e.key == value ? Colors.white : scheme.onSurface,
                  ),
                ),
              ),
          },
          onValueChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Chọn ngày bằng bánh xe cuộn
// ---------------------------------------------------------------------------

/// Kết quả chọn (phân biệt "chọn giá trị null" với "huỷ").
class Picked<T> {
  const Picked(this.value);
  final T value;
}

/// Mở bánh xe chọn ngày. Trả về null nếu huỷ; `Picked(null)` nếu bấm "Xoá ngày".
Future<Picked<DateTime?>?> pickDate(
  BuildContext context, {
  required String title,
  DateTime? initial,
  bool allowClear = false,
}) {
  var selected = initial ?? today();
  final scheme = Theme.of(context).colorScheme;
  final dark = Theme.of(context).brightness == Brightness.dark;
  return showModalBottomSheet<Picked<DateTime?>>(
    context: context,
    showDragHandle: false,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
            child: Row(
              children: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Huỷ')),
                Expanded(
                  child: Text(title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, Picked<DateTime?>(selected)),
                  child: Text('Xong',
                      style: TextStyle(fontWeight: FontWeight.w700, color: scheme.primary)),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 216,
            child: CupertinoTheme(
              data: CupertinoThemeData(
                brightness: dark ? Brightness.dark : Brightness.light,
                textTheme: CupertinoTextThemeData(
                  dateTimePickerTextStyle: TextStyle(fontSize: 21, color: scheme.onSurface),
                ),
              ),
              child: CupertinoDatePicker(
                mode: CupertinoDatePickerMode.date,
                dateOrder: DatePickerDateOrder.dmy,
                initialDateTime: selected,
                minimumYear: 2000,
                maximumYear: 2100,
                onDateTimeChanged: (d) => selected = DateTime(d.year, d.month, d.day),
              ),
            ),
          ),
          if (allowClear)
            TextButton(
              onPressed: () => Navigator.pop(ctx, const Picked<DateTime?>(null)),
              child: Text('Xoá ngày', style: TextStyle(color: scheme.error)),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

/// Dòng ngày: bấm để mở bánh xe chọn ngày.
class FormDateRow extends StatelessWidget {
  const FormDateRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.allowClear = false,
    this.valueColor,
    this.placeholder = 'Chưa chọn',
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final bool allowClear;
  final Color? valueColor;
  final String placeholder;

  @override
  Widget build(BuildContext context) {
    return FormValueRow(
      label: label,
      value: value == null ? null : DateFormat('dd/MM/yyyy').format(value!),
      placeholder: placeholder,
      valueColor: valueColor,
      onTap: () async {
        FocusScope.of(context).unfocus();
        final r = await pickDate(context, title: label, initial: value, allowClear: allowClear);
        if (r != null) onChanged(r.value);
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Bảng chọn từ danh sách (có tìm kiếm)
// ---------------------------------------------------------------------------

class SelectItem<T> {
  const SelectItem(this.value, this.title, {String? subtitle, this.icon, this.color, this.trailing})
      : subtitle = (subtitle == null || subtitle == '') ? null : subtitle;
  final T value;
  final String title;
  final String? subtitle;
  final IconData? icon;
  final Color? color;
  final Widget? trailing;
}

/// Mở bảng chọn trượt từ dưới lên. Danh sách dài (> 7 mục) có ô tìm kiếm.
/// [onAddNew] hiện dòng "＋ Thêm mới" ở đầu; trả về giá trị mới tạo để chọn luôn.
Future<Picked<T>?> showSelectSheet<T>(
  BuildContext context, {
  required String title,
  required List<SelectItem<T>> items,
  required T selected,
  String addNewLabel = 'Thêm mới',
  Future<T?> Function()? onAddNew,
}) {
  FocusScope.of(context).unfocus();
  return showModalBottomSheet<Picked<T>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _SelectSheet<T>(
      title: title,
      items: items,
      selected: selected,
      addNewLabel: addNewLabel,
      onAddNew: onAddNew,
    ),
  );
}

class _SelectSheet<T> extends StatefulWidget {
  const _SelectSheet({
    required this.title,
    required this.items,
    required this.selected,
    required this.addNewLabel,
    this.onAddNew,
  });

  final String title;
  final List<SelectItem<T>> items;
  final T selected;
  final String addNewLabel;
  final Future<T?> Function()? onAddNew;

  @override
  State<_SelectSheet<T>> createState() => _SelectSheetState<T>();
}

class _SelectSheetState<T> extends State<_SelectSheet<T>> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final searchable = widget.items.length > 7;
    final q = _q.toLowerCase();
    final list = q.isEmpty
        ? widget.items
        : widget.items
            .where((i) =>
                i.title.toLowerCase().contains(q) || (i.subtitle?.toLowerCase().contains(q) ?? false))
            .toList();
    final maxH = MediaQuery.sizeOf(context).height * 0.8;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxH),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: Text(widget.title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          ),
          if (searchable)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: SearchBar(
                hintText: 'Tìm…',
                leading: const Icon(Icons.search, size: 20),
                constraints: const BoxConstraints(minHeight: 44, maxHeight: 44),
                onChanged: (v) => setState(() => _q = v.trim()),
              ),
            ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainer,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      if (widget.onAddNew != null) ...[
                        ListTile(
                          leading: Icon(Icons.add_circle_rounded, color: scheme.primary),
                          title: Text(widget.addNewLabel,
                              style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w600)),
                          onTap: () async {
                            final v = await widget.onAddNew!();
                            if (v != null && context.mounted) Navigator.pop(context, Picked<T>(v));
                          },
                        ),
                        if (list.isNotEmpty) Divider(height: 1, indent: 16, color: scheme.outlineVariant),
                      ],
                      if (list.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(20),
                          child: Text('Không tìm thấy', style: TextStyle(color: scheme.onSurfaceVariant)),
                        ),
                      for (var i = 0; i < list.length; i++) ...[
                        ListTile(
                          dense: list[i].subtitle == null,
                          leading: list[i].icon == null
                              ? null
                              : Icon(list[i].icon, color: list[i].color ?? scheme.onSurfaceVariant),
                          title: Text(list[i].title, style: const TextStyle(fontSize: 15)),
                          subtitle: list[i].subtitle == null ? null : Text(list[i].subtitle!),
                          trailing: list[i].value == widget.selected
                              ? Icon(Icons.check_rounded, color: scheme.primary)
                              : list[i].trailing,
                          onTap: () => Navigator.pop(context, Picked<T>(list[i].value)),
                        ),
                        if (i < list.length - 1)
                          Divider(height: 1, indent: 16, color: scheme.outlineVariant),
                      ],
                    ],
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

// ---------------------------------------------------------------------------
// Tiền: tự thêm dấu chấm ngăn cách khi gõ (800000 → 800.000)
// ---------------------------------------------------------------------------

final _group = NumberFormat.decimalPattern('vi_VN');

class MoneyInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return const TextEditingValue();
    final text = _group.format(int.parse(digits));
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}

int? parseMoney(String s) => int.tryParse(s.replaceAll(RegExp(r'[^0-9]'), ''));

String moneyText(int? v) => v == null ? '' : _group.format(v);

/// Dòng hành động trong nhóm (vd: "Đồng bộ ngay", "Xuất file sao lưu").
class FormActionRow extends StatelessWidget {
  const FormActionRow({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.subtitle,
    this.color,
    this.busy = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final String? subtitle;
  final Color? color;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = onTap == null ? scheme.onSurfaceVariant : (color ?? scheme.primary);
    return InkWell(
      onTap: busy ? null : onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: _rowMinHeight),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              busy
                  ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(icon, size: 20, color: c),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(label, style: TextStyle(fontSize: 15, color: c, fontWeight: FontWeight.w600)),
                    if (subtitle != null)
                      Text(subtitle!, style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Ô nhập IP trên bàn phím số: máy đặt tiếng Việt hiện phím "," thay cho "." → tự đổi "," thành ".",
/// chỉ giữ chữ số, "." và ":" (IPv6).
class IpInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final text = newValue.text.replaceAll(',', '.').replaceAll(RegExp(r'[^0-9a-fA-F.:]'), '');
    final offset = (newValue.selection.baseOffset - (newValue.text.length - text.length))
        .clamp(0, text.length);
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: offset));
  }
}
