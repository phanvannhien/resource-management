import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Màu thương hiệu lấy từ icon AMV-WebManage.
class Brand {
  static const blue = Color(0xFF0458F6); // xanh chủ đạo
  static const navy = Color(0xFF0223B6); // xanh đậm
  static const sky = Color(0xFF09A7FD); // xanh trời (góc sáng của icon)
  static const mint = Color(0xFF15E8A3); // xanh ngọc của mũi tên
  static const accent = Color(0xFF4C82FF); // xanh sáng, nổi trên nền tối

  static const gradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [sky, blue, navy],
    stops: [0, 0.45, 1],
  );

  /// Gradient cho ô icon ở tiêu đề trang.
  static const tileGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [sky, blue],
  );
}

// ---------------------------------------------------------------------------
// Bảng màu kính (liquid glass): bề mặt trong suốt nằm trên nền có mảng màu loang
// ---------------------------------------------------------------------------
const _darkBase = Color(0xFF070B1E); // nền gốc rất tối
const _darkSheet = Color(0xFF141B3D); // sheet / dialog: đặc để chữ dễ đọc
const _darkMenu = Color(0xFF1A2148);
const _darkGlass = Color(0x14FFFFFF); // thẻ kính
const _darkGlassHigh = Color(0x1FFFFFFF); // ô bên trong thẻ / nút
const _darkBorder = Color(0x24FFFFFF); // viền sáng mảnh
const _darkMuted = Color(0xFF9AA4CC);

const _lightBase = Color(0xFFEFF3FF);
const _lightSheet = Color(0xFFFFFFFF);
const _lightGlass = Color(0xA6FFFFFF);
const _lightGlassHigh = Color(0xCCFFFFFF);
const _lightBorder = Color(0xE6FFFFFF);
const _lightMuted = Color(0xFF5F6787);

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final base = ColorScheme.fromSeed(
    seedColor: Brand.blue,
    brightness: brightness,
    dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
  );
  final primary = dark ? Brand.accent : Brand.blue;
  final glass = dark ? _darkGlass : _lightGlass;
  final glassHigh = dark ? _darkGlassHigh : _lightGlassHigh;
  final border = dark ? _darkBorder : _lightBorder;
  final sheet = dark ? _darkSheet : _lightSheet;
  final scheme = base.copyWith(
    primary: primary,
    onPrimary: Colors.white,
    primaryContainer: dark ? const Color(0xFF1E2F66) : const Color(0xFFDDE7FF),
    onPrimaryContainer: dark ? const Color(0xFFCADAFF) : Brand.navy,
    secondary: Brand.mint,
    secondaryContainer: dark ? const Color(0xFF1E2F66) : const Color(0xFFDDE7FF),
    onSecondaryContainer: dark ? const Color(0xFFCADAFF) : Brand.navy,
    tertiary: Brand.mint,
    // surface giữ màu đặc: dùng cho menu dropdown, canvas
    surface: dark ? const Color(0xFF111735) : Colors.white,
    onSurface: dark ? Colors.white : const Color(0xFF131A3A),
    onSurfaceVariant: dark ? _darkMuted : _lightMuted,
    // các lớp "container" là kính trong suốt
    surfaceContainerLowest: glass,
    surfaceContainerLow: glass,
    surfaceContainer: glass,
    surfaceContainerHigh: glassHigh,
    surfaceContainerHighest: glassHigh,
    outline: border,
    outlineVariant: border,
  );
  final radius = BorderRadius.circular(16);

  return ThemeData(
    colorScheme: scheme,
    // Scaffold trong suốt: nền mảng màu nằm phía sau cả app (xem glassAppBuilder)
    scaffoldBackgroundColor: Colors.transparent,
    canvasColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      elevation: 0,
      titleTextStyle: TextStyle(
          color: scheme.onSurface, fontSize: 22, fontWeight: FontWeight.w700),
    ),
    cardTheme: CardThemeData(
      color: glass,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: border),
      ),
    ),
    dividerTheme: DividerThemeData(color: border, space: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: glass,
      border: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: border)),
      enabledBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: border)),
      focusedBorder:
          OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: primary, width: 1.6)),
    ),
    searchBarTheme: SearchBarThemeData(
      backgroundColor: WidgetStatePropertyAll(glass),
      elevation: const WidgetStatePropertyAll(0),
      shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: radius, side: BorderSide(color: border))),
      hintStyle: WidgetStatePropertyAll(TextStyle(color: scheme.onSurfaceVariant)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: radius),
        minimumSize: const Size(64, 46),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        backgroundColor: glass,
        shape: RoundedRectangleBorder(borderRadius: radius),
        side: BorderSide(color: border),
        minimumSize: const Size(64, 46),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: primary,
      foregroundColor: Colors.white,
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: sheet,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      modalBarrierColor: Colors.black.withValues(alpha: dark ? 0.55 : 0.3),
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        side: BorderSide(color: border),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: sheet,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(26),
        side: BorderSide(color: border),
      ),
    ),
    datePickerTheme: DatePickerThemeData(
      backgroundColor: sheet,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: dark ? _darkMenu : _lightSheet,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: border),
      ),
    ),
    listTileTheme: ListTileThemeData(iconColor: scheme.onSurfaceVariant),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}

/// Đặt nền mảng màu phía sau toàn bộ app (dùng cho `MaterialApp.builder`).
/// Các Scaffold đều trong suốt nên nền này hiện xuyên qua mọi màn hình.
/// Trên màn hình rộng (Mac, tablet) nội dung giữ tối đa 640px và nằm giữa.
Widget glassAppBuilder(BuildContext context, Widget? child) => GlassBackground(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: child ?? const SizedBox.shrink(),
        ),
      ),
    );

/// Nền có các mảng màu loang (xanh dương, xanh trời, tím, xanh ngọc) để lớp kính có thứ "nhìn xuyên".
class GlassBackground extends StatelessWidget {
  const GlassBackground({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final size = MediaQuery.sizeOf(context);
    final w = size.width;

    Widget blob(double left, double top, double d, Color c, double a) => Positioned(
          left: left - d / 2,
          top: top - d / 2,
          width: d,
          height: d,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [c.withValues(alpha: a), c.withValues(alpha: 0)],
              ),
            ),
          ),
        );

    final k = dark ? 1.0 : 0.55; // nền sáng dùng màu nhạt hơn
    return ColoredBox(
      color: dark ? _darkBase : _lightBase,
      child: Stack(
        children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: Stack(
                children: [
                  blob(w * 0.05, size.height * 0.04, w * 1.25, Brand.blue, 0.55 * k),
                  blob(w * 1.0, size.height * 0.20, w * 1.0, Brand.sky, 0.32 * k),
                  blob(w * 0.0, size.height * 0.58, w * 1.1, const Color(0xFF7C3AED), 0.30 * k),
                  blob(w * 0.95, size.height * 0.85, w * 1.05, Brand.mint, 0.20 * k),
                ],
              ),
            ),
          ),
          Positioned.fill(child: child),
        ],
      ),
    );
  }
}

/// Chế độ sáng / tối, lưu trên máy. Mặc định giao diện tối.
class ThemeModeController extends Notifier<ThemeMode> {
  static const _key = 'theme_mode';

  @override
  ThemeMode build() {
    SharedPreferences.getInstance().then((p) {
      final v = p.getString(_key);
      if (v == 'light') state = ThemeMode.light;
    });
    return ThemeMode.dark;
  }

  Future<void> setDark(bool dark) async {
    state = dark ? ThemeMode.dark : ThemeMode.light;
    (await SharedPreferences.getInstance()).setString(_key, dark ? 'dark' : 'light');
  }
}

final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(ThemeModeController.new);
