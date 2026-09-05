import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:miaogo/app_theme.dart';
import 'package:miaogo/core/rules.dart';
import 'package:miaogo/storage/settings_store.dart';
import 'package:miaogo/ui/settings/settings_common.dart';

/// 选项页中的单个选项。
class SettingsOption<T> {
  const SettingsOption(this.value, this.label, [this.subtitle]);

  final T value;
  final String label;
  final String? subtitle;
}

/// 通用「选项页」骨架：点选仅高亮，点右上角「完成」才写入并返回。
class SettingsSelectionPage<T> extends StatefulWidget {
  const SettingsSelectionPage({
    super.key,
    required this.title,
    required this.options,
    required this.initial,
    required this.onConfirm,
  });

  final String title;
  final List<SettingsOption<T>> options;
  final T initial;
  final ValueChanged<T> onConfirm;

  @override
  State<SettingsSelectionPage<T>> createState() =>
      _SettingsSelectionPageState<T>();
}

class _SettingsSelectionPageState<T> extends State<SettingsSelectionPage<T>> {
  late T _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.initial;
  }

  void _confirm() {
    widget.onConfirm(_selected);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: settingsAppBar(
        context,
        widget.title,
        action: IconButton(
          tooltip: '完成',
          onPressed: _confirm,
          icon: const Icon(Icons.check, color: GoColors.pine),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              elevation: 0,
              margin: EdgeInsets.zero,
              clipBehavior: Clip.antiAlias,
              color: theme.colorScheme.surfaceContainerHighest,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  for (var i = 0; i < widget.options.length; i++) ...[
                    if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
                    _optionTile(widget.options[i]),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _optionTile(SettingsOption<T> option) {
    final theme = Theme.of(context);
    final selected = option.value == _selected;
    final primary = GoColors.pine;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      title: Text(
        option.label,
        style: theme.textTheme.bodyLarge?.copyWith(
          fontWeight: FontWeight.w600,
          color: selected ? primary : theme.colorScheme.onSurface,
        ),
      ),
      subtitle: option.subtitle == null
          ? null
          : Text(
              option.subtitle!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
      trailing: selected
          ? Icon(Icons.check, color: primary, size: 20)
          : null,
      onTap: () => setState(() => _selected = option.value),
    );
  }
}

/// 棋盘大小选择页。
class BoardSizePage extends ConsumerWidget {
  const BoardSizePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(settingsProvider).boardSize;
    return SettingsSelectionPage<BoardSize>(
      title: '棋盘大小',
      initial: current,
      options: [
        for (final s in BoardSize.values)
          SettingsOption(s, '${s.size} 路', '${s.size} × ${s.size}'),
      ],
      onConfirm: (v) => ref.read(settingsProvider.notifier).setBoardSize(v),
    );
  }
}

/// 对弈规则选择页。
class RulePage extends ConsumerWidget {
  const RulePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(settingsProvider).rule;
    return SettingsSelectionPage<GoRule>(
      title: '对弈规则',
      initial: current,
      options: [
        for (final r in GoRule.values)
          SettingsOption(r, r.label, '贴目 ${_fmtKomi(r.defaultKomi)}'),
      ],
      onConfirm: (v) => ref.read(settingsProvider.notifier).setRule(v),
    );
  }
}

/// 音效开关选择页。
class SoundPage extends ConsumerWidget {
  const SoundPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(settingsProvider).soundEnabled;
    return SettingsSelectionPage<bool>(
      title: '音效',
      initial: current,
      options: const [
        SettingsOption(true, '开'),
        SettingsOption(false, '关'),
      ],
      onConfirm: (v) =>
          ref.read(settingsProvider.notifier).setSoundEnabled(v),
    );
  }
}

/// 落子方式选择页：双击落子 / 确认落子。
class MoveStylePage extends ConsumerWidget {
  const MoveStylePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(settingsProvider).moveStyle;
    return SettingsSelectionPage<MoveStyle>(
      title: '落子方式',
      initial: current,
      options: [
        for (final s in MoveStyle.values) SettingsOption(s, s.label),
      ],
      onConfirm: (v) => ref.read(settingsProvider.notifier).setMoveStyle(v),
    );
  }
}

/// 贴目展示：整数省略小数点（如 7.5 / 6），避免出现 6.0 之类。
String _fmtKomi(double komi) {
  if (komi == komi.roundToDouble()) return '${komi.toInt()}';
  return '$komi';
}
