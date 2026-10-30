import 'package:flutter/material.dart';

import '../core/format.dart';

int? _int(Object? v) => (v as num?)?.toInt();
double? _double(Object? v) => (v as num?)?.toDouble();

// ============================================================
// Khách hàng
// ============================================================
class Customer {
  Customer({
    this.id,
    required this.name,
    this.phone,
    this.email,
    this.zalo,
    this.company,
    this.note,
    this.isActive = true,
  });

  final String? id;
  final String name;
  final String? phone, email, zalo, company, note;
  final bool isActive;

  /// Số dùng cho Zalo: ưu tiên trường zalo, không có thì dùng số điện thoại.
  String? get zaloPhone => zalo ?? phone;

  factory Customer.fromJson(Map<String, dynamic> j) => Customer(
        id: j['id'] as String,
        name: j['name'] as String,
        phone: j['phone'] as String?,
        email: j['email'] as String?,
        zalo: j['zalo'] as String?,
        company: j['company'] as String?,
        note: j['note'] as String?,
        isActive: j['is_active'] as bool? ?? true,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'phone': phone,
        'email': email,
        'zalo': zalo,
        'company': company,
        'note': note,
        'is_active': isActive,
      };
}

// ============================================================
// Nhà cung cấp
// ============================================================
class Vendor {
  Vendor({this.id, required this.name, this.website, this.supportContact, this.note});

  final String? id;
  final String name;
  final String? website, supportContact, note;

  factory Vendor.fromJson(Map<String, dynamic> j) => Vendor(
        id: j['id'] as String,
        name: j['name'] as String,
        website: j['website'] as String?,
        supportContact: j['support_contact'] as String?,
        note: j['note'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'website': website,
        'support_contact': supportContact,
        'note': note,
      };
}

// ============================================================
// Dịch vụ: Domain / Hosting / VPS
// ============================================================
enum ServiceType {
  domain('DOMAIN', 'Domain', Icons.language),
  hosting('HOSTING', 'Hosting', Icons.dns_outlined),
  vps('VPS', 'VPS', Icons.storage),
  other('OTHER', 'Khác', Icons.build_outlined); // bảo trì, SSL, email...

  const ServiceType(this.db, this.label, this.icon);
  final String db;
  final String label;
  final IconData icon;

  static ServiceType fromDb(String v) => values.firstWhere((e) => e.db == v);
}

enum ExpiryState { ok, expiring, expired, cancelled }

class Service {
  Service({
    this.id,
    required this.type,
    required this.name,
    this.customerId,
    this.vendorId,
    this.parentVpsId,
    this.startDate,
    required this.expiryDate,
    this.cycleMonths = 12,
    this.costPrice,
    this.sellPrice,
    this.notifyDays = 15,
    this.cancelled = false,
    this.note,
    this.ip,
    this.os,
    this.cpu,
    this.ramGb,
    this.diskGb,
    this.panel,
    this.nameservers,
    this.linkedHostingId,
  });

  final String? id;
  final ServiceType type;
  final String name;
  final String? customerId; // null = của mình
  final String? vendorId;
  final String? parentVpsId;
  final DateTime? startDate;
  final DateTime expiryDate;
  final int cycleMonths;
  final int? costPrice, sellPrice;
  final int notifyDays;
  final bool cancelled;
  final String? note;
  final String? ip, os, panel, nameservers, linkedHostingId;
  final int? cpu, diskGb;
  final double? ramGb;

  bool get isMine => customerId == null;

  int get daysLeft => daysBetween(today(), expiryDate);

  ExpiryState get state {
    if (cancelled) return ExpiryState.cancelled;
    final d = daysLeft;
    if (d < 0) return ExpiryState.expired;
    if (d <= notifyDays) return ExpiryState.expiring;
    return ExpiryState.ok;
  }

  /// Cần gia hạn = sắp hết hạn hoặc đã quá hạn (không tính dịch vụ đã ngừng).
  bool get needsRenewal => state == ExpiryState.expiring || state == ExpiryState.expired;

  factory Service.fromJson(Map<String, dynamic> j) => Service(
        id: j['id'] as String,
        type: ServiceType.fromDb(j['type'] as String),
        name: j['name'] as String,
        customerId: j['customer_id'] as String?,
        vendorId: j['provider_id'] as String?,
        parentVpsId: j['parent_vps_id'] as String?,
        startDate: parseDbDate(j['start_date']),
        expiryDate: parseDbDate(j['expiry_date'])!,
        cycleMonths: _int(j['cycle_months']) ?? 12,
        costPrice: _int(j['cost_price']),
        sellPrice: _int(j['sell_price']),
        notifyDays: _int(j['notify_days']) ?? 15,
        cancelled: j['status'] == 'CANCELLED',
        note: j['note'] as String?,
        ip: j['ip'] as String?,
        os: j['os'] as String?,
        cpu: _int(j['cpu']),
        ramGb: _double(j['ram_gb']),
        diskGb: _int(j['disk_gb']),
        panel: j['panel'] as String?,
        nameservers: j['nameservers'] as String?,
        linkedHostingId: j['linked_hosting_id'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'type': type.db,
        'name': name,
        'customer_id': customerId,
        'provider_id': vendorId,
        'parent_vps_id': parentVpsId,
        'start_date': toDbDate(startDate),
        'expiry_date': toDbDate(expiryDate),
        'cycle_months': cycleMonths,
        'cost_price': costPrice,
        'sell_price': sellPrice,
        'notify_days': notifyDays,
        'status': cancelled ? 'CANCELLED' : 'ACTIVE',
        'note': note,
        'ip': ip,
        'os': os,
        'cpu': cpu,
        'ram_gb': ramGb,
        'disk_gb': diskGb,
        'panel': panel,
        'nameservers': nameservers,
        'linked_hosting_id': linkedHostingId,
      };
}

// ============================================================
// Tài khoản đăng nhập
// ============================================================
enum AccountKind {
  portal('PORTAL', 'Trang nhà cung cấp', Icons.public),
  controlPanel('CONTROL_PANEL', 'Control panel', Icons.dashboard_outlined),
  ssh('SSH', 'SSH', Icons.terminal),
  ftp('FTP', 'FTP', Icons.folder_open),
  database('DATABASE', 'Database', Icons.table_chart_outlined),
  email('EMAIL', 'Email', Icons.mail_outline),
  other('OTHER', 'Khác', Icons.key);

  const AccountKind(this.db, this.label, this.icon);
  final String db;
  final String label;
  final IconData icon;

  static AccountKind fromDb(String v) => values.firstWhere((e) => e.db == v, orElse: () => other);
}

class Account {
  Account({
    this.id,
    this.kind = AccountKind.other,
    required this.label,
    this.loginUrl,
    this.username,
    this.passwordEnc,
    this.port,
    this.vendorId,
    this.customerId,
    this.serviceId,
    this.note,
  });

  final String? id;
  final AccountKind kind;
  final String label;
  final String? loginUrl, username, passwordEnc, note;
  final int? port;
  final String? vendorId, customerId, serviceId;

  factory Account.fromJson(Map<String, dynamic> j) => Account(
        id: j['id'] as String,
        kind: AccountKind.fromDb(j['kind'] as String),
        label: j['label'] as String,
        loginUrl: j['login_url'] as String?,
        username: j['username'] as String?,
        passwordEnc: j['password_enc'] as String?,
        port: _int(j['port']),
        vendorId: j['provider_id'] as String?,
        customerId: j['customer_id'] as String?,
        serviceId: j['service_id'] as String?,
        note: j['note'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'kind': kind.db,
        'label': label,
        'login_url': loginUrl,
        'username': username,
        'password_enc': passwordEnc,
        'port': port,
        'provider_id': vendorId,
        'customer_id': customerId,
        'service_id': serviceId,
        'note': note,
      };
}

// ============================================================
// Lịch sử gia hạn
// ============================================================
class Renewal {
  Renewal({
    required this.id,
    required this.serviceId,
    required this.renewedAt,
    required this.oldExpiry,
    required this.newExpiry,
    required this.months,
    this.amount,
    this.customerPaid = false,
    this.providerPaid = false,
    this.note,
  });

  final String id;
  final String serviceId;
  final DateTime renewedAt, oldExpiry, newExpiry;
  final int months;
  final int? amount;
  final bool customerPaid, providerPaid;
  final String? note;

  factory Renewal.fromJson(Map<String, dynamic> j) => Renewal(
        id: j['id'] as String,
        serviceId: j['service_id'] as String,
        renewedAt: DateTime.parse(j['renewed_at'] as String).toLocal(),
        oldExpiry: parseDbDate(j['old_expiry'])!,
        newExpiry: parseDbDate(j['new_expiry'])!,
        months: _int(j['months'])!,
        amount: _int(j['amount']),
        customerPaid: j['customer_paid'] as bool? ?? false,
        providerPaid: j['provider_paid'] as bool? ?? false,
        note: j['note'] as String?,
      );
}

// ============================================================
// Sổ thu chi
// ============================================================
enum TxnKind {
  income('IN', 'Thu'),
  expense('OUT', 'Chi');

  const TxnKind(this.db, this.label);
  final String db;
  final String label;

  static TxnKind fromDb(String v) => v == 'OUT' ? expense : income;
}

enum TxnSource {
  manual('MANUAL'),
  renewal('RENEWAL'),
  backfill('BACKFILL');

  const TxnSource(this.db);
  final String db;

  static TxnSource fromDb(String? v) => values.firstWhere((e) => e.db == v, orElse: () => manual);
}

/// Một khoản thu / chi. [periodFrom]–[periodTo] là kỳ dịch vụ mà khoản tiền trả cho
/// (dùng để phân bổ doanh thu theo tháng).
class Txn {
  Txn({
    this.id,
    required this.kind,
    required this.amount,
    required this.paidAt,
    this.serviceId,
    this.customerId,
    this.periodFrom,
    this.periodTo,
    this.source = TxnSource.manual,
    this.note,
  });

  final String? id;
  final TxnKind kind;
  final int amount;
  final DateTime paidAt;
  final String? serviceId, customerId;
  final DateTime? periodFrom, periodTo;
  final TxnSource source;
  final String? note;

  bool get isIncome => kind == TxnKind.income;

  factory Txn.fromJson(Map<String, dynamic> j) => Txn(
        id: j['id'] as String,
        kind: TxnKind.fromDb(j['kind'] as String),
        amount: _int(j['amount']) ?? 0,
        paidAt: parseDbDate(j['paid_at'])!,
        serviceId: j['service_id'] as String?,
        customerId: j['customer_id'] as String?,
        periodFrom: parseDbDate(j['period_from']),
        periodTo: parseDbDate(j['period_to']),
        source: TxnSource.fromDb(j['source'] as String?),
        note: j['note'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'kind': kind.db,
        'amount': amount,
        'paid_at': toDbDate(paidAt),
        'service_id': serviceId,
        'customer_id': customerId,
        'period_from': toDbDate(periodFrom),
        'period_to': toDbDate(periodTo),
        'source': source.db,
        'note': note,
      };
}
