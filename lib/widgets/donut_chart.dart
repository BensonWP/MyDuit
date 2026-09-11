import 'dart:math';

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class DonutSegment {
  const DonutSegment({required this.value, required this.color});
  final double value;
  final Color color;
}

/// Donut chart tanpa library — segmen proporsional, gap 3°,
/// total di tengah. Sweep sekali saat muncul (hormati disableAnimations).
class DonutChart extends StatelessWidget {
  const DonutChart({
    super.key,
    required this.segments,
    required this.centerTitle,
    required this.centerValue,
    this.size = 148,
    this.stroke = 22,
  });

  final List<DonutSegment> segments;
  final String centerTitle;
  final String centerValue;
  final double size;
  final double stroke;

  @override
  Widget build(BuildContext context) {
    final animate = !MediaQuery.of(context).disableAnimations;
    return SizedBox(
      width: size,
      height: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: animate ? const Duration(milliseconds: 700) : Duration.zero,
        curve: Curves.easeOutCubic,
        builder: (_, t, _) => CustomPaint(
          painter:
              _DonutPainter(segments: segments, stroke: stroke, progress: t),
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(stroke * 0.9),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(centerTitle,
                      style: const TextStyle(
                          fontSize: 11,
                          color: D.inkMuted,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(centerValue,
                        maxLines: 1,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3)),
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

class _DonutPainter extends CustomPainter {
  _DonutPainter({
    required this.segments,
    required this.stroke,
    required this.progress,
  });

  final List<DonutSegment> segments;
  final double stroke;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - stroke / 2;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt;

    final total = segments.fold<double>(0, (a, s) => a + s.value);
    if (total <= 0) {
      paint.color = D.line;
      canvas.drawCircle(center, radius, paint);
      return;
    }

    final gap = segments.length > 1 ? 0.05 : 0.0; // ~3° dalam radian
    final sweepBudget = (2 * pi - gap * segments.length) * progress;
    var start = -pi / 2; // mulai dari pukul 12
    for (final s in segments) {
      final sweep = s.value / total * sweepBudget;
      if (sweep <= 0) break;
      paint.color = s.color;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        start,
        sweep,
        false,
        paint,
      );
      start += sweep + gap * progress;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) =>
      old.progress != progress || old.segments != segments;
}
