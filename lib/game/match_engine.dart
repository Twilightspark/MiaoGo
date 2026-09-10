import 'package:miaogo/core/board.dart';
import 'package:miaogo/core/move.dart';
import 'package:miaogo/core/rules.dart';
import 'package:miaogo/engine/analysis.dart';
import 'package:miaogo/engine/difficulty.dart';
import 'package:miaogo/engine/katago_engine.dart';
import 'package:miaogo/game/move_provider.dart';

/// KataGo 驱动的 [MoveProvider]（单引擎 + Human SL）。
///
/// 按对手段位下发 Human SL 参数（`humanSLProfile` / `humanSLChosenMovePiklLambda`
/// 等，见 [DifficultyTable]），由引擎自身按该段位人类棋风选点：
/// - 级位（18级~1级）纯人类策略；
/// - 段位（1段~9段）逐步混入搜索增强棋力。
///
/// 引擎返回的 `play <move>`（含 `pass`/`resign`）即最终着法；仅在缺失时回退到
/// 分析候选中的最优合法点。引擎异常直接上抛（[GtpEngineException]），由对局层
/// 负责重启/中止，不做降级。
class KataGoMoveProvider implements MoveProvider {
  KataGoMoveProvider({
    required this.engine,
    GoRule rule = GoRule.chinese,
    double komi = 7.5,
  })  : _rule = rule,
        _komi = komi;

  /// 单引擎（b18c384 主模型 + Human SL 模型）。
  final KataGoEngine engine;

  /// 兼容旧 UI 命名：单引擎架构下两者同源。
  KataGoEngine get kyuEngine => engine;
  KataGoEngine get danEngine => engine;

  /// 每次 AI 搜索完成后的回调（侧别 = 行棋方 + 其视角胜率 0..1）。
  ///
  /// 胜率曲线复用对局中的既有搜索，无需额外评估 AI 回合那手。
  void Function(PlayerColor sideToMove, double winrate)? winrateListener;

  /// 当前规则上下文（对局中切换规则时由外部调用 [updateRule] 同步）。
  GoRule _rule;
  double _komi;

  /// 规则/贴目缓存（引擎与盘面分析共用）。
  GoRule get rule => _rule;
  double get komi => _komi;

  /// 对局中切换规则：同步引擎的规则与贴目。
  Future<void> updateRule(GoRule rule, double komi) async {
    _rule = rule;
    _komi = komi;
    await engine.updateRules(rule, komi);
  }

  @override
  Future<Move> chooseMove(GoBoard board, PlayerColor toMove,
      {required int rankIndex}) async {
    final diff = DifficultyTable.forRank(rankIndex);
    final result = await engine.searchAndAnalyze(
      board: board,
      toMove: toMove,
      rule: _rule,
      komi: _komi,
      difficulty: diff,
      ownership: false,
    );
    final winrate = bestCandidateWinrate(result.update);
    if (winrate != null) {
      winrateListener?.call(toMove, winrate);
    }
    return _selectMove(
      board: board,
      toMove: toMove,
      update: result.update,
      chosen: result.chosen,
    );
  }

  /// 引擎自选着法优先；缺失时回退分析候选中的最优合法点，最后 PASS。
  Move _selectMove({
    required GoBoard board,
    required PlayerColor toMove,
    required AnalysisUpdate? update,
    required String? chosen,
  }) {
    if (chosen != null && chosen.isNotEmpty) {
      return _chosenToMove(chosen, toMove, board);
    }
    return _bestLegalCandidate(board, toMove, update) ?? Move.pass(toMove);
  }

  /// 解析引擎 `play <vertex>`：`pass`/`resign`/坐标；非法或不可落子则 PASS。
  Move _chosenToMove(String vertex, PlayerColor color, GoBoard board) {
    final lower = vertex.toLowerCase();
    if (lower == 'pass') return Move.pass(color);
    if (lower == 'resign') return Move.resign(color);
    try {
      final v = coordFromGtp(vertex);
      if (v == null) return Move.pass(color);
      final (r, c) = v;
      if (board.inBounds(r, c) && board.isLegal(color, r, c)) {
        return Move.point(color, r, c);
      }
    } catch (_) {
      // 非法坐标：回退 PASS。
    }
    return Move.pass(color);
  }

  /// 分析候选中第一个可落子的点（`pass` 与非法点跳过）。
  Move? _bestLegalCandidate(
      GoBoard board, PlayerColor toMove, AnalysisUpdate? update) {
    if (update == null) return null;
    for (final a in update.orderedMoves) {
      try {
        final v = coordFromGtp(a.move);
        if (v == null) continue;
        final (r, c) = v;
        if (board.inBounds(r, c) && board.isLegal(toMove, r, c)) {
          return Move.point(toMove, r, c);
        }
      } catch (_) {
        continue;
      }
    }
    return null;
  }
}
