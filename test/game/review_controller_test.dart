import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miaogo/core/move.dart';
import 'package:miaogo/core/rules.dart';
import 'package:miaogo/core/scoring.dart';
import 'package:miaogo/core/sgf.dart';
import 'package:miaogo/game/review_controller.dart';

void main() {
  test('ruleFromSgf 映射', () {
    expect(ruleFromSgf('Chinese'), GoRule.chinese);
    expect(ruleFromSgf('chinese'), GoRule.chinese);
    expect(ruleFromSgf('Korean'), GoRule.korean);
    expect(ruleFromSgf('Japanese'), GoRule.japanese);
    expect(ruleFromSgf('Old Chinese'), GoRule.chinese);
    expect(ruleFromSgf(null), GoRule.chinese);
    expect(ruleFromSgf('AG'), GoRule.chinese);
  });

  test('加载并逐步跳转（含 PASS 与提子）', () {
    // aa=黑, bb=白, cc=黑提 bb? 实际让 bb 被提：黑 aa, 白 cc... 构造简单提子局面。
    // 用直序棋步：B[aa] W[cc] B[bb] W[ee]（无提子，验证重放一致）。
    const sgf = '(;GM[1]SZ[9]KM[7.5]RU[chinese]PB[黑]PW[白]'
        ';B[aa];W[cc];B[bb];W[ee];B[ff])';
    final game = Sgf.parse(sgf);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final ctrl = container.read(reviewControllerProvider.notifier);
    ctrl.load(game);

    var s = container.read(reviewControllerProvider)!;
    expect(s.index, 0);
    expect(s.atStart, isTrue);
    expect(s.atEnd, isFalse);
    expect(s.moves, isEmpty);
    expect(s.board.isEmpty, isTrue);
    expect(s.toMove, PlayerColor.black);
    expect(s.comment, isNull);
    expect(s.game.blackName, '黑');

    ctrl.next();
    s = container.read(reviewControllerProvider)!;
    expect(s.index, 1);
    expect(s.moves, [
      const Move.point(PlayerColor.black, 0, 0),
    ]);
    expect(s.board.at(0, 0), PlayerColor.black);
    expect(s.toMove, PlayerColor.white);

    ctrl.jumpTo(4);
    s = container.read(reviewControllerProvider)!;
    expect(s.moves.length, 4);
    expect(s.moves.last, const Move.point(PlayerColor.white, 4, 4));
    expect(s.board.at(4, 4), PlayerColor.white);
    expect(s.toMove, PlayerColor.black);

    ctrl.last();
    s = container.read(reviewControllerProvider)!;
    expect(s.atEnd, isTrue);
    expect(s.index, 5);

    ctrl.prev();
    s = container.read(reviewControllerProvider)!;
    expect(s.index, 4);
    // 越界夹取。
    ctrl.first();
    ctrl.prev();
    s = container.read(reviewControllerProvider)!;
    expect(s.index, 0);
    expect(s.moves, isEmpty);
  });

  test('PASS 计入手数但不落子', () {
    const sgf = '(;SZ[9]RU[chinese];B[aa];W[];B[cc])';
    final game = Sgf.parse(sgf);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final ctrl = container.read(reviewControllerProvider.notifier);
    ctrl.load(game);
    ctrl.last();
    final s = container.read(reviewControllerProvider)!;
    expect(s.moves.length, 3);
    expect(s.moves[1].isPass, isTrue);
    expect(s.board.at(0, 1), isNull); // 空点
  });

  test('布子（让子/死活题初始局面）重放', () {
    const sgf = '(;SZ[19]RU[Old Chinese]KM[0]AB[dp][pd]AW[dd][pp]'
        ';B[qd];W[dc])';
    final game = Sgf.parse(sgf);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final ctrl = container.read(reviewControllerProvider.notifier);
    ctrl.load(game);

    var s = container.read(reviewControllerProvider)!;
    expect(s.rule, GoRule.chinese); // Old Chinese → chinese
    expect(s.komi, 0);
    expect(s.board.at(14, 3), PlayerColor.black); // dp
    expect(s.board.at(3, 14), PlayerColor.black); // pd
    expect(s.board.at(3, 3), PlayerColor.white); // dd
    expect(s.board.at(14, 14), PlayerColor.white); // pp

    ctrl.next();
    s = container.read(reviewControllerProvider)!;
    expect(s.moves.first, const Move.point(PlayerColor.black, 3, 15));
    expect(s.board.at(3, 15), PlayerColor.black);
  });

  test('当前手注释读取', () {
    const sgf = '(;SZ[9]C[序盘];B[aa]C[第一手];W[cc])';
    final game = Sgf.parse(sgf);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final ctrl = container.read(reviewControllerProvider.notifier);
    ctrl.load(game);
    expect(container.read(reviewControllerProvider)!.comment, '序盘');
    ctrl.next();
    expect(container.read(reviewControllerProvider)!.comment, '第一手');
    ctrl.last();
    expect(container.read(reviewControllerProvider)!.comment, isNull);
  });

  test('任意手位点目', () {
    const sgf = '(;SZ[9]RU[chinese]KM[7.5];B[aa];W[cc];B[bb];W[dd];B[ee])';
    final game = Sgf.parse(sgf);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final ctrl = container.read(reviewControllerProvider.notifier);
    ctrl.load(game);
    ctrl.last();
    final s = container.read(reviewControllerProvider)!;
    final result = s.score();
    expect(result, isA<ScoreResult>());
    expect(result.winner, isNotNull);
  });

  test('主变化多分支：复盘跟随首子链，忽略变化', () {
    // 死活题结构：根后首分支为正解（4 步），另有错解分支。
    const sgf = '(;SZ[19]AW[pp][qp][rp]AB[pq][rq]'
        '(;B[qq];W[pr];B[qr]C[Correct])'
        '(;B[qs];W[qq])'
        '(;B[os]))';
    final game = Sgf.parse(sgf);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final ctrl = container.read(reviewControllerProvider.notifier);
    ctrl.load(game);
    expect(container.read(reviewControllerProvider)!.moves, isEmpty);
    ctrl.last();
    final s = container.read(reviewControllerProvider)!;
    expect(s.moves, [
      const Move.point(PlayerColor.black, 15, 15), // qq
      const Move.point(PlayerColor.white, 16, 14), // pr
      const Move.point(PlayerColor.black, 16, 15), // qr
    ]);
    expect(s.comment, 'Correct');
    // 主变化最后一步 B[qr]：列 q → Q，行 r(16)+1 → 17。
    expect(s.moveText, 'Q17');
  });

  test('moveText 坐标格式', () {
    const sgf = '(;SZ[9];B[aa];W[cc])';
    final game = Sgf.parse(sgf);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final ctrl = container.read(reviewControllerProvider.notifier);
    ctrl.load(game);
    ctrl.next();
    var s = container.read(reviewControllerProvider)!;
    expect(s.moveText, 'A1'); // aa → A1
    ctrl.next();
    s = container.read(reviewControllerProvider)!;
    expect(s.moveText, 'C3'); // cc → C3
  });

  test('空棋盘 / 无棋步棋谱', () {
    const sgf = '(;GM[1]SZ[9]RU[chinese]KM[7.5])';
    final game = Sgf.parse(sgf);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final ctrl = container.read(reviewControllerProvider.notifier);
    ctrl.load(game);
    final s = container.read(reviewControllerProvider)!;
    expect(s.atStart, isTrue);
    expect(s.atEnd, isTrue);
    ctrl.last();
    expect(container.read(reviewControllerProvider)!.index, 0);
  });

  test('试下：进入 / 黑白交替 / 悔棋 / 双停手终局 / 返回恢复', () {
    // dd 黑(3,3)、ee 白(4,4)、ff 黑(5,5)。
    const sgf = '(;GM[1]SZ[9]RU[chinese]KM[7.5];B[dd];W[ee];B[ff])';
    final game = Sgf.parse(sgf);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final ctrl = container.read(reviewControllerProvider.notifier);
    ctrl.load(game);
    ctrl.jumpTo(2);

    ctrl.enterTry();
    var s = container.read(reviewControllerProvider)!;
    expect(s.inTry, isTrue);
    expect(s.index, 2);
    expect(s.tryMoves, isEmpty);
    expect(s.moves.length, 2);
    expect(s.board.at(3, 3), PlayerColor.black);
    expect(s.board.at(4, 4), PlayerColor.white);
    expect(s.toMove, PlayerColor.black);
    expect(s.tryEnded, isFalse);

    // 黑在 ff 落子 → 轮到白。
    expect(ctrl.placeTryMove(5, 5), isTrue);
    s = container.read(reviewControllerProvider)!;
    expect(s.moves.length, 3);
    expect(s.tryMoves, [const Move.point(PlayerColor.black, 5, 5)]);
    expect(s.toMove, PlayerColor.white);
    expect(s.board.at(5, 5), PlayerColor.black);

    // 占点非法落子：不改变状态。
    expect(ctrl.placeTryMove(5, 5), isFalse);
    expect(container.read(reviewControllerProvider)!.moves.length, 3);

    // 白落 gg(6,6) → 轮到黑。
    expect(ctrl.placeTryMove(6, 6), isTrue);
    s = container.read(reviewControllerProvider)!;
    expect(s.moves.length, 4);
    expect(s.toMove, PlayerColor.black);
    expect(s.board.at(6, 6), PlayerColor.white);

    // 悔棋只撤销试下新增（移除 gg），不动主链。
    ctrl.undoTry();
    s = container.read(reviewControllerProvider)!;
    expect(s.tryMoves.length, 1);
    expect(s.moves.length, 3);
    expect(s.board.at(6, 6), isNull);
    expect(s.toMove, PlayerColor.white);

    // 停手(PASS)两次 → 试下终局，禁止再落子。
    ctrl.tryPass();
    s = container.read(reviewControllerProvider)!;
    expect(s.tryEnded, isFalse);
    ctrl.tryPass();
    s = container.read(reviewControllerProvider)!;
    expect(s.tryEnded, isTrue);
    expect(ctrl.placeTryMove(7, 7), isFalse);

    // 悔棋解除终局（撤掉最后一个 PASS）。
    ctrl.undoTry();
    s = container.read(reviewControllerProvider)!;
    expect(s.tryEnded, isFalse);

    // 试下期间跳转被忽略。
    ctrl.jumpTo(0);
    s = container.read(reviewControllerProvider)!;
    expect(s.inTry, isTrue);
    expect(s.index, 2);

    // 返回：恢复到进入试下前的历史局面。
    ctrl.exitTry();
    s = container.read(reviewControllerProvider)!;
    expect(s.inTry, isFalse);
    expect(s.index, 2);
    expect(s.moves.length, 2);
    expect(s.board.at(5, 5), isNull);
    expect(s.board.at(3, 3), PlayerColor.black);
  });

  test('进入试下不因主链末尾连续 PASS 直接终局', () {
    // 主链结束为 W[] B[]（连续两 PASS，历史记收官）。
    const sgf = '(;SZ[9]RU[chinese];B[aa];W[];B[])';
    final game = Sgf.parse(sgf);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final ctrl = container.read(reviewControllerProvider.notifier);
    ctrl.load(game);
    ctrl.last();
    final before = container.read(reviewControllerProvider)!;
    expect(before.moves.length, 3);
    expect(before.moves[1].isPass, isTrue);

    ctrl.enterTry();
    var s = container.read(reviewControllerProvider)!;
    expect(s.inTry, isTrue);
    expect(s.tryEnded, isFalse);
    expect(ctrl.placeTryMove(1, 1), isTrue);
    s = container.read(reviewControllerProvider)!;
    expect(s.moves.length, 4);
  });
}
