import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:miaogo/core/rank.dart';
import 'package:miaogo/core/rules.dart';
import 'package:miaogo/game/career_controller.dart';
import 'package:miaogo/storage/checkin_store.dart';
import 'package:miaogo/storage/problem_store.dart';
import 'package:miaogo/storage/record_store.dart';
import 'package:miaogo/storage/settings_store.dart';
import 'package:miaogo/storage/user_store.dart';
import 'package:miaogo/ui/common/avatar.dart';

/// 设置页：名称/头像 / 棋盘大小 / 对弈规则 / 贴目 / 音效 / 恢复默认 / 关于 / 重生棋手。
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final profile = ref.watch(userProfileProvider);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionLabel('用户'),
          Card(
            elevation: 0,
            color: theme.colorScheme.surfaceContainerHighest,
            child: ListTile(
              leading: InkWell(
                key: const ValueKey('settings_avatar'),
                customBorder: const CircleBorder(),
                onTap: () => showAvatarChangeDialog(context, ref),
                child: AvatarView(
                  avatarPath: profile.avatarPath,
                  name: profile.name,
                  radius: 22,
                ),
              ),
              title: Text(profile.name),
              subtitle: Text(
                '${RankSystem.rankName(profile.rankIndex)} · '
                '${profile.careerPoints} 分 · ${profile.totalGames} 局',
              ),
              trailing: const Icon(Icons.edit),
              onTap: () => _editName(context, ref),
            ),
          ),
          const SizedBox(height: 16),
          _SectionLabel('对弈'),
          Card(
            elevation: 0,
            color: theme.colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('棋盘大小', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 8),
                  SegmentedButton<BoardSize>(
                    segments: const [
                      ButtonSegment(value: BoardSize.nine, label: Text('9 路')),
                      ButtonSegment(
                          value: BoardSize.thirteen, label: Text('13 路')),
                      ButtonSegment(
                          value: BoardSize.nineteen, label: Text('19 路')),
                    ],
                    selected: {settings.boardSize},
                    onSelectionChanged: (s) => ref
                        .read(settingsProvider.notifier)
                        .setBoardSize(s.first),
                  ),
                  const SizedBox(height: 16),
                  Text('对弈规则', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 8),
                  SegmentedButton<GoRule>(
                    segments: [
                      for (final rule in GoRule.values)
                        ButtonSegment(value: rule, label: Text(rule.label)),
                    ],
                    selected: {settings.rule},
                    onSelectionChanged: (s) =>
                        ref.read(settingsProvider.notifier).setRule(s.first),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '贴目：${settings.komi}（随规则联动）',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _SectionLabel('通用'),
          Card(
            elevation: 0,
            color: theme.colorScheme.surfaceContainerHighest,
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('音效'),
                  value: settings.soundEnabled,
                  onChanged: (v) => ref
                      .read(settingsProvider.notifier)
                      .setSoundEnabled(v),
                ),
                const Divider(height: 1),
                ListTile(
                  title: const Text('恢复默认设置'),
                  trailing: const Icon(Icons.restart_alt),
                  onTap: () => _confirmReset(context, ref),
                ),
                const Divider(height: 1),
                ListTile(
                  title: const Text('关于喵棋'),
                  trailing: const Icon(Icons.info_outline),
                  onTap: () => _showAbout(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Center(
            child: TextButton(
              key: const ValueKey('settings_rebirth'),
              onPressed: () => _confirmRebirth(context, ref),
              child: Text(
                '重生棋手',
                style: TextStyle(
                  color: theme.colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Future<void> _editName(BuildContext context, WidgetRef ref) async {
    final controller =
        TextEditingController(text: ref.read(userProfileProvider).name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('修改名称'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 12,
          decoration: const InputDecoration(labelText: '名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (name != null) {
      ref.read(userProfileProvider.notifier).updateName(name);
    }
  }

  Future<void> _confirmReset(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('恢复默认设置'),
        content: const Text('将清空当前设置与用户档案（不含已保存棋谱）。确定继续？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (ok == true) {
      ref.read(settingsProvider.notifier).reset();
      ref.read(userProfileProvider.notifier).reset();
      ref.read(careerControllerProvider.notifier).reset();
    }
  }

  Future<void> _confirmRebirth(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重生'),
        content: const Text(
            '重生将初始化棋手信息与全部进度（名称、段位、积分、对局记录、赛事、打卡与做题进度），确定继续？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (ok == true) {
      ref.read(userProfileProvider.notifier).reset();
      ref.read(careerControllerProvider.notifier).reset();
      ref.read(recordStoreProvider.notifier).clear();
      ref.read(checkinStoreProvider.notifier).reset();
      ref.read(problemStoreProvider.notifier).reset();
    }
  }

  void _showAbout(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: '喵棋 MiaoGo',
      applicationVersion: '1.1.0',
      applicationIcon: const Icon(Icons.grid_on, size: 40),
      children: const [Text('本地 KataGo 引擎驱动的围棋对弈与学习应用。')],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        text,
        style: Theme.of(context)
            .textTheme
            .labelLarge
            ?.copyWith(color: Theme.of(context).colorScheme.primary),
      ),
    );
  }
}
