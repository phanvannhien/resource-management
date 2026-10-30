import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../data/repository.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../../widgets/form_kit.dart';

/// Thêm / sửa khách hàng. Nếu [pick] = true, sau khi tạo sẽ pop trả về id khách mới.
class CustomerFormScreen extends ConsumerStatefulWidget {
  const CustomerFormScreen({super.key, this.id, this.pick = false});
  final String? id;
  final bool pick;

  @override
  ConsumerState<CustomerFormScreen> createState() => _CustomerFormScreenState();
}

class _CustomerFormScreenState extends ConsumerState<CustomerFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _zalo = TextEditingController();
  final _email = TextEditingController();
  final _company = TextEditingController();
  final _note = TextEditingController();
  Customer? _existing;
  bool _loaded = false;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_name, _phone, _zalo, _email, _company, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  void _load(AppData data) {
    if (_loaded) return;
    _loaded = true;
    final c = data.customer(widget.id);
    _existing = c;
    if (c == null) return;
    _name.text = c.name;
    _phone.text = c.phone ?? '';
    _zalo.text = c.zalo ?? '';
    _email.text = c.email ?? '';
    _company.text = c.company ?? '';
    _note.text = c.note ?? '';
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final id = await ref.read(repositoryProvider).saveCustomer(Customer(
            id: _existing?.id,
            name: _name.text.trim(),
            phone: emptyToNull(_phone.text),
            zalo: emptyToNull(_zalo.text),
            email: emptyToNull(_email.text),
            company: emptyToNull(_company.text),
            note: emptyToNull(_note.text),
            isActive: _existing?.isActive ?? true,
          ));
      ref.invalidate(appDataProvider);
      if (!mounted) return;
      if (widget.pick || _existing != null) {
        context.pop(id);
      } else {
        context.pushReplacement('/customer/$id');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showSnack(context, 'Lỗi lưu: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.id == null;
    return Scaffold(
      appBar: formAppBar(
        context,
        title: isNew ? 'Khách hàng mới' : 'Sửa khách hàng',
        saving: _saving,
        onSave: _save,
      ),
      body: AsyncView(
        value: ref.watch(appDataProvider),
        builder: (data) {
          _load(data);
          return Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.only(bottom: 40),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              children: [
                FormSection(
                  header: 'Thông tin',
                  children: [
                    FormTextRow(
                      label: 'Tên',
                      controller: _name,
                      hint: 'Bắt buộc',
                      autofocus: isNew,
                      textCapitalization: TextCapitalization.words,
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Nhập tên' : null,
                    ),
                    FormTextRow(
                      label: 'Công ty',
                      controller: _company,
                      hint: 'Không bắt buộc',
                      textCapitalization: TextCapitalization.words,
                    ),
                  ],
                ),
                FormSection(
                  header: 'Liên hệ',
                  footer: 'Zalo để trống nếu trùng số điện thoại.',
                  children: [
                    FormTextRow(
                      label: 'Điện thoại',
                      controller: _phone,
                      hint: '09xx xxx xxx',
                      keyboardType: TextInputType.phone,
                    ),
                    FormTextRow(
                      label: 'Zalo',
                      controller: _zalo,
                      hint: 'Số Zalo',
                      keyboardType: TextInputType.phone,
                    ),
                    FormTextRow(
                      label: 'Email',
                      controller: _email,
                      hint: 'email@domain.com',
                      keyboardType: TextInputType.emailAddress,
                    ),
                  ],
                ),
                FormSection(header: 'Ghi chú', children: [FormNoteRow(controller: _note)]),
              ],
            ),
          );
        },
      ),
    );
  }
}
