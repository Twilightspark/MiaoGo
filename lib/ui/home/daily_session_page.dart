import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:miaogo/app_theme.dart';
import 'package:miaogo/storage/checkin_store.dart';
import 'package:miaogo/storage/problem_store.dart';
import 'package:miaogo/storage/user_store.dart';
import 'package:miaogo/study/daily_problems.dart';
import 'package:miaogo/study/problem_engine.dart';
import 'package:miaogo/ui/study/problem_solve_view.dart';

/// 每日一题页：进入即抽 [kDailyProblemCount] 题并作答；退出不保留本轮状态。
///
/// 右上角两个图标按钮：
/// - 打卡日历：查看历史打卡（月历弹窗）。
/// - 再来一组：重新抽 5 题。
///
/// 当日**首次**全部做完弹「打卡成功」，点「确定」留在本页（不退出）。
class DailySessionPage extends ConsumerStatefulWidget {
  const DailySessionPage({super.key});

  @override
  ConsumerState<DailySessionPage> createState() => _DailySessionPageState();
}

class _DailySessionPageState extends ConsumerState<DailySessionPage> {
  List<Problem> _problems = const [];
  int _round = 0;
  int _index = 0;
  bool _loading = true;

  /// 本轮各题本局错误次数 / 是否解出（仅本页会话，退出即弃）。
  final Map<String, int> _attempts = {};
  final Set<String> _solved = {};

  /// 本次进入已出过的题目（供「再来一组」避开）。
  final Set<String> _usedIds = {};

  /// 本轮完成弹窗是否已处理。
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    _loadRound(1);
  }

  Future<void> _loadRound(int round) async {
    setState(() => _loading = true);
    final library = await ref.read(problemLibraryProvider.future);
    if (!mounted) return;
    final problems = selectDailyProblems(
      library: library.problems,
      rankIndex: ref.read(userProfileProvider).rankIndex,
      progress: ref.read(problemStoreProvider),
      now: DateTime.now(),
      round: round,
      excludeIds: _usedIds,
    );
    setState(() {
      _problems = problems;
      _round = round;
      _index = 0;
      _attempts.clear();
      _solved.clear();
      _usedIds.addAll(problems.map((p) => p.id));
      _completed = false;
      _loading = false;
    });
  }

  bool _isDone(String id) =>
      _solved.contains(id) || (_attempts[id] ?? 0) >= kMaxProblemAttempts;

  int get _doneCount => _problems.where((p) => _isDone(p.id)).length;

  void _onProgress(Problem problem, int stepIndex, int attempts, bool solved) {
    setState(() {
      _attempts[problem.id] = attempts;
      if (solved) _solved.add(problem.id);
    });
    _maybeComplete();
  }

  /// 本轮全部做完：当日首次则记打卡并弹「打卡成功」。
  void _maybeComplete() {
    if (_completed || _problems.isEmpty) return;
    if (_doneCount < _problems.length) return;
    _completed = true;
    if (ref
        .read(checkinStoreProvider)
        .completedDays
        .contains(checkinDateKey(DateTime.now()))) {
      return;
    }
    ref.read(checkinStoreProvider.notifier).markToday();
    _showCheckinDialog();
  }

  Future<void> _showCheckinDialog() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.emoji_events, color: GoColors.wood, size: 40),
        title: const Text('打卡成功'),
        content: const Text('恭喜完成今日全部题目，坚持就是胜利！'),
        actions: [
          FilledButton(
            key: const ValueKey('daily_checkin_ok'),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Future<void> _showCalendar() async {
    await showDialog<void>(
      context: context,
      builder: (_) => const _CheckinCalendarDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('每日打卡'),
        actions: [
          IconButton(
            key: const ValueKey('daily_calendar'),
            icon: const Icon(Icons.calendar_month_outlined),
            tooltip: '打卡日历',
            onPressed: _showCalendar,
          ),
          IconButton(
            key: const ValueKey('daily_another'),
            icon: const Icon(Icons.refresh),
            tooltip: '再来一组',
            onPressed: _loading ? null : () => _loadRound(_round + 1),
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : (_problems.isEmpty
                ? const Center(child: Text('暂无题库'))
                : Builder(builder: (context) {
                    final index = _index.clamp(0, _problems.length - 1);
                    return ProblemSolveView(
                      key: ValueKey('daily_round_$_round'),
                      problems: _problems,
                      index: index,
                      sessionOnly: true,
                      onIndexChanged: (i) => setState(() => _index = i),
                      onProgress: _onProgress,
                      headerBuilder: (context, index, total) => _ProgressCard(
                        done: _doneCount,
                        total: total,
                        problems: _problems,
                        solved: _solved,
                        attempts: _attempts,
                        currentIndex: index,
                        onSelect: (i) => setState(() => _index = i),
                      ),
                    );
                  })),
      ),
    );
  }
}

/// 顶部进度卡：本轮进度条 + 每题完成/易错标记。
class _ProgressCard extends StatelessWidget {
  const _ProgressCard({
    required this.done,
    required this.total,
    required this.problems,
    required this.solved,
    required this.attempts,
    required this.currentIndex,
    required this.onSelect,
  });

  final int done;
  final int total;
  final List<Problem> problems;

  /// 本轮已解出的题目 id。
  final Set<String> solved;

  /// 本轮各题已用错误次数。
  final Map<String, int> attempts;
  final int currentIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ratio = total == 0 ? 0.0 : done / total;
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: theme.colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '今日做题进度',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Text(
                  '$done / $total',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: GoColors.pine,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 6,
                backgroundColor: theme.colorScheme.outlineVariant,
                valueColor: const AlwaysStoppedAnimation<Color>(GoColors.pine),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                for (var i = 0; i < problems.length; i++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: _ProblemDot(
                        number: i + 1,
                        solved: solved.contains(problems[i].id),
                        wrongAttempts: attempts[problems[i].id] ?? 0,
                        current: i == currentIndex,
                        onTap: () => onSelect(i),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 单题标记：做对（浅绿底）/ 用满错误机会判错（浅红底）/ 未判错（无底），统一显示题号。
class _ProblemDot extends StatelessWidget {
  const _ProblemDot({
    required this.number,
    required this.solved,
    required this.wrongAttempts,
    required this.current,
    required this.onTap,
  });

  final int number;
  final bool solved;
  final int wrongAttempts;
  final bool current;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 仅当用满三次错误机会才判为做错。
    final wrong = !solved && wrongAttempts >= kMaxProblemAttempts;

    final Color background;
    final Color foreground;
    if (solved) {
      background = GoColors.pineContainer;
      foreground = GoColors.onPineContainer;
    } else if (wrong) {
      background = theme.colorScheme.error.withValues(alpha: 0.14);
      foreground = theme.colorScheme.error;
    } else {
      background = Colors.transparent;
      foreground = GoColors.textSecondary;
    }

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        height: 34,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: current ? GoColors.pine : theme.colorScheme.outlineVariant,
            width: current ? 2 : 1,
          ),
        ),
        child: Center(
          child: Text(
            '$number',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: foreground,
              fontWeight:
                  solved || wrong || current ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}

/// 打卡日历弹窗：月历展示历史打卡日期，可翻月。
class _CheckinCalendarDialog extends ConsumerStatefulWidget {
  const _CheckinCalendarDialog();

  @override
  ConsumerState<_CheckinCalendarDialog> createState() =>
      _CheckinCalendarDialogState();
}

class _CheckinCalendarDialogState
    extends ConsumerState<_CheckinCalendarDialog> {
  late DateTime _month;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
  }

  void _shiftMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final checked = ref.watch(checkinStoreProvider).completedDays;
    final days = DateTime(_month.year, _month.month + 1, 0).day;
    final leading = DateTime(_month.year, _month.month, 1).weekday % 7;
    final todayKey = checkinDateKey(DateTime.now());

    final cells = <Widget>[
      for (var i = 0; i < leading; i++) const SizedBox.shrink(),
      for (var d = 1; d <= days; d++)
        _dayCell(
          theme,
          d,
          checked: checked.contains(
              checkinDateKey(DateTime(_month.year, _month.month, d))),
          isToday:
              checkinDateKey(DateTime(_month.year, _month.month, d)) == todayKey,
        ),
    ];

    return AlertDialog(
      title: const Text('打卡日历'),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () => _shiftMonth(-1),
                  icon: const Icon(Icons.chevron_left),
                  visualDensity: VisualDensity.compact,
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      '${_month.year} 年 ${_month.month} 月',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => _shiftMonth(1),
                  icon: const Icon(Icons.chevron_right),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                for (final w in const ['日', '一', '二', '三', '四', '五', '六'])
                  Expanded(
                    child: Center(
                      child: Text(
                        w,
                        style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            GridView.count(
              crossAxisCount: 7,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: cells,
            ),
            const SizedBox(height: 8),
            Text(
              '累计打卡 ${checked.length} 天',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: GoColors.textSecondary),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }

  Widget _dayCell(
    ThemeData theme,
    int day, {
    required bool checked,
    required bool isToday,
  }) {
    return Container(
      margin: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: checked ? GoColors.pine : Colors.transparent,
        shape: BoxShape.circle,
        border: isToday ? Border.all(color: GoColors.pine, width: 1.5) : null,
      ),
      alignment: Alignment.center,
      child: Text(
        '$day',
        style: theme.textTheme.bodySmall?.copyWith(
          color: checked ? Colors.white : theme.colorScheme.onSurface,
          fontWeight: checked ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }
}
