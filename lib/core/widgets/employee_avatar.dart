import 'package:flutter/material.dart';

/// Deterministic avatar color from [seed] (e.g. employeeUid) for consistent rows.
class EmployeeAvatar extends StatelessWidget {
  const EmployeeAvatar({
    super.key,
    required this.seed,
    required this.initials,
    this.radius = 20,
    this.fontSize,
  });

  final String seed;
  final String initials;
  final double radius;
  final double? fontSize;

  static const _accents = <Color>[
    Color(0xFF4F46E5),
    Color(0xFF0D9488),
    Color(0xFFCA8A04),
    Color(0xFFBE185D),
    Color(0xFF2563EB),
    Color(0xFF7C3AED),
    Color(0xFF059669),
    Color(0xFFEA580C),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final idx = seed.isEmpty ? 0 : seed.hashCode.abs() % _accents.length;
    final accent = _accents[idx];
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = Color.alphaBlend(
      accent.withValues(alpha: isDark ? 0.42 : 0.26),
      scheme.surface,
    );
    final fg = scheme.onSurface;
    final fs = fontSize ?? (radius >= 26 ? 15.0 : 13.0);
    return CircleAvatar(
      radius: radius,
      backgroundColor: bg,
      child: Text(
        initials.trim().isEmpty ? '?' : initials.trim().toUpperCase(),
        style: TextStyle(
          fontSize: fs,
          fontWeight: FontWeight.w700,
          color: fg,
          letterSpacing: radius >= 26 ? 0.5 : 0,
        ),
      ),
    );
  }
}
