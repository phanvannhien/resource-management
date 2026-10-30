import 'package:flutter_test/flutter_test.dart';
import 'package:service_manager/core/format.dart';
import 'package:service_manager/data/accounting.dart';
import 'package:service_manager/data/repository.dart';
import 'package:service_manager/models/models.dart';

void main() {
  Txn txn(
    int amount,
    DateTime paid, {
    DateTime? from,
    DateTime? to,
    TxnKind kind = TxnKind.income,
    String? sid,
  }) =>
      Txn(kind: kind, amount: amount, paidAt: paid, periodFrom: from, periodTo: to, serviceId: sid);

  group('Phân bổ theo kỳ', () {
    test('hosting 1 năm gia hạn giữa năm: chia theo số ngày cho 2 năm', () {
      // 365 ngày, 01/07/2026 → 01/07/2027: 184 ngày rơi vào 2026
      final t = txn(
        365000,
        DateTime(2026, 7, 1),
        from: DateTime(2026, 7, 1),
        to: DateTime(2027, 7, 1),
      );
      final y26 = allocate(t, 2026, Basis.accrual).fold<double>(0, (a, b) => a + b);
      final y27 = allocate(t, 2027, Basis.accrual).fold<double>(0, (a, b) => a + b);
      expect(y26, closeTo(184000, 1));
      expect(y26 + y27, closeTo(365000, 1));
      expect(allocate(t, 2026, Basis.accrual)[0], 0); // tháng 1 chưa có
    });

    test('thực thu – chi: tính hết vào tháng trả tiền', () {
      final t = txn(
        800000,
        DateTime(2026, 9, 13),
        from: DateTime(2026, 9, 13),
        to: DateTime(2027, 9, 13),
      );
      final m = allocate(t, 2026, Basis.cash);
      expect(m[8], 800000);
      expect(m.fold<double>(0, (a, b) => a + b), 800000);
      expect(allocate(t, 2027, Basis.cash).every((v) => v == 0), isTrue);
    });

    test('khoản không có kỳ: tính vào ngày trả', () {
      final m = allocate(txn(100000, DateTime(2026, 3, 5)), 2026, Basis.accrual);
      expect(m[2], 100000);
    });
  });

  group('Báo cáo & lãi theo VPS', () {
    final vps = Service(
      id: 'v',
      type: ServiceType.vps,
      name: 'VPS',
      expiryDate: DateTime(2027, 2, 9),
      cycleMonths: 1,
      costPrice: 500000,
    );
    final h1 = Service(
      id: 'h1',
      type: ServiceType.hosting,
      name: 'a.vn',
      customerId: 'c',
      parentVpsId: 'v',
      expiryDate: DateTime(2027, 1, 1),
      sellPrice: 1200000,
    );
    final data = AppData(
      customers: [Customer(id: 'c', name: 'K')],
      vendors: const [],
      services: [vps, h1],
    );

    test('lãi = thu − chi, VPS ước tính theo năm', () {
      final txns = [
        txn(
          1200000,
          DateTime(2026, 1, 1),
          from: DateTime(2026, 1, 1),
          to: DateTime(2027, 1, 1),
          sid: 'h1',
        ),
        txn(
          500000,
          DateTime(2026, 6, 9),
          from: DateTime(2026, 6, 9),
          to: DateTime(2026, 7, 9),
          kind: TxnKind.expense,
          sid: 'v',
        ),
      ];
      final r = LedgerReport.build(data, txns, 2026, Basis.accrual);
      expect(r.income, closeTo(1200000, 1));
      expect(r.expense, closeTo(500000, 1));
      expect(r.profit, closeTo(700000, 1));
      final p = VpsProfit.build(data, txns, 2026).single;
      expect(p.estIncome, 1200000);
      expect(p.estExpense, 6000000); // 500k × 12 tháng
      expect(p.bookProfit, closeTo(700000, 1));
    });
  });

  group('Nhập lịch sử các kỳ trước', () {
    test('VPS trả theo tháng: liệt kê từng tháng từ ngày đăng ký tới nay', () {
      final now = today();
      final start = DateTime(now.year, now.month - 3, 9);
      final vps = Service(
        id: 'v',
        type: ServiceType.vps,
        name: 'VPS',
        startDate: start,
        expiryDate: addMonths(start, 4),
        cycleMonths: 1,
        costPrice: 500000,
      );
      final data = AppData(customers: const [], vendors: const [], services: [vps]);
      final items = backfillCandidates(data, const []);
      expect(items.every((i) => i.kind == TxnKind.expense && i.amount == 500000), isTrue);
      expect(items.length, 4); // 4 kỳ đã bắt đầu (kể cả kỳ hiện tại)
      expect(items.first.from, start);
    });

    test('dùng lịch sử gia hạn thật trước, không trùng kỳ đã có', () {
      final vps = Service(
        id: 'v',
        type: ServiceType.vps,
        name: 'VPS',
        startDate: DateTime(2026, 8, 1),
        expiryDate: DateTime(2026, 11, 1),
        cycleMonths: 1,
        costPrice: 500000,
      );
      final data = AppData(customers: const [], vendors: const [], services: [vps]);
      final renewal = Renewal(
        id: 'r',
        serviceId: 'v',
        renewedAt: DateTime(2026, 9, 28),
        oldExpiry: DateTime(2026, 10, 1),
        newExpiry: DateTime(2026, 11, 1),
        months: 1,
        amount: 520000,
      );
      final existing = [
        txn(
          500000,
          DateTime(2026, 8, 1),
          from: DateTime(2026, 8, 1),
          to: DateTime(2026, 9, 1),
          kind: TxnKind.expense,
          sid: 'v',
        ),
      ];
      final items = backfillCandidates(data, existing, renewals: [renewal]);
      final oct = items.singleWhere((i) => i.from == DateTime(2026, 10, 1));
      expect(oct.fromRenewal, isTrue);
      expect(oct.amount, 520000);
      expect(items.any((i) => i.from == DateTime(2026, 8, 1)), isFalse); // đã có trong sổ
      expect(items.where((i) => i.from == DateTime(2026, 9, 1)).single.amount, 500000);
    });
  });
}
