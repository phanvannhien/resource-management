import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app/router.dart';
import 'app/theme.dart';
import 'data/storage_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('vi');

  // Nơi lưu đã chọn (lần đầu cài = chưa chọn → màn chào mừng).
  var config = await StorageConfig.load();
  if (config.mode == StorageMode.cloud) {
    if (config.hasSupabase) {
      await AppGate.instance.initSupabase(config.supabaseUrl, config.supabaseKey);
    } else {
      config = config.copyWith(mode: () => null);
    }
  }
  AppGate.instance.setMode(config.mode);

  runApp(ProviderScope(
    overrides: [initialStorageConfigProvider.overrideWithValue(config)],
    child: const ServiceManagerApp(),
  ));
}

class ServiceManagerApp extends ConsumerStatefulWidget {
  const ServiceManagerApp({super.key});

  @override
  ConsumerState<ServiceManagerApp> createState() => _ServiceManagerAppState();
}

class _ServiceManagerAppState extends ConsumerState<ServiceManagerApp> {
  final _router = buildRouter();

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'AMV-WebManage',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: ref.watch(themeModeProvider),
      locale: const Locale('vi'),
      supportedLocales: const [Locale('vi'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      routerConfig: _router,
      builder: glassAppBuilder,
    );
  }
}
