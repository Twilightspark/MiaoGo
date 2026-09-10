import 'package:flutter_test/flutter_test.dart';
import 'package:miaogo/engine/difficulty.dart';

void main() {
  group('DifficultyTable 锚点', () {
    test('锚点档取值符合出厂参考表', () {
      final d0 = DifficultyTable.forRank(0); // 18级
      expect(d0.humanSLProfile, 'rank_18k');
      expect(d0.maxVisits, 30);
      expect(d0.piklLambda, greaterThan(1e6)); // 纯人类策略

      final d18 = DifficultyTable.forRank(18); // 1段
      expect(d18.humanSLProfile, 'rank_1d');
      expect(d18.maxVisits, 120);
      expect(d18.maxTimeMs, 1200);
      expect(d18.rootExploreProbWeightless, greaterThan(0));

      final d26 = DifficultyTable.forRank(26); // 9段
      expect(d26.humanSLProfile, 'rank_9d');
      expect(d26.maxVisits, greaterThanOrEqualTo(700));
      expect(d26.piklLambda, lessThan(0.05));
    });

    test('画像命名：级位 18k~1k、段位 1d~9d', () {
      expect(DifficultyTable.profileForRank(0), 'rank_18k');
      expect(DifficultyTable.profileForRank(8), 'rank_10k');
      expect(DifficultyTable.profileForRank(17), 'rank_1k');
      expect(DifficultyTable.profileForRank(18), 'rank_1d');
      expect(DifficultyTable.profileForRank(26), 'rank_9d');
    });

    test('边界夹紧：越界索引安全', () {
      expect(DifficultyTable.forRank(-3).rankIndex, 0);
      expect(DifficultyTable.forRank(100).rankIndex, 26);
      expect(DifficultyTable.forRank(-3).humanSLProfile, 'rank_18k');
      expect(DifficultyTable.forRank(100).humanSLProfile, 'rank_9d');
    });
  });

  group('DifficultyTable 单调性', () {
    test('27 档全相邻单调：搜索量升、纯人类度降', () {
      var prev = DifficultyTable.forRank(0);
      for (var i = 1; i <= 26; i++) {
        final cur = DifficultyTable.forRank(i);
        expect(DifficultyTable.isMonotonic(prev, cur),
            isTrue,
            reason: 'rank $i 破坏单调性: visits ${prev.maxVisits}->${cur.maxVisits}, '
                'pikl ${prev.piklLambda}->${cur.piklLambda}');
        prev = cur;
      }
    });

    test('分段插值落在两端锚点之间（抽查 5/13/20）', () {
      final d5 = DifficultyTable.forRank(5);
      expect(d5.humanSLProfile, 'rank_13k');
      expect(d5.maxVisits, 30);

      final d13 = DifficultyTable.forRank(13);
      expect(d13.maxVisits, inInclusiveRange(30, 50));

      final d20 = DifficultyTable.forRank(20);
      expect(d20.maxVisits, inInclusiveRange(120, 350));
      expect(d20.piklLambda, inInclusiveRange(0.08, 0.50));
    });
  });
}
