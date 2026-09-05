import 'dart:async';
import 'dart:math';

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
import 'package:miaogo/game/career.dart';
import 'package:miaogo/game/game_controller.dart';
import 'package:miaogo/storage/pending_game_store.dart';
import 'package:miaogo/storage/record_store.dart';
import 'package:miaogo/storage/settings_store.dart';
import 'package:miaogo/storage/user_store.dart';
import 'package:miaogo/ui/analysis_overlay.dart';
import 'package:miaogo/ui/board_widget.dart';
import 'package:miaogo/ui/score_sheet.dart';

/// 对局页：人机/生涯共用棋盘对弈界面。
///
/// [opponentName] 为对手段位展示名（生涯传 AI 中文名；空 = 默认 `AI · 段位`），
/// [source] 标记棋谱来源。默认构造开局新对局；
/// 待续快照续弈请用 [GamePage.resume]。
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
    this.moveStyle,
  }) : _resumeFrom = null;

  /// 从「保存对局」快照续弈（参数均取自快照）。
  GamePage.resume({super.key, required PendingGame pending})
      : _resumeFrom = pending,
        size = pending.size,
        rule = pending.rule,
        komi = pending.komi,
        humanColor = pending.humanColor,
        difficulty = pending.difficulty,
        opponentName = pending.opponentName,
        source = pending.source,
        tournamentId = pending.tournamentId,
        moveStyle = pending.moveStyle;

  final int size;
  final GoRule rule;
  final double komi;
  final PlayerColor humanColor;
  final int difficulty;
  final String? opponentName;
  final GameSource source;
  final String? tournamentId;

  /// 本局落子方式；为空则取全局设置（进入前一致）。
  final MoveStyle? moveStyle;

  /// 非空 = 本页从该快照续弈（跳过开局）。
  final PendingGame? _resumeFrom;

  @override
  ConsumerState<GamePage> createState() => _GamePageState();
}

/// 实时分析单局面搜索 visit 上限：到达后自动停止并保留结果展示。
const int _kAnalysisVisitCap = 100;

/// 胜率曲线「轮到玩家那手」的低开销评估预算（不套对手段位）。
const EngineDifficulty _kCurveEvalDifficulty = EngineDifficulty(
  rankIndex: 0,
  maxVisits: 40,
  maxTimeMs: 300,
  temperature: 0.1,
  rootNoise: 0,
  topK: 1,
);

class _GamePageState extends ConsumerState<GamePage> {
  bool _dialogShown = false;
  bool _scoreDialogShown = false;
  bool _engineErrorDialogShown = false;
  (int, int)? _selected;

  /// 上次系统返回时间（双击返回判定）。
  DateTime? _lastBackAt;

  /// 引擎实时分析会话（热力图 + AI 建议）。
  AnalysisSession? _analysisSession;
  List<List<double>>? _engineInfluence;
  bool _analysisEnabled = false;

  /// AI 推荐点（≤4，编号标注）。实时分析会话产出。
  List<MoveAnalysis> _suggestions = const [];
  int _lastMoveCount = -1;

  /// 胜率曲线面板可见性（数据自开局常开采集，与面板开关无关）。
  bool _curveVisible = false;

  /// 黑方胜率采样：(手数 → 黑方胜率 0..1)，本局自第 0 手起持续累积。
  final Map<int, double> _blackWinrateByHand = {};
  bool _curveEvalInFlight = false;

  /// 是否正在“自动关闭实时分析以释放引擎”的过渡中。
  bool _curveStoppingAnalysis = false;

  /// 当前已挂载 AI 胜率监听的选点器卸载函数（dispose 时清理，避免残留监听）。
  void Function()? _detachCurveListener;

  /// 本局落子方式（双击 / 确认；进入前设置一致）。
  late MoveStyle _moveStyle;

  /// 本局对手展示名（竞赛 = 真实对手名；人机 = 随机昵称）。
  late String _aiName;

  @override
  void initState() {
    super.initState();
    _moveStyle =
        widget.moveStyle ?? ref.read(settingsProvider).moveStyle;
    _aiName = widget.opponentName ?? CareerNames.aiPlayerName(Random());
    final pending = widget._resumeFrom;
    if (pending != null) {
      for (final (hand, wr) in pending.winrateHistory) {
        _blackWinrateByHand[hand] = wr;
      }
    }
    // 避免在构建期修改 Provider：帧结束后再开局并挂上胜率采样监听。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _startGame();
      if (mounted) _attachWinrateListener();
    });
  }

  @override
  void dispose() {
    _detachWinrateListener();
    _stopAnalysis();
    super.dispose();
  }
  void _startGame() {
    final resume = widget._resumeFrom;
    final notifier = ref.read(gameControllerProvider.notifier);
    if (resume != null) {
      unawaited(notifier.resumePending(resume));
      return;
    }
    notifier.startNewGame(
      size: widget.size,
      rule: widget.rule,
      komi: widget.komi,
      humanColor: widget.humanColor,
      difficulty: widget.difficulty,
      opponentName: _aiName,
      source: widget.source,
      tournamentId: widget.tournamentId,
      moveStyle: _moveStyle,
    );
  }

  void _restart() {
    setState(() {
      _dialogShown = false;
      _scoreDialogShown = false;
      _engineErrorDialogShown = false;
      _selected = null;
      _suggestions = const [];
      _blackWinrateByHand.clear();
    });
    _stopAnalysis();
    _attachWinrateListener();
    _startGame();
  }

  /// 关闭势力范围覆盖层。
  void _closeInfluence() {
    setState(() {
      _engineInfluence = null;
      _suggestions = const [];
    });
  }

  /// 第一步：点选/拖拽选点；双击模式再次点同一选点即落子。
  void _onPointTapped(int row, int col) {
    final game = ref.read(gameControllerProvider);
    if (!game.isHumanTurn || game.finished) return;
    if (_moveStyle == MoveStyle.doubleTap) {
      if (_selected == (row, col)) {
        _placeSelected();
      } else {
        setState(() => _selected = (row, col));
      }
      return;
    }
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
    if (ok) {
      setState(() {
        _selected = null;
        _suggestions = const [];
      });
    }
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
        _suggestions = const [];
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
      final rootVisits = u.rootInfo?.visits;
      setState(() {
        if (u.ownership != null) {
          _engineInfluence = ownershipToInfluence(u.ownership!, size, toMove);
        }
        _suggestions = filterSuggestions(u, game.board, toMove);
      });
      // 搜索访问数达到上限：自动停止并保留最后一次结果展示。
      if (rootVisits != null && rootVisits >= _kAnalysisVisitCap) {
        unawaited(_stopAnalysis());
      }
    });
  }

  Future<void> _stopAnalysis() async {
    final session = _analysisSession;
    _analysisSession = null;
    if (session != null) {
      await session.stop();
    }
  }

  /// 底部「取消」：提前终止分析或关闭当前分析结果显示。
  void _cancelAnalysis() {
    if (!_analysisEnabled) return;
    setState(() {
      _analysisEnabled = false;
      _engineInfluence = null;
      _suggestions = const [];
    });
    unawaited(_stopAnalysis());
  }

  /// 把当前推荐点转成棋盘编号标注（跳过已失效/被占点）。
  List<BoardSuggestionMark> _suggestionMarks(
      GoBoard board, PlayerColor toMove) {
    final out = <BoardSuggestionMark>[];
    for (final a in _suggestions) {
      if (a.move == 'pass') continue;
      final v = coordFromGtp(a.move);
      if (v == null) continue;
      final (r, c) = v;
      if (!board.inBounds(r, c) || !board.isLegal(toMove, r, c)) continue;
      out.add(BoardSuggestionMark(
        row: r,
        col: c,
        number: out.length + 1,
        isBest: out.isEmpty,
      ));
    }
    return out;
  }

  // ---- 胜率曲线 ----

  /// 顶部按钮：显示/隐藏胜率曲线面板（数据自开局常开采集，不随开关清空）。
  void _toggleCurve() {
    setState(() => _curveVisible = !_curveVisible);
  }

  /// 把 AI 搜索监听挂到当前 KataGo 选点器上（每次对局状态变化重挂，
  /// 兼容引擎重启后选点器实例被重建）。
  void _attachWinrateListener() {
    final provider = ref.read(kataGoMoveProvider);
    if (provider == null) return;
    provider.winrateListener = _onAiSearchWinrate;
    _detachCurveListener = () => provider.winrateListener = null;
  }

  void _detachWinrateListener() {
    final detach = _detachCurveListener;
    _detachCurveListener = null;
    detach?.call();
  }

  /// AI 行棋前搜索完成（该搜索状态恰好 = 玩家刚落子那手）。
  void _onAiSearchWinrate(PlayerColor sideToMove, double winrate) {
    if (!mounted) return;
    final hand = ref.read(gameControllerProvider).moves.length;
    _recordBlackWinrate(hand, winrate, sideToMove);
  }

  void _recordBlackWinrate(int hand, double winrate, PlayerColor sideToMove) {
    _blackWinrateByHand[hand] =
        blackPerspectiveWinrate(winrate, sideToMove);
    if (mounted) setState(() {});
  }

  /// 轮到玩家且引擎空闲时补做一次低开销评估（每手一个真实点）。
  /// 与 AI 行棋同引擎保证数据源一致；段位局若大模型正被实时分析占用，
  /// 先自动关闭实时分析以释放引擎，再继续采样，保证曲线完整。
  void _scheduleCurveSample() {
    if (_curveEvalInFlight || _curveStoppingAnalysis) return;
    _attachWinrateListener();
    final game = ref.read(gameControllerProvider);
    if (game.finished || game.aiError != null) return;
    if (game.turn == game.aiColor) return; // AI 思考会自行回调
    final hand = game.moves.length;
    if (_blackWinrateByHand.containsKey(hand)) return;
    final provider = ref.read(kataGoMoveProvider);
    final engine = provider == null
        ? null
        : (game.difficulty >= RankSystem.kNumKyuRanks
            ? provider.danEngine
            : provider.kyuEngine);
    if (engine == null) return;
    final usingDan = engine == provider!.danEngine;
    if (usingDan && _analysisEnabled) {
      // 实时分析正占用大模型：先异步关闭，再回来评估。
      _curveStoppingAnalysis = true;
      unawaited(() async {
        try {
          await _stopAnalysis();
        } catch (_) {
          // 引擎异常交由对局错误流程处理，这里仅保证采样状态复位。
        }
        if (!mounted) {
          _curveStoppingAnalysis = false;
          return;
        }
        setState(() {
          _analysisEnabled = false;
          _engineInfluence = null;
          _suggestions = const [];
        });
        _curveStoppingAnalysis = false;
        _scheduleCurveSample();
      }());
      return;
    }
    final sideToMove = game.turn;
    final rule = game.rule;
    final komi = game.komi;
    _curveEvalInFlight = true;
    unawaited(() async {
      try {
        final r = await engine.searchAndAnalyze(
          board: game.board.clone(),
          toMove: sideToMove,
          rule: rule,
          komi: komi,
          difficulty: _kCurveEvalDifficulty,
        );
        if (!mounted) return;
        final wr = bestCandidateWinrate(r.update);
        if (wr == null) return;
        // 悔棋等导致该手已不在历史里则丢弃。
        if (hand <= ref.read(gameControllerProvider).moves.length) {
          _recordBlackWinrate(hand, wr, sideToMove);
        }
      } catch (_) {
        // 采样失败不中断对局（引擎异常由对局错误流程处理）。
      } finally {
        _curveEvalInFlight = false;
      }
    }());
  }

  /// 悔棋/切规则后丢弃超出当前手数的采样点。
  void _pruneCurveTo(int hand) {
    if (_blackWinrateByHand.keys.any((k) => k > hand)) {
      _blackWinrateByHand.removeWhere((k, _) => k > hand);
      if (mounted) setState(() {});
    }
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
      // 胜率曲线自开局常开采集：每步状态变化都修剪/排程采样。
      _pruneCurveTo(next.moves.length);
      _scheduleCurveSample();
    });
    final influence = _analysisEnabled ? _engineInfluence : null;
    final canSave = !game.finished && game.moves.isNotEmpty;
    final profile = ref.watch(userProfileProvider);
    final humanName = profile.name.isEmpty ? '玩家' : profile.name;
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
            key: const ValueKey('game_winrate'),
            tooltip: '胜率曲线',
            icon: Icon(
              Icons.show_chart,
              color: _curveVisible ? GoColors.pine : null,
            ),
            onPressed: _engineReady ? _toggleCurve : null,
          ),
          IconButton(
            key: const ValueKey('game_save'),
            tooltip: '保存对局',
            icon: const Icon(Icons.save_outlined),
            onPressed: canSave ? _saveGame : null,
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Column(
            children: [
              const EngineStatusBanner(),
              _StatusBar(
                game: game,
                humanName: humanName,
                aiName: _aiName,
              ),
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
                        suggestions: _suggestions.isEmpty
                            ? null
                            : _suggestionMarks(game.board, game.turn),
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
              if (_curveVisible) ...[
                const SizedBox(height: 8),
                _WinratePanel(
                  points: ([
                    for (final e in _blackWinrateByHand.entries)
                      (e.key, e.value),
                  ]..sort((a, b) => a.$1.compareTo(b.$1))),
                  currentHand: game.moves.length,
                ),
              ],
              const SizedBox(height: 8),
              if (_analysisEnabled)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      OutlinedButton(
                        key: const ValueKey('game_analysis_cancel'),
                        onPressed: _cancelAnalysis,
                        child: const Text('取消'),
                      ),
                    ],
                  ),
                ),
              if (_moveStyle == MoveStyle.confirm) ...[
                const SizedBox(height: 8),
                _SelectionBar(
                  selected: _selected,
                  isLegal: _selected != null &&
                      game.board.isLegal(game.humanColor, _selected!.$1,
                          _selected!.$2),
                  onCancel: () => setState(() => _selected = null),
                  onPlace: _placeSelected,
                ),
              ],
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

  /// 系统返回拦截：本页禁止返回；约 2 秒内再次返回弹「放弃对局」确认。
  void _handleBack() {
    final game = ref.read(gameControllerProvider);
    if (game.finished) {
      Navigator.of(context).pop();
      return;
    }
    final now = DateTime.now();
    final last = _lastBackAt;
    _lastBackAt = now;
    if (last != null && now.difference(last) < const Duration(seconds: 2)) {
      _confirmAbandon();
    } else {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
          content: Text('再按一次返回可放弃本局并回到首页'),
          duration: Duration(milliseconds: 1200),
        ));
    }
  }

  /// 放弃对局确认：弃局终止（历史记「弃」、清存档），回到首页。
  ///
  /// 赛事对局弃局 = 判负：仅退出到赛程页，由赛程页既有流程判负结算并返回首页。
  Future<void> _confirmAbandon() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('放弃对局'),
        content: const Text('是否放弃当前对局并回到首页？\n放弃后本局记入历史（弃），无法续弈。'),
        actions: [
          TextButton(
            key: const ValueKey('abandon_cancel'),
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const ValueKey('abandon_confirm'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('放弃'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    ref.read(gameControllerProvider.notifier).abandon();
    if (widget.source == GameSource.career) {
      Navigator.of(context).pop();
    } else {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  /// 保存对局：弹确认后中断并保存，回到首页（可日后续弈）。
  Future<void> _saveGame() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('保存对局'),
        content: const Text('中断本局并保存？之后可从首页继续本局。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const ValueKey('game_save_confirm'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final history = [
      for (final e in _blackWinrateByHand.entries) (e.key, e.value),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    await ref
        .read(gameControllerProvider.notifier)
        .saveAndInterrupt(winrateHistory: history);
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
    messenger.showSnackBar(
      const SnackBar(content: Text('对局已保存，可从首页继续本局')),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({
    required this.game,
    required this.humanName,
    required this.aiName,
  });

  final GameState game;
  final String humanName;
  final String aiName;

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
              child: _PlayerInfo(
                name: humanName,
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
              child: _PlayerInfo(
                name: aiName,
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
    return Row(
      mainAxisAlignment:
          alignEnd ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: [
        if (!alignEnd) _stone(color),
        if (!alignEnd) const SizedBox(width: 8),
        Flexible(
          child: Column(
            crossAxisAlignment:
                alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color:
                            isTurn ? GoColors.pine : GoColors.textPrimary,
                      ),
                    ),
                  ),
                  if (isTurn) ...[
                    const SizedBox(width: 6),
                    const _ThinkingTag(),
                  ],
                ],
              ),
              Text(
                '提 $captured',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: GoColors.textSecondary),
              ),
            ],
          ),
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

/// 顶部卡片上的「思考中」tag（轮到该方时显示，替代原绿点）。
class _ThinkingTag extends StatelessWidget {
  const _ThinkingTag();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: GoColors.pine,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '思考中',
            style: theme.textTheme.labelSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// 黑方胜率曲线面板：Y 轴 0~1（0/0.5/1 刻度），横轴手数。
class _WinratePanel extends StatelessWidget {
  const _WinratePanel({required this.points, required this.currentHand});

  /// (手数, 黑方胜率 0..1)，按手数升序。
  final List<(int, double)> points;
  final int currentHand;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const ValueKey('winrate_panel'),
      height: 104,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      clipBehavior: Clip.antiAlias,
      child: CustomPaint(
        painter: _WinratePainter(
          points: points,
          currentHand: currentHand,
          tickStyle: theme.textTheme.labelSmall?.copyWith(
            color: GoColors.textSecondary,
          ),
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _WinratePainter extends CustomPainter {
  _WinratePainter({
    required this.points,
    required this.currentHand,
    required this.tickStyle,
  });

  final List<(int, double)> points;
  final int currentHand;
  final TextStyle? tickStyle;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 30.0;
    const right = 8.0;
    const top = 10.0;
    const bottom = 22.0;
    final plotW = size.width - left - right;
    final plotH = size.height - top - bottom;
    final maxHand = currentHand < 1 ? 1 : currentHand;

    double xOf(int hand) =>
        left + (maxHand <= 0 ? 0 : hand / maxHand * plotW);
    double yOf(double wr) =>
        top + (1 - wr.clamp(0.0, 1.0)) * plotH;

    // 参考线（0/0.5/1）与 Y 轴数值刻度。
    final grid = Paint()
      ..color = GoColors.outlineVariant.withValues(alpha: 0.7)
      ..strokeWidth = 1;
    for (final v in const [0.0, 0.5, 1.0]) {
      final y = yOf(v);
      canvas.drawLine(Offset(left, y), Offset(left + plotW, y), grid);
      final label = TextPainter(
        text: TextSpan(
          text: v == 0 ? '0' : (v == 0.5 ? '0.5' : '1'),
          style: tickStyle,
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(
          canvas, Offset(left - 4 - label.width, y - label.height / 2));
    }

    // 手数刻度。
    if (maxHand >= 1) {
      final step = maxHand > 20 ? 4 : (maxHand > 8 ? 2 : 1);
      for (var h = 0; h <= maxHand; h += step) {
        final x = xOf(h);
        final tp = TextPainter(
          text: TextSpan(text: '$h', style: tickStyle),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(x - tp.width / 2, top + plotH + 4));
      }
    }

    if (points.isEmpty) {
      final hint = TextPainter(
        text: TextSpan(
          text: '暂无胜率数据',
          style: tickStyle?.copyWith(color: GoColors.textSecondary),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      hint.paint(
        canvas,
        Offset(left + (plotW - hint.width) / 2,
            top + (plotH - hint.height) / 2),
      );
      return;
    }

    // 折线：黑方胜率。
    final linePaint = Paint()
      ..color = const Color(0xFF2B2926)
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final (h, wr) = points[i];
      final p = Offset(xOf(h), yOf(wr));
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    canvas.drawPath(path, linePaint);

    // 采样点。
    final dotPaint = Paint()..color = const Color(0xFF2B2926);
    for (final (h, wr) in points) {
      canvas.drawCircle(Offset(xOf(h), yOf(wr)), 2.2, dotPaint);
    }
  }

  @override
  bool shouldRepaint(_WinratePainter oldDelegate) => true;
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

/// 两步落子选点栏（确认模式）：显示所选坐标，确认落子或取消。
class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.selected,
    required this.isLegal,
    required this.onCancel,
    required this.onPlace,
  });

  final (int, int)? selected;
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
          _coord(sel),
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
        FilledButton(
          key: const ValueKey('game_place'),
          onPressed: isLegal ? onPlace : null,
          child: const Text('落子'),
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
            label: '停手',
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
