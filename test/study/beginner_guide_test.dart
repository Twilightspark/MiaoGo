import 'package:flutter_test/flutter_test.dart';
import 'package:miaogo/core/board.dart';
import 'package:miaogo/core/move.dart';
import 'package:miaogo/study/beginner_guide.dart';

void main() {
  group('步骤结构与基础推进', () {
    test('共 12 步，标题齐全', () {
      expect(BeginnerGuideEngine.totalSteps, 12);
      expect(kGuideSteps.length, 12);
      for (final s in kGuideSteps) {
        expect(s.title, isNotEmpty);
        expect(s.instruction, isNotEmpty);
      }
    });

    test('逐步推进可达完成并正常进入下一课', () {
      final e = BeginnerGuideEngine();
      expect(e.index, 0);
      expect(e.canPrev, isFalse);
      expect(e.canNext, isFalse);

      // 第 1 步：任意空点落子即完成。
      e.onTap(2, 3);
      expect(e.completed, isTrue);
      expect(e.board.at(2, 3), PlayerColor.black);
      expect(e.canNext, isTrue);
      e.gotoNext();

      // 第 2 步（阅读：气）进入即完成。
      expect(e.index, 1);
      expect(e.completed, isTrue);

      // 第 3 步：数气练习（错误不改盘、正确后进入下一课）。
      e.gotoNext();
      expect(e.index, 2);
      expect(e.board.groupLiberties(4, 4), 4);
      final before = e.board.clone();
      e.onTap(8, 1); // 错（3 气）
      expect(e.completed, isFalse);
      expect(e.board.at(8, 1), isNull); // 错误不改盘
      expect(_stonesOf(e.board, PlayerColor.black),
          _stonesOf(before, PlayerColor.black));
      expect(_stonesOf(e.board, PlayerColor.white),
          _stonesOf(before, PlayerColor.white));
      e.onTap(8, 3); // 对（4 气）
      expect(e.completed, isTrue);

      // 第 4 步：提子（堵最后一口气）。
      e.gotoNext();
      expect(e.index, 3);
      e.onTap(0, 0); // 错误尝试
      expect(e.completed, isFalse);
      expect(e.board.at(4, 4), PlayerColor.white);
      e.onTap(5, 4);
      expect(e.completed, isTrue);
      expect(e.board.at(4, 4), isNull);

      // 第 5 步：先探禁入点，再“无气吃子”。
      e.gotoNext();
      expect(e.index, 4);
      e.onTap(4, 4);
      expect(e.completed, isFalse);
      expect(e.board.at(4, 4), isNull); // 禁入点未落子
      e.onTap(6, 1);
      expect(e.completed, isTrue);
      expect(e.board.at(6, 0), isNull);
      expect(e.board.at(8, 2), isNull);

      // 第 6 步：连接延气。
      e.gotoNext();
      expect(e.index, 5);
      e.onTap(4, 5);
      expect(e.completed, isTrue);
      expect(e.board.groupLiberties(4, 4), greaterThanOrEqualTo(2));

      // 第 7 步：分断并提两子。
      e.gotoNext();
      expect(e.index, 6);
      e.onTap(4, 5);
      expect(e.completed, isTrue);
      expect(e.board.at(4, 4), isNull);
      expect(e.board.at(4, 6), isNull);

      // 第 8 步：做眼（直三补中 → 两真眼）。
      e.gotoNext();
      expect(e.index, 7);
      e.onTap(8, 5);
      expect(e.completed, isTrue);
      expect(e.board.at(8, 4), isNull);
      expect(e.board.at(8, 6), isNull);
      expect(e.board.groupLiberties(7, 3), 2);

      // 第 9 步：打劫（先提成劫 → 立刻回提被禁）。
      e.gotoNext();
      expect(e.index, 8);
      expect(e.completed, isFalse);
      e.onTap(4, 5);
      expect(e.completed, isFalse);
      expect(e.board.at(4, 4), isNull);
      e.onTap(0, 0); // 去别处（合法劫材演示）
      expect(e.completed, isFalse);
      e.onTap(4, 4); // 尝试立刻提回
      expect(e.completed, isTrue);

      // 第 10 步（阅读：胜负判定）进入即完成。
      e.gotoNext();
      expect(e.index, 9);
      expect(e.completed, isTrue);

      // 第 11 步：停一手。
      e.gotoNext();
      expect(e.index, 10);
      expect(e.completed, isFalse);
      expect(e.showPass, isTrue);
      e.pass();
      expect(e.completed, isTrue);

      // 第 12 步：毕业挑战（天元一子提尽）。
      e.gotoNext();
      expect(e.index, 11);
      expect(e.completed, isFalse);
      e.onTap(4, 4);
      expect(e.completed, isTrue);
      expect(_countOf(e.board, PlayerColor.white), 0);
      expect(e.isLastStep, isTrue);
    });
  });

  group('单步细节', () {
    test('重试复位当前步', () {
      final e = BeginnerGuideEngine();
      e.onTap(0, 0);
      expect(e.completed, isTrue);
      e.retry();
      expect(e.completed, isFalse);
      expect(e.board.isEmpty, isTrue);
    });

    test('打劫第 1 相提交不改完成态，重试可整体复位', () {
      final e = BeginnerGuideEngine(initialStep: 8);
      e.onTap(4, 5);
      expect(e.completed, isFalse);
      expect(e.board.at(4, 5), PlayerColor.black);
      e.retry();
      expect(e.board.at(4, 5), isNull);
      expect(e.board.at(4, 4), PlayerColor.white);
    });

    test('第 12 步错点（占点）提示且不完成', () {
      final e = BeginnerGuideEngine(initialStep: 11);
      e.onTap(0, 0); // 已有白子
      expect(e.completed, isFalse);
      expect(e.feedback, isNotNull);
    });

    test('讲解步 next 常开，动作步未完成时 next 关闭', () {
      final info = BeginnerGuideEngine(initialStep: 9);
      expect(info.completed, isTrue);
      expect(info.canNext, isTrue);

      final act = BeginnerGuideEngine(initialStep: 3);
      expect(act.completed, isFalse);
      expect(act.canNext, isFalse);
    });

    test('停一手：半盘各两气，再下只会自紧', () {
      final e = BeginnerGuideEngine(initialStep: 10);
      final b = e.board;
      // 双方各占半盘，整串只剩两个眼位。
      expect(b.groupLiberties(0, 0), 2);
      expect(b.groupLiberties(8, 8), 2);
      // 全盘仅剩 4 个空点，均为各方的眼位。
      var empty = 0;
      for (var r = 0; r < b.size; r++) {
        for (var c = 0; c < b.size; c++) {
          if (b.at(r, c) == null) empty++;
        }
      }
      expect(empty, 4);
      expect(b.at(1, 2), isNull);
      expect(b.at(1, 6), isNull);
      expect(b.at(7, 2), isNull);
      expect(b.at(7, 6), isNull);
      expect(e.canPlay, isFalse);
      expect(e.completed, isFalse);
      expect(e.showPass, isTrue);
    });
  });
}

int _stonesOf(GoBoard b, PlayerColor color) {
  var n = 0;
  for (var r = 0; r < b.size; r++) {
    for (var c = 0; c < b.size; c++) {
      if (b.at(r, c) == color) n++;
    }
  }
  return n;
}

int _countOf(GoBoard b, PlayerColor color) => _stonesOf(b, color);
