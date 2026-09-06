import 'package:flutter/material.dart';
import 'package:miaogo/app_theme.dart';

/// 黑方胜率曲线面板：Y 轴 0~1（0/0.5/1 刻度），横轴手数。
///
/// 快速对弈页与历史回看页共用；数据源由调用方决定（对局采集 / 回看逐手计算）。
class WinratePanel extends StatelessWidget {
  const WinratePanel({super.key, required this.points, required this.currentHand});

  /// (手数, 黑方胜率 0..1)，按手数升序。
  final List<(int, double)> points;
  final int currentHand;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const ValueKey('winrate_panel'),
      height: 104,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      clipBehavior: Clip.antiAlias,
      child: CustomPaint(
        painter: _WinratePainter(
          points: points,
          currentHand: currentHand,
          tickStyle: theme.textTheme.labelSmall?.copyWith(
            color: GoColors.textSecondary,
          ),
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _WinratePainter extends CustomPainter {
  _WinratePainter({
    required this.points,
    required this.currentHand,
    required this.tickStyle,
  });

  final List<(int, double)> points;
  final int currentHand;
  final TextStyle? tickStyle;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 30.0;
    const right = 8.0;
    const top = 10.0;
    const bottom = 22.0;
    final plotW = size.width - left - right;
    final plotH = size.height - top - bottom;
    final maxHand = currentHand < 1 ? 1 : currentHand;

    double xOf(int hand) =>
        left + (maxHand <= 0 ? 0 : hand / maxHand * plotW);
    double yOf(double wr) =>
        top + (1 - wr.clamp(0.0, 1.0)) * plotH;

    // 参考线（0/0.5/1）与 Y 轴数值刻度。
    final grid = Paint()
      ..color = GoColors.outlineVariant.withValues(alpha: 0.7)
      ..strokeWidth = 1;
    for (final v in const [0.0, 0.5, 1.0]) {
      final y = yOf(v);
      canvas.drawLine(Offset(left, y), Offset(left + plotW, y), grid);
      final label = TextPainter(
        text: TextSpan(
          text: v == 0 ? '0' : (v == 0.5 ? '0.5' : '1'),
          style: tickStyle,
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(
          canvas, Offset(left - 4 - label.width, y - label.height / 2));
    }

    // 手数刻度。
    if (maxHand >= 1) {
      final step = maxHand > 20 ? 4 : (maxHand > 8 ? 2 : 1);
      for (var h = 0; h <= maxHand; h += step) {
        final x = xOf(h);
        final tp = TextPainter(
          text: TextSpan(text: '$h', style: tickStyle),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(x - tp.width / 2, top + plotH + 4));
      }
    }

    if (points.isEmpty) {
      final hint = TextPainter(
        text: TextSpan(
          text: '暂无胜率数据',
          style: tickStyle?.copyWith(color: GoColors.textSecondary),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      hint.paint(
        canvas,
        Offset(left + (plotW - hint.width) / 2,
            top + (plotH - hint.height) / 2),
      );
      return;
    }

    // 折线：黑方胜率。
    final linePaint = Paint()
      ..color = const Color(0xFF2B2926)
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final (h, wr) = points[i];
      final p = Offset(xOf(h), yOf(wr));
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    canvas.drawPath(path, linePaint);

    // 采样点。
    final dotPaint = Paint()..color = const Color(0xFF2B2926);
    for (final (h, wr) in points) {
      canvas.drawCircle(Offset(xOf(h), yOf(wr)), 2.2, dotPaint);
    }
  }

  @override
  bool shouldRepaint(_WinratePainter oldDelegate) => true;
}
