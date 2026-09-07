import 'package:flutter/material.dart';
import 'package:miaogo/app_theme.dart';
import 'package:miaogo/ui/study/beginner_guide_page.dart';
import 'package:miaogo/ui/study/joseki_practice_page.dart';
import 'package:miaogo/ui/study/problem_list_page.dart';

/// 功课页：基础规则新手指引 / 定式布局 / 死活题。
class StudyHomePage extends StatelessWidget {
  const StudyHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('功课')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _StudyCard(
            icon: Icons.auto_stories,
            title: '基础规则新手指引',
            subtitle: '12 步引导式入门，边下边学',
            color: GoColors.pine,
            onTap: () => _push(context, const BeginnerGuidePage()),
          ),
          _StudyCard(
            icon: Icons.stacked_line_chart,
            title: '定式练习',
            subtitle: '落子推荐匹配定式，逐步讲解',
            color: GoColors.wood,
            onTap: () => _push(context, const JosekiPracticePage()),
          ),
          _StudyCard(
            icon: Icons.grid_on,
            title: '死活题',
            subtitle: '按难度分组，判定正解与讲解',
            color: GoColors.pineDark,
            onTap: () => _push(context, const ProblemListPage()),
          ),
        ],
      ),
    );
  }

  void _push(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }
}

class _StudyCard extends StatelessWidget {
  const _StudyCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest,
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          radius: 24,
          backgroundColor: color.withValues(alpha: 0.15),
          child: Icon(icon, color: color),
        ),
        title: Text(title,
            style:
                theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle, style: theme.textTheme.bodySmall),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
