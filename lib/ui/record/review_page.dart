import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:miaogo/app_theme.dart';
import 'package:miaogo/core/move.dart';
import 'package:miaogo/core/rules.dart';
import 'package:miaogo/core/scoring.dart';
import 'package:miaogo/core/sgf.dart';
import 'package:miaogo/engine/analysis.dart';
import 'package:miaogo/engine/engine_controller.dart';
import 'package:miaogo/engine/katago_engine.dart';
import 'package:miaogo/game/review_controller.dart';
import 'package:miaogo/game/review_winrate.dart';
import 'package:miaogo/ui/analysis_overlay.dart';
import 'package:miaogo/ui/board_widget.dart';
import 'package:miaogo/ui/common/responsive.dart';
import 'package:miaogo/ui/common/winrate_panel.dart';

/// 历史对弈回看/复盘页：逐步回放棋谱，支持试下续弈与逐手胜率曲线。
///
/// - 顶栏去掉返回箭头/标题/AI 建议，保留实时分析，新增胜率曲线。
/// - 底栏「试下」进入人工黑白交替续弈（悔棋/停手/点目/返回）。
/// - 「退出」或系统双击返回回到首页。
class ReviewPage extends ConsumerStatefulWidget {
  const ReviewPage({super.key, required this.game});

  final SgfGame game;

  @override
  ConsumerState<ReviewPage> createState() => _ReviewPageState();
}

/// 回看页胜率曲线逐手评估预算（中性分析参数，低开销，不套对手段位）。
const int _kCurveEvalVisits = 40;
const int _kCurveEvalTimeMs = 300;

class _ReviewPageState extends ConsumerState<ReviewPage> {
  AnalysisSession? _analysisSession;
  List<List<double>>? _engineInfluence;
  bool _analysisEnabled = false;
  MoveAnalysis? _suggestion;
  (int, int)? _suggestionHint;

  /// 上次系统返回时间（双击返回判定）。
  DateTime? _lastBackAt;

  /// 试下双 PASS 终局是否已弹过点目。
  bool _autoScoreShown = false;

  // ---- 胜率曲线 ----
  bool _curveVisible = false;
  ReviewWinrateTask? _curveTask;
  bool _curveBusy = false;
  bool _curveFailed = false;
  int _curveTargetIndex = -1;
  int _curveRanTarget = -1;
  int _curveProgress = 0;
  int _curveTotal = 0;
  int _curveEpoch = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(reviewControllerProvider.notifier).load(widget.game);
      }
    });
  }

  @override
  void dispose() {
    _curveEpoch++;
    _curveTask?.cancel();
    _stopAnalysis();
    super.dispose();
  }

  bool get _engineReady =>
      ref.read(danEngineStatusProvider) == EngineStatus.ready;

  void _toggleAnalysis() {
    setState(() => _analysisEnabled = !_analysisEnabled);
    if (_analysisEnabled) {
      _restartAnalysis();
    } else {
      _stopAnalysis();
      setState(() {
        _engineInfluence = null;
        _suggestion = null;
        _suggestionHint = null;
      });
    }
  }

  Future<void> _restartAnalysis() async {
    final s = ref.read(reviewControllerProvider);
    final engine = ref.read(kataGoDanEngineProvider);
    if (engine == null || s == null) return;
    await _stopAnalysis();
    if (!mounted) return;
    final toMove = s.toMove;
    final size = s.board.size;
    late final AnalysisSession session;
    try {
      session = engine.startAnalysis(
        board: s.board,
        toMove: toMove,
        rule: s.rule,
        komi: s.komi,
      );
    } catch (_) {
      return; // 引擎故障：由引擎状态条/提示处理
    }
    _analysisSession = session;
    session.updates.listen((u) {
      if (!mounted || session != _analysisSession) return;
      setState(() {
        if (u.ownership != null) {
          _engineInfluence = ownershipToInfluence(u.ownership!, size, toMove);
        }
        _suggestion = u.orderedMoves.isNotEmpty ? u.orderedMoves.first : null;
        _suggestionHint = suggestionPointFrom(u, s.board, toMove);
      });
    });
  }

  Future<void> _stopAnalysis() async {
    final session = _analysisSession;
    _analysisSession = null;
    if (session != null) await session.stop();
  }

  // ---- 试下 ----

  void _enterTry() {
    final s = ref.read(reviewControllerProvider);
    if (s == null) return;
    // 试下期间棋盘人工对弈：先停实时分析，避免引擎热力图/占用。
    _stopAnalysis();
    setState(() {
      _analysisEnabled = false;
      _engineInfluence = null;
      _suggestion = null;
      _suggestionHint = null;
    });
    ref.read(reviewControllerProvider.notifier).enterTry();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('已进入试下：可手动黑白交替落子（停手=PASS）'),
          duration: Duration(milliseconds: 1600),
        ),
      );
  }

  void _exitTry() {
    ref.read(reviewControllerProvider.notifier).exitTry();
    _maybeAutoScoreEnd();
  }

  void _undoTry() {
    ref.read(reviewControllerProvider.notifier).undoTry();
  }

  void _passTry() {
    ref.read(reviewControllerProvider.notifier).tryPass();
    _maybeAutoScoreEnd();
  }

  /// 双 PASS 终局：自动弹点目结果（关闭后仍停留在试下）。
  void _maybeAutoScoreEnd() {
    final s = ref.read(reviewControllerProvider);
    if (s == null || !s.inTry || !s.tryEnded || _autoScoreShown) return;
    _autoScoreShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoScoreShown = false;
      if (mounted) _scoreNow();
    });
  }

  /// 试下点格子：直接以当前方落子（黑白交替）。
  void _onTryPointTapped(int row, int col) {
    ref.read(reviewControllerProvider.notifier).placeTryMove(row, col);
  }

  // ---- 点目 ----

  /// 当前局面点目：弹出数子/数目结果。
  void _scoreNow() {
    final s = ref.read(reviewControllerProvider);
    if (s == null) return;
    final result = s.score();
    showDialog<void>(
      context: context,
      builder: (_) => _ScoreResultDialog(
        result: result,
        ruleLabel: s.rule.label,
        boardSize: s.boardSize,
        moveCount: s.moves.length,
      ),
    );
  }

  // ---- 胜率曲线（数据源 = KataGo 逐手轻量分析，非对局实时采集） ----

  void _toggleCurve() {
    if (_curveVisible) {
      // 关闭：取消计算并丢弃本次任务（下次打开从开局重算）。
      _curveEpoch++;
      _curveTask?.cancel();
      setState(() {
        _curveVisible = false;
        _curveTask = null;
        _curveBusy = false;
        _curveFailed = false;
        _curveTargetIndex = -1;
        _curveRanTarget = -1;
        _curveProgress = 0;
        _curveTotal = 0;
      });
      return;
    }
    setState(() => _curveVisible = true);
    unawaited(_activateCurve());
  }

  Future<void> _activateCurve() async {
    final s = ref.read(reviewControllerProvider);
    if (s == null || !_curveVisible) return;
    final engine = ref.read(kataGoDanEngineProvider);
    if (engine == null) {
      setState(() => _curveFailed = true);
      return;
    }
    // 大模型被实时分析占用时先释放。
    if (_analysisEnabled) {
      await _stopAnalysis();
      if (!mounted) return;
      setState(() {
        _analysisEnabled = false;
        _engineInfluence = null;
        _suggestion = null;
        _suggestionHint = null;
      });
    }
    if (!mounted || !_curveVisible) return;
    _curveTask ??= ReviewWinrateTask(
      game: s.game,
      rule: s.rule,
      komi: s.komi,
      eval: _curveEvalFor(engine, s.rule, s.komi),
    );
    _curveTargetIndex = s.index;
    unawaited(_runCurve());
  }

  ReviewWinrateEval _curveEvalFor(
    KataGoEngine engine,
    GoRule rule,
    double komi,
  ) {
    return (board, toMove) async {
      final result = await engine.searchAnalysis(
        board: board,
        toMove: toMove,
        rule: rule,
        komi: komi,
        maxVisits: _kCurveEvalVisits,
        maxTimeMs: _kCurveEvalTimeMs,
      );
      return bestCandidateWinrate(result.update);
    };
  }

  /// 当前主链手位推进超过已算范围时续算（逐手补齐到当前）。
  void _maybeCurveTo(int nodeIndex) {
    if (!_curveVisible || _curveTask == null) return;
    if (nodeIndex > _curveTargetIndex) {
      _curveTargetIndex = nodeIndex;
      unawaited(_runCurve());
    }
  }

  Future<void> _runCurve() async {
    if (_curveBusy) return;
    // 大模型被实时分析占用时先释放（与快速对弈页同一策略）。
    if (_analysisEnabled) {
      await _stopAnalysis();
      if (!mounted) return;
      setState(() {
        _analysisEnabled = false;
        _engineInfluence = null;
        _suggestion = null;
        _suggestionHint = null;
      });
    }
    if (!mounted) return;
    final task = _curveTask;
    final target = _curveTargetIndex;
    if (task == null || target < 0) return;
    final epoch = _curveEpoch;
    _curveBusy = true;
    setState(() => _curveFailed = false);
    final ok = await task.runTo(
      target,
      onProgress: (done, total) {
        if (!mounted || epoch != _curveEpoch) return;
        setState(() {
          _curveProgress = done;
          _curveTotal = total;
        });
      },
    );
    if (!mounted || epoch != _curveEpoch) {
      _curveBusy = false;
      return;
    }
    _curveBusy = false;
    if (ok) {
      _curveRanTarget = target;
      setState(() => _curveProgress = _curveTotal);
      // 计算期间若用户又往后翻了，补齐剩余段。
      if (_curveVisible && _curveTargetIndex > _curveRanTarget) {
        unawaited(_runCurve());
      }
    } else if (task.isCancelled) {
      _curveTask = null;
    } else {
      setState(() => _curveFailed = true);
    }
  }

  // ---- 跳转 / 退出 ----

  void _jump(int index) {
    ref.read(reviewControllerProvider.notifier).jumpTo(index);
    if (_analysisEnabled) _restartAnalysis();
  }

  /// 系统返回：首次提示，2 秒内再次返回回到首页。
  void _handleBack() {
    final now = DateTime.now();
    final last = _lastBackAt;
    _lastBackAt = now;
    if (last != null && now.difference(last) < const Duration(seconds: 2)) {
      _exitToHome();
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('再按一次返回退出回看'),
          duration: Duration(milliseconds: 1200),
        ),
      );
  }

  /// 「退出」/双击返回：直接回到首页。
  void _exitToHome() {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(reviewControllerProvider);
    ref.listen<ReviewState?>(reviewControllerProvider, (prev, next) {
      // 回放模式下跳到更远手位时，把胜率曲线补齐到当前。
      if (next != null && !next.inTry) _maybeCurveTo(next.index);
    });
    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          actions: [
            IconButton(
              key: const ValueKey('review_influence'),
              tooltip: '实时分析',
              icon: Icon(
                Icons.radar,
                color: _analysisEnabled ? GoColors.pine : null,
              ),
              onPressed: (_engineReady && !_curveBusy) ? _toggleAnalysis : null,
            ),
            IconButton(
              key: const ValueKey('review_winrate'),
              tooltip: '胜率曲线',
              icon: Icon(
                Icons.show_chart,
                color: _curveVisible ? GoColors.pine : null,
              ),
              onPressed: _engineReady ? _toggleCurve : null,
            ),
          ],
        ),
        body: s == null
            ? const Center(child: CircularProgressIndicator())
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                  child: AdaptiveBoardLayout(
                    board: GoBoardWidget(
                      board: s.board,
                      lastMove: s.moves.isNotEmpty ? s.moves.last : null,
                      hint: _suggestionHint,
                      influence: _analysisEnabled ? _engineInfluence : null,
                      enabled: s.inTry && !s.tryEnded,
                      onPointTapped: s.inTry ? _onTryPointTapped : null,
                    ),
                    top: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const EngineStatusBanner(),
                        _GameInfoCard(state: s),
                        const SizedBox(height: 8),
                      ],
                    ),
                    bottom: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 8),
                        if (s.inTry)
                          _TryStatusBar(state: s)
                        else
                          _NavBar(state: s, onJump: _jump),
                        const SizedBox(height: 8),
                        if (_curveVisible) ...[
                          _curvePanel(s),
                          const SizedBox(height: 8),
                        ],
                        if (_analysisEnabled || _suggestion != null)
                          SuggestionPanel(
                            boardSize: s.boardSize,
                            suggestion: _suggestion,
                            onDismiss: () => setState(() {
                              _suggestion = null;
                              _suggestionHint = null;
                            }),
                          ),
                        if (s.comment != null) ...[
                          const SizedBox(height: 8),
                          _CommentPanel(comment: s.comment!),
                        ],
                        const SizedBox(height: 8),
                        if (s.inTry)
                          _TryBar(
                            state: s,
                            onUndo: _undoTry,
                            onPass: _passTry,
                            onScore: _scoreNow,
                            onBack: _exitTry,
                          )
                        else
                          _NavActionBar(
                            atStart: s.atStart,
                            atEnd: s.atEnd,
                            onFirst: () => _jump(0),
                            onPrev: () => _jump(s.index - 1),
                            onNext: () => _jump(s.index + 1),
                            onLast: () => _jump(s.mainline.length - 1),
                          ),
                        const SizedBox(height: 8),
                        _ModeBar(
                          inTry: s.inTry,
                          onTry: _enterTry,
                          onExit: _exitToHome,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _curvePanel(ReviewState s) {
    final points = <(int, double)>[
      for (final e in _curveTask?.results.entries ?? <MapEntry<int, double>>[])
        (e.key, e.value),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    final currentHand = s.moves.length - (s.inTry ? s.tryMoves.length : 0);
    final caption = _curveFailed
        ? '胜率曲线计算中断（引擎不可用）'
        : (_curveBusy || _curveProgress < _curveTotal)
        ? '正在计算胜率：$_curveProgress/$_curveTotal'
        : (points.isEmpty ? '暂无胜率数据' : null);
    return Column(
      children: [
        WinratePanel(points: points, currentHand: currentHand),
        if (caption != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              caption,
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: GoColors.textSecondary),
            ),
          ),
      ],
    );
  }
}

/// 棋谱信息卡：双方 / 结果 / 日期 / 规则。
class _GameInfoCard extends StatelessWidget {
  const _GameInfoCard({required this.state});

  final ReviewState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final g = state.game;
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '${g.blackName ?? '?'} 执黑  ·  ${g.whiteName ?? '?'} 执白',
                style: theme.textTheme.bodySmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            if (g.result != null)
              Text(
                g.result!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: GoColors.pine,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 注释面板（名谱逐步讲解 / 死活题说明）。
class _CommentPanel extends StatelessWidget {
  const _CommentPanel({required this.comment});

  final String comment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: GoColors.woodContainer,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            const Icon(Icons.notes, size: 16, color: GoColors.woodDark),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                comment,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: GoColors.textPrimary,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 手位进度条（仅历史回放模式显示）。
class _NavBar extends StatelessWidget {
  const _NavBar({required this.state, required this.onJump});

  final ReviewState state;
  final ValueChanged<int> onJump;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final max = (state.mainline.length - 1).clamp(0, state.mainline.length);
    final count = state.mainline.length - 1;
    return Column(
      children: [
        Row(
          children: [
            Text(
              state.atStart ? '开局' : '第 ${state.index} 手',
              style: theme.textTheme.bodySmall?.copyWith(
                color: GoColors.textSecondary,
              ),
            ),
            const Spacer(),
            Text(
              state.moveText ?? '',
              style: theme.textTheme.bodySmall?.copyWith(
                color: GoColors.pine,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        Slider(
          value: state.index.toDouble().clamp(0, max.toDouble()),
          min: 0,
          max: max.toDouble() == 0 ? 1 : max.toDouble(),
          onChanged: (v) => onJump(v.round()),
        ),
        Text(
          '共 $count 手',
          style: theme.textTheme.labelSmall?.copyWith(
            color: GoColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

/// 试下状态条（替代手位进度条）。
class _TryStatusBar extends StatelessWidget {
  const _TryStatusBar({required this.state});

  final ReviewState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ended = state.tryEnded;
    return SizedBox(
      height: 36,
      child: Row(
        children: [
          Text(
            '试下 · 第 ${state.moves.length} 手',
            style: theme.textTheme.bodySmall?.copyWith(
              color: GoColors.textSecondary,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            ended ? '已终局' : '轮到 ${state.toMove.label}方',
            style: theme.textTheme.bodySmall?.copyWith(
              color: ended ? GoColors.wood : GoColors.pine,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          Text(
            state.moveText ?? '',
            style: theme.textTheme.bodySmall?.copyWith(
              color: GoColors.pine,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// 历史回放操作栏：首手/上一手/下一手/末手。
class _NavActionBar extends StatelessWidget {
  const _NavActionBar({
    required this.atStart,
    required this.atEnd,
    required this.onFirst,
    required this.onPrev,
    required this.onNext,
    required this.onLast,
  });

  final bool atStart;
  final bool atEnd;
  final VoidCallback onFirst;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onLast;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _NavButton(
            key: const ValueKey('review_first'),
            icon: Icons.skip_previous,
            label: '首手',
            enabled: !atStart,
            onTap: onFirst,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _NavButton(
            key: const ValueKey('review_prev'),
            icon: Icons.chevron_left,
            label: '上一手',
            enabled: !atStart,
            onTap: onPrev,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _NavButton(
            key: const ValueKey('review_next'),
            icon: Icons.chevron_right,
            label: '下一手',
            enabled: !atEnd,
            onTap: onNext,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _NavButton(
            key: const ValueKey('review_last'),
            icon: Icons.skip_next,
            label: '末手',
            enabled: !atEnd,
            onTap: onLast,
          ),
        ),
      ],
    );
  }
}

/// 试下操作栏：悔棋/停手/点目/返回。
class _TryBar extends StatelessWidget {
  const _TryBar({
    required this.state,
    required this.onUndo,
    required this.onPass,
    required this.onScore,
    required this.onBack,
  });

  final ReviewState state;
  final VoidCallback onUndo;
  final VoidCallback onPass;
  final VoidCallback onScore;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final ended = state.tryEnded;
    return Row(
      children: [
        Expanded(
          child: _NavButton(
            key: const ValueKey('review_undo'),
            icon: Icons.undo,
            label: '悔棋',
            enabled: state.tryMoves.isNotEmpty,
            onTap: onUndo,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _NavButton(
            key: const ValueKey('review_pass'),
            icon: Icons.do_not_disturb_on_outlined,
            label: '停手',
            enabled: !ended,
            onTap: onPass,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _NavButton(
            key: const ValueKey('review_score'),
            icon: Icons.functions,
            label: '点目',
            enabled: true,
            onTap: onScore,
            accent: true,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _NavButton(
            key: const ValueKey('review_back'),
            icon: Icons.keyboard_return,
            label: '返回',
            enabled: true,
            onTap: onBack,
          ),
        ),
      ],
    );
  }
}

/// 模式操作栏：试下 / 退出。
class _ModeBar extends StatelessWidget {
  const _ModeBar({
    required this.inTry,
    required this.onTry,
    required this.onExit,
  });

  final bool inTry;
  final VoidCallback onTry;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            key: const ValueKey('review_try'),
            onPressed: inTry ? null : onTry,
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('试下'),
            style: FilledButton.styleFrom(
              backgroundColor: GoColors.pine,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            key: const ValueKey('review_exit'),
            onPressed: onExit,
            icon: const Icon(Icons.exit_to_app, size: 18),
            label: const Text('退出'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              foregroundColor: GoColors.textPrimary,
              side: BorderSide(color: theme.colorScheme.outline),
            ),
          ),
        ),
      ],
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    super.key,
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
    this.accent = false,
  });

  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = accent ? GoColors.wood : GoColors.pine;
    return OutlinedButton.icon(
      onPressed: enabled ? onTap : null,
      icon: Icon(icon, size: 18),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 12),
        side: BorderSide(
          color: enabled ? color : theme.colorScheme.outlineVariant,
        ),
        foregroundColor: enabled ? color : theme.colorScheme.outline,
      ),
    );
  }
}

/// 点目结果对话框（回看/试下轻量版）。
class _ScoreResultDialog extends StatelessWidget {
  const _ScoreResultDialog({
    required this.result,
    required this.ruleLabel,
    required this.boardSize,
    required this.moveCount,
  });

  final ScoreResult result;
  final String ruleLabel;
  final int boardSize;
  final int moveCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final headlineColor = result.winner == null
        ? GoColors.wood
        : (result.winner == PlayerColor.black
              ? GoColors.pine
              : GoColors.textSecondary);
    final unit = result.method == ScoringMethod.area ? '点' : '目';
    return AlertDialog(
      title: const Text('当前局面点目'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Text(
              result.description,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: headlineColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 14),
          for (final line in result.details)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(line, style: theme.textTheme.bodySmall),
            ),
          const SizedBox(height: 12),
          Divider(color: theme.colorScheme.outlineVariant),
          Text(
            '黑 ${result.blackTotal} $unit · 白 ${result.whiteTotal} $unit · '
            '$ruleLabel规则 · $boardSize 路 · 已走 $moveCount 手',
            style: theme.textTheme.bodySmall?.copyWith(
              color: GoColors.textSecondary,
            ),
          ),
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}
