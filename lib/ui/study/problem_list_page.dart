import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:miaogo/app_theme.dart';
import 'package:miaogo/storage/problem_store.dart';
import 'package:miaogo/study/problem_engine.dart';
import 'package:miaogo/ui/study/problem_category_page.dart';

/// 死活题首页：三栏难度，点击进入对应难度的题目列表。
class ProblemListPage extends ConsumerWidget {
  const ProblemListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(problemLibraryProvider);
    final progress = ref.watch(problemStoreProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('死活题')),
      body: SafeArea(
        child: library.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => _ErrorPlaceholder(message: '$e'),
          data: (lib) => Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final difficulty in ProblemDifficulty.values) ...[
                  if (difficulty != ProblemDifficulty.values.first)
                    const SizedBox(width: 12),
                  Expanded(
                    child: _DifficultyColumn(
                      difficulty: difficulty,
                      solved: lib
                          .byDifficulty(difficulty)
                          .where((p) => progress[p.id]?.solved ?? false)
                          .length,
                      total: lib.byDifficulty(difficulty).length,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              ProblemCategoryPage(difficulty: difficulty),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 单栏难度：竖排卡片，展示难度名与已解进度。
class _DifficultyColumn extends StatelessWidget {
  const _DifficultyColumn({
    required this.difficulty,
    required this.solved,
    required this.total,
    required this.onTap,
  });

  final ProblemDifficulty difficulty;
  final int solved;
  final int total;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = switch (difficulty) {
      ProblemDifficulty.beginner => GoColors.pine,
      ProblemDifficulty.intermediate => GoColors.wood,
      ProblemDifficulty.advanced => GoColors.woodDark,
    };
    final ratio = total == 0 ? 0.0 : solved / total;
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: theme.colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(height: 12),
              Text(
                difficulty.label,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '共 $total 题',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: GoColors.textSecondary),
              ),
              const Spacer(),
              Text(
                '$solved',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              Text(
                '已解',
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: GoColors.textSecondary),
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: ratio,
                  minHeight: 6,
                  backgroundColor: theme.colorScheme.outlineVariant,
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
              ),
            ],
          ),
        ),
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
