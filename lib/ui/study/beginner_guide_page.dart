import 'package:flutter/material.dart';
import 'package:miaogo/app_theme.dart';
import 'package:miaogo/study/beginner_guide.dart';
import 'package:miaogo/ui/board_widget.dart';
import 'package:miaogo/ui/common/responsive.dart';

/// 基础规则新手指引：引导式 12 步入门学习页。
///
/// 布局：顶栏（回到首页）→ 上（步骤标题+引导文字）→ 中（可点击棋盘）
/// → 下（上一步 / 重试 / 下一步 操作按钮）。
class BeginnerGuidePage extends StatefulWidget {
  const BeginnerGuidePage({super.key, this.initialStep = 0});

  /// 测试/跳转用起始步骤（0~11）。
  final int initialStep;

  @override
  State<BeginnerGuidePage> createState() => _BeginnerGuidePageState();
}

class _BeginnerGuidePageState extends State<BeginnerGuidePage> {
  late BeginnerGuideEngine _engine;
  bool _completionDialogShown = false;

  @override
  void initState() {
    super.initState();
    _engine = BeginnerGuideEngine(initialStep: widget.initialStep);
  }

  void _backHome() {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _handleTap(int row, int col) {
    _engine.onTap(row, col);
    _completionDialogShown = false;
    setState(() {});
    if (_engine.completed && _engine.isLastStep) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _showCompletionDialog();
      });
    }
  }

  void _gotoPrev() {
    setState(() => _engine.gotoPrev());
  }

  void _retry() {
    setState(() => _engine.retry());
  }

  void _gotoNext() {
    if (!_engine.canNext) return;
    if (_engine.isLastStep) {
      _showCompletionDialog();
      return;
    }
    setState(() => _engine.gotoNext());
  }

  void _pass() {
    setState(() => _engine.pass());
  }

  Future<void> _showCompletionDialog() async {
    if (_completionDialogShown) return;
    _completionDialogShown = true;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.emoji_events, color: GoColors.wood),
            SizedBox(width: 8),
            Text('恭喜入门！'),
          ],
        ),
        content: const Text(
          '你已完成《基础规则新手指引》，掌握了棋盘、气与提子、'
          '禁着点、连接分断、做眼、打劫、胜负判定与停一手等入门规则。'
          '现在去下一盘棋试试吧！',
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          FilledButton.icon(
            key: const ValueKey('guide_final_home'),
            onPressed: () {
              Navigator.of(ctx).pop();
              _backHome();
            },
            icon: const Icon(Icons.home_outlined, size: 18),
            label: const Text('返回首页'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('再逛逛'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    setState(() => _completionDialogShown = false);
  }

  @override
  Widget build(BuildContext context) {
    final idx = _engine.index;
    final total = BeginnerGuideEngine.totalSteps;
    final e = _engine;
    return Scaffold(
      appBar: AppBar(title: const Text('基础规则新手指引')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
          child: AdaptiveBoardLayout(
            board: GoBoardWidget(
              board: e.board,
              lastMove: e.lastMove,
              marks: [for (final m in e.marks) _toBoardMark(m)],
              enabled: e.canPlay,
              onPointTapped: e.canPlay ? _handleTap : null,
            ),
            top: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _StepHeader(engine: e, stepLabel: '第 ${idx + 1} / $total 步'),
                const SizedBox(height: 8),
              ],
            ),
            bottom: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                if (e.feedback != null)
                  _FeedbackBar(
                    text: e.feedback!.message,
                    good: e.feedback!.good,
                  ),
                if (e.showPass) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      key: const ValueKey('guide_pass'),
                      onPressed: e.canNext ? null : _pass,
                      icon: const Icon(Icons.skip_next_outlined, size: 18),
                      label: const Text('停一手'),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                _ActionBar(
                  canPrev: e.canPrev,
                  canRetry: e.canRetry,
                  canNext: e.canNext,
                  isLast: e.isLastStep,
                  onPrev: _gotoPrev,
                  onRetry: _retry,
                  onNext: _gotoNext,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static BoardMark _toBoardMark(GuideMark m) {
    switch (m.kind) {
      case GuideMarkKind.dot:
        final color = switch (m.color) {
          GuideMarkColor.pine || GuideMarkColor.auto => GoColors.pine,
          GuideMarkColor.wood => GoColors.wood,
        };
        return BoardMark.dot(row: m.row, col: m.col, color: color);
      case GuideMarkKind.badge:
        return BoardMark.badge(row: m.row, col: m.col, text: m.text);
      case GuideMarkKind.ring:
        return BoardMark.ring(row: m.row, col: m.col);
    }
  }
}

/// 顶部步骤头：进度 + 标题 + 引导正文。
class _StepHeader extends StatelessWidget {
  const _StepHeader({required this.engine, required this.stepLabel});

  final BeginnerGuideEngine engine;
  final String stepLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final step = engine.step;
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  stepLabel,
                  key: const ValueKey('guide_step_index'),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: GoColors.pineDark,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                if (engine.completed)
                  const _DoneChip()
                else
                  const Icon(
                    Icons.school_outlined,
                    size: 16,
                    color: GoColors.textSecondary,
                  ),
              ],
            ),
            const SizedBox(height: 2),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (engine.index + 1) / BeginnerGuideEngine.totalSteps,
                minHeight: 4,
                backgroundColor: theme.colorScheme.outlineVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${engine.index + 1}. ${step.title}',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: GoColors.pineDark,
              ),
            ),
            const SizedBox(height: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 96),
              child: SingleChildScrollView(
                child: Text(
                  step.instruction,
                  style: theme.textTheme.bodySmall?.copyWith(height: 1.5),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DoneChip extends StatelessWidget {
  const _DoneChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: GoColors.pineContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle, size: 13, color: GoColors.pine),
          SizedBox(width: 3),
          Text(
            '已完成',
            style: TextStyle(fontSize: 11, color: GoColors.onPineContainer),
          ),
        ],
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(
                good ? Icons.check_circle_outline : Icons.error_outline,
                size: 18,
                color: good ? GoColors.pine : GoColors.woodDark,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 76),
                child: SingleChildScrollView(
                  child: Text(
                    text,
                    style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
                  ),
                ),
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
    required this.canPrev,
    required this.canRetry,
    required this.canNext,
    required this.isLast,
    required this.onPrev,
    required this.onRetry,
    required this.onNext,
  });

  final bool canPrev;
  final bool canRetry;
  final bool canNext;
  final bool isLast;
  final VoidCallback onPrev;
  final VoidCallback onRetry;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            key: const ValueKey('guide_prev'),
            onPressed: canPrev ? onPrev : null,
            icon: const Icon(Icons.chevron_left, size: 18),
            label: const Text('上一步'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            key: const ValueKey('guide_retry'),
            onPressed: canRetry ? onRetry : null,
            icon: const Icon(Icons.replay, size: 18),
            label: const Text('重试'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FilledButton.icon(
            key: const ValueKey('guide_next'),
            onPressed: canNext ? onNext : null,
            icon: Icon(
              isLast ? Icons.flag_outlined : Icons.chevron_right,
              size: 18,
            ),
            label: Text(isLast ? '完成' : '下一步'),
          ),
        ),
      ],
    );
  }
}
