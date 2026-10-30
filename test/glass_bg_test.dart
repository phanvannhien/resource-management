import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:service_manager/app/theme.dart';

void main() {
  testWidgets('nền mảng màu nằm sau trang của go_router', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, _) => const Scaffold(body: Text('x'))),
    ]);
    await tester.pumpWidget(MaterialApp.router(
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: ThemeMode.dark,
      routerConfig: router,
      builder: glassAppBuilder,
    ));
    await tester.pumpAndSettle();
    expect(find.byType(GlassBackground), findsOneWidget);
    expect(find.descendant(of: find.byType(GlassBackground), matching: find.text('x')), findsOneWidget);
  });
}
