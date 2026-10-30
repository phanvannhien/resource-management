import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../data/accounting.dart';
import '../../data/repository.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../../widgets/form_kit.dart';

final _allRenewalsProvider =
    FutureProvider.autoDispose<List<Renewal>>((ref) => ref.watch(repositoryProvider).loadAllRenewals());

/// Nhập bù lịch sử: liệt kê các kỳ đã qua (theo ngày đăng ký + chu kỳ + giá) chưa có trong sổ,
/// cho bỏ chọn / sửa số tiền rồi lưu vào sổ thu chi.
class BackfillScreen extends ConsumerStatefulWidget {
  const BackfillScreen({super.key, this.serviceId});
  final String? serviceId;

  @override
  ConsumerState<BackfillScreen> createState() => _BackfillScreenState();
}

class _BackfillScreenState extends ConsumerState<BackfillScreen> {
  List<BackfillItem>? _items;
  bool _saving = false;

  AppData? _source;

  /// Tính danh sách; tính lại khi dữ liệu dịch vụ đổi (vd: vừa nhập giá rồi quay lại).
  void _init(AppData data, List<Txn> txns, List<Renewal> renewals) {
    if (_items != null && identical(_source, data)) return;
    _source = data;
    _items = backfillCandidates(data, txns, renewals: renewals, serviceId: widget.serviceId);
  }

  Future<void> _save() async {
    final chosen = _items!.where((i) => i.selected && i.amount > 0).toList();
    if (chosen.isEmpty) return;
    setState(() => _saving = true);
    try {
      await ref.read(repositoryProvider).addTransactions([for (final i in chosen) i.toTxn()]);
      ref.invalidate(transactionsProvider);
      if (mounted) {
        context.pop();
        showSnack(context, 'Đã ghi ${chosen.length} khoản vào sổ thu chi');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showSnack(context, 'Lỗi: $e');
      }
    }
  }

  Future<void> _editAmount(BackfillItem item) async {
    final c = TextEditingController(text: moneyText(item.amount));
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom + 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('${item.kind == TxnKind.income ? 'Thu' : 'Chi'} kỳ ${fmtDate(item.from)} – ${fmtDate(item.to)}',
                textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            FormSection(children: [
              FormTextRow(
                label: 'Số tiền',
                controller: c,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [MoneyInputFormatter()],
                suffix: 'đ',
              ),
            ]),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Xong')),
            ),
          ],
        ),
      ),
    );
    if (ok == true) setState(() => item.amount = parseMoney(c.text) ?? item.amount);
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(appDataProvider).value;
    final txns = ref.watch(transactionsProvider);
    final renewals = ref.watch(_allRenewalsProvider);
    if (data != null && txns.hasValue && renewals.hasValue) _init(data, txns.value!, renewals.value!);
    final count = _items?.where((i) => i.selected).length ?? 0;

    return Scaffold(
      appBar: formAppBar(
        context,
        title: 'Nhập lịch sử thu chi',
        saving: _saving,
        saveLabel: 'Lưu ($count)',
        onSave: count == 0 ? null : _save,
      ),
      body: () {
        if (txns.hasError && !txns.hasValue) {
          return Padding(padding: const EdgeInsets.all(24), child: Text('${txns.error}'));
        }
        if (data == null || !txns.hasValue || !renewals.hasValue) {
          return const Center(child: CircularProgressIndicator());
        }
        _init(data, txns.value!, renewals.value ?? const []);
        final items = _items!;
        final services = <Service, List<BackfillItem>>{};
        for (final i in items) {
          services.putIfAbsent(i.service, () => []).add(i);
        }
        final noPrice = data.services.where((s) =>
            (widget.serviceId == null || s.id == widget.serviceId) &&
            (s.isMine ? s.costPrice == null : s.sellPrice == null));

        return ListView(
          padding: const EdgeInsets.only(bottom: 40),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: Text(
                'App tính các kỳ đã qua từ ngày đăng ký, chu kỳ và giá của từng dịch vụ. '
                'Bỏ chọn kỳ không đúng, bấm số tiền để sửa nếu từng đổi giá, rồi bấm Lưu.\n'
                'Thu = giá bán (dịch vụ của khách) · Chi = giá vốn. Kỳ đã có trong sổ sẽ không hiện lại.',
                style: TextStyle(fontSize: 12.5, color: kGrey),
              ),
            ),
            if (items.isEmpty)
              const Card(
                margin: EdgeInsets.all(16),
                child: EmptyState('Không còn kỳ nào cần nhập', icon: Icons.check_circle_outline),
              ),
            for (final e in services.entries)
              FormSection(
                header: '${e.key.name} · ${data.ownerName(e.key)} · ${fmtCycle(e.key.cycleMonths)}',
                children: [
                  for (final i in e.value)
                    CheckboxListTile(
                      value: i.selected,
                      onChanged: (v) => setState(() => i.selected = v!),
                      controlAffinity: ListTileControlAffinity.leading,
                      dense: true,
                      title: Text('${fmtDate(i.from)} – ${fmtDate(i.to)}'),
                      subtitle: Text([
                        i.kind == TxnKind.income ? 'Thu của khách' : 'Chi cho nhà cung cấp',
                        if (i.fromRenewal) 'đã gia hạn ${fmtDate(i.paidAt)}',
                      ].join(' · ')),
                      secondary: InkWell(
                        onTap: () => _editAmount(i),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Text(
                            '${i.kind == TxnKind.income ? '+' : '−'}${fmtMoney(i.amount)}',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: i.kind == TxnKind.income ? kGreen : kOrange,
                              decoration: TextDecoration.underline,
                              decorationStyle: TextDecorationStyle.dotted,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            if (noPrice.isNotEmpty)
              FormSection(
                header: 'Chưa có giá (không tạo được lịch sử)',
                footer: 'Nhập giá bán / giá vốn cho các dịch vụ này rồi quay lại đây.',
                children: [
                  for (final s in noPrice)
                    FormValueRow(
                      label: s.name,
                      value: s.isMine ? 'thiếu giá vốn' : 'thiếu giá bán',
                      valueColor: kOrange,
                      onTap: () => context.push('/service/${s.id}/edit'),
                    ),
                ],
              ),
          ],
        );
      }(),
    );
  }
}
