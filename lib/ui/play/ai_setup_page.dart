import 'dart:math';

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
import 'package:miaogo/ui/play/match_wait_page.dart';

/// 快速匹配设置页：对手段位 / 棋盘尺寸 / 对弈规则 / 下棋顺序 / 落子方式。
class AISetupPage extends ConsumerStatefulWidget {
  const AISetupPage({super.key, this.random});

  /// 猜先随机源（测试注入用）；为空则在页面内部自建。
  final Random? random;

  @override
  ConsumerState<AISetupPage> createState() => _AISetupPageState();
}

class _AISetupPageState extends ConsumerState<AISetupPage> {
  late int _difficulty;
  late BoardSize _boardSize;
  late GoRule _rule;
  late _MoveOrder _order;
  late MoveStyle _moveStyle;
  late final Random _random;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider);
    _difficulty = ref.read(userProfileProvider).rankIndex;
    _boardSize = settings.boardSize;
    _rule = settings.rule;
    _order = _MoveOrder.guess;
    _moveStyle = settings.moveStyle;
    _random = widget.random ?? Random();
  }

  /// 进入匹配：先确定本局玩家执子色（猜先则走猜先流程），
  /// 再弹出老虎机匹配弹窗，定格到旗鼓相当的对手后进入对局页。
  Future<void> _start() async {
    final color = await _resolveHumanColor();
    if (color == null || !mounted) return;
    final matched = await showMatchDialog(
      context,
      random: _random,
    );
    if (!mounted || matched == null) return; // 兜底：取消则留在本页。
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => GamePage(
        size: _boardSize.size,
        rule: _rule,
        komi: _rule.defaultKomi,
        humanColor: color,
        difficulty: _difficulty,
        moveStyle: _moveStyle,
      ),
    ));
  }

  /// 按下棋顺序解析玩家执子色；猜先由 [widget.random] 或内部随机决定。
  Future<PlayerColor?> _resolveHumanColor() async {
    switch (_order) {
      case _MoveOrder.first:
        return PlayerColor.black;
      case _MoveOrder.second:
        return PlayerColor.white;
      case _MoveOrder.guess:
        return _runGuess();
    }
  }

  /// 猜先：选择单/双后随机生成 0~9，猜中则执黑先手，否则执白后手。
  Future<PlayerColor?> _runGuess() async {
    final parity = await showDialog<_GuessParity>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('猜先'),
        content: const Text('猜对手抓子的单双：\n猜中执黑先手，猜错执白后手。'),
        actions: [
          TextButton(
            key: const ValueKey('guess_even'),
            onPressed: () => Navigator.pop(ctx, _GuessParity.even),
            child: const Text('双'),
          ),
          TextButton(
            key: const ValueKey('guess_odd'),
            onPressed: () => Navigator.pop(ctx, _GuessParity.odd),
            child: const Text('单'),
          ),
        ],
      ),
    );
    if (parity == null || !mounted) return null;

    final n = _random.nextInt(10); // 0~9
    final guessedOdd = parity == _GuessParity.odd;
    final win = guessedOdd == n.isOdd;
    final color = win ? PlayerColor.black : PlayerColor.white;

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('猜先结果'),
        content: Text(
          '对手抓了 $n 子（${n.isOdd ? '单' : '双'}），你猜「${parity.label}」'
          '${win ? '，猜中了' : '，未猜中'}。\n本局你执${color.label}'
          '${color == PlayerColor.black ? '，先行' : '，后行'}。',
        ),
        actions: [
          FilledButton(
            key: const ValueKey('guess_confirm_start'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('进入对局'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return null;
    return color;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        automaticallyImplyLeading: false,
        title: Text(
          '快速匹配',
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
          const _SectionLabel('对手段位'),
          _PillChoice<int>(
            values: [
              for (var i = 0; i < RankSystem.kTotalRanks; i++) i,
            ],
            selected: _difficulty,
            onChanged: (v) => setState(() => _difficulty = v),
            labelOf: RankSystem.rankName,
            chipKeyOf: (i, _) => ValueKey('rank_option_$i'),
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
          const _SectionLabel('下棋顺序'),
          _PillChoice<_MoveOrder>(
            values: _MoveOrder.values,
            selected: _order,
            onChanged: (v) => setState(() => _order = v),
            labelOf: (v) => v.label,
          ),
          const SizedBox(height: 16),
          const _SectionLabel('落子方式'),
          _PillChoice<MoveStyle>(
            values: MoveStyle.values,
            selected: _moveStyle,
            onChanged: (v) => setState(() => _moveStyle = v),
            labelOf: _moveStyleLabel,
          ),
          const SizedBox(height: 28),
          _buildStartArea(theme),
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              key: const ValueKey('ai_back_home'),
              onPressed: () =>
                  Navigator.of(context).popUntil((route) => route.isFirst),
              child: Text(
                '返回首页',
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

  /// 匹配对手按钮（按对手段位选型门槛）：
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
        return FilledButton(
          key: const ValueKey('ai_start_button'),
          onPressed: _start,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          child: const Text('匹配对手'),
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

/// 下棋顺序：猜先（默认）/ 先手（执黑）/ 后手（执白）。
enum _MoveOrder {
  guess('猜先'),
  first('先手'),
  second('后手');

  const _MoveOrder(this.label);
  final String label;
}

/// 猜先的单双选择。
enum _GuessParity {
  odd('单'),
  even('双');

  const _GuessParity(this.label);
  final String label;
}

/// 落子方式在快速匹配页的短文案。
String _moveStyleLabel(MoveStyle style) => switch (style) {
      MoveStyle.doubleTap => '双击',
      MoveStyle.confirm => '确认',
    };

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

/// 与「对手段位」同款卡片 + 胶囊单选（横向滚动、高 44、圆角 22）。
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

  /// 每个胶囊可选的测试键（如对手段位 `rank_option_$i`）。
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
