import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Courvite palette: white canvas, black ink, electric yellow energy.
abstract final class AppColors {
  /// Electric yellow. Used as a fill (with black on top), never as text on white.
  static const volt = Color(0xFFFFE500);
  static const voltDeep = Color(0xFFFFC800);
  static const ink = Color(0xFF111111);
  static const inkSoft = Color(0xFF2A2A2A);
  static const muted = Color(0xFF7A7A76);
  static const canvas = Color(0xFFFFFFFF);
  static const card = Color(0xFFF5F5F1);
  static const line = Color(0xFFE8E8E3);
  static const danger = Color(0xFFE5484D);
  static const go = Color(0xFF22C55E);
}

/// Condensed italic numbers: the "scoreboard" look used for metrics.
TextStyle numberStyle(double size, {Color color = AppColors.ink}) => TextStyle(
  fontFamily: 'BarlowCondensed',
  fontStyle: FontStyle.italic,
  fontWeight: FontWeight.w800,
  fontSize: size,
  height: 1,
  color: color,
  letterSpacing: -0.5,
  fontFeatures: const [FontFeature.tabularFigures()],
);

/// Small uppercase label, e.g. "AVG PACE".
TextStyle labelStyle({Color color = AppColors.muted, double size = 12}) =>
    TextStyle(
      fontFamily: 'Barlow',
      fontWeight: FontWeight.w600,
      fontSize: size,
      letterSpacing: 1.2,
      color: color,
    );

/// Big section/screen titles.
TextStyle headlineStyle(double size, {Color color = AppColors.ink}) =>
    TextStyle(
      fontFamily: 'BarlowCondensed',
      fontStyle: FontStyle.italic,
      fontWeight: FontWeight.w800,
      fontSize: size,
      height: 1.05,
      color: color,
      letterSpacing: 0.2,
    );

ThemeData buildTheme() {
  final scheme =
      ColorScheme.fromSeed(
        seedColor: AppColors.volt,
        brightness: Brightness.light,
      ).copyWith(
        primary: AppColors.ink,
        onPrimary: AppColors.volt,
        primaryContainer: AppColors.volt,
        onPrimaryContainer: AppColors.ink,
        secondary: AppColors.volt,
        onSecondary: AppColors.ink,
        surface: AppColors.canvas,
        onSurface: AppColors.ink,
        onSurfaceVariant: AppColors.muted,
        surfaceContainerLowest: AppColors.canvas,
        surfaceContainerLow: AppColors.card,
        surfaceContainer: AppColors.card,
        surfaceContainerHigh: AppColors.card,
        surfaceContainerHighest: AppColors.line,
        outline: AppColors.muted,
        outlineVariant: AppColors.line,
        error: AppColors.danger,
      );

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: 'Barlow',
    scaffoldBackgroundColor: AppColors.canvas,
    splashFactory: InkSparkle.splashFactory,
  );

  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: AppColors.ink,
      displayColor: AppColors.ink,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.canvas,
      surfaceTintColor: Colors.transparent,
      foregroundColor: AppColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: headlineStyle(26),
      systemOverlayStyle: SystemUiOverlayStyle.dark,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.canvas,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      titleTextStyle: headlineStyle(26),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.volt,
        foregroundColor: AppColors.ink,
        textStyle: const TextStyle(
          fontFamily: 'Barlow',
          fontWeight: FontWeight.w700,
          fontSize: 16,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        shape: const StadiumBorder(),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.ink,
        textStyle: const TextStyle(
          fontFamily: 'Barlow',
          fontWeight: FontWeight.w600,
          fontSize: 16,
        ),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.ink,
      contentTextStyle: const TextStyle(
        fontFamily: 'Barlow',
        color: Colors.white,
        fontSize: 15,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.line, space: 1),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.ink,
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
      },
    ),
  );
}

/// Rounded light-grey container used for cards throughout the app.
class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.color = AppColors.card,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// Small uppercase section header with a yellow tick.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 12),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 18,
            decoration: BoxDecoration(
              color: AppColors.volt,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text.toUpperCase(),
              style: labelStyle(color: AppColors.ink, size: 13),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
