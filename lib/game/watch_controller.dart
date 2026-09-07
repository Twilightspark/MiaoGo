import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:miaogo/core/board.dart';
import 'package:miaogo/core/move.dart';
import 'package:miaogo/core/rules.dart';
import 'package:miaogo/core/scoring.dart';

/// 观赛对局状态（无真人参与的 AI 互弈，供休闲观赛页展示）。
///
/// 双方棋手为本地 KataGo 引擎角色，黑先白后依次落子；引擎调度/思考时长
/// （每手展示节奏按观赛设置「棋手落子时间」由观赛页驱动）由观赛页驱动，
/// 本控制器只负责纯棋盘状态机：
/// 落子/PASS/终局数子。终局后是否保存由用户决定，不在此自动写棋谱。
class WatchState {
  const WatchState({
    required this.boardSize,
    required this.rule,
    required this.komi,
    required this.rankIndex,
    required this.blackName,
    required this.whiteName,
    required this.board,
    required this.moves,
    required this.turn,
    required this.thinking,
    required this.finished,
    required this.result,
    required this.winner,
    required this.consecutivePasses,
  });

  factory WatchState.initial() => WatchState(
        boardSize: 9,
        rule: GoRule.chinese,
        komi: GoRule.chinese.defaultKomi,
        rankIndex: 0,
        blackName: '',
        whiteName: '',
        board: GoBoard(size: 9),
        moves: const [],
        turn: PlayerColor.black,
        thinking: false,
        finished: false,
        result: null,
        winner: null,
        consecutivePasses: 0,
      );

  final int boardSize;
  final GoRule rule;
  final double komi;

  /// 双方共用等级（观赛默认双方同棋力）。
  final int rankIndex;
  final String blackName;
  final String whiteName;
  final GoBoard board;
  final List<Move> moves;

  /// 当前行棋方（未开局时为黑）。
  final PlayerColor turn;

  /// 引擎思考中（含每手展示等待期）。
  final bool thinking;
  final bool finished;
  final ScoreResult? result;
  final PlayerColor? winner;
  final int consecutivePasses;

  /// 黑方提子数（顶部状态栏展示）。
  int get capturedBlack => board.capturesBlack;

  /// 白方提子数。
  int get capturedWhite => board.capturesWhite;

  /// 当前手数。
  int get moveCount => moves.length;

  WatchState copyWith({
    int? boardSize,
    GoRule? rule,
    double? komi,
    int? rankIndex,
    String? blackName,
    String? whiteName,
    GoBoard? board,
    List<Move>? moves,
    PlayerColor? turn,
    bool? thinking,
    bool? finished,
    Object? result = _unset,
    Object? winner = _unset,
    int? consecutivePasses,
  }) {
    return WatchState(
      boardSize: boardSize ?? this.boardSize,
      rule: rule ?? this.rule,
      komi: komi ?? this.komi,
      rankIndex: rankIndex ?? this.rankIndex,
      blackName: blackName ?? this.blackName,
      whiteName: whiteName ?? this.whiteName,
      board: board ?? this.board,
      moves: moves ?? this.moves,
      turn: turn ?? this.turn,
      thinking: thinking ?? this.thinking,
      finished: finished ?? this.finished,
      result: identical(result, _unset) ? this.result : result as ScoreResult?,
      winner: identical(winner, _unset) ? this.winner : winner as PlayerColor?,
      consecutivePasses: consecutivePasses ?? this.consecutivePasses,
    );
  }
}

const Object _unset = _Sentinel();

class _Sentinel {
  const _Sentinel();
}

/// 观赛对局状态机（见 [WatchState]）。
///
/// 控制器不含引擎细节：引擎选点/每手展示节流由观赛页驱动后调用 [applyMove]
/// 落子。PASS 连续两次即终局并按规则数子。
class WatchController extends Notifier<WatchState> {
  @override
  WatchState build() => WatchState.initial();

  /// 开局（黑先）。
  void start({
    required int size,
    required GoRule rule,
    required double komi,
    required int rankIndex,
    required String blackName,
    required String whiteName,
  }) {
    state = WatchState(
      boardSize: size,
      rule: rule,
      komi: komi,
      rankIndex: rankIndex,
      blackName: blackName,
      whiteName: whiteName,
      board: GoBoard(size: size),
      moves: const [],
      turn: PlayerColor.black,
      thinking: false,
      finished: false,
      result: null,
      winner: null,
      consecutivePasses: 0,
    );
  }

  /// 标记引擎思考中（观赛页发起一次引擎选点前调用；终局后忽略）。
  void beginThinking() {
    final s = state;
    if (s.finished) return;
    if (s.thinking) return;
    state = s.copyWith(thinking: true);
  }

  /// 引擎返回一手后落子；非法着按 PASS 处理。
  ///
  /// 返回 false 表示对局已终局/行棋方不符，棋步被忽略。
  bool applyMove(Move move) {
    final s = state;
    if (s.finished || s.thinking == false) {
      // 未在思考窗口内的消息（如离开页面后的迟到响应）一律忽略。
      return false;
    }
    if (move.color != s.turn) return false;
    if (move.isPass) {
      _applyPass(move.color);
      return true;
    }
    if (!s.board.play(move.color, move.row!, move.col!)) {
      // 非法着（引擎误判/劫争）降级为 PASS。
      _applyPass(move.color);
      return true;
    }
    state = s.copyWith(
      moves: [...s.moves, move],
      turn: move.color.opposite,
      consecutivePasses: 0,
      thinking: false,
    );
    return true;
  }

  void _applyPass(PlayerColor color) {
    final s = state;
    final passes = s.consecutivePasses + 1;
    final next = color.opposite;
    final moves = [...s.moves, Move.pass(color)];
    if (passes >= 2) {
      final result = scoreGame(s.board, rule: s.rule, komi: s.komi);
      state = WatchState(
        boardSize: s.boardSize,
        rule: s.rule,
        komi: s.komi,
        rankIndex: s.rankIndex,
        blackName: s.blackName,
        whiteName: s.whiteName,
        board: s.board,
        moves: moves,
        turn: next,
        thinking: false,
        finished: true,
        result: result,
        winner: result.winner,
        consecutivePasses: passes,
      );
      return;
    }
    state = s.copyWith(
      moves: moves,
      turn: next,
      consecutivePasses: passes,
      thinking: false,
    );
  }
}

final watchControllerProvider =
    NotifierProvider<WatchController, WatchState>(WatchController.new);
