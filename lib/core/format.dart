import 'package:intl/intl.dart';

final _dateFmt = DateFormat('dd/MM/yyyy');
final _moneyFmt = NumberFormat.decimalPattern('vi_VN');

String fmtDate(DateTime? d) => d == null ? '—' : _dateFmt.format(d);

String fmtMoney(num? v) => v == null ? '—' : '${_moneyFmt.format(v)}đ';

String fmtCycle(int months) {
  if (months % 12 == 0) return '${months ~/ 12} năm';
  return '$months tháng';
}

/// Ngày hôm nay (bỏ giờ), theo giờ máy.
DateTime today() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

/// Số ngày từ [from] tới [to], chỉ tính phần ngày.
int daysBetween(DateTime from, DateTime to) {
  final a = DateTime.utc(from.year, from.month, from.day);
  final b = DateTime.utc(to.year, to.month, to.day);
  return b.difference(a).inDays;
}

/// Cộng tháng, giữ cuối tháng giống Postgres (31/01 + 1 tháng = 28/02).
DateTime addMonths(DateTime d, int months) {
  final total = d.year * 12 + (d.month - 1) + months;
  final year = total ~/ 12;
  final month = total % 12 + 1;
  final lastDay = DateTime(year, month + 1, 0).day;
  return DateTime(year, month, d.day > lastDay ? lastDay : d.day);
}

DateTime? parseDbDate(Object? v) => v == null ? null : DateTime.parse(v as String);

String? toDbDate(DateTime? d) => d == null
    ? null
    : '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String daysLeftLabel(int days) {
  if (days < 0) return 'Quá ${-days} ngày';
  if (days == 0) return 'Hết hạn hôm nay';
  return 'Còn $days ngày';
}

String? emptyToNull(String? s) {
  final t = s?.trim();
  return (t == null || t.isEmpty) ? null : t;
}

/// Tiền dạng gọn: 950k, 9,4 tr, 1,2 tỷ.
String fmtMoneyShort(num v) {
  String trim(double x) {
    final t = x.toStringAsFixed(x >= 100 ? 0 : 1);
    return (t.endsWith('.0') ? t.substring(0, t.length - 2) : t).replaceAll('.', ',');
  }

  final a = v.abs();
  final sign = v < 0 ? '-' : '';
  if (a >= 1e9) return '$sign${trim(a / 1e9)} tỷ';
  if (a >= 1e6) return '$sign${trim(a / 1e6)} tr';
  if (a >= 1e3) return '$sign${trim(a / 1e3)}k';
  return '$sign${a.round()}';
}
