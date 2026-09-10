import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:miaogo/app_theme.dart';
import 'package:miaogo/storage/checkin_store.dart';
import 'package:miaogo/storage/problem_store.dart';
import 'package:miaogo/study/daily_problems.dart';
import 'package:miaogo/study/problem_engine.dart';
import 'package:miaogo/ui/study/problem_solve_view.dart';

/// 每日打卡页：逐题作答今日 [kDailyProblemCount] 题。
///
/// 顶栏标题 + 返回；顶部进度卡展示今日进度；下方为通用作答视图（提示卡、轮次信息、
/// 自动放大的棋盘、反馈与底部操作）。看正解时改为「下一步」逐步演示正解。全部解出后
/// 弹窗祝贺打卡成功。落子方式遵循设置中的「确认落子 / 双击落子」。
class DailySessionPage extends ConsumerStatefulWidget {
  const DailySessionPage({super.key});

  @override
  ConsumerState<DailySessionPage> createState() => _DailySessionPageState();
}

class _DailySessionPageState extends ConsumerState<DailySessionPage> {
  int _index = 0;
  bool _completionShown = false;

  /// 本轮全部做完：弹窗提示（首轮「今日打卡完成」/ 后续「补充功课完成」）并退出回首页。
  Future<void> _showCompleteDialog() async {
    final daily = ref.read(dailyStoreProvider);
    final first = daily.round == 1 && !daily.firstCompleted;
    if (first) {
      ref.read(dailyStoreProvider.notifier).markFirstCompleted();
      ref.read(checkinStoreProvider.notifier).markToday();
    }
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.emoji_events, color: GoColors.wood, size: 40),
        title: Text(first ? '今日打卡完成' : '补充功课完成'),
        content: Text(
          first ? '恭喜完成今日全部题目，坚持就是胜利！' : '恭喜完成补充功课，继续保持！',
        ),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              if (mounted) Navigator.of(context).maybePop();
            },
            child: const Text('退出'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final daily = ref.watch(dailyProblemsProvider);
    final progress = ref.watch(problemStoreProvider);
    final dailyAttempts =
        ref.watch(dailyStoreProvider.select((s) => s.attempts));

    ref.listen<({int done, int total, bool complete})>(
        dailyRoundProgressProvider, (prev, next) {
      if (next.complete && !(prev?.complete ?? false) && !_completionShown) {
        _completionShown = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _showCompleteDialog();
        });
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('每日打卡')),
      body: SafeArea(
        child: daily.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('每日一题加载失败：$e')),
          data: (problems) {
            if (problems.isEmpty) {
              return const Center(child: Text('暂无题库'));
            }
            final index = _index.clamp(0, problems.length - 1);
            final dailyState = ref.read(dailyStoreProvider);
            return ProblemSolveView(
              problems: problems,
              index: index,
              onIndexChanged: (i) => setState(() => _index = i),
              restoreProgress: (p) =>
                  (dailyState.stepIndex[p.id] ?? 0, dailyState.attempts[p.id] ?? 0),
              onProgress: (p, step, attempts) => ref
                  .read(dailyStoreProvider.notifier)
                  .recordProgress(p.id, stepIndex: step, attempts: attempts),
              headerBuilder: (context, index, total) => _ProgressCard(
                done: problems.where((p) {
                  final solved = progress[p.id]?.solved ?? false;
                  return solved ||
                      (dailyAttempts[p.id] ?? 0) >= kMaxProblemAttempts;
                }).length,
                total: total,
                problems: problems,
                progress: progress,
                attempts: dailyAttempts,
                currentIndex: index,
                onSelect: (i) => setState(() => _index = i),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// 顶部进度卡：今日进度条 + 每题完成/易错标记。
class _ProgressCard extends StatelessWidget {
  const _ProgressCard({
    required this.done,
    required this.total,
    required this.problems,
    required this.progress,
    required this.attempts,
    required this.currentIndex,
    required this.onSelect,
  });

  final int done;
  final int total;
  final List<Problem> problems;
  final Map<String, ProblemStatus> progress;

  /// 本轮各题已用错误次数。
  final Map<String, int> attempts;
  final int currentIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ratio = total == 0 ? 0.0 : done / total;
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: theme.colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '今日做题进度',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Text(
                  '$done / $total',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: GoColors.pine,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 6,
                backgroundColor: theme.colorScheme.outlineVariant,
                valueColor: const AlwaysStoppedAnimation<Color>(GoColors.pine),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                for (var i = 0; i < problems.length; i++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: _ProblemDot(
                        number: i + 1,
                        solved: progress[problems[i].id]?.solved ?? false,
                        wrongAttempts: attempts[problems[i].id] ?? 0,
                        current: i == currentIndex,
                        onTap: () => onSelect(i),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 单题标记：做对（浅绿底）/ 用满错误机会判错（浅红底）/ 未判错（无底），统一显示题号。
class _ProblemDot extends StatelessWidget {
  const _ProblemDot({
    required this.number,
    required this.solved,
    required this.wrongAttempts,
    required this.current,
    required this.onTap,
  });

  final int number;
  final bool solved;
  final int wrongAttempts;
  final bool current;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 仅当用满三次错误机会才判为做错。
    final wrong = !solved && wrongAttempts >= kMaxProblemAttempts;

    final Color background;
    final Color foreground;
    if (solved) {
      background = GoColors.pineContainer;
      foreground = GoColors.onPineContainer;
    } else if (wrong) {
      background = theme.colorScheme.error.withValues(alpha: 0.14);
      foreground = theme.colorScheme.error;
    } else {
      background = Colors.transparent;
      foreground = GoColors.textSecondary;
    }

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        height: 34,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: current ? GoColors.pine : theme.colorScheme.outlineVariant,
            width: current ? 2 : 1,
          ),
        ),
        child: Center(
          child: Text(
            '$number',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: foreground,
              fontWeight:
                  solved || wrong || current ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}
