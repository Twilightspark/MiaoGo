import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:miaogo/app_theme.dart';
import 'package:miaogo/core/board.dart';
import 'package:miaogo/core/move.dart';
import 'package:miaogo/core/rank.dart';
import 'package:miaogo/core/rules.dart';
import 'package:miaogo/engine/analysis.dart';
import 'package:miaogo/engine/difficulty.dart';
import 'package:miaogo/engine/engine_controller.dart';
import 'package:miaogo/engine/katago_engine.dart';
import 'package:miaogo/game/game_controller.dart';
import 'package:miaogo/storage/record_store.dart';
import 'package:miaogo/ui/analysis_overlay.dart';
import 'package:miaogo/ui/board_widget.dart';
import 'package:miaogo/ui/common/rank_badge.dart';
import 'package:miaogo/ui/score_sheet.dart';

/// 对局页：人机/生涯共用棋盘对弈界面。
///
/// [opponentName] 为对手段位展示名（生涯传 AI 中文名；空 = 默认 `AI · 段位`），
/// [source] 标记棋谱来源。
class GamePage extends ConsumerStatefulWidget {
  const GamePage({
    super.key,
    required this.size,
    required this.rule,
    required this.komi,
    required this.humanColor,
    required this.difficulty,
    this.opponentName,
    this.source = GameSource.ai,
    this.tournamentId,
  });

  final int size;
  final GoRule rule;
  final double komi;
  final PlayerColor humanColor;
  final int difficulty;
  final String? opponentName;
  final GameSource source;
  final String? tournamentId;

  @override
  ConsumerState<GamePage> createState() => _GamePageState();
}

class _GamePageState extends ConsumerState<GamePage> {
  bool _dialogShown = false;
  bool _scoreDialogShown = false;
  bool _engineErrorDialogShown = false;
  (int, int)? _selected;

  /// 引擎实时分析会话（热力图 + AI 建议）。
  AnalysisSession? _analysisSession;
  List<List<double>>? _engineInfluence;
  bool _analysisEnabled = false;
  MoveAnalysis? _suggestion;
  (int, int)? _suggestionHint;
  int _lastMoveCount = -1;

  @override
  void initState() {
    super.initState();
    // 避免在构建期修改 Provider：帧结束后再开局。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _startGame();
    });
  }

  @override
  void dispose() {
    _stopAnalysis();
    super.dispose();
  }

  void _startGame() {
    ref.read(gameControllerProvider.notifier).startNewGame(
          size: widget.size,
          rule: widget.rule,
          komi: widget.komi,
          humanColor: widget.humanColor,
          difficulty: widget.difficulty,
          opponentName: widget.opponentName,
          source: widget.source,
          tournamentId: widget.tournamentId,
        );
  }

  void _restart() {
    setState(() {
      _dialogShown = false;
      _scoreDialogShown = false;
      _engineErrorDialogShown = false;
      _selected = null;
      _suggestion = null;
      _suggestionHint = null;
    });
    _stopAnalysis();
    _startGame();
  }

  /// 关闭势力范围覆盖层。
  void _closeInfluence() {
    setState(() {
      _engineInfluence = null;
      _suggestion = null;
      _suggestionHint = null;
    });
  }

  /// 第一步：点选/拖拽选点。
  void _onPointTapped(int row, int col) {
    final game = ref.read(gameControllerProvider);
    if (!game.isHumanTurn || game.finished) return;
    setState(() => _selected = (row, col));
  }

  /// 拖拽移动选中点。
  void _onPointDrag(int row, int col) {
    final game = ref.read(gameControllerProvider);
    if (!game.isHumanTurn || game.finished) return;
    setState(() => _selected = (row, col));
  }

  /// 第二步：确认落子。
  void _placeSelected() {
    final sel = _selected;
    if (sel == null) return;
    final ok =
        ref.read(gameControllerProvider.notifier).placeStone(sel.$1, sel.$2);
    if (ok) setState(() => _selected = null);
  }

  /// 点目：直接计分终局。
  void _scoreNow() {
    _closeInfluence();
    setState(() => _selected = null);
    ref.read(gameControllerProvider.notifier).scoreAndFinish();
  }

  bool get _engineReady =>
      ref.read(danEngineStatusProvider) == EngineStatus.ready;

  /// 本局 AI 所用引擎控制器（按对手段位选型：级位小模型 / 段位大模型）。
  EngineController get _gameEngineController =>
      widget.difficulty >= RankSystem.kNumKyuRanks
          ? ref.read(danEngineStatusProvider.notifier)
          : ref.read(engineStatusProvider.notifier);

  NotifierProvider<EngineController, EngineStatus> get _gameEngineStatusProvider =>
      widget.difficulty >= RankSystem.kNumKyuRanks
          ? danEngineStatusProvider
          : engineStatusProvider;

  /// 实时分析开关（引擎必须就绪；未就绪由按钮禁用拦截）。
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

  /// 按当前局面重启分析会话（落子/悔棋/切规则后调用）。
  /// 分析固定走大模型（b18c384），不随对手段位变化。
  Future<void> _restartAnalysis() async {
    final game = ref.read(gameControllerProvider);
    final engine = ref.read(kataGoDanEngineProvider);
    if (engine == null || game.finished) return;
    await _stopAnalysis();
    if (!mounted) return;
    final toMove = game.turn;
    final size = game.board.size;
    late final AnalysisSession session;
    try {
      session = engine.startAnalysis(
        board: game.board,
        toMove: toMove,
        rule: game.rule,
        komi: game.komi,
      );
    } catch (_) {
      return; // 引擎故障：会话由对局错误弹窗处理
    }
    _analysisSession = session;
    session.updates.listen((u) {
      if (!mounted || session != _analysisSession) return;
      setState(() {
        if (u.ownership != null) {
          _engineInfluence = ownershipToInfluence(u.ownership!, size, toMove);
        }
        _suggestion = u.orderedMoves.isNotEmpty ? u.orderedMoves.first : null;
        _suggestionHint = suggestionPointFrom(u, game.board, toMove);
      });
    });
  }

  Future<void> _stopAnalysis() async {
    final session = _analysisSession;
    _analysisSession = null;
    if (session != null) {
      await session.stop();
    }
  }

  /// AI 建议下一步：单次搜索取最优着法（大模型 b18c384）。
  Future<void> _askSuggestion() async {
    final engine = ref.read(kataGoDanEngineProvider);
    final game = ref.read(gameControllerProvider);
    if (engine == null || game.finished) return;
    setState(() {
      _suggestion = null;
      _suggestionHint = null;
    });
    final diff = DifficultyTable.forRank(game.difficulty);
    late final ({AnalysisUpdate? update, String? chosen}) r;
    try {
      r = await engine.searchAndAnalyze(
        board: game.board,
        toMove: game.turn,
        rule: game.rule,
        komi: game.komi,
        difficulty: diff,
      );
    } catch (_) {
      if (mounted) setState(() {}); // 引擎故障：对局错误弹窗处理
      return;
    }
    if (!mounted) return;
    setState(() {
      _suggestion = r.update?.orderedMoves.isNotEmpty == true
          ? r.update!.orderedMoves.first
          : null;
      _suggestionHint = suggestionPointFrom(r.update, game.board, game.turn);
    });
  }

  /// 对局中切换规则（引擎侧同步规则与贴目）。
  Future<void> _changeRule() async {
    final game = ref.read(gameControllerProvider);
    final rule = await showDialog<GoRule>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('切换规则'),
        children: [
          for (final r in GoRule.values)
            SimpleDialogOption(
              key: ValueKey('rule_option_${r.name}'),
              onPressed: () => Navigator.pop(ctx, r),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  '${r.label} · 贴目 ${r.defaultKomi}',
                  style: TextStyle(
                    fontWeight: game.rule == r ? FontWeight.bold : null,
                    color: game.rule == r
                        ? GoColors.pine
                        : GoColors.textPrimary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
    if (rule == null || !mounted) return;
    final notifier = ref.read(gameControllerProvider.notifier);
    try {
      await notifier.switchRule(rule, rule.defaultKomi);
    } catch (_) {
      // 引擎故障：规则侧改动保留，错误由对局错误弹窗处理。
    }
    if (_analysisEnabled) _restartAnalysis();
  }

  /// 引擎故障处理：重启（用历史对弈记录恢复局面续弈）或退出（提前终止）。
  Future<void> _showEngineErrorDialog() async {
    final action = await showDialog<_EngineErrorAction>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('引擎出错'),
        content: const Text('KataGo 引擎异常，对局暂时中止。\n可重启引擎恢复本局，或退出本局。'),
        actions: [
          TextButton(
            key: const ValueKey('engine_error_quit'),
            onPressed: () => Navigator.pop(ctx, _EngineErrorAction.quit),
            child: const Text('退出'),
          ),
          FilledButton(
            key: const ValueKey('engine_error_restart'),
            onPressed: () => Navigator.pop(ctx, _EngineErrorAction.restart),
            child: const Text('重启'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    _engineErrorDialogShown = false;
    if (action == _EngineErrorAction.quit) {
      // 提前终止本局：不终局不计分不存棋谱，直接返回。
      Navigator.of(context).pop();
      return;
    }
    // 重启本局 AI 所用引擎（按段位选型）→ 恢复本局续弈。
    await _gameEngineController.restart();
    if (!mounted) return;
    if (ref.read(_gameEngineStatusProvider) == EngineStatus.ready) {
      ref.read(gameControllerProvider.notifier).resumeAfterEngineRestart();
    } else {
      _engineErrorDialogShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showEngineErrorDialog();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final game = ref.watch(gameControllerProvider);
    ref.listen<GameState>(gameControllerProvider, (prev, next) {
      if (next.aiError != null && !_engineErrorDialogShown) {
        _engineErrorDialogShown = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _showEngineErrorDialog();
        });
      }
      if (next.finished && !_dialogShown) {
        _dialogShown = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _showResultDialog();
        });
      }
      if (!next.finished && next.suggestScoring && !_scoreDialogShown) {
        _scoreDialogShown = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _showScoringRequestDialog();
        });
      }
      if (!next.isHumanTurn && _selected != null) {
        setState(() => _selected = null);
      }
      // 落子/悔棋后：若实时分析开启，按新局面重启。
      if (_analysisEnabled && next.moves.length != _lastMoveCount) {
        _lastMoveCount = next.moves.length;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _restartAnalysis();
        });
      }
    });
    final influence = _analysisEnabled ? _engineInfluence : null;
    return Scaffold(
      appBar: AppBar(
        title: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              RankBadge(rankIndex: widget.difficulty, size: 20),
              const SizedBox(width: 6),
              Text(widget.opponentName ??
                  'AI · ${RankSystem.rankName(widget.difficulty)}'),
            ],
          ),
        ),
        actions: [
          IconButton(
            key: const ValueKey('game_influence'),
            tooltip: '实时分析',
            icon: Icon(
              Icons.radar,
              color: _analysisEnabled ? GoColors.pine : null,
            ),
            onPressed: _engineReady
                ? () {
                    _selected = null;
                    _toggleAnalysis();
                  }
                : null,
          ),
          IconButton(
            key: const ValueKey('game_suggest'),
            tooltip: 'AI 建议下一步',
            icon: const Icon(Icons.lightbulb_outline),
            onPressed: _engineReady ? _askSuggestion : null,
          ),
          IconButton(
            key: const ValueKey('game_rule'),
            tooltip: '切换规则',
            icon: const Icon(Icons.swap_horiz),
            onPressed: _changeRule,
          ),
          IconButton(
            key: const ValueKey('game_new_game'),
            tooltip: '新对局',
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _closeInfluence();
              _confirmNewGame();
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Column(
            children: [
              const EngineStatusBanner(),
              _StatusBar(game: game, opponentName: widget.opponentName),
              const SizedBox(height: 8),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: GoBoardWidget(
                        board: game.board,
                        lastMove:
                            game.moves.isNotEmpty ? game.moves.last : null,
                        hint: _suggestionHint,
                        enabled: game.isHumanTurn,
                        selected: _selected,
                        selectedColor: game.humanColor,
                        influence: influence,
                        onPointTapped: _onPointTapped,
                        onPointDrag: _onPointDrag,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              if ((_analysisEnabled || _suggestion != null) &&
                  !game.finished)
                SuggestionPanel(
                  boardSize: game.board.size,
                  suggestion: _suggestion,
                  onDismiss: () => setState(() {
                    _suggestion = null;
                    _suggestionHint = null;
                  }),
                ),
              const SizedBox(height: 8),
              _SelectionBar(
                selected: _selected,
                humanColor: game.humanColor,
                isLegal: _selected != null &&
                    game.board.isLegal(game.humanColor, _selected!.$1,
                        _selected!.$2),
                onCancel: () => setState(() => _selected = null),
                onPlace: _placeSelected,
              ),
              const SizedBox(height: 8),
              _ThinkingBar(thinking: game.aiThinking),
              const SizedBox(height: 8),
              _ControlBar(
                game: game,
                onUndo: () {
                  _closeInfluence();
                  setState(() => _selected = null);
                  ref.read(gameControllerProvider.notifier).undo();
                },
                onPass: () {
                  _closeInfluence();
                  setState(() => _selected = null);
                  ref.read(gameControllerProvider.notifier).pass();
                },
                onResign: () {
                  _closeInfluence();
                  setState(() => _selected = null);
                  _confirmResign();
                },
                onScore: () {
                  _closeInfluence();
                  _scoreNow();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showScoringRequestDialog() async {
    final action = await showDialog<_ScoringAction>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('地盘已基本确定'),
        content: const Text('双方地盘已大致定型，是否现在点目并判断胜负？'),
        actions: [
          TextButton(
            key: const ValueKey('score_request_refuse'),
            onPressed: () => Navigator.pop(ctx, _ScoringAction.continuePlay),
            child: const Text('继续对弈'),
          ),
          FilledButton(
            key: const ValueKey('score_request_accept'),
            onPressed: () => Navigator.pop(ctx, _ScoringAction.score),
            child: const Text('点目'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    _scoreDialogShown = false;
    if (action == _ScoringAction.score) {
      _scoreNow();
    } else {
      ref.read(gameControllerProvider.notifier).refuseScoring();
    }
  }

  Future<void> _showResultDialog() async {
    final game = ref.read(gameControllerProvider);
    final action = await showDialog<ScoreSheetAction>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ScoreSheetDialog(game: game),
    );
    if (!mounted) return;
    if (action == ScoreSheetAction.restart) {
      _restart();
    } else {
      Navigator.of(context).pop();
    }
  }

  Future<void> _confirmResign() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('认输'),
        content: const Text('确定要认输吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('认输'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      ref.read(gameControllerProvider.notifier).resign();
    }
  }

  Future<void> _confirmNewGame() async {
    final game = ref.read(gameControllerProvider);
    final inProgress = !game.finished && game.moves.isNotEmpty;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新对局'),
        content: Text(inProgress ? '当前棋局尚未结束，开始新对局将放弃本局。' : '开始新对局？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('开始'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      _restart();
    }
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.game, this.opponentName});

  final GameState game;
  final String? opponentName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final human = game.humanColor;
    final ai = game.aiColor;

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child:               _PlayerInfo(
                name: '玩家',
                color: human,
                captured: game.humanCaptured,
                isTurn: game.turn == human && !game.finished,
                alignEnd: false,
              ),
            ),
            Column(
              children: [
                Text(
                  game.finished ? '对局结束' : '轮到 ${game.turn.label}方',
                  style: theme.textTheme.labelMedium
                      ?.copyWith(color: GoColors.pine),
                ),
                const SizedBox(height: 2),
                Text(
                  '第 ${game.moves.length} 手',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: GoColors.textSecondary),
                ),
              ],
            ),
            Expanded(
              child:              _PlayerInfo(
                name: opponentName ?? 'AI',
                color: ai,
                captured: game.aiCaptured,
                isTurn: game.turn == ai && !game.finished,
                alignEnd: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayerInfo extends StatelessWidget {
  const _PlayerInfo({
    required this.name,
    required this.color,
    required this.captured,
    required this.isTurn,
    required this.alignEnd,
  });

  final String name;
  final PlayerColor color;
  final int captured;
  final bool isTurn;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final turnColor = isTurn ? GoColors.pine : Colors.transparent;
    return Row(
      mainAxisAlignment:
          alignEnd ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: [
        if (!alignEnd) _stone(color),
        if (!alignEnd) const SizedBox(width: 8),
        Column(
          crossAxisAlignment:
              alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 4),
                if (isTurn)
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: turnColor,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
            Text(
              '提 $captured',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: GoColors.textSecondary),
            ),
          ],
        ),
        if (alignEnd) const SizedBox(width: 8),
        if (alignEnd) _stone(color),
      ],
    );
  }

  Widget _stone(PlayerColor color) {
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: color == PlayerColor.black
              ? const [Color(0xFF555555), Color(0xFF111111)]
              : const [Colors.white, Color(0xFFD8D3C9)],
        ),
        border: Border.all(
          color: color == PlayerColor.black
              ? Colors.transparent
              : const Color(0xFFA8A096),
        ),
      ),
    );
  }
}

class _ThinkingBar extends StatelessWidget {
  const _ThinkingBar({required this.thinking});

  final bool thinking;

  @override
  Widget build(BuildContext context) {
    if (!thinking) return const SizedBox.shrink();
    return Column(
      children: [
        const LinearProgressIndicator(minHeight: 3),
        const SizedBox(height: 4),
        Text(
          'AI 思考中…',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _ScoringAction {
  const _ScoringAction._();
  static const score = _ScoringAction._();
  static const continuePlay = _ScoringAction._();
}

/// 引擎故障对话框选项。
class _EngineErrorAction {
  const _EngineErrorAction._();
  static const restart = _EngineErrorAction._();
  static const quit = _EngineErrorAction._();
}

/// 两步落子选点栏：显示已选坐标，确认落子或取消。
class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.selected,
    required this.humanColor,
    required this.isLegal,
    required this.onCancel,
    required this.onPlace,
  });

  final (int, int)? selected;
  final PlayerColor humanColor;
  final bool isLegal;
  final VoidCallback onCancel;
  final VoidCallback onPlace;

  String _coord((int, int) p) =>
      '${GoBoard.letters[p.$2]}${p.$1 + 1}';

  @override
  Widget build(BuildContext context) {
    final sel = selected;
    if (sel == null) return const SizedBox.shrink();
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          '已选 ${_coord(sel)} · ${humanColor.label}',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: GoColors.textSecondary,
              ),
        ),
        const SizedBox(width: 12),
        OutlinedButton(
          key: const ValueKey('game_sel_cancel'),
          onPressed: onCancel,
          child: const Text('取消'),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          key: const ValueKey('game_place'),
          onPressed: isLegal ? onPlace : null,
          icon: const Icon(Icons.circle, size: 16),
          label: const Text('落子'),
        ),
      ],
    );
  }
}

class _ControlBar extends StatelessWidget {
  const _ControlBar({
    required this.game,
    required this.onUndo,
    required this.onPass,
    required this.onResign,
    required this.onScore,
  });

  final GameState game;
  final VoidCallback onUndo;
  final VoidCallback onPass;
  final VoidCallback onResign;
  final VoidCallback onScore;

  @override
  Widget build(BuildContext context) {
    final canAct = game.isHumanTurn;
    final canUndo = !game.finished && game.moves.isNotEmpty;
    final canScore = !game.finished && game.moves.isNotEmpty;
    return Row(
      children: [
        Expanded(
          child: _CtrlButton(
            key: const ValueKey('game_undo'),
            icon: Icons.undo,
            label: '悔棋',
            enabled: canUndo,
            onTap: onUndo,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _CtrlButton(
            key: const ValueKey('game_pass'),
            icon: Icons.do_not_disturb_on_outlined,
            label: 'PASS',
            enabled: canAct,
            onTap: onPass,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _CtrlButton(
            key: const ValueKey('game_resign'),
            icon: Icons.flag_outlined,
            label: '认输',
            enabled: canAct,
            onTap: onResign,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _CtrlButton(
            key: const ValueKey('game_score'),
            icon: Icons.functions,
            label: '点目',
            enabled: canScore,
            onTap: onScore,
          ),
        ),
      ],
    );
  }
}

class _CtrlButton extends StatelessWidget {
  const _CtrlButton({
    super.key,
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return OutlinedButton.icon(
      onPressed: enabled ? onTap : null,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 14),
        side: BorderSide(
          color: enabled
              ? GoColors.pine
              : theme.colorScheme.outlineVariant,
        ),
        foregroundColor: enabled ? GoColors.pine : theme.colorScheme.outline,
      ),
    );
  }
}
