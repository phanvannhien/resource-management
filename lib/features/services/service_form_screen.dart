import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../data/repository.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../../widgets/form_kit.dart';
import '../settings/vendors_screen.dart';
import 'renew_sheet.dart';

class ServiceFormScreen extends ConsumerWidget {
  const ServiceFormScreen({
    super.key,
    this.id,
    this.initialType,
    this.initialCustomerId,
    this.initialParentVpsId,
  });

  final String? id;
  final ServiceType? initialType;
  final String? initialCustomerId;
  final String? initialParentVpsId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(appDataProvider);
    return AsyncView(
      value: async,
      builder: (data) {
        final existing = data.service(id);
        if (id != null && existing == null) {
          return Scaffold(appBar: AppBar(), body: const EmptyState('Dịch vụ không tồn tại'));
        }
        return _ServiceForm(
          data: data,
          existing: existing,
          initialType: initialType,
          initialCustomerId: initialCustomerId,
          initialParentVpsId: initialParentVpsId,
        );
      },
    );
  }
}

class _ServiceForm extends ConsumerStatefulWidget {
  const _ServiceForm({
    required this.data,
    this.existing,
    this.initialType,
    this.initialCustomerId,
    this.initialParentVpsId,
  });

  final AppData data;
  final Service? existing;
  final ServiceType? initialType;
  final String? initialCustomerId;
  final String? initialParentVpsId;

  @override
  ConsumerState<_ServiceForm> createState() => _ServiceFormState();
}

class _ServiceFormState extends ConsumerState<_ServiceForm> {
  final _formKey = GlobalKey<FormState>();
  late ServiceType _type;
  String? _customerId, _vendorId, _parentVpsId, _linkedHostingId;
  late bool _onVps; // hosting tự tạo trên VPS
  DateTime? _start;
  late DateTime _expiry;
  late bool _expiryTouched;
  late int _cycle;
  bool _saving = false;
  bool _showErrors = false;

  final _name = TextEditingController();
  final _cost = TextEditingController();
  final _sell = TextEditingController();
  final _notify = TextEditingController();
  final _note = TextEditingController();
  final _ip = TextEditingController();
  final _os = TextEditingController();
  final _cpu = TextEditingController();
  final _ram = TextEditingController();
  final _disk = TextEditingController();
  final _panel = TextEditingController();
  final _ns = TextEditingController();

  @override
  void initState() {
    super.initState();
    final s = widget.existing;
    _type = s?.type ?? widget.initialType ?? ServiceType.domain;
    _customerId = s?.customerId ?? widget.initialCustomerId;
    _vendorId = s?.vendorId;
    _parentVpsId = s?.parentVpsId ?? widget.initialParentVpsId;
    _linkedHostingId = s?.linkedHostingId;
    _onVps = _parentVpsId != null;
    _cycle = s?.cycleMonths ?? 12;
    _start = s?.startDate ?? (s == null ? today() : null);
    _expiry = s?.expiryDate ?? addMonths(today(), _cycle);
    _expiryTouched = s != null;

    _name.text = s?.name ?? '';
    _cost.text = moneyText(s?.costPrice);
    _sell.text = moneyText(s?.sellPrice);
    _notify.text = (s?.notifyDays ?? 15).toString();
    _note.text = s?.note ?? '';
    _ip.text = s?.ip ?? '';
    _os.text = s?.os ?? '';
    _cpu.text = s?.cpu?.toString() ?? '';
    _ram.text = s?.ramGb == null ? '' : s!.ramGb.toString().replaceAll(RegExp(r'\.0$'), '');
    _disk.text = s?.diskGb?.toString() ?? '';
    _panel.text = s?.panel ?? '';
    _ns.text = s?.nameservers ?? '';

    // Hosting tạo trên VPS của khách → mặc định chủ sở hữu là khách đó.
    if (s == null && _parentVpsId != null && _customerId == null) {
      _customerId = widget.data.service(_parentVpsId)?.customerId;
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _cost, _sell, _notify, _note, _ip, _os, _cpu, _ram, _disk, _panel, _ns]) {
      c.dispose();
    }
    super.dispose();
  }

  void _recalcExpiry() {
    if (!_expiryTouched && _start != null) _expiry = addMonths(_start!, _cycle);
  }

  Future<void> _save() async {
    final vpsMissing = _type == ServiceType.hosting && _onVps && _parentVpsId == null;
    setState(() => _showErrors = true);
    if (!_formKey.currentState!.validate() || vpsMissing) return;
    final isHosting = _type == ServiceType.hosting;
    final hasServer = _type == ServiceType.hosting || _type == ServiceType.vps;
    final service = Service(
      id: widget.existing?.id,
      type: _type,
      name: _name.text.trim(),
      customerId: _customerId,
      vendorId: (isHosting && _onVps) ? null : _vendorId,
      parentVpsId: (isHosting && _onVps) ? _parentVpsId : null,
      startDate: _start,
      expiryDate: _expiry,
      cycleMonths: _cycle,
      costPrice: parseMoney(_cost.text),
      sellPrice: parseMoney(_sell.text),
      notifyDays: int.tryParse(_notify.text) ?? 15,
      cancelled: widget.existing?.cancelled ?? false,
      note: emptyToNull(_note.text),
      ip: hasServer ? emptyToNull(_ip.text) : null,
      panel: hasServer ? emptyToNull(_panel.text) : null,
      os: _type == ServiceType.vps ? emptyToNull(_os.text) : null,
      cpu: _type == ServiceType.vps ? int.tryParse(_cpu.text) : null,
      ramGb: _type == ServiceType.vps ? double.tryParse(_ram.text.replaceAll(',', '.')) : null,
      diskGb: hasServer ? int.tryParse(_disk.text) : null,
      nameservers: _type == ServiceType.domain ? emptyToNull(_ns.text) : null,
      linkedHostingId: _type == ServiceType.domain ? _linkedHostingId : null,
    );

    setState(() => _saving = true);
    try {
      final id = await ref.read(repositoryProvider).saveService(service);
      ref.invalidate(appDataProvider);
      if (!mounted) return;
      if (widget.existing == null) {
        context.pushReplacement('/service/$id');
      } else {
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showSnack(context, 'Lỗi lưu: $e');
      }
    }
  }

  Future<String?> _addCustomer() => context.push<String>('/customer/new?pick=1');

  Future<String?> _addVendor() => showVendorDialog(context, ref);

  Future<void> _pickCustomer(AppData data) async {
    final r = await showSelectSheet<String?>(
      context,
      title: 'Chủ sở hữu',
      selected: _customerId,
      addNewLabel: 'Thêm khách hàng mới',
      onAddNew: _addCustomer,
      items: [
        const SelectItem(null, 'Của tôi', icon: Icons.person_pin_rounded),
        for (final c in data.customers.where((c) => c.isActive || c.id == _customerId))
          SelectItem(c.id, c.name,
              subtitle: [c.phone, c.company].whereType<String>().join(' · '),
              icon: Icons.person_outline_rounded),
      ],
    );
    if (r != null) setState(() => _customerId = r.value);
  }

  Future<void> _pickVendor(AppData data) async {
    final r = await showSelectSheet<String?>(
      context,
      title: 'Nhà cung cấp',
      selected: _vendorId,
      addNewLabel: 'Thêm nhà cung cấp mới',
      onAddNew: _addVendor,
      items: [
        const SelectItem(null, 'Không chọn'),
        for (final v in data.vendors) SelectItem(v.id, v.name, icon: Icons.business_outlined),
      ],
    );
    if (r != null) setState(() => _vendorId = r.value);
  }

  Future<void> _pickVps(AppData data, List<Service> vpsList) async {
    final r = await showSelectSheet<String?>(
      context,
      title: 'Chạy trên VPS',
      selected: _parentVpsId,
      items: [
        for (final v in vpsList)
          SelectItem(v.id, v.name,
              subtitle: [data.ownerName(v), v.ip].whereType<String>().join(' · '),
              icon: ServiceType.vps.icon),
      ],
    );
    if (r == null) return;
    setState(() {
      _parentVpsId = r.value;
      if (widget.existing == null && _customerId == null) {
        _customerId = data.service(r.value)?.customerId;
      }
    });
  }

  Future<void> _pickLinkedHosting(AppData data) async {
    final r = await showSelectSheet<String?>(
      context,
      title: 'Trỏ về hosting',
      selected: _linkedHostingId,
      items: [
        const SelectItem(null, 'Không chọn'),
        for (final h in data.activeHostings)
          SelectItem(h.id, h.name, subtitle: data.ownerName(h), icon: ServiceType.hosting.icon),
      ],
    );
    if (r != null) setState(() => _linkedHostingId = r.value);
  }

  Future<void> _pickCycle() async {
    final r = await showSelectSheet<int>(
      context,
      title: 'Chu kỳ gia hạn',
      selected: _cycle,
      items: [for (final m in {...kCycleOptions, _cycle}.toList()..sort()) SelectItem(m, fmtCycle(m))],
    );
    if (r != null) {
      setState(() {
        _cycle = r.value;
        _recalcExpiry();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final isNew = widget.existing == null;
    final nameLabel = switch (_type) {
      ServiceType.domain => 'Tên miền',
      ServiceType.hosting => 'Tên hosting',
      ServiceType.vps => 'Tên VPS',
      ServiceType.other => 'Tên dịch vụ',
    };
    final nameHint = switch (_type) {
      ServiceType.domain => 'abc.vn',
      ServiceType.hosting => 'abc.vn',
      ServiceType.vps => 'VPS-SG-01',
      ServiceType.other => 'Bảo trì web abc.vn',
    };
    final vpsList = data.activeVps.where((v) => v.id != widget.existing?.id).toList();
    final hasServer = _type == ServiceType.hosting || _type == ServiceType.vps;
    final digits = [FilteringTextInputFormatter.digitsOnly];
    final money = [MoneyInputFormatter()];
    final expiryColor = daysBetween(today(), _expiry) < 0 ? kRed : null;

    return Scaffold(
      appBar: formAppBar(
        context,
        title: isNew ? 'Thêm ${_type.label}' : 'Sửa ${_type.label}',
        saving: _saving,
        onSave: _save,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 40),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          children: [
            if (isNew)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                child: FormSegmented<ServiceType>(
                  value: _type,
                  options: {for (final t in ServiceType.values) t: t.label},
                  onChanged: (v) => setState(() => _type = v),
                ),
              ),

            FormSection(
              header: 'Thông tin',
              children: [
                FormTextRow(
                  label: nameLabel,
                  controller: _name,
                  hint: nameHint,
                  autofocus: isNew,
                  keyboardType: _type == ServiceType.other ? TextInputType.text : TextInputType.url,
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Bắt buộc' : null,
                ),
                FormValueRow(
                  label: 'Chủ sở hữu',
                  value: data.customer(_customerId)?.name ?? 'Của tôi',
                  onTap: () => _pickCustomer(data),
                ),
                if (_type == ServiceType.hosting)
                  FormSegmented<bool>(
                    value: _onVps,
                    options: const {false: 'Mua từ nhà cung cấp', true: 'Tự tạo trên VPS'},
                    onChanged: (v) => setState(() => _onVps = v),
                  ),
                if (_type == ServiceType.hosting && _onVps)
                  FormValueRow(
                    label: 'Chạy trên VPS',
                    value: data.service(_parentVpsId)?.name,
                    placeholder: vpsList.isEmpty ? 'Chưa có VPS' : 'Chọn VPS',
                    errorText: _showErrors && _parentVpsId == null ? 'Chọn VPS' : null,
                    onTap: vpsList.isEmpty ? null : () => _pickVps(data, vpsList),
                  )
                else
                  FormValueRow(
                    label: 'Nhà cung cấp',
                    value: data.vendor(_vendorId)?.name,
                    placeholder: 'Không chọn',
                    onTap: () => _pickVendor(data),
                  ),
                if (_type == ServiceType.domain)
                  FormValueRow(
                    label: 'Trỏ về hosting',
                    value: data.service(_linkedHostingId)?.name,
                    placeholder: 'Không chọn',
                    onTap: () => _pickLinkedHosting(data),
                  ),
              ],
            ),

            FormSection(
              header: 'Thời hạn',
              footer: _expiryTouched
                  ? 'Ngày hết hạn đang nhập tay.'
                  : 'Ngày hết hạn tự tính = ngày đăng ký + chu kỳ.',
              children: [
                FormDateRow(
                  label: 'Ngày đăng ký',
                  value: _start,
                  allowClear: true,
                  onChanged: (d) => setState(() {
                    _start = d;
                    _recalcExpiry();
                  }),
                ),
                FormValueRow(label: 'Chu kỳ', value: fmtCycle(_cycle), onTap: _pickCycle),
                FormDateRow(
                  label: 'Ngày hết hạn',
                  value: _expiry,
                  valueColor: expiryColor,
                  onChanged: (d) => setState(() {
                    if (d != null) _expiry = d;
                    _expiryTouched = true;
                  }),
                ),
                FormTextRow(
                  label: 'Nhắc trước',
                  controller: _notify,
                  keyboardType: TextInputType.number,
                  inputFormatters: digits,
                  suffix: 'ngày',
                ),
              ],
            ),
            if (_start != null && _expiryTouched)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: 20),
                  child: TextButton(
                    onPressed: () => setState(() {
                      _expiryTouched = false;
                      _recalcExpiry();
                    }),
                    child: const Text('Tính lại hạn theo chu kỳ'),
                  ),
                ),
              ),

            FormSection(
              header: 'Chi phí',
              footer: _customerId == null ? null : 'Giá bán dùng để tính doanh thu trong báo cáo.',
              children: [
                FormTextRow(
                  label: 'Giá vốn',
                  controller: _cost,
                  hint: '0',
                  keyboardType: TextInputType.number,
                  inputFormatters: money,
                  suffix: 'đ',
                ),
                FormTextRow(
                  label: 'Giá bán',
                  controller: _sell,
                  hint: '0',
                  keyboardType: TextInputType.number,
                  inputFormatters: money,
                  suffix: 'đ',
                ),
              ],
            ),

            if (hasServer)
              FormSection(
                header: 'Kỹ thuật',
                children: [
                  FormTextRow(
                    label: 'IP',
                    controller: _ip,
                    hint: '0.0.0.0',
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [IpInputFormatter()],
                  ),
                  FormTextRow(label: 'Panel', controller: _panel, hint: 'cPanel, aaPanel…'),
                  if (_type == ServiceType.vps) ...[
                    FormTextRow(label: 'Hệ điều hành', controller: _os, hint: 'Ubuntu 24.04'),
                    FormTextRow(
                      label: 'CPU',
                      controller: _cpu,
                      hint: '0',
                      keyboardType: TextInputType.number,
                      inputFormatters: digits,
                      suffix: 'core',
                    ),
                    FormTextRow(
                      label: 'RAM',
                      controller: _ram,
                      hint: '0',
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                      suffix: 'GB',
                    ),
                  ],
                  FormTextRow(
                    label: _type == ServiceType.vps ? 'Ổ cứng' : 'Dung lượng',
                    controller: _disk,
                    hint: '0',
                    keyboardType: TextInputType.number,
                    inputFormatters: digits,
                    suffix: 'GB',
                  ),
                ],
              ),

            if (_type == ServiceType.domain)
              FormSection(
                header: 'Nameservers',
                children: [FormNoteRow(controller: _ns, hint: 'ns1.example.com\nns2.example.com', minLines: 2)],
              ),

            FormSection(
              header: 'Ghi chú',
              children: [FormNoteRow(controller: _note)],
            ),
          ],
        ),
      ),
    );
  }
}
