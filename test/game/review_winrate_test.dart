import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:miaogo/core/move.dart';
import 'package:miaogo/core/rules.dart';
import 'package:miaogo/core/sgf.dart';
import 'package:miaogo/game/review_winrate.dart';

void main() {
  test('逐手计算黑方胜率：交替行棋方折算到黑方视角', () async {
    const sgf = '(;GM[1]SZ[9]RU[chinese]KM[7.5];B[aa];W[cc];B[bb];W[ee])';
    final game = Sgf.parse(sgf);
    final calls = <PlayerColor>[];
    final task = ReviewWinrateTask(
      game: game,
      rule: GoRule.chinese,
      komi: 7.5,
      eval: (board, toMove) async {
        calls.add(toMove);
        return toMove == PlayerColor.black ? 0.8 : 0.6;
      },
    );

    final ok = await task.runTo(4);
    expect(ok, isTrue);
    // 手 0..4 共 5 次评估，行棋方自黑起交替。
    expect(calls, [
      PlayerColor.black,
      PlayerColor.white,
      PlayerColor.black,
      PlayerColor.white,
      PlayerColor.black,
    ]);
    final m = task.results;
    expect(m.length, 5);
    expect(m[0], closeTo(0.8, 1e-9)); // 黑视角：黑 0.8
    expect(m[1], closeTo(0.4, 1e-9)); // 白 0.6 → 黑 0.4
    expect(m[2], closeTo(0.8, 1e-9));
    expect(m[3], closeTo(0.4, 1e-9));
    expect(m[4], closeTo(0.8, 1e-9));
  });

  test('跳过纯注释节点，手数只按实际棋步计', () async {
    // 节点 1 为无棋步注释节点。
    const sgf = '(;GM[1]SZ[9]RU[chinese];C[开局];B[aa];W[cc])';
    final game = Sgf.parse(sgf);
    final task = ReviewWinrateTask(
      game: game,
      rule: GoRule.chinese,
      komi: 7.5,
      eval: (board, toMove) async => 0.5,
    );

    expect(await task.runTo(3), isTrue); // 主链节点 3 = W[cc]（第 2 手）
    final m = task.results;
    expect(m.length, 3); // 手 0、1、2
    expect(m.keys, containsAll([0, 1, 2]));
  });

  test('断点续算：已算手数不再重复评估', () async {
    const sgf = '(;GM[1]SZ[9]RU[chinese];B[aa];W[cc];B[bb];W[ee])';
    final game = Sgf.parse(sgf);
    var count = 0;
    final task = ReviewWinrateTask(
      game: game,
      rule: GoRule.chinese,
      komi: 7.5,
      eval: (board, toMove) async {
        count++;
        return 0.5;
      },
    );

    expect(await task.runTo(2), isTrue);
    expect(task.results.length, 3);
    expect(count, 3);

    expect(await task.runTo(4), isTrue);
    expect(task.results.length, 5);
    expect(count, 5); // 只补算了 3、4 两处。
  });

  test('取消：中止后续评估，标记 isCancelled', () async {
    const sgf = '(;GM[1]SZ[9]RU[chinese];B[aa];W[cc])';
    final game = Sgf.parse(sgf);
    final first = Completer<double?>();
    var firstEval = true;
    final task = ReviewWinrateTask(
      game: game,
      rule: GoRule.chinese,
      komi: 7.5,
      eval: (board, toMove) {
        if (firstEval) {
          firstEval = false;
          return first.future;
        }
        return Future.value(0.5);
      },
    );

    final running = task.runTo(2);
    task.cancel();
    first.complete(0.7);
    final ok = await running;
    expect(ok, isFalse);
    expect(task.isCancelled, isTrue);
    // 手 0 评估结果已落袋，手 1 起被取消。
    expect(task.results.containsKey(0), isTrue);
    expect(task.results.containsKey(1), isFalse);
  });
}
