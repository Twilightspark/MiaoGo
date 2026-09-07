import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miaogo/core/move.dart';
import 'package:miaogo/core/rules.dart';
import 'package:miaogo/game/watch_controller.dart';

ProviderContainer makeContainer() {
  final container = ProviderContainer(overrides: [
    watchControllerProvider.overrideWith(WatchController.new),
  ]);
  addTearDown(container.dispose);
  return container;
}

void startGame(ProviderContainer container) {
  container.read(watchControllerProvider.notifier).start(
        size: 9,
        rule: GoRule.chinese,
        komi: 7.5,
        rankIndex: 8,
        blackName: '黑侠',
        whiteName: '白喵',
      );
}

/// 模拟一次引擎思考并落子。
bool play(ProviderContainer container, int row, int col) {
  final notifier = container.read(watchControllerProvider.notifier);
  notifier.beginThinking();
  final s = container.read(watchControllerProvider);
  return notifier.applyMove(Move.point(s.turn, row, col));
}

/// 模拟一次引擎思考并停一手。
bool playPass(ProviderContainer container) {
  final notifier = container.read(watchControllerProvider.notifier);
  notifier.beginThinking();
  final s = container.read(watchControllerProvider);
  return notifier.applyMove(Move.pass(s.turn));
}

void main() {
  test('开局：黑先、双方名/等级写入、空盘未终局', () {
    final container = makeContainer();
    startGame(container);
    final s = container.read(watchControllerProvider);
    expect(s.boardSize, 9);
    expect(s.rule, GoRule.chinese);
    expect(s.komi, 7.5);
    expect(s.rankIndex, 8);
    expect(s.blackName, '黑侠');
    expect(s.whiteName, '白喵');
    expect(s.turn, PlayerColor.black);
    expect(s.thinking, isFalse);
    expect(s.finished, isFalse);
    expect(s.moves, isEmpty);
    expect(s.moveCount, 0);
  });

  test('交替落子：黑白轮流、手数累计、思考标志复位', () {
    final container = makeContainer();
    startGame(container);

    expect(play(container, 4, 4), isTrue);
    var s = container.read(watchControllerProvider);
    expect(s.turn, PlayerColor.white);
    expect(s.moves, hasLength(1));
    expect(s.moves.single.color, PlayerColor.black);
    expect(s.thinking, isFalse);

    expect(play(container, 2, 2), isTrue);
    s = container.read(watchControllerProvider);
    expect(s.turn, PlayerColor.black);
    expect(s.moves, hasLength(2));
    expect(s.moves.last.color, PlayerColor.white);
  });

  test('思考窗口外/行棋方不符的落子被忽略', () {
    final container = makeContainer();
    startGame(container);
    // 未 beginThinking：窗口外落子被忽略。
    expect(
        container
            .read(watchControllerProvider.notifier)
            .applyMove(Move.point(PlayerColor.black, 4, 4)),
        isFalse);

    // beginThinking 后落白子（当前应黑先）被忽略。
    container.read(watchControllerProvider.notifier).beginThinking();
    expect(
        container
            .read(watchControllerProvider.notifier)
            .applyMove(Move.point(PlayerColor.white, 4, 4)),
        isFalse);
  });

  test('黑围提白：提子计数正确', () {
    final container = makeContainer();
    startGame(container);
    // 白 (4,4) 被黑 (3,4)(5,4)(4,3)(4,5) 围提；白方其余应手停一手。
    play(container, 3, 4);
    play(container, 4, 4); // 白子被围目标
    play(container, 5, 4);
    playPass(container); // 白停（不构成双停，黑仍在走）
    play(container, 4, 3);
    playPass(container);
    expect(play(container, 4, 5), isTrue); // 提 (4,4)
    final s = container.read(watchControllerProvider);
    expect(s.capturedBlack, 1);
    expect(s.capturedWhite, 0);
    expect(s.moves, hasLength(7));
  });

  test('非法着降级为 PASS：占位重复落子不成真着', () {
    final container = makeContainer();
    startGame(container);
    expect(play(container, 4, 4), isTrue);
    // 白手同点非法 → 引擎着判为 PASS（仍计一手）。
    expect(play(container, 4, 4), isTrue);
    final s = container.read(watchControllerProvider);
    expect(s.moves, hasLength(2));
    expect(s.moves.first.isPass, isFalse);
    expect(s.moves.last.isPass, isTrue);
  });

  test('双方连续 PASS：终局并按规则数子给出胜者', () {
    final container = makeContainer();
    startGame(container);
    expect(playPass(container), isTrue);
    expect(playPass(container), isTrue);
    final s = container.read(watchControllerProvider);
    expect(s.finished, isTrue);
    expect(s.result, isNotNull);
    expect(s.consecutivePasses, 2);
    // 空盘：黑 0，白 0 + 贴目 7.5 → 白胜。
    expect(s.winner, PlayerColor.white);
  });

  test('终局后落子忽略', () {
    final container = makeContainer();
    startGame(container);
    playPass(container);
    playPass(container);
    final notifier = container.read(watchControllerProvider.notifier);
    notifier.beginThinking();
    expect(notifier.applyMove(Move.point(PlayerColor.black, 4, 4)), isFalse);
  });
}
