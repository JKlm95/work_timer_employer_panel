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
    IconData icon;
    switch (state) {
      case WorkPresenceState.working:
        bg = isDark ? const Color(0xFF14532D) : const Color(0xFFDCFCE7);
        fg = isDark ? const Color(0xFFBBF7D0) : const Color(0xFF166534);
        label = 'Working';
        icon = Icons.play_circle_filled_rounded;
        break;
      case WorkPresenceState.paused:
        bg = isDark ? const Color(0xFF713F12) : const Color(0xFFFEF9C3);
        fg = isDark ? const Color(0xFFFDE68A) : const Color(0xFF854D0E);
        label = 'Paused';
        icon = Icons.pause_circle_filled_rounded;
        break;
      case WorkPresenceState.online:
        bg = isDark ? const Color(0xFF1E3A5F) : const Color(0xFFDBEAFE);
        fg = isDark ? const Color(0xFFBFDBFE) : const Color(0xFF1D4ED8);
        label = 'Online';
        icon = Icons.wifi_rounded;
        break;
      case WorkPresenceState.offline:
        bg = scheme.surfaceContainerHighest;
        fg = scheme.onSurfaceVariant;
        label = 'Offline';
        icon = Icons.wifi_off_rounded;
        break;
      case WorkPresenceState.unknown:
        bg = scheme.surfaceContainerHighest;
        fg = scheme.onSurfaceVariant;
        label = 'Unknown';
        icon = Icons.help_outline_rounded;
        break;
    }

    final iconSize = compact ? 14.0 : 15.0;
    final padH = compact ? 9.0 : 11.0;
    final padV = compact ? 4.0 : 6.0;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.symmetric(horizontal: padH, vertical: padV),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: fg.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: iconSize, color: fg),
          SizedBox(width: compact ? 5 : 6),
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontSize: compact ? 11.5 : 12.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.15,
            ),
          ),
        ],
      ),
    );
  }
}
