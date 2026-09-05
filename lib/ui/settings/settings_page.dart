import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:miaogo/core/rank.dart';
import 'package:miaogo/game/career_controller.dart';
import 'package:miaogo/storage/checkin_store.dart';
import 'package:miaogo/storage/pending_game_store.dart';
import 'package:miaogo/storage/problem_store.dart';
import 'package:miaogo/storage/record_store.dart';
import 'package:miaogo/storage/settings_store.dart';
import 'package:miaogo/storage/user_store.dart';
import 'package:miaogo/ui/common/avatar.dart';
import 'package:miaogo/ui/common/slide_route.dart';
import 'package:miaogo/ui/settings/edit_name_page.dart';
import 'package:miaogo/ui/settings/settings_common.dart';
import 'package:miaogo/ui/settings/settings_selection_page.dart';

/// 设置页：用户 / 对弈（棋盘大小、对弈规则）/ 通用（音效、恢复默认、关于喵棋）。
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final profile = ref.watch(userProfileProvider);
    final theme = Theme.of(context);
    final board = settings.boardSize;
    return Scaffold(
      appBar: settingsAppBar(context, '设置'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionLabel('用户'),
          _SettingsTile(
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
            title: Text(
              profile.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${RankSystem.rankName(profile.rankIndex)} · '
              '${profile.careerPoints} 分 · ${profile.totalGames} 局',
            ),
            chevron: true,
            onTap: () => Navigator.of(context).push(
              slideRightRoute<void>(const EditNamePage()),
            ),
          ),
          const SizedBox(height: 16),
          _SectionLabel('对弈'),
          _SettingsTile(
            title: const Text('棋盘大小'),
            subtitle: Text('${board.size} 路 · ${board.size} × ${board.size}'),
            chevron: true,
            onTap: () => Navigator.of(context).push(
              slideRightRoute<void>(const BoardSizePage()),
            ),
          ),
          const SizedBox(height: 10),
          _SettingsTile(
            title: const Text('对弈规则'),
            subtitle: Text('${settings.rule.label} · 贴目 ${_fmtKomi(settings.komi)}'),
            chevron: true,
            onTap: () => Navigator.of(context).push(
              slideRightRoute<void>(const RulePage()),
            ),
          ),
          const SizedBox(height: 10),
          _SettingsTile(
            title: const Text('落子方式'),
            subtitle: Text(settings.moveStyle.label),
            chevron: true,
            onTap: () => Navigator.of(context).push(
              slideRightRoute<void>(const MoveStylePage()),
            ),
          ),
          const SizedBox(height: 16),
          _SectionLabel('通用'),
          _SettingsTile(
            title: const Text('音效'),
            subtitle: Text(settings.soundEnabled ? '开' : '关'),
            chevron: true,
            onTap: () => Navigator.of(context).push(
              slideRightRoute<void>(const SoundPage()),
            ),
          ),
          const SizedBox(height: 10),
          _SettingsTile(
            title: const Text('恢复默认设置'),
            trailing: Icon(
              Icons.restart_alt,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            onTap: () => _confirmReset(context, ref),
          ),
          const SizedBox(height: 10),
          _SettingsTile(
            title: const Text('关于喵棋'),
            trailing: Icon(
              Icons.info_outline,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            onTap: () => _showAbout(context),
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
      ref.read(pendingGameStoreProvider.notifier).clear();
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
      ref.read(pendingGameStoreProvider.notifier).clear();
    }
  }

  void _showAbout(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Image.asset(
          'assets/icon/app_icon_fg.png',
          width: 72,
          height: 72,
          fit: BoxFit.contain,
        ),
        title: const Text('喵棋 MiaoGo'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('版本 1.2.0'),
            SizedBox(height: 8),
            Text('本地 KataGo 引擎驱动的围棋对弈与学习应用。'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}

/// 设置页通用卡片项：暖米色卡 + ListTile 结构，模仿「用户卡片」。
class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.chevron = false,
    this.onTap,
  });

  final Widget title;
  final Widget? subtitle;
  final Widget? leading;

  /// 自定义右侧控件；与 [chevron] 互斥（[chevron] 优先）。
  final Widget? trailing;

  /// 是否显示右侧箭头。
  final bool chevron;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: theme.colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: leading,
        title: title,
        subtitle: subtitle,
        trailing: chevron
            ? Icon(Icons.chevron_right,
                color: theme.colorScheme.onSurfaceVariant)
            : trailing,
        onTap: onTap,
      ),
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

/// 贴目展示：整数省略小数点（如 7.5 / 6），避免出现 6.0 之类。
String _fmtKomi(double komi) {
  if (komi == komi.roundToDouble()) return '${komi.toInt()}';
  return '$komi';
}
