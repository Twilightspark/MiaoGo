import 'package:flutter/material.dart';
import 'package:miaogo/app_theme.dart';
import 'package:miaogo/ui/play/ai_setup_page.dart';
import 'package:miaogo/ui/play/career_page.dart';

/// 对弈页：生涯模式 / 人机模式入口。
class PlayHomePage extends StatelessWidget {
  const PlayHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('对弈')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _ModeCard(
            icon: Icons.emoji_events,
            title: '生涯模式',
            subtitle: '报名随机生成的段位大赛，按大赛积分升降级',
            color: GoColors.wood,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const CareerPage()),
            ),
          ),
          const SizedBox(height: 12),
          _ModeCard(
            icon: Icons.person,
            title: '人机模式',
            subtitle: '自由选择对手棋力、尺寸与规则对弈（不计分）',
            color: GoColors.pine,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const AISetupPage()),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
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
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        leading: CircleAvatar(
          radius: 24,
          backgroundColor: color.withValues(alpha: 0.15),
          child: Icon(icon, color: color),
        ),
        title: Text(title,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle, style: theme.textTheme.bodySmall),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
