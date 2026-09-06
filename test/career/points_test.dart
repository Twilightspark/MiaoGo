import 'package:flutter_test/flutter_test.dart';
import 'package:miaogo/game/career.dart';

void main() {
  group('CareerPoints 基础分（同档）', () {
    test('W=ceil(档差/3)，L=floor(W/2)', () {
      expect(CareerPoints.baseWin(0), 4); // 级内档差 10
      expect(CareerPoints.baseLoss(0), 2);
      expect(CareerPoints.baseWin(17), 5); // 1级->1段 档差 13
      expect(CareerPoints.baseLoss(17), 2);
      expect(CareerPoints.baseWin(18), 6); // 1段->2段 档差 16
      expect(CareerPoints.baseLoss(18), 3);
      expect(CareerPoints.baseWin(26), 36); // 9段 兜底档差 106
      expect(CareerPoints.baseLoss(26), 18);
    });
  });

  group('quickDelta 档差加权', () {
    int win(int p, int o) =>
        CareerPoints.quickDelta(won: true, playerRank: p, opponentRank: o);
    int loss(int p, int o) =>
        CareerPoints.quickDelta(won: false, playerRank: p, opponentRank: o);

    test('同档：胜 +W / 负 −L', () {
      expect(win(0, 0), 4);
      expect(loss(0, 0), -2);
    });

    test('对手越强胜分越多（d>0 加成）', () {
      expect(win(0, 1), 4); // 4×1.2=4.8→4
      expect(win(0, 2), 5); // 4×1.4=5.6→5
    });

    test('对手越弱胜分越少，低自己 5 档不得分', () {
      expect(win(1, 0), 3); // 4×0.8=3.2→3
      expect(win(0, 0), 4);
      // player 0 vs 对手低 5 档需对手 rank 为负，等价用例用 player 高一方。
      expect(win(5, 0), 0); // d=-5 → 不得分
    });

    test('输给强手扣得少，高自己 5 档不扣分', () {
      expect(loss(0, 1), -1); // -2×0.8=-1.6→-1
      expect(loss(5, 10), 0); // d=5 → 不扣分
      expect(loss(0, 5), 0);
    });

    test('输给弱手扣得多（负分同档差加权）', () {
      expect(loss(0, 0), -2);
      expect(loss(5, 0), -4); // d=-5：-(2×clamp(2))=-(4)
    });

    test('加权封顶：5 档以上不再增减', () {
      expect(win(0, 10), 8); // 封顶 ×2
      expect(loss(0, 10), 0); // 已触发不扣分
    });
  });

  group('tournamentCap / tournamentReward（大赛名次奖励）', () {
    test('封顶 = 最强对手「上一档」档差', () {
      expect(CareerPoints.tournamentCap(0), 10);
      expect(CareerPoints.tournamentCap(16), 10);
      expect(CareerPoints.tournamentCap(17), 13);
      expect(CareerPoints.tournamentCap(25), 106);
      expect(CareerPoints.tournamentCap(26), 106); // 9段 兜底用上一档差
    });

    test('冠军 X / 亚军 X/2 / 四强 X/4 / 八强 0', () {
      int rw(int placement) => CareerPoints.tournamentReward(
            placement: placement,
            topOpponentRank: 0,
          );
      expect(rw(1), 10);
      expect(rw(2), 5);
      expect(rw(3), 2); // floor(10/4)
      expect(rw(5), 0);
      expect(rw(0), 0); // 退赛
    });

    test('按最强对手档位取整（X=13）', () {
      int rw(int placement) => CareerPoints.tournamentReward(
            placement: placement,
            topOpponentRank: 17,
          );
      expect(rw(1), 13);
      expect(rw(2), 6); // floor(13/2)
      expect(rw(3), 3); // floor(13/4)
    });
  });
}
