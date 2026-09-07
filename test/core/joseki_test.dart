import 'package:flutter_test/flutter_test.dart';
import 'package:miaogo/core/board.dart';
import 'package:miaogo/core/joseki.dart';
import 'package:miaogo/core/move.dart';

void main() {
  const size = 19;

  group('JosekiCoords.canonical', () {
    test('星位小飞挂（TL 角）归一化到 TR 规范串', () {
      final pts = [
        GoBoard.coordFromSgf('dd'), // (3,3)
        GoBoard.coordFromSgf('dc'), // (3,2)
        GoBoard.coordFromSgf('ed'), // (4,3)
        GoBoard.coordFromSgf('be'), // (1,4)
        GoBoard.coordFromSgf('dg'), // (3,6)
      ];
      expect(JosekiCoords.canonical(pts, size), ['qd', 'qc', 'pd', 'se', 'qg']);
    });

    test('8 个对称变换折叠为同一个规范串（去重保证）', () {
      final base = <(int, int)>[
        (3, 15),
        (3, 16),
        (4, 15),
        (1, 14),
        (3, 12),
      ];
      (int, int) t((int, int) p, int m) {
        final (r, c) = p;
        return switch (m) {
          0 => (r, c),
          1 => (c, size - 1 - r),
          2 => (size - 1 - r, size - 1 - c),
          3 => (size - 1 - c, r),
          4 => (r, size - 1 - c),
          5 => (size - 1 - r, c),
          6 => (c, r),
          _ => (size - 1 - c, size - 1 - r),
        };
      }

      final canon = <String>[];
      for (var m = 0; m < 8; m++) {
        canon.add(JosekiCoords.canonical([for (final p in base) t(p, m)], size)
            .join(' '));
      }
      expect(canon.toSet().length, 1);
    });
  });

  group('JosekiMatcher', () {
    const e1 = JosekiEntry(
      id: 'a',
      moves: ['pd', 'qc', 'pc', 'qd'],
      label: 'A',
      sgf: '',
      frequency: 50,
    );
    const e2 = JosekiEntry(
      id: 'b',
      moves: ['qd', 'qc'],
      label: 'B',
      sgf: '',
    );

    test('前缀命中与排序（匹配手数优先、频率次之）', () {
      final m = JosekiMatcher([e1, e2]);
      final r1 = m.match(['pd']);
      expect(r1.first.entry.id, 'a');

      final r2 = m.match(['pd', 'qc']);
      expect(r2.first.entry.id, 'a');
      expect(r2.first.matchLen, 2);

      final r3 = m.match(['qd']);
      expect(r3.first.entry.id, 'b');
    });

    test('不命中返回空', () {
      final m = JosekiMatcher([e1, e2]);
      expect(m.match(['pp', 'qq']), isEmpty);
    });
  });

  group('movesInCorner', () {
    test('TR 规范坐标在指定角内展开且黑白交替', () {
      final moves = movesInCorner(['pd', 'qc'], 'TL', size);
      expect(moves.length, 2);
      expect(moves[0].color, PlayerColor.black);
      expect(moves[1].color, PlayerColor.white);
      // pd=(row3,col14) -> TL 反推 (3, 18-14=4)=ed
      expect(GoBoard.sgfCoord(moves[0].row!, moves[0].col!), 'ed');
    });
  });

  group('recommendNext', () {
    const a = JosekiEntry(
        id: 'a', moves: ['pd', 'qc', 'pc'], label: 'A', sgf: '', frequency: 50);
    const b = JosekiEntry(
        id: 'b', moves: ['pd', 'qc', 'qd'], label: 'B', sgf: '', frequency: 30);
    const c = JosekiEntry(
        id: 'c', moves: ['qd', 'qc'], label: 'C', sgf: '', frequency: 20);
    final entries = [a, b, c];

    test('空棋盘按首手分布推荐、概率归一化且取前 4', () {
      final hints = recommendNext(entries, const []);
      expect(hints.length, lessThanOrEqualTo(4));
      expect(hints.map((h) => h.coord).toList(), ['pd', 'qd']);
      expect(hints.first.probability, closeTo(0.8, 1e-9));
      expect(hints[1].probability, closeTo(0.2, 1e-9));
    });

    test('有着法时按命中定式下一手加权', () {
      final hints = recommendNext(entries, ['pd', 'qc']);
      expect(hints.map((h) => h.coord).toList(), ['pc', 'qd']);
      expect(hints.first.probability, closeTo(0.625, 1e-9));
      expect(hints[1].probability, closeTo(0.375, 1e-9));
    });

    test('无任何候选返回空', () {
      expect(recommendNext(entries, ['pp', 'qq']), isEmpty);
    });
  });
}
