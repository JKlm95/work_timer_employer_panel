import 'package:flutter/material.dart';

import '../theme/app_layout.dart';

/// Centered icon + title + subtitle for empty and soft-error marketing-style UI.
class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.detailSelectable = false,
    this.action,
    this.iconColor,
  });

  final IconData icon;
  final String title;
  final String? subtitle;

  /// When true, [subtitle] is rendered as [SelectableText] (e.g. error payloads).
  final bool detailSelectable;
  final Widget? action;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final onVar = scheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppLayout.pagePaddingCompact,
        vertical: AppLayout.cardPadding,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 44,
              color: iconColor ?? scheme.primary.withValues(alpha: 0.85),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                height: 1.25,
              ),
            ),
            if (subtitle != null && subtitle!.isNotEmpty) ...[
              const SizedBox(height: 8),
              detailSelectable
                  ? SelectableText(
                      subtitle!,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: onVar,
                        height: 1.35,
                      ),
                    )
                  : Text(
                      subtitle!,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: onVar,
                        height: 1.35,
                      ),
                    ),
            ],
            if (action != null) ...[const SizedBox(height: 22), action!],
          ],
        ),
      ),
    );
  }
}
