import 'package:flutter_test/flutter_test.dart';
import 'package:miaogo/core/board.dart';
import 'package:miaogo/core/move.dart';

void main() {
  group('落子与提子', () {
    test('空棋盘落子并读取', () {
      final b = GoBoard(size: 9);
      expect(b.play(PlayerColor.black, 4, 4), isTrue);
      expect(b.at(4, 4), PlayerColor.black);
      expect(b.play(PlayerColor.white, 3, 3), isTrue);
      expect(b.at(3, 3), PlayerColor.white);
    });

    test('提子：最后一气吃掉对方单子', () {
      final b = GoBoard(size: 9);
      expect(b.play(PlayerColor.black, 3, 4), isTrue);
      expect(b.play(PlayerColor.black, 5, 4), isTrue);
      expect(b.play(PlayerColor.black, 4, 5), isTrue);
      expect(b.play(PlayerColor.white, 4, 4), isTrue); // 仅剩 (4,3) 一气
      expect(b.capturesBlack, 0);
      expect(b.play(PlayerColor.black, 4, 3), isTrue); // 提子
      expect(b.at(4, 4), isNull);
      expect(b.capturesBlack, 1);
    });

    test('提子：多子棋串', () {
      final b = GoBoard(size: 9);
      expect(b.play(PlayerColor.white, 4, 4), isTrue);
      expect(b.play(PlayerColor.white, 4, 5), isTrue);
      expect(b.play(PlayerColor.black, 3, 4), isTrue);
      expect(b.play(PlayerColor.black, 3, 5), isTrue);
      expect(b.play(PlayerColor.black, 4, 3), isTrue);
      expect(b.play(PlayerColor.black, 4, 6), isTrue);
      expect(b.play(PlayerColor.black, 5, 4), isTrue);
      expect(b.play(PlayerColor.black, 5, 5), isTrue); // 提两子
      expect(b.at(4, 4), isNull);
      expect(b.at(4, 5), isNull);
      expect(b.capturesBlack, 2);
    });

    test('落子被占点非法', () {
      final b = GoBoard(size: 9);
      b.play(PlayerColor.black, 0, 0);
      expect(b.play(PlayerColor.black, 0, 0), isFalse);
      expect(b.play(PlayerColor.white, 0, 0), isFalse);
    });
  });

  group('提子计数', () {
    test('一次提两串：连提各组分别累计', () {
      final b = GoBoard(size: 9);
      // 白 (3,4) 仅剩 (4,4) 一气
      for (final (r, c) in const [(2, 4), (3, 3), (3, 5)]) {
        b.play(PlayerColor.black, r, c);
      }
      b.play(PlayerColor.white, 3, 4);
      // 白 (5,4) 仅剩 (4,4) 一气
      for (final (r, c) in const [(6, 4), (5, 3), (5, 5)]) {
        b.play(PlayerColor.black, r, c);
      }
      b.play(PlayerColor.white, 5, 4);
      expect(b.capturesBlack, 0);
      // 黑 (4,4) 一口气提两串
      expect(b.play(PlayerColor.black, 4, 4), isTrue);
      expect(b.at(3, 4), isNull);
      expect(b.at(5, 4), isNull);
      expect(b.capturesBlack, 2);
    });

    test('多子棋串一次计入整串数量', () {
      final b = GoBoard(size: 9);
      for (final (r, c) in const [(4, 4), (4, 5), (5, 5), (5, 6)]) {
        b.play(PlayerColor.white, r, c);
      }
      for (final (r, c) in const [
        (3, 4), (3, 5), (4, 3), (4, 6), (5, 3), (5, 7), (6, 4), (6, 5),
        (6, 6),
      ]) {
        b.play(PlayerColor.black, r, c);
      }
      expect(b.play(PlayerColor.black, 5, 4), isTrue); // 最后一气提 4 子整串
      expect(b.capturesBlack, 4);
    });

    test('黑白双方各自累计，互不混淆', () {
      final b = GoBoard(size: 9);
      // 黑围白 (4,4)：黑 (3,4)(5,4)(4,3)，(4,5) 最后落子提子
      b.play(PlayerColor.black, 3, 4);
      b.play(PlayerColor.white, 4, 4);
      b.play(PlayerColor.black, 5, 4);
      b.play(PlayerColor.white, 1, 1); // 远处虚着
      b.play(PlayerColor.black, 4, 3);
      b.play(PlayerColor.white, 1, 3); // 白方包围黑 (1,2) 的起点
      b.play(PlayerColor.black, 4, 5); // 提白 (4,4)
      expect(b.capturesBlack, 1);
      expect(b.capturesWhite, 0);
      // 白围黑 (1,2)：白 (1,1)(1,3)(2,2)，(0,2) 最后落子提子
      b.play(PlayerColor.white, 2, 2);
      b.play(PlayerColor.black, 1, 2);
      expect(b.play(PlayerColor.white, 0, 2), isTrue); // 提黑 (1,2)
      expect(b.capturesWhite, 1);
      expect(b.capturesBlack, 1); // 互不影响
      // 各自多次累计
      expect(b.capturesBlack, 1);
      expect(b.capturesWhite, 1);
    });

    test('提子计数：isLegal 模拟不污染计数与棋盘', () {
      final b = GoBoard(size: 9);
      b.play(PlayerColor.black, 4, 3);
      b.play(PlayerColor.black, 3, 4);
      b.play(PlayerColor.black, 5, 4);
      b.play(PlayerColor.black, 4, 5);
      expect(b.isLegal(PlayerColor.white, 4, 4), isFalse); // 禁自杀
      expect(b.capturesBlack, 0);
      expect(b.capturesWhite, 0);
      expect(b.at(4, 4), isNull);
    });

    test('emptyRegions：单色边界计领地区域，双色边界为未定', () {
      final b = GoBoard(size: 9);
      for (final (r, c) in const [(0, 3), (1, 3), (2, 3), (3, 0), (3, 1), (3, 2)]) {
        b.play(PlayerColor.black, r, c);
      }
      for (final (r, c) in const [(5, 6), (5, 7), (5, 8), (6, 5), (7, 5), (8, 5)]) {
        b.play(PlayerColor.white, r, c);
      }
      final regions = b.emptyRegions();
      final black = regions.where((e) => e.borders.length == 1 && e.borders.first == PlayerColor.black).fold<int>(0, (s, e) => s + e.area);
      final white = regions.where((e) => e.borders.length == 1 && e.borders.first == PlayerColor.white).fold<int>(0, (s, e) => s + e.area);
      final neutral = regions.where((e) => e.borders.length != 1).fold<int>(0, (s, e) => s + e.area);
      expect(black, 9);
      expect(white, 9);
      expect(neutral, 81 - 12 - 18);
    });
  });

  group('禁自杀', () {
    test('无气且无提子 → 禁着', () {
      final b = GoBoard(size: 9);
      b.play(PlayerColor.black, 4, 3);
      b.play(PlayerColor.black, 3, 4);
      b.play(PlayerColor.black, 5, 4);
      b.play(PlayerColor.black, 4, 5);
      expect(b.play(PlayerColor.white, 4, 4), isFalse);
      expect(b.at(4, 4), isNull);
    });

    test('自杀但可提子 → 合法', () {
      final b = GoBoard(size: 9);
      b.play(PlayerColor.black, 3, 4);
      b.play(PlayerColor.black, 5, 4);
      b.play(PlayerColor.black, 4, 5);
      b.play(PlayerColor.white, 4, 4);
      // 黑在 (4,3) 提掉白 (4,4)（落子点本身无气但提子后复活）
      expect(b.play(PlayerColor.black, 4, 3), isTrue);
      expect(b.at(4, 4), isNull);
      expect(b.capturesBlack, 1);
    });
  });

  group('打劫', () {
    test('简单劫：禁立即回提，隔一手后可回提', () {
      final b = GoBoard(size: 9);
      // 劫形：黑 (5,3)(5,5)(6,4)，白 (3,4)(4,3)(4,5)(5,4)，
      // 黑 (4,4) 提劫后仅剩 (5,4) 一口气 → 形成劫
      for (final (r, c) in const [(5, 3), (5, 5), (6, 4)]) {
        expect(b.play(PlayerColor.black, r, c), isTrue);
      }
      for (final (r, c) in const [(3, 4), (4, 3), (4, 5), (5, 4)]) {
        expect(b.play(PlayerColor.white, r, c), isTrue);
      }

      // 黑 (4,4) 提劫
      expect(b.play(PlayerColor.black, 4, 4), isTrue);
      expect(b.at(5, 4), isNull);
      expect(b.capturesBlack, 1);
      expect(b.koPoint, (5, 4));

      // 白立即回提 → 非法
      expect(b.play(PlayerColor.white, 5, 4), isFalse);

      // 白隔一手落子，劫解除
      expect(b.play(PlayerColor.white, 0, 0), isTrue);
      expect(b.koPoint, isNull);

      // 白可回提，形成反劫
      expect(b.play(PlayerColor.white, 5, 4), isTrue);
      expect(b.capturesWhite, 1);
      expect(b.koPoint, (4, 4));
      expect(b.play(PlayerColor.black, 4, 4), isFalse);
    });
  });

  group('合法点', () {
    test('空棋盘合法点数等于总点数', () {
      final b = GoBoard(size: 9);
      expect(b.legalPoints(PlayerColor.black), hasLength(81));
      final b13 = GoBoard(size: 13);
      expect(b13.legalPoints(PlayerColor.white), hasLength(169));
    });

    test('含禁自杀与劫禁', () {
      final b = GoBoard(size: 9);
      b.play(PlayerColor.black, 4, 3);
      b.play(PlayerColor.black, 3, 4);
      b.play(PlayerColor.black, 5, 4);
      b.play(PlayerColor.black, 4, 5);
      final legal = b.legalPoints(PlayerColor.white);
      expect(legal.contains((4, 4)), isFalse);
      expect(legal, hasLength(76)); // 81 - 4 黑子 - (4,4) 禁自杀
    });
  });

  group('SGF 坐标', () {
    test('行列 ↔ 坐标往返，跳过 i', () {
      expect(GoBoard.letters, 'abcdefghjklmnopqrst');
      expect(GoBoard.sgfCoord(0, 0), 'aa');
      expect(GoBoard.sgfCoord(8, 8), 'jj'); // 9 路右上角
      expect(GoBoard.sgfCoord(18, 18), 'tt'); // 19 路右上角
      expect(GoBoard.coordFromSgf('jj'), (8, 8));
      expect(GoBoard.coordFromSgf('tt'), (18, 18));
      expect(GoBoard.coordFromSgf('aa'), (0, 0));
    });

    test('非法坐标抛错', () {
      expect(() => GoBoard.coordFromSgf('ai'), throwsArgumentError);
      expect(() => GoBoard.coordFromSgf('z1'), throwsArgumentError);
      expect(() => GoBoard.coordFromSgf('a'), throwsArgumentError);
    });
  });

  group('位置超劫（superko）', () {
    test('重现更早局面被禁（sending two, returning one 循环）', () {
      // S2R1：黑 X=(1,0)（G0）→ 黑(0,0) 送两子（G1）→ 白(2,0) 提两子（G2）→
      // 黑(1,0) 回提（应重现 G0）；positional superko 禁止之
      // （simple ko 不拦，因上一步是 G2 而非 G0）。
      final b = GoBoard(size: 9); // superko 默认开启
      for (final (r, c) in const [(1, 1), (0, 1)]) {
        expect(b.play(PlayerColor.white, r, c), isTrue);
      }
      for (final (r, c) in const [(3, 0), (2, 1)]) {
        expect(b.play(PlayerColor.black, r, c), isTrue);
      }
      expect(b.play(PlayerColor.black, 1, 0), isTrue); // G0
      expect(b.play(PlayerColor.black, 0, 0), isTrue); // G1 送两子（自紧气）
      expect(b.play(PlayerColor.white, 2, 0), isTrue); // G2 提黑两子
      expect(b.at(1, 0), isNull);
      expect(b.at(0, 0), isNull);
      // 回提 (1,0) 会重现 G0 → 被位置超劫禁止
      expect(b.play(PlayerColor.black, 1, 0), isFalse, reason: '重现更早局面');
      expect(b.at(2, 0), PlayerColor.white); // 白子仍在
    });

    test('关闭 superko 时允许重现（simple ko 放行）', () {
      final b = GoBoard(size: 9, superko: false);
      for (final (r, c) in const [(1, 1), (0, 1)]) {
        b.play(PlayerColor.white, r, c);
      }
      for (final (r, c) in const [(3, 0), (2, 1)]) {
        b.play(PlayerColor.black, r, c);
      }
      b.play(PlayerColor.black, 1, 0);
      b.play(PlayerColor.black, 0, 0);
      b.play(PlayerColor.white, 2, 0);
      expect(b.play(PlayerColor.black, 1, 0), isTrue);
      expect(b.at(2, 0), isNull); // 提回白子
      expect(b.at(0, 0), isNull); // 网格回到 G0
    });
  });

  group('克隆', () {
    test('克隆后互不影响', () {
      final b = GoBoard(size: 9);
      b.play(PlayerColor.black, 0, 0);
      final c = b.clone();
      expect(c.at(0, 0), PlayerColor.black);
      c.play(PlayerColor.white, 8, 8);
      expect(b.at(8, 8), isNull);
      expect(c.at(8, 8), PlayerColor.white);
      c.capturesBlack = 3;
      expect(b.capturesBlack, 0);
    });
  });

  group('星位', () {
    test('9/13/19 路星位数量', () {
      expect(GoBoard.starPoints(9), hasLength(5));
      expect(GoBoard.starPoints(13), hasLength(9));
      expect(GoBoard.starPoints(19), hasLength(9));
      expect(GoBoard.starPoints(9).contains((4, 4)), isTrue);
    });
  });
}
