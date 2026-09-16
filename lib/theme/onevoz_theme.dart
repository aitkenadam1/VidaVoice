/// OneVoz brand theme for the Calling & Safety build.
///
/// Visual identity follows the approved product mockup
/// (`onevoz-calling-and-safety-mockup`, the complete-app version):
/// deep navy, blue-to-teal gradients, rounded forms, waveform/signal-bar
/// motif — bright and playful on the child side, calm and clean on the
/// caregiver side.
///
/// Two variants:
/// * [OneVozTheme.childTheme] — brighter and more playful (child side).
/// * [OneVozTheme.caregiverTheme] — calm and clean (caregiver side).
///
/// Both are unmistakably OneVoz: navy + blue-to-teal gradient + rounded shapes.
/// Child-critical touch targets are >= 64px at every screen size — never
/// assume a fixed screen size.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Brand colors. Exact values are sampled from the approved OneVoz product
/// mockup (`onevoz-calling-and-safety-mockup`): deep navy #0D2B4F,
/// blue-to-teal gradients, rounded forms, waveform/signal-bar motif.
/// All consts — no runtime cost.
abstract final class OneVozColors {
  OneVozColors._();

  /// Deep navy — mockup `--navy` (#0D2B4F).
  static const Color navy = Color(0xFF0D2B4F);

  /// Darker navy for gradient depth / text-on-light contrast.
  static const Color navyDark = Color(0xFF071E36);

  /// Primary blue — mockup `--blue` (#0877CA).
  static const Color blue = Color(0xFF0877CA);

  /// Bright sky blue — mockup `--blue-2` (#24A7DD). Kept the `azure` name
  /// for compatibility with existing call sites.
  static const Color azure = Color(0xFF24A7DD);

  /// Brand teal — mockup `--teal` (#32D6C0).
  static const Color teal = Color(0xFF32D6C0);

  /// Light aqua accent for gradients and playful child-side details.
  static const Color aqua = Color(0xFF49DDC8);

  /// Deep teal for text-on-light accents — mockup `--teal-deep` (#0A766F).
  static const Color tealDeep = Color(0xFF0A766F);

  /// Warm yellow accent — mockup `--yellow` (#FFD76B), child side.
  static const Color yellow = Color(0xFFFFD76B);

  /// Warm orange accent — mockup `--orange` (#F6A23A), child side.
  static const Color orange = Color(0xFFF6A23A);

  /// Purple accent — mockup `--purple` (#7D62C7), child side.
  static const Color purple = Color(0xFF7D62C7);

  /// Primary brand gradient: blue -> teal, left to right.
  /// Matches the mockup's `linear-gradient(90deg, var(--blue), var(--teal))`.
  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [blue, teal],
  );

  /// Navy hero gradient for call/onboarding headers.
  /// Matches the mockup's `.call-hero`: 155deg navy -> #075B91 -> #168F9B.
  static const LinearGradient heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0D2B4F), Color(0xFF075B91), Color(0xFF168F9B)],
    stops: [0.0, 0.68, 1.0],
  );

  /// Red gradient for the emergency header.
  /// Matches the mockup's `.emergency-head`: 145deg #821A30 -> #D33A4A.
  static const LinearGradient emergencyGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF821A30), Color(0xFFD33A4A)],
  );

  // ---- Semantic ----
  /// Emergency red — mockup `--danger` (#D33A4A).
  static const Color emergency = Color(0xFFD33A4A);

  /// Dark emergency red for gradient depth — mockup #821A30.
  static const Color emergencyDark = Color(0xFF821A30);

  /// Success green — mockup `--success` (#0A7C63).
  static const Color success = Color(0xFF0A7C63);

  /// Warning amber — mockup `--orange` (#F6A23A).
  static const Color warning = Color(0xFFF6A23A);

  static const Color info = azure;

  // ---- Surfaces: child (brighter, playful) ----
  static const Color childBackground = Color(0xFFEAF9FB);
  static const Color childSurface = Color(0xFFFFFFFF);
  static const Color childCard = Color(0xFFFFFFFF);

  // ---- Surfaces: caregiver (calm, clean) ----
  static const Color caregiverBackground = Color(0xFFF4F7FA);
  static const Color caregiverSurface = Color(0xFFFFFFFF);
  static const Color caregiverCard = Color(0xFFFFFFFF);

  // ---- Text ----
  static const Color ink = navy;
  static const Color inkSoft = Color(0xFF3D5A7A);
  static const Color onNavy = Color(0xFFFFFFFF);
}

/// The two OneVoz theme variants. Both are Material 3, rounded everywhere
/// (16-24dp), and respect the user's text-scaling settings — no fixed
/// textScaleFactor overrides anywhere.
abstract final class OneVozTheme {
  OneVozTheme._();

  /// Brighter, more playful theme for the child side.
  static ThemeData childTheme() => _build(
    seed: OneVozColors.aqua,
    primary: OneVozColors.azure,
    scaffoldBackground: OneVozColors.childBackground,
    cardColor: OneVozColors.childCard,
    headlineBoost: 1.12,
    playful: true,
  );

  /// Calm, clean theme for the caregiver side (also the app default).
  static ThemeData caregiverTheme() => _build(
    seed: OneVozColors.navy,
    primary: OneVozColors.navy,
    scaffoldBackground: OneVozColors.caregiverBackground,
    cardColor: OneVozColors.caregiverCard,
    headlineBoost: 1.0,
    playful: false,
  );

  static ThemeData _build({
    required Color seed,
    required Color primary,
    required Color scaffoldBackground,
    required Color cardColor,
    required double headlineBoost,
    required bool playful,
  }) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      primary: primary,
      brightness: Brightness.light,
    );
    const radius = BorderRadius.all(Radius.circular(20));

    TextTheme boosted(TextTheme base) => base.copyWith(
      displayLarge: base.displayLarge?.copyWith(
        fontSize: (base.displayLarge?.fontSize ?? 57) * headlineBoost,
      ),
      displayMedium: base.displayMedium?.copyWith(
        fontSize: (base.displayMedium?.fontSize ?? 45) * headlineBoost,
      ),
      headlineLarge: base.headlineLarge?.copyWith(
        fontSize: (base.headlineLarge?.fontSize ?? 32) * headlineBoost,
      ),
      headlineMedium: base.headlineMedium?.copyWith(
        fontSize: (base.headlineMedium?.fontSize ?? 28) * headlineBoost,
      ),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scaffoldBackground,
      cardColor: cardColor,
      textTheme: boosted(ThemeData.light().textTheme),
      appBarTheme: AppBarTheme(
        backgroundColor: OneVozColors.navy,
        foregroundColor: OneVozColors.onNavy,
        elevation: 0,
        centerTitle: false,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
        ),
      ),
      cardTheme: const CardThemeData(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: radius),
        margin: EdgeInsets.all(8),
      ),
      dialogTheme: const DialogThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(24)),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        labelStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: playful ? 16 : 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
        contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(88, 56),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(88, 56),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(88, 56),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        shape: StadiumBorder(),
      ),
    );
  }
}

/// Decorative waveform / signal-bar motif from the logo: rounded bars in a
/// blue-to-teal gradient. Deterministic (no randomness), painted with a
/// single gradient shader — cheap enough for headers and backgrounds.
class WaveformMotif extends StatelessWidget {
  const WaveformMotif({
    super.key,
    this.barCount = 9,
    this.height = 48,
    this.barWidth = 8,
    this.gap = 6,
    this.gradient,
    this.color,
  }) : assert(barCount > 0);

  /// Number of bars. Defaults to 9 (echoes the logo's signal bars).
  final int barCount;

  /// Total height of the motif.
  final double height;

  /// Width of each rounded bar.
  final double barWidth;

  /// Gap between bars.
  final double gap;

  /// Gradient painted across the bars. Defaults to the brand gradient.
  final Gradient? gradient;

  /// Solid color override (takes precedence over [gradient]).
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        size: Size(barWidth * barCount + gap * (barCount - 1), height),
        painter: _WaveformPainter(
          barCount: barCount,
          barWidth: barWidth,
          gap: gap,
          gradient: gradient ?? OneVozColors.brandGradient,
          color: color,
        ),
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  _WaveformPainter({
    required this.barCount,
    required this.barWidth,
    required this.gap,
    required this.gradient,
    this.color,
  });

  final int barCount;
  final double barWidth;
  final double gap;
  final Gradient gradient;
  final Color? color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    if (color != null) {
      paint.color = color!;
    } else {
      paint.shader = gradient.createShader(
        Rect.fromLTWH(0, 0, size.width, size.height),
      );
    }
    final radius = Radius.circular(barWidth / 2);
    for (var i = 0; i < barCount; i++) {
      // Smooth raised-cosine envelope: tallest in the middle, like the
      // logo's signal bars. Deterministic — same motif every paint.
      final t = barCount == 1 ? 0.5 : i / (barCount - 1);
      final envelope = 0.25 + 0.75 * math.pow(math.sin(math.pi * t), 0.8);
      final barHeight = size.height * envelope;
      final x = i * (barWidth + gap);
      final y = (size.height - barHeight) / 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, barWidth, barHeight),
          radius,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) =>
      oldDelegate.barCount != barCount ||
      oldDelegate.barWidth != barWidth ||
      oldDelegate.gap != gap ||
      oldDelegate.gradient != gradient ||
      oldDelegate.color != color;
}

/// Primary OneVoz action button: blue-to-teal gradient, fully rounded,
/// minimum 64px tall. Optional icon + label. Honors large text sizes by
/// growing taller rather than clipping.
class OneVozGradientButton extends StatelessWidget {
  const OneVozGradientButton({
    super.key,
    required this.onPressed,
    required this.label,
    this.icon,
    this.gradient,
    this.minHeight = 64,
    this.textStyle,
    this.padding,
  });

  final VoidCallback? onPressed;
  final String label;
  final IconData? icon;

  /// Gradient override — defaults to [OneVozColors.brandGradient].
  final Gradient? gradient;

  /// Minimum tap height; child-critical actions must stay >= 64.
  final double minHeight;
  final TextStyle? textStyle;
  final EdgeInsetsGeometry? padding;

  bool get _enabled => onPressed != null;

  @override
  Widget build(BuildContext context) {
    final resolvedGradient = gradient ?? OneVozColors.brandGradient;
    return Opacity(
      opacity: _enabled ? 1.0 : 0.5,
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            gradient: resolvedGradient,
            borderRadius: BorderRadius.circular(1000),
            boxShadow: _enabled
                ? [
                    BoxShadow(
                      color: OneVozColors.azure.withValues(alpha: 0.35),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : null,
          ),
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(1000),
            child: Container(
              constraints: BoxConstraints(minHeight: minHeight),
              padding:
                  padding ??
                  const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              alignment: Alignment.center,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Icon(icon, color: Colors.white, size: 28),
                    const SizedBox(width: 12),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style:
                          textStyle ??
                          const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
