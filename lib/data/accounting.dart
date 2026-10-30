import '../core/format.dart';
import '../models/models.dart';
import 'report.dart';
import 'repository.dart';

/// Cách tính số liệu trong báo cáo kế toán.
enum Basis {
  /// Theo ngày thu/chi tiền thực tế.
  cash('Thực thu – chi'),

  /// Chia đều tiền của mỗi kỳ dịch vụ theo từng ngày (chuẩn kế toán).
  accrual('Phân bổ theo kỳ');

  const Basis(this.label);
  final String label;
}

DateTime _d(DateTime x) => DateTime.utc(x.year, x.month, x.day);

/// Số tiền của [t] rơi vào từng tháng của năm [year] theo cách tính [basis].
List<double> allocate(Txn t, int year, Basis basis) {
  final m = List<double>.filled(12, 0);
  final from = t.periodFrom, to = t.periodTo;
  if (basis == Basis.cash || from == null || to == null || !to.isAfter(from)) {
    if (t.paidAt.year == year) m[t.paidAt.month - 1] += t.amount;
    return m;
  }
  final f = _d(from), e = _d(to);
  final perDay = t.amount / e.difference(f).inDays;
  for (var i = 0; i < 12; i++) {
    final ms = DateTime.utc(year, i + 1, 1), me = DateTime.utc(year, i + 2, 1);
    final s = f.isAfter(ms) ? f : ms, en = e.isBefore(me) ? e : me;
    final days = en.difference(s).inDays;
    if (days > 0) m[i] += days * perDay;
  }
  return m;
}

class TypeTotals {
  double income = 0;
  double expense = 0;
}

class LedgerReport {
  LedgerReport(this.year, this.basis);

  final int year;
  final Basis basis;
  final monthIn = List<double>.filled(12, 0);
  final monthOut = List<double>.filled(12, 0);

  /// Theo loại dịch vụ (null = khoản không gắn dịch vụ).
  final byType = <ServiceType?, TypeTotals>{};
  final byCustomer = <String, double>{};
  double income = 0;
  double expense = 0;
  int txnCount = 0;

  /// Dự kiến từ hôm nay tới hết năm (theo giá & chu kỳ của dịch vụ đang dùng).
  double forecastIn = 0;
  double forecastOut = 0;

  double get profit => income - expense;

  static LedgerReport build(AppData data, List<Txn> txns, int year, Basis basis) {
    final r = LedgerReport(year, basis);
    for (final t in txns) {
      final m = allocate(t, year, basis);
      final sum = m.fold<double>(0, (a, b) => a + b);
      if (sum == 0) continue;
      r.txnCount++;
      final type = data.service(t.serviceId)?.type;
      final tt = r.byType.putIfAbsent(type, TypeTotals.new);
      for (var i = 0; i < 12; i++) {
        (t.isIncome ? r.monthIn : r.monthOut)[i] += m[i];
      }
      if (t.isIncome) {
        r.income += sum;
        tt.income += sum;
        final cid = t.customerId ?? data.service(t.serviceId)?.customerId;
        if (cid != null) r.byCustomer[cid] = (r.byCustomer[cid] ?? 0) + sum;
      } else {
        r.expense += sum;
        tt.expense += sum;
      }
    }

    // Dự kiến: các kỳ thanh toán còn lại trong năm
    final now = today();
    if (year >= now.year) {
      for (final s in data.services) {
        for (final d in YearReport.paymentDates(s, year)) {
          if (!d.isAfter(now)) continue;
          if (!s.isMine) r.forecastIn += s.sellPrice ?? 0;
          r.forecastOut += s.costPrice ?? 0;
        }
      }
    }
    return r;
  }
}

/// Lãi của một VPS: thu từ các hosting chạy trên nó trừ chi phí của chính VPS.
class VpsProfit {
  VpsProfit(this.vps, this.hostings);
  final Service vps;
  final List<Service> hostings;

  /// Theo giá & chu kỳ hiện tại, quy ra 1 năm.
  double estIncome = 0;
  double estExpense = 0;

  /// Theo sổ thu chi trong năm (phân bổ theo kỳ).
  double bookIncome = 0;
  double bookExpense = 0;

  double get estProfit => estIncome - estExpense;
  double get bookProfit => bookIncome - bookExpense;

  static double _perYear(int? price, int cycle) => (price ?? 0) * 12 / cycle;

  static List<VpsProfit> build(AppData data, List<Txn> txns, int year) {
    final out = <VpsProfit>[];
    for (final vps in data.activeVps) {
      final hostings = data.hostingsOn(vps.id!);
      final p = VpsProfit(vps, hostings);
      p.estExpense = _perYear(vps.costPrice, vps.cycleMonths) +
          hostings.fold(0.0, (a, h) => a + _perYear(h.costPrice, h.cycleMonths));
      p.estIncome = hostings.where((h) => !h.isMine).fold(0.0, (a, h) => a + _perYear(h.sellPrice, h.cycleMonths));
      final ids = {vps.id, for (final h in hostings) h.id};
      for (final t in txns.where((t) => ids.contains(t.serviceId))) {
        final sum = allocate(t, year, Basis.accrual).fold<double>(0, (a, b) => a + b);
        if (t.isIncome) {
          p.bookIncome += sum;
        } else {
          p.bookExpense += sum;
        }
      }
      out.add(p);
    }
    return out;
  }
}

/// Một khoản đề xuất khi "Tạo lịch sử các kỳ trước".
class BackfillItem {
  BackfillItem({
    required this.service,
    required this.kind,
    required this.from,
    required this.to,
    required this.amount,
    this.paidAt,
    this.fromRenewal = false,
  });
  final Service service;
  final TxnKind kind;
  final DateTime from, to;

  /// Ngày trả thật (lấy từ lịch sử gia hạn); null = coi như trả vào đầu kỳ.
  final DateTime? paidAt;

  /// Lấy từ lịch sử gia hạn đã lưu (số liệu thật) thay vì ước tính theo chu kỳ.
  final bool fromRenewal;
  int amount;
  bool selected = true;

  Txn toTxn() => Txn(
        kind: kind,
        amount: amount,
        paidAt: paidAt ?? from,
        serviceId: service.id,
        customerId: service.customerId,
        periodFrom: from,
        periodTo: to,
        source: TxnSource.backfill,
        note: fromRenewal ? 'Từ lịch sử gia hạn' : 'Nhập bù kỳ ${fmtDate(from)} – ${fmtDate(to)}',
      );
}

/// Liệt kê các kỳ đã qua (tính lùi từ ngày hết hạn theo chu kỳ, tới ngày đăng ký) chưa có trong sổ.
/// Mỗi kỳ: 1 khoản Thu (giá bán, nếu là dịch vụ của khách) và 1 khoản Chi (giá vốn, nếu có).
/// Các lần gia hạn đã lưu ([renewals]) được dùng trước, đúng ngày và số tiền thật.
List<BackfillItem> backfillCandidates(
  AppData data,
  List<Txn> txns, {
  List<Renewal> renewals = const [],
  String? serviceId,
}) {
  final now = today();
  final have = <String>{
    for (final t in txns)
      if (t.serviceId != null && t.periodFrom != null) '${t.serviceId}|${t.kind.db}|${toDbDate(t.periodFrom)}',
  };
  final out = <BackfillItem>[];
  final services = data.services.where((s) => serviceId == null ? true : s.id == serviceId);

  // 1. Lịch sử gia hạn đã lưu
  for (final r in renewals) {
    final s = data.service(r.serviceId);
    if (s == null || (serviceId != null && s.id != serviceId)) continue;
    void add(TxnKind kind, int? amount) {
      if (amount == null || amount <= 0) return;
      final key = '${s.id}|${kind.db}|${toDbDate(r.oldExpiry)}';
      if (!have.add(key)) return;
      out.add(BackfillItem(
        service: s,
        kind: kind,
        from: r.oldExpiry,
        to: r.newExpiry,
        amount: amount,
        paidAt: DateTime(r.renewedAt.year, r.renewedAt.month, r.renewedAt.day),
        fromRenewal: true,
      ));
    }

    if (s.isMine) {
      add(TxnKind.expense, r.amount ?? s.costPrice);
    } else {
      add(TxnKind.income, r.amount ?? s.sellPrice);
      if (s.costPrice != null) add(TxnKind.expense, (s.costPrice! * r.months / s.cycleMonths).round());
    }
  }

  // 2. Các kỳ còn lại ước tính theo chu kỳ & giá
  for (final s in services) {
    final m = s.cycleMonths;
    final first = s.startDate ?? addMonths(s.expiryDate, -m);
    // Các kỳ: [hết hạn − (k+1)·chu kỳ, hết hạn − k·chu kỳ), chỉ lấy kỳ đã bắt đầu
    for (var k = 0; k < 600; k++) {
      final to = addMonths(s.expiryDate, -k * m);
      final from = addMonths(s.expiryDate, -(k + 1) * m);
      if (from.isBefore(first) && daysBetween(first, from).abs() > 3) break;
      if (from.isAfter(now)) continue;
      for (final kind in TxnKind.values) {
        final price = kind == TxnKind.income ? (s.isMine ? null : s.sellPrice) : s.costPrice;
        if (price == null || price == 0) continue;
        if (have.contains('${s.id}|${kind.db}|${toDbDate(from)}')) continue;
        out.add(BackfillItem(service: s, kind: kind, from: from, to: to, amount: price));
      }
    }
  }
  out.sort((a, b) {
    final c = a.service.name.compareTo(b.service.name);
    return c != 0 ? c : a.from.compareTo(b.from);
  });
  return out;
}
