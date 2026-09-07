import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:miaogo/app_theme.dart';
import 'package:miaogo/core/board.dart';
import 'package:miaogo/core/joseki.dart';
import 'package:miaogo/core/move.dart';
import 'package:miaogo/storage/settings_store.dart';
import 'package:miaogo/study/joseki_library.dart';

const int _size = 19;

/// 定式查询：完整 19 路棋盘，用户按设置中的落子方式落子；
/// 依据定式库推荐最高概率的后续点位（颜色深浅表示概率），下方列出命中定式；
/// 点选某条后进入逐步查看（上一手 / 下一手 / 退出）。二次返回弹窗回功能首页。
class JosekiPracticePage extends ConsumerStatefulWidget {
  const JosekiPracticePage({super.key});

  @override
  ConsumerState<JosekiPracticePage> createState() =>
      _JosekiPracticePageState();
}

class _JosekiPracticePageState extends ConsumerState<JosekiPracticePage> {
  /// 用户（查询态）已落的棋步。
  final List<Move> _moves = [];

  /// 两步落子：当前选中点（confirm 模式需确认后落子）。
  (int, int)? _selected;

  /// 逐步查看选中的定式；为空表示查询态。
  JosekiEntry? _viewing;

  /// 逐步查看的当前步数（0..moves.length）。
  int _step = 0;

  /// 上次系统返回时间（双击返回判定）。
  DateTime? _lastBackAt;

  MoveStyle get _moveStyle =>
      ref.read(settingsProvider).moveStyle;

  /// 展开当前指定角：取首手所属角；为空默认右上角（规范角）。
  String get _corner {
    if (_moves.isEmpty) return 'TR';
    return JosekiCoords.cornerOf(_moves.first.row!, _moves.first.col!, _size) ??
        'TR';
  }

  /// 当前查询着法的规范串。
  List<String> get _canonical => JosekiCoords.canonical(
      [for (final m in _moves) (m.row!, m.col!)], _size);

  void _reset() => setState(() {
        _moves.clear();
        _selected = null;
        _viewing = null;
        _step = 0;
      });

  void _undo() {
    if (_moves.isEmpty) return;
    setState(() {
      _moves.removeLast();
      _selected = null;
    });
  }

  /// 棋盘点击（第一步）。
  void _onPointTapped(int row, int col) {
    if (_viewing != null) return; // 逐步查看态不可落子。
    if (_moveStyle == MoveStyle.doubleTap) {
      if (_selected == (row, col)) {
        _placeSelected();
      } else {
        setState(() => _selected = (row, col));
      }
      return;
    }
    setState(() => _selected = (row, col));
  }

  /// 拖拽移动选中点。
  void _onPointDrag(int row, int col) {
    if (_viewing != null) return;
    setState(() => _selected = (row, col));
  }

  /// 第二步：确认落子。
  void _placeSelected() {
    final sel = _selected;
    if (sel == null) return;
    if (!_inBounds(sel.$1, sel.$2)) return;
    if (_occupied(sel.$1, sel.$2)) return;
    final color =
        _moves.length.isEven ? PlayerColor.black : PlayerColor.white;
    setState(() {
      _moves.add(Move.point(color, sel.$1, sel.$2));
      _selected = null;
    });
  }

  bool _inBounds(int row, int col) =>
      row >= 0 && row < _size && col >= 0 && col < _size;

  bool _occupied(int row, int col) =>
      _moves.any((m) => m.row == row && m.col == col && !m.isPass);

  /// 进入逐步查看：保留当前局面（停在命中手数处），可整条回放。
  void _startView(JosekiMatch match) {
    setState(() {
      _viewing = match.entry;
      final len = match.entry.moves.length;
      _step = match.matchLen > len ? len : match.matchLen;
    });
  }

  void _exitView() => setState(() {
        _viewing = null;
        _step = 0;
      });

  void _stepPrev() {
    if (_step > 0) setState(() => _step--);
  }

  void _stepNext() {
    if (_step < (_viewing?.moves.length ?? 0)) setState(() => _step++);
  }

  /// 系统返回：首次提示，2 秒内再次返回弹窗回功能首页。
  void _handleBack() {
    final now = DateTime.now();
    final last = _lastBackAt;
    _lastBackAt = now;
    if (last != null && now.difference(last) < const Duration(seconds: 2)) {
      _showExitDialog();
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(
        content: Text('再按一次返回退出'),
        duration: Duration(milliseconds: 1200),
      ));
  }

  Future<void> _showExitDialog() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('退出定式查询'),
        content: const Text('确定退出并回到功能首页吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('退出'),
          ),
        ],
      ),
    );
    if (confirm == true && mounted) _exitToHome();
  }

  void _exitToHome() {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final library = ref.watch(josekiLibraryProvider).valueOrNull;
    final theme = Theme.of(context);
    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('定式查询')),
        body: library == null
            ? const Center(child: CircularProgressIndicator())
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 420),
                          child: AspectRatio(
                            aspectRatio: 1,
                            child: _FullBoard(
                              key: const ValueKey('joseki_board'),
                              moves: _viewing == null
                                  ? _moves
                                  : movesInCorner(_viewing!.moves, _corner,
                                      _size)
                                      .take(_step)
                                      .toList(),
                              selected: _viewing == null ? _selected : null,
                              hints:
                                  _viewing == null ? _hints(library) : const [],
                              onTap: _onPointTapped,
                              onDrag: _onPointDrag,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (_viewing == null) _controls(theme, library),
                      const SizedBox(height: 8),
                      Expanded(
                        child: _viewing == null
                            ? _matchList(theme, library)
                            : _viewerControls(theme),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  /// 查询态最高概率的推荐点位（TR 规范坐标 + 概率），映射到当前角。
  List<JosekiMoveHint> _hints(JosekiLibrary library) {
    return recommendNext(library.entries, _canonical)
        .where((h) {
          final (r, c) = GoBoard.coordFromSgf(h.coord);
          final (br, bc) = JosekiCoords.fromTr((r, c), _corner, _size);
          return !_occupied(br, bc);
        })
        .toList();
  }

  ButtonStyle _btnStyle(ThemeData theme) => OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 12),
        side: BorderSide(color: theme.colorScheme.outline),
      );

  Widget _controls(ThemeData theme, JosekiLibrary library) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _undo,
            icon: const Icon(Icons.undo, size: 18),
            label: const Text('撤销'),
            style: _btnStyle(theme),
          ),
        ),
        const SizedBox(width: 8),
        if (_moveStyle == MoveStyle.confirm)
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _placeSelected,
              icon: const Icon(Icons.circle, size: 16),
              label: const Text('落子'),
              style: _btnStyle(theme),
            ),
          ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _reset,
            icon: const Icon(Icons.replay, size: 18),
            label: const Text('清空'),
            style: _btnStyle(theme),
          ),
        ),
      ],
    );
  }

  Widget _viewerControls(ThemeData theme) {
    final len = _viewing?.moves.length ?? 0;
    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _stepPrev,
                icon: const Icon(Icons.chevron_left, size: 18),
                label: const Text('上一手'),
                style: _btnStyle(theme),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _stepNext,
                icon: const Icon(Icons.chevron_right, size: 18),
                label: const Text('下一手'),
                style: _btnStyle(theme),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _exitView,
                icon: const Icon(Icons.logout, size: 18),
                label: const Text('退出'),
                style: _btnStyle(theme),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_viewing != null)
          Text(
            '${_viewing!.label}\n第 $_step/$len 手',
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: GoColors.textSecondary),
          ),
      ],
    );
  }

  Widget _matchList(ThemeData theme, JosekiLibrary library) {
    if (_moves.isEmpty) {
      return Center(
        child: Text(
          '在棋盘上落子，下方会推荐匹配的定式',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: GoColors.textSecondary),
        ),
      );
    }
    final matches = library.matcher.match(_canonical);
    if (matches.isEmpty) {
      return Center(
        child: Text(
          '当前着法未收录到定式库，换一手试试',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: GoColors.textSecondary),
        ),
      );
    }
    return ListView.separated(
      itemCount: matches.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final m = matches[i];
        return Card(
          elevation: 0,
          color: theme.colorScheme.surfaceContainerHighest,
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            leading: CircleAvatar(
              radius: 22,
              backgroundColor: GoColors.woodContainer,
              child: const Icon(Icons.auto_awesome, color: GoColors.wood),
            ),
            title: Text(
              m.entry.label,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              '${m.summary} · 出现 ${m.entry.frequency ?? 0} 次',
              style: theme.textTheme.bodySmall,
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _startView(m),
          ),
        );
      },
    );
  }
}

/// 完整 19 路棋盘：绘制木色棋盘、网格、星位、坐标、棋子和概率推荐点。
class _FullBoard extends StatelessWidget {
  const _FullBoard({
    super.key,
    required this.moves,
    required this.selected,
    required this.hints,
    required this.onTap,
    required this.onDrag,
  });

  final List<Move> moves;

  /// 两步落子的选中点（confirm 模式 ghost 标记）。
  final (int, int)? selected;

  final List<JosekiMoveHint> hints;
  final void Function(int row, int col) onTap;
  final void Function(int row, int col) onDrag;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final side = constraints.maxWidth;
      final geometry = _BoardGeometry(side, _size);
      return GestureDetector(
        onTapUp: (details) {
          final p = geometry.pointAt(details.localPosition, _size);
          if (p == null) return;
          onTap(p.$1, p.$2);
        },
        onPanStart: (details) {
          final p = geometry.pointAt(details.localPosition, _size);
          if (p == null) return;
          onDrag(p.$1, p.$2);
        },
        onPanUpdate: (details) {
          final p = geometry.pointAt(details.localPosition, _size);
          if (p == null) return;
          onDrag(p.$1, p.$2);
        },
        child: CustomPaint(
          size: Size.square(side),
          painter: _BoardPainter(
            moves: moves,
            selected: selected,
            hints: hints,
            geometry: geometry,
          ),
        ),
      );
    });
  }
}

class _BoardGeometry {
  _BoardGeometry(double side, int size)
      : margin = side * 0.06,
        cell = (side - side * 0.12) / (size - 1);

  final double margin;
  final double cell;

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
    required this.moves,
    required this.selected,
    required this.hints,
    required this.geometry,
  });

  final List<Move> moves;
  final (int, int)? selected;
  final List<JosekiMoveHint> hints;
  final _BoardGeometry geometry;

  @override
  void paint(Canvas canvas, Size size) {
    final n = _size;
    final margin = geometry.margin;
    final cell = geometry.cell;
    final edge = margin + (n - 1) * cell;

    // 底色
    final bg = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: const [Color(0xFFEBCFA1), Color(0xFFDCB07D)],
      ).createShader(Offset.zero & size);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(10)),
      bg,
    );

    // 网格
    final line = Paint()
      ..color = const Color(0xFF7A4B28).withValues(alpha: 0.75)
      ..strokeWidth = math.max(0.7, cell * 0.04);
    for (var i = 0; i < n; i++) {
      final p = margin + i * cell;
      canvas.drawLine(Offset(p, margin), Offset(p, edge), line);
      canvas.drawLine(Offset(margin, p), Offset(edge, p), line);
    }

    // 星位
    final star = Paint()..color = const Color(0xFF7A4B28);
    for (final (r, c) in GoBoard.starPoints(n)) {
      canvas.drawCircle(
          Offset(margin + c * cell, margin + r * cell), cell * 0.1, star);
    }

    // 棋子
    for (var i = 0; i < moves.length; i++) {
      final m = moves[i];
      if (m.isPass || m.row == null || m.col == null) continue;
      final center = Offset(
          margin + m.col! * cell, margin + m.row! * cell);
      _stone(canvas, m.color, center, cell);
      if (i == moves.length - 1) {
        final marker = m.color == PlayerColor.black
            ? Colors.white70
            : GoColors.pineDark;
        canvas.drawCircle(center, cell * 0.15, Paint()..color = marker);
      }
    }

    // 概率推荐点（松柏青，透明度随概率加深）
    var idx = 0;
    for (final h in hints) {
      final (r, c) = GoBoard.coordFromSgf(h.coord);
      final (br, bc) = JosekiCoords.fromTr((r, c), cornerOf(moves), n);
      final center = Offset(margin + bc * cell, margin + br * cell);
      final alpha = (0.30 + 0.55 * h.probability).clamp(0.30, 0.90);
      canvas.drawCircle(
        center,
        cell * 0.46,
        Paint()..color = GoColors.pine.withValues(alpha: alpha),
      );
      // 白色序号，便于区分。
      if (idx < 4) {
        final label = _numberPainter('${idx + 1}', cell * 0.22);
        label.paint(
          canvas,
          Offset(center.dx - label.width / 2, center.dy - label.height / 2),
        );
      }
      idx++;
    }

    // 选中 ghost（两步落子第一步）
    if (selected != null) {
      final center = Offset(
          margin + selected!.$2 * cell, margin + selected!.$1 * cell);
      canvas.drawCircle(
        center,
        cell * 0.44,
        Paint()..color = Colors.black.withValues(alpha: 0.30),
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
          center, cell * 0.12, Paint()..color = GoColors.woodDark);
    }

    // 坐标
    final style = const TextStyle(
        color: GoColors.woodDark, fontSize: 10, fontWeight: FontWeight.w600);
    for (var i = 0; i < n; i++) {
      final num = TextPainter(
        text: TextSpan(text: '${i + 1}', style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      num.paint(
          canvas, Offset(margin * 0.35, margin + i * cell - num.height / 2));

      final letter = TextPainter(
        text: TextSpan(text: GoBoard.letters[i], style: style.copyWith(fontSize: 9)),
        textDirection: TextDirection.ltr,
      )..layout();
      letter.paint(
        canvas,
        Offset(margin + i * cell - letter.width / 2, edge + margin * 0.5),
      );
    }
  }

  /// 当前展开角：取首手所属角；无子时默认右上角。
  String cornerOf(List<Move> moves) {
    if (moves.isEmpty) return 'TR';
    return JosekiCoords.cornerOf(moves.first.row!, moves.first.col!, _size) ??
        'TR';
  }

  TextPainter _numberPainter(String text, double fontSize) {
    return TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: Colors.white,
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
  }

  void _stone(Canvas canvas, PlayerColor color, Offset center, double cell) {
    final radius = cell * 0.46;
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

  @override
  bool shouldRepaint(_BoardPainter old) =>
      old.moves != moves ||
      old.selected != selected ||
      old.hints != hints ||
      old.geometry != geometry;
}
