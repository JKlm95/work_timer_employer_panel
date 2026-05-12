import 'package:flutter/material.dart';

import '../utils/employee_presence_utils.dart';

/// Presence / timer badge for light and dark themes.
class WorkStatusBadge extends StatelessWidget {
  const WorkStatusBadge({super.key, required this.state, this.compact = false});

  final WorkPresenceState state;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final Color bg;
    final Color fg;
    String label;
    switch (state) {
      case WorkPresenceState.working:
        bg = isDark ? const Color(0xFF14532D) : const Color(0xFFDCFCE7);
        fg = isDark ? const Color(0xFFBBF7D0) : const Color(0xFF166534);
        label = 'Working';
        break;
      case WorkPresenceState.paused:
        bg = isDark ? const Color(0xFF713F12) : const Color(0xFFFEF9C3);
        fg = isDark ? const Color(0xFFFDE68A) : const Color(0xFF854D0E);
        label = 'Paused';
        break;
      case WorkPresenceState.online:
        bg = isDark ? const Color(0xFF1E3A5F) : const Color(0xFFDBEAFE);
        fg = isDark ? const Color(0xFFBFDBFE) : const Color(0xFF1D4ED8);
        label = 'Online';
        break;
      case WorkPresenceState.offline:
        bg = scheme.surfaceContainerHighest;
        fg = scheme.onSurfaceVariant;
        label = 'Offline';
        break;
      case WorkPresenceState.unknown:
        bg = scheme.surfaceContainerHighest;
        fg = scheme.onSurfaceVariant;
        label = '—';
        break;
    }

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
