import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:miaogo/app_theme.dart';
import 'package:miaogo/storage/problem_store.dart';
import 'package:miaogo/study/problem_engine.dart';
import 'package:miaogo/ui/study/problem_solve_page.dart';

/// 题目数据类别：已做（做对）/ 错题（用满机会判错）/ 未做。
enum ProblemFilter {
  done('已做'),
  wrong('错题'),
  undone('未做');

  const ProblemFilter(this.label);
  final String label;
}

/// 某难度的死活题列表：按已做 / 错题 / 未做筛选，点击进入作答。
class ProblemCategoryPage extends ConsumerStatefulWidget {
  const ProblemCategoryPage({
    super.key,
    required this.difficulty,
    this.initialFilter = ProblemFilter.done,
  });

  final ProblemDifficulty difficulty;
  final ProblemFilter initialFilter;

  @override
  ConsumerState<ProblemCategoryPage> createState() =>
      _ProblemCategoryPageState();
}

class _ProblemCategoryPageState extends ConsumerState<ProblemCategoryPage> {
  late ProblemFilter _filter = widget.initialFilter;

  /// 某题是否属于指定数据类别。
  bool _matches(ProblemFilter filter, ProblemStatus? status) {
    final solved = status?.solved ?? false;
    final attempts = status?.attempts ?? 0;
    return switch (filter) {
      ProblemFilter.done => solved,
      ProblemFilter.wrong => !solved && attempts >= kMaxProblemAttempts,
      ProblemFilter.undone => !solved && attempts < kMaxProblemAttempts,
    };
  }

  void _open(List<Problem> problems, int index) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ProblemSolvePage(problems: problems, initialIndex: index),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final library = ref.watch(problemLibraryProvider);
    final progress = ref.watch(problemStoreProvider);

    return Scaffold(
      appBar: AppBar(title: Text('${widget.difficulty.label}死活题')),
      body: SafeArea(
        child: library.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('题库加载失败：$e')),
          data: (lib) {
            final all = lib.byDifficulty(widget.difficulty);
            final filtered =
                all.where((p) => _matches(_filter, progress[p.id])).toList();
            final counts = {
              for (final f in ProblemFilter.values)
                f: all.where((p) => _matches(f, progress[p.id])).length,
            };

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: SegmentedButton<ProblemFilter>(
                    segments: [
                      for (final f in ProblemFilter.values)
                        ButtonSegment(
                          value: f,
                          label: Text('${f.label} ${counts[f]}'),
                        ),
                    ],
                    selected: {_filter},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) =>
                        setState(() => _filter = s.first),
                  ),
                ),
                Expanded(
                  child: filtered.isEmpty
                      ? _EmptyPlaceholder(label: _filter.label)
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                          itemCount: filtered.length,
                          itemBuilder: (context, i) {
                            final problem = filtered[i];
                            return _ProblemTile(
                              problem: problem,
                              onTap: () => _open(filtered, i),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// 题目卡片（无对勾标记）：标题 + 说明，点击进入作答。
class _ProblemTile extends StatelessWidget {
  const _ProblemTile({required this.problem, required this.onTap});

  final Problem problem;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final prompt = problem.prompt.split('\n').first.trim();
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        title: Text(problem.title, style: theme.textTheme.bodyMedium),
        subtitle: prompt.isEmpty
            ? null
            : Text(
                prompt,
                style: theme.textTheme.bodySmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
        trailing: const Icon(Icons.chevron_right, size: 18),
        onTap: onTap,
      ),
    );
  }
}

class _EmptyPlaceholder extends StatelessWidget {
  const _EmptyPlaceholder({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Text(
        '暂无「$label」的题目',
        style: theme.textTheme.bodyMedium
            ?.copyWith(color: GoColors.textSecondary),
      ),
    );
  }
}
