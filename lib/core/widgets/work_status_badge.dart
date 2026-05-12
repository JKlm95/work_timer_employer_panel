import 'package:flutter/material.dart';

/// Green-style “Working” vs neutral “Offline”, tuned for light and dark themes.
class WorkStatusBadge extends StatelessWidget {
  const WorkStatusBadge({super.key, required this.isWorking, this.compact = false});

  final bool isWorking;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final Color bg;
    final Color fg;
    if (isWorking) {
      bg = isDark ? const Color(0xFF14532D) : const Color(0xFFDCFCE7);
      fg = isDark ? const Color(0xFFBBF7D0) : const Color(0xFF166534);
    } else {
      bg = scheme.surfaceContainerHighest;
      fg = scheme.onSurfaceVariant;
    }

    final label = isWorking ? 'Working' : 'Offline';
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 10, vertical: compact ? 3 : 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontSize: compact ? 11 : 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
