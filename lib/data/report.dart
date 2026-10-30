import '../core/format.dart';
import '../models/models.dart';
import 'repository.dart';

/// Số liệu của một loại dịch vụ trong năm.
class TypeStat {
  int payments = 0; // số kỳ thanh toán
  int revenue = 0;
  int cost = 0;
}

/// Báo cáo tiền trong một năm.
///
/// Mỗi dịch vụ phát sinh 1 khoản tiền vào mỗi kỳ thanh toán: ngày đăng ký và các mốc
/// "hạn cũ + k × chu kỳ". Dịch vụ đã quá hạn không tính các kỳ sau ngày hết hạn
/// (khách chưa gia hạn), dịch vụ đã ngừng không tính.
/// - Doanh thu = giá bán của dịch vụ của khách.
/// - Chi phí = giá vốn (kể cả VPS/domain của mình).
/// - Đã thu = tổng tiền các lần gia hạn trong năm có đánh dấu "khách đã thanh toán".
class YearReport {
  YearReport(this.year);

  final int year;
  final monthRevenue = List<int>.filled(12, 0);
  final monthCost = List<int>.filled(12, 0);
  final byType = {for (final t in ServiceType.values) t: TypeStat()};
  final byCustomer = <String, int>{};
  int revenue = 0;
  int cost = 0;
  int collected = 0;
  int renewalCount = 0;

  /// Số dịch vụ có doanh thu trong năm nhưng chưa nhập giá vốn.
  int missingCost = 0;

  int get profit => revenue - cost;

  /// Các năm nên cho chọn: từ năm sớm nhất có dữ liệu tới năm sau.
  static List<int> availableYears(AppData data) {
    final now = today().year;
    var first = now;
    for (final s in data.services) {
      final start = s.startDate ?? addMonths(s.expiryDate, -s.cycleMonths);
      if (start.year < first) first = start.year;
    }
    if (first < now - 6) first = now - 6;
    return [for (var y = now + 1; y >= first; y--) y];
  }

  /// Các ngày thanh toán của [s] rơi vào năm [year].
  static List<DateTime> paymentDates(Service s, int year) {
    if (s.cancelled) return const [];
    final e = s.expiryDate;
    final m = s.cycleMonths;
    final start = s.startDate ?? addMonths(e, -m);
    final overdue = s.daysLeft < 0;

    final diff = year * 12 - (e.year * 12 + e.month - 1);
    final kFrom = (diff / m).floor() - 1;
    final kTo = ((diff + 12) / m).ceil() + 1;
    final out = <DateTime>[];
    for (var k = kFrom; k <= kTo; k++) {
      final d = addMonths(e, k * m);
      if (d.year != year) continue;
      if (d.isBefore(start)) continue;
      if (overdue && d.isAfter(e)) continue;
      out.add(d);
    }
    return out;
  }

  static YearReport build(AppData data, List<Renewal> renewals, int year) {
    final r = YearReport(year);
    for (final s in data.services) {
      final dates = paymentDates(s, year);
      if (dates.isEmpty) continue;
      final rev = s.isMine ? 0 : (s.sellPrice ?? 0);
      final cost = s.costPrice ?? 0;
      if (rev > 0 && s.costPrice == null) r.missingCost++;
      final stat = r.byType[s.type]!;
      for (final d in dates) {
        stat.payments++;
        stat.revenue += rev;
        stat.cost += cost;
        r.monthRevenue[d.month - 1] += rev;
        r.monthCost[d.month - 1] += cost;
        r.revenue += rev;
        r.cost += cost;
        if (rev > 0) r.byCustomer[s.customerId!] = (r.byCustomer[s.customerId!] ?? 0) + rev;
      }
    }
    for (final rn in renewals) {
      r.renewalCount++;
      if (rn.customerPaid) r.collected += rn.amount ?? 0;
    }
    return r;
  }
}
