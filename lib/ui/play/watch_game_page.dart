import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:miaogo/app_theme.dart';
import 'package:miaogo/core/move.dart';
import 'package:miaogo/core/rank.dart';
import 'package:miaogo/core/rules.dart';
import 'package:miaogo/core/sgf.dart';
import 'package:miaogo/engine/analysis.dart';
import 'package:miaogo/engine/engine_controller.dart';
import 'package:miaogo/engine/katago_engine.dart';
import 'package:miaogo/game/career.dart';
import 'package:miaogo/game/match_engine.dart';
import 'package:miaogo/game/watch_controller.dart';
import 'package:miaogo/storage/record_store.dart';
import 'package:miaogo/ui/board_widget.dart';
import 'package:miaogo/ui/common/winrate_panel.dart';

/// 休闲观赛对局页：两名本地 KataGo 棋手（同名同级）自动互弈，用户纯旁观。
///
/// - 顶栏仅「实时分析」与「退出（不保存）」两个按钮。
/// - 顶部为双方棋手卡（随机名 + 等级 + 提子数 + 思考中标识），中部棋盘
///   （每手展示间隔 [minMoveGap]，默认 [kWatchMinMoveGap]，最新落子额外高亮提醒），
///   底部为双方胜率曲线面板。
/// - 系统返回需**连按两次**才弹出「提前终止观赛」确认（防止误触直接退出）。
/// - 终局弹窗展示胜负并给出「保存到棋谱 / 退出」选择；退出不写任何记录。
class WatchGamePage extends ConsumerStatefulWidget {
  const WatchGamePage({
    super.key,
    required this.size,
    required this.rule,
    required this.komi,
    required this.rankIndex,
    this.minMoveGap = kWatchMinMoveGap,
  });

  /// 每手至少展示间隔（测试注入可缩短；生产固定 [kWatchMinMoveGap]）。
  final Duration minMoveGap;

  final int size;
  final GoRule rule;
  final double komi;

  /// 双方棋手共用等级（双方同棋力）。
  final int rankIndex;

  @override
  ConsumerState<WatchGamePage> createState() => _WatchGamePageState();
}

/// 每手最小展示间隔（不足该时长会等待补齐，防止观众来不及反应）。
/// 观赛设置页可按「棋手落子时间」覆盖；未指定时沿用本默认值。
const Duration kWatchMinMoveGap = Duration(seconds: 10);

/// 观赛「领地分析」单局面搜索预算（中性分析参数，短促即可，避免影响落子节奏）。
const int _kWatchAnalysisVisits = 250;
const int _kWatchAnalysisTimeMs = 2000;

class _WatchGamePageState extends ConsumerState<WatchGamePage> {
  late String _blackName;
  late String _whiteName;

  /// 本页驱动会话号：递增即作废在途的自动行棋任务。
  int _epoch = 0;

  /// 下一手计划展示时间（节流用）。
  late DateTime _nextApplyAt;

  /// 黑方胜率采样：(手数 → 黑方胜率 0..1)。
  final Map<int, double> _blackWinrateByHand = {};

  /// 实时领地热力图（分析开启后每手刷新）。
  List<List<double>>? _influence;
  bool _analysisEnabled = false;

  bool _resultDialogShown = false;
  bool _engineDialogShown = false;

  /// 上次系统返回时间（连按两次返回判定）。
  DateTime? _lastBackAt;

  KataGoMoveProvider? _lastProvider;

  @override
  void initState() {
    super.initState();
    final rng = Random();
    _blackName = CareerNames.aiPlayerName(rng);
    _whiteName = CareerNames.aiPlayerName(rng);
    var guard = 0;
    while (_whiteName == _blackName && guard++ < 20) {
      _whiteName = CareerNames.aiPlayerName(rng);
    }
    // 帧结束后再开局并启动自动行棋（避免在构建期修改 Provider）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(watchControllerProvider.notifier).start(
            size: widget.size,
            rule: widget.rule,
            komi: widget.komi,
            rankIndex: widget.rankIndex,
            blackName: _blackName,
            whiteName: _whiteName,
          );
      _epoch++;
      _nextApplyAt = DateTime.now().add(widget.minMoveGap);
      unawaited(_drive());
    });
  }

  @override
  void dispose() {
    _epoch++;
    final last = _lastProvider;
    if (last != null) {
      last.winrateListener = null;
    }
    super.dispose();
  }

  /// 引擎版选点器（双方同等级同一引擎）；未就绪抛错交给错误弹窗处理。
  KataGoMoveProvider _moveProvider() {
    final provider = ref.read(kataGoMoveProvider);
    if (provider == null) {
      throw const GtpEngineException('KataGo 引擎未就绪，无法继续观赛');
    }
    return provider;
  }

  Future<Move> _requestMove(PlayerColor color) async {
    final s = ref.read(watchControllerProvider);
    final provider = _moveProvider();
    // 每次搜索前把胜率监听挂到当前选点器实例上（引擎重启后实例重建）。
    provider.winrateListener = _onAiSearchWinrate;
    _lastProvider = provider;
    return provider.chooseMove(
      s.board.clone(),
      color,
      rankIndex: s.rankIndex,
    );
  }

  /// AI 搜索完成回调（行棋方 + 其视角胜率），转黑方视角记录。
  void _onAiSearchWinrate(PlayerColor sideToMove, double winrate) {
    if (!mounted) return;
    final hand = ref.read(watchControllerProvider).moves.length;
    _blackWinrateByHand[hand] =
        blackPerspectiveWinrate(winrate, sideToMove);
    setState(() {});
  }

  /// 自动行棋主循环：思考 → 补齐最小间隔 → 落子 → 分析刷新 → 下一手。
  Future<void> _drive() async {
    final epoch = _epoch;
    while (mounted && epoch == _epoch) {
      final s = ref.read(watchControllerProvider);
      if (s.finished) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _showResultDialog();
        });
        return;
      }
      ref.read(watchControllerProvider.notifier).beginThinking();
      setState(() {}); // 展示思考中
      final color = s.turn;
      Move move;
      try {
        move = await _requestMove(color);
      } catch (err) {
        if (mounted && epoch == _epoch) {
          await _handleEngineError(err);
        }
        return;
      }
      if (!mounted || epoch != _epoch) return;

      // 补足最小展示间隔。
      final target = _nextApplyAt;
      final now = DateTime.now();
      if (now.isBefore(target)) {
        await Future<void>.delayed(target.difference(now));
      }
      if (!mounted || epoch != _epoch) return;

      final ok =
          ref.read(watchControllerProvider.notifier).applyMove(move);
      if (!ok) return;
      _nextApplyAt = DateTime.now().add(widget.minMoveGap);
      if (ref.read(watchControllerProvider).finished) continue;

      if (_analysisEnabled) {
        await _refreshInfluence();
      }
    }
  }

  // ---- 实时分析 ----

  bool get _danReady =>
      ref.read(danEngineStatusProvider) == EngineStatus.ready;

  /// 单局面领地评估（大模型；用后归还引擎，避免与落子争抢）。
  Future<void> _refreshInfluence() async {
    final s = ref.read(watchControllerProvider);
    if (s.finished || s.moves.isEmpty) return;
    final engine = ref.read(kataGoDanEngineProvider);
    if (engine == null) {
      if (mounted) setState(() => _influence = null);
      return;
    }
    final toMove = s.turn;
    try {
      final r = await engine.searchAnalysis(
        board: s.board.clone(),
        toMove: toMove,
        rule: s.rule,
        komi: s.komi,
        maxVisits: _kWatchAnalysisVisits,
        maxTimeMs: _kWatchAnalysisTimeMs,
        ownership: true,
      );
      if (!mounted || !_analysisEnabled) return;
      final own = r.update?.ownership;
      setState(() {
        _influence = own == null
            ? null
            : ownershipToInfluence(own, s.boardSize, toMove);
      });
    } catch (_) {
      if (mounted && _analysisEnabled) {
        setState(() => _influence = null);
      }
    }
  }

  void _toggleAnalysis() {
    setState(() {
      _analysisEnabled = !_analysisEnabled;
      if (!_analysisEnabled) _influence = null;
    });
    if (_analysisEnabled) {
      unawaited(_refreshInfluence());
    }
  }

  // ---- 退出 / 引擎错误 ----

  /// 退出观赛（不保存）：作废在途行棋并回首页。
  void _exitWatch() {
    _epoch++;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  /// 系统返回拦截：本页禁止返回；对局结束后直接退出（由终局弹窗决定去留），
  /// 进行中须约 2 秒内**连按两次返回**才弹「提前终止观赛」确认。
  void _handleBack() {
    final s = ref.read(watchControllerProvider);
    if (s.finished) {
      _exitWatch();
      return;
    }
    final now = DateTime.now();
    final last = _lastBackAt;
    _lastBackAt = now;
    if (last != null && now.difference(last) < const Duration(seconds: 2)) {
      unawaited(_confirmAbort());
    } else {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
          content: Text('再按一次返回可提前终止观赛并回到首页'),
          duration: Duration(milliseconds: 1200),
        ));
    }
  }

  /// 提前终止观赛确认：确认后作废在途行棋并回首页（不保存、不入记录）。
  Future<void> _confirmAbort() async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('提前终止观赛'),
        content: const Text('是否提前终止本局观赛并回到首页？\n本局不会被保存。'),
        actions: [
          TextButton(
            key: const ValueKey('watch_abort_cancel'),
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const ValueKey('watch_abort_confirm'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('退出观赛'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) _exitWatch();
  }

  Future<void> _handleEngineError(Object error) async {
    if (_engineDialogShown) return;
    _engineDialogShown = true;
    final retry = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('引擎出错'),
        content: Text('KataGo 引擎异常，观赛暂时中断。\n$error'),
        actions: [
          TextButton(
            key: const ValueKey('watch_engine_quit'),
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('退出'),
          ),
          FilledButton(
            key: const ValueKey('watch_engine_retry'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('重试'),
          ),
        ],
      ),
    );
    _engineDialogShown = false;
    if (!mounted) return;
    if (retry != true) {
      _exitWatch();
      return;
    }
    final s = ref.read(watchControllerProvider);
    final isDan = s.rankIndex >= RankSystem.kNumKyuRanks;
    final notifier = isDan
        ? ref.read(danEngineStatusProvider.notifier)
        : ref.read(engineStatusProvider.notifier);
    await notifier.restart();
    if (!mounted) return;
    final status = isDan
        ? ref.read(danEngineStatusProvider)
        : ref.read(engineStatusProvider);
    if (status == EngineStatus.ready) {
      _epoch++;
      _nextApplyAt = DateTime.now().add(widget.minMoveGap);
      unawaited(_drive());
    } else {
      await _handleEngineError(notifier.lastError ?? '引擎仍不可用');
    }
  }

  // ---- 终局 ----

  Future<void> _showResultDialog() async {
    if (_resultDialogShown) return;
    _resultDialogShown = true;
    final save = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _WatchResultDialog(
        state: ref.read(watchControllerProvider),
      ),
    );
    if (!mounted) return;
    if (save == true) {
      final messenger = ScaffoldMessenger.of(context);
      final store = ref.read(recordStoreProvider.notifier);
      final record = _buildRecord();
      // 先回首页，再异步落库并提示（与既有棋谱写入一致，不阻塞返回）。
      Navigator.of(context).popUntil((route) => route.isFirst);
      unawaited(() async {
        await store.add(record);
        messenger.showSnackBar(
          const SnackBar(content: Text('棋局已保存到棋谱')),
        );
      }());
    } else {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  /// 构造本局棋谱记录（来源：观赛）。观赛不影响个人积分/段位。
  GameRecord _buildRecord() {
    final s = ref.read(watchControllerProvider);
    final winner = s.winner;
    final result = s.result;
    final isDraw = result != null && result.winner == null;
    final re = isDraw
        ? 'Draw'
        : '${winner == PlayerColor.black ? 'B' : 'W'}+'
            '${_fmtMargin(result?.margin)}';
    return GameRecord(
      id: '${DateTime.now().millisecondsSinceEpoch}',
      date: DateTime.now(),
      opponentName: '$_blackName 对 $_whiteName',
      opponentRank: s.rankIndex,
      result: isDraw
          ? GameResult.draw
          : (winner == PlayerColor.black
              ? GameResult.win
              : GameResult.loss),
      boardSize: s.boardSize,
      rule: s.rule,
      komi: s.komi,
      sgfPath: '',
      source: GameSource.watch,
      moveCount: s.moveCount,
      blackName: s.blackName,
      whiteName: s.whiteName,
      sgfContent: Sgf.build(
        size: s.boardSize,
        rules: s.rule.name,
        komi: s.komi,
        blackName: s.blackName,
        whiteName: s.whiteName,
        result: re,
        moves: s.moves,
      ),
    );
  }

  // ---- 构建 ----

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(watchControllerProvider);
    final lastMove =
        state.moves.isNotEmpty ? state.moves.last : null;
    final points = ([
      for (final e in _blackWinrateByHand.entries) (e.key, e.value),
    ]..sort((a, b) => a.$1.compareTo(b.$1)));

    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          centerTitle: true,
          title: Text(
            '休闲观赛 · ${RankSystem.rankName(state.rankIndex)}',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
          ),
          actions: [
            IconButton(
              key: const ValueKey('watch_analysis'),
              tooltip: '实时分析',
              icon: Icon(
                Icons.radar,
                color: _analysisEnabled ? GoColors.pine : null,
              ),
              onPressed: _danReady ? _toggleAnalysis : null,
            ),
            IconButton(
              key: const ValueKey('watch_exit'),
              tooltip: '退出（不保存）',
              icon: const Icon(Icons.close),
              onPressed: _exitWatch,
            ),
          ],
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Column(
              children: [
                _StatusCard(state: state),
                const SizedBox(height: 8),
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 480),
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: GoBoardWidget(
                          board: state.board,
                          lastMove: lastMove,
                          lastMoveEmphasis: true,
                          influence:
                              _analysisEnabled ? _influence : null,
                          enabled: false,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                WinratePanel(
                  points: points,
                  currentHand: state.moveCount,
                  showWhiteLine: true,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 顶部双方棋手卡（参考人机对弈状态栏；含等级与提子数）。
class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.state});

  final WatchState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final turn = state.turn;
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: _PlayerInfo(
                name: state.blackName,
                rankIndex: state.rankIndex,
                color: PlayerColor.black,
                captured: state.capturedBlack,
                isTurn: state.thinking && !state.finished && turn == PlayerColor.black,
                alignEnd: false,
              ),
            ),
            Column(
              children: [
                Text(
                  state.finished
                      ? '对局结束'
                      : (state.thinking
                          ? '轮到 ${turn.label}方'
                          : '观赛进行中'),
                  key: const ValueKey('watch_status'),
                  style: theme.textTheme.labelMedium
                      ?.copyWith(color: GoColors.pine),
                ),
                const SizedBox(height: 2),
                Text(
                  '第 ${state.moveCount} 手',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: GoColors.textSecondary),
                ),
              ],
            ),
            Expanded(
              child: _PlayerInfo(
                name: state.whiteName,
                rankIndex: state.rankIndex,
                color: PlayerColor.white,
                captured: state.capturedWhite,
                isTurn: state.thinking && !state.finished && turn == PlayerColor.white,
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
    required this.rankIndex,
    required this.color,
    required this.captured,
    required this.isTurn,
    required this.alignEnd,
  });

  final String name;
  final int rankIndex;
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
                  if (isTurn && alignEnd) ...[
                    const _ThinkingTag(),
                    const SizedBox(width: 6),
                  ],
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
                  if (isTurn && !alignEnd) ...[
                    const SizedBox(width: 6),
                    const _ThinkingTag(),
                  ],
                ],
              ),
              Text(
                '${RankSystem.rankName(rankIndex)} · 提 $captured',
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

/// 「思考中」tag（轮到该方时显示）。
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

/// 终局弹窗：胜负信息 + 「保存到棋谱 / 退出」。
class _WatchResultDialog extends StatelessWidget {
  const _WatchResultDialog({required this.state});

  final WatchState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final winner = state.winner;
    final result = state.result;

    String headline;
    Color headlineColor;
    if (winner == null) {
      headline = '和棋';
      headlineColor = GoColors.wood;
    } else {
      final winnerName = winner == PlayerColor.black
          ? state.blackName
          : state.whiteName;
      headline = '${winner.label}方 $winnerName 胜';
      headlineColor = winner == PlayerColor.black
          ? GoColors.textPrimary
          : GoColors.pine;
    }

    return AlertDialog(
      title: const Text('对局结束'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Text(
              headline,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: headlineColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          if (result != null) ...[
            const SizedBox(height: 6),
            Center(
              child: Text(
                result.description,
                style: theme.textTheme.titleSmall
                    ?.copyWith(color: GoColors.textSecondary),
              ),
            ),
            const SizedBox(height: 12),
            for (final line in result.details.take(3))
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(line, style: theme.textTheme.bodySmall),
              ),
          ],
          const SizedBox(height: 12),
          Divider(color: theme.colorScheme.outlineVariant),
          Text(
            '${state.blackName} 对 ${state.whiteName} · '
            '${state.rule.label}规则 · 贴目 ${state.komi} · '
            '${state.boardSize} 路 · 共 ${state.moveCount} 手',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: GoColors.textSecondary),
          ),
        ],
      ),
      actions: [
        OutlinedButton(
          key: const ValueKey('watch_result_exit'),
          onPressed: () => Navigator.pop(context, false),
          child: const Text('退出'),
        ),
        FilledButton.icon(
          key: const ValueKey('watch_result_save'),
          onPressed: () => Navigator.pop(context, true),
          icon: const Icon(Icons.save_outlined, size: 18),
          label: const Text('保存到棋谱'),
        ),
      ],
    );
  }
}

/// 目差展示：整数省略小数点（如 1.5 / 2）。
String _fmtMargin(double? margin) {
  if (margin == null) return 'R';
  if (margin == margin.roundToDouble()) return '${margin.round()}';
  return margin.toStringAsFixed(1);
}
