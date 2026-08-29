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
  });

  final SgfGame game;

  /// 主变化节点链（含根节点，下标 0 = 根）。
  final List<SgfNode> mainline;

  /// 当前手位（0 = 根/开局）。
  final int index;

  /// 当前局面（布子 + 已重放棋步）。
  final GoBoard board;

  /// 已应用的棋步（不含布子；含 PASS）。
  final List<Move> moves;

  final GoRule rule;
  final double komi;

  bool get atStart => index == 0;
  bool get atEnd => index >= mainline.length - 1;

  int get boardSize => board.size;

  /// 轮到行棋方（无棋步默认黑；否则上一手之对方）。
  PlayerColor get toMove =>
      moves.isEmpty ? PlayerColor.black : moves.last.color.opposite;

  /// 当前手位注释（`C[]`）；无则 null。
  String? get comment => mainline[index].comment;

  /// 当前手位 SGF 文本坐标（如 `E4`）或 null（根/无棋步）。
  String? get moveText {
    final m = mainline[index].move;
    if (m == null) return null;
    if (m.isPass) return 'PASS';
    return '${GoBoard.letters[m.col!].toUpperCase()}${m.row! + 1}';
  }

  /// 以当前局面计分（数子/数目按 [rule]）。
  ScoreResult score() => scoreGame(board, rule: rule, komi: komi);
}

/// 复盘控制器：加载棋谱并跳转任意手位。
///
/// 每次跳转按「重放建盘」重建棋盘（captures/打劫与历史一致），
/// 与对局悔棋同模式；棋盘以 `superko: false` 建盘，避免历史名谱的
/// 旧规则着法被位置超劫误拦。
class ReviewController extends Notifier<ReviewState?> {
  @override
  ReviewState? build() => null;

  /// 加载一局棋谱（初始在开局手位）。
  void load(SgfGame game) {
    final rule = ruleFromSgf(game.rulesProp);
    final komi = game.komi ?? rule.defaultKomi;
    state = _buildState(game, game.mainline, 0, rule, komi);
  }

  /// 跳转到任意手位（自动夹取到合法范围）。
  void jumpTo(int index) {
    final s = state;
    if (s == null) return;
    final clamped = index.clamp(0, s.mainline.length - 1);
    state = _buildState(s.game, s.mainline, clamped, s.rule, s.komi);
  }

  void next() => jumpTo((state?.index ?? 0) + 1);
  void prev() => jumpTo((state?.index ?? 0) - 1);
  void first() => jumpTo(0);
  void last() => jumpTo(state?.mainline.length ?? 0);

  ReviewState _buildState(
      SgfGame game, List<SgfNode> mainline, int index, GoRule rule, double komi) {
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
    return ReviewState(
      game: game,
      mainline: mainline,
      index: index,
      board: board,
      moves: moves,
      rule: rule,
      komi: komi,
    );
  }
}

final reviewControllerProvider =
    NotifierProvider<ReviewController, ReviewState?>(ReviewController.new);
