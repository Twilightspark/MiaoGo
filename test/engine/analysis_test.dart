import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:miaogo/core/move.dart';
import 'package:miaogo/engine/analysis.dart';

const _goldenPath = 'test/engine/golden/kata_analyze_9x9.txt';

void main() {
  group('KataAnalyzeParser 基础', () {
    test('解析单 move 行', () {
      const line = 'info move E4 visits 100 winrate 0.5 utility -0.01 '
          'scoreLead 0.1 prior 0.4 lcb 0.49 order 0 pv E4 F5 F4';
      final u = KataAnalyzeParser(boardSize: 9).parse(line);
      expect(u.moves, hasLength(1));
      final m = u.moves.single;
      expect(m.move, 'E4');
      expect(m.visits, 100);
      expect(m.winrate, closeTo(0.5, 1e-9));
      expect(m.utility, closeTo(-0.01, 1e-9));
      expect(m.scoreLead, closeTo(0.1, 1e-9));
      expect(m.prior, closeTo(0.4, 1e-9));
      expect(m.lcb, closeTo(0.49, 1e-9));
      expect(m.order, 0);
      expect(m.pv, ['E4', 'F5', 'F4']);
      expect(m.isSymmetryOf, isNull);
      expect(u.ownership, isNull);
    });

    test('解析 isSymmetryOf 与 pass 候选', () {
      const line = 'info move E4 visits 100 winrate 0.5 order 0 pv E4 '
          'info move D5 visits 100 winrate 0.5 isSymmetryOf E4 order 1 pv D5 '
          'info move pass visits 1 winrate 0.01 order 2 pv pass';
      final u = KataAnalyzeParser(boardSize: 9).parse(line);
      expect(u.moves, hasLength(3));
      expect(u.moves[1].isSymmetryOf, 'E4');
      expect(u.moves[2].move, 'pass');
      expect(u.orderedMoves.first.move, 'E4');
    });

    test('解析 ownership（行主序长度 = 尺寸²）', () {
      final ownership = List.generate(81, (i) => (i - 40) / 40.0)
          .map((v) => v.toStringAsFixed(4))
          .join(' ');
      final line = 'info move E4 visits 1 winrate 0.5 order 0 pv E4 '
          'ownership $ownership';
      final u = KataAnalyzeParser(boardSize: 9).parse(line);
      expect(u.ownership, hasLength(81));
      expect(u.ownership!.first, closeTo((0 - 40) / 40.0, 1e-4));
      expect(u.ownership!.last, closeTo((80 - 40) / 40.0, 1e-4));
    });

    test('未知字段健壮：跳过其值不报错', () {
      const line = 'info move E4 visits 1 winrate 0.5 futureField 1.0 '
          'order 0 pv E4';
      final u = KataAnalyzeParser(boardSize: 9).parse(line);
      expect(u.moves.single.order, 0);
    });
  });

  group('KataAnalyzeParser golden（真实引擎输出）', () {
    test('解析 Windows eigen 版真实 kata-analyze 行', () {
      final raw = File(_goldenPath).readAsStringSync().trim();
      expect(raw, startsWith('info move'));
      final u = KataAnalyzeParser(boardSize: 9).parse(raw);
      expect(u.moves, isNotEmpty);
      expect(u.ownership, isNotNull);
      expect(u.ownership, hasLength(81));

      // 首候选 order=0 且 moves 有序
      final ordered = u.orderedMoves;
      expect(ordered.first.order, 0);
      expect(ordered.first.visits, greaterThan(0));
      expect(ordered.first.winrate, inInclusiveRange(0.0, 1.0));
    });
  });

  group('ownershipToInfluence', () {
    test('黑方行棋时正值保持为正（黑=正）', () {
      final own = List<double>.filled(9, 0.8);
      final map =
          ownershipToInfluence(own, 3, PlayerColor.black);
      expect(map[0][0], closeTo(0.8, 1e-9));
      expect(map[2][2], closeTo(0.8, 1e-9));
    });

    test('白方行棋时整体取反（黑=正）', () {
      final own = List<double>.filled(9, 0.8);
      final map =
          ownershipToInfluence(own, 3, PlayerColor.white);
      expect(map[0][0], closeTo(-0.8, 1e-9));
    });
  });

  group('coordFromGtp', () {
    test('GTP 坐标与 pass', () {
      expect(coordFromGtp('E4'), (3, 4));
      expect(coordFromGtp('A1'), (0, 0));
      expect(coordFromGtp('J19'), (18, 8)); // 跳过 i：j 为第 9 列（索引 8）
      expect(coordFromGtp('pass'), isNull);
    });

    test('非法坐标抛错', () {
      expect(() => coordFromGtp('I1'), throwsArgumentError);
      expect(() => coordFromGtp('Q'), throwsArgumentError);
    });
  });
}
