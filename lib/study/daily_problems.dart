import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:miaogo/core/rank.dart';
import 'package:miaogo/storage/problem_store.dart';
import 'package:miaogo/storage/user_store.dart';
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
/// [excludeIds] 用于同一自然日内后续轮次避开已出过的题。
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

/// 当前一轮每日一题进度：`(done, total, complete)`。
///
/// 一题「做对」或用满 [kMaxProblemAttempts] 次错误机会判错即计入完成；
/// 全部完成即本轮完成。
final dailyRoundProgressProvider =
    Provider<({int done, int total, bool complete})>((ref) {
  final daily = ref.watch(dailyProblemsProvider).value ?? const <Problem>[];
  final progress = ref.watch(problemStoreProvider);
  final attempts = ref.watch(dailyStoreProvider.select((s) => s.attempts));
  var done = 0;
  for (final p in daily) {
    final solved = progress[p.id]?.solved ?? false;
    if (solved || (attempts[p.id] ?? 0) >= kMaxProblemAttempts) done++;
  }
  final total = daily.length;
  return (done: done, total: total, complete: total > 0 && done >= total);
});

/// 每日一题轮次状态：当前轮题目、轮次、是否完成首轮、当日已出题、续做进度。
class DailyState {
  const DailyState({
    required this.dateKey,
    required this.round,
    required this.problemIds,
    required this.firstCompleted,
    required this.usedIds,
    required this.stepIndex,
    required this.attempts,
  });

  const DailyState.empty()
      : dateKey = '',
        round = 0,
        problemIds = const <String>[],
        firstCompleted = false,
        usedIds = const <String>{},
        stepIndex = const <String, int>{},
        attempts = const <String, int>{};

  final String dateKey;

  /// 当前轮次（1 起；0 表示今日尚未开始）。
  final int round;
  final List<String> problemIds;

  /// 今日首轮是否已完成（用于区分「今日打卡完成 / 补充功课完成」）。
  final bool firstCompleted;

  /// 今日已出过的题目 id（跨轮去重）。
  final Set<String> usedIds;

  /// 进行中的主线进度（题 id → 主线节点下标），用于续做恢复。
  final Map<String, int> stepIndex;

  /// 本局各题错误次数，用于「看正解」门槛与续做恢复。
  final Map<String, int> attempts;

  DailyState copyWith({
    String? dateKey,
    int? round,
    List<String>? problemIds,
    bool? firstCompleted,
    Set<String>? usedIds,
    Map<String, int>? stepIndex,
    Map<String, int>? attempts,
  }) {
    return DailyState(
      dateKey: dateKey ?? this.dateKey,
      round: round ?? this.round,
      problemIds: problemIds ?? this.problemIds,
      firstCompleted: firstCompleted ?? this.firstCompleted,
      usedIds: usedIds ?? this.usedIds,
      stepIndex: stepIndex ?? this.stepIndex,
      attempts: attempts ?? this.attempts,
    );
  }

  Map<String, dynamic> toJson() => {
        'dateKey': dateKey,
        'round': round,
        'problemIds': problemIds,
        'firstCompleted': firstCompleted,
        'usedIds': usedIds.toList(),
        'stepIndex': stepIndex,
        'attempts': attempts,
      };

  factory DailyState.fromJson(Map<String, dynamic> json) => DailyState(
        dateKey: json['dateKey'] as String? ?? '',
        round: (json['round'] as num?)?.toInt() ?? 0,
        problemIds: (json['problemIds'] as List<dynamic>? ?? const [])
            .whereType<String>()
            .toList(),
        firstCompleted: json['firstCompleted'] as bool? ?? false,
        usedIds: (json['usedIds'] as List<dynamic>? ?? const [])
            .whereType<String>()
            .toSet(),
        stepIndex: _intMap(json['stepIndex']),
        attempts: _intMap(json['attempts']),
      );
}

Map<String, int> _intMap(dynamic value) {
  if (value is Map) {
    return value.map(
        (k, v) => MapEntry(k.toString(), (v as num?)?.toInt() ?? 0));
  }
  return const <String, int>{};
}

/// 每日一题轮次状态持久化：跨启动/跨页面稳定，支持续做恢复。
class DailyStore extends Notifier<DailyState> {
  static const _key = 'daily_round';

  @override
  DailyState build() {
    final raw = ref.read(sharedPreferencesProvider).getString(_key);
    if (raw == null) return const DailyState.empty();
    try {
      return DailyState.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const DailyState.empty();
    }
  }

  /// 确保今日首轮已抽取；返回当前轮题目 id 顺序列表。
  List<String> ensureRound({
    required List<Problem> library,
    required int rankIndex,
    required Map<String, ProblemStatus> progress,
    DateTime? now,
  }) {
    final date = now ?? DateTime.now();
    final today = _dateKey(date);
    if (state.dateKey == today && state.problemIds.isNotEmpty) {
      final valid =
          state.problemIds.every((id) => library.any((p) => p.id == id));
      if (valid) return state.problemIds;
    }
    final ids = selectDailyProblemIds(
      library: library,
      rankIndex: rankIndex,
      progress: progress,
      now: date,
      round: 1,
    );
    state = DailyState(
      dateKey: today,
      round: 1,
      problemIds: ids,
      firstCompleted: false,
      usedIds: ids.toSet(),
      stepIndex: const {},
      attempts: const {},
    );
    _persist();
    return ids;
  }

  /// 开始下一轮：重新抽 [kDailyProblemCount] 题（避开今日已出过的题）。
  void startNextRound({
    required List<Problem> library,
    required int rankIndex,
    required Map<String, ProblemStatus> progress,
    DateTime? now,
  }) {
    final date = now ?? DateTime.now();
    final today = _dateKey(date);
    final base = state.dateKey == today ? state : const DailyState.empty();
    final nextRound = base.round + 1;
    final ids = selectDailyProblemIds(
      library: library,
      rankIndex: rankIndex,
      progress: progress,
      now: date,
      round: nextRound,
      excludeIds: base.usedIds,
    );
    state = DailyState(
      dateKey: today,
      round: nextRound,
      problemIds: ids,
      firstCompleted: base.firstCompleted,
      usedIds: {...base.usedIds, ...ids},
      stepIndex: const {},
      attempts: const {},
    );
    _persist();
  }

  /// 标记今日首轮已完成（用于「今日打卡完成 / 补充功课完成」区分）。
  void markFirstCompleted() {
    if (state.firstCompleted) return;
    state = state.copyWith(firstCompleted: true);
    _persist();
  }

  /// 记录某题的续做进度（主线下标 + 本局错误次数）。
  void recordProgress(
    String problemId, {
    required int stepIndex,
    required int attempts,
  }) {
    state = state.copyWith(
      stepIndex: {...state.stepIndex, problemId: stepIndex},
      attempts: {...state.attempts, problemId: attempts},
    );
    _persist();
  }

  /// 清空当日轮次（重生用）。
  void reset() {
    state = const DailyState.empty();
    _persist();
  }

  void _persist() {
    ref.read(sharedPreferencesProvider).setString(
          _key,
          jsonEncode(state.toJson()),
        );
  }
}

final dailyStoreProvider =
    NotifierProvider<DailyStore, DailyState>(DailyStore.new);

/// 当前一轮每日一题列表（顺序即出题顺序）。
final dailyProblemsProvider = FutureProvider<List<Problem>>((ref) async {
  final lib = await ref.watch(problemLibraryProvider.future);
  final all = lib.problems;
  if (all.isEmpty) return const [];
  // 仅当题目集合变化（新一轮/跨日）时重建。
  var ids = ref.watch(dailyStoreProvider.select((s) => s.problemIds));
  if (ids.isEmpty) {
    ids = ref.read(dailyStoreProvider.notifier).ensureRound(
          library: all,
          rankIndex: ref.read(userProfileProvider).rankIndex,
          progress: ref.read(problemStoreProvider),
        );
  }
  final byId = {for (final p in all) p.id: p};
  return [
    for (final id in ids)
      if (byId.containsKey(id)) byId[id]!,
  ];
});

int _dateSeed(DateTime d) => d.year * 1000000 + d.month * 1000 + d.day;

String _dateKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';
