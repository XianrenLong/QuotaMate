import 'package:flutter/material.dart';

/// Stable daytime design tokens, resolved through the active theme at render time.
abstract final class C {
  static const bg = Color(0xFFEFEEF4),
      side = Color(0xFFE5E3EB),
      card = Color(0xFFFBFAFD),
      blue = Color(0xFF3483FF),
      ink = Color(0xFF171A29),
      muted = Color(0xFF7C8099),
      line = Color(0xFFE9E8F0),
      track = Color(0xFFE5E4EE),
      green = Color(0xFF35B54A),
      amber = Color(0xFFDC962F);
}

class AppPalette extends ThemeExtension<AppPalette> {
  final Map<int, Color> colors;
  const AppPalette(this.colors);
  static const light = AppPalette({});
  static const dark = AppPalette({
    0xFFEFEEF4: Color(0xFF161821),
    0xFFE5E3EB: Color(0xFF1D1F2B),
    0xFFFBFAFD: Color(0xFF252836),
    0xFF171A29: Color(0xFFF0F1F8),
    0xFF7C8099: Color(0xFFABB0C4),
    0xFFE9E8F0: Color(0xFF3A3E50),
    0xFFE5E4EE: Color(0xFF383D4F),
    0xFF3483FF: Color(0xFF6BA7FF),
    0xFF35B54A: Color(0xFF6ACF83),
    0xFFDC962F: Color(0xFFF0B45E),
    0xFFEEEDF4: Color(0xFF1B1E29),
    0xFFD8D6E1: Color(0xFF34394D),
    0xFFDAD8E2: Color(0xFF2B2F3F),
    0xFFF0EFF5: Color(0xFF303445),
    0xFFF0F5FF: Color(0xFF293A55),
    0xFFB7CEFF: Color(0xFF46648E),
    0xFFE3E6F0: Color(0xFF353B50),
    0xFFEBEAF2: Color(0xFF35394B),
    0xFFECF0FF: Color(0xFF33415D),
    0xFFE7EEFF: Color(0xFF2D405F),
    0xFFE1EBFF: Color(0xFF293F5E),
    0xFF226CE4: Color(0xFF8BBAFF),
    0xFFD8F4DA: Color(0xFF263F31),
    0xFF24833A: Color(0xFF91DFA4),
    0xFFD7F2D2: Color(0xFF263F31),
    0xFF269B37: Color(0xFF91DFA4),
    0xFFFFEACD: Color(0xFF473820),
    0xFFFFF4DF: Color(0xFF3E3325),
    0xFFE8E8ED: Color(0xFF383D4E),
    0xFF656978: Color(0xFFC0C5D6),
    0xFFFFEDBD: Color(0xFF493B24),
    0xFF91600A: Color(0xFFF4CF80),
    0xFFE7C366: Color(0xFF947641),
  });

  Color resolve(Color value) => colors[value.toARGB32()] ?? value;
  @override
  AppPalette copyWith({Map<int, Color>? colors}) =>
      AppPalette(colors ?? this.colors);
  @override
  AppPalette lerp(covariant AppPalette? other, double t) {
    if (other == null) return this;
    return AppPalette({
      for (final key in {...colors.keys, ...other.colors.keys})
        key: Color.lerp(
          colors[key] ?? Color(key),
          other.colors[key] ?? Color(key),
          t,
        )!,
    });
  }
}

Color themeColor(BuildContext context, Color color) =>
    Theme.of(context).extension<AppPalette>()?.resolve(color) ?? color;

Color primaryFill(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const Color(0xFF2F70DC)
    : C.blue;

ThemeData createAppTheme(Brightness brightness) {
  final palette = brightness == Brightness.dark
      ? AppPalette.dark
      : AppPalette.light;
  final dark = brightness == Brightness.dark;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: C.blue,
        brightness: brightness,
        surface: palette.resolve(C.card),
      ).copyWith(
        primary: palette.resolve(C.blue),
        onPrimary: dark ? const Color(0xFF10274D) : Colors.white,
        onSurface: palette.resolve(C.ink),
        outline: palette.resolve(C.line),
      );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    extensions: [palette],
    fontFamily: 'PingFang SC',
    fontFamilyFallback: const [
      '.AppleSystemUIFont',
      'Microsoft YaHei',
      'Arial',
    ],
    colorScheme: scheme,
    scaffoldBackgroundColor: palette.resolve(C.bg),
    tooltipTheme: const TooltipThemeData(
      waitDuration: Duration(milliseconds: 450),
    ),
    textTheme: TextTheme(
      bodyMedium: TextStyle(fontSize: 14, color: palette.resolve(C.ink)),
    ),
    dividerColor: palette.resolve(C.line),
    dividerTheme: DividerThemeData(
      color: palette.resolve(C.line),
      thickness: 1,
    ),
    dialogTheme: DialogThemeData(backgroundColor: palette.resolve(C.card)),
    popupMenuTheme: PopupMenuThemeData(color: palette.resolve(C.card)),
  );
}
