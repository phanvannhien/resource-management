import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../data/repository.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../../widgets/form_kit.dart';

/// Bảng thêm / sửa một khoản thu chi. [serviceId] = gắn sẵn dịch vụ khi thêm mới.
Future<void> showTxnSheet(BuildContext context, {Txn? existing, String? serviceId}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _TxnSheet(existing: existing, serviceId: serviceId),
    );

class _TxnSheet extends ConsumerStatefulWidget {
  const _TxnSheet({this.existing, this.serviceId});
  final Txn? existing;
  final String? serviceId;

  @override
  ConsumerState<_TxnSheet> createState() => _TxnSheetState();
}

class _TxnSheetState extends ConsumerState<_TxnSheet> {
  late TxnKind _kind = widget.existing?.kind ?? TxnKind.income;
  late String? _serviceId = widget.existing?.serviceId ?? widget.serviceId;
  late DateTime _paidAt = widget.existing?.paidAt ?? today();
  late DateTime? _from = widget.existing?.periodFrom;
  late DateTime? _to = widget.existing?.periodTo;
  late final _amount = TextEditingController(text: moneyText(widget.existing?.amount));
  late final _note = TextEditingController(text: widget.existing?.note);
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  /// Chọn dịch vụ thì tự điền giá và kỳ (nếu chưa nhập).
  void _applyService(Service? s) {
    if (s == null) return;
    final price = _kind == TxnKind.income ? s.sellPrice : s.costPrice;
    if (_amount.text.isEmpty && price != null) _amount.text = moneyText(price);
    if (_from == null && _to == null) {
      _to = s.expiryDate;
      _from = addMonths(s.expiryDate, -s.cycleMonths);
    }
  }

  Future<void> _pickService(AppData data) async {
    final r = await showSelectSheet<String?>(
      context,
      title: 'Dịch vụ',
      selected: _serviceId,
      items: [
        const SelectItem(null, 'Không gắn dịch vụ'),
        for (final s in data.services)
          SelectItem(s.id, s.name,
              subtitle: '${s.type.label} · ${data.ownerName(s)}', icon: s.type.icon, color: typeColor(s.type)),
      ],
    );
    if (r == null) return;
    setState(() {
      _serviceId = r.value;
      _applyService(data.service(r.value));
    });
  }

  Future<void> _save(AppData data) async {
    final amount = parseMoney(_amount.text);
    if (amount == null || amount <= 0) return setState(() => _error = 'Nhập số tiền');
    if ((_from == null) != (_to == null) || (_from != null && !_to!.isAfter(_from!))) {
      return setState(() => _error = 'Kỳ áp dụng chưa đúng (cần cả "từ" và "đến", "đến" sau "từ")');
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(repositoryProvider).saveTransaction(Txn(
            id: widget.existing?.id,
            kind: _kind,
            amount: amount,
            paidAt: _paidAt,
            serviceId: _serviceId,
            customerId: data.service(_serviceId)?.customerId,
            periodFrom: _from,
            periodTo: _to,
            source: widget.existing?.source ?? TxnSource.manual,
            note: emptyToNull(_note.text),
          ));
      ref.invalidate(transactionsProvider);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() {
        _busy = false;
        _error = '$e';
      });
    }
  }

  Future<void> _delete() async {
    if (!await confirm(context, 'Xoá khoản này?', 'Khoản ${fmtMoney(widget.existing!.amount)} sẽ bị xoá khỏi sổ.',
        ok: 'Xoá', danger: true)) {
      return;
    }
    await ref.read(repositoryProvider).deleteTransaction(widget.existing!.id!);
    ref.invalidate(transactionsProvider);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(appDataProvider).value;
    if (data == null) return const SizedBox(height: 200, child: Center(child: CircularProgressIndicator()));
    final service = data.service(_serviceId);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom + 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  if (widget.existing != null)
                    IconButton(
                      tooltip: 'Xoá',
                      icon: const Icon(Icons.delete_outline, color: kRed),
                      onPressed: _busy ? null : _delete,
                    )
                  else
                    const SizedBox(width: 48),
                  Expanded(
                    child: Text(widget.existing == null ? 'Thêm khoản thu chi' : 'Sửa khoản thu chi',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  ),
                  TextButton(
                    onPressed: _busy ? null : () => _save(data),
                    child: const Text('Lưu', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: FormSegmented<TxnKind>(
                value: _kind,
                options: const {TxnKind.income: 'Thu (khách trả)', TxnKind.expense: 'Chi (mình trả)'},
                onChanged: (k) => setState(() => _kind = k),
              ),
            ),
            FormSection(
              children: [
                FormTextRow(
                  label: 'Số tiền',
                  controller: _amount,
                  hint: '0',
                  autofocus: widget.existing == null,
                  keyboardType: TextInputType.number,
                  inputFormatters: [MoneyInputFormatter()],
                  suffix: 'đ',
                ),
                FormDateRow(
                  label: _kind == TxnKind.income ? 'Ngày thu' : 'Ngày chi',
                  value: _paidAt,
                  onChanged: (d) => setState(() => _paidAt = d ?? _paidAt),
                ),
                FormValueRow(
                  label: 'Dịch vụ',
                  value: service?.name,
                  placeholder: 'Không gắn',
                  leading: service == null ? null : TypeBadge(service.type),
                  onTap: () => _pickService(data),
                ),
              ],
            ),
            FormSection(
              header: 'Kỳ áp dụng',
              footer: 'Kỳ dịch vụ mà khoản tiền này trả cho, dùng để phân bổ doanh thu theo tháng. '
                  'Để trống = tính hết vào ngày thu/chi.',
              children: [
                FormDateRow(label: 'Từ ngày', value: _from, allowClear: true, onChanged: (d) => setState(() => _from = d)),
                FormDateRow(label: 'Đến ngày', value: _to, allowClear: true, onChanged: (d) => setState(() => _to = d)),
              ],
            ),
            FormSection(header: 'Ghi chú', children: [FormNoteRow(controller: _note, minLines: 1)]),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 10, 32, 0),
                child: Text(_error!, style: const TextStyle(color: kRed)),
              ),
          ],
        ),
      ),
    );
  }
}
