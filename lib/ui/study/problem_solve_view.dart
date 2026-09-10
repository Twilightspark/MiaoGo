import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:miaogo/app_theme.dart';
import 'package:miaogo/core/board.dart';
import 'package:miaogo/core/move.dart';
import 'package:miaogo/storage/problem_store.dart';
import 'package:miaogo/storage/settings_store.dart';
import 'package:miaogo/study/problem_engine.dart';
import 'package:miaogo/ui/board_widget.dart';

/// 单题作答会话：保存该题的求解器、正解回放与界面状态。
class ProblemSession {
  ProblemSession(this.problem)
      : solver = ProblemSolver(problem),
        replayBoard = problem.initial.clone(superko: false);

  final Problem problem;
  final ProblemSolver solver;
  GoBoard replayBoard;
  int replayStep = 0;
  bool showSolution = false;
  String? feedback;
  bool feedbackGood = false;
  bool recorded = false;
  bool wrongRecorded = false;
  Move? lastPlayed;

  /// 当前选中待确认的落点（确认落子方式下由点击设置）。
  (int, int)? selected;
}

/// 通用死活题作答视图：提示卡 + 轮次信息 + 棋盘 + 反馈 + 底部操作。
///
/// 「每日打卡」与「题库」复用。视图自身负责 [problemStoreProvider] 的进度记录，
/// 额外持久化（如每日轮次续做）通过 [onProgress] 回调交由调用方处理。
class ProblemSolveView extends ConsumerStatefulWidget {
  const ProblemSolveView({
    super.key,
    required this.problems,
    required this.index,
    required this.onIndexChanged,
    this.headerBuilder,
    this.onProgress,
    this.restoreProgress,
  });

  final List<Problem> problems;
  final int index;
  final ValueChanged<int> onIndexChanged;

  /// 顶部自定义内容（如每日进度卡），随当前题号与总题数构建。
  final Widget Function(BuildContext context, int index, int total)? headerBuilder;

  /// 额外持久化：题目 + 主线下标 + 本局错误次数。
  final void Function(Problem problem, int stepIndex, int attempts)? onProgress;

  /// 恢复续做进度；返回 `(主线下标, 本局错误次数)`。
  final (int, int)? Function(Problem problem)? restoreProgress;

  @override
  ConsumerState<ProblemSolveView> createState() => _ProblemSolveViewState();
}

class _ProblemSolveViewState extends ConsumerState<ProblemSolveView> {
  final Map<String, ProblemSession> _sessions = {};

  /// 取（或创建）某题的会话；首次创建时按 [ProblemSolveView.restoreProgress] 恢复。
  ProblemSession _sessionFor(Problem p) => _sessions.putIfAbsent(p.id, () {
        final s = ProblemSession(p);
        final restored = widget.restoreProgress?.call(p);
        if (restored != null && (restored.$1 > 0 || restored.$2 > 0)) {
          s.solver.restore(index: restored.$1, attempts: restored.$2);
          if (restored.$1 > 0 && restored.$1 < p.mainline.length) {
            s.lastPlayed = p.mainline[restored.$1].move;
          }
        }
        return s;
      });

  void _goTo(int index) => widget.onIndexChanged(index);

  void _select(Problem problem, int row, int col) {
    final s = _sessionFor(problem);
    if (s.solver.solved || s.showSolution) return;
    setState(() => s.selected = (row, col));
  }

  void _confirm(Problem problem) {
    final s = _sessionFor(problem);
    final sel = s.selected;
    if (sel == null) return;
    _playAt(problem, sel.$1, sel.$2);
  }

  /// 在指定交叉点落子并按正解判定。
  void _playAt(Problem problem, int row, int col) {
    final s = _sessionFor(problem);
    if (s.solver.solved || s.showSolution) return;
    final outcome = s.solver.play(row, col);
    setState(() {
      s.selected = null;
      if (outcome == StepOutcome.wrong) {
        s.feedback = '这手不对，再想想（第 ${s.solver.attempts}/$kMaxProblemAttempts 次）';
        s.feedbackGood = false;
        _recordWrong(s);
      } else if (outcome == StepOutcome.correct) {
        s.lastPlayed = Move.point(problem.toPlay, row, col);
        s.feedback = s.solver.solved ? '正确！' : null;
        s.feedbackGood = true;
        if (s.solver.solved) _recordSolved(s);
      } else {
        s.feedback = null;
      }
    });
    _notifyProgress(s);
  }

  void _recordSolved(ProblemSession s) {
    if (s.recorded) return;
    s.recorded = true;
    ref.read(problemStoreProvider.notifier).recordAttempt(
          s.problem.id,
          solved: true,
          attempts: s.solver.attempts,
        );
  }

  void _recordWrong(ProblemSession s) {
    s.wrongRecorded = true;
    ref.read(problemStoreProvider.notifier).recordAttempt(
          s.problem.id,
          solved: false,
          attempts: 1,
        );
  }

  void _revealSolution(ProblemSession s) {
    setState(() {
      s.showSolution = true;
      s.replayStep = 0;
      s.replayBoard = s.problem.initial.clone(superko: false);
      s.feedback = null;
      s.selected = null;
    });
    // 看正解 = 做错：将该题标记为做错（仅一次）。
    if (!s.solver.solved && !s.wrongRecorded) {
      _recordWrong(s);
      _notifyProgress(s);
    }
  }

  void _solutionNext(ProblemSession s) {
    final moves = s.problem.solutionMoves;
    if (s.replayStep >= moves.length) return;
    setState(() {
      final m = moves[s.replayStep];
      if (!m.isPass && m.row != null && m.col != null) {
        s.replayBoard.forcePlay(m.color, m.row!, m.col!);
      }
      s.replayStep++;
    });
  }

  void _reset(ProblemSession s) {
    setState(() {
      s.solver.reset();
      s.showSolution = false;
      s.feedback = null;
      s.lastPlayed = null;
      s.selected = null;
      s.replayStep = 0;
      s.replayBoard = s.problem.initial.clone(superko: false);
    });
    _notifyProgress(s);
  }

  void _notifyProgress(ProblemSession s) {
    widget.onProgress?.call(
      s.problem,
      s.solver.progressIndex,
      s.solver.attempts,
    );
  }

  @override
  Widget build(BuildContext context) {
    final problems = widget.problems;
    if (problems.isEmpty) {
      return const Center(child: Text('暂无题目'));
    }
    final index = widget.index.clamp(0, problems.length - 1);
    final problem = problems[index];
    final session = _sessionFor(problem);
    final progress = ref.watch(problemStoreProvider);
    final settings = ref.watch(settingsProvider);

    final canPlay = !session.solver.solved && !session.showSolution;
    final displayBoard =
        session.showSolution ? session.replayBoard : session.solver.board;
    final lastMove = session.showSolution
        ? (session.replayStep > 0
            ? problem.solutionMoves[session.replayStep - 1]
            : null)
        : session.lastPlayed;
    final demonstrating = session.showSolution &&
        session.replayStep < problem.solutionMoves.length;
    // 做对或用满三次错误机会的题目不可重做。
    final problemDone = (progress[problem.id]?.solved ?? false) ||
        session.solver.solved ||
        session.solver.attempts >= kMaxProblemAttempts;
    // 用满 3 次做题机会（本局错误次数）后才可看正解。
    final canReveal = session.solver.attempts >= kMaxProblemAttempts;
    final viewport = viewportFor(problem);

    return Column(
      children: [
        if (widget.headerBuilder != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: widget.headerBuilder!(context, index, problems.length),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          child: PromptCard(
            toPlay: problem.toPlay,
            totalSteps: problem.solutionStepCount,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: RoundInfo(
            index: index,
            total: problems.length,
            difficulty: problem.difficulty,
            remainingSteps:
                session.showSolution ? 0 : session.solver.remainingSteps,
            solved: session.solver.solved,
            showSolution: session.showSolution,
          ),
        ),
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: GoBoardWidget(
                    board: displayBoard,
                    lastMove: lastMove,
                    viewport: viewport,
                    selected: session.selected,
                    selectedColor: problem.toPlay,
                    enabled: canPlay,
                    onPointTapped:
                        canPlay && settings.moveStyle == MoveStyle.confirm
                            ? (r, c) => _select(problem, r, c)
                            : null,
                    onPointDoubleTapped:
                        canPlay && settings.moveStyle == MoveStyle.doubleTap
                            ? (r, c) => _playAt(problem, r, c)
                            : null,
                  ),
                ),
              ),
            ),
          ),
        ),
        if (session.feedback != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: FeedbackBar(
              text: session.feedback!,
              good: session.feedbackGood,
            ),
          ),
        if (canPlay &&
            settings.moveStyle == MoveStyle.confirm &&
            session.selected != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ConfirmBar(
              selected: session.selected!,
              onConfirm: () => _confirm(problem),
              onCancel: () => setState(() => session.selected = null),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: demonstrating
              ? SolutionBar(
                  step: session.replayStep,
                  total: problem.solutionMoves.length,
                  onNext: () => _solutionNext(session),
                )
              : ActionButtons(
                  canPrev: index > 0,
                  canNext: index < problems.length - 1,
                  canReset: !problemDone,
                  canReveal: canReveal,
                  showSolution: session.showSolution,
                  onPrev: () => _goTo(index - 1),
                  onNext: () => _goTo(index + 1),
                  onReveal: () => _revealSolution(session),
                  onReset: () => _reset(session),
                ),
        ),
      ],
    );
  }
}

/// 依据题目初始棋子与正解范围，计算放大后的可视区域（最小 9×9）。
BoardViewport viewportFor(Problem p) {
  var minR = p.boardSize, maxR = -1, minC = p.boardSize, maxC = -1;
  void include(int r, int c) {
    if (r < 0 || c < 0 || r >= p.boardSize || c >= p.boardSize) return;
    minR = math.min(minR, r);
    maxR = math.max(maxR, r);
    minC = math.min(minC, c);
    maxC = math.max(maxC, c);
  }

  for (var r = 0; r < p.boardSize; r++) {
    for (var c = 0; c < p.boardSize; c++) {
      if (p.initial.at(r, c) != null) include(r, c);
    }
  }
  for (final m in p.solutionMoves) {
    if (!m.isPass && m.row != null && m.col != null) include(m.row!, m.col!);
  }
  if (maxR < 0) return BoardViewport.full(p.boardSize);

  const pad = 1;
  minR -= pad;
  maxR += pad;
  minC -= pad;
  maxC += pad;
  final rows = maxR - minR + 1;
  final cols = maxC - minC + 1;
  final size = math.min(math.max(math.max(rows, cols), 9), p.boardSize);
  var startR = ((minR + maxR) - (size - 1)) ~/ 2;
  var startC = ((minC + maxC) - (size - 1)) ~/ 2;
  startR = startR.clamp(0, p.boardSize - size);
  startC = startC.clamp(0, p.boardSize - size);
  return BoardViewport(startRow: startR, startCol: startC, size: size);
}

/// 提示卡：提醒做题者执黑还是执白、本题共需走多少步。
class PromptCard extends StatelessWidget {
  const PromptCard({super.key, required this.toPlay, required this.totalSteps});

  final PlayerColor toPlay;
  final int totalSteps;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: theme.colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: toPlay == PlayerColor.black
                    ? const Color(0xFF2B2926)
                    : Colors.white,
                border: Border.all(color: theme.colorScheme.outline),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '轮到 ${toPlay.label}方落子',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            Text(
              '共 $totalSteps 步',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: GoColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

/// 轮次信息：第几题 / 难度 / 本题还剩几步。
class RoundInfo extends StatelessWidget {
  const RoundInfo({
    super.key,
    required this.index,
    required this.total,
    required this.difficulty,
    required this.remainingSteps,
    required this.solved,
    required this.showSolution,
  });

  final int index;
  final int total;
  final ProblemDifficulty difficulty;
  final int remainingSteps;
  final bool solved;
  final bool showSolution;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusText = showSolution
        ? '正解演示'
        : solved
            ? '已解出'
            : '本题还剩 $remainingSteps 步';
    return Row(
      children: [
        Text(
          '第 ${index + 1} / $total 题',
          style: theme.textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: GoColors.woodContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            difficulty.label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: GoColors.woodDark,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const Spacer(),
        Text(
          statusText,
          style: theme.textTheme.bodySmall?.copyWith(
            color: solved ? GoColors.pine : GoColors.textSecondary,
            fontWeight: solved ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ],
    );
  }
}

class FeedbackBar extends StatelessWidget {
  const FeedbackBar({super.key, required this.text, required this.good});

  final String text;
  final bool good;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: good ? GoColors.pineContainer : GoColors.woodContainer,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Icon(
              good ? Icons.check_circle_outline : Icons.error_outline,
              size: 18,
              color: good ? GoColors.pine : GoColors.woodDark,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 两步落子选点栏（确认模式）：显示所选坐标，确认落子或取消。
class ConfirmBar extends StatelessWidget {
  const ConfirmBar({
    super.key,
    required this.selected,
    required this.onConfirm,
    required this.onCancel,
  });

  final (int, int) selected;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = '${GoBoard.sgfCoord(selected.$1, selected.$2)}'
        '（${selected.$2 + 1}, ${selected.$1 + 1}）';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          const Icon(Icons.place_outlined, size: 18, color: GoColors.pine),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '已选 $label',
              style: theme.textTheme.bodySmall,
            ),
          ),
          TextButton(
            onPressed: onCancel,
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: onConfirm,
            child: const Text('落子'),
          ),
        ],
      ),
    );
  }
}

/// 底部操作：上一题 / 下一题 / 看正解 / 重做（同一排，紧凑宽度）。
class ActionButtons extends StatelessWidget {
  const ActionButtons({
    super.key,
    required this.canPrev,
    required this.canNext,
    required this.canReset,
    required this.canReveal,
    required this.showSolution,
    required this.onPrev,
    required this.onNext,
    required this.onReveal,
    required this.onReset,
  });

  final bool canPrev;
  final bool canNext;

  /// 是否可重做（已做对 / 已做错的题不可重做）。
  final bool canReset;

  /// 是否可看正解（用满做题机会后才可点击）。
  final bool canReveal;
  final bool showSolution;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onReveal;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: CompactButton(
            label: '上一题',
            onPressed: canPrev ? onPrev : null,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: CompactButton(
            label: '下一题',
            onPressed: canNext ? onNext : null,
            filled: true,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: CompactButton(
            label: '看正解',
            onPressed: (canReveal && !showSolution) ? onReveal : null,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: CompactButton(
            label: '重做',
            onPressed: canReset ? onReset : null,
          ),
        ),
      ],
    );
  }
}

/// 紧凑按钮：小内边距 + 小字号，用于一排四个的底部操作。
class CompactButton extends StatelessWidget {
  const CompactButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.filled = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final style = ButtonStyle(
      padding: WidgetStateProperty.all(
        const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
      ),
      minimumSize: WidgetStateProperty.all(const Size(0, 38)),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      textStyle: WidgetStateProperty.all(
        const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    );
    final child = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    return filled
        ? FilledButton(onPressed: onPressed, style: style, child: child)
        : OutlinedButton(onPressed: onPressed, style: style, child: child);
  }
}

/// 正解演示栏：看正解时替代底部操作，逐步演示正解。
class SolutionBar extends StatelessWidget {
  const SolutionBar({
    super.key,
    required this.step,
    required this.total,
    required this.onNext,
  });

  final int step;
  final int total;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            '正解演示  第 $step / $total 手',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: GoColors.textSecondary),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          onPressed: onNext,
          icon: const Icon(Icons.chevron_right, size: 18),
          label: const Text('下一步'),
        ),
      ],
    );
  }
}
