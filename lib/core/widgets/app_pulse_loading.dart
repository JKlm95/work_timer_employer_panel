import 'package:flutter/material.dart';

/// Lightweight loading blocks (opacity pulse, no extra packages).
class AppPulseLoading extends StatefulWidget {
  const AppPulseLoading({super.key, this.rows = 4});

  final int rows;

  @override
  State<AppPulseLoading> createState() => _AppPulseLoadingState();
}

class _AppPulseLoadingState extends State<AppPulseLoading>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hi = scheme.surfaceContainerHighest;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = 0.45 + _c.value * 0.35;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < widget.rows; i++) ...[
              if (i > 0) const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    flex: i % 2 == 0 ? 3 : 2,
                    child: _Bar(color: hi.withValues(alpha: t), height: 12),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: _Bar(
                      color: hi.withValues(alpha: t * 0.85),
                      height: 12,
                    ),
                  ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.color, required this.height});

  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: SizedBox(height: height),
    );
  }
}
