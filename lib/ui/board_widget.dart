import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:miaogo/app_theme.dart';
import 'package:miaogo/core/board.dart';
import 'package:miaogo/core/move.dart';

/// 一个棋盘推荐点标注：编号圆点（[isBest] 时用主色，其余用木色）。
class BoardSuggestionMark {
  const BoardSuggestionMark({
    required this.row,
    required this.col,
    required this.number,
    required this.isBest,
  });

  final int row;
  final int col;

  /// 显示序号（1 = 最推荐）。
  final int number;
  final bool isBest;
}

/// 棋盘组件：CustomPainter 绘制木色棋盘/网格/星位/坐标/棋子。
///
/// 交互为两步落子：点击/拖拽选点（[onPointTapped]/[onPointDrag]），
/// 由外部确认后落子；支持落子标记、AI 建议标注与势力范围热力图覆盖。
class GoBoardWidget extends StatelessWidget {
  const GoBoardWidget({
    super.key,
    required this.board,
    this.lastMove,
    this.hint,
    this.suggestions,
    this.selected,
    this.selectedColor = PlayerColor.black,
    this.influence,
    this.enabled = true,
    this.onPointTapped,
    this.onPointDrag,
  });

  final GoBoard board;
  final Move? lastMove;

  /// AI 建议的下一步交叉点（松柏青标注）。
  final (int, int)? hint;

  /// AI 建议候选点（最多 4 个，编号标注，最佳与其余异色）。
  final List<BoardSuggestionMark>? suggestions;

  /// 当前选中的交叉点（两步落子第一步）。
  final (int, int)? selected;

  /// 选中 ghost 子的颜色（玩家执子色）。
  final PlayerColor selectedColor;

  /// 势力范围热力图（每点 [-1,1]，正=黑/负=白）；非空时渲染覆盖层。
  final List<List<double>>? influence;
  final bool enabled;
  final void Function(int row, int col)? onPointTapped;
  final void Function(int row, int col)? onPointDrag;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(builder: (context, constraints) {
        final side = constraints.maxWidth;
        final geometry = _BoardGeometry(side, board.size);
        return GestureDetector(
          onTapUp: enabled
              ? (details) {
                  final p = geometry.pointAt(details.localPosition, board.size);
                  if (p == null) return;
                  onPointTapped?.call(p.$1, p.$2);
                }
              : null,
          onPanStart: enabled && onPointDrag != null
              ? (details) {
                  final p = geometry.pointAt(details.localPosition, board.size);
                  if (p == null) return;
                  onPointDrag?.call(p.$1, p.$2);
                }
              : null,
          onPanUpdate: enabled && onPointDrag != null
              ? (details) {
                  final p = geometry.pointAt(details.localPosition, board.size);
                  if (p == null) return;
                  onPointDrag?.call(p.$1, p.$2);
                }
              : null,
          child: CustomPaint(
            size: Size.square(side),
            painter: _BoardPainter(
              board: board,
              lastMove: lastMove,
              hint: hint,
              suggestions: suggestions,
              selected: selected,
              selectedColor: selectedColor,
              influence: influence,
              geometry: geometry,
            ),
          ),
        );
      }),
    );
  }
}

class _BoardGeometry {
  _BoardGeometry(double side, int size)
      : margin = side * 0.06,
        cell = (side - side * 0.12) / (size - 1);

  final double margin;
  final double cell;

  /// 取触点最近的交叉点；超出棋盘返回 null。
  (int, int)? pointAt(Offset local, int size) {
    final col = ((local.dx - margin) / cell).round();
    final row = ((local.dy - margin) / cell).round();
    if (row < 0 || row >= size || col < 0 || col >= size) return null;
    final x = margin + col * cell;
    final y = margin + row * cell;
    final tol = cell * 0.55;
    if ((local.dx - x).abs() <= tol && (local.dy - y).abs() <= tol) {
      return (row, col);
    }
    return null;
  }
}

class _BoardPainter extends CustomPainter {
  _BoardPainter({
    required this.board,
    required this.lastMove,
    required this.hint,
    required this.suggestions,
    required this.selected,
    required this.selectedColor,
    required this.influence,
    required this.geometry,
  });

  final GoBoard board;
  final Move? lastMove;
  final (int, int)? hint;
  final List<BoardSuggestionMark>? suggestions;
  final (int, int)? selected;
  final PlayerColor selectedColor;
  final List<List<double>>? influence;
  final _BoardGeometry geometry;

  @override
  void paint(Canvas canvas, Size size) {
    final n = board.size;
    final margin = geometry.margin;
    final cell = geometry.cell;
    final boardEdge = margin + (n - 1) * cell;

    // 棋盘底色
    final bgPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: const [Color(0xFFEBCFA1), Color(0xFFDCB07D)],
      ).createShader(Offset.zero & size);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(10)),
      bgPaint,
    );

    // 网格线
    final linePaint = Paint()
      ..color = const Color(0xFF7A4B28).withValues(alpha: 0.75)
      ..strokeWidth = math.max(0.7, cell * 0.04);
    for (var i = 0; i < n; i++) {
      final p = margin + i * cell;
      canvas.drawLine(Offset(p, margin), Offset(p, boardEdge), linePaint);
      canvas.drawLine(Offset(margin, p), Offset(boardEdge, p), linePaint);
    }

    // 势力范围热力图（画在棋子下方）
    _drawInfluence(canvas, margin, cell);

    // 星位
    final starPaint = Paint()..color = const Color(0xFF7A4B28);
    for (final (r, c) in GoBoard.starPoints(n)) {
      canvas.drawCircle(
        Offset(margin + c * cell, margin + r * cell),
        cell * 0.1,
        starPaint,
      );
    }

    // 棋子
    for (var r = 0; r < n; r++) {
      for (var c = 0; c < n; c++) {
        final stone = board.at(r, c);
        if (stone == null) continue;
        _drawStone(
          canvas,
          stone,
          Offset(margin + c * cell, margin + r * cell),
          cell * 0.46,
        );
      }
    }

    // 选中标记（两步落子第一步）
    if (selected != null) {
      final center = Offset(
        margin + selected!.$2 * cell,
        margin + selected!.$1 * cell,
      );
      final ghost = selectedColor == PlayerColor.black;
      canvas.drawCircle(
        center,
        cell * 0.44,
        Paint()
          ..color = ghost
              ? Colors.black.withValues(alpha: 0.30)
              : Colors.white.withValues(alpha: 0.55),
      );
      canvas.drawCircle(
        center,
        cell * 0.44,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = cell * 0.06
          ..color = GoColors.woodDark.withValues(alpha: 0.9),
      );
      canvas.drawCircle(
        center,
        cell * 0.12,
        Paint()..color = GoColors.woodDark,
      );
    }

    // 落子标记
    if (lastMove != null && !lastMove!.isPass && !lastMove!.isResign) {
      final center = Offset(
        margin + lastMove!.col! * cell,
        margin + lastMove!.row! * cell,
      );
      final markerColor = lastMove!.color == PlayerColor.black
          ? Colors.white70
          : GoColors.pineDark;
      canvas.drawCircle(center, cell * 0.15, Paint()..color = markerColor);
    }

    // AI 建议标记（P2 启用）
    if (hint != null) {
      final center = Offset(
        margin + hint!.$2 * cell,
        margin + hint!.$1 * cell,
      );
      canvas.drawCircle(
        center,
        cell * 0.22,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = cell * 0.08
          ..color = GoColors.pine,
      );
    }

    // 推荐点编号标注（最多 4 个；最佳主色、其余木色）
    final marks = suggestions;
    if (marks != null && marks.isNotEmpty) {
      for (final mark in marks) {
        final center = Offset(
          margin + mark.col * cell,
          margin + mark.row * cell,
        );
        final radius = cell * 0.24;
        canvas.drawCircle(
          center.translate(0, radius * 0.1),
          radius,
          Paint()..color = Colors.black.withValues(alpha: 0.15),
        );
        canvas.drawCircle(
          center,
          radius,
          Paint()
            ..color = mark.isBest ? GoColors.pine : GoColors.woodDark,
        );
        canvas.drawCircle(
          center,
          radius,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(1, cell * 0.03)
            ..color = Colors.white.withValues(alpha: 0.55),
        );
        final label = TextPainter(
          text: TextSpan(
            text: '${mark.number}',
            style: TextStyle(
              color: Colors.white,
              fontSize: radius * 1.1,
              fontWeight: FontWeight.w700,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        label.paint(
          canvas,
          Offset(center.dx - label.width / 2, center.dy - label.height / 2),
        );
      }
    }

    // 坐标：左侧数字 + 底部字母（SGF a..t 跳过 i）
    _drawCoordinates(canvas, margin, cell, n, boardEdge);
  }

  void _drawInfluence(Canvas canvas, double margin, double cell) {
    final map = influence;
    if (map == null) return;
    final n = board.size;
    for (var r = 0; r < n; r++) {
      for (var c = 0; c < n; c++) {
        final v = map[r][c];
        if (v == 0 || board.at(r, c) != null) continue;
        final center = Offset(margin + c * cell, margin + r * cell);
        final radius = cell * 0.5;
        final alpha = (v.abs() * 0.6).clamp(0.12, 0.6);
        final color = v > 0
            ? GoColors.pine
            : const Color(0xFFFCF6EC);
        canvas.drawCircle(
          center,
          radius,
          Paint()..color = color.withValues(alpha: alpha),
        );
      }
    }
  }

  void _drawStone(
      Canvas canvas, PlayerColor color, Offset center, double radius) {
    canvas.drawCircle(
      center.translate(0, radius * 0.06),
      radius,
      Paint()..color = Colors.black.withValues(alpha: 0.18),
    );
    final paint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.35, -0.35),
        colors: color == PlayerColor.black
            ? const [Color(0xFF555555), Color(0xFF111111)]
            : const [Color(0xFFFFFFFF), Color(0xFFD8D3C9)],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, paint);
    if (color == PlayerColor.white) {
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = const Color(0xFFA8A096),
      );
    }
  }

  void _drawCoordinates(
      Canvas canvas, double margin, double cell, int n, double boardEdge) {
    final textStyle = const TextStyle(
      color: GoColors.woodDark,
      fontSize: 10,
      fontWeight: FontWeight.w600,
    );
    for (var i = 0; i < n; i++) {
      // 左侧数字（1..n，自上而下）
      final num = TextPainter(
        text: TextSpan(text: '${i + 1}', style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      num.paint(
        canvas,
        Offset(margin * 0.35, margin + i * cell - num.height / 2),
      );
      // 底部字母（SGF a..t 跳过 i）
      final letter = TextPainter(
        text: TextSpan(
          text: GoBoard.letters[i],
          style: textStyle.copyWith(fontSize: 9),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      letter.paint(
        canvas,
        Offset(margin + i * cell - letter.width / 2, boardEdge + margin * 0.45),
      );
    }
  }

  @override
  bool shouldRepaint(_BoardPainter oldDelegate) =>
      oldDelegate.board != board ||
      oldDelegate.lastMove != lastMove ||
      oldDelegate.hint != hint ||
      oldDelegate.suggestions != suggestions ||
      oldDelegate.selected != selected ||
      oldDelegate.selectedColor != selectedColor ||
      oldDelegate.influence != influence;
}
