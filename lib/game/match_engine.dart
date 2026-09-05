import 'dart:math' as math;

import 'package:miaogo/core/board.dart';
import 'package:miaogo/core/move.dart';
import 'package:miaogo/core/rank.dart';
import 'package:miaogo/core/rules.dart';
import 'package:miaogo/engine/analysis.dart';
import 'package:miaogo/engine/difficulty.dart';
import 'package:miaogo/engine/katago_engine.dart';
import 'package:miaogo/game/move_provider.dart';

/// KataGo 驱动的 [MoveProvider]：引擎搜索 + 低段位选点容错采样。
///
/// 双模型（P3）：按对手段位自动选型——rankIndex < 18（18级~1级）用小模型
/// b6c96，>= 18（1段~9段）用大模型 b18c384。
///
/// - 用 `kata-search_analyze` 拿 top-N 候选，按难度温度加权采样（§7 选点容错）；
///   温度高/段位低时容易抽中次优乃至再次优，制造漏招。
/// - 采样结果用 [GoBoard] 二次合法性校验（引擎不含劫禁历史），非法则重采样。
/// - 引擎异常直接上抛（[GtpEngineException]），由对局层负责重启/中止，不做降级。
class KataGoMoveProvider implements MoveProvider {
  KataGoMoveProvider({
    required this.kyuEngine,
    required this.danEngine,
    math.Random? random,
    GoRule rule = GoRule.chinese,
    double komi = 7.5,
  })  : _random = random ?? math.Random(),
        _rule = rule,
        _komi = komi;

  /// 小模型引擎（级位对弈）。
  final KataGoEngine kyuEngine;

  /// 大模型引擎（段位对弈）；未就绪时为 null（由 UI 按难度拦截）。
  final KataGoEngine? danEngine;

  final math.Random _random;

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

  /// 按段位选型（AGENTS.md §6：index 0..17 = 18级~1级，18..26 = 1段~9段）。
  KataGoEngine engineFor(int rankIndex) {
    if (rankIndex >= RankSystem.kNumKyuRanks) {
      final dan = danEngine;
      if (dan == null) {
        throw const GtpEngineException('大模型（b18c384）未就绪，无法进行段位对弈');
      }
      return dan;
    }
    return kyuEngine;
  }

  /// 对局中切换规则：同步两个引擎的规则与贴目。
  Future<void> updateRule(GoRule rule, double komi) async {
    _rule = rule;
    _komi = komi;
    await kyuEngine.updateRules(rule, komi);
    final dan = danEngine;
    if (dan != null) await dan.updateRules(rule, komi);
  }

  @override
  Future<Move> chooseMove(GoBoard board, PlayerColor toMove,
      {required int rankIndex}) async {
    final diff = DifficultyTable.forRank(rankIndex);
    final engine = engineFor(rankIndex);
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
    return _sampleMove(
      board: board,
      toMove: toMove,
      update: result.update,
      chosen: result.chosen,
      difficulty: diff,
    );
  }

  /// 从分析候选里按温度加权采样；无有效候选时回退引擎自选/PASS。
  Move _sampleMove({
    required GoBoard board,
    required PlayerColor toMove,
    required AnalysisUpdate? update,
    required String? chosen,
    required EngineDifficulty difficulty,
  }) {
    final candidates = _legalCandidates(board, toMove, update);
    if (candidates.isEmpty) {
      // 无可用候选：回退引擎自选着法。
      return _moveFromVertex(chosen, toMove, board) ?? Move.pass(toMove);
    }
    if (difficulty.topK <= 1 || difficulty.temperature <= 0.05) {
      // 高段位：取最优。
      return candidates.first.move;
    }

    final topK = math.min(difficulty.topK, candidates.length);
    final pool = candidates.sublist(0, topK);
    // 权重 = exp(-order / temperature)：温度越高越趋于均匀随机。
    final weights = [
      for (final m in pool) math.exp(-m.analysis.order / difficulty.temperature)
    ];
    return _weightedPick(pool, weights);
  }

  /// 按 order 排序、去对称重复、过滤本棋盘合法点的候选。
  List<({MoveAnalysis analysis, Move move})> _legalCandidates(
      GoBoard board, PlayerColor toMove, AnalysisUpdate? update) {
    if (update == null) return const [];
    final seen = <String>{};
    final out = <({MoveAnalysis analysis, Move move})>[];
    for (final a in update.orderedMoves) {
      final key = a.isSymmetryOf ?? a.move;
      if (!seen.add(key)) continue; // 对称候选合并
      final v = coordFromGtp(a.move);
      if (v == null) continue; // pass 不作为采样候选（引擎自身会判断）
      final (r, c) = v;
      if (!board.inBounds(r, c) || !board.isLegal(toMove, r, c)) continue;
      out.add((analysis: a, move: Move.point(toMove, r, c)));
    }
    return out;
  }

  Move? _moveFromVertex(String? vertex, PlayerColor color, GoBoard board) {
    if (vertex == null) return null;
    final v = coordFromGtp(vertex);
    if (v == null) return Move.pass(color);
    final (r, c) = v;
    if (board.inBounds(r, c) && board.isLegal(color, r, c)) {
      return Move.point(color, r, c);
    }
    return null;
  }

  Move _weightedPick(
      List<({MoveAnalysis analysis, Move move})> pool, List<double> weights) {
    var total = 0.0;
    for (final w in weights) {
      total += w;
    }
    var r = _random.nextDouble() * total;
    for (var i = 0; i < pool.length; i++) {
      r -= weights[i];
      if (r <= 0) return pool[i].move;
    }
    return pool.last.move;
  }
}
