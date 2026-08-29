import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:miaogo/app_theme.dart';
import 'package:miaogo/core/board.dart';
import 'package:miaogo/core/move.dart';
import 'package:miaogo/storage/problem_store.dart';
import 'package:miaogo/study/problem_engine.dart';
import 'package:miaogo/ui/board_widget.dart';

/// 答题尝试上限：达到后展示正解。
const int kMaxProblemAttempts = 3;

/// 死活题答题页：棋盘落子判定 + 正解回放 + 讲解 + 进度记录。
class ProblemPage extends ConsumerStatefulWidget {
  const ProblemPage({super.key, required this.problem});

  final Problem problem;

  @override
  ConsumerState<ProblemPage> createState() => _ProblemPageState();
}

class _ProblemPageState extends ConsumerState<ProblemPage> {
  late ProblemSolver _solver;
  late GoBoard _replayBoard;
  int _replayStep = 0;
  bool _showSolution = false;
  String? _feedback;
  bool _feedbackIsGood = false;
  bool _recorded = false;
  Move? _lastPlayed;

  Problem get problem => widget.problem;

  @override
  void initState() {
    super.initState();
    _solver = ProblemSolver(problem);
    _replayBoard = problem.initial.clone(superko: false);
  }

  void _reset() {
    setState(() {
      _solver.reset();
      _showSolution = false;
      _feedback = null;
      _replayStep = 0;
      _lastPlayed = null;
      _replayBoard = problem.initial.clone(superko: false);
    });
  }

  void _onTap(int row, int col) {
    if (_solver.solved || _showSolution) return;
    final outcome = _solver.play(row, col);
    setState(() {
      if (outcome == StepOutcome.wrong) {
        _feedback = '这手不对，再想想（第 ${_solver.attempts}/$kMaxProblemAttempts 次）';
        _feedbackIsGood = false;
        _recordWrong();
      } else if (outcome == StepOutcome.correct) {
        _lastPlayed = Move.point(problem.toPlay, row, col);
        _feedback = _solver.solved ? '正确！' : null;
        _feedbackIsGood = true;
        if (_solver.solved) _recordSolved();
      } else {
        _feedback = null;
      }
    });
    if (outcome == StepOutcome.correct && _solver.solved) {
      _showSolvedDialog();
    }
  }

  void _recordSolved() {
    if (_recorded) return;
    _recorded = true;
    ref
        .read(problemStoreProvider.notifier)
        .recordAttempt(problem.id, solved: true, attempts: _solver.attempts);
  }

  void _recordWrong() {
    ref.read(problemStoreProvider.notifier).recordAttempt(
          problem.id,
          solved: false,
          attempts: 1,
        );
  }

  void _revealSolution() {
    setState(() {
      _showSolution = true;
      _replayStep = 0;
      _replayBoard = problem.initial.clone(superko: false);
      _feedback = null;
    });
  }

  void _replayNext() {
    final moves = problem.solutionMoves;
    if (_replayStep >= moves.length) return;
    setState(() {
      final m = moves[_replayStep];
      if (!m.isPass) {
        _replayBoard.play(m.color, m.row!, m.col!);
      }
      _replayStep++;
    });
  }

  Future<void> _showSolvedDialog() async {
    final explanation = problem.explanation;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('解答正确'),
        content: Text(explanation ?? '恭喜，本题已解出！'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _revealSolution();
            },
            child: const Text('看正解'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('继续'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final attemptsLeft = kMaxProblemAttempts - _solver.attempts;
    final solved = _solver.solved;
    final canPlay = !solved && !_showSolution;
    final displayBoard = _showSolution ? _replayBoard : _solver.board;
    final lastMove = _showSolution && _replayStep > 0
        ? problem.solutionMoves[_replayStep - 1]
        : _lastPlayed;

    return Scaffold(
      appBar: AppBar(title: Text(problem.title)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
          child: Column(
            children: [
              _Header(
                toPlay: problem.toPlay,
                solved: solved,
                attemptsLeft: attemptsLeft,
                showSolution: _showSolution,
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: GoBoardWidget(
                        board: displayBoard,
                        lastMove: lastMove,
                        selectedColor: problem.toPlay,
                        enabled: canPlay,
                        onPointTapped: _onTap,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              if (_feedback != null)
                _FeedbackBar(text: _feedback!, good: _feedbackIsGood),
              const SizedBox(height: 8),
              if (_showSolution)
                _SolutionBar(
                  step: _replayStep,
                  total: problem.solutionMoves.length,
                  onNext: _replayNext,
                )
              else if (!solved)
                _ActionBar(
                  canReveal: _solver.attempts >= kMaxProblemAttempts,
                  onReveal: _revealSolution,
                  onReset: _reset,
                )
              else
                _SolvedBar(onReveal: _revealSolution, onReset: _reset),
            ],
          ),
        ),
      ),
    );
  }
}

/// 顶部信息条：执子方 / 状态 / 剩余尝试。
class _Header extends StatelessWidget {
  const _Header({
    required this.toPlay,
    required this.solved,
    required this.attemptsLeft,
    required this.showSolution,
  });

  final PlayerColor toPlay;
  final bool solved;
  final int attemptsLeft;
  final bool showSolution;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = showSolution
        ? '正解回放'
        : solved
            ? '已解出'
            : '轮到 ${toPlay.label}方';
    final color = showSolution
        ? GoColors.wood
        : solved
            ? GoColors.pine
            : GoColors.textSecondary;
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 14,
              height: 14,
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
              status,
              style: theme.textTheme.titleSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Spacer(),
            if (!solved && !showSolution)
              Text(
                '剩余尝试 $attemptsLeft',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: GoColors.textSecondary),
              ),
          ],
        ),
      ),
    );
  }
}

class _FeedbackBar extends StatelessWidget {
  const _FeedbackBar({required this.text, required this.good});

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

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.canReveal,
    required this.onReveal,
    required this.onReset,
  });

  final bool canReveal;
  final VoidCallback onReveal;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: canReveal ? onReveal : null,
            icon: const Icon(Icons.visibility_outlined, size: 18),
            label: const Text('看正解'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onReset,
            icon: const Icon(Icons.replay, size: 18),
            label: const Text('重做'),
          ),
        ),
      ],
    );
  }
}

class _SolvedBar extends StatelessWidget {
  const _SolvedBar({required this.onReveal, required this.onReset});

  final VoidCallback onReveal;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: onReveal,
            icon: const Icon(Icons.visibility_outlined, size: 18),
            label: const Text('正解回放'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onReset,
            icon: const Icon(Icons.replay, size: 18),
            label: const Text('重做'),
          ),
        ),
      ],
    );
  }
}

class _SolutionBar extends StatelessWidget {
  const _SolutionBar({
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
    final done = step >= total;
    return Row(
      children: [
        Expanded(
          child: Text(
            '第 $step / $total 手${done ? '（完）' : ''}',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: GoColors.textSecondary),
          ),
        ),
        FilledButton.icon(
          onPressed: done ? null : onNext,
          icon: const Icon(Icons.chevron_right, size: 18),
          label: Text(done ? '完成' : '下一步'),
        ),
      ],
    );
  }
}
