import 'package:flutter_test/flutter_test.dart';
import 'package:miaogo/core/rank.dart';

void main() {
  group('rankName 段位文本', () {
    test('边界与代表档位', () {
      expect(RankSystem.rankName(0), '18级');
      expect(RankSystem.rankName(8), '10级');
      expect(RankSystem.rankName(16), '2级');
      expect(RankSystem.rankName(17), '1级');
      expect(RankSystem.rankName(18), '1段');
      expect(RankSystem.rankName(22), '5段');
      expect(RankSystem.rankName(26), '9段');
    });
  });

  group('pointsForRank 阈值', () {
    test('首档阈值与单调性（级内 10/档，段位区逐档 ×1.3）', () {
      expect(RankSystem.pointsForRank(0), 0);
      expect(RankSystem.pointsForRank(1), 10); // 17级
      expect(RankSystem.pointsForRank(2), 20); // 16级
      expect(RankSystem.pointsForRank(17), 170); // 1级
      expect(RankSystem.pointsForRank(18), 183); // 1段
      expect(RankSystem.pointsForRank(19), 199); // 2段
      expect(RankSystem.pointsForRank(26), 582); // 9段
      for (var i = 1; i <= 26; i++) {
        expect(
          RankSystem.pointsForRank(i),
          greaterThan(RankSystem.pointsForRank(i - 1)),
        );
      }
    });

    test('步长：级内 10，段位区档差递增', () {
      expect(RankSystem.stepForRank(0), 10);
      expect(RankSystem.stepForRank(16), 10);
      expect(RankSystem.stepForRank(17), 13); // 1级->1段 = 10×1.3
      expect(RankSystem.stepForRank(18), 16);
      expect(RankSystem.stepForRank(19), 21);
      expect(RankSystem.stepForRank(25), 106); // 8段->9段 = 10×1.3^9
    });
  });

  group('reconcile 积分升降级', () {
    test('积分位于档位区间内不升降', () {
      final r = RankSystem.reconcile(85, 8);
      expect(r.rank, 8);
      expect(r.points, 85);
    });

    test('达到阈值晋升', () {
      final r = RankSystem.reconcile(90, 8);
      expect(r.rank, 9);
      expect(r.points, 90);
    });

    test('跨多档连升（级内每档 10）', () {
      final r = RankSystem.reconcile(150, 8);
      expect(r.rank, 15);
      expect(r.points, 150);
    });

    test('1级 升 1段 需 183 分', () {
      final r = RankSystem.reconcile(183, 17);
      expect(r.rank, 18);
      expect(r.points, 183);
    });

    test('跌破底线降级（负局扣分可触发）', () {
      final r = RankSystem.reconcile(95, 10);
      expect(r.rank, 9);
      expect(r.points, 95);
    });

    test('降级不破 18级 底线', () {
      final r = RankSystem.reconcile(0, 5);
      expect(r.rank, 0);
      expect(r.points, 0);
    });

    test('9段 封顶保留溢出积分', () {
      final r = RankSystem.reconcile(100000, 26);
      expect(r.rank, 26);
      expect(r.points, 100000);
    });

    test('负数积分归零', () {
      final r = RankSystem.reconcile(-10, 3);
      expect(r.rank, 0);
      expect(r.points, 0);
    });
  });
}
