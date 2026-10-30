import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:service_manager/app/router.dart';
import 'package:service_manager/app/theme.dart';

void main() {
  testWidgets(
    'vuốt từ mép trái quay lại trang trước (iOS)',
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    (tester) async {
      // Kích thước điện thoại (màn rộng hơn 640 thì nội dung nằm giữa, mép trái không phải mép màn hình)
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const Scaffold(body: Center(child: Text('danh sách'))),
            routes: [
              GoRoute(
                path: 'detail',
                pageBuilder: (_, s) =>
                    pushedPage(s, const Scaffold(body: Center(child: Text('chi tiết')))),
              ),
            ],
          ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp.router(
          theme: buildTheme(Brightness.dark),
          routerConfig: router,
          builder: glassAppBuilder,
        ),
      );
      router.push('/detail');
      await tester.pumpAndSettle();
      expect(find.text('chi tiết'), findsOneWidget);

      // Vuốt từ mép trái sang phải
      final g = await tester.startGesture(const Offset(5, 300));
      for (var i = 0; i < 10; i++) {
        await g.moveBy(const Offset(50, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await g.up();
      await tester.pumpAndSettle();
      expect(find.text('chi tiết'), findsNothing);
      expect(find.text('danh sách'), findsOneWidget);
    },
  );
}
