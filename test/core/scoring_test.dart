import 'package:flutter_test/flutter_test.dart';
import 'package:miaogo/core/board.dart';
import 'package:miaogo/core/move.dart';
import 'package:miaogo/core/rules.dart';
import 'package:miaogo/core/scoring.dart';

/// 构造一个双活+提子的局面：
/// - 黑左上角围 9 目（6 子，墙在 3 列/3 行）
/// - 白右下角围 9 目（墙在 5 行/5 列：6 子）
/// - 白 (4,4)(4,5) 两子被黑围杀（黑 6 子）
/// 结果：黑 12 子，白 6 子；黑空 12（9+被提点 2+(3,3) 1），白空 9；黑提 2，白提 0。
GoBoard buildPosition() {
  final b = GoBoard(size: 9);
  // 黑左上角
  for (final (r, c) in const [
    (0, 3), (1, 3), (2, 3), (3, 0), (3, 1), (3, 2),
  ]) {
    expect(b.play(PlayerColor.black, r, c), isTrue, reason: '黑落子 ($r,$c)');
  }
  // 白右下角墙 + 待提棋串
  for (final (r, c) in const [
    (5, 6), (5, 7), (5, 8), (6, 5), (7, 5), (8, 5),
    (4, 4), (4, 5),
  ]) {
    expect(b.play(PlayerColor.white, r, c), isTrue, reason: '白落子 ($r,$c)');
  }
  // 黑围杀 (4,4)(4,5)，最后一子 (5,5) 提走两白子
  for (final (r, c) in const [
    (3, 4), (3, 5), (4, 3), (4, 6), (5, 4), (5, 5),
  ]) {
    expect(b.play(PlayerColor.black, r, c), isTrue, reason: '黑落子 ($r,$c)');
  }
  expect(b.capturesBlack, 2);
  return b;
}

void main() {
  test('数子：黑胜 2.5 点', () {
    final r = scoreGame(buildPosition(), rule: GoRule.chinese, komi: 6.5);
    expect(r.blackStones, 12);
    expect(r.whiteStones, 6);
    expect(r.blackTerritory, 12); // 9（左上）+ 1（(3,3) 单点）+ 2（被提点）
    expect(r.whiteTerritory, 9);
    expect(r.blackCaptures, 2);
    expect(r.blackPoints, 24);
    expect(r.whitePoints, 15);
    expect(r.winner, PlayerColor.black);
    expect(r.margin, 2.5);
    expect(r.description, '黑胜 2.5点');
  });

  test('数目：白胜 1.5 目', () {
    final r = scoreGame(buildPosition(), rule: GoRule.japanese, komi: 6.5);
    expect(r.blackPoints, 14); // 空 12 + 提 2
    expect(r.whitePoints, 9);
    expect(r.winner, PlayerColor.white);
    expect(r.margin, 1.5);
    expect(r.description, '白胜 1.5目');
  });

  test('空棋盘数子：白方因贴目获胜', () {
    final b = GoBoard(size: 9);
    final r = scoreGame(b, rule: GoRule.chinese, komi: 7.5);
    expect(r.blackPoints, 0);
    expect(r.whitePoints, 0);
    expect(r.winner, PlayerColor.white);
    expect(r.margin, 7.5);
  });

  test('和棋：无贴目双方点数相同', () {
    final b = GoBoard(size: 9);
    b.play(PlayerColor.black, 0, 1);
    b.play(PlayerColor.black, 1, 0); // 黑围 (0,0)
    b.play(PlayerColor.white, 7, 8);
    b.play(PlayerColor.white, 8, 7); // 白围 (8,8)
    final r = scoreGame(b, rule: GoRule.chinese, komi: 0);
    expect(r.blackPoints, 3); // 2 子 + 1 空
    expect(r.whitePoints, 3);
    expect(r.winner, isNull);
    expect(r.description, '和棋');
  });

  group('判死子与双活', () {
    /// 黑 3×3 环（眼 (2,2)）被白 5×5 环围死。
    GoBoard deadGroupBoard() {
      final b = GoBoard(size: 9, superko: false);
      for (var r = 1; r <= 3; r++) {
        for (var c = 1; c <= 3; c++) {
          if (r == 2 && c == 2) continue;
          b.setStone(r, c, PlayerColor.black);
        }
      }
      for (var r = 0; r <= 4; r++) {
        for (var c = 0; c <= 4; c++) {
          if (b.at(r, c) == null && !(r == 2 && c == 2)) {
            b.setStone(r, c, PlayerColor.white);
          }
        }
      }
      return b;
    }

    /// 双活局面：黑左上 U 形（眼 (1,1)），白墙（眼 (6,6)），共享气口 (2,5)。
    GoBoard sekiBoard() {
      final b = GoBoard(size: 9, superko: false);
      for (var r = 0; r < 9; r++) {
        for (var c = 0; c < 9; c++) {
          final isBlack = r <= 3 && c <= 4 && !(r == 1 && c == 1);
          final isEye = (r == 1 && c == 1) ||
              (r == 2 && c == 5) ||
              (r == 6 && c == 6);
          if (isBlack) {
            b.setStone(r, c, PlayerColor.black);
          } else if (!isEye) {
            b.setStone(r, c, PlayerColor.white);
          }
        }
      }
      return b;
    }

    test('数子：判死子移除，空点并入对方领地', () {
      final r = scoreGame(deadGroupBoard(), rule: GoRule.chinese, komi: 0);
      expect(r.deadBlack, 8);
      expect(r.deadWhite, 0);
      expect(r.blackStones, 0); // 死子不再计子
      expect(r.whiteStones, 16);
      expect(r.blackTerritory, 0);
      expect(r.whiteTerritory, 65); // 环内 9 + 环外 56
      expect(r.blackPoints, 0);
      expect(r.whitePoints, 81);
      expect(r.winner, PlayerColor.white);
    });

    test('数目：判死子计入对方俘虏', () {
      final r = scoreGame(deadGroupBoard(), rule: GoRule.japanese, komi: 0);
      expect(r.deadBlack, 8);
      expect(r.whiteCaptures, 8); // 8 个死黑子 = 白方俘虏
      expect(r.blackCaptures, 0);
      expect(r.whiteTerritory, 65);
      expect(r.blackPoints, 0);
      expect(r.whitePoints, 73); // 65 空 + 8 俘虏
    });

    test('双活：数子计眼，数目不计眼', () {
      final area = scoreGame(sekiBoard(), rule: GoRule.chinese, komi: 0);
      expect(area.deadBlack, 0);
      expect(area.blackStones, 19);
      expect(area.whiteStones, 59);
      expect(area.blackTerritory, 1); // 双活眼 (1,1) 在数子中计分
      expect(area.whiteTerritory, 1); // 双活眼 (6,6) 在数子中计分
      expect(area.blackPoints, 20);
      expect(area.whitePoints, 60);

      final ter = scoreGame(sekiBoard(), rule: GoRule.japanese, komi: 0);
      expect(ter.blackTerritory, 0); // 双活眼在数目中不计
      expect(ter.whiteTerritory, 0);
      expect(ter.blackPoints, 0);
      expect(ter.whitePoints, 0);
      expect(ter.winner, isNull); // 和棋
    });

    test('ScoreResult.details 包含判死子行', () {
      final r = scoreGame(deadGroupBoard(), rule: GoRule.chinese, komi: 0);
      expect(r.details.any((l) => l.contains('判死子')), isTrue);
      final s = scoreGame(sekiBoard(), rule: GoRule.japanese, komi: 0);
      expect(s.details.any((l) => l.contains('判死子')), isFalse);
    });
  });

  group('analyzeSettledness', () {
    /// 基本定型局面：黑堵 2-3 行（上两行成黑空），白堵 4-5 行（下三行成白空），
    /// 无未定空区，全部空点单色归属。
    GoBoard settledBoard() {
      final b = GoBoard(size: 9);
      for (var r = 2; r <= 3; r++) {
        for (var c = 0; c < 9; c++) {
          b.play(PlayerColor.black, r, c);
        }
      }
      for (var r = 4; r <= 5; r++) {
        for (var c = 0; c < 9; c++) {
          b.play(PlayerColor.white, r, c);
        }
      }
      return b;
    }

    test('基本定型局面判定型', () {
      final s = analyzeSettledness(settledBoard(), moveCount: 40);
      expect(s.ownedEmpty, 45);
      expect(s.neutralEmpty, 0);
      expect(s.maxNeutralRegion, 0);
      expect(s.ownedRatio, 1.0);
      expect(s.basicallySettled, isTrue);
    });

    test('手数不足不判定型（单子包围全盘）', () {
      final b = GoBoard(size: 9);
      b.play(PlayerColor.black, 4, 4);
      final s = analyzeSettledness(b, moveCount: 1);
      expect(s.ownedRatio, 1.0);
      expect(s.basicallySettled, isFalse); // 手数不足
    });

    test('残留大型未定区不判定型', () {
      // buildPosition：中间大块未定区边界双色
      final s = analyzeSettledness(buildPosition(), moveCount: 30);
      expect(s.maxNeutralRegion, greaterThan(2));
      expect(s.basicallySettled, isFalse);
    });

    test('空棋盘不判定型', () {
      final b = GoBoard(size: 9);
      final s = analyzeSettledness(b, moveCount: 40);
      expect(s.basicallySettled, isFalse);
    });

    test('阈值可调：降低要求后判定型', () {
      final s = analyzeSettledness(
        buildPosition(),
        moveCount: 30,
        ownedThreshold: 0.3,
        maxNeutralRegion: 60,
      );
      expect(s.basicallySettled, isTrue);
    });
  });
}
