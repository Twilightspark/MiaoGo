import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:miaogo/core/board.dart';
import 'package:miaogo/core/move.dart';
import 'package:miaogo/core/rules.dart';
import 'package:miaogo/core/scoring.dart';
import 'package:miaogo/core/sgf.dart';

/// SGF 规则字符串 → 应用规则（未知/旧中国规则按中国数子兜底）。
GoRule ruleFromSgf(String? ru) {
  switch (ru?.trim().toLowerCase()) {
    case 'korean':
      return GoRule.korean;
    case 'japanese':
      return GoRule.japanese;
    default:
      // 含 `Old Chinese` / 空 / 其它规则：统一按中国数子计分。
      return GoRule.chinese;
  }
}

/// 复盘/回看模式。
enum ReviewMode {
  /// 历史回放：沿主变化逐步跳转，棋盘只读。
  view,

  /// 试下：在定格手位继续人工交替黑白落子（不写回棋谱）。
  tryPlay,
}

/// 复盘状态：主变化链 + 当前手位 + 该位局面（棋盘按棋步重放重建）。
class ReviewState {
  const ReviewState({
    required this.game,
    required this.mainline,
    required this.index,
    required this.board,
    required this.moves,
    required this.rule,
    required this.komi,
    this.mode = ReviewMode.view,
    this.tryMoves = const [],
  });

  final SgfGame game;

  /// 主变化节点链（含根节点，下标 0 = 根）。
  final List<SgfNode> mainline;

  /// 当前主链手位。试下期间固定为进入试下时的定格手位。
  final int index;

  /// 当前局面（主链已放至 [index] 的棋步 + 试下新增棋步）。
  final GoBoard board;

  /// 已应用的棋步（含 PASS；试下期间含 [tryMoves]）。
  final List<Move> moves;

  final GoRule rule;
  final double komi;
  final ReviewMode mode;

  /// 试下期间新增的棋步（主链定格手位之后）。
  final List<Move> tryMoves;

  bool get inTry => mode == ReviewMode.tryPlay;

  bool get atStart => index <= 0;
  bool get atEnd => index >= mainline.length - 1;

  int get boardSize => board.size;

  /// 试下期间新增棋步中连续 PASS 数（用于双 PASS 终局判定）。
  int get tryTrailingPasses {
    var n = 0;
    for (final m in tryMoves.reversed) {
      if (!m.isPass) break;
      n++;
    }
    return n;
  }

  /// 试下中连续两手 PASS → 视同该次试下终局（棋盘停止落子，可点目/悔棋/返回）。
  bool get tryEnded => inTry && tryTrailingPasses >= 2;

  /// 轮到行棋方（无棋步默认黑；否则上一手之对方）。
  PlayerColor get toMove =>
      moves.isEmpty ? PlayerColor.black : moves.last.color.opposite;

  /// 当前手位注释（`C[]`；无则 null）。试下期间不展示历史注释。
  String? get comment =>
      mode == ReviewMode.view ? mainline[index].comment : null;

  /// 当前手位 SGF 文本坐标（如 `E4`）或 null（根/无棋步）。
  String? get moveText {
    if (mode == ReviewMode.tryPlay && moves.isNotEmpty) {
      return _coordOf(moves.last);
    }
    final m = mainline[index].move;
    if (m == null) return null;
    return _coordOf(m);
  }

  static String? _coordOf(Move m) {
    if (m.isPass) return 'PASS';
    return '${GoBoard.letters[m.col!].toUpperCase()}${m.row! + 1}';
  }

  /// 以当前局面计分（数子/数目按 [rule]）。
  ScoreResult score() => scoreGame(board, rule: rule, komi: komi);
}

/// 复盘控制器：加载棋谱、逐步回放、试下。
///
/// 每次状态变化按「重放建盘」重建棋盘（captures/打劫与历史一致），
/// 与对局悔棋同模式；棋盘以 `superko: false` 建盘，避免外部导入/观赛棋谱的
/// 旧规则着法被位置超劫误拦。试下为临时行棋，不写回棋谱/历史。
class ReviewController extends Notifier<ReviewState?> {
  @override
  ReviewState? build() => null;

  /// 加载一局棋谱（初始在开局手位）。
  void load(SgfGame game) {
    final rule = ruleFromSgf(game.rulesProp);
    final komi = game.komi ?? rule.defaultKomi;
    state = _buildState(game, game.mainline, 0, rule, komi);
  }

  /// 跳转到任意主链手位（自动夹取到合法范围；试下期间忽略跳转）。
  void jumpTo(int index) {
    final s = state;
    if (s == null || s.inTry) return;
    final clamped = index.clamp(0, s.mainline.length - 1);
    state = _buildState(s.game, s.mainline, clamped, s.rule, s.komi);
  }

  void next() => jumpTo((state?.index ?? 0) + 1);
  void prev() => jumpTo((state?.index ?? 0) - 1);
  void first() => jumpTo(0);
  void last() => jumpTo(state?.mainline.length ?? 0);

  /// 进入试下：在当前主链手位定格，开始人工交替黑白落子。
  void enterTry() {
    final s = state;
    if (s == null || s.inTry) return;
    state = _buildState(s.game, s.mainline, s.index, s.rule, s.komi,
        mode: ReviewMode.tryPlay);
  }

  /// 退出试下：恢复到进入试下时的历史对局局面。
  void exitTry() {
    final s = state;
    if (s == null || !s.inTry) return;
    state = _buildState(s.game, s.mainline, s.index, s.rule, s.komi);
  }

  /// 试下落子（轮到方自动黑白交替）；成功返回 true。
  bool placeTryMove(int row, int col) {
    final s = state;
    if (s == null || !s.inTry || s.tryEnded) return false;
    final color = s.toMove;
    final probe = s.board.clone(superko: false);
    if (!probe.play(color, row, col)) return false;
    state = _buildState(s.game, s.mainline, s.index, s.rule, s.komi,
        mode: ReviewMode.tryPlay,
        tryMoves: [...s.tryMoves, Move.point(color, row, col)]);
    return true;
  }

  /// 试下停手（当前方 PASS）；连续两次 PASS 视同终局。
  void tryPass() {
    final s = state;
    if (s == null || !s.inTry || s.tryEnded) return;
    state = _buildState(s.game, s.mainline, s.index, s.rule, s.komi,
        mode: ReviewMode.tryPlay,
        tryMoves: [...s.tryMoves, Move.pass(s.toMove)]);
  }

  /// 试下悔棋：撤销最后一手试下棋步（不触碰主链历史）。
  void undoTry() {
    final s = state;
    if (s == null || !s.inTry || s.tryMoves.isEmpty) return;
    state = _buildState(
        s.game, s.mainline, s.index, s.rule, s.komi,
        mode: ReviewMode.tryPlay,
        tryMoves: s.tryMoves.sublist(0, s.tryMoves.length - 1));
  }

  ReviewState _buildState(
      SgfGame game, List<SgfNode> mainline, int index, GoRule rule, double komi,
      {ReviewMode mode = ReviewMode.view,
      List<Move> tryMoves = const []}) {
    final size = game.size ?? 19;
    final board = GoBoard(size: size, superko: false);
    for (final (r, c) in game.setupBlack) {
      if (board.inBounds(r, c)) board.setStone(r, c, PlayerColor.black);
    }
    for (final (r, c) in game.setupWhite) {
      if (board.inBounds(r, c)) board.setStone(r, c, PlayerColor.white);
    }
    for (final (r, c) in game.setupEmpty) {
      if (board.inBounds(r, c)) board.clearPoint(r, c);
    }
    final moves = <Move>[];
    for (var i = 1; i <= index && i < mainline.length; i++) {
      final m = mainline[i].move;
      if (m == null) continue;
      if (m.isPass) {
        moves.add(m);
        continue;
      }
      // 非法重放（旧规则打劫等罕见情形）：容忍跳过，不破坏复盘。
      if (board.play(m.color, m.row!, m.col!)) {
        moves.add(m);
      }
    }
    for (final m in tryMoves) {
      if (m.isPass) {
        moves.add(m);
        continue;
      }
      if (board.play(m.color, m.row!, m.col!)) {
        moves.add(m);
      }
    }
    return ReviewState(
      game: game,
      mainline: mainline,
      index: index,
      board: board,
      moves: moves,
      rule: rule,
      komi: komi,
      mode: mode,
      tryMoves: tryMoves,
    );
  }
}

final reviewControllerProvider =
    NotifierProvider<ReviewController, ReviewState?>(ReviewController.new);
