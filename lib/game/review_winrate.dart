import 'package:miaogo/core/board.dart';
import 'package:miaogo/core/move.dart';
import 'package:miaogo/core/rules.dart';
import 'package:miaogo/core/sgf.dart';
import 'package:miaogo/engine/analysis.dart';

/// 单局面胜率评估器（生产为 KataGo 低预算搜索，测试注入脚本）。
///
/// 返回 [toMove] 视角的胜率 0..1（无结果返回 null）。
typedef ReviewWinrateEval = Future<double?> Function(
    GoBoard board, PlayerColor toMove);

/// 回看页「胜率曲线」逐手计算任务。
///
/// 与快速对弈的数据源（对局中 AI 搜索回调实时采集）不同：
/// 这里在进入回看后按需从开局把每一手主链局面重放出来，逐手低预算
/// 评估并折算成黑方胜率（0..1），可断点续算、可取消。
class ReviewWinrateTask {
  ReviewWinrateTask({
    required this.game,
    required this.rule,
    required this.komi,
    required this.eval,
  }) {
    _appliedAt = _precompute(game);
  }

  final SgfGame game;
  final GoRule rule;
  final double komi;
  final ReviewWinrateEval eval;

  /// 主链实际可应用棋步（跳过注释节点/非法重放），下标从 0 起。
  late final List<Move> _moves;

  /// 主链节点下标 → 已应用棋步数（`_appliedAt[i]` = 节点 i 处的落子数）。
  late final List<int> _appliedAt;

  /// 黑方胜率采样：手数 → 黑方胜率 0..1。
  final Map<int, double> _winrate = {};

  /// 已成功评估到的最高手数（-1 = 尚未评估）。
  int _doneHands = -1;
  bool _cancelled = false;

  /// 已算出的黑方胜率（手数升序），可反复读取。
  Map<int, double> get results => Map.unmodifiable(_winrate);

  /// 是否已被 [cancel] 中止。
  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;

  List<int> _precompute(SgfGame game) {
    final size = game.size ?? 19;
    final board = GoBoard(size: size, superko: false);
    for (final (r, c) in game.setupBlack) {
      if (board.inBounds(r, c)) board.setStone(r, c, PlayerColor.black);
    }
    for (final (r, c) in game.setupWhite) {
      if (board.inBounds(r, c)) board.setStone(r, c, PlayerColor.white);
    }
    for (final (r, c) in game.setupEmpty) {
      if (board.inBounds(r, c)) board.clearPoint(r, c);
    }
    final moves = <Move>[];
    final appliedAt = <int>[0];
    for (var i = 1; i < game.mainline.length; i++) {
      final m = game.mainline[i].move;
      if (m == null) {
        appliedAt.add(moves.length);
        continue;
      }
      if (m.isPass) {
        moves.add(m);
      } else if (board.play(m.color, m.row!, m.col!)) {
        moves.add(m);
      }
      appliedAt.add(moves.length);
    }
    _moves = moves;
    return appliedAt;
  }

  /// 计算到主链节点 [mainlineIndex]（含）为止每手黑方胜率。
  ///
  /// 已算过的部分自动跳过；引擎/评估异常或中途取消返回 false，
  /// 未完成的手数不会写入 [results]。
  Future<bool> runTo(
    int mainlineIndex, {
    void Function(int done, int total)? onProgress,
  }) async {
    final nodeIdx = mainlineIndex.clamp(0, _appliedAt.length - 1);
    final want = _appliedAt[nodeIdx];
    final size = game.size ?? 19;
    final board = GoBoard(size: size, superko: false);
    for (final (r, c) in game.setupBlack) {
      if (board.inBounds(r, c)) board.setStone(r, c, PlayerColor.black);
    }
    for (final (r, c) in game.setupWhite) {
      if (board.inBounds(r, c)) board.setStone(r, c, PlayerColor.white);
    }
    for (final (r, c) in game.setupEmpty) {
      if (board.inBounds(r, c)) board.clearPoint(r, c);
    }
    for (var h = 0; h <= want; h++) {
      if (h > _doneHands) {
        if (_cancelled) return false;
        final toMove = h == 0
            ? PlayerColor.black
            : _moves[h - 1].color.opposite;
        final double? raw;
        try {
          raw = await eval(board.clone(superko: false), toMove);
        } catch (_) {
          return false;
        }
        if (raw == null) return false;
        _winrate[h] = blackPerspectiveWinrate(raw, toMove);
        _doneHands = h;
        onProgress?.call(h, want);
      }
      if (h == want) break;
      final m = _moves[h];
      if (!m.isPass) board.play(m.color, m.row!, m.col!);
    }
    return true;
  }
}
