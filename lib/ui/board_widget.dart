import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:miaogo/app_theme.dart';
import 'package:miaogo/core/board.dart';
import 'package:miaogo/core/move.dart';

/// 通用棋盘标注样式。
enum BoardMarkKind {
  /// 小实心圆点（如标“气”）。
  dot,

  /// 圆形徽章 + 居中文字（选项数字、✗、字母等）。
  badge,

  /// 提示圆环。
  ring,
}

/// 棋盘通用标注：用于引导/教程在交叉点上做气点、选项、禁点等可视化。
class BoardMark {
  const BoardMark.dot({
    required this.row,
    required this.col,
    this.color,
  })  : kind = BoardMarkKind.dot,
        text = null;

  const BoardMark.badge({
    required this.row,
    required this.col,
    this.text,
    this.color,
  }) : kind = BoardMarkKind.badge;

  const BoardMark.ring({
    required this.row,
    required this.col,
    this.color,
  })  : kind = BoardMarkKind.ring,
        text = null;

  final int row;
  final int col;
  final BoardMarkKind kind;
  final String? text;

  /// 覆盖默认色（仅可使用主题令牌色，见 [GoColors]）。
  final Color? color;

  @override
  bool operator ==(Object other) =>
      other is BoardMark &&
      other.row == row &&
      other.col == col &&
      other.kind == kind &&
      other.text == text &&
      other.color == color;

  @override
  int get hashCode => Object.hash(row, col, kind, text, color);
}

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

/// 棋盘可视区域（裁剪/放大）：从 `(startRow, startCol)` 起取 `size×size`
/// 个交叉点的窗口。用于死活题等只关注棋盘一隅的场景，把局部放大到整块棋盘。
class BoardViewport {
  const BoardViewport({
    required this.startRow,
    required this.startCol,
    required this.size,
  });

  /// 整盘视图。
  factory BoardViewport.full(int boardSize) =>
      BoardViewport(startRow: 0, startCol: 0, size: boardSize);

  final int startRow;
  final int startCol;
  final int size;

  @override
  bool operator ==(Object other) =>
      other is BoardViewport &&
      other.startRow == startRow &&
      other.startCol == startCol &&
      other.size == size;

  @override
  int get hashCode => Object.hash(startRow, startCol, size);
}

/// 棋盘组件：CustomPainter 绘制木色棋盘/网格/星位/坐标/棋子。
///
/// 交互支持单击选点（[onPointTapped]）、拖拽选点（[onPointDrag]）与双击
/// 落子（[onPointDoubleTapped]）；支持落子标记、AI 建议标注与势力范围热力图覆盖。
class GoBoardWidget extends StatelessWidget {
  const GoBoardWidget({
    super.key,
    required this.board,
    this.lastMove,
    this.lastMoveEmphasis = false,
    this.hint,
    this.suggestions,
    this.marks,
    this.selected,
    this.selectedColor = PlayerColor.black,
    this.influence,
    this.enabled = true,
    this.viewport,
    this.onPointTapped,
    this.onPointDrag,
    this.onPointDoubleTapped,
  });

  final GoBoard board;
  final Move? lastMove;

  /// 是否对最新一手棋子做「双层光环」强调（观赛等场景提醒最新落子）。
  final bool lastMoveEmphasis;

  /// AI 建议的下一步交叉点（松柏青标注）。
  final (int, int)? hint;

  /// AI 建议候选点（最多 4 个，编号标注，最佳与其余异色）。
  final List<BoardSuggestionMark>? suggestions;

  /// 教程通用标注（气点/选项/禁点/提示环）。
  final List<BoardMark>? marks;

  /// 当前选中的交叉点（两步落子第一步）。
  final (int, int)? selected;

  /// 选中 ghost 子的颜色（玩家执子色）。
  final PlayerColor selectedColor;

  /// 势力范围热力图（每点 [-1,1]，正=黑/负=白）；非空时渲染覆盖层。
  final List<List<double>>? influence;
  final bool enabled;

  /// 裁剪/放大视图；null 表示整盘。
  final BoardViewport? viewport;

  final void Function(int row, int col)? onPointTapped;
  final void Function(int row, int col)? onPointDrag;
  final void Function(int row, int col)? onPointDoubleTapped;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(builder: (context, constraints) {
        final side = constraints.maxWidth;
        final vp = viewport ?? BoardViewport.full(board.size);
        final geometry = _BoardGeometry(side, board.size, vp);
        return GestureDetector(
          onTapUp: enabled && onPointTapped != null
              ? (details) {
                  final p = geometry.pointAt(details.localPosition);
                  if (p == null) return;
                  onPointTapped?.call(p.$1, p.$2);
                }
              : null,
          onDoubleTapDown: enabled && onPointDoubleTapped != null
              ? (details) {
                  final p = geometry.pointAt(details.localPosition);
                  if (p == null) return;
                  onPointDoubleTapped?.call(p.$1, p.$2);
                }
              : null,
          onPanStart: enabled && onPointDrag != null
              ? (details) {
                  final p = geometry.pointAt(details.localPosition);
                  if (p == null) return;
                  onPointDrag?.call(p.$1, p.$2);
                }
              : null,
          onPanUpdate: enabled && onPointDrag != null
              ? (details) {
                  final p = geometry.pointAt(details.localPosition);
                  if (p == null) return;
                  onPointDrag?.call(p.$1, p.$2);
                }
              : null,
          child: CustomPaint(
            size: Size.square(side),
            painter: _BoardPainter(
              board: board,
              lastMove: lastMove,
              lastMoveEmphasis: lastMoveEmphasis,
              hint: hint,
              suggestions: suggestions,
              marks: marks,
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
  _BoardGeometry(double side, this.boardSize, this.viewport)
      : margin = side * 0.06,
        cell = (side - side * 0.12) / (viewport.size - 1);

  final int boardSize;
  final BoardViewport viewport;
  final double margin;
  final double cell;

  /// 交叉点 → 画布局部坐标。
  Offset pointToLocal(int row, int col) => Offset(
        margin + (col - viewport.startCol) * cell,
        margin + (row - viewport.startRow) * cell,
      );

  /// 取触点最近的交叉点；超出可视区域返回 null。
  (int, int)? pointAt(Offset local) {
    final col = ((local.dx - margin) / cell).round() + viewport.startCol;
    final row = ((local.dy - margin) / cell).round() + viewport.startRow;
    if (row < viewport.startRow ||
        row >= viewport.startRow + viewport.size ||
        col < viewport.startCol ||
        col >= viewport.startCol + viewport.size) {
      return null;
    }
    if (row < 0 || row >= boardSize || col < 0 || col >= boardSize) {
      return null;
    }
    final x = margin + (col - viewport.startCol) * cell;
    final y = margin + (row - viewport.startRow) * cell;
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
    required this.lastMoveEmphasis,
    required this.hint,
    required this.suggestions,
    required this.marks,
    required this.selected,
    required this.selectedColor,
    required this.influence,
    required this.geometry,
  });

  final GoBoard board;
  final Move? lastMove;
  final bool lastMoveEmphasis;
  final (int, int)? hint;
  final List<BoardSuggestionMark>? suggestions;
  final List<BoardMark>? marks;
  final (int, int)? selected;
  final PlayerColor selectedColor;
  final List<List<double>>? influence;
  final _BoardGeometry geometry;

  @override
  void paint(Canvas canvas, Size size) {
    final vp = geometry.viewport;
    final margin = geometry.margin;
    final cell = geometry.cell;
    final viewSize = vp.size;
    final boardEdge = margin + (viewSize - 1) * cell;

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
    for (var i = 0; i < viewSize; i++) {
      final p = margin + i * cell;
      canvas.drawLine(Offset(p, margin), Offset(p, boardEdge), linePaint);
      canvas.drawLine(Offset(margin, p), Offset(boardEdge, p), linePaint);
    }

    // 势力范围热力图（画在棋子下方）
    _drawInfluence(canvas);

    // 星位
    final starPaint = Paint()..color = const Color(0xFF7A4B28);
    for (final (r, c) in GoBoard.starPoints(board.size)) {
      if (!_inView(r, c)) continue;
      canvas.drawCircle(geometry.pointToLocal(r, c), cell * 0.1, starPaint);
    }

    // 棋子
    final rEnd = math.min(vp.startRow + viewSize, board.size);
    final cEnd = math.min(vp.startCol + viewSize, board.size);
    for (var r = vp.startRow; r < rEnd; r++) {
      for (var c = vp.startCol; c < cEnd; c++) {
        final stone = board.at(r, c);
        if (stone == null) continue;
        _drawStone(
          canvas,
          stone,
          geometry.pointToLocal(r, c),
          cell * 0.46,
        );
      }
    }

    // 选中标记（两步落子第一步）
    if (selected != null) {
      final center = geometry.pointToLocal(selected!.$1, selected!.$2);
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
      final center = geometry.pointToLocal(lastMove!.row!, lastMove!.col!);
      final markerColor = lastMove!.color == PlayerColor.black
          ? Colors.white70
          : GoColors.pineDark;
      canvas.drawCircle(center, cell * 0.15, Paint()..color = markerColor);

      // 最新一手强调：静态双层光环包围最新落子。
      if (lastMoveEmphasis) {
        canvas.drawCircle(
          center,
          cell * 0.48,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = cell * 0.07
            ..color = GoColors.wood.withValues(alpha: 0.9),
        );
        canvas.drawCircle(
          center,
          cell * 0.36,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = cell * 0.05
            ..color = GoColors.pine,
        );
      }
    }

    // AI 建议标记（P2 启用）
    if (hint != null) {
      final center = geometry.pointToLocal(hint!.$1, hint!.$2);
      canvas.drawCircle(
        center,
        cell * 0.22,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = cell * 0.08
          ..color = GoColors.pine,
      );
    }

    // 教程通用标注（气点/选项/禁点等）
    _drawGuideMarks(canvas);

    // 推荐点编号标注（最多 4 个；最佳主色、其余木色）
    final suggestionMarks = suggestions;
    if (suggestionMarks != null && suggestionMarks.isNotEmpty) {
      for (final mark in suggestionMarks) {
        final center = geometry.pointToLocal(mark.row, mark.col);
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
    _drawCoordinates(canvas, viewSize, boardEdge);
  }

  /// 交叉点是否落在当前可视区域内。
  bool _inView(int row, int col) {
    final vp = geometry.viewport;
    return row >= vp.startRow &&
        row < vp.startRow + vp.size &&
        col >= vp.startCol &&
        col < vp.startCol + vp.size;
  }

  void _drawInfluence(Canvas canvas) {
    final map = influence;
    if (map == null) return;
    final vp = geometry.viewport;
    final rEnd = math.min(vp.startRow + vp.size, board.size);
    final cEnd = math.min(vp.startCol + vp.size, board.size);
    for (var r = vp.startRow; r < rEnd; r++) {
      for (var c = vp.startCol; c < cEnd; c++) {
        final v = map[r][c];
        if (v == 0 || board.at(r, c) != null) continue;
        final center = geometry.pointToLocal(r, c);
        final radius = geometry.cell * 0.5;
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

  void _drawGuideMarks(Canvas canvas) {
    final list = marks;
    if (list == null || list.isEmpty) return;
    final cell = geometry.cell;
    for (final mark in list) {
      final center = geometry.pointToLocal(mark.row, mark.col);
      switch (mark.kind) {
        case BoardMarkKind.dot:
          final radius = cell * 0.13;
          final color = mark.color ?? GoColors.pine;
          canvas.drawCircle(
            center.translate(0, radius * 0.08),
            radius,
            Paint()..color = Colors.black.withValues(alpha: 0.15),
          );
          canvas.drawCircle(center, radius, Paint()..color = color);
          canvas.drawCircle(
            center,
            radius,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = math.max(0.6, cell * 0.02)
              ..color = Colors.white.withValues(alpha: 0.7),
          );
        case BoardMarkKind.badge:
          final radius = cell * 0.24;
          final color = mark.color ?? GoColors.woodDark;
          canvas.drawCircle(
            center.translate(0, radius * 0.1),
            radius,
            Paint()..color = Colors.black.withValues(alpha: 0.15),
          );
          canvas.drawCircle(center, radius, Paint()..color = color);
          canvas.drawCircle(
            center,
            radius,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = math.max(1, cell * 0.03)
              ..color = Colors.white.withValues(alpha: 0.55),
          );
          final text = mark.text ?? '';
          final label = TextPainter(
            text: TextSpan(
              text: text,
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
        case BoardMarkKind.ring:
          final color = mark.color ?? GoColors.pine;
          canvas.drawCircle(
            center,
            cell * 0.22,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = cell * 0.08
              ..color = color,
          );
      }
    }
  }

  void _drawCoordinates(Canvas canvas, int viewSize, double boardEdge) {
    final margin = geometry.margin;
    final cell = geometry.cell;
    final vp = geometry.viewport;
    final textStyle = const TextStyle(
      color: GoColors.woodDark,
      fontSize: 10,
      fontWeight: FontWeight.w600,
    );
    for (var i = 0; i < viewSize; i++) {
      final rowIndex = vp.startRow + i;
      final colIndex = vp.startCol + i;
      // 左侧数字（棋盘行号，自上而下）
      final num = TextPainter(
        text: TextSpan(text: '${rowIndex + 1}', style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      num.paint(
        canvas,
        Offset(margin * 0.35, margin + i * cell - num.height / 2),
      );
      // 底部字母（SGF a..t 跳过 i）
      if (colIndex >= 0 && colIndex < GoBoard.letters.length) {
        final letter = TextPainter(
          text: TextSpan(
            text: GoBoard.letters[colIndex],
            style: textStyle.copyWith(fontSize: 9),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        letter.paint(
          canvas,
          Offset(
              margin + i * cell - letter.width / 2, boardEdge + margin * 0.45),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_BoardPainter oldDelegate) =>
      oldDelegate.board != board ||
      oldDelegate.lastMove != lastMove ||
      oldDelegate.lastMoveEmphasis != lastMoveEmphasis ||
      oldDelegate.hint != hint ||
      oldDelegate.suggestions != suggestions ||
      !listEquals(oldDelegate.marks, marks) ||
      oldDelegate.selected != selected ||
      oldDelegate.selectedColor != selectedColor ||
      oldDelegate.influence != influence ||
      oldDelegate.geometry.viewport != geometry.viewport;
}
