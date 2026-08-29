import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:miaogo/app_theme.dart';
import 'package:miaogo/core/sgf.dart';
import 'package:miaogo/study/lesson_data.dart';
import 'package:miaogo/ui/record/review_page.dart';

/// 定式布局：条目列表 → 复盘页逐步讲解。
class JosekiListPage extends ConsumerWidget {
  const JosekiListPage({super.key});

  Future<void> _open(BuildContext context, JosekiEntry entry) async {
    try {
      final data = await rootBundle.loadString(entry.asset);
      final game = Sgf.parse(data);
      if (!context.mounted) return;
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ReviewPage(game: game, title: entry.title),
      ));
    } on Exception {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('定式内容加载失败')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('定式布局')),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: kJosekiEntries.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final entry = kJosekiEntries[i];
          return Card(
            elevation: 0,
            color: theme.colorScheme.surfaceContainerHighest,
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: CircleAvatar(
                radius: 24,
                backgroundColor: GoColors.woodContainer,
                child: const Icon(Icons.stacked_line_chart, color: GoColors.wood),
              ),
              title: Text(
                entry.title,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(entry.subtitle, style: theme.textTheme.bodySmall),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _open(context, entry),
            ),
          );
        },
      ),
    );
  }
}
