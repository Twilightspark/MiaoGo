import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:miaogo/app_theme.dart';
import 'package:miaogo/core/rank.dart';
import 'package:miaogo/storage/avatar_store.dart';
import 'package:miaogo/storage/user_store.dart';
import 'package:miaogo/ui/common/rank_badge.dart';
import 'package:miaogo/ui/home/avatar_crop_page.dart';
import 'package:miaogo/ui/play/play_home_page.dart';
import 'package:miaogo/ui/record/record_home_page.dart';
import 'package:miaogo/ui/settings/settings_page.dart';
import 'package:miaogo/ui/study/study_home_page.dart';

/// 首页：顶部用户区（头像/名称/等级/设置） + 功能入口卡片（快速对局/参加竞赛/今日学习/棋谱/功课）。
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userProfileProvider);
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            _HomeHeader(profile: profile),
            const SizedBox(height: 28),
            _WideEntryCard(
              key: const ValueKey('home_card_quick_play'),
              icon: Icons.sports_esports,
              title: '快速对局',
              subtitle: '人机对弈 · 随时开局',
              color: GoColors.pine,
              onTap: () => _push(context, const PlayHomePage()),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _EntryCard(
                    key: const ValueKey('home_card_tournament'),
                    icon: Icons.emoji_events,
                    title: '参加竞赛',
                    subtitle: '报名段位大赛',
                    color: GoColors.wood,
                    onTap: () => _push(context, const PlayHomePage()),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _EntryCard(
                    key: const ValueKey('home_card_daily_study'),
                    icon: Icons.school,
                    title: '今日学习',
                    subtitle: '死活 · 定式',
                    color: GoColors.pineDark,
                    onTap: () => _push(context, const StudyHomePage()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _NavButton(
                    key: const ValueKey('home_button_record'),
                    icon: Icons.menu_book,
                    label: '棋谱',
                    color: GoColors.wood,
                    onTap: () => _push(context, const RecordHomePage()),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _NavButton(
                    key: const ValueKey('home_button_study'),
                    icon: Icons.auto_stories,
                    label: '功课',
                    color: GoColors.pineDark,
                    onTap: () => _push(context, const StudyHomePage()),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _push(BuildContext context, Widget page) {
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => page));
  }
}

/// 顶部用户区：头像（弹窗换头像）+ 名称（弹窗用户详情）/等级 + 设置按钮。
class _HomeHeader extends ConsumerWidget {
  const _HomeHeader({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          key: const ValueKey('home_avatar'),
          customBorder: const CircleBorder(),
          onTap: () => _showAvatarDialog(context, ref),
          child: _AvatarView(
            avatarPath: profile.avatarPath,
            name: profile.name,
            radius: 28,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: InkWell(
            key: const ValueKey('home_username'),
            borderRadius: BorderRadius.circular(8),
            onTap: () => showDialog<void>(
              context: context,
              builder: (_) => const _UserDetailDialog(),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile.name,
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  RankBadge(rankIndex: profile.rankIndex, size: 20),
                ],
              ),
            ),
          ),
        ),
        IconButton(
          key: const ValueKey('home_settings'),
          icon: Icon(Icons.settings_outlined,
              color: theme.colorScheme.onSurfaceVariant),
          tooltip: '设置',
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const SettingsPage()),
          ),
        ),
      ],
    );
  }

  Future<void> _showAvatarDialog(BuildContext context, WidgetRef ref) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _AvatarView(
                avatarPath: profile.avatarPath,
                name: profile.name,
                radius: 52,
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('更换头像'),
                onPressed: () {
                  Navigator.pop(ctx);
                  _changeAvatar(context, ref);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 选图 → 圆形裁剪 → 保存 → 更新头像。
  Future<void> _changeAvatar(BuildContext context, WidgetRef ref) async {
    final bytes = await AvatarStore.pickFromGallery();
    if (bytes == null) {
      if (context.mounted) _toast(context, '未选择图片');
      return;
    }
    if (!context.mounted) return;
    final cropped = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute<Uint8List>(
          builder: (_) => AvatarCropPage(imageBytes: bytes)),
    );
    if (cropped == null) return;
    try {
      final path = await AvatarStore.save(cropped);
      if (!context.mounted) return;
      ref.read(userProfileProvider.notifier).updateAvatar(path);
      if (context.mounted) _toast(context, '头像已更新');
    } catch (_) {
      if (context.mounted) _toast(context, '头像保存失败');
    }
  }

  void _toast(BuildContext context, String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

/// 圆形头像：未设置时显示姓名首字。
class _AvatarView extends StatelessWidget {
  const _AvatarView({
    required this.avatarPath,
    required this.name,
    required this.radius,
  });

  final String avatarPath;
  final String name;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: radius * 2,
      height: radius * 2,
      child: ClipOval(
        child: avatarPath.isNotEmpty
            ? Image.file(
                File(avatarPath),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _initialAvatar(),
              )
            : _initialAvatar(),
      ),
    );
  }

  Widget _initialAvatar() {
    final initial = name.isEmpty ? '棋' : name.characters.first;
    return ColoredBox(
      color: GoColors.pineContainer,
      child: Center(
        child: Text(
          initial,
          style: TextStyle(
            fontSize: radius * 0.9,
            fontWeight: FontWeight.bold,
            color: GoColors.onPineContainer,
          ),
        ),
      ),
    );
  }
}

/// 用户详情弹窗：第一行 用户名 + 改名/重生；下方统计：等级/积分/参赛/冠军/胜率。
class _UserDetailDialog extends ConsumerStatefulWidget {
  const _UserDetailDialog();

  @override
  ConsumerState<_UserDetailDialog> createState() => _UserDetailDialogState();
}

class _UserDetailDialogState extends ConsumerState<_UserDetailDialog> {
  Future<void> _rename() async {
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

  Future<void> _rebirth() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重生'),
        content: const Text('重生将初始化用户信息（名称、段位、积分与全部统计），确定继续？'),
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
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(userProfileProvider);
    final theme = Theme.of(context);
    return Dialog(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    profile.name,
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton.icon(
                  onPressed: _rename,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('改名'),
                ),
                TextButton.icon(
                  onPressed: _rebirth,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('重生'),
                ),
              ],
            ),
            const Divider(height: 24),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: _StatTile(
                      label: '当前等级',
                      value: RankSystem.rankName(profile.rankIndex),
                    ),
                  ),
                  Expanded(
                    child: _StatTile(
                      label: '积分',
                      value: '${profile.careerPoints}',
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: _StatTile(
                      label: '参赛次数',
                      value: '${profile.participations}',
                    ),
                  ),
                  Expanded(
                    child: _StatTile(
                      label: '冠军次数',
                      value: '${profile.championships}',
                    ),
                  ),
                ],
              ),
            ),
            _StatTile(
              label: '胜率',
              value: '${(profile.winRate * 100).toStringAsFixed(1)}%',
            ),
          ],
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}

/// 首行整宽入口卡片（快速对局）。
class _WideEntryCard extends StatelessWidget {
  const _WideEntryCard({
    super.key,
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: color.withValues(alpha: 0.15),
                child: Icon(icon, size: 28, color: color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 2),
                    Text(subtitle, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              Icon(Icons.chevron_right,
                  color: theme.colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

/// 半宽入口卡片（参加竞赛 / 今日学习）。
class _EntryCard extends StatelessWidget {
  const _EntryCard({
    super.key,
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 28, color: color),
              const SizedBox(height: 10),
              Text(
                title,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 底部导航按钮（棋谱 / 功课）。
class _NavButton extends StatelessWidget {
  const _NavButton({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: 8),
              Text(
                label,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
