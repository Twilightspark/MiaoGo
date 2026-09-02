import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:miaogo/storage/problem_store.dart';
import 'package:miaogo/study/problem_engine.dart';

/// 每日一题数量。
const int kDailyProblemCount = 5;

/// 以日期为确定性种子，从题库取每日 [kDailyProblemCount] 题。
///
/// 同一日期内每次读取结果一致（稳定性），跨日自动更换。
final dailyProblemsProvider =
    FutureProvider<List<Problem>>((ref) async {
  final lib = await ref.watch(problemLibraryProvider.future);
  final all = lib.problems;
  if (all.isEmpty) return const [];
  final seed = _dateSeed(DateTime.now());
  final rng = math.Random(seed);
  final count = math.min(kDailyProblemCount, all.length);
  // 洗牌取前 count 题（保留题库原有顺序之外的确定性随机序）。
  final shuffled = [...all];
  for (var i = shuffled.length - 1; i > 0; i--) {
    final j = rng.nextInt(i + 1);
    final tmp = shuffled[i];
    shuffled[i] = shuffled[j];
    shuffled[j] = tmp;
  }
  return shuffled.take(count).toList();
});

/// 今日每日一题进度：`(solved, total)`。
///
/// 由 [dailyProblemsProvider] 结合题目完成状态推导；供首页与断言使用。
final todayDailyProgressProvider =
    Provider<({int solved, int total})>((ref) {
  final daily = ref.watch(dailyProblemsProvider).value ?? const <Problem>[];
  final progress = ref.watch(problemStoreProvider);
  final solved = daily.where((p) => progress[p.id]?.solved ?? false).length;
  return (solved: solved, total: daily.length);
});

int _dateSeed(DateTime d) => d.year * 1000000 + d.month * 1000 + d.day;
