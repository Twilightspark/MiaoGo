import 'dart:math' as math;

import 'package:miaogo/core/rank.dart';
import 'package:miaogo/storage/problem_store.dart';
import 'package:miaogo/study/problem_engine.dart';

/// 每日一题每轮数量。
const int kDailyProblemCount = 5;

/// 难度权重（顺序：入门 / 中级 / 高级），按用户段位分档。
///
/// - 18级~10级（rankIndex 0..8）：基础为主，少量中级。
/// - 9级~1级（rankIndex 9..17）：中级为主，基础与高级各少量。
/// - 1段~9段（rankIndex 18..26）：高级为主，中级与基础各少量。
const List<int> _lowKyuWeights = [95, 5, 0];
const List<int> _midKyuWeights = [30, 55, 5];
const List<int> _danWeights = [5, 30, 55];

List<int> _difficultyWeights(int rankIndex) {
  if (rankIndex < 9) return _lowKyuWeights;
  if (rankIndex < RankSystem.kNumKyuRanks) return _midKyuWeights;
  return _danWeights;
}

/// 按日期 + 段位 + 轮次确定性地生成一轮题目 id 列表。
///
/// 难度分布由用户段位决定（见 [_difficultyWeights]）；同一难度内优先抽
/// **未做过**的题，其次是**做错过的题**，最后才是**做过且已解出**的题。
/// [excludeIds] 用于「再来一组」避开上一组已出过的题。
List<String> selectDailyProblemIds({
  required List<Problem> library,
  required int rankIndex,
  required Map<String, ProblemStatus> progress,
  required DateTime now,
  int count = kDailyProblemCount,
  int round = 1,
  Set<String> excludeIds = const {},
}) {
  if (library.isEmpty) return const [];
  var pool = [
    for (final p in library)
      if (!excludeIds.contains(p.id)) p,
  ];
  if (pool.isEmpty) pool = library;
  final rng = math.Random(
      _dateSeed(now) ^ (rankIndex * 0x9E3779B1) ^ (round * 0x85EBCA6B));
  final weights = _difficultyWeights(rankIndex);
  final byDifficulty = <ProblemDifficulty, List<Problem>>{
    for (final d in ProblemDifficulty.values)
      d: [for (final p in pool) if (p.difficulty == d) p],
  };

  final selected = <String>{};
  final result = <String>[];
  for (var slot = 0; slot < count; slot++) {
    final target = _weightedDifficulty(rng, weights);
    final difficulty = _hasAvailable(byDifficulty[target]!, selected)
        ? target
        : _bestAvailableDifficulty(weights, byDifficulty, selected);
    if (difficulty == null) break;
    final problem =
        _pickByPriority(rng, byDifficulty[difficulty]!, progress, selected);
    if (problem == null) break;
    result.add(problem.id);
    selected.add(problem.id);
  }
  return result;
}

/// 生成一轮题目对象列表（顺序即出题顺序，缺失的 id 自动忽略）。
List<Problem> selectDailyProblems({
  required List<Problem> library,
  required int rankIndex,
  required Map<String, ProblemStatus> progress,
  required DateTime now,
  int count = kDailyProblemCount,
  int round = 1,
  Set<String> excludeIds = const {},
}) {
  final ids = selectDailyProblemIds(
    library: library,
    rankIndex: rankIndex,
    progress: progress,
    now: now,
    count: count,
    round: round,
    excludeIds: excludeIds,
  );
  final byId = {for (final p in library) p.id: p};
  return [
    for (final id in ids)
      if (byId.containsKey(id)) byId[id]!,
  ];
}

ProblemDifficulty _weightedDifficulty(math.Random rng, List<int> weights) {
  final total = weights.fold<int>(0, (a, b) => a + b);
  if (total <= 0) return ProblemDifficulty.beginner;
  var r = rng.nextInt(total);
  for (var i = 0; i < weights.length; i++) {
    r -= weights[i];
    if (r < 0) return ProblemDifficulty.values[i];
  }
  return ProblemDifficulty.values.last;
}

bool _hasAvailable(List<Problem> pool, Set<String> selected) =>
    pool.any((p) => !selected.contains(p.id));

/// 目标难度已抽空时，退回到仍有题且权重最高的难度。
ProblemDifficulty? _bestAvailableDifficulty(
  List<int> weights,
  Map<ProblemDifficulty, List<Problem>> byDifficulty,
  Set<String> selected,
) {
  ProblemDifficulty? best;
  var bestWeight = -1;
  for (var i = 0; i < ProblemDifficulty.values.length; i++) {
    final d = ProblemDifficulty.values[i];
    if (_hasAvailable(byDifficulty[d]!, selected) && weights[i] > bestWeight) {
      bestWeight = weights[i];
      best = d;
    }
  }
  return best;
}

/// 优先级：未做过 > 做错过（未解出）> 已解出。
Problem? _pickByPriority(
  math.Random rng,
  List<Problem> pool,
  Map<String, ProblemStatus> progress,
  Set<String> selected,
) {
  final unseen = <Problem>[];
  final wrong = <Problem>[];
  final solved = <Problem>[];
  for (final p in pool) {
    if (selected.contains(p.id)) continue;
    final st = progress[p.id];
    if (st == null || (st.attempts == 0 && !st.solved)) {
      unseen.add(p);
    } else if (!st.solved) {
      wrong.add(p);
    } else {
      solved.add(p);
    }
  }
  for (final tier in [unseen, wrong, solved]) {
    if (tier.isNotEmpty) return tier[rng.nextInt(tier.length)];
  }
  return null;
}

int _dateSeed(DateTime d) => d.year * 1000000 + d.month * 1000 + d.day;
