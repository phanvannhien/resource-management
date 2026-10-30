import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../data/repository.dart';
import '../../data/vault.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../../widgets/form_kit.dart';
import 'vault_ui.dart';

class AccountFormScreen extends ConsumerStatefulWidget {
  const AccountFormScreen({super.key, this.id, this.serviceId, this.customerId});
  final String? id;
  final String? serviceId;
  final String? customerId;

  @override
  ConsumerState<AccountFormScreen> createState() => _AccountFormScreenState();
}

class _AccountFormScreenState extends ConsumerState<AccountFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _label = TextEditingController();
  final _url = TextEditingController();
  final _user = TextEditingController();
  final _pw = TextEditingController();
  final _port = TextEditingController();
  final _note = TextEditingController();
  AccountKind _kind = AccountKind.controlPanel;
  String? _vendorId, _customerId, _serviceId;
  Account? _existing;
  bool _loaded = false;
  bool _obscure = true;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_label, _url, _user, _pw, _port, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  void _load(List<Account> accounts, AppData data) {
    if (_loaded) return;
    _loaded = true;
    _serviceId = widget.serviceId;
    _customerId = widget.customerId;
    if (widget.id == null) {
      // Gợi ý tên tài khoản theo dịch vụ
      final s = data.service(_serviceId);
      if (s != null) {
        _vendorId = s.vendorId;
        _kind = s.type == ServiceType.vps ? AccountKind.ssh : AccountKind.controlPanel;
        _label.text = '${_kind.label} ${s.name}';
        if (s.type == ServiceType.vps) _port.text = '22';
      }
      return;
    }
    final a = accounts.where((x) => x.id == widget.id).firstOrNull;
    _existing = a;
    if (a == null) return;
    _kind = a.kind;
    _label.text = a.label;
    _url.text = a.loginUrl ?? '';
    _user.text = a.username ?? '';
    _port.text = a.port?.toString() ?? '';
    _note.text = a.note ?? '';
    _vendorId = a.vendorId;
    _customerId = a.customerId;
    _serviceId = a.serviceId;
  }

  Future<void> _revealCurrent() async {
    final enc = _existing?.passwordEnc;
    if (enc == null || !await requireVault(context, ref)) return;
    try {
      _pw.text = await ref.read(vaultProvider.notifier).decrypt(enc);
      setState(() => _obscure = false);
    } catch (_) {
      if (mounted) showSnack(context, 'Không giải mã được mật khẩu');
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    var passwordEnc = _existing?.passwordEnc;
    if (_pw.text.isNotEmpty) {
      if (!await requireVault(context, ref)) return;
      passwordEnc = await ref.read(vaultProvider.notifier).encrypt(_pw.text);
    }
    setState(() => _saving = true);
    try {
      await ref.read(repositoryProvider).saveAccount(Account(
            id: _existing?.id,
            kind: _kind,
            label: _label.text.trim(),
            loginUrl: emptyToNull(_url.text),
            username: emptyToNull(_user.text),
            passwordEnc: passwordEnc,
            port: int.tryParse(_port.text),
            vendorId: _vendorId,
            customerId: _customerId,
            serviceId: _serviceId,
            note: emptyToNull(_note.text),
          ));
      ref.invalidate(accountsProvider);
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showSnack(context, 'Lỗi lưu: $e');
      }
    }
  }

  Future<void> _delete() async {
    if (!await confirm(context, 'Xoá tài khoản?', 'Xoá "${_existing!.label}"?',
        ok: 'Xoá', danger: true)) {
      return;
    }
    try {
      await ref.read(repositoryProvider).deleteAccount(_existing!.id!);
      ref.invalidate(accountsProvider);
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) showSnack(context, 'Lỗi: $e');
    }
  }

  Future<void> _pickKind() async {
    final r = await showSelectSheet<AccountKind>(
      context,
      title: 'Loại tài khoản',
      selected: _kind,
      items: [for (final k in AccountKind.values) SelectItem(k, k.label, icon: k.icon)],
    );
    if (r != null) setState(() => _kind = r.value);
  }

  Future<void> _pickService(AppData data) async {
    final r = await showSelectSheet<String?>(
      context,
      title: 'Dịch vụ',
      selected: _serviceId,
      items: [
        const SelectItem(null, 'Không liên kết'),
        for (final s in data.services)
          SelectItem(s.id, s.name,
              subtitle: '${s.type.label} · ${data.ownerName(s)}', icon: s.type.icon, color: typeColor(s.type)),
      ],
    );
    if (r == null) return;
    setState(() {
      _serviceId = r.value;
      final s = data.service(r.value);
      if (s != null) {
        _customerId = s.customerId;
        _vendorId ??= s.vendorId;
      }
    });
  }

  Future<void> _pickCustomer(AppData data) async {
    final r = await showSelectSheet<String?>(
      context,
      title: 'Khách hàng',
      selected: _customerId,
      items: [
        const SelectItem(null, 'Của tôi', icon: Icons.person_pin_rounded),
        for (final c in data.customers) SelectItem(c.id, c.name, icon: Icons.person_outline_rounded),
      ],
    );
    if (r != null) setState(() => _customerId = r.value);
  }

  Future<void> _pickVendor(AppData data) async {
    final r = await showSelectSheet<String?>(
      context,
      title: 'Nhà cung cấp',
      selected: _vendorId,
      items: [
        const SelectItem(null, 'Không chọn'),
        for (final v in data.vendors) SelectItem(v.id, v.name, icon: Icons.business_outlined),
      ],
    );
    if (r != null) setState(() => _vendorId = r.value);
  }

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(accountsProvider);
    final appData = ref.watch(appDataProvider);
    return Scaffold(
      appBar: formAppBar(
        context,
        title: widget.id == null ? 'Tài khoản mới' : 'Sửa tài khoản',
        saving: _saving,
        onSave: _save,
      ),
      body: AsyncView(
        value: appData,
        builder: (data) => AsyncView(
          value: accounts,
          builder: (list) {
            _load(list, data);
            if (widget.id != null && _existing == null) {
              return const EmptyState('Tài khoản không tồn tại');
            }
            return _form(data);
          },
        ),
      ),
    );
  }

  Widget _form(AppData data) {
    final scheme = Theme.of(context).colorScheme;
    final hasOldPassword = _existing?.passwordEnc != null;
    final service = data.service(_serviceId);
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          FormSection(
            header: 'Tài khoản',
            children: [
              FormValueRow(
                label: 'Loại',
                value: _kind.label,
                leading: Icon(_kind.icon, size: 18, color: scheme.onSurfaceVariant),
                onTap: _pickKind,
              ),
              FormTextRow(
                label: 'Tên gợi nhớ',
                controller: _label,
                hint: 'Bắt buộc',
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Nhập tên' : null,
              ),
            ],
          ),
          FormSection(
            header: 'Đăng nhập',
            footer: hasOldPassword
                ? 'Để trống mật khẩu = giữ nguyên mật khẩu cũ. Mật khẩu được mã hoá trước khi lưu.'
                : 'Mật khẩu được mã hoá bằng master password trước khi lưu.',
            children: [
              FormTextRow(
                label: 'Link / host',
                controller: _url,
                hint: 'https://… hoặc IP',
                keyboardType: TextInputType.url,
              ),
              FormTextRow(label: 'Username', controller: _user, hint: 'root, admin…'),
              FormTextRow(
                label: 'Mật khẩu',
                controller: _pw,
                hint: hasOldPassword ? '••••••••' : 'Không bắt buộc',
                obscure: _obscure,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (hasOldPassword && _pw.text.isEmpty)
                      IconButton(
                        tooltip: 'Hiện mật khẩu hiện tại',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.lock_open_rounded, size: 20),
                        onPressed: _revealCurrent,
                      ),
                    IconButton(
                      tooltip: _obscure ? 'Hiện' : 'Ẩn',
                      visualDensity: VisualDensity.compact,
                      icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                          size: 20),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ],
                ),
              ),
              FormTextRow(
                label: 'Port',
                controller: _port,
                hint: '22, 2083…',
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              ),
            ],
          ),
          FormSection(
            header: 'Liên kết',
            children: [
              FormValueRow(
                label: 'Dịch vụ',
                value: service?.name,
                placeholder: 'Không liên kết',
                leading: service == null ? null : TypeBadge(service.type),
                onTap: () => _pickService(data),
              ),
              FormValueRow(
                label: 'Khách hàng',
                value: data.customer(_customerId)?.name ?? 'Của tôi',
                onTap: () => _pickCustomer(data),
              ),
              FormValueRow(
                label: 'Nhà cung cấp',
                value: data.vendor(_vendorId)?.name,
                placeholder: 'Không chọn',
                onTap: () => _pickVendor(data),
              ),
            ],
          ),
          FormSection(header: 'Ghi chú', children: [FormNoteRow(controller: _note)]),
          if (widget.id != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
              child: TextButton(
                onPressed: _delete,
                child: const Text('Xoá tài khoản', style: TextStyle(color: kRed, fontSize: 16)),
              ),
            ),
        ],
      ),
    );
  }
}
