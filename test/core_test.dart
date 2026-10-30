import 'package:flutter_test/flutter_test.dart';
import 'package:service_manager/core/format.dart';
import 'package:service_manager/core/vault_crypto.dart';
import 'package:service_manager/data/report.dart';
import 'package:service_manager/models/models.dart';
import 'package:service_manager/widgets/form_kit.dart';

void main() {
  group('addMonths', () {
    test('cộng tháng bình thường', () {
      expect(addMonths(DateTime(2026, 3, 15), 12), DateTime(2027, 3, 15));
      expect(addMonths(DateTime(2026, 11, 1), 3), DateTime(2027, 2, 1));
    });

    test('giữ cuối tháng giống Postgres', () {
      expect(addMonths(DateTime(2026, 1, 31), 1), DateTime(2026, 2, 28));
      expect(addMonths(DateTime(2028, 1, 31), 1), DateTime(2028, 2, 29));
      expect(addMonths(DateTime(2028, 2, 29), 12), DateTime(2029, 2, 28));
    });
  });

  test('daysBetween chỉ tính phần ngày', () {
    expect(daysBetween(DateTime(2026, 10, 28, 23, 59), DateTime(2026, 10, 29)), 1);
    expect(daysBetween(DateTime(2026, 10, 28), DateTime(2026, 10, 20)), -8);
  });

  group('trạng thái hết hạn', () {
    Service svc(int days, {bool cancelled = false}) => Service(
      type: ServiceType.domain,
      name: 'abc.vn',
      expiryDate: today().add(Duration(days: days)),
      cancelled: cancelled,
    );

    test('theo ngưỡng 15 ngày', () {
      expect(svc(16).state, ExpiryState.ok);
      expect(svc(15).state, ExpiryState.expiring);
      expect(svc(0).state, ExpiryState.expiring);
      expect(svc(-1).state, ExpiryState.expired);
      expect(svc(-1, cancelled: true).state, ExpiryState.cancelled);
      expect(svc(-1, cancelled: true).needsRenewal, isFalse);
    });
  });

  group('VaultCrypto', () {
    test('mã hoá / giải mã và kiểm tra master password', () async {
      final salt = VaultCrypto.newSaltSpec();
      final key = await VaultCrypto.deriveKey('master-pass-123', salt);
      final enc = await VaultCrypto.encrypt(key, 'root@VPS!');
      expect(enc, startsWith('v1:'));
      expect(await VaultCrypto.decrypt(key, enc), 'root@VPS!');

      final check = await VaultCrypto.makeCheck(key);
      expect(await VaultCrypto.verify(key, check), isTrue);
      final wrong = await VaultCrypto.deriveKey('sai-mat-khau', salt);
      expect(await VaultCrypto.verify(wrong, check), isFalse);
    });
  });

  group('YearReport.paymentDates', () {
    final y = today().year;
    Service svc({
      required DateTime expiry,
      DateTime? start,
      int cycle = 12,
      bool cancelled = false,
    }) => Service(
      type: ServiceType.hosting,
      name: 'x',
      customerId: 'c1',
      expiryDate: expiry,
      startDate: start,
      cycleMonths: cycle,
      sellPrice: 800000,
      cancelled: cancelled,
    );

    test('dịch vụ còn hạn, chu kỳ 1 năm: 1 kỳ mỗi năm từ ngày đăng ký', () {
      final s = svc(expiry: DateTime(y + 1, 3, 10), start: DateTime(y - 2, 3, 10));
      expect(YearReport.paymentDates(s, y), [DateTime(y, 3, 10)]);
      expect(YearReport.paymentDates(s, y - 2), [DateTime(y - 2, 3, 10)]);
      expect(YearReport.paymentDates(s, y - 3), isEmpty); // trước ngày đăng ký
      expect(YearReport.paymentDates(s, y + 1), [DateTime(y + 1, 3, 10)]); // kỳ gia hạn sắp tới
    });

    test('chu kỳ 3 tháng: 4 kỳ trong năm', () {
      final s = svc(expiry: DateTime(y + 1, 2, 15), start: DateTime(y - 1, 2, 15), cycle: 3);
      expect(YearReport.paymentDates(s, y).length, 4);
    });

    test('dịch vụ quá hạn không tính các kỳ sau ngày hết hạn', () {
      final s = svc(expiry: DateTime(y - 1, 7, 1), start: DateTime(y - 4, 7, 1));
      expect(YearReport.paymentDates(s, y), isEmpty);
      expect(YearReport.paymentDates(s, y - 1), [DateTime(y - 1, 7, 1)]);
    });

    test('dịch vụ đã ngừng không tính', () {
      final s = svc(expiry: DateTime(y + 1, 1, 1), start: DateTime(y - 1, 1, 1), cancelled: true);
      expect(YearReport.paymentDates(s, y), isEmpty);
    });
  });

  group('Ô nhập tiền', () {
    TextEditingValue type(String text) => MoneyInputFormatter().formatEditUpdate(
      TextEditingValue.empty,
      TextEditingValue(text: text),
    );

    test('tự thêm dấu chấm ngăn cách hàng nghìn', () {
      expect(type('800000').text, '800.000');
      expect(type('1500000').text, '1.500.000');
      expect(type('12a3').text, '123');
      expect(type('').text, '');
    });

    test('đọc lại số từ chuỗi đã định dạng', () {
      expect(parseMoney('1.500.000'), 1500000);
      expect(parseMoney(''), isNull);
      expect(moneyText(800000), '800.000');
      expect(moneyText(null), '');
    });
  });

  test('Ô nhập IP đổi dấu phẩy thành dấu chấm', () {
    String type(String t) => IpInputFormatter()
        .formatEditUpdate(TextEditingValue.empty, TextEditingValue(text: t))
        .text;
    expect(type('103,12,5,8'), '103.12.5.8');
    expect(type('192.168.1.10'), '192.168.1.10');
    expect(type('10 0,0;1'), '100.01');
  });
}
