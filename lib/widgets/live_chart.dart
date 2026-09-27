import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Rolling window of samples for a live chart.
class Series {
  Series([this.capacity = 60]);

  final int capacity;
  final List<double> values = [];

  void add(double? v) {
    if (v == null || v.isNaN) return;
    values.add(v);
    if (values.length > capacity) values.removeAt(0);
  }

  double? get last => values.isEmpty ? null : values.last;
  double get avg => values.isEmpty ? 0 : values.reduce((a, b) => a + b) / values.length;
  double get peak => values.isEmpty ? 0 : values.reduce(math.max);
}

class ChartLine {
  const ChartLine(this.values, this.color, {this.fill = true});

  final List<double> values;
  final Color color;
  final bool fill;
}

/// Live line chart: soft area fill, faint dashed grid, optional dashed
/// average line and a dot on the newest sample. Newest sample on the right.
class LiveChart extends StatelessWidget {
  const LiveChart({
    super.key,
    required this.lines,
    this.maxY,
    this.avg,
    this.capacity = 60,
    this.height = 64,
    this.grid = true,
  });

  final List<ChartLine> lines;

  /// Fixed top of the scale (100 for percentages); auto when null.
  final double? maxY;

  /// Draws a dashed horizontal line at this value.
  final double? avg;
  final int capacity;
  final double height;
  final bool grid;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(
          painter: _ChartPainter(
            lines: lines,
            maxY: maxY,
            avg: avg,
            capacity: capacity,
            grid: grid,
            gridColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.08),
          ),
        ),
      );
}

class _ChartPainter extends CustomPainter {
  _ChartPainter({
    required this.lines,
    required this.maxY,
    required this.avg,
    required this.capacity,
    required this.grid,
    required this.gridColor,
  });

  final List<ChartLine> lines;
  final double? maxY;
  final double? avg;
  final int capacity;
  final bool grid;
  final Color gridColor;

  void _dashed(Canvas c, double y, double w, Paint p) {
    for (var x = 0.0; x < w; x += 7) {
      c.drawLine(Offset(x, y), Offset(math.min(x + 3.5, w), y), p);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final top = 4.0, bottom = h - 2;
    if (grid) {
      final gp = Paint()
        ..color = gridColor
        ..strokeWidth = 1;
      for (var i = 0; i < 4; i++) {
        _dashed(canvas, top + (bottom - top) * i / 3, w, gp);
      }
    }
    var peak = maxY ?? 0;
    if (maxY == null) {
      for (final l in lines) {
        for (final v in l.values) {
          peak = math.max(peak, v);
        }
      }
      peak = peak <= 0 ? 1 : peak * 1.15;
    }
    double yOf(double v) => bottom - (v.clamp(0, peak) / peak) * (bottom - top);
    final step = w / math.max(1, capacity - 1);

    for (final l in lines) {
      final vals = l.values;
      if (vals.isEmpty) continue;
      final startX = w - (vals.length - 1) * step;
      final path = Path();
      for (var i = 0; i < vals.length; i++) {
        final x = startX + i * step, y = yOf(vals[i]);
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          // Smooth with a midpoint curve.
          final px = startX + (i - 1) * step, py = yOf(vals[i - 1]);
          final mx = (px + x) / 2;
          path.cubicTo(mx, py, mx, y, x, y);
        }
      }
      if (l.fill && vals.length > 1) {
        final area = Path.from(path)
          ..lineTo(w, bottom)
          ..lineTo(startX, bottom)
          ..close();
        canvas.drawPath(
          area,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [l.color.withValues(alpha: 0.35), l.color.withValues(alpha: 0.02)],
            ).createShader(Rect.fromLTWH(0, top, w, bottom - top)),
        );
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = l.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8
          ..strokeJoin = StrokeJoin.round,
      );
      canvas.drawCircle(Offset(w, yOf(vals.last)), 3, Paint()..color = l.color);
    }
    if (avg != null && lines.isNotEmpty) {
      _dashed(
          canvas,
          yOf(avg!),
          w,
          Paint()
            ..color = lines.first.color.withValues(alpha: 0.7)
            ..strokeWidth = 1.2);
    }
  }

  @override
  bool shouldRepaint(covariant _ChartPainter old) => true;
}
