import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:service_manager/core/format.dart';
import 'package:service_manager/data/local_repository.dart';
import 'package:service_manager/data/repository.dart';
import 'package:service_manager/data/storage_config.dart';
import 'package:service_manager/data/sync.dart';
import 'package:service_manager/models/models.dart';

void main() {
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('amv_test'));
  tearDown(() async => dir.delete(recursive: true));

  LocalRepository repo([String name = 'data.json']) => LocalRepository(filePath: '${dir.path}/$name');

  group('LocalRepository (lưu trên máy)', () {
    test('thêm, đọc lại sau khi mở lại file, sắp xếp', () async {
      final r = repo();
      final cid = await r.saveCustomer(Customer(name: 'Bà Phương'));
      await r.saveCustomer(Customer(name: 'A Giang'));
      await r.saveService(Service(
          type: ServiceType.hosting, name: 'b.vn', customerId: cid, expiryDate: DateTime(2027, 4, 1)));
      await r.saveService(Service(type: ServiceType.domain, name: 'a.vn', expiryDate: DateTime(2026, 11, 3)));

      final data = await repo().loadAll(); // đọc lại từ file
      expect(data.customers.map((c) => c.name), ['A Giang', 'Bà Phương']);
      expect(data.services.map((s) => s.name), ['a.vn', 'b.vn']); // theo ngày hết hạn
      expect(data.servicesOf(cid).single.name, 'b.vn');
    });

    test('gia hạn: hạn mới = hạn cũ + chu kỳ, có lịch sử', () async {
      final r = repo();
      final id = await r.saveService(
          Service(type: ServiceType.domain, name: 'x.vn', expiryDate: DateTime(2026, 1, 31)));
      await r.renew(serviceId: id, months: 1, amount: 450000, customerPaid: true);
      final s = (await r.loadAll()).service(id)!;
      expect(s.expiryDate, DateTime(2026, 2, 28));
      final h = await r.loadRenewals(id);
      expect(h.single.amount, 450000);
      expect(toDbDate(h.single.oldExpiry), '2026-01-31');
    });

    test('xoá giữ đúng ràng buộc: xoá khách → dịch vụ thành "của tôi", xoá dịch vụ → xoá lịch sử',
        () async {
      final r = repo();
      final cid = await r.saveCustomer(Customer(name: 'K'));
      final vps = await r.saveService(
          Service(type: ServiceType.vps, name: 'vps', expiryDate: DateTime(2027)));
      final host = await r.saveService(Service(
          type: ServiceType.hosting,
          name: 'h',
          customerId: cid,
          parentVpsId: vps,
          expiryDate: DateTime(2027)));
      await r.renew(serviceId: vps, months: 12);
      await r.deleteCustomer(cid);
      expect((await r.loadAll()).service(host)!.customerId, isNull);
      await r.deleteService(vps);
      expect((await r.loadAll()).service(host)!.parentVpsId, isNull);
      expect(await r.loadRenewals(vps), isEmpty);
    });

    test('xuất / nhập (sao lưu) giữ nguyên dữ liệu và cấu hình kho mật khẩu', () async {
      final a = repo('a.json');
      await a.saveCustomer(Customer(name: 'K', phone: '0909'));
      await a.saveVaultSettings('salt', 'check');
      final json = jsonEncode(BackupFile.wrap(await a.exportTables()));

      final b = repo('b.json');
      await b.importTables(BackupFile.tablesOf(jsonDecode(json) as Map<String, dynamic>));
      expect((await b.loadAll()).customers.single.phone, '0909');
      expect((await b.loadSettings())!['vault_salt'], 'salt');
    });
  });

  group('WebDAV', () {
    late HttpServer server;
    final files = <String, String>{};
    var mkcol = 0;

    setUp(() async {
      files.clear();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        final auth = req.headers.value('authorization');
        if (auth != 'Basic ${base64.encode(utf8.encode('u:p'))}') {
          req.response.statusCode = 401;
        } else if (req.method == 'MKCOL') {
          mkcol++;
          req.response.statusCode = 201;
        } else if (req.method == 'PUT') {
          if (mkcol == 0) {
            req.response.statusCode = 409; // thư mục chưa có
          } else {
            files[req.uri.path] = await utf8.decodeStream(req);
            req.response.statusCode = 201;
          }
        } else if (req.method == 'GET') {
          final f = files[req.uri.path];
          req.response.statusCode = f == null ? 404 : 200;
          if (f != null) req.response.write(f);
        } else if (req.method == 'DELETE') {
          files.remove(req.uri.path);
          req.response.statusCode = 204;
        }
        await req.response.close();
      });
    });
    tearDown(() => server.close(force: true));

    WebDavConfig cfg({String pass = 'p'}) => WebDavConfig(
        enabled: true, url: 'http://127.0.0.1:${server.port}/amv', username: 'u', password: pass);

    test('tạo thư mục khi chưa có, tải lên rồi tải về đúng nội dung', () async {
      final c = WebDavClient(cfg());
      expect(await c.download(), isNull);
      await c.upload('{"a":1}');
      expect(mkcol, greaterThan(0));
      expect(await c.download(), '{"a":1}');
    });

    test('sai mật khẩu báo lỗi rõ ràng', () async {
      expect(() => WebDavClient(cfg(pass: 'x')).test(), throwsA(predicate((e) => '$e'.contains('401'))));
    });
  });
}
