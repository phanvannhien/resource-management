import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../data/repository.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../../widgets/form_kit.dart';

const kCycleOptions = [1, 3, 6, 12, 24, 36];

/// Bottom sheet gia hạn: hạn mới = hạn cũ + số tháng.
Future<void> showRenewSheet(BuildContext context, Service service) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _RenewSheet(service),
  );
}

class _RenewSheet extends ConsumerStatefulWidget {
  const _RenewSheet(this.service);
  final Service service;

  @override
  ConsumerState<_RenewSheet> createState() => _RenewSheetState();
}

class _RenewSheetState extends ConsumerState<_RenewSheet> {
  late int _months = widget.service.cycleMonths;
  // Dịch vụ của khách: _amount = tiền thu của khách, _cost = tiền trả nhà cung cấp.
  // Dịch vụ của mình: chỉ có _cost.
  late final _amount = TextEditingController(text: moneyText(_scaled(widget.service.sellPrice, _months)));
  late final _cost = TextEditingController(text: moneyText(_scaled(widget.service.costPrice, _months)));
  final _note = TextEditingController();
  bool _customerPaid = false;
  late bool _providerPaid = widget.service.isMine;
  bool _saving = false;

  int? _scaled(int? price, int months) =>
      price == null ? null : (price * months / widget.service.cycleMonths).round();

  /// Ghi sổ thu chi cho lần gia hạn này (thu của khách / chi cho nhà cung cấp).
  Future<String?> _writeLedger(DateTime oldExpiry, DateTime newExpiry) async {
    final s = widget.service;
    Txn txn(TxnKind kind, int amount) => Txn(
          kind: kind,
          amount: amount,
          paidAt: today(),
          serviceId: s.id,
          customerId: s.customerId,
          periodFrom: oldExpiry,
          periodTo: newExpiry,
          source: TxnSource.renewal,
          note: emptyToNull(_note.text) ?? 'Gia hạn ${fmtCycle(_months)}',
        );
    final list = [
      if (!s.isMine && _customerPaid && (parseMoney(_amount.text) ?? 0) > 0)
        txn(TxnKind.income, parseMoney(_amount.text)!),
      if (_providerPaid && (parseMoney(_cost.text) ?? 0) > 0) txn(TxnKind.expense, parseMoney(_cost.text)!),
    ];
    if (list.isEmpty) return null;
    try {
      await ref.read(repositoryProvider).addTransactions(list);
      ref.invalidate(transactionsProvider);
      return null;
    } catch (e) {
      return '$e';
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final oldExpiry = widget.service.expiryDate;
      final newExpiry = addMonths(oldExpiry, _months);
      await ref.read(repositoryProvider).renew(
            serviceId: widget.service.id!,
            months: _months,
            amount: widget.service.isMine ? parseMoney(_cost.text) : parseMoney(_amount.text),
            customerPaid: _customerPaid,
            providerPaid: _providerPaid,
            note: emptyToNull(_note.text),
          );
      final ledgerError = await _writeLedger(oldExpiry, newExpiry);
      ref.invalidate(appDataProvider);
      ref.invalidate(renewalsProvider(widget.service.id!));
      if (mounted) {
        Navigator.pop(context);
        showSnack(
          context,
          ledgerError == null
              ? 'Đã gia hạn ${widget.service.name} tới ${fmtDate(newExpiry)}'
              : 'Đã gia hạn, nhưng chưa ghi sổ thu chi: $ledgerError',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showSnack(context, 'Lỗi: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.service;
    final newExpiry = addMonths(s.expiryDate, _months);
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom + 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text('Gia hạn ${s.name}',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 12),
            // Thời hạn gia hạn + hạn cũ → hạn mới
            FormSection(
              header: 'Gia hạn thêm',
              children: [
                FormValueRow(
                  label: 'Thời gian',
                  value: fmtCycle(_months),
                  onTap: () async {
                    final r = await showSelectSheet<int>(
                      context,
                      title: 'Gia hạn thêm',
                      selected: _months,
                      items: [for (final m in kCycleOptions) SelectItem(m, fmtCycle(m))],
                    );
                    if (r != null) {
                      setState(() {
                        _months = r.value;
                        final a = _scaled(s.sellPrice, r.value);
                        final c = _scaled(s.costPrice, r.value);
                        if (a != null) _amount.text = moneyText(a);
                        if (c != null) _cost.text = moneyText(c);
                      });
                    }
                  },
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _DateBox('Hạn hiện tại', s.expiryDate, kGrey),
                      const Icon(Icons.arrow_forward_rounded),
                      _DateBox('Hạn mới', newExpiry, kGreen),
                    ],
                  ),
                ),
              ],
            ),
            FormSection(
              header: 'Thanh toán',
              footer: 'Khoản đã bật "đã thanh toán / đã trả" sẽ được ghi vào Sổ thu chi.',
              children: [
                if (!s.isMine) ...[
                  FormTextRow(
                    label: 'Thu của khách',
                    controller: _amount,
                    hint: '0',
                    keyboardType: TextInputType.number,
                    inputFormatters: [MoneyInputFormatter()],
                    suffix: 'đ',
                  ),
                  FormSwitchRow(
                    label: 'Khách đã thanh toán',
                    value: _customerPaid,
                    onChanged: (v) => setState(() => _customerPaid = v),
                  ),
                ],
                FormTextRow(
                  label: s.isMine ? 'Chi phí' : 'Giá vốn',
                  controller: _cost,
                  hint: '0',
                  keyboardType: TextInputType.number,
                  inputFormatters: [MoneyInputFormatter()],
                  suffix: 'đ',
                ),
                FormSwitchRow(
                  label: 'Đã trả nhà cung cấp',
                  value: _providerPaid,
                  onChanged: (v) => setState(() => _providerPaid = v),
                ),
              ],
            ),
            FormSection(header: 'Ghi chú', children: [FormNoteRow(controller: _note, minLines: 1)]),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox.square(
                        dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.check_rounded),
                label: const Text('Xác nhận gia hạn'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DateBox extends StatelessWidget {
  const _DateBox(this.label, this.date, this.color);
  final String label;
  final DateTime date;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text(label, style: const TextStyle(color: kGrey, fontSize: 12)),
          Text(fmtDate(date),
              style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 18)),
        ],
      );
}
