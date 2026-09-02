import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:miaogo/app_theme.dart';
import 'package:miaogo/storage/problem_store.dart';
import 'package:miaogo/study/daily_problems.dart';
import 'package:miaogo/study/problem_engine.dart';
import 'package:miaogo/ui/study/problem_page.dart';

/// 每日一题会话页：列出今日 [kDailyProblemCount] 题及其完成状态，
/// 点击任意一题进入答题页；全部解出则显示「今日打卡完成」。
class DailySessionPage extends ConsumerWidget {
  const DailySessionPage({super.key});

  Future<void> _open(BuildContext context, Problem problem) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ProblemPage(problem: problem),
    ));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final daily = ref.watch(dailyProblemsProvider);
    final progress = ref.watch(problemStoreProvider);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('每日一题')),
      body: daily.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('每日一题加载失败：$e')),
        data: (problems) {
          if (problems.isEmpty) {
            return Center(
              child: Text('暂无题库',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: GoColors.textSecondary)),
            );
          }
          final solvedCount =
              problems.where((p) => progress[p.id]?.solved ?? false).length;
          final allDone = solvedCount >= problems.length;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Row(
                  children: [
                    Text(
                      '今日 ${problems.length} 题 · 已解 $solvedCount',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: GoColors.textSecondary),
                    ),
                    const Spacer(),
                    Text(
                      '$solvedCount/${problems.length}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: GoColors.pine,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: LinearProgressIndicator(
                  value: solvedCount / problems.length,
                  minHeight: 4,
                  borderRadius: const BorderRadius.all(Radius.circular(4)),
                ),
              ),
              if (allDone) ...[
                const SizedBox(height: 12),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.emoji_events, color: GoColors.wood, size: 20),
                    SizedBox(width: 8),
                    Text('今日打卡完成'),
                  ],
                ),
              ],
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  itemCount: problems.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final p = problems[i];
                    final solved = progress[p.id]?.solved ?? false;
                    return Card(
                      elevation: 0,
                      color: theme.colorScheme.surfaceContainerHighest,
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 4),
                        leading: Icon(
                          solved
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          color: solved
                              ? GoColors.pine
                              : theme.colorScheme.outline,
                        ),
                        title: Text(p.title, style: theme.textTheme.bodyMedium),
                        subtitle: Text(
                          p.prompt.split('\n').first,
                          style: theme.textTheme.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: const Icon(Icons.chevron_right, size: 18),
                        onTap: () => _open(context, p),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
