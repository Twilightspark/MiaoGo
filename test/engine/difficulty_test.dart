import 'package:flutter_test/flutter_test.dart';
import 'package:miaogo/engine/difficulty.dart';

void main() {
  group('DifficultyTable 锚点', () {
    test('锚点档取值符合 §7 参考表', () {
      expect(DifficultyTable.forRank(0).maxVisits, 4); // 18级
      expect(DifficultyTable.forRank(0).temperature, greaterThan(1.2));
      expect(DifficultyTable.forRank(0).topK, 6);

      expect(DifficultyTable.forRank(18).maxVisits, 150); // 1段
      expect(DifficultyTable.forRank(18).maxTimeMs, 1200);
      expect(DifficultyTable.forRank(18).temperature, 0.30);
      expect(DifficultyTable.forRank(18).topK, 3);

      expect(DifficultyTable.forRank(26).topK, 1); // 9段取最优
      expect(DifficultyTable.forRank(26).temperature, lessThan(0.05));
      expect(DifficultyTable.forRank(26).maxVisits, greaterThanOrEqualTo(2000));
    });

    test('边界夹紧：越界索引安全', () {
      expect(DifficultyTable.forRank(-3).rankIndex, 0);
      expect(DifficultyTable.forRank(100).rankIndex, 26);
    });
  });

  group('DifficultyTable 单调性', () {
    test('27 档全相邻单调：访问/时长升、温度/噪声/topK 降', () {
      var prev = DifficultyTable.forRank(0);
      for (var i = 1; i <= 26; i++) {
        final cur = DifficultyTable.forRank(i);
        expect(DifficultyTable.isMonotonic(prev, cur),
            isTrue,
            reason: 'rank $i 破坏单调性: ${prev.maxVisits}->${cur.maxVisits}, '
                'temp ${prev.temperature}->${cur.temperature}');
        prev = cur;
      }
    });

    test('分段插值落在两端锚点之间（抽查 5/13/20）', () {
      final d5 = DifficultyTable.forRank(5);
      expect(d5.maxVisits, inInclusiveRange(4, 20));
      expect(d5.temperature, inInclusiveRange(0.80, 1.50));
      expect(d5.topK, inInclusiveRange(5, 6));

      final d13 = DifficultyTable.forRank(13);
      expect(d13.maxVisits, inInclusiveRange(20, 60));
      expect(d13.temperature, inInclusiveRange(0.50, 0.80));

      final d20 = DifficultyTable.forRank(20);
      expect(d20.maxVisits, inInclusiveRange(150, 500));
      expect(d20.topK, inInclusiveRange(2, 3));
    });
  });
}
