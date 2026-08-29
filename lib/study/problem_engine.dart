import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:miaogo/core/board.dart';
import 'package:miaogo/core/move.dart';
import 'package:miaogo/core/sgf.dart';

/// 死活题难度分级。
enum ProblemDifficulty {
  beginner('入门'),
  elementary('初级'),
  intermediate('中级'),
  advanced('高级');

  const ProblemDifficulty(this.label);
  final String label;
}

/// 答题判定结果。
enum StepOutcome { correct, wrong, alreadySolved }

/// 一道死活题：初始局面 + 正解主线 + 讲解。
///
/// 由 [ProblemLibrary.load] 从 `assets/problems/` 的 SGF 解析生成。
class Problem {
  const Problem({
    required this.id,
    required this.title,
    required this.difficulty,
    required this.asset,
    required this.boardSize,
    required this.initial,
    required this.toPlay,
    required this.prompt,
    required this.explanation,
    required this.mainline,
  });

  final String id;
  final String title;
  final ProblemDifficulty difficulty;
  final String asset;
  final int boardSize;

  /// 初始局面（布子；答题时克隆使用）。
  final GoBoard initial;

  /// 执子方（SGF `PL`，缺省取正解首步颜色，再缺省黑）。
  final PlayerColor toPlay;

  /// 题目说明（根节点 `C[]`）。
  final String prompt;

  /// 正解讲解（`C[Correct...]` 或主线末注释）。
  final String? explanation;

  /// 主变化节点链（含根节点）。
  final List<SgfNode> mainline;

  /// 主变化棋步（含防守方应手），用于正解回放。
  List<Move> get solutionMoves => [
        for (final n in mainline.skip(1))
          if (n.move != null) n.move!,
      ];

  static Problem fromGame({
    required String id,
    required String title,
    required ProblemDifficulty difficulty,
    required String asset,
    required SgfGame game,
  }) {
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
    final toPlay = game.playerToMove ?? PlayerColor.black;
    final mainline = game.mainline;

    // 讲解：优先 `C[Correct]` 节点注释，否则取主线末注释。
    String? explanation;
    for (final n in mainline.skip(1)) {
      final c = n.comment;
      if (c != null && c.toLowerCase().contains('correct')) {
        explanation = c;
        break;
      }
    }
    if (explanation == null) {
      for (final n in mainline.reversed) {
        if (n.comment != null && n.comment!.trim().isNotEmpty) {
          explanation = n.comment;
          break;
        }
      }
    }
    return Problem(
      id: id,
      title: title,
      difficulty: difficulty,
      asset: asset,
      boardSize: size,
      initial: board,
      toPlay: toPlay,
      prompt: (game.root.comment ?? '').trim(),
      explanation: explanation,
      mainline: mainline,
    );
  }
}

/// 死活题题库：解析 `assets/problems/problems.json` 索引 + 各 SGF。
class ProblemLibrary {
  ProblemLibrary(this.problems);

  final List<Problem> problems;

  List<Problem> byDifficulty(ProblemDifficulty d) =>
      problems.where((p) => p.difficulty == d).toList();

  /// 全部题库（解析失败的文件跳过）。
  static Future<ProblemLibrary> load() async {
    final indexData =
        await rootBundle.loadString('assets/problems/problems.json');
    final map = jsonDecode(indexData) as Map<String, dynamic>;
    final problems = <Problem>[];
    for (final entry in map.entries) {
      final difficulty = ProblemDifficulty.values.firstWhere(
        (d) => d.name == entry.key,
        orElse: () => ProblemDifficulty.beginner,
      );
      final files = (entry.value as List).cast<String>();
      for (var i = 0; i < files.length; i++) {
        final path = files[i];
        try {
          final data = await rootBundle.loadString('assets/problems/$path');
          final game = Sgf.parse(data);
          problems.add(Problem.fromGame(
            id: path.replaceAll('/', '-').replaceAll('.sgf', ''),
            title: '${difficulty.label} 第 ${i + 1} 题',
            difficulty: difficulty,
            asset: 'assets/problems/$path',
            game: game,
          ));
        } catch (_) {
          // 个别题目解析失败不影响题库整体。
        }
      }
    }
    return ProblemLibrary(problems);
  }
}

/// 死活题答题引擎（纯 Dart，可单测）。
///
/// 判定规则：用户着手与正解主线匹配 → 防守方按主线自动应 → 继续；
/// 偏离正解 → 记为错解（尝试次数 +1）。到达 `C[Correct]` 或主线终点即解答成功。
class ProblemSolver {
  ProblemSolver(this.problem) {
    reset();
  }

  final Problem problem;

  late GoBoard _board;
  int _index = 0;
  int attempts = 0;
  bool solved = false;

  GoBoard get board => _board;
  PlayerColor get toPlay => problem.toPlay;

  /// 下一个应行的用户手（正解主线中的下一手执子方棋步）。
  Move? get expectedMove {
    final i = _nextUserIndex;
    return i == null ? null : problem.mainline[i].move;
  }

  /// 当前主线节点之后，下一个执子方棋步的节点下标。
  int? get _nextUserIndex {
    for (var i = _index + 1; i < problem.mainline.length; i++) {
      final m = problem.mainline[i].move;
      if (m != null && m.color == toPlay) return i;
    }
    return null;
  }

  bool get _terminalCorrect {
    final c = problem.mainline[_index].comment;
    return c != null && c.toLowerCase().contains('correct');
  }

  /// 回到初始局面，重置进度。
  void reset() {
    _board = problem.initial.clone(superko: false);
    _index = 0;
    attempts = 0;
    solved = false;
  }

  /// 用户落子判定；[StepOutcome.correct] 表示与正解一致并已推进。
  StepOutcome play(int row, int col) {
    if (solved) return StepOutcome.alreadySolved;
    final i = _nextUserIndex;
    final expected = i == null ? null : problem.mainline[i].move;
    if (i == null || expected == null || expected.isPass) {
      solved = true; // 主线无更多应手，视为已完成。
      return StepOutcome.correct;
    }
    if (expected.row != row || expected.col != col) {
      attempts++;
      return StepOutcome.wrong;
    }
    // 正解主线视为谱面事实：强制落子（含打劫回提等），保证后续推进一致。
    _board.forcePlay(toPlay, row, col);
    _index = i;
    _advanceDefender();
    if (_terminalCorrect || _nextUserIndex == null) solved = true;
    return StepOutcome.correct;
  }

  /// 沿主线自动落防守方应手，直到下一个用户手或终点。
  void _advanceDefender() {
    while (_index + 1 < problem.mainline.length) {
      final next = _index + 1;
      final m = problem.mainline[next].move;
      if (m == null) {
        _index = next;
        continue;
      }
      if (m.color == toPlay) return;
      if (!m.isPass) _board.forcePlay(m.color, m.row!, m.col!);
      _index = next;
    }
  }
}

/// 题库加载（异步，解析全部资产）。
final problemLibraryProvider =
    FutureProvider<ProblemLibrary>((ref) => ProblemLibrary.load());
