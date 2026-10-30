import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../data/repository.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../../widgets/form_kit.dart';
import '../../widgets/glass_nav_bar.dart';

class VendorsScreen extends ConsumerWidget {
  const VendorsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      extendBody: true,
      bottomNavigationBar: const GlassNavBar(),
      appBar: AppBar(title: const Text('Nhà cung cấp')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showVendorDialog(context, ref),
        child: const Icon(Icons.add),
      ),
      body: AsyncView(
        value: ref.watch(appDataProvider),
        onRetry: () => ref.invalidate(appDataProvider),
        builder: (data) {
          if (data.vendors.isEmpty) {
            return const EmptyState('Chưa có nhà cung cấp\nvd: Tenten, Mắt Bão, Vultr...');
          }
          return ListView.separated(
            padding: const EdgeInsets.only(top: 4, bottom: kNavBarSpace),
            itemCount: data.vendors.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final v = data.vendors[i];
              final count = data.services.where((s) => s.vendorId == v.id && !s.cancelled).length;
              return ListTile(
                leading: const Icon(Icons.business_outlined),
                title: Text(v.name),
                subtitle: Text(
                  [
                    '$count dịch vụ',
                    if (v.website != null) v.website!,
                    if (v.supportContact != null) v.supportContact!,
                  ].join(' · '),
                ),
                onTap: () => showVendorDialog(context, ref, existing: v),
              );
            },
          );
        },
      ),
    );
  }
}

/// Bottom sheet thêm / sửa nhà cung cấp. Trả về id.
Future<String?> showVendorDialog(BuildContext context, WidgetRef ref, {Vendor? existing}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => _VendorSheet(existing: existing),
  );
}

class _VendorSheet extends ConsumerStatefulWidget {
  const _VendorSheet({this.existing});
  final Vendor? existing;

  @override
  ConsumerState<_VendorSheet> createState() => _VendorSheetState();
}

class _VendorSheetState extends ConsumerState<_VendorSheet> {
  late final _name = TextEditingController(text: widget.existing?.name);
  late final _website = TextEditingController(text: widget.existing?.website);
  late final _support = TextEditingController(text: widget.existing?.supportContact);
  late final _note = TextEditingController(text: widget.existing?.note);
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _website, _support, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _run(Future<String?> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final id = await action();
      ref.invalidate(appDataProvider);
      if (mounted) Navigator.pop(context, id);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Lỗi: $e';
        });
      }
    }
  }

  void _save() {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Nhập tên nhà cung cấp');
      return;
    }
    _run(
      () => ref
          .read(repositoryProvider)
          .saveVendor(
            Vendor(
              id: widget.existing?.id,
              name: _name.text.trim(),
              website: emptyToNull(_website.text),
              supportContact: emptyToNull(_support.text),
              note: emptyToNull(_note.text),
            ),
          ),
    );
  }

  Future<void> _delete() async {
    final v = widget.existing!;
    if (!await confirm(
      context,
      'Xoá nhà cung cấp?',
      'Các dịch vụ đang gắn với "${v.name}" sẽ bị bỏ liên kết.',
      ok: 'Xoá',
      danger: true,
    )) {
      return;
    }
    _run(() async {
      await ref.read(repositoryProvider).deleteVendor(v.id!);
      return null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.existing == null;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      isNew ? 'Thêm nhà cung cấp' : 'Sửa nhà cung cấp',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  if (!isNew)
                    IconButton(
                      tooltip: 'Xoá',
                      icon: const Icon(Icons.delete_outline, color: kRed),
                      onPressed: _busy ? null : _delete,
                    ),
                ],
              ),
            ),
            FormSection(
              children: [
                FormTextRow(
                  label: 'Tên',
                  controller: _name,
                  hint: 'Tenten, Mắt Bão, Vultr…',
                  autofocus: isNew,
                  textCapitalization: TextCapitalization.words,
                ),
                FormTextRow(
                  label: 'Website',
                  controller: _website,
                  hint: 'trang quản trị',
                  keyboardType: TextInputType.url,
                ),
                FormTextRow(label: 'Hỗ trợ', controller: _support, hint: 'Hotline, email, Zalo…'),
              ],
            ),
            FormSection(
              header: 'Ghi chú',
              children: [FormNoteRow(controller: _note, minLines: 2)],
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 12, 32, 0),
                child: Text(_error!, style: const TextStyle(color: kRed)),
              ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                onPressed: _busy ? null : _save,
                icon: _busy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check),
                label: const Text('Lưu'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
