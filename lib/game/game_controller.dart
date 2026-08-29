import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:miaogo/core/board.dart';
import 'package:miaogo/core/move.dart';
import 'package:miaogo/core/rank.dart';
import 'package:miaogo/core/rules.dart';
import 'package:miaogo/core/scoring.dart';
import 'package:miaogo/core/sgf.dart';
import 'package:miaogo/engine/engine_controller.dart';
import 'package:miaogo/game/match_engine.dart';
import 'package:miaogo/game/move_provider.dart';
import 'package:miaogo/storage/record_store.dart';
import 'package:miaogo/storage/user_store.dart';

/// 对局状态（不可变快照 + 可变 [board]；棋谱重放/悔棋时重建棋盘）。
class GameState {
  GameState.initial()
      : boardSize = 9,
        rule = GoRule.chinese,
        komi = GoRule.chinese.defaultKomi,
        humanColor = PlayerColor.black,
        aiColor = PlayerColor.white,
        difficulty = 0,
        board = GoBoard(size: 9),
        moves = const <Move>[],
        turn = PlayerColor.black,
        aiThinking = false,
        finished = false,
        result = null,
        winner = null,
        resignedBy = null,
        consecutivePasses = 0,
        suggestScoring = false,
        aiError = null;

  const GameState({
    required this.boardSize,
    required this.rule,
    required this.komi,
    required this.humanColor,
    required this.aiColor,
    required this.difficulty,
    required this.board,
    required this.moves,
    required this.turn,
    required this.aiThinking,
    required this.finished,
    required this.result,
    required this.winner,
    required this.resignedBy,
    required this.consecutivePasses,
    required this.suggestScoring,
    required this.aiError,
  });

  final int boardSize;
  final GoRule rule;
  final double komi;
  final PlayerColor humanColor;
  final PlayerColor aiColor;

  /// 对手段位索引 0..26（§8 难度映射）。
  final int difficulty;
  final GoBoard board;
  final List<Move> moves;
  final PlayerColor turn;
  final bool aiThinking;
  final bool finished;
  final ScoreResult? result;
  final PlayerColor? winner;
  final PlayerColor? resignedBy;
  final int consecutivePasses;

  /// 主动点目申请：地盘已基本定型且未被玩家拒绝。
  final bool suggestScoring;

  /// AI 引擎故障信息（非空 = 对局中止等待处理，不终局不计分）。
  final String? aiError;

  /// 玩家可落子（未终局、AI 未思考、轮到玩家、无引擎故障）。
  bool get isHumanTurn =>
      !finished &&
      !aiThinking &&
      turn == humanColor &&
      !resigned &&
      aiError == null;

  bool get resigned => resignedBy != null;

  /// 玩家提子数（状态栏展示；修复过显示反了的问题）。
  int get humanCaptured => humanColor == PlayerColor.black
      ? board.capturesBlack
      : board.capturesWhite;

  /// AI 提子数。
  int get aiCaptured =>
      aiColor == PlayerColor.black ? board.capturesBlack : board.capturesWhite;

  GameState copyWith({
    GoRule? rule,
    double? komi,
    GoBoard? board,
    List<Move>? moves,
    PlayerColor? turn,
    bool? aiThinking,
    bool? finished,
    Object? result = _unset,
    Object? winner = _unset,
    Object? resignedBy = _unset,
    int? consecutivePasses,
    bool? suggestScoring,
    Object? aiError = _unset,
  }) {
    return GameState(
      boardSize: boardSize,
      rule: rule ?? this.rule,
      komi: komi ?? this.komi,
      humanColor: humanColor,
      aiColor: aiColor,
      difficulty: difficulty,
      board: board ?? this.board,
      moves: moves ?? this.moves,
      turn: turn ?? this.turn,
      aiThinking: aiThinking ?? this.aiThinking,
      finished: finished ?? this.finished,
      result: identical(result, _unset) ? this.result : result as ScoreResult?,
      winner: identical(winner, _unset) ? this.winner : winner as PlayerColor?,
      resignedBy: identical(resignedBy, _unset)
          ? this.resignedBy
          : resignedBy as PlayerColor?,
      consecutivePasses: consecutivePasses ?? this.consecutivePasses,
      suggestScoring: suggestScoring ?? this.suggestScoring,
      aiError: identical(aiError, _unset) ? this.aiError : aiError as String?,
    );
  }
}

const Object _unset = _Sentinel();

class _Sentinel {
  const _Sentinel();
}

/// 地盘定型判定函数签名（可注入用于测试）。
typedef SettlednessCheck = bool Function(GoBoard board, int moveCount);

/// 对局状态机：人机/生涯共用；悔棋、PASS、认输、终局计分与棋谱保存。
///
/// AI 由 [MoveProvider] 提供（生产环境为 KataGo 引擎，测试注入脚本实现），
/// 思考在异步任务中执行，以会话号守卫避免悔棋/新局后过期 AI 响应误改状态。
/// 引擎故障时置 [GameState.aiError]，由 UI 提供重启/退出，不自动降级。
class GameController extends Notifier<GameState> {
  GameController({
    MoveProvider? ai,
    Duration thinkingDelay = const Duration(milliseconds: 300),
    SettlednessCheck? isSettled,
  })  : _explicitAi = ai,
        _thinkingDelay = thinkingDelay,
        _isSettled = isSettled ?? _defaultSettled;

  /// 测试注入的显式 AI（生产环境恒为 null）。
  final MoveProvider? _explicitAi;
  final Duration _thinkingDelay;
  final SettlednessCheck _isSettled;
  int _session = 0;
  bool _disposed = false;

  /// 本局对手名（生涯模式传 AI 中文名；null = 默认 `AI · 段位`）。
  String _opponentName = '';

  /// 本局棋谱来源（生涯对局用 [GameSource.career]）。
  GameSource _source = GameSource.ai;

  /// 本局主动点目申请被拒绝的次数（≥3 后不再申请）。
  int _scoreRefusals = 0;

  /// 当前 AI：测试注入优先，否则引擎；两者皆无抛错（生产由引擎门槛保证）。
  MoveProvider get _currentAi {
    final explicit = _explicitAi;
    if (explicit != null) return explicit;
    final engineAi = ref.read(kataGoMoveProvider);
    if (engineAi == null) {
      throw StateError('KataGo 引擎未就绪，无法继续对弈');
    }
    return engineAi;
  }

  static bool _defaultSettled(GoBoard board, int moveCount) =>
      analyzeSettledness(board, moveCount: moveCount).basicallySettled;

  @override
  GameState build() {
    ref.onDispose(() => _disposed = true);
    return GameState.initial();
  }

  /// 开局（人机/生涯共用参数）。
  ///
  /// [opponentName] 为空时默认 `AI · 段位`；[source] 标记棋谱来源
  /// （人机 [GameSource.ai] / 生涯 [GameSource.career]）。
  void startNewGame({
    required int size,
    required GoRule rule,
    required double komi,
    required PlayerColor humanColor,
    required int difficulty,
    String? opponentName,
    GameSource source = GameSource.ai,
  }) {
    _session++;
    _scoreRefusals = 0;
    _opponentName = opponentName ?? '';
    _source = source;
    state = GameState(
      boardSize: size,
      rule: rule,
      komi: komi,
      humanColor: humanColor,
      aiColor: humanColor.opposite,
      difficulty: difficulty,
      board: GoBoard(size: size),
      moves: const [],
      turn: PlayerColor.black,
      aiThinking: false,
      finished: false,
      result: null,
      winner: null,
      resignedBy: null,
      consecutivePasses: 0,
      suggestScoring: false,
      aiError: null,
    );
    if (state.aiColor == PlayerColor.black) _scheduleAi();
  }

  /// 玩家落子；成功返回 true 并调度 AI。
  bool placeStone(int row, int col) {
    final s = state;
    if (!s.isHumanTurn) return false;
    if (!s.board.play(s.humanColor, row, col)) return false;
    state = s.copyWith(
      moves: [...s.moves, Move.point(s.humanColor, row, col)],
      turn: s.aiColor,
      consecutivePasses: 0,
    );
    _scheduleAi();
    return true;
  }

  /// 玩家 PASS。
  void pass() {
    final s = state;
    if (!s.isHumanTurn) return;
    _applyPass(s.humanColor);
  }

  /// 玩家认输。
  void resign() {
    final s = state;
    if (!s.isHumanTurn) return;
    _session++;
    _finishByResign(s.humanColor);
  }

  /// 悔棋：撤销 AI 应手 + 玩家最后一手，回到玩家回合。
  /// 进行中的 AI 思考会被取消（会话号守卫）。
  void undo() {
    final s = state;
    if (s.finished || s.aiError != null) return;
    final moves = [...s.moves];
    if (moves.isEmpty) return;
    if (moves.last.color == s.aiColor) moves.removeLast();
    if (moves.isNotEmpty && moves.last.color == s.humanColor) {
      moves.removeLast();
    }
    _session++;
    final board = GoBoard(size: s.boardSize);
    for (final m in moves) {
      if (m.isPass) continue;
      board.play(m.color, m.row!, m.col!);
    }
    state = s.copyWith(
      board: board,
      moves: moves,
      turn: s.humanColor,
      aiThinking: false,
      finished: false,
      result: null,
      winner: null,
      resignedBy: null,
      consecutivePasses: 0,
      suggestScoring: false,
      aiError: null,
    );
  }

  /// 玩家主动点目：直接以当前局面计分终局。
  void scoreAndFinish() {
    final s = state;
    if (s.finished || s.moves.isEmpty || s.aiError != null) return;
    _session++;
    if (s.aiThinking) return;
    _finish();
  }

  /// 对局中切换规则/贴目（引擎侧同步；评分与后续棋谱随之变化）。
  Future<void> switchRule(GoRule rule, double komi) async {
    final s = state;
    if (s.rule == rule && s.komi == komi) return;
    state = s.copyWith(rule: rule, komi: komi);
    final engineAi = ref.read(kataGoMoveProvider);
    if (engineAi is KataGoMoveProvider) {
      await engineAi.updateRule(rule, komi);
    }
  }

  /// 拒绝主动点目申请；累计三次后本局不再申请。
  void refuseScoring() {
    final s = state;
    if (!s.suggestScoring) return;
    _scoreRefusals++;
    state = s.copyWith(suggestScoring: false);
  }

  void _maybeSuggestScoring() {
    final s = state;
    if (s.finished || s.suggestScoring || _scoreRefusals >= 3) return;
    if (_isSettled(s.board, s.moves.length)) {
      state = s.copyWith(suggestScoring: true);
    }
  }

  void _scheduleAi() {
    final s = state;
    if (s.finished || s.turn != s.aiColor || s.aiError != null) return;
    final session = _session;
    state = s.copyWith(aiThinking: true);
    unawaited(() async {
      await Future<void>.delayed(_thinkingDelay);
      if (_disposed || session != _session || state.finished) return;
      Move move;
      try {
        move = await _currentAi.chooseMove(state.board.clone(), state.aiColor,
            rankIndex: state.difficulty);
      } catch (e) {
        // 引擎故障：中止等待，交由 UI 重启/退出，不自动降级。
        if (_disposed || session != _session) return;
        state = state.copyWith(aiThinking: false, aiError: '$e');
        return;
      }
      if (_disposed || session != _session || state.finished) return;
      _applyAiMove(move);
    }());
  }

  /// 引擎重启成功后恢复对局：用当前棋盘（历史对弈记录）重发 AI 一手。
  void resumeAfterEngineRestart() {
    final s = state;
    if (s.aiError == null || s.finished) return;
    state = s.copyWith(aiError: null);
    _scheduleAi();
  }

  void _applyAiMove(Move move) {
    final s = state;
    if (move.isPass) {
      _applyPass(move.color);
      return;
    }
    if (!s.board.play(move.color, move.row!, move.col!)) {
      _applyPass(move.color);
      return;
    }
    state = s.copyWith(
      moves: [...s.moves, move],
      turn: move.color.opposite,
      consecutivePasses: 0,
      aiThinking: false,
    );
    if (state.turn == state.humanColor) _maybeSuggestScoring();
  }

  void _applyPass(PlayerColor color) {
    final s = state;
    final passes = s.consecutivePasses + 1;
    final moves = [...s.moves, Move.pass(color)];
    final next = color.opposite;
    if (passes >= 2) {
      state = s.copyWith(
        moves: moves,
        consecutivePasses: passes,
        turn: next,
        aiThinking: false,
      );
      _finish();
    } else {
      state = s.copyWith(
        moves: moves,
        consecutivePasses: passes,
        turn: next,
        aiThinking: false,
      );
      if (next == s.aiColor) {
        _scheduleAi();
      } else if (next == s.humanColor) {
        _maybeSuggestScoring();
      }
    }
  }

  void _finish() {
    final s = state;
    final result = scoreGame(s.board, rule: s.rule, komi: s.komi);
    state = s.copyWith(
      finished: true,
      aiThinking: false,
      result: result,
      winner: result.winner,
      suggestScoring: false,
    );
    unawaited(_saveRecord(winner: result.winner, result: result));
  }

  void _finishByResign(PlayerColor resigner) {
    final s = state;
    final winner = resigner.opposite;
    state = s.copyWith(
      finished: true,
      aiThinking: false,
      result: null,
      winner: winner,
      resignedBy: resigner,
      suggestScoring: false,
    );
    unawaited(_saveRecord(winner: winner, result: null));
  }

  Future<void> _saveRecord(
      {required PlayerColor? winner, required ScoreResult? result}) async {
    final s = state;
    final user = ref.read(userProfileProvider);
    final humanBlack = s.humanColor == PlayerColor.black;
    final humanName = user.name;
    final aiName = _opponentName.isNotEmpty
        ? _opponentName
        : 'AI · ${RankSystem.rankName(s.difficulty)}';
    final winnerColor = result?.winner ?? s.winner;
    final isDraw = result != null && result.winner == null;
    final re = isDraw
        ? 'Draw'
        : '${winnerColor == PlayerColor.black ? 'B' : 'W'}'
            '+${result?.margin ?? 'R'}';
    final record = GameRecord(
      id: '${DateTime.now().millisecondsSinceEpoch}',
      date: DateTime.now(),
      opponentName: aiName,
      opponentRank: s.difficulty,
      result: isDraw
          ? GameResult.draw
          : (winnerColor == s.humanColor
              ? GameResult.win
              : GameResult.loss),
      boardSize: s.boardSize,
      rule: s.rule,
      komi: s.komi,
      sgfPath: '',
      source: _source,
      moveCount: s.moves.length,
      sgfContent: Sgf.build(
        size: s.boardSize,
        rules: s.rule.name,
        komi: s.komi,
        blackName: humanBlack ? humanName : aiName,
        whiteName: humanBlack ? aiName : humanName,
        result: re,
        moves: s.moves,
      ),
    );
    await ref.read(recordStoreProvider.notifier).add(record);
  }
}

final gameControllerProvider =
    NotifierProvider<GameController, GameState>(GameController.new);
