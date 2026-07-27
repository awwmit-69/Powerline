/// PowerLine visual system (AZD Global palette): midnight-navy base, mineral-white
/// type, cobalt + signal-cyan accents, emerald only for genuine connected/success.
library;

import 'package:flutter/material.dart';

class PowerlineColors {
  // AZD Global palette — no crimson anywhere.
  static const navy = Color(0xFF0B1B2B);
  static const panel = Color(0xFF102A40);
  static const raised = Color(0xFF15202E);
  static const border = Color(0xFF243444);
  static const textPrimary = Color(0xFFF4F2EC); // mineral white
  static const textSecondary = Color(0xFFAEB9C7); // silver
  static const cobalt = Color(0xFF2C6BFF);
  static const cobaltDeep = Color(0xFF1E4FCC);
  static const cyan = Color(0xFF38E1D6); // signal cyan
  static const violet = Color(0xFF7C5CFF); // controlled: AI / voicemail
  // Operational state colors
  static const stateRinging = Color(0xFFE0A537); // amber — attention
  static const stateConnected = Color(
    0xFF12B981,
  ); // emerald — connected/success only
  static const stateHold = Color(0xFF2C6BFF); // cobalt
  static const stateFailed = Color(0xFFE5675A); // red — failed/hang-up only
  static const stateVoicemail = Color(0xFF7C5CFF); // violet
}

ThemeData powerlineTheme() {
  const scheme = ColorScheme.dark(
    surface: PowerlineColors.navy,
    primary: PowerlineColors.cobalt,
    secondary: PowerlineColors.cobaltDeep,
    onSurface: PowerlineColors.textPrimary,
    error: PowerlineColors.stateFailed,
  );
  return ThemeData(
    useMaterial3: true,
    fontFamily: 'Manrope',
    colorScheme: scheme,
    scaffoldBackgroundColor: PowerlineColors.navy,
    cardTheme: const CardThemeData(
      color: PowerlineColors.panel,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(10)),
        side: BorderSide(color: PowerlineColors.border),
      ),
      margin: EdgeInsets.zero,
    ),
    dividerTheme: const DividerThemeData(
      color: PowerlineColors.border,
      space: 1,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: PowerlineColors.navy,
      foregroundColor: PowerlineColors.textPrimary,
      elevation: 0,
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: PowerlineColors.textSecondary,
      textColor: PowerlineColors.textPrimary,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: PowerlineColors.raised,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: PowerlineColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: PowerlineColors.cobalt, width: 2),
      ),
    ),
    focusColor: PowerlineColors.cobalt.withValues(alpha: 0.25),
    tooltipTheme: const TooltipThemeData(
      waitDuration: Duration(milliseconds: 400),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: PowerlineColors.raised,
      contentTextStyle: TextStyle(color: PowerlineColors.textPrimary),
    ),
  );
}

/// Original Powerline wordmark rendered purely with typography.
class PowerlineWordmark extends StatelessWidget {
  final double size;
  const PowerlineWordmark({super.key, this.size = 20});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size * 0.55,
          height: size * 1.1,
          decoration: BoxDecoration(
            color: PowerlineColors.cobalt,
            borderRadius: BorderRadius.circular(2),
          ),
          child: CustomPaint(painter: _SignalBarsPainter()),
        ),
        SizedBox(width: size * 0.4),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: 'Power',
                style: TextStyle(
                  fontSize: size,
                  fontWeight: FontWeight.w700,
                  letterSpacing: size * 0.02,
                  color: PowerlineColors.textPrimary,
                ),
              ),
              TextSpan(
                text: 'Line',
                style: TextStyle(
                  fontSize: size,
                  fontWeight: FontWeight.w300,
                  letterSpacing: size * 0.02,
                  color: PowerlineColors.textSecondary,
                ),
              ),
              TextSpan(
                text: '\u2122',
                style: TextStyle(
                  fontSize: size * 0.5,
                  fontWeight: FontWeight.w500,
                  color: PowerlineColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SignalBarsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = const Color(0xFFF4F2EC);
    final lengths = [0.82, 0.58, 0.9];
    final ys = [0.26, 0.5, 0.74];
    final h = size.height * 0.1;
    final radius = Radius.circular(h / 2);
    for (var i = 0; i < 3; i++) {
      final w = size.width * lengths[i];
      final left = (size.width - w) / 2;
      final top = size.height * ys[i] - h / 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(left, top, w, h), radius),
        p,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Standard "demo mode" banner chip used wherever simulated activity shows.
class DemoBadge extends StatelessWidget {
  final String label;
  const DemoBadge({super.key, this.label = 'DEMO'});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: PowerlineColors.stateRinging.withValues(alpha: 0.15),
        border: Border.all(color: PowerlineColors.stateRinging),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: PowerlineColors.stateRinging,
          letterSpacing: 1,
        ),
      ),
    );
  }
}
