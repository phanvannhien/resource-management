import 'package:flutter/cupertino.dart';
import 'package:go_router/go_router.dart';

import '../features/accounts/account_form_screen.dart';
import '../features/accounts/accounts_screen.dart';
import '../data/storage_config.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/welcome_screen.dart';
import '../features/customers/customer_detail_screen.dart';
import '../features/customers/customer_form_screen.dart';
import '../features/customers/customers_screen.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/reports/backfill_screen.dart';
import '../features/reports/reports_screen.dart';
import '../features/services/service_detail_screen.dart';
import '../features/services/service_form_screen.dart';
import '../features/services/services_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/settings/storage_screen.dart';
import '../features/settings/vendors_screen.dart';
import '../models/models.dart';
import 'theme.dart';
import 'home_shell.dart';

GoRouter buildRouter() {
  final gate = AppGate.instance;
  return GoRouter(
    initialLocation: '/dashboard',
    refreshListenable: gate,
    redirect: (context, state) {
      final loc = state.matchedLocation;
      final atEntry = loc == '/welcome' || loc == '/login';
      // 1. Chưa chọn nơi lưu → màn chào mừng
      if (gate.mode == null) return loc == '/welcome' ? null : '/welcome';
      // 2. Dùng Supabase mà chưa đăng nhập → đăng nhập (vẫn cho quay lại màn chào mừng)
      if (gate.mode == StorageMode.cloud && !gate.signedIn) return atEntry ? null : '/login';
      // 3. Đã sẵn sàng → vào app
      if (atEntry) return '/dashboard';
      return null;
    },
    routes: [
      GoRoute(path: '/welcome', builder: (_, _) => const WelcomeScreen()),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => HomeShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [GoRoute(path: '/dashboard', builder: (_, _) => const DashboardScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/services', builder: (_, _) => const ServicesScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/customers', builder: (_, _) => const CustomersScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/accounts', builder: (_, _) => const AccountsScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/reports', builder: (_, _) => const ReportsScreen())],
          ),
        ],
      ),

      // Dịch vụ
      GoRoute(
        path: '/service/new',
        pageBuilder: (_, s) {
          final q = s.uri.queryParameters;
          return pushedPage(
            s,
            ServiceFormScreen(
              initialType: q['type'] == null ? null : ServiceType.fromDb(q['type']!),
              initialCustomerId: q['customerId'],
              initialParentVpsId: q['parentVpsId'],
            ),
          );
        },
      ),
      GoRoute(
        path: '/service/:id',
        pageBuilder: (_, s) => pushedPage(s, ServiceDetailScreen(id: s.pathParameters['id']!)),
        routes: [
          GoRoute(
            path: 'edit',
            pageBuilder: (_, s) => pushedPage(s, ServiceFormScreen(id: s.pathParameters['id'])),
          ),
        ],
      ),

      // Khách hàng
      GoRoute(
        path: '/customer/new',
        pageBuilder: (_, s) =>
            pushedPage(s, CustomerFormScreen(pick: s.uri.queryParameters['pick'] == '1')),
      ),
      GoRoute(
        path: '/customer/:id',
        pageBuilder: (_, s) => pushedPage(s, CustomerDetailScreen(id: s.pathParameters['id']!)),
        routes: [
          GoRoute(
            path: 'edit',
            pageBuilder: (_, s) => pushedPage(s, CustomerFormScreen(id: s.pathParameters['id'])),
          ),
        ],
      ),

      // Tài khoản
      GoRoute(
        path: '/account/new',
        pageBuilder: (_, s) => pushedPage(
          s,
          AccountFormScreen(
            serviceId: s.uri.queryParameters['serviceId'],
            customerId: s.uri.queryParameters['customerId'],
          ),
        ),
      ),
      GoRoute(
        path: '/account/:id/edit',
        pageBuilder: (_, s) => pushedPage(s, AccountFormScreen(id: s.pathParameters['id'])),
      ),

      // Kế toán
      GoRoute(
        path: '/accounting/backfill',
        pageBuilder: (_, s) =>
            pushedPage(s, BackfillScreen(serviceId: s.uri.queryParameters['serviceId'])),
      ),

      // Cài đặt
      GoRoute(
        path: '/settings',
        pageBuilder: (_, s) => pushedPage(s, const SettingsScreen()),
        routes: [
          GoRoute(path: 'vendors', pageBuilder: (_, s) => pushedPage(s, const VendorsScreen())),
          GoRoute(path: 'storage', pageBuilder: (_, s) => pushedPage(s, const StorageScreen())),
        ],
      ),
    ],
  );
}

/// Trang đẩy lên trên (chi tiết, form, cài đặt): chuyển trang kiểu iOS, vuốt từ mép trái để quay lại.
/// Nền mảng màu đi kèm từng trang để lúc trượt không thấy trang bên dưới xuyên qua.
Page<void> pushedPage(GoRouterState state, Widget child) => CupertinoPage<void>(
  key: state.pageKey,
  name: state.name,
  child: GlassBackground(child: child),
);
