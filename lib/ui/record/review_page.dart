import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:miaogo/app_theme.dart';
import 'package:miaogo/core/move.dart';
import 'package:miaogo/core/rank.dart';
import 'package:miaogo/core/scoring.dart';
import 'package:miaogo/core/sgf.dart';
import 'package:miaogo/engine/analysis.dart';
import 'package:miaogo/engine/difficulty.dart';
import 'package:miaogo/engine/engine_controller.dart';
import 'package:miaogo/engine/katago_engine.dart';
import 'package:miaogo/game/review_controller.dart';
import 'package:miaogo/ui/analysis_overlay.dart';
import 'package:miaogo/ui/board_widget.dart';

/// 复盘页：逐步回放任意棋谱，任意手位查看势力 / AI 建议 / 点目。
///
/// 个人棋谱与历史名谱共用；棋盘只读，不参与对弈状态机。
class ReviewPage extends ConsumerStatefulWidget {
  const ReviewPage({super.key, required this.game, this.title});

  final SgfGame game;

  /// 标题（名谱为中文名；个人棋谱为 `黑 vs 白` 等）。
  final String? title;

  @override
  ConsumerState<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends ConsumerState<ReviewPage> {
  AnalysisSession? _analysisSession;
  List<List<double>>? _engineInfluence;
  bool _analysisEnabled = false;
  MoveAnalysis? _suggestion;
  (int, int)? _suggestionHint;

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

  /// AI 建议下一步：单次搜索（大模型，按 9 段最强参数）。
  Future<void> _askSuggestion() async {
    final engine = ref.read(kataGoDanEngineProvider);
    final s = ref.read(reviewControllerProvider);
    if (engine == null || s == null) return;
    setState(() {
      _suggestion = null;
      _suggestionHint = null;
    });
    final diff = DifficultyTable.forRank(RankSystem.kMaxRankIndex);
    late final ({AnalysisUpdate? update, String? chosen}) r;
    try {
      r = await engine.searchAndAnalyze(
        board: s.board,
        toMove: s.toMove,
        rule: s.rule,
        komi: s.komi,
        difficulty: diff,
      );
    } catch (_) {
      if (mounted) setState(() {});
      return;
    }
    if (!mounted) return;
    setState(() {
      _suggestion = r.update?.orderedMoves.isNotEmpty == true
          ? r.update!.orderedMoves.first
          : null;
      _suggestionHint = suggestionPointFrom(r.update, s.board, s.toMove);
    });
  }

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

  void _jump(int index) {
    ref.read(reviewControllerProvider.notifier).jumpTo(index);
    if (_analysisEnabled) _restartAnalysis();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(reviewControllerProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title ?? _defaultTitle(widget.game)),
        actions: [
          IconButton(
            key: const ValueKey('review_influence'),
            tooltip: '实时分析',
            icon: Icon(
              Icons.radar,
              color: _analysisEnabled ? GoColors.pine : null,
            ),
            onPressed: _engineReady ? _toggleAnalysis : null,
          ),
          IconButton(
            key: const ValueKey('review_suggest'),
            tooltip: 'AI 建议下一步',
            icon: const Icon(Icons.lightbulb_outline),
            onPressed: _engineReady ? _askSuggestion : null,
          ),
        ],
      ),
      body: s == null
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                child: Column(
                  children: [
                    const EngineStatusBanner(),
                    _GameInfoCard(state: s),
                    const SizedBox(height: 8),
                    Expanded(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 480),
                          child: AspectRatio(
                            aspectRatio: 1,
                            child: GoBoardWidget(
                              board: s.board,
                              lastMove: s.moves.isNotEmpty ? s.moves.last : null,
                              hint: _suggestionHint,
                              influence: _analysisEnabled
                                  ? _engineInfluence
                                  : null,
                              enabled: false,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    if ((_analysisEnabled || _suggestion != null))
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
                    _NavBar(state: s, onJump: _jump),
                    const SizedBox(height: 8),
                    _ReviewActions(
                      onScore: _scoreNow,
                      atStart: s.atStart,
                      atEnd: s.atEnd,
                      onFirst: () => _jump(0),
                      onPrev: () => _jump(s.index - 1),
                      onNext: () => _jump(s.index + 1),
                      onLast: () => _jump(s.mainline.length - 1),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  String _defaultTitle(SgfGame g) {
    final b = g.blackName, w = g.whiteName;
    if (b == null && w == null) return '复盘';
    return '${b ?? '?'} 对 ${w ?? '?'}';
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
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: GoColors.textPrimary),
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

/// 手位进度条。
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
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: GoColors.textSecondary),
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
          style: theme.textTheme.labelSmall
              ?.copyWith(color: GoColors.textSecondary),
        ),
      ],
    );
  }
}

/// 复盘操作栏：跳转 + 点目。
class _ReviewActions extends StatelessWidget {
  const _ReviewActions({
    required this.onScore,
    required this.atStart,
    required this.atEnd,
    required this.onFirst,
    required this.onPrev,
    required this.onNext,
    required this.onLast,
  });

  final VoidCallback onScore;
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

/// 点目结果对话框（复盘用轻量版）。
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
            '$ruleLabel规则 · 贴目 ${result.komi} · $boardSize 路 · 已走 $moveCount 手',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: GoColors.textSecondary),
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
