import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:miaogo/app_theme.dart';
import 'package:miaogo/storage/problem_store.dart';
import 'package:miaogo/study/problem_engine.dart';
import 'package:miaogo/ui/study/problem_page.dart';

/// 死活题：按难度分组，显示进度与解题入口。
class ProblemListPage extends ConsumerWidget {
  const ProblemListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(problemLibraryProvider);
    final progress = ref.watch(problemStoreProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('死活题')),
      body: library.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ErrorPlaceholder(message: '$e'),
        data: (lib) {
          final totalSolved = progress.values.where((s) => s.solved).length;
          final ratio = lib.problems.isEmpty
              ? 0.0
              : totalSolved / lib.problems.length;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Row(
                  children: [
                    Text(
                      '共 ${lib.problems.length} 题 · 已解 $totalSolved',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: GoColors.textSecondary),
                    ),
                    const Spacer(),
                    Text(
                      '进度 $totalSolved/${lib.problems.length}',
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
                  value: ratio,
                  minHeight: 4,
                  borderRadius: const BorderRadius.all(Radius.circular(4)),
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  children: [
                    for (final difficulty in ProblemDifficulty.values) ...[
                      _GroupHeader(
                        difficulty: difficulty,
                        solved: lib
                            .byDifficulty(difficulty)
                            .where((p) => progress[p.id]?.solved ?? false)
                            .length,
                        total: lib.byDifficulty(difficulty).length,
                      ),
                      for (final problem in lib.byDifficulty(difficulty))
                        _ProblemTile(problem: problem, progress: progress),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    required this.difficulty,
    required this.solved,
    required this.total,
  });

  final ProblemDifficulty difficulty;
  final int solved;
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = switch (difficulty) {
      ProblemDifficulty.beginner => GoColors.pine,
      ProblemDifficulty.elementary => GoColors.pineDark,
      ProblemDifficulty.intermediate => GoColors.wood,
      ProblemDifficulty.advanced => GoColors.woodDark,
    };
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 6),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            difficulty.label,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const Spacer(),
          Text(
            '$solved / $total',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: GoColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _ProblemTile extends StatelessWidget {
  const _ProblemTile({required this.problem, required this.progress});

  final Problem problem;
  final Map<String, ProblemStatus> progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final solved = progress[problem.id]?.solved ?? false;
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Icon(
          solved ? Icons.check_circle : Icons.radio_button_unchecked,
          color: solved ? GoColors.pine : theme.colorScheme.outline,
        ),
        title: Text(problem.title, style: theme.textTheme.bodyMedium),
        subtitle: Text(
          problem.prompt.split('\n').first,
          style: theme.textTheme.bodySmall,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.chevron_right, size: 18),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ProblemPage(problem: problem),
        )),
      ),
    );
  }
}

class _ErrorPlaceholder extends StatelessWidget {
  const _ErrorPlaceholder({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: theme.colorScheme.outline),
          const SizedBox(height: 12),
          Text('题库加载失败：$message', style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}
