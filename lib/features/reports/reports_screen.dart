import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/format.dart';
import '../../data/accounting.dart';
import '../../data/report.dart';
import '../../data/repository.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../../widgets/form_kit.dart';
import '../../widgets/glass_nav_bar.dart';
import '../../widgets/ui.dart';
import 'txn_sheet.dart';

class _YearController extends Notifier<int> {
  @override
  int build() => today().year;
  void set(int y) => state = y;
}

final reportYearProvider = NotifierProvider<_YearController, int>(_YearController.new);

enum _Tab { report, ledger, vps }

/// Tab Kế toán: Báo cáo · Sổ thu chi · Theo VPS.
class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  _Tab _tab = _Tab.report;
  Basis _basis = Basis.accrual;
  TxnKind? _kind;

  @override
  Widget build(BuildContext context) {
    final year = ref.watch(reportYearProvider);
    final dataAsync = ref.watch(appDataProvider);
    final txnsAsync = ref.watch(transactionsProvider);

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 76,
        title: const PageTitle('Kế toán', icon: Icons.account_balance_wallet_rounded, subtitle: 'Thu chi & lãi'),
        actions: [
          SquareIconButton(
            icon: Icons.history_rounded,
            tooltip: 'Nhập lịch sử các kỳ trước',
            onPressed: () => context.push('/accounting/backfill'),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: FormSegmented<_Tab>(
              value: _tab,
              options: const {_Tab.report: 'Báo cáo', _Tab.ledger: 'Sổ thu chi', _Tab.vps: 'Theo VPS'},
              onChanged: (t) => setState(() => _tab = t),
            ),
          ),
        ),
      ),
      floatingActionButton: _tab == _Tab.ledger
          ? NavBarFab(
              child: FloatingActionButton(
                onPressed: () => showTxnSheet(context),
                child: const Icon(Icons.add),
              ),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(transactionsProvider);
          ref.invalidate(appDataProvider);
          await ref.read(appDataProvider.future);
        },
        child: AsyncView(
          value: dataAsync,
          onRetry: () => ref.invalidate(appDataProvider),
          builder: (data) {
            if (txnsAsync.hasError && !txnsAsync.hasValue) {
              return ListView(children: [_LedgerMissing(txnsAsync.error!)]);
            }
            final txns = txnsAsync.value ?? const <Txn>[];
            final years = {...YearReport.availableYears(data), for (final t in txns) t.paidAt.year}.toList()
              ..sort((a, b) => b.compareTo(a));
            final yearBox = FilterBox<int>(
              label: 'Năm',
              icon: Icons.calendar_month_outlined,
              value: year,
              options: {for (final y in years) y: 'Năm $y'},
              isDefault: year == today().year,
              onSelected: (y) => ref.read(reportYearProvider.notifier).set(y),
            );
            return switch (_tab) {
              _Tab.report => _ReportView(
                  data: data,
                  txns: txns,
                  year: year,
                  basis: _basis,
                  filters: Row(children: [
                    Expanded(child: yearBox),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilterBox<Basis>(
                        label: 'Cách tính',
                        icon: Icons.functions_rounded,
                        expanded: true,
                        value: _basis,
                        options: {for (final b in Basis.values) b: b.label},
                        isDefault: true,
                        onSelected: (b) => setState(() => _basis = b),
                      ),
                    ),
                  ]),
                ),
              _Tab.ledger => _LedgerView(
                  data: data,
                  txns: txns,
                  year: year,
                  kind: _kind,
                  filters: Row(children: [
                    Expanded(child: yearBox),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilterBox<TxnKind?>(
                        label: 'Loại',
                        icon: Icons.swap_vert_rounded,
                        expanded: true,
                        value: _kind,
                        options: const {null: 'Thu & chi', TxnKind.income: 'Chỉ thu', TxnKind.expense: 'Chỉ chi'},
                        isDefault: _kind == null,
                        onSelected: (k) => setState(() => _kind = k),
                      ),
                    ),
                  ]),
                ),
              _Tab.vps => _VpsView(data: data, txns: txns, year: year, filters: Row(children: [yearBox])),
            };
          },
        ),
      ),
    );
  }
}

class _LedgerMissing extends StatelessWidget {
  const _LedgerMissing(this.error);
  final Object error;

  @override
  Widget build(BuildContext context) {
    final missing = error is MissingLedgerTable;
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const IconTile(Icons.table_chart_outlined, color: kOrange, size: 44),
            const SizedBox(height: 12),
            Text(missing ? 'Cần tạo bảng Sổ thu chi' : 'Không tải được sổ thu chi',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(missing
                ? 'Mở Supabase → SQL Editor, dán nội dung file supabase/accounting.sql rồi bấm Run. '
                    'Sau đó kéo xuống để tải lại.'
                : '$error'),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Báo cáo
// ---------------------------------------------------------------------------

class _ReportView extends StatelessWidget {
  const _ReportView({
    required this.data,
    required this.txns,
    required this.year,
    required this.basis,
    required this.filters,
  });

  final AppData data;
  final List<Txn> txns;
  final int year;
  final Basis basis;
  final Widget filters;

  @override
  Widget build(BuildContext context) {
    final r = LedgerReport.build(data, txns, year, basis);
    final forecast = r.forecastIn - r.forecastOut;
    return ListView(
      padding: const EdgeInsets.only(bottom: kNavBarSpace),
      children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 12), child: filters),
        StatGrid(children: [
          StatCard(
              icon: Icons.south_west_rounded,
              value: fmtMoneyShort(r.income),
              label: 'Thu $year',
              color: kGreen),
          StatCard(
              icon: Icons.north_east_rounded,
              value: fmtMoneyShort(r.expense),
              label: 'Chi $year',
              color: kOrange),
          StatCard(
              icon: Icons.trending_up_rounded,
              value: fmtMoneyShort(r.profit),
              label: 'Lãi $year',
              color: r.profit < 0 ? kRed : Brand.accent),
          StatCard(
            icon: Icons.event_repeat_rounded,
            value: fmtMoneyShort(forecast),
            label: 'Dự kiến lãi còn lại',
            color: const Color(0xFF38BDF8),
          ),
        ]),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
          child: Text(
            basis == Basis.accrual
                ? 'Phân bổ theo kỳ: tiền mỗi kỳ dịch vụ được chia đều theo ngày, năm nào dùng dịch vụ thì tính vào năm đó.'
                : 'Thực thu – chi: tính theo ngày tiền thực sự vào / ra.',
            style: const TextStyle(fontSize: 12, color: kGrey),
          ),
        ),
        if (r.txnCount == 0)
          Card(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: ListTile(
              leading: const IconTile(Icons.history_rounded, color: kOrange, size: 40),
              title: Text('Chưa có số liệu năm $year'),
              subtitle: const Text('Nhập lịch sử các kỳ trước để có báo cáo chính xác'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/accounting/backfill'),
            ),
          ),
        const SectionTitle('Thu chi theo tháng'),
        _MonthlyChart(r),
        const SectionTitle('Theo loại dịch vụ'),
        _TypeBreakdown(r),
        const SectionTitle('Top khách hàng'),
        _TopCustomers(report: r, data: data),
        if (r.forecastIn > 0 || r.forecastOut > 0) ...[
          const SectionTitle('Dự kiến tới hết năm'),
          Card(
            child: Column(children: [
              InfoRow('Sắp thu', fmtMoney(r.forecastIn.round()), valueColor: kGreen),
              InfoRow('Sắp chi', fmtMoney(r.forecastOut.round()), valueColor: kOrange),
              InfoRow('Lãi dự kiến', fmtMoney(forecast.round())),
            ]),
          ),
        ],
      ],
    );
  }
}

class _MonthlyChart extends StatelessWidget {
  const _MonthlyChart(this.r);
  final LedgerReport r;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final maxV = [...r.monthIn, ...r.monthOut].reduce(math.max);
    final top = maxV <= 0 ? 1.0 : maxV * 1.25;
    final labelStyle = TextStyle(fontSize: 10, color: scheme.onSurfaceVariant);

    BarChartGroupData group(int i) => BarChartGroupData(
          x: i,
          barsSpace: 2,
          barRods: [
            BarChartRodData(
              toY: r.monthIn[i],
              width: 7,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
              gradient: const LinearGradient(
                  begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Color(0xFF0A9B6A), kGreen]),
            ),
            BarChartRodData(
              toY: r.monthOut[i],
              width: 7,
              color: kOrange,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
            ),
          ],
        );

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 20, 16, 8),
        child: Column(
          children: [
            SizedBox(
              height: 210,
              child: BarChart(
                BarChartData(
                  maxY: top,
                  barGroups: [for (var i = 0; i < 12; i++) group(i)],
                  gridData: FlGridData(
                    drawVerticalLine: false,
                    horizontalInterval: top / 4,
                    getDrawingHorizontalLine: (_) =>
                        FlLine(color: scheme.outlineVariant, strokeWidth: 1, dashArray: [4, 4]),
                  ),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 44,
                        interval: top / 4,
                        getTitlesWidget: (v, meta) => SideTitleWidget(
                          meta: meta,
                          child: Text(v == 0 ? '0' : fmtMoneyShort(v), style: labelStyle),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 24,
                        getTitlesWidget: (v, meta) =>
                            SideTitleWidget(meta: meta, child: Text('${v.toInt() + 1}', style: labelStyle)),
                      ),
                    ),
                  ),
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipColor: (_) => scheme.surface,
                      tooltipBorderRadius: BorderRadius.circular(10),
                      getTooltipItem: (g, _, rod, rodIndex) => BarTooltipItem(
                        '${rodIndex == 0 ? 'Thu' : 'Chi'} T${g.x + 1}\n${fmtMoney(rod.toY.round())}',
                        TextStyle(
                            color: rodIndex == 0 ? kGreen : kOrange, fontWeight: FontWeight.w600, fontSize: 12),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(top: 8, left: 8),
              child: Row(children: [
                _Legend(color: kGreen, label: 'Thu'),
                SizedBox(width: 16),
                _Legend(color: kOrange, label: 'Chi'),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ],
      );
}

class _TypeBreakdown extends StatelessWidget {
  const _TypeBreakdown(this.r);
  final LedgerReport r;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final types = r.byType.keys.toList()
      ..sort((a, b) => (r.byType[b]!.income - r.byType[b]!.expense)
          .compareTo(r.byType[a]!.income - r.byType[a]!.expense));
    if (types.isEmpty) return const Card(child: EmptyState('Chưa có khoản thu chi nào trong năm này'));
    return Card(
      child: Column(
        children: [
          for (var i = 0; i < types.length; i++) ...[
            Builder(builder: (_) {
              final t = types[i];
              final tt = r.byType[t]!;
              final color = t == null ? kGrey : typeColor(t);
              final profit = tt.income - tt.expense;
              return ListTile(
                leading: IconTile(t?.icon ?? Icons.receipt_long_rounded, color: color, size: 40),
                title: Text(t == null ? 'Khoản khác' : (t == ServiceType.other ? 'Bảo trì / khác' : t.label),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text('Thu ${fmtMoneyShort(tt.income)} · Chi ${fmtMoneyShort(tt.expense)}'),
                trailing: Text(fmtMoneyShort(profit),
                    style: TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 15, color: profit < 0 ? kRed : kGreen)),
              );
            }),
            if (i < types.length - 1) Divider(height: 1, indent: 16, endIndent: 16, color: scheme.outlineVariant),
          ],
        ],
      ),
    );
  }
}

class _TopCustomers extends StatelessWidget {
  const _TopCustomers({required this.report, required this.data});
  final LedgerReport report;
  final AppData data;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final top = (report.byCustomer.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).take(5).toList();
    if (top.isEmpty) return const Card(child: EmptyState('Chưa có khoản thu từ khách hàng'));
    final max = top.first.value;
    return Card(
      child: Column(
        children: [
          for (var i = 0; i < top.length; i++)
            ListTile(
              onTap: () => context.push('/customer/${top[i].key}'),
              leading: Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: (i == 0 ? Brand.mint : Brand.accent).withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Text('${i + 1}',
                    style: TextStyle(fontWeight: FontWeight.w800, color: i == 0 ? Brand.mint : Brand.accent)),
              ),
              title: Text(data.customer(top[i].key)?.name ?? '—', style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                      value: top[i].value / max,
                      minHeight: 4,
                      color: Brand.accent,
                      backgroundColor: scheme.outlineVariant),
                ),
              ),
              trailing: Text(fmtMoneyShort(top[i].value), style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sổ thu chi
// ---------------------------------------------------------------------------

class _LedgerView extends StatelessWidget {
  const _LedgerView({
    required this.data,
    required this.txns,
    required this.year,
    required this.kind,
    required this.filters,
  });

  final AppData data;
  final List<Txn> txns;
  final int year;
  final TxnKind? kind;
  final Widget filters;

  @override
  Widget build(BuildContext context) {
    final inYear = txns.where((t) => t.paidAt.year == year).toList();
    final list = inYear.where((t) => kind == null || t.kind == kind).toList();
    final income = inYear.where((t) => t.isIncome).fold(0, (a, t) => a + t.amount);
    final expense = inYear.where((t) => !t.isIncome).fold(0, (a, t) => a + t.amount);

    final byMonth = <int, List<Txn>>{};
    for (final t in list) {
      byMonth.putIfAbsent(t.paidAt.month, () => []).add(t);
    }
    final months = byMonth.keys.toList()..sort((a, b) => b.compareTo(a));

    return ListView(
      padding: const EdgeInsets.only(bottom: kNavBarSpace),
      children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 8), child: filters),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(children: [
              _Total('Thu', income, kGreen),
              _Total('Chi', expense, kOrange),
              _Total('Còn lại', income - expense, income - expense < 0 ? kRed : Brand.accent),
            ]),
          ),
        ),
        if (list.isEmpty)
          Card(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Column(children: [
              const EmptyState('Chưa có khoản thu chi nào'),
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: TextButton.icon(
                  icon: const Icon(Icons.history_rounded),
                  label: const Text('Nhập lịch sử các kỳ trước'),
                  onPressed: () => context.push('/accounting/backfill'),
                ),
              ),
            ]),
          ),
        for (final m in months) ...[
          SectionTitle('Tháng $m/$year'),
          Card(child: Column(children: [for (final t in byMonth[m]!) TxnTile(txn: t, data: data)])),
        ],
      ],
    );
  }
}

class _Total extends StatelessWidget {
  const _Total(this.label, this.value, this.color);
  final String label;
  final num value;
  final Color color;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(children: [
          Text(label, style: const TextStyle(fontSize: 12, color: kGrey)),
          const SizedBox(height: 2),
          FittedBox(
            child: Text(fmtMoneyShort(value),
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: color)),
          ),
        ]),
      );
}

/// Một dòng trong sổ thu chi.
class TxnTile extends StatelessWidget {
  const TxnTile({super.key, required this.txn, required this.data, this.showService = true});
  final Txn txn;
  final AppData data;
  final bool showService;

  @override
  Widget build(BuildContext context) {
    final t = txn;
    final s = data.service(t.serviceId);
    final c = data.customer(t.customerId ?? s?.customerId);
    final color = t.isIncome ? kGreen : kOrange;
    final title = showService ? (s?.name ?? t.note ?? (t.isIncome ? 'Khoản thu' : 'Khoản chi')) : (t.note ?? t.kind.label);
    return ListTile(
      onTap: () => showTxnSheet(context, existing: t),
      leading: IconTile(t.isIncome ? Icons.south_west_rounded : Icons.north_east_rounded, color: color, size: 38),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
        [
          fmtDate(t.paidAt),
          if (showService && c != null) c.name,
          if (t.periodFrom != null && t.periodTo != null) 'kỳ ${fmtDate(t.periodFrom)}–${fmtDate(t.periodTo)}',
        ].join(' · '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text('${t.isIncome ? '+' : '−'}${fmtMoney(t.amount)}',
          style: TextStyle(fontWeight: FontWeight.w700, color: color)),
    );
  }
}

// ---------------------------------------------------------------------------
// Theo VPS
// ---------------------------------------------------------------------------

class _VpsView extends StatelessWidget {
  const _VpsView({required this.data, required this.txns, required this.year, required this.filters});
  final AppData data;
  final List<Txn> txns;
  final int year;
  final Widget filters;

  @override
  Widget build(BuildContext context) {
    final list = VpsProfit.build(data, txns, year);
    return ListView(
      padding: const EdgeInsets.only(bottom: kNavBarSpace),
      children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 8), child: filters),
        if (list.isEmpty) const Card(child: EmptyState('Chưa có VPS nào')),
        for (final p in list) _VpsCard(p: p, year: year),
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Text(
            'Ước tính / năm: theo giá bán, giá vốn và chu kỳ hiện tại của VPS và các hosting trên nó.\n'
            'Theo sổ: khoản thu chi đã ghi của VPS và các hosting đó trong năm (phân bổ theo kỳ).',
            style: TextStyle(fontSize: 12, color: kGrey),
          ),
        ),
      ],
    );
  }
}

class _VpsCard extends StatelessWidget {
  const _VpsCard({required this.p, required this.year});
  final VpsProfit p;
  final int year;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget col(String label, double v, Color color) => Expanded(
          child: Column(children: [
            Text(label, style: const TextStyle(fontSize: 11.5, color: kGrey)),
            const SizedBox(height: 2),
            FittedBox(
                child: Text(fmtMoneyShort(v), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: color))),
          ]),
        );
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            onTap: () => context.push('/service/${p.vps.id}'),
            leading: IconTile(Icons.storage_rounded, color: typeColor(ServiceType.vps), size: 42),
            title: Text(p.vps.name, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('${p.hostings.length} hosting · chi phí ${fmtMoney(p.vps.costPrice)} / ${fmtCycle(p.vps.cycleMonths)}'),
            trailing: const Icon(Icons.chevron_right),
          ),
          Divider(height: 1, color: scheme.outlineVariant),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 10, 16, 2),
            child: Text('ƯỚC TÍNH / NĂM', style: TextStyle(fontSize: 11, color: kGrey, letterSpacing: 0.4)),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(children: [
              col('Thu', p.estIncome, kGreen),
              col('Chi', p.estExpense, kOrange),
              col('Lãi', p.estProfit, p.estProfit < 0 ? kRed : Brand.accent),
            ]),
          ),
          Divider(height: 1, indent: 16, endIndent: 16, color: scheme.outlineVariant),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
            child: Text('THEO SỔ NĂM $year', style: const TextStyle(fontSize: 11, color: kGrey, letterSpacing: 0.4)),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(children: [
              col('Thu', p.bookIncome, kGreen),
              col('Chi', p.bookExpense, kOrange),
              col('Lãi', p.bookProfit, p.bookProfit < 0 ? kRed : Brand.accent),
            ]),
          ),
          if (p.hostings.isNotEmpty) ...[
            Divider(height: 1, color: scheme.outlineVariant),
            for (final h in p.hostings)
              ListTile(
                dense: true,
                onTap: () => context.push('/service/${h.id}'),
                title: Text(h.name),
                trailing: Text(
                  h.sellPrice == null ? 'chưa có giá' : '${fmtMoneyShort(h.sellPrice!)} / ${fmtCycle(h.cycleMonths)}',
                  style: TextStyle(color: h.sellPrice == null ? kOrange : scheme.onSurfaceVariant),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
