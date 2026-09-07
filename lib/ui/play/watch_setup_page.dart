import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:miaogo/app_theme.dart';
import 'package:miaogo/core/rank.dart';
import 'package:miaogo/core/rules.dart';
import 'package:miaogo/engine/engine_controller.dart';
import 'package:miaogo/engine/katago_engine.dart';
import 'package:miaogo/storage/settings_store.dart';
import 'package:miaogo/storage/user_store.dart';
import 'package:miaogo/ui/play/watch_game_page.dart';

/// 休闲观赛设置页：棋手等级 / 棋盘尺寸 / 对弈规则 → 开始观赛。
///
/// 两名本地 KataGo 棋手将自动互弈，用户仅旁观；布局参考「快速匹配」设置页。
class WatchSetupPage extends ConsumerStatefulWidget {
  const WatchSetupPage({super.key});

  @override
  ConsumerState<WatchSetupPage> createState() => _WatchSetupPageState();
}

class _WatchSetupPageState extends ConsumerState<WatchSetupPage> {
  late int _difficulty;
  late BoardSize _boardSize;
  late GoRule _rule;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider);
    _difficulty = ref.read(userProfileProvider).rankIndex;
    _boardSize = settings.boardSize;
    _rule = settings.rule;
  }

  void _start() {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => WatchGamePage(
        size: _boardSize.size,
        rule: _rule,
        komi: _rule.defaultKomi,
        rankIndex: _difficulty,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        automaticallyImplyLeading: false,
        title: Text(
          '休闲观赛',
          style: theme.textTheme.bodyLarge?.copyWith(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurface,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _SectionLabel('棋手等级'),
          _PillChoice<int>(
            values: [
              for (var i = 0; i < RankSystem.kTotalRanks; i++) i,
            ],
            selected: _difficulty,
            onChanged: (v) => setState(() => _difficulty = v),
            labelOf: RankSystem.rankName,
            chipKeyOf: (i, _) => ValueKey('watch_rank_$i'),
          ),
          const SizedBox(height: 16),
          const _SectionLabel('棋盘尺寸'),
          _PillChoice<BoardSize>(
            values: BoardSize.values,
            selected: _boardSize,
            onChanged: (v) => setState(() => _boardSize = v),
            labelOf: (v) => '${v.size} 路',
          ),
          const SizedBox(height: 16),
          const _SectionLabel('对弈规则'),
          _PillChoice<GoRule>(
            values: GoRule.values,
            selected: _rule,
            onChanged: (v) => setState(() => _rule = v),
            labelOf: (v) => v.label,
          ),
          const SizedBox(height: 16),
          _buildStartArea(theme),
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              key: const ValueKey('watch_back_home'),
              onPressed: () =>
                  Navigator.of(context).popUntil((route) => route.isFirst),
              child: Text(
                '回到首页',
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  /// 开始观赛按钮（按棋手等级选型引擎）：
  /// 级位（<18）走小模型 b6c96，段位（>=18）走大模型 b18c384，
  /// 对应模型就绪才可开始；加载中禁用+进度，失败显示错误+重试。
  Widget _buildStartArea(ThemeData theme) {
    final isDan = _difficulty >= RankSystem.kNumKyuRanks;
    final statusProvider =
        isDan ? danEngineStatusProvider : engineStatusProvider;
    final status = ref.watch(statusProvider);
    final notifier = ref.read(statusProvider.notifier);
    final modelLabel = isDan ? '大模型' : '引擎';
    switch (status) {
      case EngineStatus.ready:
        return FilledButton(
          key: const ValueKey('watch_start_button'),
          onPressed: _start,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          child: const Text('开始观赛'),
        );
      case EngineStatus.loading:
        return FilledButton.icon(
          key: const ValueKey('watch_start_button'),
          onPressed: null,
          icon: const Icon(Icons.hourglass_top),
          label: Text('$modelLabel加载中…'),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
        );
      case EngineStatus.failed:
        final error = notifier.lastError;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              elevation: 0,
              color: GoColors.woodContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'KataGo $modelLabel不可用，无法观赛${error == null ? '' : '\n$error'}',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const ValueKey('watch_start_button'),
              onPressed: () => notifier.start(),
              icon: const Icon(Icons.refresh),
              label: const Text('重试加载引擎'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ],
        );
      case EngineStatus.idle:
        // 对应模型尚未启动：触发启动并展示加载态。
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) notifier.start();
        });
        return FilledButton.icon(
          key: const ValueKey('watch_start_button'),
          onPressed: null,
          icon: const Icon(Icons.hourglass_top),
          label: Text('$modelLabel加载中…'),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
        );
    }
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
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }
}

/// 与「快速匹配」同款卡片 + 胶囊单选（横向滚动、高 44、圆角 22）。
class _PillChoice<T> extends StatelessWidget {
  const _PillChoice({
    required this.values,
    required this.selected,
    required this.onChanged,
    required this.labelOf,
    this.chipKeyOf,
  });

  final List<T> values;
  final T selected;
  final ValueChanged<T> onChanged;
  final String Function(T value) labelOf;

  /// 每个胶囊可选的测试键（如 `watch_rank_$i`）。
  final Key? Function(int index, T value)? chipKeyOf;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: values.length,
            itemBuilder: (context, i) {
              final value = values[i];
              final isSelected = value == selected;
              return InkWell(
                key: chipKeyOf?.call(i, value),
                borderRadius: BorderRadius.circular(22),
                onTap: () => onChanged(value),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isSelected ? GoColors.pine : GoColors.surface,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: isSelected
                          ? GoColors.pine
                          : GoColors.outlineVariant,
                    ),
                  ),
                  child: Text(
                    labelOf(value),
                    style: TextStyle(
                      color:
                          isSelected ? GoColors.white : GoColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              );
            },
            separatorBuilder: (_, _) => const SizedBox(width: 8),
          ),
        ),
      ),
    );
  }
}
