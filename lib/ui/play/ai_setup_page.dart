import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:miaogo/app_theme.dart';
import 'package:miaogo/core/move.dart';
import 'package:miaogo/core/rank.dart';
import 'package:miaogo/core/rules.dart';
import 'package:miaogo/engine/engine_controller.dart';
import 'package:miaogo/engine/katago_engine.dart';
import 'package:miaogo/storage/settings_store.dart';
import 'package:miaogo/storage/user_store.dart';
import 'package:miaogo/ui/play/game_page.dart';

/// 人机对弈设置页：对手段位 / 棋盘尺寸 / 规则 / 先后手。
class AISetupPage extends ConsumerStatefulWidget {
  const AISetupPage({super.key});

  @override
  ConsumerState<AISetupPage> createState() => _AISetupPageState();
}

class _AISetupPageState extends ConsumerState<AISetupPage> {
  late int _difficulty;
  late BoardSize _boardSize;
  late GoRule _rule;
  bool _humanBlack = true;

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
      builder: (_) => GamePage(
        size: _boardSize.size,
        rule: _rule,
        komi: _rule.defaultKomi,
        humanColor: _humanBlack ? PlayerColor.black : PlayerColor.white,
        difficulty: _difficulty,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('人机对弈')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _SectionLabel('对手段位'),
          Card(
            elevation: 0,
            color: theme.colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: SizedBox(
                height: 44,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: RankSystem.kTotalRanks,
                  itemBuilder: (context, i) {
                    final selected = i == _difficulty;
                    return InkWell(
                      key: ValueKey('rank_option_$i'),
                      borderRadius: BorderRadius.circular(22),
                      onTap: () => setState(() => _difficulty = i),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: selected
                              ? GoColors.pine
                              : GoColors.surface,
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: selected
                                ? GoColors.pine
                                : GoColors.outlineVariant,
                          ),
                        ),
                        child: Text(
                          RankSystem.rankName(i),
                          style: TextStyle(
                            color: selected
                                ? GoColors.white
                                : GoColors.textPrimary,
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
          ),
          const SizedBox(height: 16),
          const _SectionLabel('棋盘尺寸'),
          _OptionCard(
            child: SegmentedButton<BoardSize>(
              segments: const [
                ButtonSegment(value: BoardSize.nine, label: Text('9 路')),
                ButtonSegment(
                    value: BoardSize.thirteen, label: Text('13 路')),
                ButtonSegment(
                    value: BoardSize.nineteen, label: Text('19 路')),
              ],
              selected: {_boardSize},
              onSelectionChanged: (s) => setState(() => _boardSize = s.first),
            ),
          ),
          const SizedBox(height: 16),
          const _SectionLabel('对弈规则'),
          _OptionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SegmentedButton<GoRule>(
                  segments: [
                    for (final rule in GoRule.values)
                      ButtonSegment(value: rule, label: Text(rule.label)),
                  ],
                  selected: {_rule},
                  onSelectionChanged: (s) => setState(() => _rule = s.first),
                ),
                const SizedBox(height: 8),
                Text(
                  '贴目：${_rule.defaultKomi}（随规则联动）',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const _SectionLabel('执子'),
          _OptionCard(
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('先手（执黑）')),
                ButtonSegment(value: false, label: Text('后手（执白）')),
              ],
              selected: {_humanBlack},
              onSelectionChanged: (s) =>
                  setState(() => _humanBlack = s.first),
            ),
          ),
          const SizedBox(height: 28),
          _buildStartArea(theme),
        ],
      ),
    );
  }

  /// 开始对弈按钮（按对手段位选型门槛）：
  /// 级位（<18）走小模型 b6c96，段位（>=18）走大模型 b18c384。
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
        return FilledButton.icon(
          key: const ValueKey('ai_start_button'),
          onPressed: _start,
          icon: const Icon(Icons.play_arrow),
          label: const Text('开始对弈'),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
        );
      case EngineStatus.loading:
        return FilledButton.icon(
          key: const ValueKey('ai_start_button'),
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
                  'KataGo $modelLabel不可用，无法对弈${error == null ? '' : '\n$error'}',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const ValueKey('ai_start_button'),
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
          key: const ValueKey('ai_start_button'),
          onPressed: null,
          icon: const Icon(Icons.hourglass_top),
          label: Text('$modelLabel加载中…'),
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

class _OptionCard extends StatelessWidget {
  const _OptionCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: child,
      ),
    );
  }
}
