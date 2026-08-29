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
    test('首档阈值与单调性', () {
      expect(RankSystem.pointsForRank(0), 0);
      expect(RankSystem.pointsForRank(17), 17 * 100);
      expect(RankSystem.pointsForRank(18), 17 * 100 + 200);
      expect(RankSystem.pointsForRank(26), 17 * 100 + 200 + 8 * 150);
      for (var i = 1; i <= 26; i++) {
        expect(
          RankSystem.pointsForRank(i),
          greaterThan(RankSystem.pointsForRank(i - 1)),
        );
      }
    });

    test('步长与升段门槛', () {
      expect(RankSystem.stepForRank(0), 100);
      expect(RankSystem.stepForRank(16), 100);
      expect(RankSystem.stepForRank(17), 200);
      expect(RankSystem.stepForRank(18), 150);
      expect(RankSystem.stepForRank(25), 150);
    });
  });

  group('reconcile 积分升降级', () {
    test('积分位于档位区间内不升降', () {
      final r = RankSystem.reconcile(850, 8);
      expect(r.rank, 8);
      expect(r.points, 850);
    });

    test('达到阈值晋升', () {
      final r = RankSystem.reconcile(900, 8);
      expect(r.rank, 9);
      expect(r.points, 900);
    });

    test('跨多档连升', () {
      final r = RankSystem.reconcile(1150, 8);
      expect(r.rank, 11);
      expect(r.points, 1150);
    });

    test('1级 升 1段 需 200 分', () {
      final r = RankSystem.reconcile(1900, 17);
      expect(r.rank, 18);
      expect(r.points, 1900);
    });

    test('跌破底线降级', () {
      final r = RankSystem.reconcile(999, 10);
      expect(r.rank, 9);
      expect(r.points, 999);
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
