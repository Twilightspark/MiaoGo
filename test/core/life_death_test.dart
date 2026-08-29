import 'package:flutter_test/flutter_test.dart';
import 'package:miaogo/core/board.dart';
import 'package:miaogo/core/life_death.dart';
import 'package:miaogo/core/move.dart';

/// 构造棋盘（superko 关闭，直接布子，不受落子顺序/劫约束）。
GoBoard board9() => GoBoard(size: 9, superko: false);

void main() {
  group('活棋', () {
    test('两眼活：两个独立眼区（直二×2）', () {
      final b = board9();
      // 5×4 外框，内部分成两个直二眼
      for (final (r, c) in const [
        (0, 0), (0, 1), (0, 2), (0, 3), (0, 4),
        (1, 0), (1, 2), (1, 4),
        (2, 0), (2, 2), (2, 4),
        (3, 0), (3, 1), (3, 2), (3, 3), (3, 4),
      ]) {
        b.setStone(r, c, PlayerColor.black);
      }
      final r = analyzeLifeDeath(b);
      expect(r.statusOf(b, 0, 0), GroupStatus.alive);
      expect(r.statusOf(b, 3, 4), GroupStatus.alive);
      expect(r.deadPoints, isEmpty);
    });

    test('单大眼活：5×5 外框包 3×3 眼区', () {
      final b = board9();
      for (var r = 0; r < 5; r++) {
        for (var c = 0; c < 5; c++) {
          if (r == 0 || r == 4 || c == 0 || c == 4) {
            b.setStone(r, c, PlayerColor.black);
          }
        }
      }
      final r = analyzeLifeDeath(b);
      expect(r.statusOf(b, 0, 0), GroupStatus.alive);
      expect(r.deadPoints, isEmpty);
    });

    test('直四活', () {
      final b = board9();
      for (final (r, c) in const [
        (0, 0), (0, 1), (0, 2), (0, 3), (0, 4), (0, 5),
        (1, 0), (1, 5),
        (2, 0), (2, 1), (2, 2), (2, 3), (2, 4), (2, 5),
      ]) {
        b.setStone(r, c, PlayerColor.black);
      }
      final r = analyzeLifeDeath(b);
      expect(r.statusOf(b, 0, 0), GroupStatus.alive);
      expect(r.deadPoints, isEmpty);
    });
  });

  group('死棋', () {
    test('单点眼被围死（3×3 环 + 白外环）', () {
      final b = board9();
      // 黑 3×3 环（中心 (2,2) 单点眼）
      for (var r = 1; r <= 3; r++) {
        for (var c = 1; c <= 3; c++) {
          if (r == 2 && c == 2) continue;
          b.setStone(r, c, PlayerColor.black);
        }
      }
      // 白 5×5 环围死（保留黑眼 (2,2)）
      for (var r = 0; r <= 4; r++) {
        for (var c = 0; c <= 4; c++) {
          if (b.at(r, c) == null && !(r == 2 && c == 2)) {
            b.setStone(r, c, PlayerColor.white);
          }
        }
      }
      final r = analyzeLifeDeath(b);
      expect(r.statusOf(b, 1, 1), GroupStatus.dead);
      expect(r.deadPoints, hasLength(8));
    });

    test('方四被围死（4×4 环包 2×2 眼区）', () {
      final b = board9();
      // 黑 4×4 环，内部 2×2 方四
      for (var r = 1; r <= 4; r++) {
        for (var c = 1; c <= 4; c++) {
          final interior = (r == 2 || r == 3) && (c == 2 || c == 3);
          if (!interior) b.setStone(r, c, PlayerColor.black);
        }
      }
      // 白 6×6 环围死（保留黑方四眼区）
      for (var r = 0; r <= 5; r++) {
        for (var c = 0; c <= 5; c++) {
          final interior = (r == 2 || r == 3) && (c == 2 || c == 3);
          if (b.at(r, c) == null && !interior) {
            b.setStone(r, c, PlayerColor.white);
          }
        }
      }
      final r = analyzeLifeDeath(b);
      expect(r.statusOf(b, 1, 1), GroupStatus.dead);
    });

    test('无眼被围死：最后一气与对方共享', () {
      final b = board9();
      // 白围黑 (4,4)，黑仅剩 (4,5) 一气（与白共享）
      for (final (r, c) in const [
        (3, 4), (5, 4), (4, 3), (3, 5), (5, 5),
      ]) {
        b.setStone(r, c, PlayerColor.white);
      }
      b.setStone(4, 4, PlayerColor.black);
      final r = analyzeLifeDeath(b);
      expect(r.statusOf(b, 4, 4), GroupStatus.dead);
    });

    test('假眼剔除：两个"眼"均为假眼（被白子穿入）→ 死', () {
      final b = board9();
      // 黑环内有白子 (2,3)，两侧眼区均与白相邻 → 两个假眼
      for (final (r, c) in const [
        (0, 0), (0, 1), (0, 2), (0, 3), (0, 4), (0, 5), (0, 6),
        (4, 0), (4, 1), (4, 2), (4, 3), (4, 4), (4, 5), (4, 6),
        (1, 0), (3, 0), (1, 6), (3, 6), (2, 0), (2, 6), (2, 3),
      ]) {
        b.setStone(r, c, PlayerColor.white);
      }
      for (final (r, c) in const [
        (1, 1), (1, 2), (1, 3), (1, 4), (1, 5),
        (2, 1), (2, 5),
        (3, 1), (3, 2), (3, 3), (3, 4), (3, 5),
      ]) {
        b.setStone(r, c, PlayerColor.black);
      }
      final r = analyzeLifeDeath(b);
      expect(r.statusOf(b, 2, 1), GroupStatus.dead);
      expect(r.statusOf(b, 3, 2), GroupStatus.dead);
    });
  });

  group('双活', () {
    test('简单双活：一眼对一眼，共享密封气口', () {
      final b = board9();
      // 黑占左上 (rows0-3, cols0-4) 除 (1,1) 眼；白占其余，除 (2,5) 口与 (6,6) 眼。
      // 口点 (2,5) 四邻全为黑白棋子，双方均不能落子 → 双活。
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
      final r = analyzeLifeDeath(b);
      expect(r.statusOf(b, 0, 0), GroupStatus.seki, reason: '黑应双活');
      expect(r.statusOf(b, 8, 8), GroupStatus.seki, reason: '白应双活');
      expect(r.sekiPoints, isNotEmpty);
      expect(r.sekiEyes, isNotEmpty);
    });
  });
}
