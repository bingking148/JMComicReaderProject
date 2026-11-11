import 'package:flutter/material.dart';

/// Night-press palette: warm ink, paper, cinnabar. Not a generic purple theme.
class InkColors {
  static const bg = Color(0xFF110F0D);
  static const raised = Color(0xFF1B1814);
  static const line = Color(0xFF2E2923);
  static const paper = Color(0xFFE7DCC8);
  static const dim = Color(0xFFB7AA96);
  static const mute = Color(0xFF8A7E6E);
  static const cinnabar = Color(0xFFD24A32);
  static const cinnabarDeep = Color(0xFF8E2C1C);
  static const brass = Color(0xFFC6A15B);
  static const read = Color(0xFF0C0B0A);
}

ThemeData buildTheme() {
  const paper = InkColors.paper;
  const mute = InkColors.mute;
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: InkColors.bg,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    fontFamily: 'Literata',
    fontFamilyFallback: const [
      'Source Han Sans SC',
      'Noto Sans CJK SC',
      'Noto Sans SC',
      'PingFang SC',
      'Hiragino Sans GB',
      'Microsoft YaHei',
      'DroidSansFallback',
      'sans-serif',
    ],
  );
  return base.copyWith(
    colorScheme: const ColorScheme.dark(
      surface: InkColors.bg,
      primary: InkColors.cinnabar,
      onPrimary: InkColors.paper,
      secondary: InkColors.brass,
      onSurface: paper,
    ),
    textTheme: base.textTheme.apply(bodyColor: paper, displayColor: paper),
    dividerColor: InkColors.line,
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: paper,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: InkColors.cinnabar,
        foregroundColor: const Color(0xFFFFF6EC),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0.2),
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      isDense: true,
      hintStyle: TextStyle(color: mute),
      labelStyle: TextStyle(color: mute),
      border: UnderlineInputBorder(borderSide: BorderSide(color: InkColors.line)),
      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: InkColors.line)),
      focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: InkColors.cinnabar, width: 1.4)),
    ),
    sliderTheme: const SliderThemeData(
      trackHeight: 2,
      activeTrackColor: InkColors.cinnabar,
      inactiveTrackColor: InkColors.line,
      thumbColor: paper,
      overlayColor: Color(0x33D24A32),
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: InkColors.raised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(2)),
        side: BorderSide(color: InkColors.line),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: InkColors.raised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(2)),
      ),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: FadeUpwardsPageTransitionsBuilder(),
        TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
        TargetPlatform.macOS: FadeUpwardsPageTransitionsBuilder(),
        TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
      },
    ),
  );
}
